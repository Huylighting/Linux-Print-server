#!/usr/bin/env bash
set -Eeuo pipefail

# Linux Print Server installer for CUPS + optional Samba and Avahi.
# Usage: sudo ./install.sh [--admin-user USER] [--no-samba] [--no-avahi] [--no-firewall] [--remote-access]

SCRIPT_NAME="$(basename "$0")"
ADMIN_USER="${ADMIN_USER:-${SUDO_USER:-${USER:-}}}"
INSTALL_SAMBA="${INSTALL_SAMBA:-1}"
INSTALL_AVAHI="${INSTALL_AVAHI:-1}"
CONFIG_FIREWALL="${CONFIG_FIREWALL:-1}"
ENABLE_REMOTE="${ENABLE_REMOTE:-0}"
OS_ID="unknown"
OS_LIKE=""
CUPS_SERVICE="cups.service"
SAMBA_SERVICE="smbd.service"
AVAHI_SERVICE="avahi-daemon.service"

log() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<USAGE
Usage: sudo ./${SCRIPT_NAME} [options]

Options:
  --admin-user USER  User to add to the CUPS admin group. Default: sudo user.
  --no-samba         Skip Samba installation and printer sharing config.
  --no-avahi         Skip Avahi/Bonjour installation.
  --no-firewall      Skip firewall rule changes.
  --remote-access    Enable cross-subnet CUPS sharing. Restrict to trusted LANs.
  -h, --help         Show this help.
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --admin-user)
        [[ $# -ge 2 && -n "${2:-}" ]] || fail "--admin-user requires a username."
        ADMIN_USER="$2"; shift 2 ;;
      --no-samba) INSTALL_SAMBA=0; shift ;;
      --no-avahi) INSTALL_AVAHI=0; shift ;;
      --no-firewall) CONFIG_FIREWALL=0; shift ;;
      --remote-access) ENABLE_REMOTE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "Please run this script with sudo or as root."
}
command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
  fi
}

is_family() {
  local family="$1"
  [[ " ${OS_ID} ${OS_LIKE} " == *" ${family} "* ]]
}

backup_file() {
  local file="$1" backup
  [[ -f "$file" ]] || return 0
  backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
  cp -a -- "$file" "$backup"
  log "Backed up $file to $backup"
}

install_packages() {
  local packages=("$@")
  (("${#packages[@]}" > 0)) || return 0

  if command_exists apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y -- "${packages[@]}"
  elif command_exists dnf; then
    dnf install -y -- "${packages[@]}"
  elif command_exists zypper; then
    zypper --non-interactive install -y -- "${packages[@]}"
  elif command_exists pacman; then
    # Arch does not support partial upgrades; synchronize system and packages together.
    pacman -Syu --noconfirm --needed "${packages[@]}"
  else
    fail "Unsupported package manager. Install manually: ${packages[*]}"
  fi
}

service_exists() { systemctl cat "$1" >/dev/null 2>&1; }

enable_service() {
  local service="$1"
  if service_exists "$service"; then
    systemctl enable --now "$service"
  else
    warn "Service $service not found; skipping."
  fi
}
restart_service() {
  local service="$1"
  if service_exists "$service"; then systemctl restart "$service"
  else warn "Service $service not found; skipping restart."
  fi
}

select_services() {
  CUPS_SERVICE="cups.service"
  if is_family arch; then
    SAMBA_SERVICE="smbd.service"
    AVAHI_SERVICE="avahi-daemon.service"
  elif is_family rhel || is_family fedora; then
    SAMBA_SERVICE="smb.service"
    AVAHI_SERVICE="avahi-daemon.service"
  elif is_family suse; then
    SAMBA_SERVICE="smb.service"
    AVAHI_SERVICE="avahi-daemon.service"
  else
    SAMBA_SERVICE="smbd.service"
    AVAHI_SERVICE="avahi-daemon.service"
  fi
}

cups_packages() {
  if command_exists apt-get; then
    printf '%s\n' cups cups-filters printer-driver-all
  else
    printf '%s\n' cups cups-filters
  fi
}
avahi_packages() {
  if is_family arch; then
    printf '%s\n' avahi nss-mdns
  elif command_exists apt-get; then
    printf '%s\n' avahi-daemon
  else
    printf '%s\n' avahi
  fi
}

configure_admin_user() {
  [[ -n "$ADMIN_USER" ]] || { warn "No admin user detected; use --admin-user USER if needed."; return 0; }
  if id "$ADMIN_USER" >/dev/null 2>&1; then
    getent group lpadmin >/dev/null 2>&1 || groupadd lpadmin
    usermod -aG lpadmin "$ADMIN_USER"
    warn "User $ADMIN_USER may need to log out and back in for group changes to apply."
  else
    warn "User $ADMIN_USER does not exist; skipping lpadmin membership."
  fi
}

configure_cups() {
  [[ -f /etc/cups/cupsd.conf ]] || fail "/etc/cups/cupsd.conf not found after CUPS installation."
  command_exists cupsctl || fail "cupsctl is missing; verify the CUPS client package installation."

  log "Enabling printer sharing with conservative defaults..."
  # CUPS sharing defaults to the local subnet. Do not enable remote administration.
  cupsctl --share-printers || fail "Could not configure CUPS printer sharing."
  if [[ "$ENABLE_REMOTE" == "1" ]]; then
    warn "Enabling cross-subnet CUPS printing. Firewall rules will be limited to private IPv4 ranges where supported."
    cupsctl --remote-any || fail "Could not enable cross-subnet CUPS sharing."
  else
    cupsctl --no-remote-any || true
    log "Cross-subnet CUPS sharing remains disabled."
  fi
  restart_service "$CUPS_SERVICE"
}

