#!/usr/bin/env bash
set -euo pipefail

echo "KOMI A31 part2: 24.10 / kernel 6.6 optimized build"

config_set() {
	local key="$1"
	local value="${2:-y}"
	sed -i -E "/^(# )?CONFIG_${key}(=| is not set)/d" .config
	if [ "${value}" = "n" ]; then
		echo "# CONFIG_${key} is not set" >> .config
	else
		echo "CONFIG_${key}=${value}" >> .config
	fi
}

config_add() {
	config_set "$1" y
}

config_del() {
	config_set "$1" n
}

config_clear_matching() {
	local pattern="$1"
	sed -i -E "/^CONFIG_${pattern}(=| is not set)/d; /^# CONFIG_${pattern} is not set/d" .config
}

config_package_add() {
	config_add "PACKAGE_$1"
}

config_package_del() {
	config_del "PACKAGE_$1"
}

drop_package() {
	local name="$1"
	[ "${name}" = "golang" ] && return 0
	find package/ -follow -name "${name}" -not -path "package/custom/*" -prune -exec rm -rf {} + 2>/dev/null || true
	find feeds/ -follow -name "${name}" -not -path "feeds/base/custom/*" -prune -exec rm -rf {} + 2>/dev/null || true
}

clean_packages() {
	local path="$1"
	[ -d "${path}" ] || return 0
	find "${path}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | while read -r item; do
		drop_package "${item}"
	done
}

fix_target_platform_config() {
	echo "Fixing target platform to mediatek/filogic"
	config_add "TARGET_mediatek"
	config_del "TARGET_mediatek_mt7981"
	config_add "TARGET_mediatek_filogic"
}

keep_only_komi_a31() {
	echo "Keeping only konka_komi-a31 target device"
	config_clear_matching 'TARGET_mediatek_filogic_DEVICE_.*'
	config_clear_matching 'TARGET_PROFILE'
	config_clear_matching 'TARGET_DEVICE_mediatek_.*_DEVICE_.*'
	config_clear_matching 'TARGET_DEVICE_PACKAGES_mediatek_.*_DEVICE_.*'
	config_add "TARGET_mediatek_filogic_DEVICE_konka_komi-a31"
	config_set "TARGET_PROFILE" "\"DEVICE_konka_komi-a31\""
	config_add "TARGET_DEVICE_mediatek_filogic_DEVICE_konka_komi-a31"
	config_set "TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_konka_komi-a31" '""'
	config_del "TARGET_MULTI_PROFILE"
	config_del "TARGET_PER_DEVICE_ROOTFS"
}

apply_optimization_level() {
	local level="${OPTIMIZATION_LEVEL:-full}"
	case "${level}" in
		basic)
			ENABLE_LTO=true
			ENABLE_MOLD=true
			ENABLE_BPF=false
			KERNEL_CLANG_LTO=false
			USE_GCC14=false
			;;
		full)
			ENABLE_LTO=true
			ENABLE_MOLD=true
			ENABLE_BPF=true
			KERNEL_CLANG_LTO=true
			USE_GCC14=true
			;;
		advanced)
			ENABLE_LTO=true
			ENABLE_MOLD=true
			ENABLE_BPF=true
			KERNEL_CLANG_LTO=true
			USE_GCC14=true
			ENABLE_ADVANCED_FEATURES=true
			;;
		custom)
			ENABLE_LTO="${ENABLE_LTO:-true}"
			ENABLE_MOLD="${ENABLE_MOLD:-true}"
			ENABLE_BPF="${ENABLE_BPF:-true}"
			KERNEL_CLANG_LTO="${KERNEL_CLANG_LTO:-true}"
			USE_GCC14="${USE_GCC14:-true}"
			;;
		*)
			echo "Unknown OPTIMIZATION_LEVEL=${level}, using full"
			OPTIMIZATION_LEVEL=full
			apply_optimization_level
			return
			;;
	esac
	export ENABLE_LTO ENABLE_MOLD ENABLE_BPF KERNEL_CLANG_LTO USE_GCC14
}

