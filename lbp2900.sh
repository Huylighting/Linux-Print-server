#!/usr/bin/env bash
# lbp2900 - Cài đặt và in cho máy in Canon LBP2900 (CAPT) trên Linux
# (Debian, Ubuntu, Armbian, Fedora, Arch, openSUSE)
#
# Dùng driver mã nguồn mở "captdriver" (build từ source) + CUPS.
# Tham khảo dự án: https://github.com/Huylighting/Linux-Print-server
#
# Cách dùng:  ./lbp2900.sh help
set -Eeuo pipefail

VERSION="1.1.0"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
PRINTER_NAME="${PRINTER_NAME:-Canon-LBP2900}"
CAPT_REPO="${CAPT_REPO:-https://github.com/mounaiban/captdriver.git}"
SRC_DIR="${SRC_DIR:-/usr/local/src/captdriver}"
PPD_DEST_NAME="canon-lbp2900-captdriver.ppd"

log()  { printf '\033[1;32m[OK]\033[0m   %s\n' "$*"; }
info() { printf '\033[1;34m[...]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[CHÚ Ý]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[LỖI]\033[0m  %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    have sudo || fail "Cần quyền root. Hãy chạy lại bằng: sudo $0 $*"
    exec sudo -E bash "$SCRIPT_PATH" "$@"
  fi
}

cups_dirs() {
  if have cups-config; then
    FILTER_DIR="$(cups-config --serverbin)/filter"
    MODEL_DIR="$(cups-config --datadir)/model"
  else
    FILTER_DIR="/usr/lib/cups/filter"
    MODEL_DIR="/usr/share/cups/model"
  fi
  mkdir -p "$MODEL_DIR"
}

usage() {
  cat <<EOF
lbp2900 v${VERSION} - Canon LBP2900 cho Linux (Debian/Ubuntu/Armbian/Fedora/Arch/openSUSE)

Lệnh cần quyền root (tự gọi sudo):
  install            Cài gói phụ thuộc, build + cài driver captdriver, thêm máy in
  add [--uri URI]    (Thêm lại) máy in vào CUPS; tự tìm máy in USB Canon
  doctor             Chẩn đoán: máy in nhận nhưng không in (AppArmor, USB, CUPS, driver, log)
  fix [--apparmor-complain]
                     Sửa: đặt filter đúng chỗ, huỷ job kẹt, restart CUPS, bật lại hàng đợi
  share              Chia sẻ máy in qua mạng LAN (IPP/AirPrint)
  uninstall [--purge]  Gỡ máy in và driver (--purge: xoá cả mã nguồn)

Lệnh thường:
  print FILE...      In file    [-n SỐ_BẢN] [-r TRANG, vd 1-3,5] [--fit] [-p TÊN_MÁY_IN]
  test               In trang thử
  status             Xem trạng thái USB / CUPS / hàng đợi in
  gui                Chọn file bằng hộp thoại (cần zenity + giao diện đồ hoạ)
  help               Hiện trợ giúp này

Biến môi trường: PRINTER_NAME (mặc định ${PRINTER_NAME}), SRC_DIR, CAPT_REPO
Chạy không tham số trong terminal sẽ mở menu.
EOF
}

# ----------------------------------------------------------------- install
install_deps() {
  info "Cài các gói cần thiết..."
  if have apt-get; then
    # Debian, Ubuntu, Armbian, Raspberry Pi OS, Mint...
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y git build-essential autoconf automake libtool pkg-config \
      cups cups-client cups-filters libcups2-dev usbutils
    # Tuỳ phiên bản, libcupsimage nằm ở gói riêng hoặc đã gộp vào libcups2-dev
    if apt-cache show libcupsimage2-dev >/dev/null 2>&1; then
      apt-get install -y libcupsimage2-dev
    fi
  elif have dnf; then
    dnf install -y git gcc make autoconf automake libtool pkgconf-pkg-config \
      cups cups-devel cups-filters usbutils
  elif have zypper; then
    zypper --non-interactive install -y git gcc make autoconf automake libtool pkg-config \
      cups cups-devel cups-filters usbutils
  elif have pacman; then
    # Arch không hỗ trợ nâng cấp từng phần nên phải đồng bộ cả hệ thống (-Syu)
    pacman -Syu --noconfirm --needed git base-devel cups cups-filters usbutils
  else
    fail "Không nhận ra trình quản lý gói (apt, dnf, zypper, pacman). Hãy cài thủ công: git, trình biên dịch C, autotools, CUPS kèm header, usbutils."
  fi
  systemctl enable --now cups >/dev/null 2>&1 || true
  log "Đã cài xong gói phụ thuộc."
}

