[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SourceIso,
    [Parameter(Mandatory)] [string] $OutputIso,
    [Parameter(Mandatory)] [string] $SshPublicKey,
    [string] $WorkingDirectory = (Join-Path $env:TEMP 'tlb-rhel-aap-iso'),
    [Parameter(Mandatory)] [string] $HostName,
    [Parameter(Mandatory)] [string] $Fqdn,
    [Parameter(Mandatory)] [string] $IPv4Address,
    [Parameter(Mandatory)] [string] $Netmask,
    [Parameter(Mandatory)] [string] $Gateway,
    [Parameter(Mandatory)] [string] $Dns,
    [string] $TimeZone = 'America/New_York',
    [string] $BootVolumeLabel = 'TLB-AAP-BOOT'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Path([string] $Path, [string] $Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not found: $Path"
    }
}

Assert-Path $SourceIso 'RHEL ISO'
Assert-Path $SshPublicKey 'SSH public key'
$oscdimg = (Get-Command oscdimg.exe -ErrorAction Stop).Source

$key = (Get-Content -LiteralPath $SshPublicKey -Raw).Trim()
if ($key -notmatch '^(ssh-(rsa|ed25519)|ecdsa-sha2-)') {
    throw 'The supplied file does not contain an OpenSSH public key.'
}

New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
$stage = Join-Path $WorkingDirectory 'iso-root'
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage | Out-Null

$disk = $null
try {
    $disk = Mount-DiskImage -ImagePath $SourceIso -PassThru
    $volume = $disk | Get-Volume
    if (-not $volume.DriveLetter) { throw 'The mounted ISO has no drive letter.' }
    $sourceRoot = "$($volume.DriveLetter):\"
    $volumeLabel = $volume.FileSystemLabel

    foreach ($directory in @('EFI', 'boot')) {
        & robocopy (Join-Path $sourceRoot $directory) (Join-Path $stage $directory) /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /NFL /NDL /NP
        if ($LASTEXITCODE -gt 7) { throw "ISO boot-file copy failed with robocopy exit code $LASTEXITCODE." }
    }
    New-Item -ItemType Directory -Path (Join-Path $stage 'images') -Force | Out-Null
    foreach ($file in @('efiboot.img', 'eltorito.img')) {
        Copy-Item -LiteralPath (Join-Path $sourceRoot "images\$file") -Destination (Join-Path $stage "images\$file") -Force
    }
    & robocopy (Join-Path $sourceRoot 'images\pxeboot') (Join-Path $stage 'images\pxeboot') /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /NFL /NDL /NP
    if ($LASTEXITCODE -gt 7) { throw "ISO kernel/initramfs copy failed with robocopy exit code $LASTEXITCODE." }
    foreach ($file in @('.discinfo', '.treeinfo', 'media.repo')) {
        Copy-Item -LiteralPath (Join-Path $sourceRoot $file) -Destination (Join-Path $stage $file) -Force
    }
}
finally {
    if ($disk) { Dismount-DiskImage -ImagePath $SourceIso -ErrorAction SilentlyContinue }
}

& attrib.exe -R (Join-Path $stage '*') /S /D

# Get-Volume can report a shortened ISO/UDF label. RHEL's own boot command is
# authoritative because Anaconda uses this value to locate its stage-2 image.
$stage2Line = Get-ChildItem -LiteralPath $stage -Recurse -File -Filter grub.cfg |
    Select-String -Pattern 'inst\.stage2=hd:LABEL=([^\s]+)' |
    Select-Object -First 1
if (-not $stage2Line) { throw 'Could not determine the RHEL stage-2 volume label from grub.cfg.' }
$sourceVolumeLabel = $stage2Line.Matches[0].Groups[1].Value

$kickstart = @"
text
lang en_US.UTF-8
keyboard --xlayouts='us'
timezone $TimeZone --utc
network --bootproto=static --device=link --ip=$IPv4Address --netmask=$Netmask --gateway=$Gateway --nameserver=$Dns --hostname=$Fqdn --activate
rootpw --lock
user --name=labadmin --groups=wheel --lock
sshkey --username=root "$key"
sshkey --username=labadmin "$key"
firewall --enabled --service=ssh
selinux --enforcing
services --enabled=sshd,chronyd
firstboot --disable
zerombr
clearpart --all --initlabel
part /boot/efi --fstype=efi --size=600
part /boot --fstype=xfs --size=1024
part pv.01 --grow --size=1
volgroup rhel pv.01
logvol swap --fstype=swap --name=swap --vgname=rhel --size=4096
logvol / --fstype=xfs --name=root --vgname=rhel --grow --size=50000
reboot

