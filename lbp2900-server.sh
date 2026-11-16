#!/usr/bin/env bash
# lbp2900-server.sh - Print server Canon LBP2900 (CUPS)
#
# Chạy ĐỘC LẬP với lbp2900.sh. Dùng khi in tại chỗ đã được nhưng in từ máy khác
# trong mạng (Windows/Mac/điện thoại) qua print server thì không ra giấy.
#
# Phạm vi tác động (an toàn cho máy đang chạy dịch vụ khác):
#   - chỉ đụng tới CUPS và hàng đợi của máy in này
#   - reset-usb chỉ tác động thiết bị USB hãng Canon (04a9)
#   - KHÔNG sửa tường lửa, Avahi, Samba, Docker, Tailscale, NetBird, v.v.
#
# Cách dùng: ./lbp2900-server.sh help
set -Eeuo pipefail

VERSION="1.0.0"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
PRINTER_NAME="${PRINTER_NAME:-Canon-LBP2900}"
CUPS_LOG="${CUPS_LOG:-/var/log/cups/error_log}"
WAIT="${WAIT:-90}"                 # số giây chờ job trong lệnh nettest
CANON_VID="04a9"
SRC_CANDIDATES=("${SRC_DIR:-}" /root/capt-test/captdriver-src /usr/local/src/captdriver)

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

usage() {
  cat <<EOF
lbp2900-server v${VERSION} - Print server Canon LBP2900

Lệnh (đều tự gọi sudo):
  share        Bật chia sẻ máy in qua LAN, in địa chỉ để thêm vào Windows/Mac
  check        Kiểm tra toàn bộ đường in qua mạng (chia sẻ, cổng 631, tường lửa,
               USB, hàng đợi, lỗi CAPT trong log)
  nettest [FILE]  Gửi 1 job qua IPP (localhost:631, giống máy khách) và theo dõi
               kết quả + lỗi CAPT phát sinh. Mặc định in trang thử PDF của CUPS
  reset-usb    "Rút/cắm" lại USB của máy in bằng phần mềm (chỉ thiết bị Canon)
  debug on|off Bật/tắt log chi tiết của CUPS (nhớ tắt sau khi lấy log)
  bundle       Gói thông tin chẩn đoán vào 1 file .tar.gz để gửi đi phân tích
  help         Trợ giúp này

Biến môi trường: PRINTER_NAME (mặc định ${PRINTER_NAME}), WAIT (giây chờ, mặc định ${WAIT}),
                 SRC_DIR (thư mục mã nguồn captdriver), CUPS_LOG

Quy trình gợi ý khi in từ máy khác không ra giấy:
  1) ./lbp2900-server.sh check
  2) ./lbp2900-server.sh nettest
     - Nếu nettest cũng lỗi: máy in/driver ở tầng USB (reset-usb, hoặc tắt/bật máy in)
     - Nếu nettest in được mà máy khách vẫn không in: lỗi nằm ở phía máy khách
       (định dạng/tuỳ chọn job). Chạy: debug on, in từ máy khách, rồi bundle
EOF
}

# ------------------------------------------------------------------ chung
ensure_root() {
  [[ "${EUID}" -eq 0 ]] && return 0
  have sudo || fail "Cần quyền root. Hãy chạy lại bằng: sudo $0 $*"
  exec sudo -E bash "$SCRIPT_PATH" "$@"
}

need_cups() {
  have lpstat && have lp && have lpadmin || fail "Chưa cài CUPS (thiếu lp/lpstat/lpadmin)."
}

need_printer() {
  need_cups
  lpstat -p "$PRINTER_NAME" >/dev/null 2>&1 \
    || fail "Chưa có máy in '$PRINTER_NAME' trong CUPS. Hãy cài trước bằng lbp2900.sh (install/add)."
}

lan_ip() { hostname -I 2>/dev/null | awk '{print $1}'; }

# CUPS đang nghe cổng 631 ở đâu: none | local | lan
listen_scope() {
  local addrs
  addrs="$(ss -ltn 2>/dev/null | awk 'NR>1 {print $4}' | grep -E ':631$' || true)"
  if [[ -z "$addrs" ]]; then echo none; return; fi
  if printf '%s\n' "$addrs" | grep -vqE '^(127\.0\.0\.1|\[::1\]|::1):631$'; then
    echo lan
  else
    echo local
  fi
}

# Trạng thái ufw đối với cổng 631: ufw-open | ufw-closed | none (không dùng ufw)
fw_state() {
  if have ufw && ufw status 2>/dev/null | grep -qi '^Status: active'; then
    if ufw status 2>/dev/null | grep -qE '(^|[^0-9])631(/|[[:space:]])'; then echo ufw-open; else echo ufw-closed; fi
  else
    echo none
  fi
}

