#!/bin/bash -e

# Stage2 is Lite - set default target to multi-user (text console)
on_chroot << EOF
systemctl set-default multi-user.target
EOF
