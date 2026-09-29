# Validation record

## Current state

**HOST, INSTALLER, AUTHENTICATED API, AND REBOOT VALIDATION PASSED ON 2026-09-29.**

Authenticated browser UI validation remains open because Chrome correctly rejects the lab's private installer CA. The warning has not been bypassed. This record will not call the full publishing package complete until the CA is explicitly trusted and the real UI login has been captured.

## Tested environment

- ESXi: 8.0 Update 3, build 24022510
- VM: `LAB-AAP-CONT-01`, 4 vCPU, 16 GB allocated RAM, 100 GB thin disk
- Guest: Red Hat Enterprise Linux 10.2, kernel `6.12.0-211.7.3.el10_2.x86_64`
- Address: `192.168.1.251/24`, gateway and DNS `192.168.1.1`
- AAP: 2.7-9 containerized setup bundle
- Topology: gateway, controller, private automation hub, EDA, automation metrics, PostgreSQL, Redis, and receptor on one host

The host was updated against the matching RHEL 10.2 BaseOS and AppStream DVD repositories. It was not attached to Red Hat CDN during this build, so this record does not claim content newer than the verified 10.2 media.

## Observed installation result

The official Red Hat playbook completed with:

```text
LAB-AAP-CONT-01.lab.local  : ok=731 changed=268 unreachable=0 failed=0
localhost                  : ok=41  changed=0   unreachable=0 failed=0
```

The companion wrapper then passed its corrected resume-validation path and printed the redacted completion block. The generated credential file was present as `root:root` with mode `0600`.

## Pre-reboot checks

- RHEL release and kernel: PASS
- 4 CPUs and 15,730 MiB usable memory: PASS
- Root filesystem: 95 GB total, 72 GB free after installation: PASS
- Static address and default route: PASS
- Gateway ping: 3 of 3 replies: PASS
- External DNS lookup: PASS
- SELinux: `Enforcing`: PASS
- firewalld: `active`: PASS
- HTTPS listener: PASS
- Unauthenticated gateway status endpoint: HTTP 401, as expected: PASS
- Authenticated `/api/gateway/v1/me/`: HTTP 200: PASS
- AAP containers: 24 running: PASS
- NTP after correction: synchronized, stratum 2, leap status normal: PASS

The initial VM configuration allowed VMware Tools host-time injection. The ESXi host's own NTP state was unsynchronized, so it repeatedly moved the guest clock about 95 seconds ahead after chronyd corrected it. Time synchronization with the ESXi host was disabled for `LAB-AAP-CONT-01`, chronyd corrected the guest, and a later check remained synchronized with a 0.0047-second offset. The public provisioning helper now creates the VM with `tools.syncTime = "FALSE"` so RHEL chronyd remains authoritative.

## Reboot-persistence proof

- Pre-reboot boot ID: `8f53e06e-bdb5-4798-b2fe-256f0cce8e52`
- Post-reboot boot ID: `4b71651f-f99f-4ec1-a165-a12c0ce603c1`
- firewalld and chronyd returned active: PASS
- The `aap` user systemd manager returned `running`: PASS
- All 24 AAP containers returned to `Up`: PASS
- Authenticated `/api/gateway/v1/me/` after reboot: HTTP 200: PASS

## Evidence boundary

No password, private SSH key, Red Hat media, entitlement data, or installer bundle is stored here. The retained private build log and continuous screen recording are held in the owner's local inspection folder. Public screenshots and the edited video must remain sanitized before publication.
