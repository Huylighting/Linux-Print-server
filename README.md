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
sudo usermod -aG lpadmin huylighting
```

Mở

```bash
sudo nano /etc/cups/cups-files.conf
```

Sửa

```
SystemGroup root lpadmin huylighting
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

https://github.com/hieplpvip/ubuntu_canon_printer

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
id huylighting
```

```bash
groups huylighting
```

Nếu chưa có

```
lpadmin
```

thì thêm

```bash
sudo usermod -aG lpadmin huylighting
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
