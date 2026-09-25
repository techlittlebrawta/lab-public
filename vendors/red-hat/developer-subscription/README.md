# Red Hat Developer Subscription companion

Companion material for the Tech Little Brawta guide **What You Actually Get with the Red Hat Developer Subscription—and How to Activate It**.

## Purpose

This package gives readers a copy-ready, non-destructive verification command for a RHEL system registered to a Red Hat account.

## Verify a registered RHEL host

```bash
chmod +x verify-rhel-developer-subscription.sh
./verify-rhel-developer-subscription.sh
```

The script does **not** register the machine, change subscriptions, enable repositories, install packages, or store credentials. It checks:

- RHEL release
- subscription-manager identity
- subscription-manager status
- enabled repositories
- DNF repository visibility
- a refreshed DNF metadata transaction

## Registration command

Run interactively on the RHEL system:

```bash
sudo subscription-manager register
```

Do not put a Red Hat password directly in shell history.

Modern Red Hat documentation describes Simple Content Access as the current access model and the old entitlement-attachment model as deprecated. The normal goal is a registered host with a valid account subscription that can consume available content.

## Validation status

The verification script has been syntax-checked before publication to this repository. A full TLB lab run against a registered RHEL Developer Subscription host is still required before the related website article can pass the TLB publication gate.

## Primary references

- https://developers.redhat.com/about
- https://developers.redhat.com/articles/faqs-no-cost-red-hat-enterprise-linux
- https://developers.redhat.com/products/rhel
- https://developers.redhat.com/products/rhel/download
- https://developers.redhat.com/products/ansible
- https://developers.redhat.com/products/ansible/download
- https://developers.redhat.com/developer-sandbox/FAQ
- https://developers.redhat.com/products
- https://developers.redhat.com/terms-and-conditions
- https://docs.redhat.com/en/documentation/subscription_central/1-latest/html-single/getting_started_with_rhel_system_registration/getting_started_with_rhel_system_registration
- https://developers.redhat.com/articles/renew-your-red-hat-developer-program-subscription
- https://developers.redhat.com/articles/2026/03/16/unlocking-ubi-red-hat-enterprise-linux-container-images
