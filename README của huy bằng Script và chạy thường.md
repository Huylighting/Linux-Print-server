# Linux Print Server

An open-source Linux Print Server powered by **CUPS**, **Samba**, and **Avahi**.

Build your own print server for home, office, school, or enterprise environments.

---

# 🚀 Quick Install

Clone the repository:

```bash
git clone https://github.com/Huylighting/Linux-Print-server.git
```

Go to the project directory:

```bash
cd Linux-Print-server
```

Make the installer executable:

```bash
chmod +x scripts/install.sh
```

Run the installer:

```bash
sudo ./scripts/install.sh
```

After installation, open:

```text
http://localhost:631
```

or

```text
http://SERVER_IP:631
```

> **Note**
>
> The installation script currently supports:
>
> - Ubuntu
> - Debian
> - Linux Mint

---

# 📂 Repository Structure

```text
Linux-Print-server
│
├── README.md
├── LICENSE
├── CHANGELOG.md
├── ROADMAP.md
├── CONTRIBUTING.md
├── SECURITY.md
├── CODE_OF_CONDUCT.md
│
├── docs/
│   ├── quick-install.md
│   ├── manual-install.md
│   ├── configuration.md
│   ├── troubleshooting.md
│   ├── faq.md
│   ├── ubuntu.md
│   └── debian.md
│
├── scripts/
│   ├── install.sh
│   └── common.sh
│
├── drivers/
│   └── canon-lbp2900.md
│
├── examples/
│   ├── cupsd.conf
│   ├── cups-files.conf
│   └── smb.conf
│
├── images/
│
└── .github/
```

---

# ✨ Features

- Easy installation
- Automatic dependency installation
- CUPS configuration
- Samba printer sharing
- Avahi (AirPrint / Bonjour)
- Firewall configuration
- Backup & Restore configuration
- Installation verification
- Open Source
- Lightweight
- Beginner friendly

---

# 💻 Supported Operating Systems

| Distribution | Status |
|--------------|--------|
| Ubuntu | ✅ |
| Debian | ✅ |
| Linux Mint | ✅ |
| Raspberry Pi OS | 🚧 |
| Armbian | 🚧 |
| Fedora | 🚧 |
| Arch Linux | 🚧 |
| openSUSE | 🚧 |

---

# 🖨 Supported Printers

Current tested printers

- Canon LBP2900

Coming soon

- HP
- Brother
- Epson
- Ricoh
- Kyocera

---

# 🛠 Installation Methods

There are two installation methods.

## Method 1 — Quick Install (Recommended)

```bash
git clone https://github.com/Huylighting/Linux-Print-server.git

cd Linux-Print-server

chmod +x scripts/install.sh

sudo ./scripts/install.sh
```

---

## Method 2 — Manual Installation

### Install CUPS

```bash
sudo apt update
sudo apt install cups cups-filters
```

### Enable CUPS

```bash
sudo systemctl enable --now cups
```

### Configure CUPS

```bash
sudo cupsctl --remote-any
```

Edit

```text
/etc/cups/cupsd.conf
```

Restart CUPS

```bash
sudo systemctl restart cups
```

---

### Add User

```bash
sudo usermod -aG lpadmin $USER
```

---

### Install Samba

```bash
sudo apt install samba
```

Edit

```text
/etc/samba/smb.conf
```

Restart

```bash
sudo systemctl restart smbd
```

---

### Install Avahi

```bash
sudo apt install avahi-daemon
```

Enable

```bash
sudo systemctl enable --now avahi-daemon
```

---

### Configure Firewall

```bash
sudo ufw allow samba
```

```bash
sudo ufw allow 631/tcp
```

---

# 🖨 Driver Repository

## Canon LBP2900

Ubuntu Canon CAPT Driver

https://github.com/hieplpvip/ubuntu_canon_printer

---

# 🔍 Verify Installation

Check CUPS

```bash
systemctl status cups
```

Check Samba

```bash
systemctl status smbd
```

Check Avahi

```bash
systemctl status avahi-daemon
```

Check CUPS configuration

```bash
sudo cupsctl
```

Open Web Interface

```text
http://localhost:631
```

---

# ⚙ Configuration Files

CUPS

```text
/etc/cups/cupsd.conf
```

CUPS Files

```text
/etc/cups/cups-files.conf
```

Samba

```text
/etc/samba/smb.conf
```

---

# 📸 Screenshots

Coming Soon

---

# 🛠 Troubleshooting

Common issues

- Unable to access CUPS
- Permission denied
- Printer Offline
- Samba not visible
- AirPrint not working
- Driver installation failed

Detailed documentation is available in

```text
docs/troubleshooting.md
```

---

# ❓ FAQ

### Does this project support Ubuntu?

Yes.

### Does it support Debian?

Yes.

### Does it support Linux Mint?

Yes.

### Does it support Fedora?

Coming Soon.

### Does it support Docker?

Planned.

---

# 🗺 Roadmap

## Version 1.0

- Ubuntu
- Debian
- Canon LBP2900
- CUPS
- Samba
- Avahi

## Version 1.1

- Linux Mint
- Raspberry Pi OS
- Armbian
- Installer Script

## Version 2.0

- Fedora
- Arch Linux
- openSUSE
- Docker Deployment

## Version 3.0

- Web Installer
- GitHub Pages
- Multi-language Documentation

---

# 🤝 Contributing

Contributions are welcome.

Please open an Issue before submitting a Pull Request.

---

# 📜 License

MIT License

---

# ❤️ Community

If you like this project,

⭐ Star this repository

🐛 Report bugs

💡 Suggest new features

📥 Submit Pull Requests

---

# 🙏 Credits

Project Author

**Huylighting**

Powered by

- Ubuntu
- Debian
- CUPS
- Samba
- Avahi

Special thanks to the Linux Open Source Community.

---

# 📈 Project Status

Current Version

```text
v1.0
```

Status

```text
Active Development
```

Repository

```text
https://github.com/Huylighting/Linux-Print-server
```
