#!/usr/bin/env bash
set -euo pipefail

MESA_REPO="${MESA_REPO:-https://github.com/lfdevs/mesa-for-android-container.git}"
MESA_COMMIT="${MESA_COMMIT:-98f3d6229d61452cef80f8563af7c56ae599dc14}"
JOBS="${JOBS:-2}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${GITHUB_WORKSPACE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PATCH="$ROOT/recovery-wifi/patches/mesa-kgsl-channel-compat.patch"
SRC="${MESA_SRC:-/tmp/mesa-kgsl-channel-src}"
BUILD="${MESA_BUILD:-/tmp/mesa-kgsl-channel-build}"
STAGE="${MESA_STAGE:-/tmp/mesa-kgsl-channel-stage}"
OUT="${MESA_OUT:-$ROOT/recovery-wifi/out/mesa-kgsl-channel}"

for cmd in git meson ninja tar sha256sum; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd" >&2
    exit 1
  }
done

test -r "$PATCH"
PATCH_SHA256="$(sha256sum "$PATCH" | awk '{print $1}')"
PROJECT_COMMIT="${GITHUB_SHA:-}"
if [[ -z "$PROJECT_COMMIT" ]] && git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
  PROJECT_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
fi
[[ -n "$PROJECT_COMMIT" ]] || PROJECT_COMMIT=unknown

rm -rf "$SRC" "$BUILD" "$STAGE"
mkdir -p "$OUT"

git init -q "$SRC"
git -C "$SRC" remote add origin "$MESA_REPO"
git -C "$SRC" fetch -q --depth=1 origin "$MESA_COMMIT"
git -C "$SRC" checkout -q --detach FETCH_HEAD

git -C "$SRC" apply --check "$PATCH"
git -C "$SRC" apply "$PATCH"
git -C "$SRC" diff --check

version="$(grep -v '^[[:space:]]*$' "$SRC/VERSION" | head -n1)"
arch="$(uname -m)"
case "$arch" in
  aarch64|arm64) arch_tag=arm64 ;;
  x86_64|amd64) arch_tag=x86_64 ;;
  *) arch_tag="$arch" ;;
esac

meson setup "$BUILD" "$SRC" \
  --prefix=/usr \
  -Dplatforms=x11,wayland \
  -Dgallium-drivers=freedreno,zink,virgl,llvmpipe \
  -Dgallium-va=disabled \
  -Dgallium-mediafoundation=disabled \
  -Dvulkan-drivers=freedreno \
  -Dvulkan-layers= \
  -Degl=enabled \
  -Dgles2=enabled \
  -Dglvnd=enabled \
  -Dglx=dri \
  -Dlibunwind=disabled \
  -Dintel-rt=disabled \
  -Dmicrosoft-clc=disabled \
  -Dvalgrind=disabled \
  -Dgles1=disabled \
  -Dfreedreno-kmds=kgsl \
  -Dbuildtype=release

ninja -C "$BUILD" -j"$JOBS"

DESTDIR="$STAGE" meson install -C "$BUILD"

buildinfo_dir="$STAGE/usr/share/rctools-gpu"
mkdir -p "$buildinfo_dir"
cat >"$buildinfo_dir/mesa-channel-kgsl.buildinfo" <<EOF
runtime=mesa-channel-kgsl
mesa_source_commit=$MESA_COMMIT
project_commit=$PROJECT_COMMIT
compat_patch_sha256=$PATCH_SHA256
architecture=$arch_tag
prefix=/usr
platforms=x11,wayland
gallium_drivers=freedreno,zink,virgl,llvmpipe
vulkan_drivers=freedreno
freedreno_kmds=kgsl
egl=enabled
gles2=enabled
glvnd=enabled
glx=dri
buildtype=release
EOF

name="mesa_${version}-channel-kgsl_${arch_tag}.tar.gz"
tar -zcf "$OUT/$name" -C "$STAGE" .
sha256sum "$OUT/$name" > "$OUT/$name.sha256"
cp "$buildinfo_dir/mesa-channel-kgsl.buildinfo" "$OUT/$name.buildinfo"

echo "Mesa Channel KGSL build OK"
echo "source_commit=$MESA_COMMIT"
echo "project_commit=$PROJECT_COMMIT"
echo "patch_sha256=$PATCH_SHA256"
echo "arch=$arch"
echo "artifact=$OUT/$name"
cat "$OUT/$name.sha256"
