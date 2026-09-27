# Validation record

- Date: 2026-09-27
- Lab subnet: `192.168.1.0/24`
- PNETLab bridge: `pnet0`, `192.168.1.252/24`
- Default route: `192.168.1.1` through `pnet0`
- Node: VPCS node 1, `VPC-Internet-Test`
- Path: VPCS `eth0` to `Internet-Cloud0` / Management (Cloud0)
- DHCP: `192.168.1.21/24`, gateway `192.168.1.1`
- Default-gateway reachability: passed, 3 of 3 replies
- External IP reachability: passed, 3 of 3 replies from `1.1.1.1`
- DNS and external reachability: passed, `cloudflare.com` resolved to `104.16.133.229` and replied 3 of 3 times

The GUI actions and tests were captured live. Every connectivity test ran from VPCS, not from the PNETLab server. The exact observed output is retained in `vpcs-validation.txt`.
