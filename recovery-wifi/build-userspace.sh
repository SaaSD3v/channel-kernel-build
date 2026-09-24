#!/usr/bin/env bash
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
OUT="$ROOT/recovery-wifi/out"
SRC="$ROOT/recovery-wifi/src"
PREFIX="$ROOT/recovery-wifi/prefix"
CROSS=aarch64-linux-gnu-
CC=${CROSS}gcc
STRIP=${CROSS}strip

WPA_TAG=hostap_2_9
BUSYBOX_COMMIT=1a64f6a20aaf6ea4dbba68bbfa8cc1ab7e5c57c4
LIBNL_TAG=libnl3_2_25

rm -rf "$OUT" "$SRC" "$PREFIX"
mkdir -p "$OUT" "$SRC" "$PREFIX"

# libnl 3.2 for the native NL80211 path.
git clone --depth=1 --branch "$LIBNL_TAG" https://github.com/thom311/libnl.git "$SRC/libnl"
pushd "$SRC/libnl" >/dev/null
autoreconf -fi
./configure \
  --host=aarch64-linux-gnu \
  --prefix="$PREFIX" \
  --enable-static \
  --disable-shared \
  --disable-cli
make -j"$(nproc)"
make install
popd >/dev/null

# Standalone upstream wpa_supplicant 2.9.  The Android/LineageOS fork from
# the same generation includes the Android HIDL notification layer even when
# built through the standalone Makefile; recovery has no HIDL framework.
# Use the upstream hostap tag instead so the binary is genuinely self-contained.
git init "$SRC/wpa"
git -C "$SRC/wpa" remote add origin https://git.w1.fi/hostap.git
git -C "$SRC/wpa" fetch --depth=1 origin "refs/tags/$WPA_TAG"
git -C "$SRC/wpa" checkout --detach FETCH_HEAD
cp "$ROOT/recovery-wifi/wpa_supplicant.config" "$SRC/wpa/wpa_supplicant/.config"
cat >> "$SRC/wpa/wpa_supplicant/.config" <<EOF
CFLAGS += -Os -ffunction-sections -fdata-sections -I$PREFIX/include/libnl3
LIBS += -L$PREFIX/lib
LIBS_c += -L$PREFIX/lib
EOF

pushd "$SRC/wpa/wpa_supplicant" >/dev/null
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
make clean || true
make -j"$(nproc)" \
  CC="$CC" \
  PKG_CONFIG="pkg-config --static" \
  LDFLAGS='-static -Wl,--gc-sections' \
  wpa_supplicant wpa_cli wpa_passphrase
cp wpa_supplicant "$OUT/wpa_supplicant.ds"
cp wpa_cli "$OUT/wpa_cli.ds"
cp wpa_passphrase "$OUT/wpa_passphrase.ds"
popd >/dev/null

# BusyBox supplies DHCP/network tooling without depending on TWRP Bionic.
git init "$SRC/busybox"
git -C "$SRC/busybox" remote add origin https://github.com/mirror/busybox.git
git -C "$SRC/busybox" fetch --depth=1 origin "$BUSYBOX_COMMIT"
git -C "$SRC/busybox" checkout --detach FETCH_HEAD
pushd "$SRC/busybox" >/dev/null
make ARCH=arm64 CROSS_COMPILE="$CROSS" defconfig
sed -i 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' .config
sed -i 's/^CONFIG_TC=y$/# CONFIG_TC is not set/' .config || true
yes '' | make ARCH=arm64 CROSS_COMPILE="$CROSS" oldconfig >/dev/null
make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE="$CROSS"
cp busybox "$OUT/busybox.ds"
popd >/dev/null

# Minimal recovery-only WCNSS handshake; no Android framework/QMI/vendor libs.
"$CC" -static -Os -ffunction-sections -fdata-sections \
  -Wl,--gc-sections \
  "$ROOT/recovery-wifi/wcnss-recovery.c" \
  -o "$OUT/wcnss-recovery"

cp "$ROOT/recovery-wifi/wifi" "$OUT/wifi"
cp "$ROOT/recovery-wifi/wifi-udhcpc.script" "$OUT/wifi-udhcpc.script"
chmod 0755 "$OUT"/*

for f in "$OUT/wpa_supplicant.ds" "$OUT/wpa_cli.ds" "$OUT/wpa_passphrase.ds" \
         "$OUT/busybox.ds" "$OUT/wcnss-recovery"; do
  "$STRIP" --strip-all "$f"
  file "$f"
  file "$f" | grep -q 'statically linked'
done

for applet in udhcpc ip ifconfig ping grep sed tail pkill mount tee sleep cat chmod mkdir; do
  "$OUT/busybox.ds" --list | grep -qx "$applet" || {
    echo "Missing BusyBox applet: $applet" >&2
    exit 1
  }
done

sha256sum "$OUT"/* | tee "$OUT/SHA256SUMS"
du -h "$OUT"/*
