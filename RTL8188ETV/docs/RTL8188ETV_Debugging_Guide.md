# RTL8188ETV Driver - Complete Debugging & Troubleshooting Guide
## Fedora Linux | Kernel 5.15+ | Realtek USB Wi-Fi

---

## PART A: MODULE LOAD FAILURES

### Symptom: `modprobe 8188eu` returns error or module won't load

**Step 1: Check kernel messages for load errors**
```bash
sudo dmesg | grep -i "8188eu\|rtl8188" | tail -30
```

**Step 2: Check module dependencies**
```bash
modinfo 8188eu
# Look for:
# - vermagic (must match your kernel version)
# - dependencies (cfg80211, usbcore, etc.)
```

**Step 3: Check if module exists**
```bash
find /lib/modules/$(uname -r) -name "8188eu.ko" 2>/dev/null
find /usr/lib/modules/$(uname -r) -name "8188eu.ko" 2>/dev/null
```

**Step 4: Manual load with debug**
```bash
# Remove if already loaded
sudo modprobe -r 8188eu 2>/dev/null || true

# Load with maximum debug
sudo insmod /path/to/8188eu.ko rtw_debug=7

# Check result immediately
sudo dmesg | tail -50
```

**Step 5: Check for symbol errors**
```bash
# If you see "Unknown symbol" errors:
sudo dmesg | grep "Unknown symbol"

# Check if required modules are loaded
lsmod | grep cfg80211
lsmod | grep mac80211

# Load dependencies manually
sudo modprobe cfg80211
sudo modprobe usbcore
```

**Step 6: Rebuild for current kernel**
```bash
cd /usr/src/8188eu-5.3.9
sudo make clean
sudo make -j$(nproc) KVER=$(uname -r) KSRC=/lib/modules/$(uname -r)/build
sudo cp 8188eu.ko /lib/modules/$(uname -r)/kernel/drivers/net/wireless/
sudo depmod -a
sudo modprobe 8188eu
```

---

## PART B: MISSING WLAN INTERFACES

### Symptom: No `wlan0`, `wlx*`, or wireless interface appears after loading module

**Step 1: Verify USB device detection**
```bash
# List all USB devices
lsusb

# Look for lines like:
# Bus 001 Device 005: ID 0bda:8179 Realtek Semiconductor Corp. RTL8188EUS 802.11n Wireless Network Adapter

# Get detailed USB info
lsusb -v -d 0bda:8179 2>/dev/null | head -30

# Check USB device tree
lsusb -t
```

**Step 2: Check kernel USB detection**
```bash
sudo dmesg | grep -i "usb\|realtek\|rtl8188" | tail -40

# Look for:
# - "new high-speed USB device"
# - "USB device detected"
# - "rtl8188eu_probe" or similar
# - Any errors after detection
```

**Step 3: Check if driver bound to device**
```bash
# Find your USB device path
USB_DEV=$(lsusb | grep -i "0bda:8179\|Realtek.*8188" | awk '{print $2"/"$4}' | sed 's/://')
echo "USB Device: $USB_DEV"

# Check driver binding
ls -la /sys/bus/usb/devices/${USB_DEV}/driver 2>/dev/null

# Check all USB interfaces
cat /sys/kernel/debug/usb/devices 2>/dev/null | grep -A5 -i "rtl8188\|0bda"
```

**Step 4: Force driver binding**
```bash
# If driver didn't bind automatically:
USB_ID="0bda 8179"  # VendorID ProductID for RTL8188ETV

# Add to driver's device ID table
echo "${USB_ID}" | sudo tee /sys/bus/usb/drivers/rtl8188eu/new_id 2>/dev/null || echo "${USB_ID}" | sudo tee /sys/bus/usb/drivers/8188eu/new_id 2>/dev/null || echo "Manual bind not available - check driver loaded"
```

**Step 5: Check network interface registration**
```bash
# All network interfaces
ip link show

# Wireless specific
iw dev

# Check sysfs for wireless devices
ls /sys/class/net/

# Check if device registered but not named wlan*
cat /proc/net/dev
```

