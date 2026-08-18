#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_BASE="/tmp/pillarius-build/pillarius-live"
OUTPUT_DIR="${PROJECT_DIR}/output"
DATE=$(date +%Y%m%d)
# CLEAN=purge removes the apt package cache too; default keeps it for faster rebuilds
CLEAN="${CLEAN:-normal}"

mkdir -p "${OUTPUT_DIR}"

sync_config() {
    local version=$1
    local src="${PROJECT_DIR}/pillarius-live/${version}"
    local dst="${BUILD_BASE}/${version}"

    mkdir -p "${dst}"
    # Sync config files, but preserve the .build cache between builds.
    # Run as root so stale root-owned build artifacts can be removed.
    sudo rsync -a --delete --exclude '.build' "${src}/" "${dst}/"
}

build_version() {
    local version=$1
    local build_path="${BUILD_BASE}/${version}"
    local iso_name="pillarius-${version}-${DATE}-amd64.iso"

    echo "==> Syncing ${version} config..."
    sync_config "${version}"

    echo "==> Building ${version} version..."
    cd "${build_path}"

    # Regenerate config from auto/config
    sudo lb config

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
    if [ -f live-image-amd64.hybrid.iso ]; then
        mv live-image-amd64.hybrid.iso "${OUTPUT_DIR}/${iso_name}"
    elif [ -f binary.hybrid.iso ]; then
        mv binary.hybrid.iso "${OUTPUT_DIR}/${iso_name}"
    else
        echo "ERROR: ISO not found for ${version}"
        exit 1
    fi
    echo "Built: ${OUTPUT_DIR}/${iso_name}"

    # Generate SHA256
    sha256sum "${OUTPUT_DIR}/${iso_name}" > "${OUTPUT_DIR}/${iso_name}.sha256"
    echo "Checksum: $(cat "${OUTPUT_DIR}/${iso_name}.sha256")"
}

VERSION="${1:-all}"
case "${VERSION}" in
    all)  build_version "minimal"; build_version "full" ;;
    minimal|full) build_version "${VERSION}" ;;
    *) echo "usage: $0 [minimal|full|all]"; exit 1 ;;
esac

echo ""
echo "Build complete! ISOs in ${OUTPUT_DIR}:"
ls -la "${OUTPUT_DIR}"/*.iso