fetch_source() {
  if [[ -d "$SRC_DIR/.git" ]]; then
    info "Cập nhật mã nguồn captdriver tại $SRC_DIR ..."
    git -C "$SRC_DIR" pull --ff-only || warn "Không cập nhật được, dùng bản hiện có."
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
    # File PPD chỉ được sinh ra khi chạy 'make ppd' (theo hướng dẫn của captdriver)
    make ppd || warn "'make ppd' không chạy được; sẽ tìm PPD có sẵn trong mã nguồn." )
  FILTER_BIN="$(find "$SRC_DIR" -type f -name rastertocapt -perm -u+x 2>/dev/null | head -n1 || true)"
  [[ -n "$FILTER_BIN" ]] || fail "Build xong nhưng không thấy file 'rastertocapt'. Xem log phía trên."
  log "Build thành công: $FILTER_BIN"
}

install_driver_files() {
  cups_dirs
  install -D -m 0755 -o root -g root "$FILTER_BIN" "$FILTER_DIR/rastertocapt"
  log "Đã cài filter vào $FILTER_DIR/rastertocapt"

  local ppd
  ppd="$(find "$SRC_DIR" -type f -iname '*2900*.ppd' 2>/dev/null | head -n1 || true)"
  if [[ -z "$ppd" ]]; then
    ppd="$(grep -rl --include='*.ppd' 'rastertocapt' "$SRC_DIR" 2>/dev/null | head -n1 || true)"
    [[ -n "$ppd" ]] && warn "Không có PPD riêng cho 2900, dùng tạm: $(basename "$ppd")"
  fi
  [[ -n "$ppd" ]] || fail "Không tìm thấy file PPD (thường tên CanonLBP-2900-3000.ppd, sinh bởi 'make ppd') trong $SRC_DIR."
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
  [[ -f "$MODEL_DIR/$PPD_DEST_NAME" ]] || fail "Chưa cài driver. Hãy chạy: $0 install"
  systemctl restart cups; sleep 2
  if [[ -z "$uri" ]]; then
    uri="$(find_uri || true)"
  fi
  if [[ -z "$uri" ]]; then
    warn "Không thấy máy in Canon qua USB."
    echo "  - Bật nguồn máy in, cắm cáp USB (thử cổng USB 2.0, cáp ngắn)"
    echo "  - Kiểm tra: lsusb | grep -i canon"
    echo "  - Sau đó chạy lại: $0 add"
    return 1
  fi
  info "Thiết bị: $uri"
  lpadmin -x "$PRINTER_NAME" 2>/dev/null || true
  lpadmin -p "$PRINTER_NAME" -E -v "$uri" -P "$MODEL_DIR/$PPD_DEST_NAME" \
          -o printer-error-policy=retry-job
  lpadmin -d "$PRINTER_NAME"
  log "Đã thêm máy in '$PRINTER_NAME' và đặt làm mặc định."
}

add_admin_group() {
  local u="${SUDO_USER:-}"
  [[ -n "$u" && "$u" != "root" ]] || return 0
  have apt-get || return 0   # nhóm lpadmin chỉ dùng trên Debian/Ubuntu/Armbian
  getent group lpadmin >/dev/null 2>&1 || groupadd lpadmin
  usermod -aG lpadmin "$u" && info "Đã thêm '$u' vào nhóm lpadmin (đăng nhập lại để có hiệu lực)."
}