**Step 6: Check cfg80211 registration**
```bash
# List all wireless PHYs
iw phy

# If empty, cfg80211 registration failed
# Check dmesg for cfg80211 errors
sudo dmesg | grep -i "cfg80211\|wiphy" | tail -20
```

**Step 7: Restart networking stack**
```bash
# Remove and re-add module
sudo modprobe -r 8188eu
sleep 2
sudo modprobe 8188eu

# Restart NetworkManager (if installed)
sudo systemctl restart NetworkManager

# Or use iproute2 to bring up
sudo ip link set wlan0 up 2>/dev/null || echo "Interface not found"
```

---

## PART C: MONITOR MODE FAILURES

### Symptom: `iw dev wlan0 set type monitor` returns error

**Step 1: Verify current interface state**
```bash
# Check current mode
iw dev wlan0 info
iwconfig wlan0 2>/dev/null || echo "iwconfig not available, using iw"

# Check if interface is UP (must be DOWN to change type)
ip link show wlan0
```

**Step 2: Proper monitor mode sequence**
```bash
# Standard method using iw
sudo ip link set wlan0 down
sudo iw dev wlan0 set type monitor
sudo ip link set wlan0 up

# Verify
iw dev wlan0 info | grep type
```

**Step 3: Using airmon-ng**
```bash
# Kill interfering processes
sudo airmon-ng check kill

# Start monitor mode
sudo airmon-ng start wlan0

# Check result
iw dev | grep -A5 "Interface"
```

**Step 4: Debug cfg80211 interface change**
```bash
# Enable kernel debug for cfg80211
# (Must be compiled with CONFIG_CFG80211_DEBUGFS)

# Check if debugfs available
ls /sys/kernel/debug/ieee80211/ 2>/dev/null

# Monitor dmesg during mode change
sudo dmesg -C  # Clear buffer
sudo ip link set wlan0 down
sudo iw dev wlan0 set type monitor
sudo dmesg | tail -30
```

**Step 5: Check driver monitor mode support**
```bash
# Check supported interface types
iw phy phy0 info | grep -A20 "Supported interface modes"

# Should show:
#  * IBSS
#  * managed
#  * AP
#  * AP/VLAN
#  * monitor          <-- THIS MUST BE PRESENT
#  * P2P-client
#  * P2P-GO
```

**Step 6: Force monitor mode via driver parameter**
```bash
# Some drivers support module parameter
sudo modprobe -r 8188eu
sudo modprobe 8188eu rtw_monitor_mode=1  # Check if parameter exists

# Check available parameters
modinfo 8188eu | grep parm
```

**Step 7: Manual channel setting in monitor mode**
```bash
# After setting monitor mode, set channel
sudo iw dev wlan0 set channel 6

# Or with frequency
sudo iw dev wlan0 set freq 2437

# Verify
iw dev wlan0 info
```

---

## PART D: KERNEL PANICS / OOPS

### Symptom: System crashes, kernel oops, or freezes when using driver

**Step 1: Capture oops message**
```bash
# After reboot, check previous boot logs
sudo journalctl -k -b -1 | grep -A50 "Oops\|BUG\|panic"

# Or check dmesg if system didn't reboot
sudo dmesg | grep -B5 -A50 "Oops\|BUG\|panic\|Call Trace"
```

**Step 2: Enable kdump for crash capture**
```bash
# Install kdump tools
sudo dnf install kexec-tools crash

# Enable kdump
sudo systemctl enable kdump.service
sudo systemctl start kdump.service

# Configure crash kernel memory
sudo grubby --update-kernel=ALL --args="crashkernel=256M"
```

**Step 3: Common panic causes and fixes**

**NULL pointer dereference:**
```bash
# Check dmesg for:
# "Unable to handle kernel NULL pointer dereference"
# Look at the Call Trace to find the function

# Common fix: Add NULL checks in probe/disconnect
# Edit os_dep/usb_intf.c and os_dep/os_intfs.c
```

