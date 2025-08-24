#!/bin/bash -e
# stage2/06-extra-pkgs/01-run.sh

# Copy a local .deb into the rootfs and install it
install -m 644 files/sdca_2.3-59_arm64.deb "${ROOTFS_DIR}/tmp/"
on_chroot << EOF
apt-get update
dpkg -i /tmp/sdca_2.3-59_arm64.deb || apt-get -f -y install
# no need to "start" it here; systemd will do that on the Pi’s first boot
EOF

cat > /etc/watchdog.conf << EOF
watchdog-device = /dev/watchdog
watchdog-timeout = 15
EOF

