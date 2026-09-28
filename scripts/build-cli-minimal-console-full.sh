#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <minimal.img> <output-dir>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage

BASE_IMG="$(readlink -f "$1")"
OUT_DIR="$(readlink -m "$2")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INTEGRATOR="$ROOT/scripts/build-cli-minimal-console.sh"

CONSOLE_REPO="https://github.com/SaaSD3v/recovery-console.git"
CONSOLE_COMMIT="a524cfc92ccab42830c575120b048c424cd8a782"
BUILDER_COMMIT="692b3ab5bba4944eae9c93ebf9d8825879682941"

TWRP_VERSION="3.5.2_10-0"
TWRP_INSTALLER_SHA256="2c43cee3d2fc64c7632d6f2f49567f59a563446a34b073678eda8b77cb5bd74c"
MAGISK_VERSION="30.7"
MAGISK_APK_SHA256="e0d32d2123532860f97123d927b1bb86c4e08e6fd8a48bfc6b5bee0afae9ebd5"
MAGISKBOOT_SHA256="a18ecbd7981179494b7d281453d6c4e25b5c719e7d2ef7f6eba3c6be3043c58e"

[ -s "$BASE_IMG" ] || { echo "ERROR: minimal image missing: $BASE_IMG" >&2; exit 1; }
[ -x "$INTEGRATOR" ] || { echo "ERROR: integrator missing/not executable: $INTEGRATOR" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT_DIR"

fetch_commit() {
  dest="$1"
  commit="$2"
  git init "$dest"
  git -C "$dest" remote add origin "$CONSOLE_REPO"
  git -C "$dest" fetch --depth=1 origin "$commit"
  git -C "$dest" checkout --detach FETCH_HEAD
  test "$(git -C "$dest" rev-parse HEAD)" = "$commit"
}

echo "==> Fetching pinned headless Recovery Console"
fetch_commit "$WORK/console-src" "$CONSOLE_COMMIT"

echo "==> Fetching pinned proven Channel console builder"
fetch_commit "$WORK/builder-tools" "$BUILDER_COMMIT"

echo "==> Downloading aarch64 musl toolchain"
TOOLCHAIN="$HOME/toolchains/aarch64-linux-musl-cross"
if [ ! -x "$TOOLCHAIN/bin/aarch64-linux-musl-gcc" ]; then
  mkdir -p "$HOME/toolchains"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 \
    -o "$WORK/aarch64-linux-musl-cross.tar.gz" \
    "https://github.com/ravindu644/Droidspaces-OSS/releases/download/compilers/aarch64-linux-musl-cross.tar.gz"
  tar -xzf "$WORK/aarch64-linux-musl-cross.tar.gz" -C "$HOME/toolchains"
fi
"$TOOLCHAIN/bin/aarch64-linux-musl-gcc" --version

echo "==> Building headless Recovery Console"
(
  cd "$WORK/console-src"
  ./scripts/build-freetype.sh aarch64-linux-musl
  make clean
  make aarch64 V=1
)
CONSOLE_BIN="$WORK/console-src/output/recovery-console-aarch64"
test -s "$CONSOLE_BIN"
chmod 0755 "$CONSOLE_BIN"
file "$CONSOLE_BIN"
if readelf -l "$CONSOLE_BIN" | grep -q 'Requesting program interpreter'; then
  echo "ERROR: Recovery Console must be static" >&2
  exit 1
fi
grep -Fq 'headless PTY/socket mode' "$WORK/console-src/display.c"

echo "==> Downloading validated official Channel TWRP installer"
NAME="twrp-installer-$TWRP_VERSION-channel.zip"
PAGE="https://dl.twrp.me/channel/$NAME.html"
PAGE_HTML="$(curl -fLsS --retry 3 --retry-delay 2 \
  -A 'Mozilla/5.0 GitHub-Actions Channel-CLI-Minimal' "$PAGE")"
HREF="$(printf '%s' "$PAGE_HTML" \
  | grep -oE 'href="[^"]*twrp-installer-[^"]*-channel\.zip"' \
  | head -n1 | cut -d'"' -f2 || true)"

case "$HREF" in
  http://*|https://*) FILE_URL="$HREF" ;;
  /*) FILE_URL="https://dl.twrp.me$HREF" ;;
  "") FILE_URL="" ;;
  *) FILE_URL="https://dl.twrp.me/channel/$HREF" ;;
esac

INSTALLER="$WORK/$NAME"
ok=0
for URL in \
  "https://eu.dl.twrp.me/channel/$NAME" \
  "$FILE_URL" \
  "https://dl.twrp.me/channel/$NAME?download=1"
do
  [ -n "$URL" ] || continue
  rm -f "$INSTALLER.part"
  if curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 \
      -A 'Mozilla/5.0 GitHub-Actions Channel-CLI-Minimal' \
      -e "$PAGE" -o "$INSTALLER.part" "$URL" &&
     unzip -t "$INSTALLER.part" >/dev/null 2>&1; then
    mv "$INSTALLER.part" "$INSTALLER"
    ok=1
    break
  fi
done
[ "$ok" -eq 1 ] || { echo "ERROR: could not download official TWRP installer" >&2; exit 1; }
echo "$TWRP_INSTALLER_SHA256  $INSTALLER" | sha256sum -c -

unzip -Z1 "$INSTALLER" | grep -Eq '^ramdisk-(twrp|recovery)\.cpio$'
unzip -Z1 "$INSTALLER" | grep -q '^META-INF/com/google/android/update-binary$'
unzip -Z1 "$INSTALLER" | grep -q '^magiskboot$'

echo "==> Installing pinned host magiskboot"
MAGISK_APK="$WORK/Magisk-v$MAGISK_VERSION.apk"
curl -fL --retry 3 --retry-delay 2 \
  -o "$MAGISK_APK" \
  "https://github.com/topjohnwu/Magisk/releases/download/v$MAGISK_VERSION/Magisk-v$MAGISK_VERSION.apk"
echo "$MAGISK_APK_SHA256  $MAGISK_APK" | sha256sum -c -
unzip -p "$MAGISK_APK" lib/x86_64/libmagiskboot.so > "$WORK/magiskboot"
chmod 0755 "$WORK/magiskboot"
echo "$MAGISKBOOT_SHA256  $WORK/magiskboot" | sha256sum -c -

BUILDER="$WORK/builder-tools/builder/integrate-channel-twrp-zip.sh"
chmod +x "$BUILDER"

OUTPUT_IMG="$OUT_DIR/channel-twrp-3.5.2_10-0-cli-minimal-recovery-console.img"
"$INTEGRATOR" \
  "$BASE_IMG" \
  "$INSTALLER" \
  "$CONSOLE_BIN" \
  "$WORK/magiskboot" \
  "$BUILDER" \
  "$OUTPUT_IMG"

cp "$CONSOLE_BIN" "$OUT_DIR/recovery-console-channel-aarch64-headless"
sha256sum "$OUT_DIR/recovery-console-channel-aarch64-headless" \
  > "$OUT_DIR/recovery-console-channel-aarch64-headless.sha256"

cat > "$OUT_DIR/BUILD-INFO.txt" <<EOF
Device: Motorola Moto G7 Play (channel)
Artifact: CLI-minimal + permanent headless Recovery Console
Minimal base: $(basename "$BASE_IMG")
Minimal base SHA-256: $(sha256sum "$BASE_IMG" | awk '{print $1}')
Recovery Console repository: SaaSD3v/recovery-console
Recovery Console commit: $CONSOLE_COMMIT
Console mode: auto DRM/FBDEV, headless PTY/socket fallback 120x40
Console path: /system/bin/recovery-console
Console socket: /tmp/rc.sock
Console autostart: YES
Stock TWRP recovery service: disabled by permanent integration
Console exit fallback: start recovery
Builder commit: $BUILDER_COMMIT
TWRP installer version: $TWRP_VERSION
Kernel integration: unchanged from minimal base
Recovery DTBO integration: unchanged from minimal base
EOF

echo "==> Final Channel CLI-minimal + headless Recovery Console artifacts"
ls -lh "$OUT_DIR"
cat "$OUTPUT_IMG.sha256"