ensure_samba_section() {
  local conf="$1" section="$2" body="$3"
  if ! awk -v wanted="[$section]" '{ line=$0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line); if (line == wanted) found=1 } END { exit(found ? 0 : 1) }' "$conf"; then
    printf '\n%s\n' "$body" >> "$conf"
    log "Added Samba [$section] section."
  else
    warn "Samba [$section] section already exists; preserving administrator-managed settings."
  fi
}

configure_samba() {
  local conf="/etc/samba/smb.conf"
  [[ -f "$conf" ]] || { warn "$conf not found; skipping Samba config."; return 0; }

  backup_file "$conf"
  install -d -m 1777 /var/spool/samba
  install -d -m 0755 /var/lib/samba/printers

  ensure_samba_section "$conf" "printers" '[printers]
   comment = All Printers
   path = /var/spool/samba
   printable = yes
   browseable = no
   guest ok = no
   read only = yes
   create mask = 0600'

  ensure_samba_section "$conf" "print\$" '[print$]
   comment = Printer Drivers
   path = /var/lib/samba/printers
   browseable = yes
   read only = yes
   guest ok = no'

  if command_exists testparm; then testparm -s "$conf" >/dev/null || fail "Samba configuration validation failed."
  else warn "testparm unavailable; could not validate Samba configuration."; fi
  restart_service "$SAMBA_SERVICE"
}

ufw_allow_private() {
  local proto="$1" port="$2" subnet
  for subnet in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
    ufw allow from "$subnet" to any port "$port" proto "$proto" >/dev/null
  done
}
ufw_allow_tailscale() {
  local proto="$1" port="$2"
  # Restrict these rules to the Tailscale interface, not every interface using 100.64.0.0/10.
  if ip link show tailscale0 >/dev/null 2>&1; then
    ufw allow in on tailscale0 to any port "$port" proto "$proto" >/dev/null
  else
    warn "tailscale0 not found; skipping Tailscale UFW rule for $proto/$port."
  fi
}
firewalld_allow_private() {
  local proto="$1" port="$2" subnet
  for subnet in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
    firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$subnet\" port port=\"$port\" protocol=\"$proto\" accept" >/dev/null
  done
}
firewalld_allow_tailscale() {
  local proto="$1" port="$2"
  # Tailscale IPv4 addresses are in 100.64.0.0/10; enforce this source range in firewalld.
  firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"100.64.0.0/10\" port port=\"$port\" protocol=\"$proto\" accept" >/dev/null
}
configure_firewall() {
  [[ "$CONFIG_FIREWALL" == "1" ]] || { log "Skipping firewall changes."; return 0; }
  local proto port
  if command_exists ufw && ufw status | grep -q '^Status: active'; then
    log "Restricting print-server firewall rules to private IPv4 ranges..."
    ufw_allow_private tcp 631
    ufw_allow_tailscale tcp 631
    if [[ "$INSTALL_SAMBA" == "1" ]]; then
      for port in 137 138; do ufw_allow_private udp "$port"; done
      for port in 139 445; do ufw_allow_private tcp "$port"; done
      for port in 137 138; do ufw_allow_tailscale udp "$port"; done
      for port in 139 445; do ufw_allow_tailscale tcp "$port"; done
    fi
  elif command_exists firewall-cmd && systemctl is-active --quiet firewalld; then
    log "Restricting print-server firewall rules to private IPv4 ranges..."
    firewalld_allow_private tcp 631
    firewalld_allow_tailscale tcp 631
    if [[ "$INSTALL_SAMBA" == "1" ]]; then
      for port in 137 138; do firewalld_allow_private udp "$port"; done
      for port in 139 445; do firewalld_allow_private tcp "$port"; done
      for port in 137 138; do firewalld_allow_tailscale udp "$port"; done
      for port in 139 445; do firewalld_allow_tailscale tcp "$port"; done
    fi
    firewall-cmd --reload
  else
    warn "No active UFW/firewalld detected; no firewall rules were changed. Review host/router firewall before enabling remote access."
  fi
}

print_summary() {
  local ip_addresses
  ip_addresses="$(hostname -I 2>/dev/null | xargs || true)"
  cat <<SUMMARY

Installation steps completed (printer hardware has not been tested by this script).

Next steps:
  1. Open CUPS locally: http://localhost:631
  2. Add the printer under Administration -> Add Printer.
  3. Use an account in the lpadmin group for administration.
  4. Mark each intended queue as shared in CUPS before clients connect.
  5. Remote access is off by default. Do not expose TCP 631 to the public Internet.

Detected server IP(s): ${ip_addresses:-unknown}
CUPS service: ${CUPS_SERVICE}
Samba service: ${SAMBA_SERVICE}
Avahi service: ${AVAHI_SERVICE}
Admin user: ${ADMIN_USER:-not configured}
SUMMARY
}

main() {
  parse_args "$@"
  require_root
  detect_os
  select_services
  log "Detected OS: $OS_ID ${OS_LIKE}"
  log "Installing CUPS..."
  mapfile -t cups_pkg_list < <(cups_packages)
  install_packages "${cups_pkg_list[@]}"
  enable_service "$CUPS_SERVICE"
  configure_admin_user
  configure_cups

  if [[ "$INSTALL_SAMBA" == "1" ]]; then
    log "Installing Samba..."
    install_packages samba
    configure_samba
  else
    log "Skipping Samba."
  fi

  if [[ "$INSTALL_AVAHI" == "1" ]]; then
    log "Installing Avahi/Bonjour..."
    mapfile -t avahi_pkg_list < <(avahi_packages)
    install_packages "${avahi_pkg_list[@]}"
    enable_service "$AVAHI_SERVICE"
  else
    log "Skipping Avahi."
  fi
  configure_firewall
  print_summary
}
main "$@"
