#!/usr/bin/env bash
# =============================================================================
# Linux Print Server - https://github.com/Huylighting/Linux-Print-server
#
#   1) Print server : CUPS + Samba + Avahi (+ tường lửa)
#   2) Driver       : Canon LBP2900 (CAPT) bằng captdriver, build từ mã nguồn
#   3) Gỡ lỗi       : chẩn đoán và sửa lỗi "nhận máy in nhưng không in"
#
# Hỗ trợ: Debian, Ubuntu, Armbian, Raspberry Pi OS, Fedora, Arch, openSUSE.
# Dùng:   sudo ./install.sh help
# =============================================================================
set -Eeuo pipefail

VERSION="2.0.0"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ME="./$(basename "$SCRIPT_PATH")"
ORIG_ARGS=("$@")

PRINTER_NAME="${PRINTER_NAME:-Canon-LBP2900}"
CAPT_REPO="${CAPT_REPO:-https://github.com/mounaiban/captdriver.git}"
SRC_DIR="${SRC_DIR:-/usr/local/src/captdriver}"
PPD_DEST_NAME="canon-lbp2900-captdriver.ppd"
CUPS_LOG="${CUPS_LOG:-/var/log/cups/error_log}"
WAIT="${WAIT:-90}"                       # số giây chờ job trong lệnh test
CANON_VID="04a9"

ADMIN_USER="${ADMIN_USER:-${SUDO_USER:-}}"
INSTALL_SAMBA="${INSTALL_SAMBA:-1}"
INSTALL_AVAHI="${INSTALL_AVAHI:-1}"
CONFIG_FIREWALL="${CONFIG_FIREWALL:-1}"
ENABLE_REMOTE="${ENABLE_REMOTE:-0}"
INSTALL_PRINTER_DRIVERS="${INSTALL_PRINTER_DRIVERS:-1}"

OS_ID="unknown"
OS_LIKE=""
CUPS_SERVICE="cups.service"
SAMBA_SERVICE="smbd.service"
AVAHI_SERVICE="avahi-daemon.service"
FILTER_DIR="/usr/lib/cups/filter"
MODEL_DIR="/usr/share/cups/model"

# ------------------------------------------------------------------ chung
log()  { printf '\033[1;32m[OK]\033[0m   %s\n' "$*"; }
info() { printf '\033[1;34m[...]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[CHÚ Ý]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[LỖI]\033[0m  %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

D_PASS=0; D_WARN=0; D_FAIL=0
d_ok()   { printf '  \033[1;32m✔\033[0m %s\n' "$*"; D_PASS=$((D_PASS + 1)); }
d_warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; D_WARN=$((D_WARN + 1)); }
d_bad()  { printf '  \033[1;31m✘\033[0m %s\n' "$*"; D_FAIL=$((D_FAIL + 1)); }
d_hint() { printf '      → %s\n' "$*"; }

ensure_root() {
  [[ "${EUID}" -eq 0 ]] && return 0
  have sudo || fail "Cần quyền root. Hãy chạy lại bằng: sudo $ME ${ORIG_ARGS[*]:-}"
  exec sudo -E bash "$SCRIPT_PATH" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
}

need_cups() {
  { have lpstat && have lp && have lpadmin; } || fail "Chưa cài CUPS (thiếu lp/lpstat/lpadmin). Chạy: sudo $ME server  hoặc  sudo $ME driver"
}

need_printer() {
  need_cups
  lpstat -p "$PRINTER_NAME" >/dev/null 2>&1 \
    || fail "Chưa có máy in '$PRINTER_NAME' trong CUPS. Chạy: sudo $ME driver  (hoặc sudo $ME add)"
}

cups_dirs() {
  if have cups-config; then
    FILTER_DIR="$(cups-config --serverbin)/filter"
    MODEL_DIR="$(cups-config --datadir)/model"
  fi
}

lan_ip() { hostname -I 2>/dev/null | awk '{print $1}'; }

detect_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
  fi
}

is_family() { [[ " ${OS_ID} ${OS_LIKE} " == *" $1 "* ]]; }

backup_file() {
  local file="$1" backup
  [[ -f "$file" ]] || return 0
  backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
  cp -a -- "$file" "$backup"
  log "Đã sao lưu $file thành $backup"
}

install_packages() {
  local packages=("$@")
  (("${#packages[@]}" > 0)) || return 0
  if have apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y -- "${packages[@]}"
  elif have dnf; then
    dnf install -y -- "${packages[@]}"
  elif have zypper; then
    zypper --non-interactive install -y -- "${packages[@]}"
  elif have pacman; then
    # Arch không hỗ trợ nâng cấp từng phần: phải đồng bộ cả hệ thống cùng lúc
    pacman -Syu --noconfirm --needed "${packages[@]}"
  else
    fail "Không nhận ra trình quản lý gói. Hãy cài thủ công: ${packages[*]}"
  fi
}

service_exists() { systemctl cat "$1" >/dev/null 2>&1; }

enable_service() {
  if service_exists "$1"; then systemctl enable --now "$1"
  else warn "Không tìm thấy dịch vụ $1; bỏ qua."; fi
}

restart_service() {
  if service_exists "$1"; then systemctl restart "$1"
  else warn "Không tìm thấy dịch vụ $1; bỏ qua restart."; fi
}

select_services() {
  CUPS_SERVICE="cups.service"
  AVAHI_SERVICE="avahi-daemon.service"
  if is_family rhel || is_family fedora || is_family suse; then SAMBA_SERVICE="smb.service"
  else SAMBA_SERVICE="smbd.service"; fi
}

# CUPS đang nghe cổng 631 ở đâu: none | local | lan
listen_scope() {
  local addrs
  addrs="$(ss -ltn 2>/dev/null | awk 'NR>1 {print $4}' | grep -E ':631$' || true)"
  if [[ -z "$addrs" ]]; then echo none; return; fi
  if printf '%s\n' "$addrs" | grep -vqE '^(127\.0\.0\.1|\[::1\]|::1):631$'; then echo lan; else echo local; fi
}

# Trạng thái ufw đối với cổng 631: ufw-open | ufw-closed | none
fw_state() {
  if have ufw && ufw status 2>/dev/null | grep -qi '^Status: active'; then
    if ufw status 2>/dev/null | grep -qE '(^|[^0-9])631(/|[[:space:]])'; then echo ufw-open; else echo ufw-closed; fi
  else
    echo none
  fi
}

# Log CUPS: dùng file nếu có, không thì journal
read_recent_log() {
  local n="${1:-2000}"
  if [[ -s "$CUPS_LOG" ]]; then tail -n "$n" "$CUPS_LOG" 2>/dev/null || true
  else journalctl -u cups --no-pager -n "$n" 2>/dev/null || true; fi
}

