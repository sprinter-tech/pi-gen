#!/bin/bash -e

# Ensure the resize service is enabled for first boot
# This will automatically resize the root partition on first boot

# Create a systemd service that runs resize2fs_once on first boot
cat > /etc/systemd/system/resize2fs_once.service << 'EOF'
[Unit]
Description=Resize root filesystem
DefaultDependencies=no
After=local-fs-pre.target
Before=local-fs.target shutdown.target
Conflicts=shutdown.target
ConditionPathExists=!/boot/SSH

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/resize2fs_once
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=local-fs.target
EOF

# Create the resize2fs_once script
cat > /sbin/resize2fs_once << 'EOF'
#!/bin/bash
# Resize root filesystem to fill SD card

set -e

# Check if already resized
if [ -f /boot/resize2fs_once ]; then
    exit 0
fi

# Get root device and partition info
ROOT_PART_DEV=$(findmnt / -o source -n)
ROOT_DEV_NAME=$(echo "${ROOT_PART_DEV}" | sed 's/p[0-9]*$//' | sed 's/[0-9]*$//')
ROOT_PART_NUM=$(echo "${ROOT_PART_DEV}" | grep -o '[0-9]*$')

# Verify this is an SD card device (mmcblk)
if [[ ! "${ROOT_DEV_NAME}" =~ mmcblk ]]; then
    echo "Not running on SD card, skipping resize"
    exit 0
fi

# Get total device size
DEVICE_SIZE=$(blockdev --getsz "${ROOT_DEV_NAME}")
PART_END=$(parted "${ROOT_DEV_NAME}" -ms unit s p | grep "^${ROOT_PART_NUM}" | cut -f 3 -d: | sed 's/s$//')

# Check if partition already fills device
if [ $((PART_END + 100)) -gt "${DEVICE_SIZE}" ]; then
    echo "Partition already maximized"
    touch /boot/resize2fs_once
    exit 0
fi

# Resize partition
parted "${ROOT_DEV_NAME}" --script resizepart "${ROOT_PART_NUM}" 100%

# Resize filesystem
resize2fs "${ROOT_PART_DEV}"

# Create marker to prevent re-running
touch /boot/resize2fs_once

echo "Root filesystem resized successfully"
EOF

chmod +x /sbin/resize2fs_once

# Enable the service
systemctl enable resize2fs_once.service

# Also create the proper init_resize.sh that raspi-config expects
mkdir -p /usr/lib/raspi-config
cat > /usr/lib/raspi-config/init_resize.sh << 'EOF'
#!/bin/bash
# First boot resize init script

# Check if resize is needed
if [ ! -f /boot/resize2fs_once ]; then
    /sbin/resize2fs_once
fi

# Continue with normal init
exec /sbin/init "$@"
EOF

chmod +x /usr/lib/raspi-config/init_resize.sh