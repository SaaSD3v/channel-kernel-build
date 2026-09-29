#!/usr/bin/env bash
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
OUT="$ROOT/recovery-wifi/out"
SRC="$ROOT/recovery-wifi/src"
PREFIX="$ROOT/recovery-wifi/prefix"

# Device build profile. channel remains the default and therefore preserves the
# already validated Moto G7 Play build. New ports add their own
# recovery-wifi/devices/<codename>/device.conf instead of forking this script.
DEVICE="${DEVICE:-channel}"
DEVICE_PROFILE="$ROOT/recovery-wifi/devices/$DEVICE/device.conf"
if [[ ! -f "$DEVICE_PROFILE" ]]; then
  echo "Missing recovery Wi-Fi device profile: $DEVICE_PROFILE" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$DEVICE_PROFILE"

TARGET_ARCH="${DS_WIFI_ARCH:-arm64}"
CROSS="${DS_WIFI_CROSS:-aarch64-linux-gnu-}"
HOST_TRIPLE="${DS_WIFI_HOST:-aarch64-linux-gnu}"
OPENSSL_TARGET="${DS_WIFI_OPENSSL_TARGET:-linux-aarch64}"
CC="${CROSS}gcc"
STRIP="${CROSS}strip"

echo "Recovery Wi-Fi userspace device: $DEVICE"
echo "  arch=$TARGET_ARCH host=$HOST_TRIPLE cross=$CROSS openssl=$OPENSSL_TARGET"

WPA_TAG=hostap_2_9
WPA_COMMIT=ca8c2bd28ad53f431d6ee60ef754e98cfdb4c17b
OPENSSL_TAG=OpenSSL_1_1_1w
BUSYBOX_COMMIT=1a64f6a20aaf6ea4dbba68bbfa8cc1ab7e5c57c4
IPTABLES_COMMIT=c16bdec15137b241586310d0e61bc88cc3726004 # iptables 1.6.2 legacy
LIBNL_TAG=libnl3_2_25
IW_COMMIT=8934cc42695817d63b00507c20eaefa98174e0a9 # iw v5.9
TINYALSA_COMMIT=1c5fb68ced57d838f2b7ecd0c00bc1fefc9ab60d # tinyalsa v2.0.0

rm -rf "$OUT" "$SRC" "$PREFIX"
mkdir -p "$OUT" "$SRC" "$PREFIX"

# libnl 3.2 for the native NL80211 path.
git clone --depth=1 --branch "$LIBNL_TAG" https://github.com/thom311/libnl.git "$SRC/libnl"
pushd "$SRC/libnl" >/dev/null
autoreconf -fi
./configure \
  --host="$HOST_TRIPLE" \
  --prefix="$PREFIX" \
  --enable-static \
  --disable-shared \
  --disable-cli
make -j"$(nproc)"
make install
popd >/dev/null

# Static OpenSSL backend for SAE/WPA3 and OWE.  The internal hostap crypto
# backend does not implement the generic EC/ECDH API required by these modes.
git init "$SRC/openssl"
git -C "$SRC/openssl" remote add origin https://github.com/openssl/openssl.git
git -C "$SRC/openssl" fetch --depth=1 origin "refs/tags/$OPENSSL_TAG"
git -C "$SRC/openssl" checkout --detach FETCH_HEAD
pushd "$SRC/openssl" >/dev/null
./Configure "$OPENSSL_TARGET" \
  --cross-compile-prefix="$CROSS" \
  no-shared \
  no-tests
make -j"$(nproc)" build_libs
popd >/dev/null

# Standalone upstream wpa_supplicant 2.9.  The Android/LineageOS fork from
# the same generation includes the Android HIDL notification layer even when
# built through the standalone Makefile; recovery has no HIDL framework.
# Use the upstream hostap tag instead so the binary is genuinely self-contained.
git init "$SRC/wpa"
hostap_fetched=0
for hostap_origin in \
    https://github.com/rsta2/hostap.git \
    https://git.w1.fi/hostap.git