# Log phát sinh sau khi bắt đầu thử (cần LOG_START và T0 được đặt trước)
read_new_log() {
  if [[ -s "$CUPS_LOG" ]]; then tail -n +"$((LOG_START + 1))" "$CUPS_LOG" 2>/dev/null || true
  else journalctl -u cups --no-pager --since "@${T0}" 2>/dev/null || true; fi
}

usage() {
  cat <<EOF
Linux Print Server v${VERSION} - CUPS/Samba/Avahi + Canon LBP2900 (CAPT) + gỡ lỗi in

CÀI ĐẶT (cần root, tự gọi sudo)
  all [tuỳ chọn]       Cài tất cả: print server + driver Canon LBP2900 + thêm máy in + chia sẻ
  server [tuỳ chọn]    Chỉ cài print server: CUPS + Samba + Avahi + tường lửa
  driver               Chỉ cài driver Canon LBP2900 (build captdriver) và thêm máy in
  add [--uri URI]      Thêm/cập nhật máy in trong CUPS (tự tìm máy in USB Canon)
  uninstall [--purge]  Gỡ máy in + driver (--purge: xoá cả mã nguồn). Không gỡ CUPS/Samba/Avahi

GỠ LỖI (cần root)
  doctor               Chẩn đoán: USB, CUPS, driver, chia sẻ mạng, AppArmor/SELinux, log CAPT
  test [FILE]          In thử qua IPP (giống máy khách trong mạng), theo dõi job + lỗi CAPT
  fix [--apparmor-complain]
                       Đặt filter đúng chỗ, huỷ job kẹt, restart CUPS, bật lại hàng đợi
  reset-usb            "Rút/cắm" lại USB của máy in bằng phần mềm (chỉ thiết bị Canon)
  share                Bật chia sẻ qua LAN, in địa chỉ để thêm vào Windows/Mac
  debug on|off         Bật/tắt log chi tiết của CUPS (nhớ tắt sau khi lấy log)
  bundle               Gói thông tin chẩn đoán vào .tar.gz để gửi nhờ phân tích

LỆNH THƯỜNG
  print FILE...        In file  [-n SỐ_BẢN] [-r TRANG, vd 1-3,5] [--fit] [-p TÊN_MÁY_IN]
  status               Xem nhanh trạng thái USB / CUPS / hàng đợi
  gui                  Chọn file bằng hộp thoại (cần zenity)

TUỲ CHỌN cho 'server' và 'all'
  --admin-user USER    Người dùng thêm vào nhóm quản trị CUPS (mặc định: người gọi sudo)
  --no-samba           Bỏ qua Samba
  --no-avahi           Bỏ qua Avahi/Bonjour
  --no-firewall        Không đổi luật tường lửa
  --remote-access      Cho in qua nhiều dải mạng (chỉ dùng trong LAN tin cậy)
  --printer-drivers    Cài thêm printer-driver-all (apt, rất nặng). 'server' mặc định cài, 'all' mặc định bỏ
  --no-printer-drivers Không cài printer-driver-all

Chạy không tham số trong terminal sẽ mở menu.
Biến môi trường: PRINTER_NAME (${PRINTER_NAME}), SRC_DIR (thư mục mã nguồn captdriver),
                 WAIT (giây chờ khi test), CUPS_LOG, CAPT_REPO
Tương thích bản cũ: './install.sh --no-samba ...' vẫn chạy như './install.sh server --no-samba ...'
EOF
}

# =============================================================================
# PHẦN 1: PRINT SERVER (CUPS + Samba + Avahi + tường lửa)
# =============================================================================
server_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --admin-user) [[ $# -ge 2 && -n "${2:-}" ]] || fail "--admin-user cần một tên người dùng."
                    ADMIN_USER="$2"; shift 2 ;;
      --no-samba)  INSTALL_SAMBA=0; shift ;;
      --no-avahi)  INSTALL_AVAHI=0; shift ;;
      --no-firewall) CONFIG_FIREWALL=0; shift ;;
      --remote-access) ENABLE_REMOTE=1; shift ;;
      --printer-drivers) INSTALL_PRINTER_DRIVERS=1; shift ;;
      --no-printer-drivers) INSTALL_PRINTER_DRIVERS=0; shift ;;
      *) fail "Tuỳ chọn lạ: $1 (xem: $ME help)" ;;
    esac
  done
}

cups_packages() {
  if have apt-get; then
    printf '%s\n' cups cups-client cups-filters
    [[ "$INSTALL_PRINTER_DRIVERS" == "1" ]] && printf '%s\n' printer-driver-all
  elif have dnf || have zypper; then
    printf '%s\n' cups cups-client cups-filters
  else
    printf '%s\n' cups cups-filters
  fi
  return 0
}

avahi_packages() {
  if is_family arch; then printf '%s\n' avahi nss-mdns
  elif have apt-get; then printf '%s\n' avahi-daemon
  else printf '%s\n' avahi; fi
}

configure_admin_user() {
  [[ -n "$ADMIN_USER" && "$ADMIN_USER" != "root" ]] || return 0
  if id "$ADMIN_USER" >/dev/null 2>&1; then
    getent group lpadmin >/dev/null 2>&1 || groupadd lpadmin
    usermod -aG lpadmin "$ADMIN_USER"
    warn "Người dùng $ADMIN_USER có thể cần đăng xuất/đăng nhập lại để nhóm lpadmin có hiệu lực."
  else
    warn "Người dùng $ADMIN_USER không tồn tại; bỏ qua nhóm lpadmin."
  fi
}

configure_cups() {
  [[ -f /etc/cups/cupsd.conf ]] || fail "Không thấy /etc/cups/cupsd.conf sau khi cài CUPS."
  have cupsctl || fail "Thiếu cupsctl; kiểm tra gói CUPS client."
  log "Bật chia sẻ máy in với cấu hình thận trọng..."
  cupsctl --share-printers || fail "Không bật được chia sẻ máy in trong CUPS."
  if [[ "$ENABLE_REMOTE" == "1" ]]; then
    warn "Bật in qua nhiều dải mạng. Luật tường lửa sẽ giới hạn trong dải IPv4 riêng tư (nếu hỗ trợ)."
    cupsctl --remote-any || fail "Không bật được remote-any."
  else
    cupsctl --no-remote-any || true
    log "In qua nhiều dải mạng vẫn TẮT."
  fi
  restart_service "$CUPS_SERVICE"
}

ensure_samba_section() {
  local conf="$1" section="$2" body="$3"
  if ! awk -v wanted="[$section]" '{ line=$0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line); if (line == wanted) found=1 } END { exit(found ? 0 : 1) }' "$conf"; then
    printf '\n%s\n' "$body" >> "$conf"
    log "Đã thêm mục Samba [$section]."
  else
    warn "Mục Samba [$section] đã có; giữ nguyên cấu hình của quản trị viên."
  fi
}

