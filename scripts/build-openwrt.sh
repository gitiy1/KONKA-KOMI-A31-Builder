#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${WORKDIR:-${ROOT_DIR}/LocalWorkdir}"
OPENWRT_DIR="${OPENWRT_DIR:-${WORKDIR}/openwrt}"
LOCAL_SOURCE="${OPENWRT_LOCAL_SOURCE:-${ROOT_DIR}/references/immortalwrt-mt798x-6.6}"
REPO_URL="${REPO_URL:-https://github.com/padavanonly/immortalwrt-mt798x-6.6}"
REPO_BRANCH="${REPO_BRANCH:-openwrt-24.10-6.6}"
JOBS="${JOBS:-$(($(nproc) + 1))}"
CCACHE_DIR="${CCACHE_DIR:-${WORKDIR}/.ccache}"
export CCACHE_DIR

mkdir -p "${WORKDIR}" "${CCACHE_DIR}"

prepare_source() {
	if [ "${CLEAN_SOURCE:-0}" = "1" ]; then
		rm -rf "${OPENWRT_DIR}"
	fi

	if [ -d "${OPENWRT_DIR}/scripts" ]; then
		echo "Using existing OpenWrt tree: ${OPENWRT_DIR}"
		return
	fi

	mkdir -p "$(dirname "${OPENWRT_DIR}")"
	if [ -d "${LOCAL_SOURCE}/scripts" ]; then
		echo "Copying local OpenWrt source from ${LOCAL_SOURCE}"
		cp -a "${LOCAL_SOURCE}" "${OPENWRT_DIR}"
	else
		echo "Cloning OpenWrt source from ${REPO_URL} (${REPO_BRANCH})"
		git clone -b "${REPO_BRANCH}" --single-branch --depth 1 "${REPO_URL}" "${OPENWRT_DIR}"
	fi
}

prepare_source

download_sources() {
	local jobs="$1"
	for attempt in 1 2; do
		if make download -j"${jobs}"; then
			return 0
		fi
		echo "Parallel download failed (attempt ${attempt}); removing tiny partial files and retrying."
		find dl -size -1024c -print -delete 2>/dev/null || true
	done

	echo "Retrying downloads single-threaded with verbose output."
	make download -j1 V=s
}

cp -f "${ROOT_DIR}/feeds.conf.default" "${OPENWRT_DIR}/feeds.conf.default"
"${ROOT_DIR}/scripts/apply-openwrt-patches.sh" "${OPENWRT_DIR}"

cd "${OPENWRT_DIR}"
"${ROOT_DIR}/diy-part1.sh"
./scripts/feeds update -a
./scripts/feeds install -a

cp -f defconfig/mt7981-ax3000.config .config
"${ROOT_DIR}/diy-part2-komi-a31.sh"

make defconfig
download_sources "${JOBS}"
find dl -size -1024c -print -delete

if [ "${DOWNLOAD_ONLY:-0}" = "1" ]; then
	echo "DOWNLOAD_ONLY=1, stopping before compile"
	exit 0
fi

make -j"${JOBS}" V="${V:-s}" || make -j1 V="${V:-s}"

echo "Build output:"
find bin/targets -type f \( -name '*komi*a31*' -o -name '*konka*' -o -name '*.itb' -o -name '*.manifest' -o -name 'sha256sums' \) -print
