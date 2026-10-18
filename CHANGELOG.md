# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

---

## [1.2.1] - 2026-10-18

### Fixed

- Detect Samba sections independently so an existing `[printers]` section does not prevent adding a missing `[print$]` section.
- Validate Samba configuration with `testparm` when available.
- Detect systemd units with `systemctl cat` and select Samba service names by distribution family.
- Map CUPS and Avahi package names for Debian-family and other supported package-manager paths.
- Restrict UFW/firewalld rules created by the installer to private IPv4 ranges instead of opening printer-sharing ports globally.
- Keep remote CUPS sharing disabled by default and avoid enabling remote administration.

### Notes

- The installer has not been tested on physical printer hardware or every listed distribution.
- Arch package installation uses `pacman -Syu`, which updates the system as required by Arch's supported upgrade model.
- Existing administrator-managed Samba sections are preserved rather than rewritten automatically.

---

## [1.2.0] - 2026-10-18

### Security

- Keep remote CUPS access disabled unless the operator explicitly passes `--remote-access`.
- Stop forcing CUPS `DefaultAuthType=Basic`; preserve the distribution's authentication defaults.
- Do not add guest-enabled Samba printer sharing to the default printer share stanza.
- Avoid opening TCP 631 in the firewall unless remote CUPS access was explicitly requested.
- Add explicit warnings against exposing CUPS directly to the public Internet.

### Documentation

- Add third-party source attribution and clarify that Canon CAPT driver projects are independent upstream projects.
- Document the scope and compatibility limits of the Codechickens Canon LBP2900 autoinstall project.
- Add security notes and safer remote-access guidance.

### Notes

- This release has not yet been tested on physical printer hardware as part of this update.
- Review `install.sh` and test in a disposable environment before deploying on an existing print server.

## [1.1.0] - 2026-07-30

### Added

- Added automatic installation script (`install.sh`).
- Added Quick Install instructions in README.
- Added support for CUPS configuration.
- Added Samba printer sharing configuration.
- Added Avahi (Bonjour/AirPrint) support.
- Added automatic firewall configuration.
- Added installation verification.
- Added troubleshooting documentation.
- Added Canon LBP2900 driver installation guide.
- Added support for Ubuntu, Debian and Linux Mint.

### Changed

- Improved README structure.
- Simplified installation steps.
- Improved project documentation.
- Updated installation commands.
- Improved repository organization.

### Fixed

- Fixed incorrect GitHub download URL.
- Fixed CUPS remote administration configuration.
- Fixed README installation examples.
- Fixed installation permission issues.

---

## [1.0.0] - 2026-07-29

### Added

- Initial public release.
- CUPS Print Server installation.
- Samba integration.
- Avahi support.
- Remote administration.
- Canon LBP2900 testing.
- Basic project documentation.
- GitHub repository created.

---

## Upcoming

### Planned

- Support Raspberry Pi OS.
- Support Armbian.
- Support Fedora.
- Support Arch Linux.
- Support openSUSE.
- Support Docker deployment.
- Interactive installation menu.
- Automatic printer detection.
- Backup & Restore configuration.
- Multi-language documentation.
- GitHub Pages documentation.