configure_samba() {
  local conf="/etc/samba/smb.conf"
  [[ -f "$conf" ]] || { warn "Không thấy $conf; bỏ qua cấu hình Samba."; return 0; }
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

  if have testparm; then testparm -s "$conf" >/dev/null || fail "Cấu hình Samba không hợp lệ."
  else warn "Không có testparm; chưa kiểm tra được cấu hình Samba."; fi
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
  # Chỉ áp dụng cho giao diện tailscale0, không phải mọi giao diện dùng 100.64.0.0/10
  if ip link show tailscale0 >/dev/null 2>&1; then
    ufw allow in on tailscale0 to any port "$port" proto "$proto" >/dev/null
  else
    warn "Không có tailscale0; bỏ qua luật ufw Tailscale cho $proto/$port."
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
  firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"100.64.0.0/10\" port port=\"$port\" protocol=\"$proto\" accept" >/dev/null
}

configure_firewall() {
  [[ "$CONFIG_FIREWALL" == "1" ]] || { log "Bỏ qua thay đổi tường lửa."; return 0; }
  local port
  if have ufw && ufw status | grep -q '^Status: active'; then
    log "Giới hạn luật tường lửa trong dải IPv4 riêng tư..."
    ufw_allow_private tcp 631
    ufw_allow_tailscale tcp 631
    if [[ "$INSTALL_SAMBA" == "1" ]]; then
      for port in 137 138; do ufw_allow_private udp "$port"; ufw_allow_tailscale udp "$port"; done
      for port in 139 445; do ufw_allow_private tcp "$port"; ufw_allow_tailscale tcp "$port"; done
    fi
  elif have firewall-cmd && systemctl is-active --quiet firewalld; then
    log "Giới hạn luật tường lửa trong dải IPv4 riêng tư..."
    firewalld_allow_private tcp 631
    firewalld_allow_tailscale tcp 631
    if [[ "$INSTALL_SAMBA" == "1" ]]; then
      for port in 137 138; do firewalld_allow_private udp "$port"; firewalld_allow_tailscale udp "$port"; done
      for port in 139 445; do firewalld_allow_private tcp "$port"; firewalld_allow_tailscale tcp "$port"; done
    fi
    firewall-cmd --reload
  else
    warn "Không có UFW/firewalld đang bật nên không đổi luật nào. Hãy tự kiểm tra tường lửa máy/router trước khi mở truy cập từ xa."
  fi
}

run_server_install() {
  detect_os
  select_services
  log "Hệ điều hành: $OS_ID ${OS_LIKE}"
  log "Cài CUPS..."
  local cups_pkg_list avahi_pkg_list
  mapfile -t cups_pkg_list < <(cups_packages)
  install_packages "${cups_pkg_list[@]}"
  enable_service "$CUPS_SERVICE"
  configure_admin_user
  configure_cups

  if [[ "$INSTALL_SAMBA" == "1" ]]; then
    log "Cài Samba..."
    install_packages samba
    configure_samba
  else
    log "Bỏ qua Samba."
  fi

  if [[ "$INSTALL_AVAHI" == "1" ]]; then
    log "Cài Avahi/Bonjour..."
    mapfile -t avahi_pkg_list < <(avahi_packages)
    install_packages "${avahi_pkg_list[@]}"
    enable_service "$AVAHI_SERVICE"
  else
    log "Bỏ qua Avahi."
  fi
  configure_firewall
}

cmd_server() {
  server_parse_args "$@"
  run_server_install
  cat <<SUMMARY

Đã xong các bước cài print server (script chưa kiểm tra phần cứng máy in).

Bước tiếp theo:
  1. Có máy in Canon LBP2900?  Chạy:  sudo $ME driver
  2. Máy in khác: mở http://localhost:631 > Administration > Add Printer
  3. Đánh dấu hàng đợi là "shared" trước khi máy khách kết nối
  4. Truy cập từ xa mặc định TẮT. Không mở TCP 631 ra Internet.

IP máy chủ: $(lan_ip || true)
Dịch vụ: CUPS=${CUPS_SERVICE}  Samba=${SAMBA_SERVICE}  Avahi=${AVAHI_SERVICE}
Người quản trị: ${ADMIN_USER:-chưa cấu hình}
SUMMARY
}

# =============================================================================
# PHẦN 2: DRIVER CANON LBP2900 (captdriver)
# =============================================================================
build_packages() {
  if have apt-get; then
    printf '%s\n' git build-essential autoconf automake libtool pkg-config libcups2-dev usbutils
    # Tuỳ phiên bản, libcupsimage nằm ở gói riêng hoặc đã gộp vào libcups2-dev
    if apt-cache show libcupsimage2-dev >/dev/null 2>&1; then printf '%s\n' libcupsimage2-dev; fi
  elif have dnf; then
    printf '%s\n' git gcc make autoconf automake libtool pkgconf-pkg-config cups-devel usbutils
  elif have zypper; then
    printf '%s\n' git gcc make autoconf automake libtool pkg-config cups-devel usbutils
  elif have pacman; then
    printf '%s\n' git base-devel usbutils
  fi
}