cmd_install() {
  ensure_root install "$@"
  install_deps
  fetch_source
  build_driver
  install_driver_files
  add_admin_group
  systemctl restart cups
  add_printer "" || warn "Driver đã cài; hãy cắm máy in rồi chạy: $0 add"
  echo
  log "Hoàn tất. Thử in: $0 test"
}

# --------------------------------------------------------------------- add
cmd_add() {
  ensure_root add "$@"
  local uri=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --uri) [[ -n "${2:-}" ]] || fail "--uri cần giá trị."; uri="$2"; shift 2 ;;
      *) fail "Tham số lạ: $1" ;;
    esac
  done
  add_printer "$uri"
}

# --------------------------------------------------------------------- fix
cmd_fix() {
  ensure_root fix "$@"
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
    # Fedora/openSUSE (SELinux): đặt lại nhãn bảo mật cho file vừa chép
    if have restorecon; then restorecon -v "$FILTER_DIR/rastertocapt" || true; fi
  else
    warn "Chưa có filter rastertocapt. Chạy: $0 install"
  fi

  # 2. Huỷ job kẹt, khởi động lại CUPS, bật lại hàng đợi
  info "Huỷ các job đang kẹt..."
  cancel -a "$PRINTER_NAME" 2>/dev/null || true
  info "Restart CUPS..."
  systemctl restart cups; sleep 2
  cupsaccept "$PRINTER_NAME" 2>/dev/null || true
  cupsenable "$PRINTER_NAME" 2>/dev/null || true

  # 3. AppArmor (chỉ khi người dùng yêu cầu, vì làm lỏng bảo vệ của cupsd)
  if (( complain )); then
    have aa-complain || { info "Cài apparmor-utils..."; apt-get install -y apparmor-utils; }
    aa-complain /usr/sbin/cupsd
    warn "cupsd đang ở chế độ 'complain' (chỉ ghi log, không chặn). Hoàn tác: sudo aa-enforce /usr/sbin/cupsd"
    systemctl restart cups
  fi

  log "Xong bước sửa tự động."
  lpstat -p "$PRINTER_NAME" 2>/dev/null || true
  echo "  Tiếp theo: tắt máy in 5 giây rồi bật lại, chạy '$0 test', rồi '$0 doctor' nếu vẫn không ra giấy."
}

# ------------------------------------------------------------------ doctor
D_PASS=0; D_WARN=0; D_FAIL=0
d_ok()   { printf '  \033[1;32m✔\033[0m %s\n' "$*"; D_PASS=$((D_PASS + 1)); }
d_warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; D_WARN=$((D_WARN + 1)); }
d_bad()  { printf '  \033[1;31m✘\033[0m %s\n' "$*"; D_FAIL=$((D_FAIL + 1)); }
d_hint() { printf '      → %s\n' "$*"; }

