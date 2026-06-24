#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENWRT_DIR="${1:-$(pwd)}"
PATCH_DIR="${ROOT_DIR}/patches/openwrt"

if [ ! -d "${OPENWRT_DIR}" ]; then
	echo "OpenWrt directory not found: ${OPENWRT_DIR}" >&2
	exit 1
fi

if [ ! -d "${PATCH_DIR}" ]; then
	echo "Patch directory not found: ${PATCH_DIR}" >&2
	exit 1
fi

cd "${OPENWRT_DIR}"

for patch_file in "${PATCH_DIR}"/*.patch; do
	[ -e "${patch_file}" ] || continue
	echo "Applying patch: ${patch_file##*/}"
	if git apply --check "${patch_file}" >/dev/null 2>&1; then
		git apply "${patch_file}"
	elif git apply --reverse --check "${patch_file}" >/dev/null 2>&1; then
		echo "Patch already applied: ${patch_file##*/}"
	else
		echo "Patch cannot be applied cleanly: ${patch_file}" >&2
		exit 1
	fi
done