**Use-after-free:**
```bash
# Symptoms: Random crashes during USB disconnect
# Check dmesg for:
# "general protection fault"
# "Kernel panic - not syncing: stack-protector"

# Fix: Ensure proper cleanup order in disconnect handler
```

**Memory corruption:**
```bash
# Enable slab debugging
sudo grubby --update-kernel=ALL --args="slub_debug=FZPU"

# Reboot and test
# Check dmesg for slab corruption warnings
```

**Step 4: Safe testing mode**
```bash
# Load module with minimal features
sudo modprobe -r 8188eu
sudo modprobe 8188eu rtw_power_mgnt=0 rtw_ips_mode=0

# Disable power management to avoid suspend/resume bugs
```

---

## PART E: USB DISCONNECTS

### Symptom: Device randomly disconnects, "device not accepting address", or USB resets

**Step 1: Check USB power management**
```bash
# Disable USB autosuspend for the device
USB_DEV=$(lsusb | grep -i "0bda:8179" | awk '{print $2"/"$4}' | sed 's/://')
echo "on" | sudo tee /sys/bus/usb/devices/${USB_DEV}/power/control

# Or disable globally
sudo grubby --update-kernel=ALL --args="usbcore.autosuspend=-1"
```

**Step 2: Check USB port power**
```bash
# Check for overcurrent conditions
sudo dmesg | grep -i "overcurrent\|power"

# Check USB port speed (should be 480M for USB 2.0)
lsusb -t | grep -i "480M\|5000M"
```

**Step 3: Disable USB selective suspend**
```bash
# Create systemd service to disable autosuspend
cat << 'EOF' | sudo tee /etc/systemd/system/usb-no-autosuspend.service
[Unit]
Description=Disable USB autosuspend for RTL8188ETV

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for f in /sys/bus/usb/devices/*/power/control; do echo on > "$f"; done'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable usb-no-autosuspend.service
sudo systemctl start usb-no-autosuspend.service
```

**Step 4: Check USB cable/port**
```bash
# Test with different USB port (preferably USB 2.0, not 3.0)
# Some Realtek chips have issues with USB 3.0 hubs

# Check for CRC errors
sudo dmesg | grep -i "crc\|error" | grep -i usb
```

**Step 5: Driver-level USB stability patch**
```bash
# Increase URB timeout and retry count
# Edit hal/rtl8188e/usb/usb_ops_linux.c
# Look for: rtw_usb_ctrl_msg() and rtw_usb_bulk_msg()
# Increase timeout values
```

---

## PART F: PACKET INJECTION FAILURES

### Symptom: `aireplay-ng -9 wlan0mon` shows 0/0 successful injections

**Step 1: Verify monitor mode is active**
```bash
# Check interface is in monitor mode
iw dev wlan0mon info | grep type
# Should show: type monitor

# Check if interface is UP
ip link show wlan0mon | grep "state UP"
```

**Step 2: Test injection with aireplay-ng**
```bash
# Test injection without specific AP
sudo aireplay-ng -9 wlan0mon

# Test with specific AP (more reliable)
sudo aireplay-ng -9 -a AA:BB:CC:DD:EE:FF wlan0mon

# Look for:
# "Injection is working!"
# Or "Found X APs" and "X/XX tests successful"
```

**Step 3: Check TX power**
```bash
# Check current TX power
iw dev wlan0mon info | grep txpower

# Set TX power if too low
sudo iw dev wlan0mon set txpower fixed 2000  # 20 dBm
```

**Step 4: Verify driver injection support**
```bash
# Check if driver reports injection capability
iw phy phy0 info | grep -A5 "frame injection"

# Should show: "frame injection" in supported commands
```

**Step 5: Test with tcpdump**
```bash
# Capture injected frames to verify TX path
sudo tcpdump -i wlan0mon -e -n -w /tmp/injection_test.pcap &
TCPDUMP_PID=$!

# Run injection test
sudo aireplay-ng -9 wlan0mon

# Stop capture
sudo kill $TCPDUMP_PID

# Analyze
sudo tcpdump -r /tmp/injection_test.pcap -e | head -20
```

