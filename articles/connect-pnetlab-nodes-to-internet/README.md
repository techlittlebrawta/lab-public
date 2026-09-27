# Give a PNETLab Node Internet Access with Cloud0

This is the public technical companion to the Tech Little Brawta blog, **How to Give a PNETLab Node Internet Access**.

It contains the host bridge configuration, exact VPCS commands and observed results, and the troubleshooting sequence used in the live walkthrough. It contains no credentials or private management URL.

## What the lab does

The VPCS node connects directly to **Management (Cloud0)**. On the PNETLab host, Cloud0 maps to the Linux bridge `pnet0`.

```text
VPC-Internet-Test eth0 ─── Internet-Cloud0
                              │
                              └── Management (Cloud0) / pnet0
```

There is no router appliance and no PNETLab NAT object in this design.

## Host-side CLI configuration

Inspect the existing bridge before changing it:

```bash
ip -br address show pnet0
ip route show default
bridge link show
```

The validated TLB lab uses `pnet0` at `192.168.1.252/24`, with a default route through `192.168.1.1`.

The matching static bridge block is in [pnet0-interfaces.example](pnet0-interfaces.example). Confirm the server's physical uplink and assigned address before using it. Make management-bridge changes from a hypervisor or physical console because a bad change can end the SSH session or disconnect the server.

## PNETLab GUI

1. Add a Network object.
2. Name it `Internet-Cloud0`.
3. Select **Management (Cloud0)**.
4. Add a VPCS node named `VPC-Internet-Test`.
5. Connect VPCS `eth0` directly to `Internet-Cloud0`.
6. Start the node and open its console.

## Exact VPCS validation

Run:

```text
ip dhcp
show ip
ping 192.168.1.1 -c 3
ping 1.1.1.1 -c 3
ping cloudflare.com -c 3
```

The live node received `192.168.1.21/24`; its gateway, DNS server, and DHCP server were `192.168.1.1`. All three ping tests returned 3 of 3 replies, and `cloudflare.com` resolved to `104.16.133.229`.

The complete observed output is in [vpcs-validation.txt](vpcs-validation.txt).

## Troubleshooting

- No DHCP lease: confirm the node uses Management (Cloud0) and that DHCP is available upstream.
- No gateway reply: verify the node link, VLAN, subnet, and duplicate addresses.
- Gateway works but `1.1.1.1` fails: check upstream routing and firewall/NAT policy.
- `1.1.1.1` works but names fail: check the DNS value shown by `show ip`.
- ESXi nested-node failure: review the dedicated lab port group's MAC Address Changes, Forged Transmits, and Promiscuous Mode requirements.

Cloud0 connects the node to the real network behind PNETLab's management interface. Use a dedicated lab VLAN or another controlled network for untrusted devices.

## Primary sources

- [PNETLab documentation](https://pnetlab.com/pages/documentation)
- [PNETLab deployment and pnet0 bridge example](https://pnetlab.com/pages/documentation?slug=how-to-deploy-pnetlab-box-on-google-cloud)
- [PNETLab Cloud Management guidance for ESXi](https://www.pnetlab.com/pages/documentation?slug=can-not-get-ip-from-cloud-management-on-esxi)
- [Broadcom vSphere switch security guidance](https://knowledge.broadcom.com/external/article/446719/security-implications-of-enabling-promis.html)

## Validation scope

Validated on September 27, 2026, from the VPCS console in the owner's PNETLab lab. The GUI and VPCS path were freshly validated. The `pnet0` address and default route come from the governed TLB host record retained for this server.
