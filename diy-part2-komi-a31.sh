#!/usr/bin/env bash
#
# Thanks for https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2-komi-a31.sh
# Description: ImmortalWrt DIY script part 2 for KONKA KOMI A31
# Enhanced with build optimizations
#

set -euo pipefail

echo "Enhanced DIY-Part2 for KOMI A31 24.10 / kernel 6.6"

# ============================================
# Utility Functions
# ============================================

function config_key() {
    local key="$1"
    key="${key#CONFIG_}"
    printf '%s' "$key"
}

function config_set() {
    local key
    key="$(config_key "$1")"
    local value="${2:-y}"

    sed -i -E "/^(# )?CONFIG_${key}(=| is not set)/d" .config

    if [ "$value" = "n" ]; then
        echo "# CONFIG_${key} is not set" >> .config
    else
        echo "CONFIG_${key}=${value}" >> .config
    fi
}

function config_del() {
    config_set "$1" n
}

function config_add() {
    config_set "$1" y
}

function config_clear_matching() {
    local pattern="$1"
    sed -i -E "/^CONFIG_${pattern}(=| is not set)/d; /^# CONFIG_${pattern} is not set/d" .config
}

function config_package_del() {
    config_del "PACKAGE_$1"
}

function config_package_add() {
    config_add "PACKAGE_$1"
}

function drop_package() {
    local name="$1"

    if [ "$name" != "golang" ]; then
        find package/ -follow -name "$name" -not -path "package/custom/*" -prune -exec rm -rf {} + 2>/dev/null || true
        find feeds/ -follow -name "$name" -not -path "feeds/base/custom/*" -prune -exec rm -rf {} + 2>/dev/null || true
    fi
}

function clean_packages() {
    local path="$1"

    [ -d "$path" ] || return 0

    find "$path" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | while read -r item; do
        drop_package "$item"
    done
}

function config_device_list() {
    { grep -E 'CONFIG_TARGET_DEVICE_|CONFIG_TARGET_DEVICE_PACKAGES_' .config || true; } | while read -r line; do
        if [[ "$line" =~ CONFIG_TARGET_DEVICE_([^=]+)=y ]]; then
            local chipset_device="${BASH_REMATCH[1]}"
            local chipset="${chipset_device%_DEVICE_*}"
            local device="${chipset_device#*_DEVICE_}"
            echo "Chipset: $chipset, Model: $device"
        fi
    done | sort -u
}

# ============================================
# Configuration Correction Functions
# ============================================

function fix_target_platform_config() {
    echo "Checking and fixing target platform configuration..."

    config_add "TARGET_mediatek"
    config_del "TARGET_mediatek_mt7981"
    config_add "TARGET_mediatek_filogic"

    echo "Target platform configuration completed"
}

function keep_only_komi_a31() {
    echo "Keeping only KONKA KOMI A31 target device..."

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

    echo "Configured for KONKA KOMI A31 only"
    echo "Device list after device pruning:"
    config_device_list
}

# ============================================
# Optimization Functions
# ============================================

function apply_optimizations_by_level() {
    local optimization_level="${OPTIMIZATION_LEVEL:-full}"

    echo "Applying optimizations for level: $optimization_level"

    case "$optimization_level" in
        "basic")
            echo "Basic optimizations: LTO + MOLD"
            export ENABLE_LTO="true"
            export ENABLE_MOLD="true"
            export ENABLE_BPF="false"
            export KERNEL_CLANG_LTO="false"
            export USE_GCC14="false"
            export ENABLE_ADVANCED_OPTIMIZATIONS="false"
            ;;
        "full")
            echo "Full optimizations: LTO + MOLD + BPF + CLANG LTO + GCC14"
            export ENABLE_LTO="true"
            export ENABLE_MOLD="true"
            export ENABLE_BPF="true"
            export KERNEL_CLANG_LTO="true"
            export USE_GCC14="true"
            export ENABLE_ADVANCED_OPTIMIZATIONS="true"
            ;;
        "advanced")
            echo "Advanced optimizations: all supported features enabled"
            export ENABLE_LTO="true"
            export ENABLE_MOLD="true"
            export ENABLE_BPF="true"
            export KERNEL_CLANG_LTO="true"
            export USE_GCC14="true"
            export ENABLE_ADVANCED_OPTIMIZATIONS="true"
            ;;
        "custom")
            echo "Custom optimizations: using individual environment settings"
            export ENABLE_LTO="${ENABLE_LTO:-true}"
            export ENABLE_MOLD="${ENABLE_MOLD:-true}"
            export ENABLE_BPF="${ENABLE_BPF:-true}"
            export KERNEL_CLANG_LTO="${KERNEL_CLANG_LTO:-true}"
            export USE_GCC14="${USE_GCC14:-true}"
            export ENABLE_ADVANCED_OPTIMIZATIONS="${ENABLE_ADVANCED_OPTIMIZATIONS:-true}"
            ;;
        *)
            echo "Unknown optimization level: $optimization_level, using full"
            export OPTIMIZATION_LEVEL="full"
            apply_optimizations_by_level
            return
            ;;
    esac

    echo "Optimization level configuration completed"
}