do
  git -C "$SRC/wpa" remote remove origin >/dev/null 2>&1 || true
  git -C "$SRC/wpa" remote add origin "$hostap_origin"
  if timeout 75 git -C "$SRC/wpa" -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=30 \
      fetch --depth=1 origin "refs/tags/$WPA_TAG"; then
    resolved=$(git -C "$SRC/wpa" rev-parse 'FETCH_HEAD^{commit}')
    if [ "$resolved" = "$WPA_COMMIT" ]; then
      echo "Pinned hostap source: $hostap_origin @ $resolved"
      hostap_fetched=1
      break
    fi
    echo "Rejecting hostap mirror with unexpected commit: $resolved" >&2
  else
    echo "Hostap source unavailable: $hostap_origin" >&2
  fi
done
[ "$hostap_fetched" -eq 1 ] || {
  echo "Could not fetch pinned hostap $WPA_TAG / $WPA_COMMIT" >&2
  exit 1
}
git -C "$SRC/wpa" checkout --detach "$WPA_COMMIT"
cp "$ROOT/recovery-wifi/wpa_supplicant.config" "$SRC/wpa/wpa_supplicant/.config"
cat >> "$SRC/wpa/wpa_supplicant/.config" <<EOF
CFLAGS += -Os -ffunction-sections -fdata-sections -I$PREFIX/include/libnl3 -I$SRC/openssl/include
LIBS += -L$PREFIX/lib -L$SRC/openssl
LIBS_p += -L$SRC/openssl
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

# Dedicated static hostapd for recovery SoftAP. The channel PRONTO driver has
# a real cfg80211 SoftAP path (NL80211_IFTYPE_AP + start_ap/stop_ap), so keep
# AP control separate from the already validated station supplicant.
cp "$ROOT/recovery-wifi/hostapd.config" "$SRC/wpa/hostapd/.config"
cat >> "$SRC/wpa/hostapd/.config" <<EOF
CFLAGS += -Os -ffunction-sections -fdata-sections -I$PREFIX/include/libnl3 -I$SRC/openssl/include
LIBS += -L$PREFIX/lib -L$SRC/openssl
EOF

pushd "$SRC/wpa/hostapd" >/dev/null
make clean || true
make -j"$(nproc)" \
  CC="$CC" \
  PKG_CONFIG="pkg-config --static" \
  LDFLAGS='-static -Wl,--gc-sections' \
  hostapd
cp hostapd "$OUT/hostapd.ds"
popd >/dev/null

# Static iw from the same Droidspaces fork used by VirtualAP. Keep it separate
# from Android/TWRP userspace so recovery can exercise cfg80211 add_virtual_intf
# directly and create an AP VIF without converting the validated wlan0 STA.
git init "$SRC/iw"
git -C "$SRC/iw" remote add origin https://github.com/Droidspaces/iw-vap.git
git -C "$SRC/iw" fetch --depth=1 origin "$IW_COMMIT"
git -C "$SRC/iw" checkout --detach FETCH_HEAD
pushd "$SRC/iw" >/dev/null
make clean || true
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export CFLAGS="-Os -ffunction-sections -fdata-sections -I$PREFIX/include/libnl3"
export LDFLAGS='-static -Wl,--gc-sections'
export PKG_CONFIG="pkg-config --static"
make -j"$(nproc)" \
  CC="$CC" \
  V=1
unset CFLAGS LDFLAGS PKG_CONFIG
cp iw "$OUT/iw.ds"
popd >/dev/null


# TinyALSA recovery toolkit. Build one static multicall binary instead of four
# separate static executables so libc and libtinyalsa are stored only once.
git init "$SRC/tinyalsa"
git -C "$SRC/tinyalsa" remote add origin https://github.com/tinyalsa/tinyalsa.git
git -C "$SRC/tinyalsa" fetch --depth=1 origin "$TINYALSA_COMMIT"
git -C "$SRC/tinyalsa" checkout --detach FETCH_HEAD
test "$(git -C "$SRC/tinyalsa" rev-parse HEAD)" = "$TINYALSA_COMMIT"

make -C "$SRC/tinyalsa/src" clean || true
make -C "$SRC/tinyalsa/src" -j"$(nproc)" \
  CROSS_COMPILE="$CROSS" \
  CFLAGS='-Os -ffunction-sections -fdata-sections' \
  libtinyalsa.a

TINYOBJ="$SRC/tinyalsa/recovery-obj"
rm -rf "$TINYOBJ"
mkdir -p "$TINYOBJ"

