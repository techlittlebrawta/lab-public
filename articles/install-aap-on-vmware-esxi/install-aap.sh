#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PROGRAM=${0##*/}
INSTALL_USER=${AAP_INSTALL_USER:-aap}
INSTALL_ROOT=${AAP_INSTALL_DIR:-/home/${INSTALL_USER}/aap-install}
ADMIN_USER=${AAP_ADMIN_USER:-admin}
MIN_CPUS=${AAP_MIN_CPUS:-4}
# A VM allocated 16 GiB reports slightly less in /proc/meminfo after firmware
# and kernel reservations. 15,000 MiB still enforces the vendor's 16 GiB VM.
MIN_RAM_MIB=${AAP_MIN_RAM_MIB:-15000}
MIN_DISK_GIB=${AAP_MIN_DISK_GIB:-60}
LOG_DIR=${AAP_LOG_DIR:-/var/log/aap-installer}
CREDENTIAL_FILE=${AAP_CREDENTIAL_FILE:-/root/aap-install-credentials.txt}
BUNDLE_OVERRIDE=${AAP_BUNDLE:-}

STAGE=initialization
RUN_LOG=""

fail() {
  local rc=${2:-1}
  printf '\nERROR [%s]: %s\n' "$STAGE" "$1" >&2
  [[ -n "$RUN_LOG" ]] && printf 'Installation log: %s\n' "$RUN_LOG" >&2
  exit "$rc"
}

on_error() {
  local rc=$?
  printf '\nERROR [%s]: command failed on line %s (exit %s).\n' "$STAGE" "$1" "$rc" >&2
  [[ -n "$RUN_LOG" ]] && printf 'Installation log: %s\n' "$RUN_LOG" >&2
  exit "$rc"
}
trap 'on_error $LINENO' ERR

need_root() {
  [[ ${EUID} -eq 0 ]] || fail "Run with sudo: sudo ./${PROGRAM}"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

random_secret() {
  openssl rand -base64 48 | tr -d '\n/+=' | cut -c1-40
}

detect_bundle() {
  local candidates=()
  if [[ -n "$BUNDLE_OVERRIDE" ]]; then
    [[ -f "$BUNDLE_OVERRIDE" ]] || fail "AAP_BUNDLE does not name a readable file: $BUNDLE_OVERRIDE"
    printf '%s\n' "$BUNDLE_OVERRIDE"
    return
  fi

  while IFS= read -r -d '' file; do candidates+=("$file"); done < <(
    find "$PWD" /root /home -maxdepth 3 -type f \
      -name 'ansible-automation-platform-containerized-setup-bundle-*-x86_64.tar.gz' \
      -print0 2>/dev/null
  )
  ((${#candidates[@]} > 0)) || fail "No AAP containerized setup bundle was found. Copy it to the current directory or set AAP_BUNDLE."
  printf '%s\n' "${candidates[@]}" | sort -V | tail -n1
}

validate_existing() {
  [[ -s "$CREDENTIAL_FILE" ]] || return 1
  local url user password code
  url=$(awk -F': ' '$1=="URL"{print $2}' "$CREDENTIAL_FILE")
  user=$(awk -F': ' '$1=="Username"{print $2}' "$CREDENTIAL_FILE")
  password=$(awk -F': ' '$1=="Password"{print $2}' "$CREDENTIAL_FILE")
  [[ -n "$url" && -n "$user" && -n "$password" ]] || return 1
  code=$(curl -ksS -o /dev/null -w '%{http_code}' --connect-timeout 5 "${url}/api/gateway/v1/status/" || true)
  if [[ "$code" =~ ^(200|401|403)$ ]]; then
    printf 'A prior AAP installation is responding at %s (HTTP %s).\n' "$url" "$code"
    printf 'Re-run with AAP_FORCE_RECONCILE=1 to apply the installer again without uninstalling data.\n'
    print_success "$url" "$user" "$password"
    return 0
  fi
  return 1
}

print_success() {
  local url=$1 user=$2 password=$3
  local host ip displayed_password
  host=$(hostnamectl --static 2>/dev/null || hostname)
  ip=$(hostname -I | awk '{print $1}')
  displayed_password=$password
  if [[ ${AAP_REDACT_OUTPUT:-0} == 1 ]]; then
    displayed_password="<stored in ${CREDENTIAL_FILE}>"
  fi
  cat <<EOF
================================================
ANSIBLE AUTOMATION PLATFORM INSTALL COMPLETE
================================================
URL: ${url}
Username: ${user}
Password: ${displayed_password}
Host: ${host}
IP: ${ip}
================================================
Credentials: ${CREDENTIAL_FILE} (root only, mode 600)
EOF
}

need_root

STAGE=preflight
[[ -r /etc/os-release ]] || fail "Cannot identify the operating system."
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == rhel ]] || fail "This installer supports Red Hat Enterprise Linux only (detected: ${ID:-unknown})."
major=${VERSION_ID%%.*}
minor=${VERSION_ID#*.}
case "$major" in
  9) ((minor >= 6)) || fail "AAP 2.7 requires RHEL 9.6 or later." ;;
  10) : ;;
  *) fail "AAP 2.7 supports RHEL 9.6+ or RHEL 10.x; detected ${VERSION_ID}." ;;
