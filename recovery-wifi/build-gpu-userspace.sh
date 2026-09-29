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

"$CC" "${COMMON_CFLAGS[@]}" -DBUILD_EGL_STUB   -shared "${COMMON_LDFLAGS[@]}"   -Wl,-soname,libEGL_adreno.so   "$GPU_SRC/link_stubs.c"   -o "$STUB/libEGL_adreno.so"

"$CC" "${COMMON_CFLAGS[@]}" -DBUILD_GLES_STUB   -shared "${COMMON_LDFLAGS[@]}"   -Wl,-soname,libGLESv2_adreno.so   "$GPU_SRC/link_stubs.c"   -o "$STUB/libGLESv2_adreno.so"

"$CC" "${COMMON_CFLAGS[@]}" -DBUILD_OPENCL_STUB   -shared "${COMMON_LDFLAGS[@]}"   -Wl,-soname,libOpenCL.so   "$GPU_SRC/link_stubs.c"   -o "$STUB/libOpenCL.so"

"$CC" "${COMMON_CFLAGS[@]}" -DBUILD_HARDWARE_STUB   -shared "${COMMON_LDFLAGS[@]}"   -Wl,-soname,libhardware.so   "$GPU_SRC/link_stubs.c"   -o "$STUB/libhardware.so"

"$CC" "${COMMON_CFLAGS[@]}" -c   "$GPU_SRC/egl_probe.c"   -o "$BUILD/egl_probe.o"

"$CC" -shared "${COMMON_LDFLAGS[@]}"   -Wl,-soname,rctools-gpu-probe.so   -Wl,--no-as-needed   "$BUILD/egl_probe.o"   -L"$STUB"   -lEGL_adreno   -lGLESv2_adreno   -o "$OUT/rctools-gpu-probe.so"

"$CC" "${COMMON_CFLAGS[@]}" -c   "$GPU_SRC/opencl_probe.c"   -o "$BUILD/opencl_probe.o"

"$CC" -shared "${COMMON_LDFLAGS[@]}"   -Wl,-soname,rctools-opencl-probe.so   -Wl,--no-as-needed   "$BUILD/opencl_probe.o"   -L"$STUB"   -lOpenCL   -o "$OUT/rctools-opencl-probe.so"

"$CC" "${COMMON_CFLAGS[@]}" -c   "$GPU_SRC/gralloc_probe.c"   -o "$BUILD/gralloc_probe.o"

"$CC" -shared "${COMMON_LDFLAGS[@]}"   -Wl,-soname,rctools-gralloc-probe.so   -Wl,--no-as-needed   "$BUILD/gralloc_probe.o"   -L"$STUB"   -lhardware   -o "$OUT/rctools-gralloc-probe.so"

for f in   "$OUT/libsync.so"   "$OUT/rctools-gpu-probe.so"   "$OUT/rctools-opencl-probe.so"   "$OUT/rctools-gralloc-probe.so"
do
  "$STRIP" --strip-unneeded "$f"
done

echo "=== libsync ABI ==="
"$READELF" -d "$OUT/libsync.so"
"$READELF" -Ws "$OUT/libsync.so" | tee "$BUILD/libsync.symbols"
grep -Eq '[[:space:]]sync_wait$' "$BUILD/libsync.symbols"
grep -Eq '[[:space:]]sync_merge$' "$BUILD/libsync.symbols"

echo "=== EGL probe dependencies ==="
"$READELF" -d "$OUT/rctools-gpu-probe.so" | tee "$BUILD/egl.dynamic"
grep -Fq 'Shared library: [libEGL_adreno.so]' "$BUILD/egl.dynamic"
grep -Fq 'Shared library: [libGLESv2_adreno.so]' "$BUILD/egl.dynamic"

echo "=== OpenCL probe dependencies ==="
"$READELF" -d "$OUT/rctools-opencl-probe.so" | tee "$BUILD/opencl.dynamic"
grep -Fq 'Shared library: [libOpenCL.so]' "$BUILD/opencl.dynamic"

echo "=== gralloc probe dependencies ==="
"$READELF" -d "$OUT/rctools-gralloc-probe.so" | tee "$BUILD/gralloc.dynamic"
grep -Fq 'Shared library: [libhardware.so]' "$BUILD/gralloc.dynamic"

for f in   "$OUT/libsync.so"   "$OUT/rctools-gpu-probe.so"   "$OUT/rctools-opencl-probe.so"   "$OUT/rctools-gralloc-probe.so"
do
  file "$f"
  file "$f" | grep -q 'ARM aarch64'
done

rm -f "$OUT/SHA256SUMS"
sha256sum "$OUT"/* | tee "$OUT/SHA256SUMS"

du -h   "$OUT/libsync.so"   "$OUT/rctools-gpu-probe.so"   "$OUT/rctools-opencl-probe.so"   "$OUT/rctools-gralloc-probe.so"