fetch_source() {
  if [[ -d "$SRC_DIR/.git" ]]; then
    if [[ -n "$(git -C "$SRC_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
      info "Mã nguồn tại $SRC_DIR có sửa đổi cục bộ: giữ nguyên, không cập nhật."
    else
      info "Cập nhật mã nguồn captdriver tại $SRC_DIR ..."
      git -C "$SRC_DIR" pull --ff-only || warn "Không cập nhật được, dùng bản hiện có."
    fi
  elif [[ -f "$SRC_DIR/configure.ac" || -f "$SRC_DIR/configure" ]]; then
    info "Dùng mã nguồn có sẵn tại $SRC_DIR"
  else
    info "Tải captdriver từ $CAPT_REPO ..."
    mkdir -p "$(dirname "$SRC_DIR")"
    git clone --depth 1 "$CAPT_REPO" "$SRC_DIR" \
      || fail "Không tải được mã nguồn. Kiểm tra mạng, hoặc đặt SRC_DIR tới thư mục captdriver có sẵn."
  fi
}

build_driver() {
  info "Biên dịch driver..."
  ( cd "$SRC_DIR"
    if [[ ! -x ./configure ]]; then autoreconf -fi; fi
    ./configure
    make -j"$(nproc)"
    # File PPD chỉ được sinh ra khi chạy 'make ppd'
    make ppd || warn "'make ppd' không chạy được; sẽ tìm PPD có sẵn trong mã nguồn." )
  FILTER_BIN="$(find "$SRC_DIR" -type f -name rastertocapt -perm -u+x 2>/dev/null | head -n1 || true)"
  [[ -n "$FILTER_BIN" ]] || fail "Build xong nhưng không thấy file 'rastertocapt'. Xem log phía trên."
  log "Build thành công: $FILTER_BIN"
}

install_driver_files() {
  cups_dirs
  mkdir -p "$MODEL_DIR"
  install -D -m 0755 -o root -g root "$FILTER_BIN" "$FILTER_DIR/rastertocapt"
  log "Đã cài filter vào $FILTER_DIR/rastertocapt"
  if have restorecon; then restorecon -v "$FILTER_DIR/rastertocapt" >/dev/null 2>&1 || true; fi

  local ppd
  ppd="$(find "$SRC_DIR" -type f -iname '*2900*.ppd' 2>/dev/null | head -n1 || true)"
  if [[ -z "$ppd" ]]; then
    ppd="$(grep -rl --include='*.ppd' 'rastertocapt' "$SRC_DIR" 2>/dev/null | head -n1 || true)"
    if [[ -n "$ppd" ]]; then warn "Không có PPD riêng cho 2900, dùng tạm: $(basename "$ppd")"; fi
  fi
  [[ -n "$ppd" ]] || fail "Không tìm thấy file PPD (sinh bởi 'make ppd') trong $SRC_DIR."
  install -m 0644 -o root -g root "$ppd" "$MODEL_DIR/$PPD_DEST_NAME"
  log "Đã cài PPD ($(basename "$ppd")) vào $MODEL_DIR/$PPD_DEST_NAME"
}

find_uri() {
  local out
  out="$(lpinfo -v 2>/dev/null || true)"
  printf '%s\n' "$out" | awk '$2 ~ /^usb:\/\// && tolower($2) ~ /lbp.?2900/ {print $2; exit}' | grep . \
    || printf '%s\n' "$out" | awk '$2 ~ /^usb:\/\// && tolower($2) ~ /canon/ {print $2; exit}'
}

add_printer() {
  local uri="${1:-}"
  cups_dirs
  [[ -f "$MODEL_DIR/$PPD_DEST_NAME" ]] || fail "Chưa cài driver. Hãy chạy: sudo $ME driver"
  restart_service "$CUPS_SERVICE"; sleep 2
  if [[ -z "$uri" ]]; then uri="$(find_uri || true)"; fi
  if [[ -z "$uri" ]]; then
    warn "Không thấy máy in Canon qua USB."
    echo "  - Bật nguồn máy in, cắm cáp USB (thử cổng USB 2.0, cáp ngắn)"
    echo "  - Kiểm tra: lsusb | grep -i canon"
    echo "  - Sau đó chạy lại: sudo $ME add"
    return 1
  fi
  info "Thiết bị: $uri"
  # Không xoá hàng đợi cũ: lpadmin -p cập nhật tại chỗ, giữ nguyên cài đặt chia sẻ
  lpadmin -p "$PRINTER_NAME" -E -v "$uri" -P "$MODEL_DIR/$PPD_DEST_NAME" -o printer-error-policy=retry-job
  if ! lpstat -d 2>/dev/null | grep -q 'system default destination:'; then
    lpadmin -d "$PRINTER_NAME"
    log "Đã đặt '$PRINTER_NAME' làm máy in mặc định."
  fi
  log "Máy in '$PRINTER_NAME' đã sẵn sàng."
}

cmd_driver() {
  detect_os
  select_services
  info "Cài CUPS và gói cần để build driver..."
  local pkgs
  INSTALL_PRINTER_DRIVERS=0
  mapfile -t pkgs < <({ cups_packages; build_packages; } | sort -u)
  install_packages "${pkgs[@]}"
  enable_service "$CUPS_SERVICE"
  fetch_source
  build_driver
  install_driver_files
  configure_admin_user
  restart_service "$CUPS_SERVICE"
  add_printer "" || warn "Driver đã cài; hãy cắm máy in rồi chạy: sudo $ME add"
  echo
  log "Hoàn tất. Thử in: sudo $ME test"
}

cmd_all() {
  INSTALL_PRINTER_DRIVERS=0
  server_parse_args "$@"
  run_server_install
  cmd_driver
  if lpstat -p "$PRINTER_NAME" >/dev/null 2>&1; then cmd_share
  else warn "Chưa có máy in '$PRINTER_NAME' (chưa thấy máy in USB). Cắm máy in rồi chạy: sudo $ME add && sudo $ME share"; fi
}

cmd_add() {
  local uri=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --uri) [[ -n "${2:-}" ]] || fail "--uri cần giá trị."; uri="$2"; shift 2 ;;
      *) fail "Tham số lạ: $1" ;;
    esac
  done
  need_cups
  add_printer "$uri"
}

cmd_uninstall() {
  need_cups
  local purge=0
  if [[ "${1:-}" == "--purge" ]]; then purge=1; fi
  cups_dirs
  lpadmin -x "$PRINTER_NAME" 2>/dev/null || true
  rm -f "$FILTER_DIR/rastertocapt" "$MODEL_DIR/$PPD_DEST_NAME"
  if [[ "$purge" == 1 ]]; then rm -rf "$SRC_DIR"; fi
  restart_service "$CUPS_SERVICE" || true
  log "Đã gỡ máy in và driver (CUPS/Samba/Avahi vẫn giữ nguyên)."
}

