# Install Red Hat Ansible Automation Platform on VMware ESXi

This is the public technical companion to the Tech Little Brawta walkthrough, **How to Install Red Hat Ansible Automation Platform on VMware ESXi**.

It contains a one-command installer and a redacted validation command for the AAP 2.7 containerized growth topology. It does not contain Red Hat installation media, subscription credentials, lab passwords, private keys, or tokens.

`build-rhel-kickstart-iso.ps1` is the matching optional ESXi lab helper. It creates a small unattended boot ISO from an owner-supplied RHEL DVD and SSH public key. The VM boots from that helper while the untouched Red Hat DVD remains attached as the trusted package source. Both private ISO files stay outside Git and are never committed.

`provision-esxi-vm.ps1` verifies both ISO hashes, creates the VM, attaches the unattended boot ISO and original RHEL DVD, starts the build, follows the serial console, and waits for key-only SSH. Its safety checks refuse to replace an already registered VM or use an IP address that is already responding.

## Tested target

- VMware ESXi 8.0 Update 3
- Red Hat Enterprise Linux 10.2 x86_64
- Red Hat Ansible Automation Platform 2.7-9 containerized setup bundle
- Growth topology on one VM; the exact lab hardware and network identifiers are retained privately

The observed host, installer, Red Hat registration, compliant AAP subscription, authenticated API, browser login, and reboot results are in [VALIDATION.md](VALIDATION.md).

## Requirements

1. A supported, fully entitled RHEL 9.6+ or RHEL 10.x x86_64 server.
2. For Red Hat's tested AAP 2.7 container growth topology: 4 vCPU, 16 GB RAM minimum (20 GB recommended), 80 GB total available disk, 3,000 IOPS, working DNS, and a resolvable FQDN. Bundled installs that seed hub collections require 32 GB RAM when `hub_seed_collections=true`.
3. Enabled RHEL BaseOS and AppStream repositories.
4. The AAP 2.7 **containerized setup bundle** copied to the server.
5. Root or sudo access.

The bundled installer carries the AAP container images, but RHEL still needs enabled package repositories for host dependencies.

## Optional unattended RHEL and ESXi build

Create the boot helper from the original Red Hat DVD:

```powershell
.\build-rhel-kickstart-iso.ps1 `
  -SourceIso C:\path\to\rhel-10.2-x86_64-dvd.iso `
  -OutputIso C:\private\rhel-10.2-aap-boot.iso `
  -SshPublicKey C:\path\to\lab-key.pub `
  -HostName aap-growth `
  -Fqdn aap-growth.example.test `
  -IPv4Address 192.0.2.50 `
  -Netmask 255.255.255.0 `
  -Gateway 192.0.2.1 `
  -Dns 192.0.2.53
```

Then provision the VM with both files:

```powershell
.\provision-esxi-vm.ps1 `
  -EsxiKey C:\private\esxi-key `
  -EsxiKnownHosts C:\private\esxi-known-hosts `
  -GuestKey C:\private\lab-key `
  -GuestKnownHosts C:\private\guest-known-hosts `
  -InstallerIso C:\private\rhel-10.2-aap-boot.iso `
  -SourceIso C:\path\to\rhel-10.2-x86_64-dvd.iso `
  -EsxiHost esxi.example.test `
  -Datastore datastore-name `
  -VmName aap-growth `
  -PortGroup server-network `
  -GuestAddress 192.0.2.50
```

The hostnames and addresses above are documentation examples and must be replaced. The helper does not modify the vendor DVD. This avoids invalidating Red Hat's installation-media layout while still providing a no-touch Kickstart boot. The helper's VMware choices are examples, not AAP requirements.

## One-command installation

Put `install-aap.sh` and the setup bundle in the same directory, then run:

```bash
chmod +x install-aap.sh
sudo ./install-aap.sh
```

The script detects the newest compatible bundle, validates the host, updates RHEL, installs `ansible-core`, creates the dedicated `aap` installation user, generates strong credentials, writes the growth-topology inventory, runs Red Hat's official installer playbook, and validates the HTTPS listener and rootless containers.