for tool in tinyplay tinycap tinymix tinypcminfo; do
  "$CC" -Os -ffunction-sections -fdata-sections \
    -I"$SRC/tinyalsa/include" \
    -Dmain="${tool}_main" \
    -Doptparse_init="${tool}_optparse_init" \
    -Doptparse="${tool}_optparse" \
    -Doptparse_long="${tool}_optparse_long" \
    -Doptparse_arg="${tool}_optparse_arg" \
    -c "$SRC/tinyalsa/utils/${tool}.c" \
    -o "$TINYOBJ/${tool}.o"
done

"$CC" -Os -ffunction-sections -fdata-sections \
  -I"$SRC/tinyalsa/include" \
  -c "$ROOT/recovery-wifi/tinybeep.c" \
  -o "$TINYOBJ/tinybeep.o"

"$CC" -Os -ffunction-sections -fdata-sections \
  -c "$ROOT/recovery-wifi/tinyalsa-multicall.c" \
  -o "$TINYOBJ/tinyalsa-multicall.o"

"$CC" -static -no-pie -Wl,--gc-sections \
  "$TINYOBJ/tinyalsa-multicall.o" \
  "$TINYOBJ/tinyplay.o" "$TINYOBJ/tinycap.o" \
  "$TINYOBJ/tinymix.o" "$TINYOBJ/tinypcminfo.o" "$TINYOBJ/tinybeep.o" \
  "$SRC/tinyalsa/src/libtinyalsa.a" -ldl \
  -o "$OUT/tinyalsa.ds"

# BusyBox supplies DHCP/network tooling without depending on TWRP Bionic.
git init "$SRC/busybox"
git -C "$SRC/busybox" remote add origin https://github.com/mirror/busybox.git
git -C "$SRC/busybox" fetch --depth=1 origin "$BUSYBOX_COMMIT"
git -C "$SRC/busybox" checkout --detach FETCH_HEAD
pushd "$SRC/busybox" >/dev/null
make ARCH="$TARGET_ARCH" CROSS_COMPILE="$CROSS" defconfig

# The recovery hotspot uses BusyBox as its tiny DHCP server. Keep this
# explicit so a BusyBox defconfig change cannot silently remove the applet.
if grep -q '^# CONFIG_UDHCPD is not set$' .config; then
  sed -i 's/^# CONFIG_UDHCPD is not set$/CONFIG_UDHCPD=y/' .config
elif ! grep -q '^CONFIG_UDHCPD=y$' .config; then
  echo 'CONFIG_UDHCPD=y' >> .config
fi

# Recovery time repair uses a one-shot BusyBox NTP client after DHCP. Keep the
# date/timeout applets explicit so a future BusyBox defconfig cannot remove it.
for symbol in CONFIG_DATE CONFIG_NTPD CONFIG_TIMEOUT CONFIG_NSLOOKUP CONFIG_UMOUNT; do
  if grep -q "^# $symbol is not set$" .config; then
    sed -i "s/^# $symbol is not set$/$symbol=y/" .config
  elif ! grep -q "^$symbol=y$" .config; then
    echo "$symbol=y" >> .config
  fi
done

sed -i 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' .config
sed -i 's/^CONFIG_TC=y$/# CONFIG_TC is not set/' .config || true
make ARCH="$TARGET_ARCH" CROSS_COMPILE="$CROSS" silentoldconfig >/dev/null
make -j"$(nproc)" ARCH="$TARGET_ARCH" CROSS_COMPILE="$CROSS"

# Cross-built ARM64 binaries cannot be executed on the x86 GitHub runner.
# Validate every applet used by RCTools networking from the resolved BusyBox config.
for symbol in \
  CONFIG_UDHCPC CONFIG_UDHCPD CONFIG_IP CONFIG_IFCONFIG CONFIG_PING CONFIG_GREP CONFIG_SED \
  CONFIG_TAIL CONFIG_PKILL CONFIG_MOUNT CONFIG_TEE CONFIG_SLEEP CONFIG_CAT \
  CONFIG_CHMOD CONFIG_MKDIR CONFIG_AWK CONFIG_CP CONFIG_MV CONFIG_RM CONFIG_CHOWN \
  CONFIG_SHA256SUM CONFIG_SYNC CONFIG_READLINK CONFIG_DATE CONFIG_NTPD CONFIG_TIMEOUT CONFIG_NSLOOKUP CONFIG_UMOUNT