**Step 6: Check for rate control issues**
```bash
# Injection often fails if rate control drops packets
# Check dmesg for rate-related messages
sudo dmesg | grep -i "rate\|xmit\|tx" | tail -20

# Try forcing a specific rate
sudo iw dev wlan0mon set bitrates legacy-2.4 1 2 5.5 11
```

**Step 7: Debug xmit path**
```bash
# Enable driver debug logging
echo 5 | sudo tee /proc/net/rtl8188eu/debug 2>/dev/null || echo "Debug proc entry not available"

# Monitor during injection
sudo dmesg -C
sudo aireplay-ng -9 wlan0mon
sudo dmesg | grep -i "xmit\|inject\|drop" | tail -30
```

---

## PART G: COMPATIBILITY WITH TOOLS

### airmon-ng
```bash
# Check version
airmon-ng --version

# Check for interfering processes
sudo airmon-ng check

# Kill interfering processes
sudo airmon-ng check kill

# Start monitor mode
sudo airmon-ng start wlan0

# If interface name changes, use new name
sudo airodump-ng wlan0mon
```

### aireplay-ng
```bash
# Test injection
sudo aireplay-ng -9 wlan0mon

# Deauth test (authorized network only!)
sudo aireplay-ng -0 1 -a <BSSID> -c <CLIENT> wlan0mon

# Fake auth
sudo aireplay-ng -1 0 -a <BSSID> -h <YOUR_MAC> wlan0mon
```

### iw
```bash
# List all commands
iw --help

# Device info
iw dev wlan0 info

# PHY info
iw phy

# Scan
sudo iw dev wlan0 scan

# Set channel
sudo iw dev wlan0 set channel 6

# Set monitor mode with flags
sudo iw dev wlan0 set type monitor
sudo iw dev wlan0 set monitor fcsfail control otherbss
```

### iproute2 (ip command)
```bash
# Show interfaces
ip link show

# Bring interface up/down
sudo ip link set wlan0 up
sudo ip link set wlan0 down

# Set monitor mode
sudo ip link set wlan0 down
sudo iw dev wlan0 set type monitor
sudo ip link set wlan0 up

# Check interface state
ip -s link show wlan0
```

---

## PART H: KERNEL STRUCTURES DEEP DIVE

### net_device (struct net_device)
```c
// Located in: include/linux/netdevice.h

struct net_device {
    char name[IFNAMSIZ];              // "wlan0", "wlx00c0ca..."
    char *ifalias;                    // User-defined alias
    unsigned long mem_end;            // Shared mem end
    unsigned long mem_start;          // Shared mem start
    unsigned long base_addr;          // Device I/O address
    int irq;                          // Device IRQ number

    unsigned long state;              // Device state flags
    struct list_head dev_list;        // Global device list
    struct list_head napi_list;       // NAPI device list

    const struct net_device_ops *netdev_ops;  // Device operations
    const struct ethtool_ops *ethtool_ops;    // Ethtool operations

    unsigned int flags;               // IFF_UP, IFF_BROADCAST, etc.
    unsigned int priv_flags;          // IFF_802_1Q_VLAN, etc.

    unsigned char dev_addr[MAX_ADDR_LEN];  // MAC address
    unsigned char broadcast[MAX_ADDR_LEN]; // Broadcast address

    struct netdev_queue *_tx;         // TX queues
    unsigned int num_tx_queues;

    struct net_device_stats stats;    // Basic statistics

    struct wireless_dev *ieee80211_ptr;  // cfg80211 pointer (for wireless)

    void *priv;                       // Driver private data (_adapter)
};
```

**In rtl8188eus driver:**
- Allocated in `rtw_init_netdev()` (os_dep/os_intfs.c)
- `priv` points to `_adapter` structure
- `netdev_ops` set to `rtw_netdev_ops`
- `wireless_handlers` set for wext compatibility