No password or inventory editing is required during the normal path.

## Optional overrides

Advanced users can set these without editing the script:

```bash
sudo AAP_BUNDLE=/path/to/bundle.tar.gz \
  AAP_HOSTNAME=aap.example.org \
  AAP_INSTALL_DIR=/home/aap/aap-install \
  ./install-aap.sh
```

`AAP_ADMIN_USER` defaults to `admin`. Passwords are generated unless an existing healthy deployment is detected.

For a screen-recorded run, `AAP_REDACT_OUTPUT=1` replaces the final on-screen password with the protected credential-file path. The real password is still generated and written to the root-only file. Normal runs print it once at completion.

If the official Red Hat playbook completed but a final wrapper validation was interrupted, resume only the health and credential-file stage without reinstalling AAP:

```bash
sudo AAP_RESUME_VALIDATION=1 AAP_REDACT_OUTPUT=1 ./install-aap.sh
```

Resume mode reuses the protected generated inventory, verifies HTTPS and the running containers, and creates the root-only credential record. It does not rerun the installer playbook.

## What the script changes

- Updates installed RHEL packages.
- Installs `ansible-core`, `curl`, `firewalld`, `openssl`, and `tar`.
- Creates the unprivileged `aap` account and a dedicated passwordless sudo rule required by the containerized installer.
- Enables firewalld and permits SSH, HTTP, and HTTPS.
- Extracts the bundle under `/home/aap/aap-install` by default.
- Backs up the bundle's original `inventory-growth` before writing the generated inventory.
- Runs `ansible.containerized_installer.install` as the `aap` user.
- Stores the generated administrator login in `/root/aap-install-credentials.txt` with mode `0600`.
- Stores installer logs in `/var/log/aap-installer` with root-only permissions.

## Access AAP

The final success block prints the detected HTTPS URL and generated administrator login. Retrieve the server-side copy as root:

```bash
sudo cat /root/aap-install-credentials.txt
```

Do not copy that file into a source repository, ticket, screenshot, or video.

## Redacted health and login validation

Run the companion validator as root after installation or reboot:

```bash
sudo ./validate-aap.sh
```

It prints the boot ID, operating system, network, SELinux, firewalld, NTP, running-container count, container states, failed user-service check, and authenticated gateway API status. It reads the protected administrator credential only for the API request and never prints the password.

## Safe second run

If the root-only credential file exists and the gateway is responding, a normal second run reports the existing installation and exits successfully. To reconcile the same installed release without uninstalling data:

```bash
sudo AAP_FORCE_RECONCILE=1 ./install-aap.sh
```

The script never invokes the uninstall playbook.

## Troubleshooting

- **Bundle not detected:** place the `...containerized-setup-bundle...tar.gz` beside the script or set `AAP_BUNDLE`.
- **FQDN failure:** make the host's FQDN resolvable in DNS or `/etc/hosts`; do not use an unresolvable short name in the installer inventory.
- **Repository failure:** register RHEL and enable BaseOS plus AppStream.
- **Resource failure:** compare the host with the current Red Hat requirements for the selected topology. The script defaults to a conservative 4 vCPU, 16 GB RAM, and 80 GiB available on the installation filesystem for this growth topology.
- **Installer failure:** read the stage printed by the script and the protected log under `/var/log/aap-installer`.
- **HTTPS unavailable:** inspect the `aap` user's containers and user services with `sudo -iu aap podman ps` and `sudo -iu aap systemctl --user --failed`.

## Official references

- [Install containerized Ansible Automation Platform 2.7](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/install-con_aap_containerized_installation_intro)
- [AAP 2.7 system requirements](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/ref_system_requirements)
- [AAP 2.7 container growth topology](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/plan-ref_cont_a_env_a)
- [Prepare the RHEL host](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/install-proc_preparing_the_rhel_host_for_containerized_installation)
- [Create the installation user](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/install-proc_preparing_the_managed_nodes_for_containerized_installation)
- [Configure the inventory](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/install-ref_configuring_inventory_file)
- [Run the containerized installer](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/install-proc_installing_containerized_aap)
