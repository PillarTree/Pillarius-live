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
	# Merge at the filesystem level (extract both cpio streams into one
	# tree, re-pack as a single archive). A naive concatenation of the
	# gzip streams leaves a TRAILER!!! member in the middle, and cpio
	# stops at the first trailer -- so the later initrd repack for
	# config/includes.binary_debian-installer would silently drop the
	# netboot stream. Read the sources from the download cache (files in
	# DESTDIR are hard links to the cache, never trust them) and install
	# the result with a plain copy so the cache inode is not clobbered.
	if [ "${DI_IMAGE_TYPE}" = "cdrom" ] && [ "${LB_ARCHITECTURES}" = "amd64" ]
	then
		Download_file /tmp/initrd.cdrom.gz ${URL}/cdrom/initrd.gz
		Download_file /tmp/initrd-gtk.cdrom.gz ${URL}/cdrom/gtk/initrd.gz
		_LB_NETBOOT_INITRD="${_LB_CACHE_DIR}/$(echo "${URL}/${DI_REMOTE_BASE}/initrd.gz" | sed 's|/|_|g')"
		_LB_NETBOOT_INITRD_GI="${_LB_CACHE_DIR}/$(echo "${URL}/${DI_REMOTE_BASE_GTK}/initrd.gz" | sed 's|/|_|g')"
		Echo_message "Merging installer initrds (cdrom + netboot) at filesystem level..."
		rm -rf /tmp/initrd-merge
		mkdir -p /tmp/initrd-merge
		zcat /tmp/initrd.cdrom.gz | (cd /tmp/initrd-merge && cpio -idm --no-absolute-filenames)
		zcat "${_LB_NETBOOT_INITRD}" | (cd /tmp/initrd-merge && cpio -idmu --no-absolute-filenames)
		(cd /tmp/initrd-merge && find -print0 | cpio -H newc -o0) | gzip -9 > /tmp/initrd.merged.gz
		install -m 644 /tmp/initrd.merged.gz "${DESTDIR}/${INITRD_DI}"
		Echo_message "Merged initrd.gz: $(stat -c%s /tmp/initrd.merged.gz) bytes"
		rm -rf /tmp/initrd-merge /tmp/initrd.merged.gz
		if [ ${DOWNLOAD_GTK_INSTALLER} -eq 1 ]
		then
			rm -rf /tmp/initrd-merge-gtk
			mkdir -p /tmp/initrd-merge-gtk
			zcat /tmp/initrd-gtk.cdrom.gz | (cd /tmp/initrd-merge-gtk && cpio -idm --no-absolute-filenames)
			zcat "${_LB_NETBOOT_INITRD_GI}" | (cd /tmp/initrd-merge-gtk && cpio -idmu --no-absolute-filenames)
			(cd /tmp/initrd-merge-gtk && find -print0 | cpio -H newc -o0) | gzip -9 > /tmp/initrd-gtk.merged.gz
			install -m 644 /tmp/initrd-gtk.merged.gz "${DESTDIR}/${INITRD_GI}"
			Echo_message "Merged gtk/initrd.gz: $(stat -c%s /tmp/initrd-gtk.merged.gz) bytes"
			rm -rf /tmp/initrd-merge-gtk /tmp/initrd-gtk.merged.gz
		fi
		rm -f /tmp/initrd.cdrom.gz /tmp/initrd-gtk.cdrom.gz
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