#!/usr/bin/env bash
set -euo pipefail

if ! command -v subscription-manager >/dev/null 2>&1; then
  echo "FAIL: subscription-manager is not installed." >&2
  exit 1
fi

if ! command -v dnf >/dev/null 2>&1; then
  echo "FAIL: dnf is not installed." >&2
  exit 1
fi

echo "=== RHEL RELEASE ==="
cat /etc/redhat-release

echo
echo "=== REGISTERED IDENTITY ==="
sudo subscription-manager identity

echo
echo "=== SUBSCRIPTION STATUS ==="
sudo subscription-manager status

echo
echo "=== ENABLED RED HAT REPOSITORIES ==="
sudo subscription-manager repos --list-enabled

echo
echo "=== DNF REPOSITORIES ==="
sudo dnf repolist

echo
echo "=== REFRESH TEST ==="
sudo dnf makecache --refresh

echo
echo "PASS: registration identity and repository refresh completed."
