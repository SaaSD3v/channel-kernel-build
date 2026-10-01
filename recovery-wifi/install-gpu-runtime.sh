#!/sbin/sh
set -eu

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

BUNDLE="${1:-}"
VARIANT="${2:-}"
NAME="${3:-debian}"

[ -n "$BUNDLE" ] || die "usage: $0 <bundle-dir> <A|B|C|D> [container-name]"
[ -d "$BUNDLE" ] || die "bundle directory not found: $BUNDLE"

DS="${DS_BIN:-/data/local/Droidspaces/bin/droidspaces}"
CFG="${CFG_PATH:-/data/local/Droidspaces/Containers/$NAME/container.config}"

[ -x "$DS" ] || die "DroidSpaces binary missing: $DS"
[ -r "$CFG" ] || die "container config missing: $CFG"

ROOT="$(sed -n 's/^rootfs_path=//p' "$CFG" | head -n 1)"
[ -n "$ROOT" ] || die "rootfs_path missing from $CFG"
[ -d "$ROOT" ] || die "directory rootfs not found: $ROOT"

case "$VARIANT" in
  A|a)
    VARIANT=A
    VGL_NAME="VirtualGL-KGSL-stable-arm64.tar.gz"
    ;;
  B|b)
    VARIANT=B
    VGL_NAME="VirtualGL-KGSL-pack-invert-experimental-arm64.tar.gz"
    ;;
  C|c)
    VARIANT=C
    VGL_NAME="VirtualGL-KGSL-pack-invert-async-xshm-experimental-arm64.tar.gz"
    ;;
  D|d)
    VARIANT=D
    VGL_NAME="VirtualGL-KGSL-pack-invert-async-xshm-pbo-experimental-arm64.tar.gz"
    ;;
  *)
    die "variant must be A, B, C or D"
    ;;
esac

MESA=
for f in "$BUNDLE"/mesa_*_arm64.tar.gz; do
  [ -f "$f" ] || continue
  [ -z "$MESA" ] || die "multiple Mesa ARM64 archives found in $BUNDLE"
  MESA="$f"
done
[ -n "$MESA" ] || die "Mesa ARM64 archive not found in $BUNDLE"

VGL="$BUNDLE/$VGL_NAME"
[ -f "$VGL" ] || die "VirtualGL variant archive missing: $VGL"

sha_check_file() {
  dir="$1"
  sums="$2"

  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$dir" && sha256sum -c "$sums")
    return
  fi
  if command -v toybox >/dev/null 2>&1; then
    (cd "$dir" && toybox sha256sum -c "$sums")
    return
  fi
  if command -v busybox >/dev/null 2>&1; then
    (cd "$dir" && busybox sha256sum -c "$sums")
    return
  fi

  die "SHA256SUMS exists but no sha256sum implementation is available"
}

if [ -r "$BUNDLE/SHA256SUMS" ]; then
  say "[*] Verifying bundle SHA256SUMS"
  sha_check_file "$BUNDLE" SHA256SUMS || die "bundle checksum validation failed"
else
  say "[!] SHA256SUMS not present; refusing unverified runtime bundle"
  die "copy SHA256SUMS from the CI bundle into $BUNDLE"
fi

STAGE="$ROOT/.rctools-gpu-install.$$"
OLD_MESA="$ROOT/opt/rctools-gpu/.mesa.old.$$"
OLD_VGL="$ROOT/opt/.VirtualGL-KGSL.old.$$"
TARGET_MESA="$ROOT/opt/rctools-gpu/mesa"
TARGET_VGL="$ROOT/opt/VirtualGL-KGSL"

cleanup_stage() {
  rm -rf "$STAGE" 2>/dev/null || true
}
trap cleanup_stage EXIT HUP INT TERM

mkdir -p "$STAGE/mesa" "$STAGE/vgl"

say "[*] Extracting Mesa into staging"
tar -xzf "$MESA" -C "$STAGE/mesa"
[ -r "$STAGE/mesa/usr/lib/aarch64-linux-gnu/dri/kgsl_dri.so" ] ||
  [ -r "$STAGE/mesa/usr/lib/dri/kgsl_dri.so" ] ||
  die "staged Mesa does not contain kgsl_dri.so"