# =============================================================================
# PHẦN 3: GỠ LỖI
# =============================================================================
cmd_doctor() {
  need_cups
  D_PASS=0; D_WARN=0; D_FAIL=0
  cups_dirs

  echo "== 1. Hệ thống =="
  local arch pretty
  arch="$(uname -m)"
  pretty="$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}")"
  d_ok "$pretty ($arch)"
  if [[ -f /etc/armbian-release ]]; then
    d_ok "Armbian, bo mạch: $(. /etc/armbian-release 2>/dev/null; printf '%s' "${BOARD_NAME:-${BOARD:-không rõ}}")"
  fi
  if [[ "$arch" == arm* || "$arch" == aarch64 ]] && [[ "$(getconf LONG_BIT 2>/dev/null)" == "32" ]]; then
    d_warn "ARM 32-bit (armhf): captdriver được báo lỗi 'bad reply from printer' trên armhf"
    d_hint "Dùng hệ điều hành 64-bit (aarch64) nếu bo mạch hỗ trợ (captdriver issue #8)"
  fi

  echo "== 2. Kết nối USB =="
  local usbline uri
  usbline="$(lsusb 2>/dev/null | grep -i "$CANON_VID" | head -n1 || true)"
  if [[ -n "$usbline" ]]; then d_ok "Thấy thiết bị Canon: $usbline"
  else
    d_bad "Không thấy thiết bị Canon (mã hãng $CANON_VID) trên USB"
    d_hint "Bật nguồn máy in, thử cáp USB khác/ngắn hơn, cổng USB 2.0; hoặc: sudo $ME reset-usb"
  fi
  uri="$(find_uri || true)"
  if [[ -n "$uri" ]]; then d_ok "CUPS thấy máy in: $uri"
  else
    d_bad "CUPS không liệt kê thiết bị usb:// của Canon (lpinfo -v)"
    d_hint "Tắt máy in 5 giây rồi bật lại, rút/cắm USB, sau đó chạy lại doctor"
  fi

  echo "== 3. CUPS =="
  if systemctl is-active --quiet cups 2>/dev/null; then d_ok "cups đang chạy"
  else d_bad "cups không chạy"; d_hint "systemctl restart cups"; fi
  local cv
  cv="$(cups-config --version 2>/dev/null || true)"
  if [[ -n "$cv" ]]; then
    if [[ "$(printf '%s\n%s\n' 2.4.17 "$cv" | sort -V | head -n1)" == "2.4.17" ]]; then
      d_ok "CUPS $cv (từ 2.4.17 trở lên)"
    else
      d_warn "CUPS $cv thấp hơn 2.4.17: bản cũ có thể dính lỗi tranh chấp USB làm job kẹt (Debian có thể đã backport bản vá)"
      d_hint "Cập nhật gói CUPS (apt update && apt upgrade) hoặc dùng bản từ backports"
    fi
  fi

  echo "== 4. Driver =="
  if [[ -x "$FILTER_DIR/rastertocapt" ]]; then d_ok "filter: $FILTER_DIR/rastertocapt"
  else d_bad "thiếu filter rastertocapt trong $FILTER_DIR"; d_hint "sudo $ME driver  (hoặc sudo $ME fix)"; fi
  if [[ -e /usr/local/bin/rastertocapt ]]; then
    d_warn "Có /usr/local/bin/rastertocapt (từ 'make install'); trên Debian 13 AppArmor chặn đường dẫn này"
    d_hint "sudo $ME fix sẽ dùng bản trong $FILTER_DIR"
  fi
  if [[ -f "$MODEL_DIR/$PPD_DEST_NAME" ]]; then d_ok "PPD: $MODEL_DIR/$PPD_DEST_NAME"
  else d_bad "thiếu PPD"; d_hint "sudo $ME driver"; fi

  echo "== 5. Máy in trong CUPS =="
  if lpstat -p "$PRINTER_NAME" >/dev/null 2>&1; then
    local line dev jobs
    line="$(lpstat -p "$PRINTER_NAME" 2>/dev/null | head -n1 || true)"
    case "$line" in
      *disabled*) d_bad "Máy in đang bị tắt trong CUPS: $line"; d_hint "cupsenable $PRINTER_NAME  (hoặc sudo $ME fix)" ;;
      *) d_ok "$line" ;;
    esac
    dev="$(lpstat -v "$PRINTER_NAME" 2>/dev/null || true)"
    case "$dev" in
      *usb://*) d_ok "$dev" ;;
      *) d_warn "URI không phải usb://: ${dev:-không rõ}"; d_hint "sudo $ME add" ;;
    esac
    jobs="$(lpstat -o "$PRINTER_NAME" 2>/dev/null || true)"
    if [[ -n "$jobs" ]]; then
      d_warn "Có job đang chờ hoặc kẹt:"; printf '      %s\n' "$jobs"
      d_hint "sudo $ME fix  (huỷ job và khởi động lại CUPS)"
    else
      d_ok "Hàng đợi trống"
    fi
  else
    d_bad "Chưa có máy in '$PRINTER_NAME' trong CUPS"; d_hint "sudo $ME add"
  fi

  echo "== 6. Chia sẻ qua mạng (in từ máy khác) =="
  if have ipptool && [[ -r /usr/share/cups/ipptool/get-printer-attributes.test ]]; then
    if ipptool -tv "ipp://localhost:631/printers/${PRINTER_NAME}" get-printer-attributes.test 2>/dev/null \
         | grep -q 'printer-is-shared (boolean) = true'; then
      d_ok "Máy in đã được chia sẻ (printer-is-shared=true)"
    else
      d_bad "Máy in CHƯA được chia sẻ"; d_hint "sudo $ME share"
    fi
  else
    d_warn "Không có ipptool nên không kiểm tra được trạng thái chia sẻ"
  fi
  case "$(listen_scope)" in
    lan)   d_ok "CUPS nghe cổng 631 trên mạng LAN" ;;
    local) d_bad "CUPS chỉ nghe ở localhost nên máy khác không kết nối được"; d_hint "sudo $ME share" ;;
    none)  d_bad "Không có gì nghe cổng 631"; d_hint "systemctl status cups" ;;
  esac
  case "$(fw_state)" in
    ufw-closed) d_warn "ufw đang bật nhưng chưa thấy luật cho cổng 631"
                d_hint "sudo $ME server  (thêm luật cho dải LAN), hoặc: sudo ufw allow from <dải_LAN> to any port 631 proto tcp" ;;
    ufw-open)   d_ok "ufw đã cho phép cổng 631" ;;
    none)       d_ok "Không có ufw chặn (nếu dùng nftables/iptables hãy tự kiểm tra)" ;;
  esac

  echo "== 7. AppArmor / SELinux =="
  local denied
  denied="$( { journalctl -k --no-pager -n 3000 2>/dev/null
               dmesg 2>/dev/null
               tail -n 3000 /var/log/audit/audit.log 2>/dev/null; } \
             | grep -iE 'apparmor="DENIED"|avc: +denied' | grep -iE 'cupsd|rastertocapt|capt' | tail -n 3 || true)"
  if [[ -n "$denied" ]]; then
    d_bad "AppArmor/SELinux đã CHẶN cupsd hoặc filter CAPT (AppArmor hay gặp trên Debian 13):"
    printf '%s\n' "$denied" | cut -c1-200 | sed 's/^/      /'
    d_hint "Bước 1: sudo $ME fix  (đặt filter vào thư mục chuẩn rồi in thử lại)"
    d_hint "Bước 2, nếu vẫn bị AppArmor chặn: sudo $ME fix --apparmor-complain  (cách tạm, làm lỏng bảo vệ cupsd)"
    d_hint "SELinux (Fedora/openSUSE): fix đã chạy restorecon; xem thêm: sudo ausearch -m avc -ts recent"
  elif have aa-status && aa-status --enabled 2>/dev/null; then
    d_ok "AppArmor đang bật, chưa thấy log chặn gần đây"
    d_hint "Nếu in vẫn lỗi: in thử một trang rồi chạy lại doctor để bắt log mới"
  else
    d_ok "AppArmor/SELinux không chặn"
  fi

  echo "== 8. Module usblp =="
  if [[ -d /sys/module/usblp ]]; then
    d_warn "usblp đang nạp; có thể tranh thiết bị với backend USB của CUPS"
    d_hint "Chỉ khi job vẫn kẹt: modprobe -r usblp  (hoàn tác bằng khởi động lại máy)"
  else
    d_ok "usblp không nạp"
  fi

  echo "== 9. Lỗi CAPT gần đây =="
  local recent errs
  recent="$(read_recent_log 3000)"
  errs="$(grep -iE 'CAPT|rastertocapt|no reply from printer|USB transaction timeout|Filter failed|Backend returned status' <<<"$recent" | tail -n 6 || true)"
  if [[ -z "$errs" ]]; then
    d_ok "Không thấy lỗi CAPT/USB gần đây (nếu log CUPS ở mức thấp, dùng: sudo $ME debug on)"
  else
    d_warn "Thông báo gần nhất:"
    printf '%s\n' "$errs" | cut -c1-200 | sed 's/^/      /'
    case "$errs" in
      *"no reply from printer"*) d_bad "'no reply from printer': máy in không trả lời lệnh CAPT qua USB (lỗi tầng USB/CAPT, không phải do mạng)"
                                 d_hint "sudo $ME reset-usb  (hoặc tắt máy in 10 giây rồi bật lại), sau đó sudo $ME test" ;;
    esac
    case "$errs" in
      *"bad reply"*) d_hint "'bad reply from printer': tắt máy in, chờ 5 giây, bật lại; thử bản 64-bit và CUPS mới" ;;
    esac
    case "$errs" in
      *"Unable to communicate"*) d_hint "'Unable to communicate': kiểm tra cáp USB và quyền truy cập, rồi tắt/bật máy in" ;;
    esac
  fi

  echo
  printf 'Kết quả: %d đạt, %d cảnh báo, %d lỗi\n' "$D_PASS" "$D_WARN" "$D_FAIL"
  echo "Lưu ý: LBP2900 với captdriver được báo cáo là in tốt ngay sau khi bật nguồn, hoặc treo sau một job."
  echo "Nếu không có lỗi nào ở trên mà vẫn không in: tắt/bật máy in giữa các lần in."
  if (( D_FAIL > 0 )); then echo "Gợi ý: sudo $ME fix  rồi  sudo $ME doctor  lại."; fi
  return 0
}

