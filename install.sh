#!/usr/bin/env bash
set -Eeuo pipefail

# Linux Print Server installer for CUPS + Samba + Avahi.
# Usage: sudo ./install.sh [--admin-user USER] [--no-samba] [--no-avahi] [--no-firewall]

SCRIPT_NAME="$(basename "$0")"
ADMIN_USER="${ADMIN_USER:-${SUDO_USER:-${USER:-}}}"
INSTALL_SAMBA="${INSTALL_SAMBA:-1}"
INSTALL_AVAHI="${INSTALL_AVAHI:-1}"
CONFIG_FIREWALL="${CONFIG_FIREWALL:-1}"
OS_ID="unknown"
OS_LIKE=""
CUPS_SERVICE="cups.service"

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
  -h, --help         Show this help.
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --admin-user)
        [[ $# -ge 2 && -n "${2:-}" ]] || fail "--admin-user requires a username."
        ADMIN_USER="$2"
        shift 2
        ;;
      --no-samba) INSTALL_SAMBA=0; shift ;;
      --no-avahi) INSTALL_AVAHI=0; shift ;;
      --no-firewall) CONFIG_FIREWALL=0; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "Please run this script with sudo or as root."
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

backup_file() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${file}" "${backup}"
    log "Backed up ${file} to ${backup}"
  fi
}

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