# Đọc log CUPS: LOG_START (số dòng) hoặc T0 (epoch) được ghi trước khi thử
read_recent_log() {
  local n="${1:-2000}"
  if [[ -s "$CUPS_LOG" ]]; then
    tail -n "$n" "$CUPS_LOG" 2>/dev/null || true
  else
    journalctl -u cups --no-pager -n "$n" 2>/dev/null || true
  fi
}

read_new_log() {
  if [[ -s "$CUPS_LOG" ]]; then
    tail -n +"$((LOG_START + 1))" "$CUPS_LOG" 2>/dev/null || true
  else
    journalctl -u cups --no-pager --since "@${T0}" 2>/dev/null || true
  fi
}

# --------------------------------------------------------------- share
cmd_share() {
  need_printer
  info "Bật chia sẻ máy in trong CUPS..."
  cupsctl --share-printers
  lpadmin -p "$PRINTER_NAME" -o printer-is-shared=true
  info "Khởi động lại CUPS (chỉ dịch vụ cups)..."
  systemctl restart cups
  sleep 2

  case "$(listen_scope)" in
    lan)   log "CUPS đang nghe cổng 631 trên mạng LAN." ;;
    local) warn "CUPS vẫn chỉ nghe ở localhost. Kiểm tra /etc/cups/cupsd.conf (dòng Listen/Port)." ;;
    none)  warn "Không thấy tiến trình nào nghe cổng 631. Xem: systemctl status cups" ;;
  esac

  case "$(fw_state)" in
    ufw-closed) warn "ufw đang bật nhưng chưa mở cổng 631. Script KHÔNG tự sửa tường lửa."
                echo "  Nếu muốn mở cho mạng nội bộ (đổi dải IP cho đúng):"
                echo "    sudo ufw allow from 192.168.0.0/16 to any port 631 proto tcp" ;;
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
  echo "Bước tiếp theo: $0 nettest   (kiểm tra job qua IPP trước khi thử từ máy khách)"
}