cmd_fix() {
  local complain=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apparmor-complain) complain=1; shift ;;
      *) fail "Tham số lạ: $1" ;;
    esac
  done
  cups_dirs

  # 1. Filter phải nằm trong thư mục filter chuẩn của CUPS (không phải /usr/local/bin)
  if [[ ! -x "$FILTER_DIR/rastertocapt" ]]; then
    local cand=""
    for cand in /usr/local/bin/rastertocapt \
                "$(find "$SRC_DIR" -type f -name rastertocapt -perm -u+x 2>/dev/null | head -n1)"; do
      if [[ -n "$cand" && -x "$cand" ]]; then
        install -D -m 0755 -o root -g root "$cand" "$FILTER_DIR/rastertocapt"
        log "Đã chép filter từ $cand vào $FILTER_DIR/rastertocapt"
        break
      fi
    done
  fi
  if [[ -e "$FILTER_DIR/rastertocapt" ]]; then
    chown root:root "$FILTER_DIR/rastertocapt"
    chmod 0755 "$FILTER_DIR/rastertocapt"
    if have restorecon; then restorecon -v "$FILTER_DIR/rastertocapt" || true; fi
  else
    warn "Chưa có filter rastertocapt. Chạy: sudo $ME driver"
  fi

  # 2. Huỷ job kẹt (chỉ của máy in này), restart CUPS, bật lại hàng đợi
  info "Huỷ các job đang kẹt của $PRINTER_NAME..."
  cancel -a "$PRINTER_NAME" 2>/dev/null || true
  info "Restart CUPS..."
  restart_service "$CUPS_SERVICE"; sleep 2
  cupsaccept "$PRINTER_NAME" 2>/dev/null || true
  cupsenable "$PRINTER_NAME" 2>/dev/null || true

  # 3. AppArmor (chỉ khi người dùng yêu cầu, vì làm lỏng bảo vệ của cupsd)
  if (( complain )); then
    have aa-complain || { info "Cài apparmor-utils..."; install_packages apparmor-utils; }
    aa-complain /usr/sbin/cupsd
    warn "cupsd đang ở chế độ 'complain' (chỉ ghi log, không chặn). Hoàn tác: sudo aa-enforce /usr/sbin/cupsd"
    restart_service "$CUPS_SERVICE"
  fi

  log "Xong bước sửa tự động."
  lpstat -p "$PRINTER_NAME" 2>/dev/null || true
  echo "  Tiếp theo: tắt máy in 5 giây rồi bật lại (hoặc sudo $ME reset-usb), chạy 'sudo $ME test', rồi 'sudo $ME doctor' nếu vẫn không ra giấy."
}

