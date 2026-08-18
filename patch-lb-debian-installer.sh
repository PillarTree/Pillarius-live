#!/bin/bash
# Patch the installed live-build (3.0~a57) so that --debian-installer live
# works with trixie:
#  1. lb_binary_debian-installer hardcodes the bootloader package names
#     "lilo grub grub-pc" and "linux-image-2.6-amd64", none of which exist in
#     trixie. Replace them with the bootloaders the Debian Installer actually
#     needs from the ISO pool (grub-pc for BIOS, grub-efi-amd64 for UEFI).
#     grub-pc and grub-efi-amd64 conflict, so grub-efi-amd64 is fetched in a
#     separate apt invocation.
#  2. For cdrom images it downloads the installer kernel/initrd from
#     .../images/amd64/cdrom/, but that initrd ships without any NIC drivers
#     (only cnic), so the installer cannot use DHCP (VirtualBox etc. hang at
#     "configure a network using static addressing"). Use the netboot initrd
#     instead, which carries the full driver set (e1000, virtio_net, r8169...).
#  3. Supplies the debian-cd data file that lb_binary_disk requires for
#     releases newer than sid (Ubuntu ships data only up to sid).
# Idempotent; safe to run on every build.
set -euo pipefail

SCRIPT=/usr/lib/live/build/lb_binary_debian-installer
DATA_DIR=/usr/share/live/build/data/debian-cd/trixie
DATA_FILE=${DATA_DIR}/amd64_netinst_udeb_include

if [ ! -f "${SCRIPT}" ]; then
    echo "error: ${SCRIPT} not found (is live-build installed?)" >&2
    exit 1
fi

if grep -q 'install grub-efi-amd64' "${SCRIPT}"; then
    echo "==> live-build already patched"
else
    sudo sed -i \
        -e 's/DI_REQ_PACKAGES="lilo grub grub-pc"/DI_REQ_PACKAGES="grub-pc"/' \
        -e 's/DI_REQ_PACKAGES="grub-pc grub-efi-amd64"/DI_REQ_PACKAGES="grub-pc"/' \
        -e 's/DI_PACKAGES="${DI_REQ_PACKAGES} linux-image-2.6-amd64"/DI_PACKAGES="${DI_REQ_PACKAGES}"/' \
        -e '/Chroot chroot ${_LB_APT_COMMAND} install ${DI_PACKAGES} ${DI_FIRMWARE_PACKAGES} ${DI_REQ_PACKAGES}/a\Chroot chroot ${_LB_APT_COMMAND} install grub-efi-amd64' \
        "${SCRIPT}"
    echo "==> patched ${SCRIPT}"
fi

if grep -q 'DI_IMAGE_TYPE}" = "cdrom" ] && \[ "${LB_ARCHITECTURES}" = "amd64" \]' "${SCRIPT}"; then
    echo "==> initrd source already patched"
else
    sudo perl -0777 -pi -e \
        's/^Check_multiarchitectures\n/if [ "\${DI_IMAGE_TYPE}" = "cdrom" ] \&\& [ "\${LB_ARCHITECTURES}" = "amd64" ]\nthen\n\tDI_REMOTE_BASE="netboot\/debian-installer\/\${LB_ARCHITECTURES}"\n\tDI_REMOTE_BASE_GTK="netboot\/gtk\/debian-installer\/\${LB_ARCHITECTURES}"\n\tDI_REMOTE_KERNEL="linux"\nfi\n\nCheck_multiarchitectures\n/m' \
        "${SCRIPT}"
    echo "==> patched initrd source in ${SCRIPT}"
fi

if [ ! -f "${DATA_FILE}" ]; then
    sudo mkdir -p "${DATA_DIR}"
    sudo touch "${DATA_FILE}"
    echo "==> created ${DATA_FILE}"
else
    echo "==> ${DATA_FILE} already present"
fi