#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_USER=${AAP_INSTALL_USER:-aap}
CREDENTIAL_FILE=${AAP_CREDENTIAL_FILE:-/root/aap-install-credentials.txt}

if [[ ${EUID} -ne 0 ]]; then
  printf 'Run this validation as root.\n' >&2
  exit 1
fi

install_uid=$(id -u "$INSTALL_USER")
runtime="/run/user/${install_uid}"
[[ -s "$CREDENTIAL_FILE" ]] || { printf 'Missing credential record: %s\n' "$CREDENTIAL_FILE" >&2; exit 1; }

username=$(awk -F': ' '$1=="Username"{print $2}' "$CREDENTIAL_FILE")
password=$(awk -F': ' '$1=="Password"{print $2}' "$CREDENTIAL_FILE")
url=$(awk -F': ' '$1=="URL"{print $2}' "$CREDENTIAL_FILE")
[[ -n "$username" && -n "$password" && -n "$url" ]] || { printf 'Credential record is incomplete.\n' >&2; exit 1; }

printf '=== AAP POST-REBOOT VALIDATION ===\n'
printf 'Boot ID: '; cat /proc/sys/kernel/random/boot_id
printf 'RHEL: '; cat /etc/redhat-release
printf 'Kernel: '; uname -r
printf 'Host: '; hostname -f
printf 'Address: '; ip -4 -br address show scope global | awk '{print $1" "$3}'
printf 'Default route: '; ip route show default
printf 'SELinux: '; getenforce
printf 'firewalld: '; systemctl is-active firewalld
printf 'NTP synchronized: '; timedatectl show -p NTPSynchronized --value

mapfile -t containers < <(
  cd /
  runuser -u "$INSTALL_USER" -- env HOME="/home/${INSTALL_USER}" XDG_RUNTIME_DIR="$runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime}/bus" \
    podman ps --format '{{.Names}}|{{.Status}}'
)
printf 'Running AAP containers: %s\n' "${#containers[@]}"
printf '%s\n' "${containers[@]}"

failed=$(cd / && runuser -u "$INSTALL_USER" -- env HOME="/home/${INSTALL_USER}" XDG_RUNTIME_DIR="$runtime" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime}/bus" \
  systemctl --user --failed --no-legend 2>/dev/null || true)
[[ -z "$failed" ]] || { printf 'Failed AAP user services:\n%s\n' "$failed" >&2; exit 1; }

status=$(curl -ksS -u "${username}:${password}" -o /tmp/aap-auth-check.json -w '%{http_code}' \
  "${url}/api/gateway/v1/me/")
rm -f /tmp/aap-auth-check.json
printf 'Authenticated gateway API: HTTP %s\n' "$status"
[[ "$status" == 200 ]] || exit 1

printf 'RESULT: PASS\n'
