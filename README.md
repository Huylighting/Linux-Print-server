
# 🖨️ Linux Print Server with CUPS

Biến một máy tính Linux thành **Print Server** sử dụng **CUPS**, **Samba** và **Avahi** để chia sẻ máy in cho Windows, macOS, Linux, Android và iPhone.

> Dự án đã được tác giả báo cáo thử nghiệm trên Ubuntu 26.04 LTS với Canon LBP2900. Khả năng tương thích trên các bản phân phối/máy in khác cần được kiểm tra riêng.

> **Lưu ý bảo mật:** Trình cài đặt thay đổi cấu hình CUPS, Samba và firewall. Hãy đọc `install.sh` trước khi chạy bằng quyền quản trị. Chỉ mở truy cập máy in trong mạng tin cậy; không chuyển tiếp cổng CUPS (631) ra Internet. Các tùy chọn truy cập từ xa và chia sẻ máy in có thể làm tăng phạm vi truy cập.

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

> Chỉ bật chia sẻ khi cần. Cấu hình mặc định của CUPS giới hạn việc chia sẻ trong mạng cục bộ. Không thêm `ServerAlias *`, không đặt `Allow all` cho khu vực quản trị và không chuyển tiếp cổng 631 ra Internet.

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

```bash
sudo ufw allow samba

sudo ufw allow 631/tcp
```

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

Hoặc

```
http://IP_SERVER:631
```

---

# 11. Cài Canon LBP2900

Driver:

- https://github.com/hieplpvip/ubuntu_canon_printer: For Ubuntu or Linux
- https://github.com/agalakhov/captdriver: For Debian or Linux
- https://github.com/Codechickens/Canon-lbp2900-autoinstall: Debian troubleshooting/fix script for Canon LBP2900 (use if you encounter installation or driver issues on Debian).

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
