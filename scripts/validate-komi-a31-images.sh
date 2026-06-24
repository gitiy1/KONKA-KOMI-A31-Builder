#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-LocalWorkdir/openwrt/bin/targets/mediatek/filogic}"
PREFIX="immortalwrt-mediatek-filogic-konka_komi-a31"
IMAGE_SIZE_KIB=114688

fail() {
	echo "KOMI A31 image validation failed: $*" >&2
	exit 1
}

need_file() {
	[ -s "$1" ] || fail "missing or empty file: $1"
}

hex_at() {
	local file="$1"
	local skip="$2"
	local count="$3"
	dd if="$file" bs=1 skip="$skip" count="$count" 2>/dev/null | od -An -tx1 -v | tr -d ' \n'
}

sysupgrade="${OUT_DIR}/${PREFIX}-squashfs-sysupgrade.bin"
factory="${OUT_DIR}/${PREFIX}-squashfs-factory.bin"
itb="${OUT_DIR}/${PREFIX}-squashfs-sysupgrade.itb"

need_file "$sysupgrade"
need_file "$factory"
[ ! -e "$itb" ] || fail "unexpected ITB output still exists: $itb"

[ "$(hex_at "$sysupgrade" 257 5)" = "7573746172" ] || \
	fail "sysupgrade.bin is not a sysupgrade tar archive"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

tar -xf "$sysupgrade" -C "$tmpdir"
payload_dir="${tmpdir}/sysupgrade-konka_komi-a31"
need_file "${payload_dir}/CONTROL"
need_file "${payload_dir}/kernel"
need_file "${payload_dir}/root"

grep -qx 'BOARD=konka_komi-a31' "${payload_dir}/CONTROL" || \
	fail "CONTROL board id is not konka_komi-a31"

[ "$(hex_at "${payload_dir}/kernel" 0 4)" = "d00dfeed" ] || \
	fail "sysupgrade kernel payload is not a FIT image"

[ "$(hex_at "${payload_dir}/root" 0 4)" = "68737173" ] || \
	fail "sysupgrade root payload is not squashfs"

[ "$(hex_at "$factory" 0 4)" = "55424923" ] || \
	fail "factory.bin is not a UBI image"

factory_size="$(stat -c '%s' "$factory")"
max_size="$((IMAGE_SIZE_KIB * 1024))"
[ "$factory_size" -le "$max_size" ] || \
	fail "factory.bin is too large: ${factory_size} > ${max_size}"

echo "KOMI A31 image validation passed:"
echo "  sysupgrade: $sysupgrade"
echo "  factory:    $factory"