cmd_reset_usb() {
  local d name n=0
  for d in /sys/bus/usb/devices/*; do
    [[ -r "$d/idVendor" ]] || continue
    [[ "$(<"$d/idVendor")" == "$CANON_VID" ]] || continue
    name="$(basename "$d")"
    if [[ ! -w "$d/authorized" ]]; then
      warn "Không ghi được $d/authorized; hãy tắt/bật nguồn máy in thủ công."
      continue
    fi
    info "Reset thiết bị USB Canon $name (ID ${CANON_VID}:$(<"$d/idProduct")); không đụng tới thiết bị khác"
    echo 0 > "$d/authorized"; sleep 2
    echo 1 > "$d/authorized"; sleep 3
    n=$((n + 1))
  done
  (( n > 0 )) || fail "Không thấy thiết bị USB hãng Canon ($CANON_VID). Kiểm tra nguồn và cáp."
  cupsenable "$PRINTER_NAME" 2>/dev/null || true
  log "Đã reset USB. Thử lại ngay: sudo $ME test"
}

cmd_share() {
  need_printer
  info "Bật chia sẻ máy in trong CUPS..."
  cupsctl --share-printers
  lpadmin -p "$PRINTER_NAME" -o printer-is-shared=true
  restart_service "$CUPS_SERVICE"
  sleep 2

  case "$(listen_scope)" in
    lan)   log "CUPS đang nghe cổng 631 trên mạng LAN." ;;
    local) warn "CUPS vẫn chỉ nghe ở localhost. Kiểm tra /etc/cups/cupsd.conf (dòng Listen/Port)." ;;
    none)  warn "Không thấy tiến trình nào nghe cổng 631. Xem: systemctl status cups" ;;
  esac
  case "$(fw_state)" in
    ufw-closed) warn "ufw đang bật nhưng chưa mở cổng 631. Lệnh này KHÔNG tự sửa tường lửa."
                echo "  Mở cho mạng nội bộ bằng: sudo $ME server --no-samba --no-avahi"
                echo "  hoặc thủ công (đổi dải IP cho đúng): sudo ufw allow from 192.168.0.0/16 to any port 631 proto tcp" ;;
    ufw-open)   log "ufw đã cho phép cổng 631." ;;
    none)       info "Không thấy ufw đang bật (nếu dùng nftables/iptables thì tự kiểm tra cổng 631)." ;;
  esac

  local ip; ip="$(lan_ip)"
  echo
  log "Địa chỉ máy in để thêm vào máy khách:"
  echo "  Windows: Cài đặt > Máy in > Thêm > 'Máy in tôi muốn không có trong danh sách'"
  echo "           > 'Chọn máy in dùng chung theo tên' và nhập:"
  echo "           http://${ip:-IP_CUA_SERVER}:631/printers/${PRINTER_NAME}"
  echo "           Driver chọn: Microsoft IPP Class Driver (hoặc 'Generic')"
  echo "  Mac/Linux/Android: ipp://${ip:-IP_CUA_SERVER}:631/printers/${PRINTER_NAME}"
  echo
  echo "Bước tiếp theo: sudo $ME test   (kiểm tra job qua IPP trước khi thử từ máy khách)"
}

cmd_test() {
  need_printer
  local file="${1:-}" tmpf=""
  if [[ -z "$file" ]]; then
    for file in /usr/share/cups/data/default-testpage.pdf /usr/share/cups/data/testprint; do
      [[ -r "$file" ]] && break
      file=""
    done
  fi
  if [[ -z "$file" ]]; then
    tmpf="$(mktemp)"
    printf 'Canon LBP2900 - trang in thu\nNgay: %s\nMay chu: %s\n' "$(date)" "$(hostname)" > "$tmpf"
    file="$tmpf"
  fi
  [[ -r "$file" ]] || fail "Không đọc được file: $file"

  T0="$(date +%s)"
  LOG_START="$(wc -l < "$CUPS_LOG" 2>/dev/null || echo 0)"

  info "Gửi job qua IPP (localhost:631), cùng đường với máy khách trong mạng..."
  info "File: $file"
  local out jobid=""
  out="$(lp -h localhost:631 -d "$PRINTER_NAME" -t "test" -- "$file" 2>&1)" \
    || { [[ -n "$tmpf" ]] && rm -f "$tmpf"; fail "Không gửi được job: $out"; }
  [[ -n "$tmpf" ]] && rm -f "$tmpf"
  jobid="$(printf '%s\n' "$out" | sed -nE 's/^request id is .*-([0-9]+) .*/\1/p' | head -n1)"
  info "$out"

  local waited=0 finished=0
  if [[ -z "$jobid" ]]; then
    warn "Không đọc được số job; chờ 20 giây rồi kiểm tra log."
    sleep 20; finished=1
  else
    while (( waited < WAIT )); do
      if ! lpstat -h localhost:631 -W not-completed -o "$PRINTER_NAME" 2>/dev/null \
           | grep -q "^${PRINTER_NAME}-${jobid} "; then
        finished=1; break
      fi
      sleep 2; waited=$((waited + 2))
    done
  fi
  sleep 2

  local newlog
  newlog="$(read_new_log)"
  echo
  echo "== Log CUPS liên quan trong lúc thử =="
  printf '%s\n' "$newlog" | grep -iE 'CAPT|rastertocapt|usb|timeout|Filter|Backend|apparmor' \
    | tail -n 14 | cut -c1-220 | sed 's/^/  /' || true
  echo

  local rc=0
  if grep -q 'no reply from printer' <<<"$newlog"; then
    rc=1
    d_bad "KẾT QUẢ: lỗi 'no reply from printer'. Máy in không trả lời lệnh CAPT qua USB."
    echo "  Job đã đi qua CUPS tới tận driver, nên lỗi ở tầng USB/CAPT chứ không phải do mạng."
    echo "  Thử lần lượt:"
    echo "   1) sudo $ME reset-usb   (hoặc tắt nguồn máy in 10 giây rồi bật lại)"
    echo "   2) sudo $ME test        (in lại ngay sau khi reset)"
    echo "   3) Nếu job đầu in được mà job thứ hai lỗi: driver không nhả máy in sau job (captdriver issue #14)"
    echo "   4) Vẫn lỗi: sudo $ME debug on, chạy lại test, rồi sudo $ME bundle và gửi file gói"
  elif grep -qE 'Filter failed|Backend returned status' <<<"$newlog"; then
    rc=1
    d_bad "KẾT QUẢ: job lỗi ở filter hoặc backend. Xem log phía trên."
    echo "  Chạy: sudo $ME debug on, thử lại, rồi sudo $ME bundle"
  elif (( finished == 0 )); then
    rc=1
    d_warn "KẾT QUẢ: job vẫn còn trong hàng đợi sau ${WAIT} giây."
    lpstat -l -o "$PRINTER_NAME" 2>/dev/null | sed 's/^/  /' || true
    echo "  Thử: sudo $ME reset-usb, hoặc huỷ job: cancel -a $PRINTER_NAME"
  else
    d_ok "KẾT QUẢ: job đã rời hàng đợi và không thấy lỗi CAPT. Hãy xem máy in đã ra giấy chưa."
    echo "  Nếu ra giấy mà máy khách (Windows) vẫn không in được: lỗi nằm ở phía máy khách"
    echo "  (cách thêm máy in, driver, hoặc định dạng job). Chạy: sudo $ME debug on,"
    echo "  in từ máy khách, rồi sudo $ME bundle để xem job do máy khách gửi."
  fi
  return "$rc"
}

cmd_debug() {
  need_cups
  case "${1:-}" in
    on)  cupsctl --debug-logging
         log "Đã bật log chi tiết của CUPS."
         warn "Log sẽ phình to rất nhanh. Sau khi lấy log, tắt bằng: sudo $ME debug off" ;;
    off) cupsctl --no-debug-logging
         log "Đã tắt log chi tiết." ;;
    *)   fail "Dùng: sudo $ME debug on|off" ;;
  esac
}

redact() { sed -E 's/(serial=)[^& ]+/\1REDACTED/g'; }

cmd_bundle() {
  need_cups
  local tmp out src="" c
  tmp="$(mktemp -d)"
  out="$PWD/lbp2900-bundle-$(date +%Y%m%d-%H%M%S).tar.gz"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  info "Thu thập thông tin chẩn đoán..."
  {
    echo "# $(date)"; uname -a; echo; cat /etc/os-release 2>/dev/null
    if [[ -f /etc/armbian-release ]]; then echo; cat /etc/armbian-release; fi
    echo; echo "CUPS: $(cups-config --version 2>/dev/null || echo '?')"
    echo "getconf LONG_BIT: $(getconf LONG_BIT 2>/dev/null || echo '?')"
    echo "install.sh: v${VERSION}"
  } > "$tmp/system.txt" 2>&1

  { lsusb 2>&1; echo; lsusb -v -d "${CANON_VID}:" 2>&1 | head -n 120; } | redact > "$tmp/usb.txt"
  { lpstat -t 2>&1; echo; lpinfo -v 2>&1; echo; lpoptions -p "$PRINTER_NAME" 2>&1
    echo; ls -l /usr/lib/cups/filter/rastertocapt 2>&1
    echo; ls -l /usr/lib/cups/backend/usb 2>&1; } | redact > "$tmp/cups.txt"
  read_recent_log 2500 | redact > "$tmp/cups-log.txt"
  { journalctl -k --no-pager -n 400 2>/dev/null || dmesg 2>/dev/null | tail -n 400; } \
    | grep -iE 'usb|usblp|apparmor|canon|capt|cups' | tail -n 150 > "$tmp/kernel.txt" || true

  for c in "$SRC_DIR" /root/capt-test/captdriver-src /usr/local/src/captdriver; do
    if [[ -n "$c" && -d "$c" ]]; then src="$c"; break; fi
  done
  if [[ -n "$src" ]]; then
    { echo "Thư mục mã nguồn: $src"
      if [[ -d "$src/.git" ]]; then
        echo "commit: $(git -C "$src" rev-parse HEAD 2>&1)"
        echo; git -C "$src" status --short 2>&1
      fi; } > "$tmp/driver.txt"
    if [[ -d "$src/.git" ]]; then git -C "$src" diff > "$tmp/driver-local-changes.diff" 2>&1 || true; fi
  else
    echo "Không tìm thấy mã nguồn captdriver (đặt SRC_DIR=...)." > "$tmp/driver.txt"
  fi

  tar -czf "$out" -C "$tmp" .
  if [[ -n "${SUDO_USER:-}" ]]; then chown "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$out" 2>/dev/null || true; fi
  log "Đã tạo: $out"
  echo "  Đã che số serial máy in. Hãy tự xem lại nội dung trước khi gửi cho người khác."
  echo "  (Log có thể chứa tên máy, địa chỉ IP, tên file đã in.)"
}