cmd_doctor() {
  ensure_root doctor "$@"
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
  usbline="$(lsusb 2>/dev/null | grep -i '04a9' | head -n1 || true)"
  if [[ -n "$usbline" ]]; then
    d_ok "Thấy thiết bị Canon: $usbline"
  else
    d_bad "Không thấy thiết bị Canon (mã hãng 04a9) trên USB"
    d_hint "Bật nguồn máy in, thử cáp USB khác/ngắn hơn, cắm thẳng vào cổng USB 2.0 (cáp cũ từng gây trễ hoặc không in)"
  fi
  uri="$(find_uri || true)"
  if [[ -n "$uri" ]]; then
    d_ok "CUPS thấy máy in: $uri"
  else
    d_bad "CUPS không liệt kê thiết bị usb:// của Canon (lpinfo -v)"
    d_hint "Tắt máy in 5 giây rồi bật lại, rút/cắm USB, sau đó chạy lại doctor"
  fi

  echo "== 3. CUPS =="
  if systemctl is-active --quiet cups; then d_ok "cups đang chạy"; else d_bad "cups không chạy"; d_hint "systemctl restart cups"; fi
  local cv
  cv="$(cups-config --version 2>/dev/null || true)"
  if [[ -n "$cv" ]]; then
    if [[ "$(printf '%s\n%s\n' 2.4.17 "$cv" | sort -V | head -n1)" == "2.4.17" ]]; then
      d_ok "CUPS $cv (từ 2.4.17 trở lên)"
    else
      d_warn "CUPS $cv thấp hơn 2.4.17: bản cũ có thể dính lỗi tranh chấp USB làm job kẹt (bản vá của Debian có thể đã backport)"
      d_hint "sudo apt update && sudo apt upgrade, hoặc dùng bản CUPS mới hơn từ backports"
    fi
  fi

  echo "== 4. Driver =="
  if [[ -x "$FILTER_DIR/rastertocapt" ]]; then d_ok "filter: $FILTER_DIR/rastertocapt"; else d_bad "thiếu filter rastertocapt trong $FILTER_DIR"; d_hint "$0 install  (hoặc $0 fix)"; fi
  if [[ -e /usr/local/bin/rastertocapt ]]; then
    d_warn "Có /usr/local/bin/rastertocapt (từ 'make install'); trên Debian 13 AppArmor đã chặn đường dẫn này"
    d_hint "$0 fix sẽ dùng bản trong $FILTER_DIR"
  fi
  if [[ -f "$MODEL_DIR/$PPD_DEST_NAME" ]]; then d_ok "PPD: $MODEL_DIR/$PPD_DEST_NAME"; else d_bad "thiếu PPD"; d_hint "$0 install"; fi

  echo "== 5. Máy in trong CUPS =="
  if lpstat -p "$PRINTER_NAME" >/dev/null 2>&1; then
    local line dev jobs
    line="$(lpstat -p "$PRINTER_NAME" 2>/dev/null | head -n1 || true)"
    case "$line" in
      *disabled*) d_bad "Máy in đang bị tắt trong CUPS: $line"; d_hint "cupsenable $PRINTER_NAME  (hoặc $0 fix)" ;;
      *) d_ok "$line" ;;
    esac
    dev="$(lpstat -v "$PRINTER_NAME" 2>/dev/null || true)"
    case "$dev" in
      *usb://*) d_ok "$dev" ;;
      *) d_warn "URI không phải usb://: ${dev:-không rõ}"; d_hint "$0 add" ;;
    esac
    jobs="$(lpstat -o "$PRINTER_NAME" 2>/dev/null || true)"
    if [[ -n "$jobs" ]]; then
      d_warn "Có job đang chờ hoặc kẹt:"; printf '      %s\n' "$jobs"
      d_hint "$0 fix  (huỷ job và khởi động lại CUPS)"
    else
      d_ok "Hàng đợi trống"
    fi
  else
    d_bad "Chưa có máy in '$PRINTER_NAME' trong CUPS"; d_hint "$0 add"
  fi

  echo "== 6. AppArmor / SELinux =="
  local denied
  denied="$( { journalctl -k --no-pager -n 3000 2>/dev/null
               dmesg 2>/dev/null
               tail -n 3000 /var/log/audit/audit.log 2>/dev/null; } \
             | grep -iE 'apparmor="DENIED"|avc: +denied' | grep -iE 'cupsd|rastertocapt|capt' | tail -n 3 || true)"
  if [[ -n "$denied" ]]; then
    d_bad "AppArmor/SELinux đã CHẶN cupsd hoặc filter CAPT (AppArmor hay gặp trên Debian 13):"
    printf '%s\n' "$denied" | cut -c1-200 | sed 's/^/      /'
    d_hint "Bước 1: $0 fix  (đặt filter vào thư mục chuẩn rồi in thử lại)"
    d_hint "Bước 2, nếu log vẫn báo chặn bởi AppArmor: $0 fix --apparmor-complain  (cách tạm, làm lỏng bảo vệ cupsd)"
    d_hint "Nếu là SELinux (Fedora/openSUSE): fix đã chạy restorecon cho filter; xem thêm: sudo ausearch -m avc -ts recent"
  elif have aa-status && aa-status --enabled 2>/dev/null; then
    d_ok "AppArmor đang bật, chưa thấy log chặn gần đây"
    d_hint "Nếu in vẫn lỗi: in thử một trang rồi chạy lại doctor để bắt log mới"
  else
    d_ok "AppArmor không bật hoặc không chặn"
  fi

  echo "== 7. Module usblp =="
  if [[ -d /sys/module/usblp ]]; then
    d_warn "usblp đang được nạp; có thể tranh quyền thiết bị với backend USB của CUPS"
    d_hint "Chỉ khi job vẫn kẹt: sudo modprobe -r usblp  (hoàn tác bằng khởi động lại máy)"
  else
    d_ok "usblp không nạp"
  fi

  echo "== 8. Lỗi CAPT gần đây =="
  local errs
  errs="$( { journalctl -u cups --no-pager -n 500 2>/dev/null
             tail -n 500 /var/log/cups/error_log 2>/dev/null; } \
           | grep -iE 'CAPT|rastertocapt' | tail -n 6 || true)"
  if [[ -z "$errs" ]]; then
    d_ok "Không có thông báo CAPT lỗi trong log"
  else
    d_warn "Thông báo CAPT gần nhất:"
    printf '%s\n' "$errs" | cut -c1-200 | sed 's/^/      /'
    case "$errs" in
      *"bad reply"*) d_hint "'bad reply from printer': tắt máy in, chờ 5 giây, bật lại; thử bản 64-bit và CUPS mới" ;;
    esac
    case "$errs" in
      *"Unable to communicate"*) d_hint "'Unable to communicate': kiểm tra cáp USB và quyền truy cập, rồi tắt/bật máy in" ;;
    esac
  fi

  echo
  printf 'Kết quả: %d đạt, %d cảnh báo, %d lỗi\n' "$D_PASS" "$D_WARN" "$D_FAIL"
  echo "Lưu ý: LBP2900 với captdriver được báo cáo là chỉ in tốt ngay sau khi bật nguồn, hoặc treo sau một job."
  echo "Nếu không có lỗi nào ở trên mà vẫn không in: tắt/bật máy in giữa các lần in."
  if (( D_FAIL > 0 )); then echo "Gợi ý: chạy '$0 fix' rồi '$0 doctor' lại."; fi
}

