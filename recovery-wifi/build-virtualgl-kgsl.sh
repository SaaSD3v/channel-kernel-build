#!/usr/bin/env bash
set -euo pipefail

VGL_REPO="${VGL_REPO:-https://github.com/VirtualGL/virtualgl.git}"
VGL_COMMIT="${VGL_COMMIT:-2473cf39bdbe88ca41ecd58ac4007385c9682a9f}"
PREFIX="${PREFIX:-/opt/VirtualGL-KGSL}"
INSTALL="${INSTALL:-0}"
PACK_INVERT="${PACK_INVERT:-0}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${GITHUB_WORKSPACE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PATCH="$ROOT/recovery-wifi/patches/virtualgl-eglkgsl.patch"
PACK_INVERT_PATCH="$ROOT/recovery-wifi/patches/virtualgl-kgsl-pack-invert.experimental.patch"
SRC="${VGL_SRC:-/tmp/virtualgl-kgsl-src}"
BUILD="${VGL_BUILD:-/tmp/virtualgl-kgsl-build}"

for cmd in git cmake ninja g++; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd" >&2
    exit 1
  }
done

test -r "$PATCH"

rm -rf "$SRC" "$BUILD"
git init -q "$SRC"
git -C "$SRC" remote add origin "$VGL_REPO"
git -C "$SRC" fetch -q --depth=1 origin "$VGL_COMMIT"
git -C "$SRC" checkout -q --detach FETCH_HEAD

git -C "$SRC" apply --check "$PATCH"
git -C "$SRC" apply "$PATCH"

if [[ "$PACK_INVERT" == 1 ]]; then
  test -r "$PACK_INVERT_PATCH"
  git -C "$SRC" apply --check "$PACK_INVERT_PATCH"
  git -C "$SRC" apply "$PACK_INVERT_PATCH"
fi

git -C "$SRC" diff --check

TJPEG_LIB="${TJPEG_LIBRARY:-$(ldconfig -p 2>/dev/null | awk '/libturbojpeg\.so/{print $NF; exit}')}"
test -n "$TJPEG_LIB"
test -e "$TJPEG_LIB"

cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DTJPEG_INCLUDE_DIR=/usr/include \
  -DTJPEG_LIBRARY="$TJPEG_LIB" \
  -DVGL_USEXV=0 \
  -DVGL_FAKEOPENCL=0

cmake --build "$BUILD" -j"${JOBS:-2}"

if [[ "$INSTALL" == 1 ]]; then
  cmake --install "$BUILD"
fi

echo "VirtualGL KGSL build OK"
echo "source_commit=$VGL_COMMIT"
echo "build=$BUILD"
echo "prefix=$PREFIX"
echo "installed=$INSTALL"
echo "pack_invert=$PACK_INVERT"
