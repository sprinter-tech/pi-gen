#!/bin/bash -e

set -e

# --- Seed keyrings into the chroot BEFORE any apt-get update ---
mkdir -p "${ROOTFS_DIR}/usr/share/keyrings" \
         "${ROOTFS_DIR}/etc/apt/sources.list.d" \
         "${ROOTFS_DIR}/etc/apt/trusted.gpg.d"

# 1) Debian archive keyring: copy from the outer builder (trixie) into the chroot
if [ -f /usr/share/keyrings/debian-archive-keyring.gpg ]; then
  install -m 0644 /usr/share/keyrings/debian-archive-keyring.gpg \
                  "${ROOTFS_DIR}/usr/share/keyrings/debian-archive-keyring.gpg"
fi

## 2) Raspberry Pi archive key: DEARMOR to .gpg inside the chroot
##    (files/raspberrypi-archive-keyring.pgp is armored; apt wants a .gpg keyring)
#install -m 0644 files/raspberrypi-archive-keyring.pgp \
#                "${ROOTFS_DIR}/usr/share/keyrings/raspberrypi-archive-keyring.pgp"
#on_chroot <<'EOF'
#set -e
#if [ -f /usr/bin/gpg ]; then
#  gpg --dearmor \
#    </usr/share/keyrings/raspberrypi-archive-keyring.pgp \
#    >/usr/share/keyrings/raspberrypi-archive-keyring.gpg
#  rm -f /usr/share/keyrings/raspberrypi-archive-keyring.pgp
#fi
#EOF

# 2) Raspberry Pi archive key: dearmor to .gpg in the OUTER container, then drop into chroot
install -m 0644 files/raspberrypi-archive-keyring.pgp \
                "${STAGE_WORK_DIR}/raspberrypi-archive-keyring.pgp"

# dearmor using builder's gpg (available in the pi-gen Docker image)
gpg --dearmor \
  < "${STAGE_WORK_DIR}/raspberrypi-archive-keyring.pgp" \
  > "${ROOTFS_DIR}/usr/share/keyrings/raspberrypi-archive-keyring.gpg"

rm -f "${STAGE_WORK_DIR}/raspberrypi-archive-keyring.pgp"
chmod 0644 "${ROOTFS_DIR}/usr/share/keyrings/raspberrypi-archive-keyring.gpg"


# Ensure world-readable for _apt
chmod 0644 "${ROOTFS_DIR}/usr/share/keyrings/"*.gpg 2>/dev/null || true

# --- Deb822 sources pointing explicitly at those keyrings ---
# wipe classic sources.list (keep empty)
: > "${ROOTFS_DIR}/etc/apt/sources.list"

# Debian (bookworm) – use Signed-By path we just seeded
cat >"${ROOTFS_DIR}/etc/apt/sources.list.d/debian.sources" <<'EOS'
Types: deb
URIs: http://deb.debian.org/debian
Suites: RELEASE
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian-security
Suites: RELEASE-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian
Suites: RELEASE-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOS
sed -i "s/RELEASE/${RELEASE}/g" "${ROOTFS_DIR}/etc/apt/sources.list.d/debian.sources"

# Raspberry Pi repo – use the DEARMORED .gpg
cat >"${ROOTFS_DIR}/etc/apt/sources.list.d/raspi.sources" <<'EOS'
Types: deb
URIs: http://archive.raspberrypi.com/debian
Suites: RELEASE
Components: main
Signed-By: /usr/share/keyrings/raspberrypi-archive-keyring.gpg
EOS
sed -i "s/RELEASE/${RELEASE}/g" "${ROOTFS_DIR}/etc/apt/sources.list.d/raspi.sources"

# If you use APT_PROXY or TEMP_REPO, insert them here as you had before.

# --- Clean lists and do a single update/upgrade with the correct keys in place ---
rm -rf "${ROOTFS_DIR}/var/lib/apt/lists/"*
on_chroot <<'EOF'
  set -e
  set -x
  grep -R . -n /etc/apt/sources.list /etc/apt/sources.list.d
  ls -l /usr/share/keyrings/*.gpg /etc/apt/trusted.gpg.d || true
  apt-get update
  apt-get -o Acquire::Retries=3 dist-upgrade -y
EOF