install_packages() {
  local packages=("$@")
  [[ ${#packages[@]} -gt 0 ]] || return 0

  if command_exists apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y "${packages[@]}"
  elif command_exists dnf; then
    dnf install -y "${packages[@]}"
  elif command_exists zypper; then
    zypper --non-interactive install -y "${packages[@]}"
  elif command_exists pacman; then
    pacman -Syu --noconfirm --needed "${packages[@]}"
  else
    fail "Unsupported package manager. Install manually: ${packages[*]}"
  fi
}

service_exists() {
  systemctl list-unit-files "$1" >/dev/null 2>&1
}

enable_service() {
  local service="$1"
  if service_exists "${service}"; then
    systemctl enable --now "${service}"
  else
    warn "Service ${service} not found; skipping."
  fi
}

restart_service() {
  local service="$1"
  if service_exists "${service}"; then
    systemctl restart "${service}"
  else
    warn "Service ${service} not found; skipping restart."
  fi
}

select_cups_service() {
  if service_exists cups.service; then
    CUPS_SERVICE="cups.service"
  elif service_exists org.cups.cupsd.service; then
    CUPS_SERVICE="org.cups.cupsd.service"
  else
    CUPS_SERVICE="cups.service"
  fi
}

cups_packages() {
  local packages=(cups cups-filters)
  if command_exists apt-get; then
    packages+=(printer-driver-all)
  fi
  printf '%s\n' "${packages[@]}"
}

avahi_packages() {
  if is_family arch; then
    printf '%s\n' avahi nss-mdns
  elif is_family rhel || is_family fedora; then
    printf '%s\n' avahi
  else
    printf '%s\n' avahi-daemon
  fi
}

configure_cups() {
  local conf="/etc/cups/cupsd.conf"
  [[ -f "${conf}" ]] || fail "${conf} not found after CUPS installation."

  log "Configuring CUPS remote access and printer sharing..."
  backup_file "${conf}"

  cupsctl --remote-any --remote-admin --share-printers DefaultAuthType=Basic || warn "cupsctl returned a warning; continuing with manual config."

  grep -q '^ServerAlias \*' "${conf}" || printf '\nServerAlias *\n' >> "${conf}"

  if grep -q '^Browsing ' "${conf}"; then
    sed -i 's/^Browsing .*/Browsing Yes/' "${conf}"
  else
    printf 'Browsing Yes\n' >> "${conf}"
  fi

  if grep -q '^DefaultAuthType ' "${conf}"; then
    sed -i 's/^DefaultAuthType .*/DefaultAuthType Basic/' "${conf}"
  else
    printf 'DefaultAuthType Basic\n' >> "${conf}"
  fi

  restart_service "${CUPS_SERVICE}"
}

configure_admin_user() {
  if [[ -z "${ADMIN_USER}" ]]; then
    warn "No admin user detected. Re-run with --admin-user USER to add a CUPS admin."
    return 0
  fi

  if id "${ADMIN_USER}" >/dev/null 2>&1; then
    log "Adding ${ADMIN_USER} to lpadmin when available..."
    getent group lpadmin >/dev/null 2>&1 || groupadd lpadmin
    usermod -aG lpadmin "${ADMIN_USER}"
    warn "User ${ADMIN_USER} may need to log out and back in for group changes to apply."
  else
    warn "User ${ADMIN_USER} does not exist; skipping lpadmin membership."
  fi
}

configure_samba() {
  local conf="/etc/samba/smb.conf"
  [[ -f "${conf}" ]] || { warn "${conf} not found; skipping Samba config."; return 0; }

  log "Configuring Samba printer sharing..."
  backup_file "${conf}"
  mkdir -p /var/spool/samba /var/lib/samba/printers
  chmod 1777 /var/spool/samba

  if ! grep -q '^\[printers\]' "${conf}"; then
    cat >> "${conf}" <<'SAMBA'

[printers]
   comment = All Printers
   path = /var/spool/samba
   printable = yes
   browseable = no
   guest ok = yes
   read only = yes
   create mask = 0700

[print$]
   comment = Printer Drivers
   path = /var/lib/samba/printers
   browseable = yes
   read only = yes
   guest ok = no
SAMBA
  fi

  if command_exists testparm; then
    testparm -s >/dev/null
  fi

  restart_service smbd.service
}

configure_firewall() {
  [[ "${CONFIG_FIREWALL}" == "1" ]] || { log "Skipping firewall changes."; return 0; }

  if command_exists ufw; then
    log "Opening CUPS and Samba ports with ufw..."
    ufw allow 631/tcp
    [[ "${INSTALL_SAMBA}" == "1" ]] && ufw allow samba
  elif command_exists firewall-cmd && systemctl is-active --quiet firewalld; then
    log "Opening CUPS and Samba ports with firewalld..."
    firewall-cmd --permanent --add-service=ipp
    [[ "${INSTALL_SAMBA}" == "1" ]] && firewall-cmd --permanent --add-service=samba
    firewall-cmd --reload
  else
    warn "No active ufw/firewalld detected; open TCP port 631 manually if needed."
  fi
}

print_summary() {
  local ip_addresses
  ip_addresses="$(hostname -I 2>/dev/null | xargs || true)"

  cat <<SUMMARY

Done.

Next steps:
  1. Open the CUPS web UI: http://localhost:631 or http://<SERVER_IP>:631
  2. Go to Administration -> Add Printer.
  3. Log in with a user in the lpadmin group.
  4. Enable "Share This Printer" and print a test page.

Detected server IP(s): ${ip_addresses:-unknown}
CUPS service: ${CUPS_SERVICE}
Admin user: ${ADMIN_USER:-not configured}
SUMMARY
}

main() {
  parse_args "$@"
  require_root
  detect_os

  log "Detected OS: ${OS_ID} ${OS_LIKE}"
  log "Installing CUPS..."
  mapfile -t cups_pkg_list < <(cups_packages)
  install_packages "${cups_pkg_list[@]}"

  select_cups_service
  enable_service "${CUPS_SERVICE}"
  configure_admin_user
  configure_cups

  if [[ "${INSTALL_SAMBA}" == "1" ]]; then
    log "Installing Samba..."
    install_packages samba
    configure_samba
  else
    log "Skipping Samba."
  fi

  if [[ "${INSTALL_AVAHI}" == "1" ]]; then
    log "Installing Avahi/Bonjour..."
    mapfile -t avahi_pkg_list < <(avahi_packages)
    install_packages "${avahi_pkg_list[@]}"
    enable_service avahi-daemon.service
  else
    log "Skipping Avahi."
  fi

  configure_firewall
  print_summary
}

main "$@"