apply_build_optimizations() {
	echo "Applying build optimizations"
	local ccache_dir
	if [ -n "${CCACHE_DIR:-}" ]; then
		ccache_dir="${CCACHE_DIR}"
	elif [ -d /workdir ] && [ -w /workdir ]; then
		ccache_dir="/workdir/.ccache"
	else
		ccache_dir="${PWD}/.ccache"
	fi

	[ "${ENABLE_LTO:-true}" = "true" ] && {
		config_add "USE_GC_SECTIONS"
		config_add "USE_LTO"
	}
	[ "${ENABLE_MOLD:-true}" = "true" ] && {
		config_add "USE_MOLD"
		config_add "MOLD"
	}

	config_add "CCACHE"
	config_set "CCACHE_DIR" "\"${ccache_dir}\""
	mkdir -p "${ccache_dir}"
	cat > "${ccache_dir}/ccache.conf" <<'EOF'
compiler_check = %compiler% -v
compression = true
compression_level = 5
max_size = 5G
EOF

	config_add "TOOLCHAINOPTS"
	config_add "TARGET_OPTIONS"
	config_set "TARGET_OPTIMIZATION" "\"-O3 -pipe -mcpu=cortex-a53+crc+crypto\""
	config_set "EXTRA_OPTIMIZATION" "\"-ffunction-sections -fdata-sections\""
	config_set "HOST_CFLAGS" "\"-O3 -pipe\""
	config_set "HOST_CXXFLAGS" "\"-O3 -pipe\""
	config_add "ZLIB_OPTIMIZE_SPEED"

	if [ "${KERNEL_CLANG_LTO:-true}" = "true" ]; then
		config_set "KERNEL_CC" "\"clang\""
		config_add "LTO_CLANG_THIN"
		config_del "LTO_CLANG_FULL"
	fi

	if [ "${ENABLE_BPF:-true}" = "true" ]; then
		config_add "DEVEL"
		config_add "BPF_TOOLCHAIN_HOST"
		config_add "USE_LLVM_HOST"
		config_set "BPF_TOOLCHAIN_HOST_PATH" '"/usr"'
		config_del "BPF_TOOLCHAIN_BUILD_LLVM"
		config_del "BPF_TOOLCHAIN_NONE"
		config_del "BPF_TOOLCHAIN_PREBUILT"
		config_del "USE_LLVM_BUILD"
		config_del "USE_LLVM_PREBUILT"
	fi

	if [ "${USE_GCC14:-true}" = "true" ]; then
		config_add "GCC_VERSION_14"
	fi
}

configure_daed_kernel_options() {
	echo "Configuring daed eBPF kernel options"
	config_add "KERNEL_BPF"
	config_add "KERNEL_BPF_SYSCALL"
	config_add "KERNEL_BPF_JIT"
	config_add "KERNEL_CGROUPS"
	config_add "KERNEL_KPROBES"
	config_add "KERNEL_KPROBE_EVENTS"
	config_add "KERNEL_NET_INGRESS"
	config_add "KERNEL_NET_EGRESS"
	config_add "KERNEL_NET_SCH_INGRESS"
	config_add "KERNEL_NET_CLS_BPF"
	config_add "KERNEL_NET_CLS_ACT"
	config_add "KERNEL_BPF_STREAM_PARSER"
	config_add "KERNEL_BPF_EVENTS"
	config_add "KERNEL_DEBUG_INFO"
	config_del "KERNEL_DEBUG_INFO_REDUCED"
	config_add "KERNEL_DEBUG_INFO_BTF"
	config_add "KERNEL_MODULE_ALLOW_BTF_MISMATCH"
	config_add "KERNEL_XDP_SOCKETS"
	config_package_add "kmod-sched-core"
	config_package_add "kmod-sched-bpf"
	config_package_add "kmod-xdp-sockets-diag"
	config_package_add "libbpf"
}

setup_third_party_packages() {
	echo "Setting up third-party packages"
	mkdir -p package/custom
	if [ ! -d package/custom/OpenWrt-Packages ]; then
		git clone --depth 1 -b openwrt-24.10 https://github.com/217heidai/OpenWrt-Packages.git package/custom/OpenWrt-Packages
	fi
	clean_packages package/custom/OpenWrt-Packages
	rm -rf package/custom/OpenWrt-Packages/luci-theme-argon 2>/dev/null || true
	rm -rf package/custom/OpenWrt-Packages/shadowsocks-rust 2>/dev/null || true
	rm -rf package/custom/OpenWrt-Packages/simple-obfs 2>/dev/null || true
	rm -rf package/custom/OpenWrt-Packages/rooter 2>/dev/null || true

	if [ -d package/custom/OpenWrt-Packages/.git ]; then
		git -C package/custom/OpenWrt-Packages checkout -- tcping luci-app-passwall/Makefile luci-app-passwall2/Makefile 2>/dev/null || true
	fi

	drop_package "luci-theme-argon"
	if [ ! -d package/custom/luci-theme-argon ]; then
		echo "Cloning luci-theme-argon from jerrykuku/luci-theme-argon"
		git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git package/custom/luci-theme-argon
	fi

	if [ -d package/custom/OpenWrt-Packages/golang ]; then
		echo "Replacing feeds golang with custom OpenWrt-Packages/golang"
		rm -rf feeds/packages/lang/golang
		cp -a package/custom/OpenWrt-Packages/golang feeds/packages/lang/golang
	elif [ ! -d feeds/packages/lang/golang ]; then
		echo "Custom golang not found, cloning sbwml/packages_lang_golang 25.x"
		git clone --depth 1 -b 25.x https://github.com/sbwml/packages_lang_golang.git feeds/packages/lang/golang
	fi

	if [ ! -d package/daed ]; then
		git clone --depth 1 https://github.com/QiuSimons/luci-app-daed.git package/daed
	fi
}