%packages
@^minimal-environment
chrony
curl
openssh-server
open-vm-tools
sudo
tar
%end

%post --log=/root/ks-post.log
hostnamectl set-hostname $HostName
printf '$IPv4Address $Fqdn $HostName\n' >> /etc/hosts
printf 'labadmin ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/labadmin
chmod 0440 /etc/sudoers.d/labadmin
mkdir -p /mnt/rhel
printf 'LABEL=$sourceVolumeLabel /mnt/rhel iso9660 ro,nofail,x-systemd.automount 0 0\n' >> /etc/fstab
cat > /etc/yum.repos.d/rhel-install-media.repo <<'REPO'
[rhel-baseos-media]
name=RHEL BaseOS installation media
baseurl=file:///mnt/rhel/BaseOS
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhel-appstream-media]
name=RHEL AppStream installation media
baseurl=file:///mnt/rhel/AppStream
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
REPO
restorecon -RFv /root/.ssh /home/labadmin/.ssh /etc/sudoers.d/labadmin
%end
"@

Set-Content -LiteralPath (Join-Path $stage 'ks.cfg') -Value $kickstart -Encoding ascii

$bootConfigs = Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object {
    $_.Name -in @('grub.cfg', 'isolinux.cfg')
}
foreach ($config in $bootConfigs) {
    $text = Get-Content -LiteralPath $config.FullName -Raw
    $text = $text.Replace($sourceVolumeLabel, $BootVolumeLabel)
    $text = $text -replace '(?m)^\s*set default=.*$', 'set default="0"'
    $text = $text -replace '(?m)^default\s+\S+\s*$', 'default 0'
    $text = $text -replace '(?m)^\s*set timeout=.*$', 'set timeout=1'
    $text = $text -replace '(?m)^timeout\s+\d+\s*$', 'timeout 10'
    if ($text -notmatch 'inst\.ks=hd:LABEL=') {
        $bootArguments = "inst.stage2=hd:LABEL=$sourceVolumeLabel inst.repo=hd:LABEL=$sourceVolumeLabel inst.ks=hd:LABEL=$BootVolumeLabel`:/ks.cfg console=tty0 console=ttyS0,115200n8"
        $text = $text -replace '(?m)inst\.stage2=hd:LABEL=\S+', $bootArguments
        $text = $text -replace '(?m)^(\s*append\s+.*)$', "`$1 $bootArguments"
    }
    Set-Content -LiteralPath $config.FullName -Value $text -Encoding ascii
}

$biosBoot = Join-Path $stage 'isolinux\isolinux.bin'
if (-not (Test-Path -LiteralPath $biosBoot -PathType Leaf)) {
    $biosBoot = Join-Path $stage 'images\eltorito.img'
}
$efiBoot = Join-Path $stage 'images\efiboot.img'
Assert-Path $biosBoot 'BIOS boot image'
Assert-Path $efiBoot 'UEFI boot image'

$bootOrder = Join-Path $WorkingDirectory 'boot-order.txt'
@(
    'images\efiboot.img'
    'images\eltorito.img'
    'EFI\BOOT\BOOTX64.EFI'
    'EFI\BOOT\grub.cfg'
    'images\pxeboot\vmlinuz'
    'images\pxeboot\initrd.img'
    'ks.cfg'
    '.treeinfo'
    '.discinfo'
    'media.repo'
) | Set-Content -LiteralPath $bootOrder -Encoding ascii

$outputParent = Split-Path -Parent $OutputIso
New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
if (Test-Path -LiteralPath $OutputIso) { Remove-Item -LiteralPath $OutputIso -Force }

& $oscdimg "-bootdata:2#p0,e,b$biosBoot#pEF,e,b$efiBoot" -m -o -u1 -udfver102 "-yo$bootOrder" "-l$BootVolumeLabel" $stage $OutputIso
if ($LASTEXITCODE -ne 0) { throw "oscdimg failed with exit code $LASTEXITCODE." }

$hash = Get-FileHash -LiteralPath $OutputIso -Algorithm SHA256
[pscustomobject]@{
    OutputIso = $OutputIso
    Bytes = (Get-Item -LiteralPath $OutputIso).Length
    SHA256 = $hash.Hash
    BootVolumeLabel = $BootVolumeLabel
    SourceVolumeLabel = $sourceVolumeLabel
    Kickstart = (Join-Path $stage 'ks.cfg')
}