say "[*] Extracting VirtualGL variant $VARIANT into staging"
tar -xzf "$VGL" -C "$STAGE/vgl"
NEW_VGL="$STAGE/vgl/opt/VirtualGL-KGSL"
[ -x "$NEW_VGL/bin/vglrun" ] || die "staged VirtualGL has no vglrun"
[ -r "$NEW_VGL/lib/libvglfaker.so" ] || die "staged VirtualGL has no libvglfaker.so"
[ -r "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" ] ||
  die "staged VirtualGL buildinfo missing"

case "$VARIANT" in
  A)
    grep -qx 'pack_invert=0' "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" &&
    grep -qx 'async_xshm=0' "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" &&
    grep -qx 'pbo_pipeline=0' "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" ||
      die "variant A buildinfo mismatch"
    ;;
  B)
    grep -qx 'pack_invert=1' "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" &&
    grep -qx 'async_xshm=0' "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" &&
    grep -qx 'pbo_pipeline=0' "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" ||
      die "variant B buildinfo mismatch"
    ;;
  C)
    grep -qx 'pack_invert=1' "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" &&
    grep -qx 'async_xshm=1' "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" &&
    grep -qx 'pbo_pipeline=0' "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" ||
      die "variant C buildinfo mismatch"
    ;;
  D)
    grep -qx 'pack_invert=1' "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" &&
    grep -qx 'async_xshm=1' "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" &&
    grep -qx 'pbo_pipeline=1' "$NEW_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo" ||
      die "variant D buildinfo mismatch"
    ;;
esac

say "[*] Stopping container $NAME"
"$DS" --name="$NAME" stop >/dev/null 2>&1 || true

mkdir -p "$ROOT/opt/rctools-gpu" "$ROOT/opt"
rm -rf "$OLD_MESA" "$OLD_VGL"

had_mesa=0
had_vgl=0

rollback() {
  rm -rf "$TARGET_MESA" "$TARGET_VGL" 2>/dev/null || true
  if [ "$had_mesa" -eq 1 ] && [ -e "$OLD_MESA" ]; then
    mv "$OLD_MESA" "$TARGET_MESA" 2>/dev/null || true
  fi
  if [ "$had_vgl" -eq 1 ] && [ -e "$OLD_VGL" ]; then
    mv "$OLD_VGL" "$TARGET_VGL" 2>/dev/null || true
  fi
}

if [ -e "$TARGET_MESA" ]; then
  if ! mv "$TARGET_MESA" "$OLD_MESA"; then
    die "could not back up existing Mesa runtime"
  fi
  had_mesa=1
fi

if [ -e "$TARGET_VGL" ]; then
  if ! mv "$TARGET_VGL" "$OLD_VGL"; then
    rollback
    die "could not back up existing VirtualGL runtime"
  fi
  had_vgl=1
fi

if ! mv "$STAGE/mesa" "$TARGET_MESA"; then
  rollback
  die "could not install Mesa runtime"
fi

if ! mv "$NEW_VGL" "$TARGET_VGL"; then
  rollback
  die "could not install VirtualGL runtime"
fi

rm -rf "$OLD_MESA" "$OLD_VGL"
rm -rf "$STAGE"
trap - EXIT HUP INT TERM

say
say "PASS GPU_RUNTIME_INSTALLED"
say "container=$NAME"
say "rootfs=$ROOT"
say "variant=$VARIANT"
say "mesa=$TARGET_MESA"
say "virtualgl=$TARGET_VGL"
say
say "--- VirtualGL buildinfo ---"
cat "$TARGET_VGL/share/rctools-gpu/virtualgl-kgsl.buildinfo"
say
say "Next:"
say "  1. Open the unchanged RCTools GPU menu."
say "  2. Select Freedreno / KGSL again so the managed .env is regenerated."
say "  3. Run Tools -> Status, then Tools -> Test."
say "  4. Start DroidSpaces with explicit --conf and --env in recovery."
