RTL8188ETV Fedora Driver Package
==================================
Version: 1.0
Date: 2026-05-08
Target: Fedora Linux, Kernel 5.15+

FOLDER STRUCTURE:
  patches/     - Kernel compatibility and debug patches
  config/      - DKMS configuration
  scripts/     - Installation and setup scripts
  docs/        - Full documentation and troubleshooting guides

QUICK START:
  1. Clone driver: git clone https://github.com/aircrack-ng/rtl8188eus.git
  2. cd rtl8188eus && git checkout v5.3.9
  3. Copy patches to driver root and apply:
     cp patches/*.patch .
     patch -p1 < patches/0001-fedora-kernel-compat.patch
     patch -p1 < patches/0002-monitor-injection-debug.patch
     patch -p1 < patches/0003-usb-debug-logging.patch
  4. cp config/dkms.conf .
  5. sudo bash scripts/install_driver.sh

DOCUMENTATION:
  docs/RTL8188ETV_Fedora_Driver_Guide.md    - Architecture & API guide
  docs/RTL8188ETV_Debugging_Guide.md        - Troubleshooting commands

IMPORTANT:
  This driver is DEPRECATED by upstream. Consider rtw88 first.
  For authorized security testing only.