### wireless_dev (struct wireless_dev)
```c
// Located in: include/net/cfg80211.h

struct wireless_dev {
    struct wiphy *wiphy;              // PHY device capabilities
    enum nl80211_iftype iftype;       // NL80211_IFTYPE_STATION,
                                      // NL80211_IFTYPE_MONITOR, etc.

    struct list_head list;            // List of interfaces on wiphy
    struct net_device *netdev;        // Associated network device

    u32 identifier;                   // Interface identifier

    struct list_head mgmt_registrations;  // Frame registrations
    spinlock_t mgmt_registrations_lock;

    struct work_struct cleanup_work;  // Cleanup workqueue

    // Current channel settings
    struct cfg80211_chan_def preset_chandef;

    // Beacon interval (for AP mode)
    u16 beacon_interval;

    // SSID (for AP/IBSS)
    u8 ssid[IEEE80211_MAX_SSID_LEN];
    u8 ssid_len;

    // Current BSS (for station mode)
    struct cfg80211_bss *current_bss;

    // ... more fields
};
```

**In rtl8188eus driver:**
- Embedded in `_adapter` structure as `wdev` and `rtw_wdev`
- `iftype` changed by `cfg80211_rtw_change_iface()`
- `wiphy` initialized in `rtw_cfg80211_init_wiphy()`

### sk_buff (struct sk_buff)
```c
// Located in: include/linux/skbuff.h

struct sk_buff {
    struct sk_buff *next;             // Next buffer in list
    struct sk_buff *prev;             // Previous buffer in list

    struct sk_buff_head *list;        // List we are on

    struct sock *sk;                  // Socket we belong to
    ktime_t tstamp;                   // Arrival/departure timestamp

    struct net_device *dev;           // Device we arrived on/are leaving by

    // Layer 4 header offset from head->data
    __u16 transport_header;
    // Layer 3 header offset
    __u16 network_header;
    // Layer 2 header offset
    __u16 mac_header;

    unsigned char *head;              // Head of buffer
    unsigned char *data;              // Data head pointer
    unsigned char *tail;              // Tail pointer
    unsigned char *end;               // End pointer

    unsigned int len;                 // Length of actual data
    unsigned int data_len;            // Length of paged data
    __u16 mac_len;                    // MAC header length
    __u16 hdr_len;                    // Header length

    __be16 protocol;                  // Packet protocol (ETH_P_IP, etc.)

    __u16 queue_mapping;              // Queue mapping for multiqueue devices

    __u8 ip_summed:2;                 // Driver fed us an IP checksum
    __u8 csum_complete_sw:1;
    __u8 csum_level:2;
    __u8 pkt_type:3;                  // Packet class (broadcast, etc.)

    __u8 priority;                    // Packet priority (QoS)
    __u8 ipvs_property:1;
    __u8 peeked:1;
    __u8 nf_trace:1;
    __u8 protocol_all:1;

    __u32 hash;                       // Packet hash
    __be16 vlan_proto;                // VLAN protocol
    __u16 vlan_tci;                   // VLAN TCI

    // ... many more fields
};
```

**In rtl8188eus driver:**
- **RX path**: `recv_linux.c` allocates sk_buff and copies frame data
- **TX path**: `xmit_linux.c` extracts data from sk_buff for transmission
- **Monitor mode**: sk_buff contains radiotap header + 802.11 frame

### ieee80211_hdr (struct ieee80211_hdr)
```c
// Located in: include/linux/ieee80211.h

struct ieee80211_hdr {
    __le16 frame_control;             // Type, subtype, flags
    __le16 duration_id;               // Duration/ID field

    /* Address fields - meaning depends on frame type:
     * Management: addr1=DA, addr2=SA, addr3=BSSID
     * Data (to DS): addr1=BSSID, addr2=SA, addr3=DA
     * Data (from DS): addr1=DA, addr2=BSSID, addr3=SA
     * Data (WDS): addr4=SA of original sender
     */
    u8 addr1[ETH_ALEN];              // Receiver Address / BSSID
    u8 addr2[ETH_ALEN];              // Transmitter Address / Source
    u8 addr3[ETH_ALEN];              // Destination / Filtering Address
    __le16 seq_ctrl;                 // Sequence Control (seqnum + frag)

    // addr4 only present in 4-address format (WDS)
    u8 addr4[ETH_ALEN];              // Optional: Address 4
} __attribute__((packed));

// Frame Control field breakdown:
// Bits 0-1: Version (always 0)
// Bits 2-3: Type (0=Management, 1=Control, 2=Data, 3=Reserved)
// Bits 4-7: Subtype (depends on Type)
// Bit 8: To DS
// Bit 9: From DS
// Bit 10: More Fragments
// Bit 11: Retry
// Bit 12: Power Management
// Bit 13: More Data
// Bit 14: Protected Frame (WEP/WPA)
// Bit 15: Order (strictly ordered)
```

