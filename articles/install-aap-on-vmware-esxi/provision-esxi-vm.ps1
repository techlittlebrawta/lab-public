[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $EsxiKey,
    [Parameter(Mandatory)] [string] $EsxiKnownHosts,
    [Parameter(Mandatory)] [string] $GuestKey,
    [Parameter(Mandatory)] [string] $GuestKnownHosts,
    [Parameter(Mandatory)] [string] $InstallerIso,
    [Parameter(Mandatory)] [string] $SourceIso,
    [string] $EsxiHost = '192.168.1.253',
    [string] $Datastore = 'datastore1',
    [string] $VmName = 'LAB-AAP-CONT-01',
    [string] $PortGroup = 'LAB-AAP-CONT-01',
    [string] $GuestAddress = '192.168.1.251',
    [int] $Cpu = 4,
    [int] $MemoryMiB = 16384,
    [int] $DiskGiB = 100
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($path in @($EsxiKey, $EsxiKnownHosts, $GuestKey, $InstallerIso, $SourceIso)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" }
}
New-Item -ItemType Directory -Path (Split-Path -Parent $GuestKnownHosts) -Force | Out-Null
if (-not (Test-Path -LiteralPath $GuestKnownHosts)) { New-Item -ItemType File -Path $GuestKnownHosts | Out-Null }

$sshBase = @(
    '-i', $EsxiKey,
    '-o', 'IdentitiesOnly=yes',
    '-o', 'HostKeyAlgorithms=ecdsa-sha2-nistp256',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$EsxiKnownHosts",
    "root@$EsxiHost"
)

function Invoke-Esxi([string] $Command) {
    & ssh @sshBase $Command
    if ($LASTEXITCODE -ne 0) { throw "ESXi command failed with exit code $LASTEXITCODE." }
}

Write-Host '=== ESXi discovery ==='
Invoke-Esxi 'hostname; esxcli system version get; esxcli storage filesystem list; esxcli network vswitch standard portgroup list; vim-cmd vmsvc/getallvms'

$vmRows = & ssh @sshBase 'vim-cmd vmsvc/getallvms'
$existing = @($vmRows | Where-Object { $_ -match "^\s*(\d+)\s+$([Regex]::Escape($VmName))\s+" } | ForEach-Object { $Matches[1] }) -join ''
if ($existing) { throw "$VmName already exists as VM ID $existing. This script will not replace it." }

$portRows = & ssh @sshBase 'esxcli network vswitch standard portgroup list'
$portExists = @($portRows | Where-Object { $_ -match "^$([Regex]::Escape($PortGroup))\s+" }) -join ''
if (-not $portExists) {
    Write-Host "Creating isolated lab port group $PortGroup on vSwitch0..."
    Invoke-Esxi "esxcli network vswitch standard portgroup add --portgroup-name='$PortGroup' --vswitch-name=vSwitch0"
    Invoke-Esxi "esxcli network vswitch standard portgroup set --portgroup-name='$PortGroup' --vlan-id=0"
}

if (Test-Connection -TargetName $GuestAddress -Count 2 -Quiet -ErrorAction SilentlyContinue) {
    throw "$GuestAddress is already responding. Resolve the address conflict before provisioning."
}

$remoteIso = "/vmfs/volumes/$Datastore/iso/$(Split-Path -Leaf $InstallerIso)"
$localHash = (Get-FileHash -LiteralPath $InstallerIso -Algorithm SHA256).Hash.ToLowerInvariant()
$remoteHashLine = & ssh @sshBase "test -f '$remoteIso' && sha256sum '$remoteIso' || true"
$remoteHash = (@($remoteHashLine) -join ' ').Trim().Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Select-Object -First 1
if ($remoteHash -ne $localHash) {
    Write-Host '=== Upload the verified unattended RHEL ISO ==='
    & scp -i $EsxiKey -o IdentitiesOnly=yes -o HostKeyAlgorithms=ecdsa-sha2-nistp256 -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$EsxiKnownHosts" $InstallerIso "root@${EsxiHost}:$remoteIso"
    if ($LASTEXITCODE -ne 0) { throw "ISO upload failed with exit code $LASTEXITCODE." }
    $remoteHashLine = & ssh @sshBase "sha256sum '$remoteIso'"
    $remoteHash = ((@($remoteHashLine) -join ' ').Trim().Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Select-Object -First 1)
    if ($remoteHash -ne $localHash) { throw 'The uploaded ISO hash does not match the local ISO.' }
}
Write-Host "[PASS] RHEL installer SHA-256: $localHash"

$remoteSourceIso = "/vmfs/volumes/$Datastore/iso/$(Split-Path -Leaf $SourceIso)"
$localSourceHash = (Get-FileHash -LiteralPath $SourceIso -Algorithm SHA256).Hash.ToLowerInvariant()
$remoteSourceHashLine = & ssh @sshBase "test -f '$remoteSourceIso' && sha256sum '$remoteSourceIso' || true"
$remoteSourceHash = (@($remoteSourceHashLine) -join ' ').Trim().Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Select-Object -First 1
if ($remoteSourceHash -ne $localSourceHash) {
    Write-Host '=== Upload the verified original RHEL DVD ==='
    & scp -i $EsxiKey -o IdentitiesOnly=yes -o HostKeyAlgorithms=ecdsa-sha2-nistp256 -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$EsxiKnownHosts" $SourceIso "root@${EsxiHost}:$remoteSourceIso"
    if ($LASTEXITCODE -ne 0) { throw "Original RHEL ISO upload failed with exit code $LASTEXITCODE." }
    $remoteSourceHashLine = & ssh @sshBase "sha256sum '$remoteSourceIso'"
    $remoteSourceHash = ((@($remoteSourceHashLine) -join ' ').Trim().Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Select-Object -First 1)
    if ($remoteSourceHash -ne $localSourceHash) { throw 'The uploaded original RHEL ISO hash does not match the local ISO.' }
}
Write-Host "[PASS] Original RHEL DVD SHA-256: $localSourceHash"

Write-Host '=== Create the AAP virtual machine ==='
$vmDir = "/vmfs/volumes/$Datastore/$VmName"
Invoke-Esxi "mkdir -p '$vmDir'"
$diskState = (& ssh @sshBase "test -f '$vmDir/$VmName.vmdk' && echo present || echo absent") -join ''
if ($diskState.Trim() -eq 'absent') {
    Invoke-Esxi "vmkfstools -c ${DiskGiB}G -d thin '$vmDir/$VmName.vmdk'"
}
else {
    Write-Host '[RESUME] Reusing the unregistered thin disk created by the prior recorded attempt.'
}

$vmx = @"
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
displayName = "$VmName"
annotation = "Tech Little Brawta AAP 2.7 recorded validation build"
guestOS = "rhel9-64"
  firmware = "efi"
  svga.present = "FALSE"
  usb.present = "FALSE"
  pciBridge0.present = "TRUE"
  pciBridge4.present = "TRUE"
  pciBridge4.virtualDev = "pcieRootPort"
  pciBridge4.functions = "8"
  pciBridge5.present = "TRUE"
  pciBridge5.virtualDev = "pcieRootPort"
  pciBridge5.functions = "8"
  pciBridge6.present = "TRUE"
  pciBridge6.virtualDev = "pcieRootPort"
  pciBridge6.functions = "8"
  pciBridge7.present = "TRUE"
  pciBridge7.virtualDev = "pcieRootPort"
  pciBridge7.functions = "8"
  numvcpus = "$Cpu"
memSize = "$MemoryMiB"
mem.hotadd = "FALSE"
vcpu.hotadd = "FALSE"
scsi0.present = "TRUE"
scsi0.virtualDev = "pvscsi"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "$VmName.vmdk"
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.deviceType = "cdrom-image"
sata0:0.fileName = "$remoteIso"
sata0:0.startConnected = "TRUE"
sata0:1.present = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "$remoteSourceIso"
sata0:1.startConnected = "TRUE"
ethernet0.present = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.networkName = "$PortGroup"
ethernet0.addressType = "generated"
ethernet0.startConnected = "TRUE"
serial0.present = "TRUE"
serial0.fileType = "file"
serial0.fileName = "serial.log"
serial0.yieldOnMsrRead = "TRUE"
# RHEL chronyd is authoritative. Do not let an unsynchronized ESXi host
# periodically overwrite the guest clock.
tools.syncTime = "FALSE"
"@
$localVmx = Join-Path (Split-Path -Parent $GuestKnownHosts) "$VmName.generated.vmx"
[IO.File]::WriteAllText($localVmx, $vmx.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
& scp -i $EsxiKey -o IdentitiesOnly=yes -o HostKeyAlgorithms=ecdsa-sha2-nistp256 -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$EsxiKnownHosts" $localVmx "root@${EsxiHost}:$vmDir/$VmName.vmx"
if ($LASTEXITCODE -ne 0) { throw "VMX upload failed with exit code $LASTEXITCODE." }
$vmId = (& ssh @sshBase "vim-cmd solo/registervm '$vmDir/$VmName.vmx'").Trim()
if ($LASTEXITCODE -ne 0 -or $vmId -notmatch '^\d+$') { throw "VM registration failed: $vmId" }

Invoke-Esxi "vim-cmd vmsvc/power.on $vmId"
Invoke-Esxi "vim-cmd vmsvc/get.summary $vmId | grep -E 'name =|guestFullName|memorySizeMB|numCpu|powerState|vmPathName'"
Invoke-Esxi "grep -E 'displayName|numvcpus|memSize|networkName|fileName|virtualDev|firmware' '$vmDir/$VmName.vmx'"

Write-Host '=== Live RHEL installation ==='
$deadline = (Get-Date).AddMinutes(45)
$lastSerialHash = ''
while ((Get-Date) -lt $deadline) {
    $probe = & ssh -i $GuestKey -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$GuestKnownHosts" -o ConnectTimeout=5 "root@$GuestAddress" 'hostnamectl --static; cat /etc/redhat-release' 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host $probe
        Write-Host '[PASS] RHEL reached key-only SSH.'
        break
    }

    $serial = & ssh @sshBase "tail -n 18 '$vmDir/serial.log' 2>/dev/null || true"
    $serialText = ($serial -join "`n")
    $serialHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($serialText)))
    if ($serialText -and $serialHash -ne $lastSerialHash) {
        Write-Host $serialText
        $lastSerialHash = $serialHash
    }
    Start-Sleep -Seconds 20
}
if ((Get-Date) -ge $deadline) { throw 'RHEL did not reach SSH within 45 minutes.' }

Write-Host '=== Installed VM proof ==='
& ssh -i $GuestKey -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$GuestKnownHosts" "root@$GuestAddress" 'hostnamectl; cat /etc/redhat-release; ip -br address; ip route; free -h; df -h /; lscpu | grep -E "^CPU\(s\):|Model name"'
if ($LASTEXITCODE -ne 0) { throw 'Installed guest validation failed.' }

Write-Host "COMPLETE: $VmName is installed and reachable at $GuestAddress."
