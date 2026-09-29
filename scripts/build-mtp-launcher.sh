#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:-$ROOT/twrp-base.img}"
OUT="${2:-$ROOT/recovery-wifi/out/rctools-mtpd}"
WORK="${RUNNER_TEMP:-/tmp}/channel-mtp-build"

test -s "$BASE"
rm -rf "$WORK"
mkdir -p "$WORK/root" "$(dirname "$OUT")"

python3 - "$BASE" "$WORK/ramdisk.lzma" <<'PY'
from pathlib import Path
import struct, sys
src=Path(sys.argv[1]).read_bytes()
if src[:8] != b"ANDROID!":
    raise SystemExit("not an Android boot image")
k=struct.unpack_from("<I", src, 8)[0]
r=struct.unpack_from("<I", src, 16)[0]
p=struct.unpack_from("<I", src, 36)[0]
align=lambda v,n:(v+n-1)//n*n
ro=align(p+k,p)
ram=src[ro:ro+r]
if len(ram) != r:
    raise SystemExit("incomplete ramdisk")
Path(sys.argv[2]).write_bytes(ram)
print("TWRP external ramdisk:", r, "bytes")
PY

xz --format=lzma -dc "$WORK/ramdisk.lzma" > "$WORK/ramdisk.cpio"
(
  cd "$WORK/root"
  cpio -idm --no-absolute-filenames < "$WORK/ramdisk.cpio" >/dev/null 2>&1
)

MTP_LIB="$WORK/root/system/lib64/libtwrpmtp-ffs.so"
USB_RC="$WORK/root/init.recovery.usb.rc"

test -s "$MTP_LIB"
test -s "$USB_RC"

readelf -Ws "$MTP_LIB" | c++filt | grep -Fq 'twrpMtp::twrpMtp(int)'
readelf -Ws "$MTP_LIB" | c++filt | grep -Fq 'twrpMtp::forkserver(int*)'
grep -Fq 'functions/mtp.gs0' "$USB_RC"
grep -Fq 'sys.usb.config=mtp' "$USB_RC"
grep -Fq 'sys.usb.config=mtp,adb' "$USB_RC"

NDK=""
for cand in   "${ANDROID_NDK_ROOT:-}"   "${ANDROID_NDK_HOME:-}"   "${ANDROID_HOME:-}/ndk-bundle"   "${ANDROID_SDK_ROOT:-}/ndk-bundle"
do
  [ -n "$cand" ] || continue
  if [ -x "$cand/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang++" ]; then
    NDK="$cand"
    break
  fi
done

if [ -z "$NDK" ]; then
  SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [ -n "$SDK" ] && [ -d "$SDK/ndk" ]; then
    while IFS= read -r cand; do
      if [ -x "$cand/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang++" ]; then
        NDK="$cand"
      fi
    done < <(find "$SDK/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V)
  fi
fi

[ -n "$NDK" ] || {
  echo "No installed Android NDK with API 29 ARM64 clang++ was found" >&2
  exit 1
}

BIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
CXX="$BIN/aarch64-linux-android29-clang++"
STRIP="$BIN/llvm-strip"

echo "Using Android NDK: $NDK"
"$CXX" --version | head -n1

"$CXX"   -std=c++17   -Os   -fPIE -pie   -fno-exceptions -fno-rtti   -nostdlib++   -Wl,--gc-sections   -Wl,--allow-shlib-undefined   -Wl,--no-as-needed   -L"$(dirname "$MTP_LIB")"   "$ROOT/recovery-wifi/rctools-mtpd.cpp"   -ltwrpmtp-ffs   -Wl,--as-needed   -o "$OUT"

"$STRIP" --strip-unneeded "$OUT"

file "$OUT"
readelf -d "$OUT" | tee "$WORK/rctools-mtpd.dynamic.txt"
readelf -Ws "$OUT" | c++filt | grep -E 'twrpMtp::(twrpMtp|forkserver)' | tee "$WORK/rctools-mtpd.symbols.txt"

grep -Fq 'Shared library: [libtwrpmtp-ffs.so]' "$WORK/rctools-mtpd.dynamic.txt"
if grep -Fq 'libc++_shared.so' "$WORK/rctools-mtpd.dynamic.txt"; then
  echo "Unexpected NDK libc++_shared dependency" >&2
  exit 1
fi

echo "MTP launcher size: $(stat -c%s "$OUT") bytes"