**In rtl8188eus driver:**
- Parsed in `core/rtw_ieee80211.c`
- Used for frame classification in RX path
- Built for TX frames in `core/rtw_xmit.c`

### usb_interface (struct usb_interface)
```c
// Located in: include/linux/usb.h

struct usb_interface {
    struct usb_host_interface *altsetting;
    struct usb_host_interface *cur_altsetting;
    unsigned num_altsetting;

    struct usb_interface_descriptor desc;  // USB descriptor

    struct usb_device *usb_dev;       // Parent USB device
    struct device dev;                // Generic device interface

    struct device *usb_intf_dev;      // USB interface device
    struct work_struct reset_ws;      // Reset workstruct

    unsigned int minor;               // Minor number (for usbfs)
    unsigned int condition;           // Device state

    struct usb_driver *driver;        // USB driver bound to this interface
    struct usb_device_id *id;         // Device ID that matched

    // ... sysfs, PM, etc.
};
```

**In rtl8188eus driver:**
- Passed to `rtw_usb_probe()` in `os_dep/usb_intf.c`
- Used to get `usb_device` via `interface_to_usbdev()`
- Driver stores pointer in `dvobj_priv->pusbintf`

### wiphy (struct wiphy)
```c
// Located in: include/net/cfg80211.h

struct wiphy {
    u8 perm_addr[ETH_ALEN];           // Permanent MAC address
    u8 addr_mask[ETH_ALEN];          // MAC address mask

    struct ieee80211_supported_band bands[NUM_NL80211_BANDS];
                                      // 2.4GHz, 5GHz, 6GHz support

    u32 interface_modes;              // Supported interface types bitmask
                                      // BIT(NL80211_IFTYPE_STATION)
                                      // BIT(NL80211_IFTYPE_MONITOR)
                                      // etc.

    u32 max_scan_ssids;               // Max SSIDs per scan request
    u16 max_scan_ie_len;              // Max IE length in scan
    u16 max_num_pmkids;               // Max PMKIDs for WPA2

    u8 max_num_pmkids;
    u8 max_remain_on_channel_duration;  // Max remain-on-channel (msec)

    u32 available_antennas_tx;        // TX antennas bitmap
    u32 available_antennas_rx;        // RX antennas bitmap

    u32 probe_resp_offload;           // Probe response offload support

    const struct ieee80211_regdomain *regd;  // Regulatory domain

    struct dentry *debugfsdir;        // Debugfs directory

    struct device dev;                // Device structure
    bool registered;                  // Registration status

    // ... many more fields for features, power, etc.

    void *priv;                       // Driver private data
};
```

**In rtl8188eus driver:**
- Allocated by `wiphy_new()` in `rtw_cfg80211_init_wiphy()`
- `priv` points to `_adapter`
- `interface_modes` set to include MONITOR bit
- Bands set to 2.4GHz (802.11b/g/n) for RTL8188E

---

## PART I: MODERN KERNEL API MIGRATION

### Timer API Changes (Kernel 4.14+)

**OLD (pre-4.14):**
```c
struct timer_list my_timer;
setup_timer(&my_timer, my_callback, (unsigned long)data);
my_timer.expires = jiffies + HZ;
add_timer(&my_timer);
```

**NEW (4.14+):**
```c
struct timer_list my_timer;
timer_setup(&my_timer, my_callback, 0);
my_timer.expires = jiffies + HZ;
add_timer(&my_timer);
```

