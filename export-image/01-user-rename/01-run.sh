#!/bin/bash -e

if [[ "${DISABLE_FIRST_BOOT_USER_RENAME}" == "0" ]]; then
	on_chroot <<- EOF
		SUDO_USER="${FIRST_USER_NAME}" rename-user -f -s
	EOF
else
	rm -f "${ROOTFS_DIR}/etc/xdg/autostart/piwiz.desktop"
fi

# Disable userconfig.service to prevent keyboard configuration dialog on boot
on_chroot <<- EOF
	systemctl disable userconfig.service 2>/dev/null || true
	systemctl mask userconfig.service 2>/dev/null || true
EOF