# ------------------------------------------------------------------- share
cmd_share() {
  ensure_root share "$@"
  lpstat -p "$PRINTER_NAME" >/dev/null 2>&1 || fail "Chưa có máy in '$PRINTER_NAME'. Chạy: $0 install"
  cupsctl --share-printers
  lpadmin -p "$PRINTER_NAME" -o printer-is-shared=true
  systemctl restart cups
  local ip; ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  log "Đã chia sẻ máy in trong mạng LAN."
  echo "  Địa chỉ IPP: ipp://${ip:-IP_MAY}:631/printers/${PRINTER_NAME}"
  echo "  Cần Samba (Windows) / Avahi (AirPrint)? Dùng thêm install.sh của dự án:"
  echo "  https://github.com/Huylighting/Linux-Print-server"
}

# --------------------------------------------------------------- uninstall
cmd_uninstall() {
  ensure_root uninstall "$@"
  local purge=0
  [[ "${1:-}" == "--purge" ]] && purge=1
  cups_dirs
  lpadmin -x "$PRINTER_NAME" 2>/dev/null || true
  rm -f "$FILTER_DIR/rastertocapt" "$MODEL_DIR/$PPD_DEST_NAME"
  [[ "$purge" == 1 ]] && rm -rf "$SRC_DIR"
  systemctl restart cups || true
  log "Đã gỡ máy in và driver."
}

