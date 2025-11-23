#!/bin/bash -e

# Ensure the resize service is enabled for first boot
# This will automatically resize the root partition to fill the SD card

# Create a systemd service that resizes root filesystem on first boot
cat > /etc/systemd/system/resize2fs_once.service << 'EOF'
[Unit]
Description=Resize root filesystem to fill SD card
DefaultDependencies=no
After=local-fs.target systemd-remount-fs.service
Before=shutdown.target
Conflicts=shutdown.target
ConditionPathExists=!/boot/firmware/resize2fs_once

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/resize2fs_once
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Create the resize2fs_once script
cat > /usr/local/sbin/resize2fs_once << 'EOF'
#!/bin/bash
# Resize root filesystem to fill SD card

set -e

# Marker file to prevent re-running
MARKER_FILE="/boot/firmware/resize2fs_once"

# Check if already resized
if [ -f "${MARKER_FILE}" ]; then
    echo "Resize already completed"
    exit 0
fi

# Get root device and partition info
ROOT_PART_DEV=$(findmnt / -o source -n)
# Use lsblk to reliably get parent device (handles both mmcblk0p2 and sda2 formats)
ROOT_DEV_NAME="/dev/$(lsblk -no pkname "${ROOT_PART_DEV}")"
ROOT_PART_NUM=$(echo "${ROOT_PART_DEV}" | grep -o '[0-9]*$')

# Verify this is an SD card or eMMC device
if [[ ! "${ROOT_DEV_NAME}" =~ (mmcblk|sd) ]]; then
    echo "Not running on SD card or eMMC, skipping resize"
    touch "${MARKER_FILE}"
    exit 0
fi

# Get total device size and current partition end
DEVICE_SIZE=$(blockdev --getsz "${ROOT_DEV_NAME}")
PART_END=$(parted "${ROOT_DEV_NAME}" -ms unit s p | grep "^${ROOT_PART_NUM}" | cut -f 3 -d: | sed 's/s$//')

# Check if partition already fills device (within 100 sectors tolerance)
if [ $((PART_END + 100)) -gt "${DEVICE_SIZE}" ]; then
    echo "Partition already maximized"
    touch "${MARKER_FILE}"
    exit 0
fi

echo "Resizing partition ${ROOT_PART_NUM} on ${ROOT_DEV_NAME}..."

# Resize partition (using pretend-input-tty to handle the "in use" warning)
echo "Yes" | parted ---pretend-input-tty "${ROOT_DEV_NAME}" resizepart "${ROOT_PART_NUM}" 100%

# Wait for partition table to be re-read
partprobe "${ROOT_DEV_NAME}"
sleep 2

echo "Resizing filesystem on ${ROOT_PART_DEV}..."

# Resize filesystem
resize2fs "${ROOT_PART_DEV}"

# Create marker to prevent re-running
touch "${MARKER_FILE}"

echo "Root filesystem resized successfully"
EOF

chmod +x /usr/local/sbin/resize2fs_once

# Enable the service
systemctl enable resize2fs_once.service
