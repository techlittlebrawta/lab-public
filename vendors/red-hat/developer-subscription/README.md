# Red Hat Developer Subscription companion

Companion for the Tech Little Brawta guide **How to claim the Red Hat Developer Subscription and prove RHEL content access**.

## Registration method

Use the registration client that matches the RHEL environment:

- **RHEL 8.8 or later:** Red Hat's current Subscription Central guide uses `rhc connect`.
- **RHEL 8.7 or earlier, or Satellite-backed registration:** use `subscription-manager register`.

For RHEL 8.8+ with an activation key:

```bash
sudo rhc connect \
  --activation-key=<ACTIVATION_KEY> \
  --organization=<ORG_ID>
```

For a username/password registration, follow the current Red Hat guide. Do not store a password in this repository, a shared file, screenshots, or video.

## Verify a registered RHEL host

```bash
chmod +x verify-rhel-developer-subscription.sh
./verify-rhel-developer-subscription.sh
```

The script is read-only with respect to registration. It checks:

- RHEL release
- `rhc status` when `rhc` is installed
- `subscription-manager identity`
- enabled Red Hat repositories
- DNF repository visibility
- a refreshed DNF metadata transaction

## Simple Content Access

Do not treat `Overall Status: Disabled` as an automatic registration failure on older clients. Red Hat documents that this can be expected under Simple Content Access. Verify system identity and working content access instead.

## Validation status

The script passes `bash -n`. The TLB article remains in lab-validation until the commands are run on an authorized RHEL Developer Subscription host and real output/screenshots are retained.

## Primary references

See `sources.md`.
