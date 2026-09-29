#!/usr/bin/env bash
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
GPU_SRC="$ROOT/recovery-wifi/gpu"
OUT="$ROOT/recovery-wifi/out"
BUILD="$ROOT/recovery-wifi/gpu-build"
STUB="$BUILD/stubs"

CROSS="${DS_GPU_CROSS:-${DS_WIFI_CROSS:-aarch64-linux-gnu-}}"
CC="${DS_GPU_CC:-${CROSS}gcc}"
READELF="${DS_GPU_READELF:-${CROSS}readelf}"
STRIP="${DS_GPU_STRIP:-${CROSS}strip}"

for tool in "$CC" "$READELF" "$STRIP"; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing GPU build tool: $tool" >&2
    exit 1
  }
done

mkdir -p "$OUT"
rm -rf "$BUILD"
mkdir -p "$BUILD" "$STUB"

COMMON_CFLAGS=(
  -Os
  -fPIC
  -ffreestanding
  -fno-builtin
  -fno-stack-protector
  -fno-unwind-tables
  -fno-asynchronous-unwind-tables
)

COMMON_LDFLAGS=(
  -nostdlib
  -Wl,--hash-style=both
  -Wl,--gc-sections
)

echo "Building Channel headless GPU support from source"
echo "  compiler=$CC"

"$CC" "${COMMON_CFLAGS[@]}"   -shared "${COMMON_LDFLAGS[@]}"   -Wl,-soname,libsync.so   "$GPU_SRC/libsync_min.c"   -o "$OUT/libsync.so"

"$CC" "${COMMON_CFLAGS[@]}"   -DBUILD_EGL_STUB   -shared "${COMMON_LDFLAGS[@]}"   -Wl,-soname,libEGL_adreno.so   "$GPU_SRC/link_stubs.c"   -o "$STUB/libEGL_adreno.so"

"$CC" "${COMMON_CFLAGS[@]}"   -DBUILD_GLES_STUB   -shared "${COMMON_LDFLAGS[@]}"   -Wl,-soname,libGLESv2_adreno.so   "$GPU_SRC/link_stubs.c"   -o "$STUB/libGLESv2_adreno.so"

"$CC" "${COMMON_CFLAGS[@]}" -c   "$GPU_SRC/egl_probe.c"   -o "$BUILD/egl_probe.o"

"$CC"   -shared "${COMMON_LDFLAGS[@]}"   -Wl,-soname,rctools-gpu-probe.so   -Wl,--no-as-needed   "$BUILD/egl_probe.o"   -L"$STUB"   -lEGL_adreno   -lGLESv2_adreno   -o "$OUT/rctools-gpu-probe.so"

"$STRIP" --strip-unneeded "$OUT/libsync.so"
"$STRIP" --strip-unneeded "$OUT/rctools-gpu-probe.so"

echo "=== libsync ABI ==="
"$READELF" -d "$OUT/libsync.so"
"$READELF" -Ws "$OUT/libsync.so" | tee "$BUILD/libsync.symbols"
grep -Eq '[[:space:]]sync_wait$' "$BUILD/libsync.symbols"
grep -Eq '[[:space:]]sync_merge$' "$BUILD/libsync.symbols"

echo "=== GPU probe dependencies ==="
"$READELF" -d "$OUT/rctools-gpu-probe.so" | tee "$BUILD/probe.dynamic"
grep -Fq 'Shared library: [libEGL_adreno.so]' "$BUILD/probe.dynamic"
grep -Fq 'Shared library: [libGLESv2_adreno.so]' "$BUILD/probe.dynamic"

file "$OUT/libsync.so" | tee "$BUILD/libsync.file"
file "$OUT/rctools-gpu-probe.so" | tee "$BUILD/probe.file"
grep -q 'ARM aarch64' "$BUILD/libsync.file"
grep -q 'ARM aarch64' "$BUILD/probe.file"

rm -f "$OUT/SHA256SUMS"
sha256sum "$OUT"/* | tee "$OUT/SHA256SUMS"

du -h "$OUT/libsync.so" "$OUT/rctools-gpu-probe.so"