esac
[[ $(uname -m) == x86_64 ]] || fail "This companion is validated for x86_64; detected $(uname -m)."

cpus=$(nproc)
ram_mib=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
disk_gib=$(df -Pk /home | awk 'NR==2{print int($4/1024/1024)}')
((cpus >= MIN_CPUS)) || fail "At least ${MIN_CPUS} CPUs are required; detected ${cpus}."
((ram_mib >= MIN_RAM_MIB)) || fail "At least 16 GB RAM is required; detected ${ram_mib} MiB."
((disk_gib >= MIN_DISK_GIB)) || fail "At least ${MIN_DISK_GIB} GiB free under /home is required; detected ${disk_gib} GiB."

fqdn=${AAP_HOSTNAME:-$(hostname -f 2>/dev/null || true)}
[[ "$fqdn" == *.* ]] || fail "The host must resolve its own FQDN. Set DNS or /etc/hosts, or provide AAP_HOSTNAME."
getent ahostsv4 "$fqdn" >/dev/null || fail "FQDN does not resolve locally: $fqdn"
getent hosts access.redhat.com >/dev/null || fail "DNS cannot resolve access.redhat.com."

if [[ ${AAP_FORCE_RECONCILE:-0} != 1 ]] && validate_existing; then
  exit 0
fi

STAGE=host-preparation
install -d -m 0700 "$LOG_DIR"
RUN_LOG="${LOG_DIR}/install-$(date -u +%Y%m%dT%H%M%SZ).log"
touch "$RUN_LOG"
chmod 0600 "$RUN_LOG"

command_exists openssl || dnf install -y openssl
dnf -y upgrade
dnf install -y ansible-core curl firewalld openssl sudo tar
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

dnf repolist --enabled | grep -qi 'baseos' || fail "The RHEL BaseOS repository is not enabled."
dnf repolist --enabled | grep -qi 'appstream' || fail "The RHEL AppStream repository is not enabled."
if command_exists subscription-manager && ! subscription-manager identity >/dev/null 2>&1; then
  printf 'RHEL is not attached to CDN content; continuing with the enabled local BaseOS/AppStream repositories for this bundled installation.\n'
fi

id "$INSTALL_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$INSTALL_USER"
install -o root -g root -m 0440 /dev/null "/etc/sudoers.d/${INSTALL_USER}"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$INSTALL_USER" >"/etc/sudoers.d/${INSTALL_USER}"
visudo -cf "/etc/sudoers.d/${INSTALL_USER}" >/dev/null
loginctl enable-linger "$INSTALL_USER"
install_uid=$(id -u "$INSTALL_USER")
systemctl start "user@${install_uid}.service"
install_runtime="/run/user/${install_uid}"
[[ -d "$install_runtime" ]] || fail "The systemd user runtime was not created for ${INSTALL_USER}."

