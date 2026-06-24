# KONKA KOMI A31 ImmortalWrt Builder

Builds ImmortalWrt 24.10 / kernel 6.6 for a KONKA KOMI A31 upgraded to 512 MB RAM.

## What this project does

- Uses `references/immortalwrt-mt798x-6.6` locally, or clones `padavanonly/immortalwrt-mt798x-6.6` in GitHub Actions.
- Builds only `konka_komi-a31`.
- Applies `patches/openwrt/010-konka-komi-a31-512mb.patch` so the DTS memory region is 512 MB.
- Keeps the OpenWrt DTS NAND UBI partition at the current U-Boot layout: `0x580000 + 0x7000000`.
- Uses `217heidai/OpenWrt-Packages` branch `openwrt-24.10`.
- Replaces feeds golang with `package/custom/OpenWrt-Packages/golang` when present, matching the 21.02 handling style.
- Uses `jerrykuku/luci-theme-argon` directly, matching the 21.02 handling style without pinning an old tag.
- Enables `luci-app-daed` and daed eBPF kernel options.
- Does not add mentohust.
- Keeps passwall2 lean and removes SSR/simple-obfs/v2ray/sing-box extras.
- Keeps `tcping` because passwall2 uses it for TCP latency checks; downloads are retried to tolerate transient source/network failures.
- Does not add USB packages because KOMI A31 has no usable USB port.
- Builds hanwckf U-Boot compatible `sysupgrade.bin` and `factory.bin` images instead of the upstream `sysupgrade.itb`.
- Enables ccache, LTO, mold, Cortex-A53 optimization, and optional clang ThinLTO/GCC 14 settings.
- Uses the host LLVM/BPF toolchain from the build container for daed eBPF instead of building OpenWrt's LLVM toolchain.

The checked device currently reports:

- board: `konka,komi-a31`
- RAM: `491492 kB`
- flash: `spi0.0` 128 MiB
- running firmware UBI partition: `0x580000 + 0x7000000`
- current UBI volumes: `kernel`, `rootfs`, `kernel2`, `rootfs2`, `rootfs_data`

The 6.6 source tree has a newer upstream KOMI A31 DTS whose UBI size is `0x7a80000`. The checked device and `references/bl-mt798x` U-Boot both use `0x7000000`, so the OpenWrt patch keeps the firmware aligned with the installed bootloader.

The upstream 24.10 / 6.6 KOMI A31 target emits `sysupgrade.itb` with a `fit` UBI volume. hanwckf's `mtkboardboot` path expects a UBI layout with a bootable FIT in the `kernel` volume and squashfs in `rootfs`, so the OpenWrt patch changes KOMI A31 to:

- `sysupgrade.bin`: OpenWrt sysupgrade tar containing `kernel` and `root`.
- `factory.bin`: complete UBI image containing `kernel`, `rootfs`, and `rootfs_data`.
- no `sysupgrade.itb` output.

After a build, the project automatically runs:

```bash
scripts/validate-komi-a31-images.sh LocalWorkdir/openwrt/bin/targets/mediatek/filogic
```

The validator rejects an ITB output, checks the sysupgrade tar magic, checks that the tar kernel payload is FIT, checks that the root payload is squashfs, and checks that `factory.bin` is a UBI image within the 112 MiB `ubi` partition.

If you rebuild and flash U-Boot from `references/bl-mt798x`, also apply `patches/uboot/010-konka-komi-a31-512mb.patch`. The U-Boot mtdparts in `mt7981_konka_komi-a31_defconfig` already match the device (`114688k(ubi)`), but its DTS memory node is still 256 MB upstream.

## Local build with Podman Compose

```bash
podman compose build
podman compose run --rm builder
```

Output is written below:

```text
LocalWorkdir/openwrt/bin/targets/mediatek/filogic/
```

Useful switches:

```bash
DOWNLOAD_ONLY=1 podman compose run --rm builder
CLEAN_SOURCE=1 podman compose run --rm builder
OPTIMIZATION_LEVEL=basic podman compose run --rm builder
```

## GitHub Actions

Run `ImmortalWrt 24.10 6.6 KOMI A31` manually from the Actions tab. The workflow caches `/workdir/.ccache` and uploads `.bin`, manifest, buildinfo, and checksums.
