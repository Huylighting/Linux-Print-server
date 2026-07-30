
# 🖨️ Linux Print Server with CUPS

Biến một máy tính Linux thành **Print Server** sử dụng **CUPS**, **Samba** và **Avahi** để chia sẻ máy in cho Windows, macOS, Linux, Android và iPhone.

> Dự án được thử nghiệm trên Ubuntu 26.04 LTS và Canon LBP2900.

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
# Cách 1:Chạy bằng lệnh Scripts
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

# 3. Cho phép truy cập từ xa

```bash
sudo cupsctl --remote-any
```

---

# 4. Chỉnh sửa cấu hình

```bash
sudo nano /etc/cups/cupsd.conf
```

Thêm

```
ServerAlias *
```

Kiểm tra

```
<Location />

Allow all

</Location>
```

```
<Location /admin>

Allow all

</Location>
```

Lưu

Restart

```bash
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

https://github.com/hieplpvip/ubuntu_canon_printer: For Ubuntu or Linux
https://github.com/agalakhov/captdriver: For Debian or Linux

Sau khi cài

- Cắm USB
- Add Printer
- Canon LBP2900 CAPT
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

Made with ❤️ by HuyLighting