bundle=$(detect_bundle)
bundle_name=$(basename "$bundle")
bundle_version=$(sed -nE 's/^ansible-automation-platform-containerized-setup-bundle-([0-9.-]+)-x86_64\.tar\.gz$/\1/p' <<<"$bundle_name")
[[ -n "$bundle_version" ]] || fail "Could not determine the AAP version from $bundle_name."

install -d -o "$INSTALL_USER" -g "$INSTALL_USER" -m 0700 "$INSTALL_ROOT"
bundle_copy="${INSTALL_ROOT}/${bundle_name}"
if [[ "$bundle" != "$bundle_copy" ]]; then
  install -o "$INSTALL_USER" -g "$INSTALL_USER" -m 0600 "$bundle" "$bundle_copy"
fi

STAGE=bundle-extraction
extract_dir="${INSTALL_ROOT}/ansible-automation-platform-containerized-setup-bundle-${bundle_version}-x86_64"
if [[ ! -d "$extract_dir/collections" ]]; then
  sudo -u "$INSTALL_USER" tar -xzf "$bundle_copy" -C "$INSTALL_ROOT"
fi
[[ -d "$extract_dir/bundle" ]] || fail "The extracted archive is not a bundled installer."

inventory="${extract_dir}/inventory-growth"
if [[ ${AAP_RESUME_VALIDATION:-0} == 1 ]]; then
  STAGE=resume-validation
  [[ -s "$inventory" ]] || fail "Cannot resume validation because the generated inventory is missing: $inventory"
  gateway_admin_user=$(sed -nE "s/^gateway_admin_user='([^']+)'/\1/p" "$inventory" | tail -n1)
  gateway_admin_password=$(sed -nE "s/^gateway_admin_password='([^']+)'/\1/p" "$inventory" | tail -n1)
  [[ -n "$gateway_admin_user" && -n "$gateway_admin_password" ]] || fail "Cannot recover the gateway administrator credentials from the generated inventory."

  url="https://${fqdn}"
  code=$(curl -ksS -o /dev/null -w '%{http_code}' --connect-timeout 5 "${url}/api/gateway/v1/status/" || true)
  [[ "$code" =~ ^(200|401|403)$ ]] || fail "AAP gateway did not respond at ${url} (HTTP ${code:-none})."
  ss -lnt | grep -Eq ':(443|8443)[[:space:]]' || fail "No AAP HTTPS listener was detected."
  (
    cd /
    sudo -u "$INSTALL_USER" env HOME="/home/${INSTALL_USER}" XDG_RUNTIME_DIR="$install_runtime" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=${install_runtime}/bus" \
      podman ps --format '{{.Names}} {{.Status}}'
  ) | tee -a "$RUN_LOG"
  if (
    cd /
    sudo -u "$INSTALL_USER" env HOME="/home/${INSTALL_USER}" XDG_RUNTIME_DIR="$install_runtime" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=${install_runtime}/bus" \
      podman ps --format '{{.Status}}'
  ) | grep -Eqi 'unhealthy|exited|dead'; then
    fail "One or more AAP containers are not healthy."
  fi

  cat >"$CREDENTIAL_FILE" <<EOF
URL: ${url}
Username: ${gateway_admin_user}
Password: ${gateway_admin_password}
Host: $(hostnamectl --static 2>/dev/null || hostname)
IP: $(hostname -I | awk '{print $1}')
AAP bundle: ${bundle_name}
Installed: $(date --iso-8601=seconds)
EOF
  chown root:root "$CREDENTIAL_FILE"
  chmod 0600 "$CREDENTIAL_FILE"
  print_success "$url" "$gateway_admin_user" "$gateway_admin_password"
  exit 0
fi

if [[ -f "$inventory" ]]; then
  cp -a "$inventory" "${inventory}.before-${PROGRAM}-$(date -u +%Y%m%dT%H%M%SZ)"
fi