# --------------------------------------------------------------- check
cmd_check() {
  need_cups
  D_PASS=0; D_WARN=0; D_FAIL=0

  echo "== 1. Máy in trong CUPS =="
  if lpstat -p "$PRINTER_NAME" >/dev/null 2>&1; then
    local line
    line="$(lpstat -p "$PRINTER_NAME" 2>/dev/null | head -n1 || true)"
    case "$line" in
      *disabled*) d_bad "Máy in đang bị tắt: $line"; d_hint "cupsenable $PRINTER_NAME" ;;
      *)          d_ok "$line" ;;
    esac
    lpstat -v "$PRINTER_NAME" 2>/dev/null | head -n1 | sed 's/^/      /' || true
  else
    d_bad "Chưa có máy in '$PRINTER_NAME'"; d_hint "Cài bằng lbp2900.sh (install/add) trước"
  fi

  echo "== 2. Chia sẻ qua mạng =="
  if have ipptool && [[ -r /usr/share/cups/ipptool/get-printer-attributes.test ]]; then
    if ipptool -tv "ipp://localhost:631/printers/${PRINTER_NAME}" get-printer-attributes.test 2>/dev/null \
         | grep -q 'printer-is-shared (boolean) = true'; then
      d_ok "Máy in đã được đặt chế độ chia sẻ (printer-is-shared=true)"
    else
      d_bad "Máy in CHƯA được chia sẻ"; d_hint "$0 share"
    fi
  else
    d_warn "Không có ipptool nên không kiểm tra được trạng thái chia sẻ"
  fi
  case "$(listen_scope)" in
    lan)   d_ok "CUPS nghe cổng 631 trên mạng LAN" ;;
    local) d_bad "CUPS chỉ nghe ở localhost nên máy khác không kết nối được"; d_hint "$0 share" ;;
    none)  d_bad "Không có gì nghe cổng 631"; d_hint "systemctl status cups" ;;
  esac
  case "$(fw_state)" in
    ufw-closed) d_warn "ufw đang bật nhưng chưa thấy luật cho cổng 631"
                d_hint "sudo ufw allow from <dải_LAN> to any port 631 proto tcp  (script không tự sửa)" ;;
    ufw-open)   d_ok "ufw đã cho phép cổng 631" ;;
    none)       d_ok "Không có ufw chặn (nếu dùng nftables/iptables hãy tự kiểm tra)" ;;
  esac

  echo "== 3. USB =="
  if have lsusb && lsusb 2>/dev/null | grep -qi "$CANON_VID"; then
    d_ok "$(lsusb | grep -i "$CANON_VID" | head -n1)"
  else
    d_bad "Không thấy thiết bị Canon trên USB"; d_hint "Bật nguồn máy in, kiểm tra cáp; hoặc $0 reset-usb"
  fi
  if [[ -d /sys/module/usblp ]]; then
    d_warn "Module usblp đang nạp; có thể tranh thiết bị với backend USB của CUPS"
    d_hint "Chỉ khi job vẫn kẹt: sudo modprobe -r usblp"
  fi

  echo "== 4. Hàng đợi =="
  local jobs
  jobs="$(lpstat -o "$PRINTER_NAME" 2>/dev/null || true)"
  if [[ -n "$jobs" ]]; then
    d_warn "Có job chưa xong:"; printf '      %s\n' "$jobs"
    d_hint "Huỷ job kẹt của máy in này: cancel -a $PRINTER_NAME  rồi chạy lại nettest"
  else
    d_ok "Hàng đợi trống"
  fi

  echo "== 5. Lỗi gần đây trong log CUPS =="
  local recent
  recent="$(read_recent_log 3000)"
  if [[ -z "$recent" ]]; then
    d_warn "Không đọc được log CUPS ($CUPS_LOG hoặc journal)"
  else
    if grep -q 'no reply from printer' <<<"$recent"; then
      d_bad "Driver báo 'no reply from printer' (máy in không trả lời lệnh CAPT qua USB)"
      d_hint "Đây là lỗi ở tầng USB/CAPT, không phải do mạng. Thử: $0 reset-usb  (hoặc tắt máy in 10 giây rồi bật lại), sau đó $0 nettest"
    fi
    if grep -q 'USB transaction timeout' <<<"$recent"; then
      d_warn "Có 'USB transaction timeout' trong log"
    fi
    if grep -qE 'Filter failed|Backend returned status' <<<"$recent"; then
      d_warn "Có job bị lỗi filter/backend"
    fi
    if ! grep -qE 'no reply from printer|USB transaction timeout|Filter failed|Backend returned status' <<<"$recent"; then
      d_ok "Không thấy lỗi CAPT/USB gần đây (nếu log CUPS ở mức thấp, hãy dùng: $0 debug on)"
    fi
  fi
  local denied
  denied="$( { journalctl -k --no-pager -n 3000 2>/dev/null; dmesg 2>/dev/null; } \
             | grep -iE 'apparmor="DENIED"' | grep -iE 'cupsd|rastertocapt|capt' | tail -n 3 || true)"
  if [[ -n "$denied" ]]; then
    d_bad "AppArmor chặn cupsd/filter CAPT:"; printf '%s\n' "$denied" | cut -c1-200 | sed 's/^/      /'
    d_hint "Xem hướng dẫn trong lbp2900.sh: fix / fix --apparmor-complain"
  fi

  echo
  printf 'Kết quả: %d đạt, %d cảnh báo, %d lỗi\n' "$D_PASS" "$D_WARN" "$D_FAIL"
  echo "Bước tiếp theo: $0 nettest"
}

# ------------------------------------------------------------- nettest
cmd_nettest() {
  need_printer
  local file="${1:-}"
  if [[ -z "$file" ]]; then
    for file in /usr/share/cups/data/default-testpage.pdf /usr/share/cups/data/testprint; do
      [[ -r "$file" ]] && break
      file=""
    done
  fi
  [[ -n "$file" && -r "$file" ]] || fail "Không có file để thử. Hãy truyền đường dẫn: $0 nettest file.pdf"

  T0="$(date +%s)"
  LOG_START="$(wc -l < "$CUPS_LOG" 2>/dev/null || echo 0)"

  info "Gửi job qua IPP (localhost:631), cùng đường với máy khách trong mạng..."
  info "File: $file"
  local out jobid=""
  out="$(lp -h localhost:631 -d "$PRINTER_NAME" -t "nettest" -- "$file" 2>&1)" \
    || fail "Không gửi được job: $out"
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
    echo "  Đường mạng/IPP đã chạy tới tận driver, nên lỗi ở tầng USB/CAPT chứ không phải do mạng."
    echo "  Thử lần lượt:"
    echo "   1) sudo $0 reset-usb   (hoặc tắt nguồn máy in 10 giây rồi bật lại)"
    echo "   2) sudo $0 nettest     (in lại ngay sau khi reset)"
    echo "   3) Nếu job đầu in được mà job thứ hai lỗi: driver không nhả máy in sau job (captdriver issue #14)"
    echo "   4) Vẫn lỗi: sudo $0 debug on, chạy lại nettest, rồi sudo $0 bundle và gửi file gói"
  elif grep -qE 'Filter failed|Backend returned status' <<<"$newlog"; then
    rc=1
    d_bad "KẾT QUẢ: job lỗi ở filter hoặc backend. Xem log phía trên."
    echo "  Chạy: sudo $0 debug on, thử lại, rồi sudo $0 bundle"
  elif (( finished == 0 )); then
    rc=1
    d_warn "KẾT QUẢ: job vẫn còn trong hàng đợi sau ${WAIT} giây."
    lpstat -l -o "$PRINTER_NAME" 2>/dev/null | sed 's/^/  /' || true
    echo "  Thử: sudo $0 reset-usb, hoặc huỷ job: cancel -a $PRINTER_NAME"
  else
    d_ok "KẾT QUẢ: job đã rời hàng đợi và không thấy lỗi CAPT. Hãy xem máy in đã ra giấy chưa."
    echo "  Nếu ra giấy mà máy khách (Windows) vẫn không in được: lỗi nằm ở phía máy khách"
    echo "  (cách thêm máy in, driver, hoặc định dạng job). Chạy: sudo $0 debug on,"
    echo "  in từ máy khách, rồi sudo $0 bundle để xem job do máy khách gửi."
  fi
  return "$rc"
}

