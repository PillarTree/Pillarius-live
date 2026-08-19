#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_BASE="/tmp/pillarius-build/pillarius-live"
OUTPUT_DIR="${PROJECT_DIR}/output"
DATE=$(date +%Y%m%d)
# CLEAN=purge removes the apt package cache too; default keeps it for faster rebuilds
CLEAN="${CLEAN:-normal}"

mkdir -p "${OUTPUT_DIR}"

# Supported architectures
ARCHS=(amd64 i386)

sync_config() {
    local version=$1
    local arch=$2
    local src="${PROJECT_DIR}/pillarius-live/${version}"
    local dst="${BUILD_BASE}/${version}-${arch}"

    mkdir -p "${dst}"
    # Sync config files, but preserve the .build cache between builds.
    # Run as root so stale root-owned build artifacts can be removed.
    sudo rsync -a --delete --exclude '.build' "${src}/" "${dst}/"
}

build_version() {
    local version=$1
    local arch=$2
    local build_path="${BUILD_BASE}/${version}-${arch}"
    local iso_name="pillarius-${version}-${DATE}-${arch}.iso"

    echo "==> Syncing ${version} config (arch=${arch})..."
    sync_config "${version}" "${arch}"

    echo "==> Building ${version} version..."
    cd "${build_path}"

    # Regenerate config from auto/config
    sudo lb config --architectures "${arch}"

    # Clean previous build (keeps apt cache unless CLEAN=purge)
    if [ "${CLEAN}" = "purge" ]; then
        sudo lb clean --purge 2>/dev/null || true
    else
        sudo lb clean 2>/dev/null || true
    fi

    # Build
    "${PROJECT_DIR}/patch-lb-debian-installer.sh"
    sudo lb build

    # Move ISO to output
    local iso_file=""
    for possible in "live-image-${arch}.hybrid.iso" "binary.hybrid.iso"; do
        if [ -f "${build_path}/${possible}" ]; then
            iso_file="${possible}"
            break
        fi
    done

    if [ -z "${iso_file}" ]; then
        echo "ERROR: ISO not found for ${version}-${arch}"
        exit 1
    fi

    mv "${build_path}/${iso_file}" "${OUTPUT_DIR}/${iso_name}"
    echo "Built: ${OUTPUT_DIR}/${iso_name}"

    # Generate SHA256
    sha256sum "${OUTPUT_DIR}/${iso_name}" > "${OUTPUT_DIR}/${iso_name}.sha256"
    echo "Checksum: $(cat "${OUTPUT_DIR}/${iso_name}.sha256")"
}

VERSION="${1:-all}"
case "${VERSION}" in
    all)  build_version "minimal" "amd64"; build_version "full" "amd64"; build_version "minimal" "i386"; build_version "full" "i386" ;;
    amd64) build_version "minimal" "amd64"; build_version "full" "amd64" ;;
    i386) build_version "minimal" "i386"; build_version "full" "i386" ;;
    minimal|full) build_version "${VERSION}" "amd64" ;;
    *) echo "usage: $0 [minimal|full|all|i386]"; exit 1 ;;
esac

echo ""
echo "Build complete! ISOs in ${OUTPUT_DIR}:"
ls -la "${OUTPUT_DIR}"/*.iso