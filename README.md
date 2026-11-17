# 🖨️ Linux Print Server with CUPS

Biến một máy tính Linux thành **Print Server** sử dụng **CUPS**, **Samba** và **Avahi** để chia sẻ máy in cho Windows, macOS, Linux, Android và iPhone.

> Script hiện tại: **v2.0.0**. Có hỗ trợ cài Print Server và driver Canon LBP2900 (CAPT), thêm máy in, chia sẻ và chẩn đoán lỗi. Khả năng tương thích cần được kiểm tra trên từng bản phân phối, kiến trúc và model máy in.

> **Phạm vi mạng:** Dự án hướng tới mạng LAN tin cậy và các thiết bị được phép trong tailnet Tailscale; không thiết kế để public trực tiếp ra Internet. Không cấu hình port forwarding cho TCP 631 (CUPS) hoặc TCP 445 (SMB). Đọc `install.sh` trước khi chạy bằng quyền quản trị. Nếu cần in qua Tailscale khác subnet, dùng `--remote-access` và bảo đảm firewall đang hoạt động.

---

## ✨ Tính năng

- CUPS Print Server và Web Interface
- Quản trị CUPS
- Samba Printer Sharing
- AirPrint (Bonjour / Avahi)
- IPP Everywhere
- Canon LBP2900 CAPT Driver Support
- Tự động thêm hàng đợi máy in Canon qua USB
- Chẩn đoán CUPS, USB, driver, chia sẻ mạng, AppArmor/SELinux và log CAPT
- Công cụ kiểm tra in qua IPP, sửa lỗi cơ bản và thu thập log

---

## 💻 Hệ điều hành

Script có các nhánh xử lý cho những họ phân phối Linux như Debian/Ubuntu, Fedora/RHEL, openSUSE và Arch. Danh sách hệ điều hành có thể dùng trong dự án:

- Ubuntu
- Debian
- Linux Mint
- Armbian
- Raspberry Pi OS
- CaramOS — Developed by Vietnam Linux Family (VNLF)
- Fedora
- openSUSE
- Arch Linux
- EndeavourOS
- CachyOS
- Manjaro
- Kali Linux
- Pop!_OS
- elementary OS

