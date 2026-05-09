#!/bin/bash
###############################################################################
# RTL8188ETV Driver Installation Script for Fedora Linux
# Version: 1.0
# Target: Kernel 5.15+ with DKMS support
###############################################################################

set -e

DRIVER_NAME="8188eu"
DRIVER_VERSION="5.3.9"
REPO_URL="https://github.com/aircrack-ng/rtl8188eus.git"
BLACKLIST_FILE="/etc/modprobe.d/realtek-rtl8188etv.conf"

echo "=========================================="
echo "RTL8188ETV Driver Installer for Fedora"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (use sudo)"
    exit 1
fi

# Detect Fedora version and kernel
FEDORA_VERSION=$(rpm -E %fedora 2>/dev/null || echo "unknown")
KERNEL_VERSION=$(uname -r)
echo "Fedora Version: $FEDORA_VERSION"
echo "Kernel Version: $KERNEL_VERSION"
echo ""

# Step 1: Install dependencies
echo "[1/10] Installing dependencies..."
dnf install -y kernel-headers-${KERNEL_VERSION} kernel-devel-${KERNEL_VERSION} \
    gcc make git bc elfutils-libelf-devel dkms \
    wireless-tools iw iproute2

# Step 2: Blacklist conflicting drivers
echo "[2/10] Blacklisting conflicting drivers..."
cat > ${BLACKLIST_FILE} << 'EOF'
# Blacklist conflicting Realtek drivers for RTL8188ETV
blacklist r8188eu
blacklist rtl8xxxu
blacklist rtl8188eu
EOF

# Remove conflicting modules if loaded
modprobe -r r8188eu 2>/dev/null || true
modprobe -r rtl8xxxu 2>/dev/null || true
modprobe -r rtl8188eu 2>/dev/null || true

# Step 3: Clone repository
echo "[3/10] Cloning driver repository..."
BUILD_DIR="/usr/src/${DRIVER_NAME}-${DRIVER_VERSION}"
rm -rf ${BUILD_DIR}
git clone --depth=1 -b v5.3.9 ${REPO_URL} ${BUILD_DIR}
cd ${BUILD_DIR}

# Step 4: Apply patches
echo "[4/10] Applying compatibility patches..."
# Note: In a real scenario, patches would be copied here
# For this script, we apply inline modifications

# Modify Makefile for Fedora compatibility
cat >> Makefile << 'EOF'

# Fedora/Modern kernel compatibility
EXTRA_CFLAGS += -Wno-implicit-fallthrough
EXTRA_CFLAGS += -Wno-address-of-packed-member
EXTRA_CFLAGS += -Wno-maybe-uninitialized
EXTRA_CFLAGS += -Wno-discarded-qualifiers
EXTRA_CFLAGS += -Wno-int-conversion
EXTRA_CFLAGS += -Wno-cast-function-type
EXTRA_CFLAGS += -Wno-format-overflow
EXTRA_CFLAGS += -DCONFIG_MONITOR_MODE
EXTRA_CFLAGS += -DCONFIG_IOCTL_CFG80211
EXTRA_CFLAGS += -DCONFIG_CONCURRENT_MODE
EOF

# Update MODDESTDIR for Fedora
sed -i 's|MODDESTDIR := /lib/modules/|MODDESTDIR := /usr/lib/modules/|g' Makefile

# Step 5: Create DKMS configuration
echo "[5/10] Setting up DKMS..."
cat > dkms.conf << EOF
PACKAGE_NAME="${DRIVER_NAME}"
PACKAGE_VERSION="${DRIVER_VERSION}"
CLEAN="make clean"
MAKE[0]="make -j\$(nproc) KVER=\${kernelver} KSRC=/lib/modules/\${kernelver}/build"
BUILT_MODULE_NAME[0]="${DRIVER_NAME}"
DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless"
AUTOINSTALL="yes"
REMAKE_INITRD="no"
EOF

# Step 6: Add DKMS module
echo "[6/10] Adding DKMS module..."
dkms add -m ${DRIVER_NAME} -v ${DRIVER_VERSION} 2>/dev/null || true

# Step 7: Build module
echo "[7/10] Building kernel module..."
dkms build -m ${DRIVER_NAME} -v ${DRIVER_VERSION}

# Step 8: Install module
echo "[8/10] Installing kernel module..."
dkms install -m ${DRIVER_NAME} -v ${DRIVER_VERSION}

# Step 9: Load module
echo "[9/10] Loading driver module..."
depmod -a
modprobe ${DRIVER_NAME}

# Step 10: Verify installation
echo "[10/10] Verifying installation..."
echo ""
echo "=== Kernel Messages ==="
dmesg | grep -i "rtl8188\|8188eu" | tail -20

echo ""
echo "=== Loaded Modules ==="
lsmod | grep 8188eu

echo ""
echo "=== Network Interfaces ==="
ip link show | grep -E "wlan|wlx"

echo ""
echo "=== USB Devices ==="
lsusb | grep -i "Realtek\|8188"

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Connect your RTL8188ETV USB adapter"
echo "2. Check 'ip link' for new interface"
echo "3. Test monitor mode: sudo airmon-ng start <interface>"
echo "4. Test injection: sudo aireplay-ng -9 <interface>"
echo ""
echo "To remove driver: sudo dkms remove ${DRIVER_NAME}/${DRIVER_VERSION} --all"
echo ""
