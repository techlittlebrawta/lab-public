#!/usr/bin/env bash
set -euo pipefail

for cmd in subscription-manager dnf; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "FAIL: $cmd is not installed." >&2
    exit 1
  }
done

echo "=== RHEL RELEASE ==="
cat /etc/redhat-release

if command -v rhc >/dev/null 2>&1; then
  echo
  echo "=== RHC STATUS ==="
  sudo rhc status
fi

echo
echo "=== REGISTERED IDENTITY ==="
sudo subscription-manager identity

echo
echo "=== ENABLED RED HAT REPOSITORIES ==="
sudo subscription-manager repos --list-enabled

echo
echo "=== DNF REPOSITORIES ==="
sudo dnf repolist

echo
echo "=== CONTENT REFRESH ==="
sudo dnf makecache --refresh

echo
echo "PASS: registration identity and repository refresh completed."
