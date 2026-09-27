# Give a PNETLab Node Internet Access with Cloud0

This is the public technical companion to the Tech Little Brawta blog, **How to Give a PNETLab Node Internet Access**.

It contains the reusable configuration and the sanitized proof from the validated lab. It does not contain credentials, private lab URLs, proprietary images, or a PNETLab export.

## What the lab does

A PNETLab node connects an available interface to **Management (Cloud0)**. On the PNETLab host, Cloud0 maps to the Linux bridge `pnet0`. The upstream lab network supplies DHCP or accepts an appropriate static configuration, plus a default gateway, DNS, and internet access. The validated example uses VPCS; other node types use their own interface commands.

```text
Internet-Cloud0 (pnet0) ─── eth0 VPCS
```

Cloud0 joins the VPC to the network behind the PNETLab management interface. Use a dedicated lab VLAN where possible.

## Host-side checks

Run these from the PNETLab server before opening the lab:

```bash
ip -br address show pnet0
ip route show default
bridge link show
```

If `pnet0` already carries the management address and the host has a valid default route, no host change is needed.

For a new DHCP-based installation, start with [pnet0-interfaces.example](pnet0-interfaces.example). Replace `eth0` with the actual uplink name. Keep the existing address, gateway, and DNS values when the server uses static management addressing.

Make management-bridge changes from a hypervisor or physical console. Restarting the bridge can end an SSH session or disconnect the server.

## PNETLab GUI

1. Stop the VPC.
2. Add a Network object.
3. Name it `Internet-Cloud0`.
4. Select **Management (Cloud0)**.
5. Connect the VPC's `eth0` interface to the network.
6. Start the VPC.

## VPCS validation

Run:

```text
ip dhcp
show ip
ping <default-gateway> -c 3
ping 1.1.1.1 -c 3
ping cloudflare.com -c 3
```

The complete sanitized output from the validated run is in [vpcs-validation.txt](vpcs-validation.txt).

## Troubleshooting

- No DHCP lease: confirm the node uses Management (Cloud0) and that DHCP is available upstream.
- No gateway reply: verify the VLAN, subnet, duplicate addresses, and hypervisor port-group configuration.
- Gateway works but `1.1.1.1` fails: check upstream routing and firewall policy.
- `1.1.1.1` works but names fail: check the DNS value from `show ip`.
- ESXi nested-node failure: review MAC address changes and forged transmits on the dedicated lab port group.

## Primary sources

- [PNETLab documentation](https://pnetlab.com/pages/documentation)
- [PNETLab deployment and pnet0 bridge example](https://pnetlab.com/pages/documentation?slug=how-to-deploy-pnetlab-box-on-google-cloud)
- [PNETLab Cloud Management guidance for ESXi](https://www.pnetlab.com/pages/documentation?slug=can-not-get-ip-from-cloud-management-on-esxi)
- [Broadcom vSphere switch security guidance](https://knowledge.broadcom.com/external/article/446719/security-implications-of-enabling-promis.html)

## Validation scope

Validated on September 27, 2026, using a VPCS node connected directly to Management (Cloud0). The VPC obtained a DHCP lease, reached its gateway, reached `1.1.1.1`, and resolved and reached `cloudflare.com`.