do
  grep -qx "$symbol=y" .config || {
    echo "Missing required BusyBox setting: $symbol=y" >&2
    exit 1
  }
done
cp .config "$OUT/busybox.config"
cp busybox "$OUT/busybox.ds"
popd >/dev/null

# Static legacy iptables 1.6.2 for DroidSpaces port-forwarding in recovery.
#
# DroidSpaces v6 can program its base NAT rules through the kernel's raw
# IP_TABLES API, but explicit port-forwards still execute iptables(8),
# iptables-save and iptables-restore.  TWRP's external ramdisk is not relied
# on for those tools: build a self-contained ARM64 legacy binary here.
git init "$SRC/iptables"
git -C "$SRC/iptables" remote add origin https://github.com/PKRoma/iptables.git
git -C "$SRC/iptables" fetch --depth=1 origin "$IPTABLES_COMMIT"
git -C "$SRC/iptables" checkout --detach FETCH_HEAD
pushd "$SRC/iptables" >/dev/null
./autogen.sh
PKG_CONFIG_LIBDIR=/nonexistent ./configure \
  --host="$HOST_TRIPLE" \
  --prefix="$PREFIX/iptables" \
  --disable-shared \
  --enable-static \
  --disable-nftables \
  --disable-ipv6 \
  --disable-devel \
  --disable-libipq \
  --disable-bpf-compiler \
  --disable-nfsynproxy \
  --disable-connlabel \
  --with-xt-lock-name=/tmp/xtables.lock \
  CC="$CC" \
  CFLAGS='-Os -ffunction-sections -fdata-sections' \
  LDFLAGS='-Wl,--gc-sections'
# libtool consumes "-static" as a library-selection hint and may still emit a
# dynamic PIE executable.  "-all-static" is the libtool program-link option
# that guarantees no dynamic loader/libc dependency in recovery.
make -j"$(nproc)" LDFLAGS='-all-static -Wl,--gc-sections'
cp iptables/xtables-multi "$OUT/iptables.ds"
popd >/dev/null

# Minimal recovery-only WCNSS handshake; no Android framework/QMI/vendor libs.
"$CC" -static -Os -ffunction-sections -fdata-sections \
  -Wl,--gc-sections \
  "$ROOT/recovery-wifi/wcnss-recovery.c" \
  -o "$OUT/wcnss-recovery"

cp "$ROOT/recovery-wifi/rctools-net" "$OUT/rctools-net"
cp "$ROOT/recovery-wifi/wifi-udhcpc.script" "$OUT/wifi-udhcpc.script"
cp "$ROOT/recovery-wifi/recovery-time-sync" "$OUT/recovery-time-sync"
cp "$ROOT/recovery-wifi/WCNSS_qcom_cfg.ini" "$OUT/WCNSS_qcom_cfg.ini"

chmod 0755 \
  "$OUT/rctools-net" "$OUT/wifi-udhcpc.script" "$OUT/recovery-time-sync" \
  "$OUT/wpa_supplicant.ds" "$OUT/wpa_cli.ds" "$OUT/wpa_passphrase.ds" \
  "$OUT/hostapd.ds" "$OUT/iw.ds" "$OUT/busybox.ds" "$OUT/iptables.ds" "$OUT/wcnss-recovery" "$OUT/tinyalsa.ds"
chmod 0644 "$OUT/WCNSS_qcom_cfg.ini"

for f in "$OUT/wpa_supplicant.ds" "$OUT/wpa_cli.ds" "$OUT/wpa_passphrase.ds" \
         "$OUT/hostapd.ds" "$OUT/iw.ds" "$OUT/busybox.ds" "$OUT/iptables.ds" "$OUT/wcnss-recovery" "$OUT/tinyalsa.ds"; do
  "$STRIP" --strip-all "$f"
  file "$f"
  file "$f" | grep -q 'statically linked'
done

sha256sum "$OUT"/* | tee "$OUT/SHA256SUMS"
du -h "$OUT"/*