# ------------------------------------------------------------------- print
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
  (( ${#files[@]} > 0 )) || fail "Chưa chỉ định file. Ví dụ: $0 print tai-lieu.pdf -n 2"
  have lp || fail "Chưa cài CUPS. Chạy: $0 install"
  lpstat -p "$printer" >/dev/null 2>&1 || fail "Không có máy in '$printer'. Chạy: $0 install"

  local opts=(-d "$printer" -n "$copies")
  [[ -n "$range" ]] && opts+=(-P "$range")
  (( fit )) && opts+=(-o fit-to-page)

  local f
  for f in "${files[@]}"; do
    [[ -r "$f" ]] || { warn "Không đọc được: $f (bỏ qua)"; continue; }
    lp "${opts[@]}" -- "$f"
  done
}

cmd_test() {
  lpstat -p "$PRINTER_NAME" >/dev/null 2>&1 || fail "Không có máy in '$PRINTER_NAME'. Chạy: $0 install"
  local tp="/usr/share/cups/data/testprint"
  if [[ -r "$tp" ]]; then
    lp -d "$PRINTER_NAME" "$tp"
  else
    printf 'Canon LBP2900 - trang in thu\nNgay: %s\nMay chu: %s\n' "$(date)" "$(hostname)" \
      | lp -d "$PRINTER_NAME"
  fi
  info "Đã gửi. Nếu sau 15 giây chưa ra giấy: tắt/bật máy in rồi chạy '$0 doctor'."
}

# ------------------------------------------------------------------ status
cmd_status() {
  echo "== USB =="
  if have lsusb; then lsusb | grep -i canon || echo "(không thấy thiết bị Canon)"; else echo "(chưa có lsusb)"; fi
  echo; echo "== CUPS =="
  systemctl is-active cups 2>/dev/null || echo "cups không chạy"
  cups_dirs
  [[ -x "$FILTER_DIR/rastertocapt" ]] && echo "filter rastertocapt: có" || echo "filter rastertocapt: CHƯA CÀI"
  [[ -f "$MODEL_DIR/$PPD_DEST_NAME" ]] && echo "PPD: có" || echo "PPD: CHƯA CÀI"
  echo; echo "== Máy in =="
  lpstat -p -d 2>/dev/null || echo "(chưa có máy in)"
  echo; echo "== Hàng đợi =="
  lpstat -o 2>/dev/null || true
  [[ -z "$(lpstat -o 2>/dev/null)" ]] && echo "(trống)"
}

# --------------------------------------------------------------------- gui
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
    zenity --error --text="Gửi lệnh in thất bại. Thử: $0 fix"
  fi
}

# -------------------------------------------------------------------- menu
cmd_menu() {
  PS3="Chọn (số): "
  select opt in "Cài driver + thêm máy in" "In file" "In trang thử" "Xem trạng thái" \
                "Chẩn đoán lỗi (doctor)" "Sửa lỗi (fix)" "Chia sẻ qua LAN" "Thoát"; do
    case "$REPLY" in
      1) cmd_install ;;
      2) read -r -e -p "Đường dẫn file: " f; cmd_print "$f" ;;
      3) cmd_test ;;
      4) cmd_status ;;
      5) cmd_doctor ;;
      6) cmd_fix ;;
      7) cmd_share ;;
      8) break ;;
      *) echo "Lựa chọn không hợp lệ." ;;
    esac
    echo
  done
}

main() {
  local cmd="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$cmd" in
    install)   cmd_install "$@" ;;
    add)       cmd_add "$@" ;;
    fix)       cmd_fix "$@" ;;
    doctor)    cmd_doctor "$@" ;;
    share)     cmd_share "$@" ;;
    uninstall) cmd_uninstall "$@" ;;
    print)     cmd_print "$@" ;;
    test)      cmd_test ;;
    status)    cmd_status ;;
    gui)       cmd_gui ;;
    help|-h|--help) usage ;;
    "")        if [[ -t 0 ]]; then cmd_menu; else usage; fi ;;
    *)         usage; exit 1 ;;
  esac
}

main "$@"
