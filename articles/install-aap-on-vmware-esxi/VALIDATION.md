# Validation record

## Current state

**HOST, INSTALLER, RED HAT REGISTRATION, AAP SUBSCRIPTION, AUTHENTICATED API, REBOOT, AND TRUSTED-BROWSER LOGIN VALIDATION PASSED. FINAL LIVE ACCEPTANCE WAS REPEATED ON 2026-10-02. PRIVATE INFRASTRUCTURE IDENTIFIERS ARE RETAINED OUTSIDE THIS PUBLIC COMPANION.**

The AAP private installer CA was fingerprint-verified before trust was configured. The browser then loaded the real sign-in page without bypassing a warning and accepted the administrator credentials with the password masked. After the owner registered the host, the AAP subscription API and visible Subscription Settings page independently reported a compliant enterprise subscription. The certificate fingerprint is intentionally omitted.

## Tested environment

- ESXi: 8.0 Update 3
- VM: one RHEL guest sized for the tested AAP 2.7 container growth topology
- Guest: Red Hat Enterprise Linux 10.2 x86_64
- Network: private hostnames, addresses, routes, and interface identifiers omitted
- AAP: 2.7-9 containerized setup bundle
- Topology: gateway, controller, private automation hub, EDA, automation metrics, PostgreSQL, Redis, and receptor on one host

The installation originally used the matching RHEL 10.2 BaseOS and AppStream DVD repositories. The host was subsequently registered to Red Hat CDN and the RHEL 10 BaseOS and AppStream repositories were enabled before final acceptance.

## Observed installation result

The official Red Hat playbook completed with:

```text
[private AAP FQDN] : ok=731 changed=268 unreachable=0 failed=0
localhost          : ok=41  changed=0   unreachable=0 failed=0
```

The companion wrapper then passed its corrected resume-validation path and printed the redacted completion block. The generated credential file was present as `root:root` with mode `0600`.

## Pre-reboot checks

- RHEL release and kernel: PASS
- 4 CPUs and 15,730 MiB usable memory: PASS
- Storage met the documented topology capacity and IOPS requirements: PASS
- Static address and default route: PASS
- Gateway ping: 3 of 3 replies: PASS
- External DNS lookup: PASS
- SELinux: `Enforcing`: PASS
- firewalld: `active`: PASS
- HTTPS listener: PASS
- Unauthenticated gateway status endpoint: HTTP 401, as expected: PASS
- Authenticated `/api/gateway/v1/me/`: HTTP 200: PASS
- Red Hat host registration: Registered
- AAP controller version: 4.8.9
- AAP subscription: Compliant, enterprise, non-trial
- Managed-host allowance: 16; 2 used and 14 remaining at final acceptance
- Subscription expiry shown by AAP: June 1, 2027
- AAP containers: 24 running: PASS
- NTP after correction: synchronized, stratum 2, leap status normal: PASS

The initial VM configuration allowed VMware Tools host-time injection. The ESXi host's clock was not synchronized, so it moved the guest clock after chronyd corrected it. Time synchronization with the ESXi host was disabled for the guest and RHEL chronyd remained authoritative. Exact timing and host identifiers are retained privately.

## Reboot-persistence proof

- The pre-reboot and post-reboot boot IDs differed; the identifiers are intentionally omitted.
- firewalld and chronyd returned active: PASS
- The `aap` user systemd manager returned `running`: PASS
- All 24 AAP containers returned to `Up`: PASS
- Authenticated `/api/gateway/v1/me/` after reboot: HTTP 200: PASS
- Private AAP CA trusted by the review workstation: PASS
- Browser loaded the sign-in page without a certificate-warning bypass: PASS
- Administrator sign-in opened the licensed platform: PASS

## Browser trust evidence

- Certificate fingerprint verification: PASS; fingerprint retained privately
- Authenticated browser result: AAP Subscription Settings displayed `Compliant` after a real administrator login

## Evidence boundary

No password, private SSH key, private hostname, private address, machine identifier, certificate fingerprint, Red Hat media, entitlement data, or installer bundle is stored here. The retained private build log remains outside the public repository. Public screenshots and video must not contain personal desktop UI or private infrastructure details.