function apply_build_optimizations() {
    echo "Applying build optimizations..."

    if [ "${ENABLE_LTO:-true}" = "true" ]; then
        echo "Enabling Link Time Optimization (LTO)"
        config_add "USE_GC_SECTIONS"
        config_add "USE_LTO"
    fi

    if [ "${ENABLE_MOLD:-true}" = "true" ]; then
        echo "Enabling MOLD linker"
        config_add "USE_MOLD"
        config_add "MOLD"
    fi

    echo "Enabling ccache"
    local ccache_dir
    if [ -n "${CCACHE_DIR:-}" ]; then
        ccache_dir="$CCACHE_DIR"
    elif [ -d /workdir ] && [ -w /workdir ]; then
        ccache_dir="/workdir/.ccache"
    else
        ccache_dir="$PWD/.ccache"
    fi

    config_add "CCACHE"
    config_set "CCACHE_DIR" "\"${ccache_dir}\""
    mkdir -p "$ccache_dir"
    cat > "${ccache_dir}/ccache.conf" <<'EOF'
compiler_check = %compiler% -v
compression = true
compression_level = 5
max_size = 5G
EOF

    echo "Build optimizations applied"
}

function apply_mt7981_optimizations() {
    echo "Applying MT7981 specific optimizations..."

    config_add "TARGET_mediatek_filogic_DEVICE_konka_komi-a31"

    if [ "${ENABLE_ADVANCED_OPTIMIZATIONS:-true}" = "true" ]; then
        echo "Enabling advanced Cortex-A53 optimizations (CRC+Crypto)"
        config_set "TARGET_OPTIMIZATION" "\"-O3 -pipe -mcpu=cortex-a53+crc+crypto\""
        config_set "EXTRA_OPTIMIZATION" "\"-ffunction-sections -fdata-sections\""
        config_set "KERNEL_CFLAGS" "\"-march=armv8-a+crc+crypto -mcpu=cortex-a53+crc+crypto -mtune=cortex-a53\""
        config_add "ZLIB_OPTIMIZE_SPEED"
    else
        echo "Using basic Cortex-A53 optimizations"
        config_set "TARGET_OPTIMIZATION" "\"-O3 -pipe -mcpu=cortex-a53\""
        config_set "EXTRA_OPTIMIZATION" "\"-ffunction-sections -fdata-sections\""
    fi

    echo "MT7981 optimizations applied"
}

function apply_compiler_optimizations() {
    echo "Applying compiler optimizations..."

    config_add "TOOLCHAINOPTS"
    config_add "TARGET_OPTIONS"
    config_set "HOST_CFLAGS" "\"-O3 -pipe\""
    config_set "HOST_CXXFLAGS" "\"-O3 -pipe\""

    export HOST_CFLAGS="-O3 -pipe"
    export HOST_CXXFLAGS="-O3 -pipe"
    export CFLAGS="-O3 -pipe"
    export CXXFLAGS="-O3 -pipe"
    export LDFLAGS="-Wl,-O1,--as-needed"

    if [ "${KERNEL_CLANG_LTO:-true}" = "true" ]; then
        echo "Enabling Kernel CLANG LTO"
        config_set "KERNEL_CC" "\"clang\""
        config_add "LTO_CLANG_THIN"
        config_del "LTO_CLANG_FULL"
    fi

    if [ "${ENABLE_BPF:-true}" = "true" ]; then
        echo "Enabling host BPF toolchain"
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
        echo "Using GCC 14 for userspace compilation"
        config_add "GCC_VERSION_14"
    fi

    echo "Compiler optimizations applied"
}

function setup_custom_lan_ip() {
    local custom_ip="${CUSTOM_LAN_IP:-192.168.6.1}"

    echo "Setting up custom LAN IP: $custom_ip"

    if [ "$custom_ip" != "192.168.6.1" ]; then
        find . -name "config_generate" -type f | while read -r config_file; do
            echo "Updating LAN IP in: $config_file"
            sed -i "s/192\\.168\\.[16]\\.1/${custom_ip}/g" "$config_file"
        done
    else
        echo "Keeping KOMI default LAN IP ($custom_ip)"
    fi

    echo "LAN IP setup completed"
}

