#!/bin/bash -e
# stage2/06-extra-pkgs/01-run.sh

# Find the latest sdca package by version
SDCA_DEB=$(ls files/sdca_*_arm64.deb 2>/dev/null | sort -V | tail -1)
if [ -z "$SDCA_DEB" ]; then
    echo "Error: No sdca_*_arm64.deb package found in files/ directory" >&2
    exit 1
fi
SDCA_DEB_BASENAME=$(basename "$SDCA_DEB")

# Copy a local .deb into the rootfs and install it
install -m 644 "$SDCA_DEB" "${ROOTFS_DIR}/tmp/"
on_chroot << EOF
apt-get update
dpkg -i /tmp/$SDCA_DEB_BASENAME || apt-get -f -y install
# no need to "start" it here; systemd will do that on the Pi's first boot
EOF

cat > "${ROOTFS_DIR}/etc/watchdog.conf" << EOF
watchdog-device = /dev/watchdog
watchdog-timeout = 15
EOF