# =============================================================================
# LỆNH THƯỜNG
# =============================================================================
cmd_print() {
  local copies=1 range="" fit=0 printer="$PRINTER_NAME" files=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n) [[ "${2:-}" =~ ^[0-9]+$ ]] || fail "-n cần một số nguyên."; copies="$2"; shift 2 ;;
      -r) [[ -n "${2:-}" ]] || fail "-r cần dải trang, ví dụ 1-3,5"; range="$2"; shift 2 ;;
      -p) [[ -n "${2:-}" ]] || fail "-p cần tên máy in."; printer="$2"; shift 2 ;;
      --fit) fit=1; shift ;;
      -*) fail "Tham số lạ: $1" ;;
      *) files+=("$1"); shift ;;
    esac
  done
  (( ${#files[@]} > 0 )) || fail "Chưa chỉ định file. Ví dụ: $ME print tai-lieu.pdf -n 2"
  have lp || fail "Chưa cài CUPS. Chạy: sudo $ME driver"
  lpstat -p "$printer" >/dev/null 2>&1 || fail "Không có máy in '$printer'. Chạy: sudo $ME driver"

  local opts=(-d "$printer" -n "$copies")
  if [[ -n "$range" ]]; then opts+=(-P "$range"); fi
  if (( fit )); then opts+=(-o fit-to-page); fi

  local f
  for f in "${files[@]}"; do
    [[ -r "$f" ]] || { warn "Không đọc được: $f (bỏ qua)"; continue; }
    lp "${opts[@]}" -- "$f"
  done
}

cmd_status() {
  echo "== USB =="
  if have lsusb; then lsusb | grep -i canon || echo "(không thấy thiết bị Canon)"; else echo "(chưa có lsusb)"; fi
  echo; echo "== CUPS =="
  systemctl is-active cups 2>/dev/null || echo "cups không chạy"
  cups_dirs
  if [[ -x "$FILTER_DIR/rastertocapt" ]]; then echo "filter rastertocapt: có"; else echo "filter rastertocapt: CHƯA CÀI"; fi
  if [[ -f "$MODEL_DIR/$PPD_DEST_NAME" ]]; then echo "PPD: có"; else echo "PPD: CHƯA CÀI"; fi
  echo; echo "== Máy in =="
  lpstat -p -d 2>/dev/null || echo "(chưa có máy in)"
  echo; echo "== Hàng đợi =="
  if [[ -n "$(lpstat -o 2>/dev/null)" ]]; then lpstat -o; else echo "(trống)"; fi
}

cmd_gui() {
  have zenity || fail "Cần zenity: sudo apt install zenity"
  [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || fail "Không có giao diện đồ hoạ."
  local file copies
  file="$(zenity --file-selection --title="Chọn file để in (Canon LBP2900)")" || exit 0
  copies="$(zenity --entry --title="Số bản in" --text="Nhập số bản:" --entry-text="1")" || exit 0
  [[ "$copies" =~ ^[0-9]+$ ]] || { zenity --error --text="Số bản không hợp lệ."; exit 1; }
  if cmd_print "$file" -n "$copies"; then
    zenity --info --text="Đã gửi lệnh in:\n$(basename "$file")" --timeout=4
  else
    zenity --error --text="Gửi lệnh in thất bại. Thử: sudo $ME fix"
  fi
}

cmd_menu() {
  local f
  PS3="Chọn (số): "
  select _ in "Cài tất cả (print server + driver Canon + chia sẻ)" "Chỉ cài print server" \
              "Chỉ cài driver Canon + thêm máy in" "In thử (có theo dõi lỗi)" "In file" \
              "Chẩn đoán lỗi (doctor)" "Sửa lỗi (fix)" "Reset USB máy in" \
              "Chia sẻ qua LAN" "Thu log để gửi phân tích (bundle)" "Thoát"; do
    case "$REPLY" in
      1) cmd_all ;;
      2) cmd_server ;;
      3) cmd_driver ;;
      4) cmd_test || true ;;
      5) read -r -e -p "Đường dẫn file: " f; cmd_print "$f" ;;
      6) cmd_doctor ;;
      7) cmd_fix ;;
      8) cmd_reset_usb ;;
      9) cmd_share ;;
      10) cmd_bundle ;;
      11) break ;;
      *) echo "Lựa chọn không hợp lệ." ;;
    esac
    echo
  done
}

main() {
  local cmd="${1:-}"
  if [[ $# -gt 0 ]]; then shift; fi
  case "$cmd" in
    -h|--help|help) usage; return 0 ;;
    -*) set -- "$cmd" "$@"; cmd="server" ;;      # tương thích bản install.sh cũ
  esac

  case "$cmd" in
    server|all|driver|add|uninstall|doctor|check|fix|test|nettest|reset-usb|share|debug|bundle) ensure_root ;;
    ""|menu) if [[ -t 0 ]]; then ensure_root; fi ;;
  esac

  case "$cmd" in
    server)         cmd_server "$@" ;;
    all)            cmd_all "$@" ;;
    driver)         cmd_driver ;;
    add)            cmd_add "$@" ;;
    uninstall)      cmd_uninstall "$@" ;;
    doctor|check)   cmd_doctor ;;
    fix)            cmd_fix "$@" ;;
    test|nettest)   cmd_test "$@" ;;
    reset-usb)      cmd_reset_usb ;;
    share)          cmd_share ;;
    debug)          cmd_debug "$@" ;;
    bundle)         cmd_bundle ;;
    print)          cmd_print "$@" ;;
    status)         cmd_status ;;
    gui)            cmd_gui ;;
    ""|menu)        if [[ -t 0 ]]; then cmd_menu; else usage; fi ;;
    *)              usage; exit 1 ;;
  esac
}

# Cho phép 'source' file này để kiểm thử mà không chạy main
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