# ============================================
# Specialized Configuration Functions
# ============================================

function configure_daed_kernel_options() {
    echo "Configuring kernel options for Daed eBPF support..."

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

    echo "Daed kernel configuration completed"
}

function setup_default_shell() {
    echo "Setting default shell to fish..."

    if [ -f package/base-files/files/etc/passwd ]; then
        sed -i 's|root:x:0:0:root:/root:/bin/ash|root:x:0:0:root:/root:/usr/bin/fish|g' package/base-files/files/etc/passwd
    fi
}

# ============================================
# Custom Package Management Functions
# ============================================

function setup_third_party_packages() {
    echo "Setting up third-party packages..."

    mkdir -p package/custom

    if [ ! -d "package/custom/OpenWrt-Packages" ]; then
        echo "Cloning third-party packages..."
        git clone --depth 1 -b openwrt-24.10 https://github.com/217heidai/OpenWrt-Packages.git package/custom/OpenWrt-Packages
    fi

    rm -rf package/custom/OpenWrt-Packages/luci-theme-argon 2>/dev/null || true

    clean_packages package/custom/OpenWrt-Packages

    # Keep passwall package metadata aligned with the upstream custom feed.
    if [ -d package/custom/OpenWrt-Packages/.git ]; then
        git -C package/custom/OpenWrt-Packages checkout -- tcping luci-app-passwall/Makefile luci-app-passwall2/Makefile 2>/dev/null || true
    fi

    # Follow the 21.02 optimized script style: xray-core/geodata are handled by
    # the custom package feed, so do not drop them explicitly here.
    if [ -d "package/custom/OpenWrt-Packages" ]; then
        rm -rf package/custom/OpenWrt-Packages/shadowsocks-rust 2>/dev/null || true
        rm -rf package/custom/OpenWrt-Packages/simple-obfs 2>/dev/null || true
        rm -rf package/custom/OpenWrt-Packages/rooter 2>/dev/null || true
    fi

    drop_package "luci-theme-argon"
    if [ ! -d "package/custom/luci-theme-argon" ]; then
        echo "Cloning luci-theme-argon..."
        git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git package/custom/luci-theme-argon
    fi

    if [ -d "package/custom/OpenWrt-Packages/golang" ]; then
        echo "Updating golang from custom packages..."
        rm -rf feeds/packages/lang/golang
        cp -a package/custom/OpenWrt-Packages/golang feeds/packages/lang/golang
    elif [ ! -d "feeds/packages/lang/golang" ]; then
        echo "Custom golang not found, cloning sbwml/packages_lang_golang 25.x..."
        git clone --depth 1 -b 25.x https://github.com/sbwml/packages_lang_golang.git feeds/packages/lang/golang
    fi

    echo "Setting up specific applications..."
    if [ ! -d "package/daed" ]; then
        git clone --depth 1 https://github.com/QiuSimons/luci-app-daed.git package/daed
    fi

    echo "Third-party packages setup completed"
}

function configure_unwanted_packages() {
    echo "Removing unwanted packages..."

    local unwanted_package_options=(
        "luci-app-ssr-plus_INCLUDE_NONE_V2RAY"
        "luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Client"
        "luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server"
        "luci-app-ssr-plus_INCLUDE_ShadowsocksR_NONE_Server"
        "luci-app-ssr-plus_INCLUDE_ShadowsocksR_Rust_Client"
        "luci-app-ssr-plus_INCLUDE_ShadowsocksR_Rust_Server"
        "luci-app-passwall2_INCLUDE_ShadowsocksR_Libev_Client"
        "luci-app-passwall2_INCLUDE_Shadowsocks_Libev_Client"
        "luci-app-passwall2_INCLUDE_Haproxy"
        "luci-app-passwall2_INCLUDE_Simple_Obfs"
    )

    for package in "${unwanted_package_options[@]}"; do
        config_package_del "$package"
    done

    local unwanted_runtime_packages=(
        "shadowsocks-rust-sslocal"
        "shadowsocks-rust-ssserver"
        "simple-obfs"
        "tcping-simple"
    )

    for package in "${unwanted_runtime_packages[@]}"; do
        config_package_del "$package"
    done

    config_package_add "luci-theme-argon"

    echo "Unwanted packages removed"
}