configure_packages() {
	echo "Configuring package selection"
	config_package_del "luci-app-mentohust"
	config_package_del "mentohust"

	config_package_add "curl"
	config_package_add "socat"
	config_package_add "kmod-tcp-bbr"
	config_package_add "kmod-nft-bridge"
	config_package_add "luci-app-ttyd"
	config_package_add "luci-app-autoreboot"
	config_package_add "luci-app-autotimeset"
	config_package_add "luci-app-arpbind"
	config_package_add "luci-app-wol"
	config_package_add "luci-app-upnp"
	config_package_add "miniupnpd"
	config_package_add "qrencode"
	config_package_add "fdisk"
	config_package_add "iperf"
	config_package_add "micro"
	config_package_add "byobu"
	config_package_add "tmux"
	config_package_add "fish"
	config_package_add "luci-theme-argon"
	config_package_add "luci-app-daed"
	config_package_add "luci-app-passwall2"
	config_package_add "luci-app-passwall2_INCLUDE_Hysteria"
	config_package_add "luci-app-passwall2_Nftables_Transparent_Proxy"
	config_package_add "tcping"
	config_package_add "kmod-nft-socket"
	config_package_add "kmod-nft-tproxy"

	config_package_del "usbutils"
	config_package_del "kmod-usb-net"
	config_package_del "kmod-usb-net-rndis"
	config_package_del "kmod-usb-net-cdc-ether"
	config_package_del "kmod-usb-net-ipheth"
	config_package_del "kmod-usb-core"
	config_package_del "kmod-usb-ehci"
	config_package_del "kmod-usb-storage"
	config_package_del "kmod-usb-storage-extras"
	config_package_del "kmod-usb-storage-uas"
	config_package_del "kmod-usb-ohci"
	config_package_del "kmod-usb-uhci"
	config_package_del "kmod-usb-xhci-hcd"
	config_package_del "kmod-usb-xhci-mtk"
	config_package_del "kmod-usb2"
	config_package_del "kmod-usb3"
	config_package_del "usb-modeswitch"
	config_package_del "sendat"
	config_package_del "luci-app-usb3disable"
	config_del "DEFAULT_kmod-usb-net-rndis"
	config_del "DEFAULT_kmod-usb2"
	config_del "DEFAULT_kmod-usb3"
	config_del "DEFAULT_usbutils"
	config_package_del "luci-app-passwall2_INCLUDE_ShadowsocksR_Libev_Client"
	config_package_del "luci-app-passwall2_INCLUDE_Shadowsocks_Libev_Client"
	config_package_del "luci-app-passwall2_INCLUDE_Shadowsocks_Rust_Client"
	config_package_del "luci-app-passwall2_INCLUDE_Haproxy"
	config_package_del "luci-app-passwall2_INCLUDE_Simple_Obfs"
	config_package_del "luci-app-passwall2_INCLUDE_V2ray_Plugin"
	config_package_del "luci-app-passwall2_INCLUDE_SingBox"
	config_package_del "sing-box"
	config_package_del "shadowsocks-rust-sslocal"
	config_package_del "shadowsocks-rust-ssserver"
	config_package_del "simple-obfs"
	config_package_del "v2ray-plugin"
	config_package_del "v2ray-geoip"
	config_package_del "v2ray-geosite"
	config_package_del "tcping-simple"

	configure_daed_kernel_options
}

setup_default_lan_ip() {
	local custom_ip="${CUSTOM_LAN_IP:-192.168.6.1}"
	[ "${custom_ip}" = "192.168.6.1" ] && return 0
	echo "Setting default LAN IP to ${custom_ip}"
	find . -name config_generate -type f -exec sed -i "s/192\\.168\\.[16]\\.1/${custom_ip}/g" {} +
}

setup_default_shell() {
	if [ -f package/base-files/files/etc/passwd ]; then
		sed -i 's|root:x:0:0:root:/root:/bin/ash|root:x:0:0:root:/root:/usr/bin/fish|g' package/base-files/files/etc/passwd
	fi
}

if [ -f feeds/luci/collections/luci/Makefile ]; then
	sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
fi

fix_target_platform_config
keep_only_komi_a31
apply_optimization_level
setup_third_party_packages
configure_packages
apply_build_optimizations
setup_default_shell
setup_default_lan_ip

echo "Enabled target devices:"
grep -E "CONFIG_TARGET_mediatek_filogic_DEVICE_.*=y|CONFIG_TARGET_DEVICE.*=y|CONFIG_TARGET_PROFILE" .config || true
echo "Selected packages: $(grep -c '^CONFIG_PACKAGE_.*=y' .config || true)"
