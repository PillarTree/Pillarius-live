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
#     .../images/cdrom/, but the archive ships two complementary initrds:
#     the cdrom one has storage/CD-ROM/filesystem drivers but no NICs, the
#     netboot one has the full NIC driver set but no storage drivers. Use
#     the netboot kernel/initrd as the base and merge the cdrom initrd's
#     module set into it, so the installer can use DHCP AND see disks and
#     the CD-ROM (fixes VirtualBox hanging at "configure a network using
#     static addressing" and the CD being unmountable).
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

if grep -q 'initrd.cdrom.gz' "${SCRIPT}"; then
    echo "==> initrd merge already patched"
else
    cat > /tmp/initrd-merge.block << 'EOF'
	# Merge the complementary cdrom and netboot initrds: the cdrom image
	# ships without NIC drivers and the netboot image without storage or
	# CD-ROM drivers; the combined initrd works on any hardware.
	if [ "${DI_IMAGE_TYPE}" = "cdrom" ] && [ "${LB_ARCHITECTURES}" = "amd64" ]
	then
		Download_file initrd.cdrom.gz ${URL}/cdrom/initrd.gz
		zcat initrd.cdrom.gz > initrd.merged
		zcat "${DESTDIR}/${INITRD_DI}" >> initrd.merged
		gzip -9 -c initrd.merged > "${DESTDIR}/${INITRD_DI}"
		rm -f initrd.cdrom.gz initrd.merged
		if [ ${DOWNLOAD_GTK_INSTALLER} -eq 1 ]
		then
			Download_file initrd-gtk.cdrom.gz ${URL}/cdrom/gtk/initrd.gz
			zcat initrd-gtk.cdrom.gz > initrd-gtk.merged
			zcat "${DESTDIR}/${INITRD_GI}" >> initrd-gtk.merged
			gzip -9 -c initrd-gtk.merged > "${DESTDIR}/${INITRD_GI}"
			rm -f initrd-gtk.cdrom.gz initrd-gtk.merged
		fi
	fi
EOF
    sudo sed -i "/DI_REMOTE_BASE_GTK}\/initrd.gz/r /tmp/initrd-merge.block" "${SCRIPT}"
    rm -f /tmp/initrd-merge.block
    echo "==> patched initrd merge in ${SCRIPT}"
fi

if [ ! -f "${DATA_FILE}" ]; then
    sudo mkdir -p "${DATA_DIR}"
    sudo touch "${DATA_FILE}"
    echo "==> created ${DATA_FILE}"
else
    echo "==> ${DATA_FILE} already present"
fi