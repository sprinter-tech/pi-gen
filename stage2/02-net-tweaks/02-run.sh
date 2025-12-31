#!/bin/bash -e

# Stage2 is Lite - set default target to multi-user (text console)
on_chroot << EOF
systemctl set-default multi-user.target
# Enable getty on the primary console (tty1)
systemctl enable getty@tty1.service
# Enable serial console getty if available
systemctl enable serial-getty@ttyAMA0.service 2>/dev/null || true
systemctl enable serial-getty@ttyS0.service 2>/dev/null || true
EOF