Danh sách trên không đồng nghĩa mọi tổ hợp hệ điều hành, phiên bản, kiến trúc và máy in đều đã được kiểm thử. Riêng driver CAPT cần chú ý kiến trúc ARM 32-bit; xem phần [Troubleshooting](#-troubleshooting).

---

# 🚀 Cài đặt nhanh

## Cách 1 - Clone repository (khuyến nghị)

```bash
git clone https://github.com/Huylighting/Linux-Print-server.git
cd Linux-Print-server
chmod +x install.sh
sudo ./install.sh
```

Chạy không tham số trong terminal sẽ mở menu tương tác. Để cài toàn bộ bằng một lệnh:

```bash
sudo ./install.sh all
```

Lệnh `all` thực hiện cài Print Server, build/cài driver Canon LBP2900, thêm máy in và bật chia sẻ nếu máy in đã được nhận qua USB.

## Cách 2 - Tải riêng install.sh

```bash
wget -O install.sh https://raw.githubusercontent.com/Huylighting/Linux-Print-server/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

---

# 🧰 Các lệnh install.sh v2.0.0

Chạy các lệnh bằng `sudo`. Hầu hết lệnh cài đặt và quản trị sẽ tự yêu cầu quyền root.

| Lệnh | Chức năng |
|---|---|
| `sudo ./install.sh` | Mở menu tương tác trong terminal |
| `sudo ./install.sh all` | Cài Print Server + driver Canon LBP2900 + thêm máy in + chia sẻ |
| `sudo ./install.sh server` | Chỉ cài Print Server: CUPS, Samba, Avahi và cấu hình firewall |
| `sudo ./install.sh driver` | Build/cài driver Canon LBP2900 (captdriver) và thêm máy in |
| `sudo ./install.sh add` | Thêm/cập nhật máy in trong CUPS, tự tìm Canon USB |
| `sudo ./install.sh add --uri "usb://..."` | Thêm máy in với URI USB chỉ định |
| `sudo ./install.sh uninstall` | Gỡ hàng đợi máy in và driver; giữ CUPS/Samba/Avahi |
| `sudo ./install.sh uninstall --purge` | Như trên và xoá cả thư mục mã nguồn driver |
| `sudo ./install.sh doctor` | Chạy 9 nhóm kiểm tra chẩn đoán |
| `sudo ./install.sh test` | Gửi trang thử qua IPP và theo dõi job/log CAPT |
| `sudo ./install.sh test FILE` | Gửi file chỉ định để kiểm tra đường in IPP |
| `sudo ./install.sh fix` | Đặt filter vào thư mục CUPS chuẩn, huỷ job kẹt, restart CUPS và bật lại queue |
| `sudo ./install.sh fix --apparmor-complain` | Chuyển profile cupsd sang complain mode (xem cảnh báo bảo mật bên dưới) |
| `sudo ./install.sh reset-usb` | Reset kết nối USB của thiết bị Canon |
| `sudo ./install.sh share` | Bật chia sẻ máy in qua LAN và in địa chỉ kết nối |
| `sudo ./install.sh debug on` | Bật log chi tiết của CUPS |
| `sudo ./install.sh debug off` | Tắt log chi tiết sau khi thu thập |
| `sudo ./install.sh bundle` | Tạo gói log/thông tin chẩn đoán dạng `.tar.gz` |
| `sudo ./install.sh print FILE` | Gửi file vào hàng đợi máy in |
| `sudo ./install.sh status` | Xem nhanh USB, CUPS, driver, queue và job |
| `sudo ./install.sh gui` | Chọn file để in bằng giao diện Zenity (cần môi trường desktop) |
| `sudo ./install.sh --help` | Hiển thị hướng dẫn lệnh |

### Tuỳ chọn cho `server` và `all`

| Tuỳ chọn | Ý nghĩa |
|---|---|
| `--admin-user USER` | Thêm USER vào nhóm quản trị CUPS; mặc định là người gọi sudo |
| `--no-samba` | Bỏ qua cài đặt/cấu hình Samba |
| `--no-avahi` | Bỏ qua Avahi/Bonjour |
| `--no-firewall` | Không thay đổi luật firewall |
| `--remote-access` | Cho phép in qua nhiều dải mạng trong LAN tin cậy |
| `--printer-drivers` | Cài thêm gói `printer-driver-all` (rất nặng); `server` mặc định bật, `all` mặc định bỏ |
| `--no-printer-drivers` | Không cài `printer-driver-all` |

Ví dụ:

```bash
# Cài Print Server, không cài Samba và Avahi
sudo ./install.sh server --no-samba --no-avahi

# Chỉ định tài khoản quản trị CUPS
sudo ./install.sh server --admin-user ten_user

# Cho phép truy cập in qua nhiều subnet trong mạng tin cậy
sudo ./install.sh server --remote-access

# Cài server nhưng bỏ qua printer-driver-all
sudo ./install.sh server --no-printer-drivers
```

Các tuỳ chọn `--no-samba`, `--no-avahi`, `--no-firewall`, `--remote-access` và các tuỳ chọn driver có thể kết hợp. Script vẫn hỗ trợ cách gọi cũ như `sudo ./install.sh --no-samba`, tương đương `sudo ./install.sh server --no-samba`.

> **Lưu ý firewall:** Khi firewall được script cấu hình, các luật được giới hạn theo các dải IPv4 private phù hợp; không mở CUPS/SMB trực tiếp ra Internet. `--no-firewall` sẽ bỏ qua việc thay đổi firewall. Hãy kiểm tra luật thực tế trên máy trước khi triển khai.

> **OpenMediaVault (OMV):** Nếu OMV đang quản lý Samba/Avahi hoặc firewall, tránh để hai công cụ cùng quản lý một cấu hình. Có thể dùng `driver` để cài driver Canon, hoặc `server --no-samba --no-avahi --no-firewall` khi chỉ muốn cài phần CUPS mà không để script thay đổi các thành phần kia.

---

# 🖨️ Cài Canon LBP2900

Script v2.0.0 có thể build và cài driver CAPT từ mã nguồn `captdriver`, sau đó thêm hàng đợi Canon LBP2900 vào CUPS.

## Quy trình

1. Bật nguồn máy in và kết nối cáp USB với máy chủ.
2. Chạy lệnh cài toàn bộ hoặc chỉ cài driver:

   ```bash
   sudo ./install.sh driver
   ```

3. Nếu máy in chưa được kết nối khi cài driver, cắm USB rồi chạy:

   ```bash
   sudo ./install.sh add
   ```

4. Kiểm tra trạng thái và chia sẻ:

   ```bash
   sudo ./install.sh status
   sudo ./install.sh share
   ```

5. In thử qua IPP:

   ```bash
   sudo ./install.sh test
   ```

Có thể chỉ định URI USB nếu tự động dò không tìm thấy thiết bị:

```bash
lpinfo -v
sudo ./install.sh add --uri "usb://Canon/LBP2900?serial=..."
```

Tên hàng đợi mặc định và đường dẫn mã nguồn/driver được khai báo trong `install.sh`; có thể xem các biến cấu hình ở đầu script trước khi chạy.

## Thêm máy in từ máy khách

Sau khi `share` báo máy in đã được chia sẻ và CUPS đang lắng nghe trên mạng:

- **Windows:** Thêm máy in mạng bằng địa chỉ HTTP được script in ra, theo dạng `http://IP_MAY_CHU:631/printers/Canon_LBP2900`. Chọn **Microsoft IPP Class Driver** (hoặc **Generic**) khi được hỏi.
- **macOS / Linux / Android:** Dùng địa chỉ IPP được script in ra, theo dạng `ipp://IP_MAY_CHU:631/printers/Canon_LBP2900`.
- **AirPrint:** Cần Avahi/Bonjour và máy in được chia sẻ trong cùng mạng có thể khám phá dịch vụ.

Địa chỉ thực tế phụ thuộc IP, tên hàng đợi và cấu hình CUPS trên máy chủ. Dùng kết quả của `sudo ./install.sh share` thay vì sao chép nguyên địa chỉ ví dụ.

---

# 🛠️ Cài đặt thủ công (CUPS)

Các bước dưới đây dành cho trường hợp muốn tự cài CUPS thay vì dùng script. Khi dùng script, không cần lặp lại các bước cài đặt thủ công này.

## 1. Cài đặt CUPS

Trên Debian/Ubuntu:

```bash
sudo apt update
sudo apt install -y cups cups-filters
```

## 2. Bật dịch vụ CUPS

```bash
sudo systemctl enable --now cups
systemctl status cups
```

## 3. Chia sẻ máy in trong mạng nội bộ

Bật tính năng chia sẻ:

```bash
sudo cupsctl --share-printers
```

Sau đó, trong giao diện CUPS tại `http://localhost:631`, chọn hàng đợi máy in cần chia sẻ và bật **Share This Printer**. Chỉ cho phép client đáng tin cậy truy cập.

Để truy cập từ thiết bị ở subnet khác, cần cấu hình CUPS nhận kết nối trên giao diện mạng và giới hạn firewall vào các mạng riêng/tin cậy. Tuỳ chọn `--remote-access` của script hỗ trợ trường hợp này; nó không đồng nghĩa bật quản trị CUPS từ xa.

## 4. Kiểm tra cấu hình CUPS

```bash
sudo cupsctl
sudo systemctl status cups --no-pager
```

Nếu cần chỉnh `/etc/cups/cupsd.conf`, hãy sao lưu trước, chỉ sửa các chỉ thị cần thiết và kiểm tra quyền truy cập sau khi khởi động lại dịch vụ:

```bash
sudo cp -a /etc/cups/cupsd.conf /etc/cups/cupsd.conf.manual-backup
sudo systemctl restart cups
```

Không thêm `ServerAlias *`, không đặt `Allow all` cho khu vực quản trị và không chuyển tiếp cổng 631 ra Internet.

## 5. Thêm quyền quản trị CUPS

```bash
sudo usermod -aG lpadmin "Tên người dùng"
```

Đăng xuất/đăng nhập lại để nhóm mới có hiệu lực. Script có tuỳ chọn `--admin-user USER` để thêm tài khoản quản trị trong quá trình cài Print Server.

## 6. Cài Samba và Avahi (nếu tự quản lý thủ công)

Samba:

```bash
sudo apt install -y samba
sudo systemctl restart smbd
systemctl status smbd
```

Avahi:

```bash
sudo apt install -y avahi-daemon
sudo systemctl enable --now avahi-daemon
```

## 7. Firewall

Ví dụ với UFW (thay `192.168.88.0/24` bằng subnet LAN thực tế):

```bash
sudo ufw allow from 192.168.88.0/24 to any port 631 proto tcp
```

Chỉ thêm luật Samba khi thực sự cần chia sẻ qua SMB, và giới hạn nguồn theo LAN/Tailscale tin cậy. Không dùng luật mở toàn cục nếu không cần. Kiểm tra lại bằng:

```bash
sudo ufw status numbered
```

## 8. Truy cập Web CUPS

Trên máy chủ:

```
http://localhost:631
```

Từ thiết bị được phép trong LAN/Tailscale (khi CUPS đã được cấu hình nhận kết nối và firewall cho phép):

```
http://IP_LAN_SERVER:631
http://TAILSCALE_IP_SERVER:631
```

---

# 🔥 Troubleshooting

## Chạy chẩn đoán trước

Bắt đầu bằng:

```bash
sudo ./install.sh doctor
sudo ./install.sh status
```

Lệnh `doctor` kiểm tra hệ thống/kiến trúc, USB Canon, CUPS, filter và PPD, hàng đợi, chia sẻ IPP, firewall, AppArmor/SELinux, module `usblp` và log CAPT.

## Job bị kẹt hoặc máy in không phản hồi

```bash
sudo ./install.sh fix
sudo ./install.sh reset-usb
sudo ./install.sh test
```

`fix` huỷ job đang kẹt của hàng đợi Canon, khởi động lại CUPS và bật lại queue. `reset-usb` chỉ tác động thiết bị USB Canon được nhận diện. Nếu vẫn không phản hồi, tắt nguồn máy in vài giây rồi bật lại và thử lại.

## AppArmor chặn rastertocapt trên Debian 13

Trước tiên chạy:

```bash
sudo ./install.sh fix
sudo ./install.sh doctor
```

Chỉ khi log xác nhận AppArmor tiếp tục chặn `cupsd`/filter CAPT, có thể cân nhắc:

```bash
sudo ./install.sh fix --apparmor-complain
```

> **Cảnh báo bảo mật:** Tuỳ chọn này chuyển profile `/usr/sbin/cupsd` sang chế độ complain (ghi nhận vi phạm thay vì chặn), làm giảm mức bảo vệ AppArmor của CUPS. Chỉ dùng để kiểm tra/tạm khắc phục trên máy tin cậy. Có thể hoàn tác bằng `sudo aa-enforce /usr/sbin/cupsd`.

Tham khảo: [captdriver issue #50 - AppArmor prevents the driver from working on Debian 13](https://github.com/mounaiban/captdriver/issues/50).

## Lỗi USB/CAPT hoặc job hoàn tất nhưng không có giấy

Bật log chi tiết, chạy lại test, sau đó thu gói chẩn đoán:

```bash
sudo ./install.sh debug on
sudo ./install.sh test
sudo ./install.sh debug off
sudo ./install.sh bundle
```

Gói `.tar.gz` được tạo trong thư mục hiện tại. Script che số serial USB trong một số thông tin đã thu thập, nhưng log vẫn có thể chứa tên máy, địa chỉ IP hoặc tên file đã in. Hãy tự kiểm tra nội dung trước khi gửi cho người khác.

Một số tham chiếu upstream liên quan đến CAPT:

- [captdriver issue #8 - Print job stuck at "Rendering completed"](https://github.com/mounaiban/captdriver/issues/8).
- [captdriver issue #14 - CUPS backend bug](https://github.com/mounaiban/captdriver/issues/14).

Các issue này là tài liệu tham khảo về lỗi đã được báo cáo; không khẳng định mọi trường hợp có cùng nguyên nhân.

## ARM 32-bit (armhf)

Script có cảnh báo về lỗi `bad reply from printer` đã được báo cáo với captdriver trên ARM 32-bit. Nếu bo mạch hỗ trợ, cân nhắc hệ điều hành 64-bit (aarch64). Tham khảo [captdriver issue #8](https://github.com/mounaiban/captdriver/issues/8).


## Unauthorized

Nguyên nhân

```
DefaultAuthType=Negotiate
```

Khắc phục

```bash
sudo cupsctl DefaultAuthType=Basic

sudo systemctl restart cups
```

---

## Không đăng nhập được

Kiểm tra

```bash
id "Tên người dùng"
```

```bash
groups "Tên người dùng"
```

Nếu chưa có

```
lpadmin
```

thì thêm

```bash
sudo usermod -aG lpadmin "Tên người dùng"
```

---

## Kiểm tra CUPS

```bash
sudo cupsctl
```

---

## Kiểm tra Samba

```bash
systemctl status smbd
```

---

## Kiểm tra Avahi

```bash
systemctl status avahi-daemon
```

---

# 🌐 Nền tảng máy khách

- Windows
- macOS
- Linux
- Android
- iPhone / AirPrint
- IPP Everywhere (tuỳ khả năng tương thích của máy in và client)

---

# 📚 Dự án liên quan

- Docker
- HomeLab
- NAS
- Home Assistant
- Nextcloud
- Tailscale
- Pi-hole
- AdGuard Home
- Minecraft Server

---

Made with ❤️ by HuyLighting and ChatGPT (ChatGPT.com)