function configure_network_packages() {
    echo "Configuring network packages..."

    config_package_add "curl"
    config_package_add "socat"
    config_package_add "kmod-tcp-bbr"
    config_package_add "kmod-nft-bridge"

    # 24.10 uses firewall4/nftables. Keep the Passwall2 transparent proxy
    # selection in the nftables family instead of the 21.02 iptables options.
    config_package_add "kmod-nft-socket"
    config_package_add "kmod-nft-tproxy"

    echo "Network packages configured"
}

function configure_system_packages() {
    echo "Configuring system packages..."

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

    local usb_packages=(
        "usbutils"
        "kmod-usb-net"
        "kmod-usb-net-rndis"
        "kmod-usb-net-cdc-ether"
        "kmod-usb-net-ipheth"
        "kmod-usb-core"
        "kmod-usb-ehci"
        "kmod-usb-storage"
        "kmod-usb-storage-extras"
        "kmod-usb-storage-uas"
        "kmod-usb-ohci"
        "kmod-usb-uhci"
        "kmod-usb-xhci-hcd"
        "kmod-usb-xhci-mtk"
        "kmod-usb2"
        "kmod-usb3"
        "usb-modeswitch"
        "sendat"
        "luci-app-usb3disable"
    )

    for package in "${usb_packages[@]}"; do
        config_package_del "$package"
    done

    config_del "DEFAULT_kmod-usb-net-rndis"
    config_del "DEFAULT_kmod-usb2"
    config_del "DEFAULT_kmod-usb3"
    config_del "DEFAULT_usbutils"

    echo "System packages configured"
}

function configure_shell_packages() {
    echo "Configuring shell and terminal packages..."

    config_package_add "micro"
    config_package_add "byobu"
    config_package_add "tmux"
    config_package_add "fish"

    echo "Shell packages configured"
}

function configure_custom_applications() {
    echo "Configuring custom applications..."

    config_package_del "luci-app-mentohust"
    config_package_del "mentohust"

    # config_package_add "luci-app-daed"
    configure_daed_kernel_options

    echo "Enabling Passwall2..."
    config_package_add "luci-app-passwall2"
    config_package_add "luci-app-passwall2_INCLUDE_Hysteria"
    config_package_add "luci-app-passwall2_Nftables_Transparent_Proxy"
    config_package_add "tcping"

    echo "Custom applications configured"
}

function setup_default_theme() {
    echo "Setting default LuCI theme to argon..."

    if [ -d feeds/luci/collections ]; then
        find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' {} +
    fi
}

# ============================================
# Main Configuration
# ============================================

echo "Device list before fixed:"
config_device_list

fix_target_platform_config
keep_only_komi_a31

setup_default_theme

setup_third_party_packages
configure_unwanted_packages
configure_network_packages
configure_system_packages
configure_shell_packages
configure_custom_applications

# ============================================
# Apply All Optimizations
# ============================================

echo "Starting optimization process..."

apply_optimizations_by_level
apply_build_optimizations
apply_mt7981_optimizations
apply_compiler_optimizations

setup_default_shell
setup_custom_lan_ip

echo "All optimizations and configurations completed successfully"

# ============================================
# Configuration Verification
# ============================================

echo "Verifying build configuration..."

echo "Enabled target devices:"
grep -E "CONFIG_TARGET_mediatek_filogic_DEVICE_.*=y|CONFIG_TARGET_DEVICE.*=y|CONFIG_TARGET_PROFILE" .config || true

echo "Enabled optimization flags:"
echo "  - LTO: ${ENABLE_LTO:-true}"
echo "  - MOLD: ${ENABLE_MOLD:-true}"
echo "  - BPF: ${ENABLE_BPF:-true}"
echo "  - KERNEL_CLANG_LTO: ${KERNEL_CLANG_LTO:-true}"
echo "  - USE_GCC14: ${USE_GCC14:-true}"
echo "  - ADVANCED_OPTIMIZATIONS: ${ENABLE_ADVANCED_OPTIMIZATIONS:-true}"

echo "Package statistics:"
total_packages=$(grep -c '^CONFIG_PACKAGE_.*=y' .config || true)
luci_apps=$(grep -c '^CONFIG_PACKAGE_luci-app.*=y' .config || true)
kernel_modules=$(grep -c '^CONFIG_PACKAGE_kmod.*=y' .config || true)
echo "  - Total packages: $total_packages"
echo "  - LuCI apps: $luci_apps"
echo "  - Kernel modules: $kernel_modules"

echo "Configuration verification completed"