# ----------------------------------------------------------- reset-usb
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
  (( n > 0 )) || fail "Không thấy thiết bị USB hãng Canon (04a9). Kiểm tra nguồn và cáp."
  cupsenable "$PRINTER_NAME" 2>/dev/null || true
  log "Đã reset USB. Thử lại ngay: $0 nettest"
}

# --------------------------------------------------------------- debug
cmd_debug() {
  need_cups
  case "${1:-}" in
    on)  cupsctl --debug-logging
         log "Đã bật log chi tiết của CUPS."
         warn "Log sẽ phình to rất nhanh. Sau khi lấy log, tắt bằng: $0 debug off" ;;
    off) cupsctl --no-debug-logging
         log "Đã tắt log chi tiết." ;;
    *)   fail "Dùng: $0 debug on|off" ;;
  esac
}

# -------------------------------------------------------------- bundle
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
    [[ -f /etc/armbian-release ]] && { echo; cat /etc/armbian-release; }
    echo; echo "CUPS: $(cups-config --version 2>/dev/null || echo '?')"
    echo "getconf LONG_BIT: $(getconf LONG_BIT 2>/dev/null || echo '?')"
  } > "$tmp/system.txt" 2>&1

  { lsusb 2>&1; echo; lsusb -v -d "${CANON_VID}:" 2>&1 | head -n 120; } | redact > "$tmp/usb.txt"
  { lpstat -t 2>&1; echo; lpinfo -v 2>&1; echo; lpoptions -p "$PRINTER_NAME" 2>&1
    echo; ls -l /usr/lib/cups/filter/rastertocapt 2>&1
    echo; ls -l /usr/lib/cups/backend/usb 2>&1; } | redact > "$tmp/cups.txt"
  read_recent_log 2500 | redact > "$tmp/cups-log.txt"
  { journalctl -k --no-pager -n 400 2>/dev/null || dmesg 2>/dev/null | tail -n 400; } \
    | grep -iE 'usb|usblp|apparmor|canon|capt|cups' | tail -n 150 > "$tmp/kernel.txt" || true

  for c in "${SRC_CANDIDATES[@]}"; do
    if [[ -n "$c" && -d "$c" ]]; then src="$c"; break; fi
  done
  if [[ -n "$src" ]]; then
    { echo "Thư mục mã nguồn: $src"
      if [[ -d "$src/.git" ]]; then
        echo "commit: $(git -C "$src" rev-parse HEAD 2>&1)"
        echo; git -C "$src" status --short 2>&1
      fi; } > "$tmp/driver.txt"
    if [[ -d "$src/.git" ]]; then
      git -C "$src" diff > "$tmp/driver-local-changes.diff" 2>&1 || true
    fi
  else
    echo "Không tìm thấy mã nguồn captdriver (đặt SRC_DIR=...)." > "$tmp/driver.txt"
  fi

  tar -czf "$out" -C "$tmp" .
  if [[ -n "${SUDO_USER:-}" ]]; then chown "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$out" 2>/dev/null || true; fi
  log "Đã tạo: $out"
  echo "  Đã che số serial máy in. Hãy tự xem lại nội dung trước khi gửi cho người khác."
  echo "  (Log có thể chứa tên máy, địa chỉ IP, tên file đã in.)"
}

# ---------------------------------------------------------------- main
main() {
  local cmd="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$cmd" in
    share|check|nettest|reset-usb|debug|bundle) ensure_root "$cmd" "$@" ;;
  esac
  case "$cmd" in
    share)     cmd_share ;;
    check)     cmd_check ;;
    nettest)   cmd_nettest "$@" ;;
    reset-usb) cmd_reset_usb ;;
    debug)     cmd_debug "$@" ;;
    bundle)    cmd_bundle ;;
    help|-h|--help|"") usage ;;
    *)         usage; exit 1 ;;
  esac
}

main "$@"