STAGE=inventory-generation
pg_admin_password=$(random_secret)
gateway_admin_password=$(random_secret)
controller_admin_password=$(random_secret)
hub_admin_password=$(random_secret)
eda_admin_password=$(random_secret)
gateway_pg_password=$(random_secret)
controller_pg_password=$(random_secret)
hub_pg_password=$(random_secret)
eda_pg_password=$(random_secret)
metrics_pg_password=$(random_secret)
metrics_read_password=$(random_secret)

cat >"$inventory" <<EOF
[automationgateway]
${fqdn}

[automationcontroller]
${fqdn}

[automationhub]
${fqdn}

[automationeda]
${fqdn}

[automationmetrics]
${fqdn}

[database]
${fqdn}

[all:vars]
ansible_connection=local
postgresql_admin_username=postgres
postgresql_admin_password='${pg_admin_password}'
bundle_install=true
bundle_dir='${extract_dir}/bundle'
redis_mode=standalone
gateway_admin_user='${ADMIN_USER}'
gateway_admin_password='${gateway_admin_password}'
gateway_pg_host='${fqdn}'
gateway_pg_password='${gateway_pg_password}'
controller_admin_user='${ADMIN_USER}'
controller_admin_password='${controller_admin_password}'
controller_pg_host='${fqdn}'
controller_pg_password='${controller_pg_password}'
controller_percent_memory_capacity=0.5
hub_admin_password='${hub_admin_password}'
hub_pg_host='${fqdn}'
hub_pg_password='${hub_pg_password}'
hub_seed_collections=false
eda_admin_password='${eda_admin_password}'
eda_pg_host='${fqdn}'
eda_pg_password='${eda_pg_password}'
automationmetrics_pg_host='${fqdn}'
automationmetrics_pg_password='${metrics_pg_password}'
automationmetrics_controller_read_pg_host='${fqdn}'
automationmetrics_controller_read_pg_password='${metrics_read_password}'
EOF
chown "$INSTALL_USER:$INSTALL_USER" "$inventory"
chmod 0600 "$inventory"

STAGE=official-installer
(
  cd "$extract_dir"
  sudo -u "$INSTALL_USER" env HOME="/home/${INSTALL_USER}" XDG_RUNTIME_DIR="$install_runtime" \
    ansible-playbook -i inventory-growth ansible.containerized_installer.install
) 2>&1 | tee "$RUN_LOG"

STAGE=validation
url="https://${fqdn}"
for _ in {1..60}; do
  code=$(curl -ksS -o /dev/null -w '%{http_code}' --connect-timeout 5 "${url}/api/gateway/v1/status/" || true)
  [[ "$code" =~ ^(200|401|403)$ ]] && break
  sleep 5
done
[[ "$code" =~ ^(200|401|403)$ ]] || fail "AAP gateway did not become reachable at ${url} (last HTTP status: ${code:-none})."
ss -lnt | grep -Eq ':(443|8443)[[:space:]]' || fail "No AAP HTTPS listener was detected."
(
  cd /
  sudo -u "$INSTALL_USER" env HOME="/home/${INSTALL_USER}" XDG_RUNTIME_DIR="$install_runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=${install_runtime}/bus" \
    podman ps --format '{{.Names}} {{.Status}}'
) | tee -a "$RUN_LOG"
if (
  cd /
  sudo -u "$INSTALL_USER" env HOME="/home/${INSTALL_USER}" XDG_RUNTIME_DIR="$install_runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=${install_runtime}/bus" \
    podman ps --format '{{.Status}}'
) | grep -Eqi 'unhealthy|exited|dead'; then
  fail "One or more AAP containers are not healthy."
fi

cat >"$CREDENTIAL_FILE" <<EOF
URL: ${url}
Username: ${ADMIN_USER}
Password: ${gateway_admin_password}
Host: $(hostnamectl --static 2>/dev/null || hostname)
IP: $(hostname -I | awk '{print $1}')
AAP bundle: ${bundle_name}
Installed: $(date --iso-8601=seconds)
EOF
chown root:root "$CREDENTIAL_FILE"
chmod 0600 "$CREDENTIAL_FILE"

print_success "$url" "$ADMIN_USER" "$gateway_admin_password"
