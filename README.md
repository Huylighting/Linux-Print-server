
# 🖨️ Linux Print Server with CUPS

Biến một máy tính Linux thành **Print Server** sử dụng **CUPS**, **Samba** và **Avahi** để chia sẻ máy in cho Windows, macOS, Linux, Android và iPhone.

> Dự án đã được tác giả báo cáo thử nghiệm trên Ubuntu 26.04 LTS với Canon LBP2900. Khả năng tương thích trên các bản phân phối/máy in khác cần được kiểm tra riêng.

> **Phạm vi mạng:** Dự án hướng tới mạng LAN tin cậy và các thiết bị được phép trong tailnet Tailscale; không thiết kế để public trực tiếp ra Internet. Không cấu hình port forwarding cho TCP 631 (CUPS) hoặc TCP 445 (SMB). Đọc `install.sh` trước khi chạy bằng quyền quản trị. Nếu cần in qua Tailscale khác subnet, dùng `--remote-access` và bảo đảm firewall đang hoạt động.

---

## ✨ Tính năng

- CUPS Print Server
- Web Interface
- Remote Administration
- Samba Printer Sharing
- AirPrint (Bonjour)
- IPP Everywhere
- Canon CAPT Driver Support
- Hỗ trợ nhiều bản phân phối Linux

---

## 💻 Hệ điều hành hỗ trợ

- Ubuntu
- Debian
- Linux Mint
- Caramos is developed by the Vietnam Linux Family (VNLF)
- Armbian
- Raspberry Pi OS
- Fedora
- openSUSE
- Arch Linux
- EndeavourOS
- CachyOS
- Manjaro
- Kali Linux
- Pop!_OS
- elementary OS

---
# Cách 1: Chạy bằng script
# 🚀 Quick Install

## Method 1 - Clone Repository (Recommended)

Clone repository

```bash
git clone https://github.com/Huylighting/Linux-Print-server.git
```

Di chuyển vào thư mục dự án

```bash
cd Linux-Print-server
```

Cấp quyền thực thi

```bash
chmod +x install.sh
```

Chạy trình cài đặt

```bash
sudo ./install.sh
```

---

## Method 2 - Download install.sh only

```bash
wget -O install.sh https://raw.githubusercontent.com/Huylighting/Linux-Print-server/main/install.sh
```

Sau đó

Cấp quyền thực thi

```bash
chmod +x install.sh
```

Chạy trình cài đặt

```bash
sudo ./install.sh
```

# Cách 2: Cài đặt thủ công:
# 1. Cài đặt CUPS

```bash
sudo apt update

sudo apt install -y cups cups-filters
```

---

# 2. Bật dịch vụ CUPS

```bash
sudo systemctl enable --now cups
```

Kiểm tra trạng thái

```bash
systemctl status cups
```

---

# 3. Chia sẻ máy in trong mạng nội bộ

> Chỉ bật chia sẻ khi cần. Mặc định, CUPS chia sẻ trong mạng cục bộ. Để truy cập qua Tailscale từ thiết bị ở subnet khác, cài/chạy script với `--remote-access`; tùy chọn này cho phép CUPS nhận kết nối từ giao diện mạng, vì vậy phải kết hợp firewall giới hạn truy cập. Không thêm `ServerAlias *`, không đặt `Allow all` cho khu vực quản trị và không chuyển tiếp cổng 631 ra Internet.

Bật tính năng chia sẻ:

```bash
sudo cupsctl --share-printers
```

Sau đó, trong giao diện CUPS tại `http://localhost:631`, chọn từng hàng đợi máy in cần chia sẻ và bật **Share This Printer**. Chỉ cho phép client đáng tin cậy truy cập.

Nếu thực sự cần chia sẻ qua nhiều subnet, hãy dùng tùy chọn `--remote-access` của script và giới hạn firewall vào các mạng riêng/tin cậy của bạn. Tùy chọn này không bật quản trị CUPS từ xa.

---

# 4. Kiểm tra cấu hình CUPS

Xem cấu hình hiện tại:

```bash
sudo cupsctl
sudo systemctl status cups --no-pager
```

Nếu phải chỉnh `/etc/cups/cupsd.conf`, hãy sao lưu trước, chỉ sửa các chỉ thị cần thiết và kiểm tra quyền truy cập sau khi khởi động lại dịch vụ:

```bash
sudo cp -a /etc/cups/cupsd.conf /etc/cups/cupsd.conf.manual-backup
sudo systemctl restart cups
```

---

# 5. Thêm quyền quản trị

```bash
sudo usermod -aG lpadmin "Tên người dùng"
```

Mở

```bash
sudo nano /etc/cups/cups-files.conf
```

Sửa

```
SystemGroup root lpadmin "Tên người dùng"
```

---

# 6. Cài Samba

```bash
sudo apt install samba -y
```

Restart

```bash
sudo systemctl restart smbd
```

Kiểm tra

```bash
systemctl status smbd
```

---

# 7. Cài Avahi

```bash
sudo apt install avahi-daemon -y
```

```bash
sudo systemctl enable --now avahi-daemon
```

---

# 8. Firewall

Ví dụ với UFW (thay `192.168.88.0/24` bằng subnet LAN thực tế của bạn):

```bash
sudo ufw allow from 192.168.88.0/24 to any port 631 proto tcp
sudo ufw allow in on tailscale0 to any port 631 proto tcp
```

Nếu cần chia sẻ máy in Windows qua Samba, chỉ mở các cổng Samba cho LAN/Tailscale khi cần; không dùng `ufw allow samba` toàn cục. Script tự thêm quy tắc cho các dải IPv4 private và giao diện Tailscale khi UFW/firewalld đang hoạt động. Kiểm tra lại bằng `sudo ufw status numbered`.

---

# 9. Kiểm tra cấu hình

```bash
grep -E "Browsing|Listen|Port|ServerAlias" /etc/cups/cupsd.conf
```

Kết quả

```
Port 631

Listen /run/cups/cups.sock

ServerAlias *

Browsing No
```

---

# 10. Truy cập Web

```
http://localhost:631
```

Hoặc từ thiết bị được phép trong LAN/Tailscale:

```
http://IP_LAN_SERVER:631
http://TAILSCALE_IP_SERVER:631
```

Địa chỉ Tailscale chỉ hoạt động khi CUPS được cấu hình nhận kết nối từ xa (ví dụ cài đặt với `--remote-access`) và firewall cho phép thiết bị đó.

---

# 11. Cài Canon LBP2900

Driver:

- https://github.com/hieplpvip/ubuntu_canon_printer: For Ubuntu or Linux
- https://github.com/agalakhov/captdriver: For Debian or Linux
- https://github.com/Codechickens/Canon-lbp2900-autoinstall: Canon LBP2900 installation script for Arch Linux and compatible distributions; Debian users may need to adapt the installation steps.

Sau khi cài

- Cắm USB
- Add Printer
- Canon LBP2900 CAPT

<img width="1080" height="2340" alt="Máy in Canon 2900 for Debian cre by Nguyễn Thành Nam" src="https://github.com/user-attachments/assets/6f40470e-8bca-489a-bba9-18a4e0689261" />

- Print Test Page

---

# 🔥 Troubleshooting

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

# 🌐 Hỗ trợ

- Windows
- macOS
- Linux
- Android
- iPhone
- AirPrint
- IPP Everywhere

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

Made with ❤️ by HuyLighting and ChatGPT (Chatgpt.com)