**Callback signature change:**
```c
// OLD:
void my_callback(unsigned long data)

// NEW:
void my_callback(struct timer_list *t)
{
    // Get data via from_timer() macro
    struct my_struct *data = from_timer(data, t, my_timer);
}
```

### access_ok() Changes (Kernel 5.0+)

**OLD:**
```c
if (!access_ok(VERIFY_READ, user_ptr, size))
    return -EFAULT;
```

**NEW:**
```c
if (!access_ok(user_ptr, size))  // 'type' argument removed
    return -EFAULT;
```

### file_operations Changes

**OLD:**
```c
static const struct file_operations my_fops = {
    .ioctl = my_ioctl,
    .read = my_read,
    .write = my_write,
};
```

**NEW:**
```c
static const struct file_operations my_fops = {
    .unlocked_ioctl = my_ioctl,    // Replaces .ioctl
    .compat_ioctl = my_ioctl_compat,
    .read = my_read,
    .write = my_write,
};
```

### kernel_read()/kernel_write() Changes (Kernel 4.14+)

**OLD:**
```c
kernel_read(file, offset, buf, count);
```

**NEW:**
```c
kernel_read(file, buf, count, &offset);
```

### netif_napi_add() Changes (Kernel 5.10+)

**OLD:**
```c
netif_napi_add(dev, napi, poll_fn, weight);
```

**NEW:**
```c
netif_napi_add_weight(dev, napi, poll_fn, weight);
// or with NAPI config:
netif_napi_add(dev, napi, poll_fn);
```

---

## PART J: PROFESSIONAL DEVELOPMENT PRACTICES

### 1. Coding Style
```bash
# Check your code against kernel style
sudo dnf install kernel-tools
./scripts/checkpatch.pl --file os_dep/os_intfs.c

# Common fixes:
# - Use tabs for indentation
# - 80 character line limit
# - Opening brace on same line for functions
# - Space after keywords (if, while, for)
# - No spaces around unary operators
```

### 2. Debug Logging Best Practices
```c
// Use appropriate log level:
pr_err()     // Errors that prevent operation
pr_warn()    // Warnings that don't prevent operation
pr_info()    // Important state changes (probe, connect, etc.)
pr_debug()   // Detailed debugging (compiled out in production)

// Format:
pr_info("[DRIVER-SUBSYS] %s: message with %s
", __func__, variable);

// Never:
// - Use printk() directly (use pr_* macros)
// - Log in hot paths (RX/TX per-packet) at info level
// - Include sensitive data (keys, passwords)
```

### 3. NULL Pointer Checks
```c
// Always check pointers before dereferencing:
struct my_struct *ptr = some_function();
if (!ptr) {
    pr_err("[DRIVER] %s: NULL pointer from some_function
", __func__);
    return -EINVAL;
}

// Use WARN_ON() for conditions that shouldn't happen:
if (WARN_ON(!ptr))
    return -EFAULT;
```

### 4. Locking Rules
```c
// Always acquire locks in consistent order to prevent deadlocks
// Document lock ordering:
// 1. rtw_lock1
// 2. rtw_lock2
// 3. rtw_lock3

// Use spin_lock_irqsave() in interrupt context
// Use spin_lock() in process context
// Always pair lock/unlock

spinlock_t my_lock;
spin_lock_init(&my_lock);

// Critical section:
unsigned long flags;
spin_lock_irqsave(&my_lock, flags);
// ... critical code ...
spin_unlock_irqrestore(&my_lock, flags);
```

### 5. Memory Management
```c
// Use kernel memory allocators:
kmalloc(size, GFP_KERNEL);      // Sleepable context
kmalloc(size, GFP_ATOMIC);      // Atomic context (interrupt)
kzalloc(size, GFP_KERNEL);      // Zeroed allocation
kfree(ptr);                     // Free

// For large allocations:
vmalloc(size);                  // Virtual contiguous
vfree(ptr);                     // Free

// Check all allocations:
void *ptr = kmalloc(size, GFP_KERNEL);
if (!ptr)
    return -ENOMEM;
```

---

*End of Debugging Guide*
*Version: 1.0 | Fedora Linux | Kernel 5.15+*
