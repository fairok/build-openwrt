#!/bin/bash
#========================================================================================================================
# https://github.com/ophub/amlogic-s9xxx-openwrt
# Description: Automatically Build OpenWrt
# Function: Diy script (After Update feeds, Modify the default IP, hostname, theme, add/remove software packages, etc.)
# Source code repository: https://github.com/openwrt/openwrt / Branch: main
#========================================================================================================================

# ------------------------------- Main source started -------------------------------
#
# Add the default password for the 'root' user（Change the empty password to 'password'）
sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' package/base-files/files/etc/shadow

# Set etc/openwrt_release
# sed -i "s|DISTRIB_REVISION='.*'|DISTRIB_REVISION='R$(date +%Y.%m.%d)'|g" package/base-files/files/etc/openwrt_release
# echo "DISTRIB_SOURCECODE='official'" >>package/base-files/files/etc/openwrt_release

# Modify default IP（FROM 192.168.1.1 CHANGE TO 192.168.31.4）
# sed -i 's/192.168.1.1/192.168.31.4/g' package/base-files/files/bin/config_generate
#
# ------------------------------- Main source ends -------------------------------

# ------------------------------- Other started -------------------------------
#
# Add luci-app-amlogic
# git clone https://github.com/ophub/luci-app-amlogic.git package/luci-app-amlogic

# coolsnowwolf default software package replaced with Lienol related software package
# rm -rf feeds/packages/utils/{containerd,libnetwork,runc,tini}
# svn co https://github.com/Lienol/openwrt-packages/trunk/utils/{containerd,libnetwork,runc,tini} feeds/packages/utils

# rm -rf feeds/luci/luci-app-socat
# git clone https://github.com/chenmozhijin/luci-app-socat feeds/luci/luci-app-socat

# Add third-party software packages (The entire repository)
# git clone https://github.com/libremesh/lime-packages.git package/lime-packages
# Add third-party software packages (Specify the package)
# svn co https://github.com/libremesh/lime-packages/trunk/packages/{shared-state-pirania,pirania-app,pirania} package/lime-packages/packages
# Add to compile options (Add related dependencies according to the requirements of the third-party software package Makefile)
# sed -i "/DEFAULT_PACKAGES/ s/$/ pirania-app pirania ip6tables-mod-nat ipset shared-state-pirania uhttpd-mod-lua/" target/linux/armvirt/Makefile

# Apply patch
# git apply ../config/patches/{0001*,0002*}.patch --directory=feeds/luci

# ------------------------------- eMMC storage expansion started -------------------------------
# Inject a first-boot script that automatically creates a /data partition on the
# remaining unallocated eMMC space (R5S has 32 GB; rootfs only uses ~576 MiB).
# The script runs once on first boot via uci-defaults and then removes itself.
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-expand-emmc << 'BOOTSCRIPT'
#!/bin/sh

# Find the eMMC block device (prefer mmcblk1 which is the on-board eMMC on R5S;
# fall back to the first mmcblk device found).
DISK=""
for dev in /dev/mmcblk1 /dev/mmcblk0; do
    [ -b "$dev" ] && { DISK="$dev"; break; }
done

[ -z "$DISK" ] && { logger -t expand-emmc "No eMMC device found, skipping"; exit 0; }

# Only proceed when the 3rd partition does not already exist
[ -b "${DISK}p3" ] && { logger -t expand-emmc "Partition ${DISK}p3 already exists, skipping"; exit 0; }

logger -t expand-emmc "Creating /data partition on ${DISK}"

# Determine the end of the last existing partition dynamically so the new
# partition starts right after it, regardless of future rootfs size changes.
LAST_END="$(parted -s "$DISK" unit MiB print | awk '/^ *[0-9]/{end=$3} END{gsub(/MiB/,"",end); print end+1}')"
[ -z "$LAST_END" ] && LAST_END=580

parted -s "$DISK" mkpart primary ext4 "${LAST_END}MiB" 100% || {
    logger -t expand-emmc "parted failed"
    exit 1
}

# Allow the kernel to re-read the partition table
partprobe "$DISK" 2>/dev/null || true
sleep 2

PART="${DISK}p3"
[ -b "$PART" ] || { logger -t expand-emmc "Partition $PART not found after partprobe"; exit 1; }

# Format the new partition as ext4 and label it "data"
mkfs.ext4 -L data "$PART" || { logger -t expand-emmc "mkfs.ext4 failed"; exit 1; }

# Register the mount in fstab so it persists across reboots.
# Use the device path directly to avoid false matches on a pre-existing "data" label.
uci set fstab.data=mount
uci set fstab.data.device="$PART"
uci set fstab.data.target=/data
uci set fstab.data.fstype=ext4
uci set fstab.data.options=rw,relatime
uci set fstab.data.enabled=1
uci commit fstab

mkdir -p /data
mount "$PART" /data && logger -t expand-emmc "/data mounted successfully ($(df -h /data | tail -1 | awk '{print $2}') total)"
BOOTSCRIPT
chmod +x files/etc/uci-defaults/99-expand-emmc
# ------------------------------- eMMC storage expansion ends -------------------------------
#
# ------------------------------- Other ends -------------------------------
