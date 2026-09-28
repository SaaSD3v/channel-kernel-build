#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <minimal.img> <official-installer.zip> <recovery-console-bin> <magiskboot> <integrator.sh> <output.img>" >&2
  exit 2
}

[ "$#" -eq 6 ] || usage

BASE_IMG="$(readlink -f "$1")"
INSTALLER="$(readlink -f "$2")"
CONSOLE_BIN="$(readlink -f "$3")"
MAGISKBOOT="$(readlink -f "$4")"
INTEGRATOR="$(readlink -f "$5")"
OUTPUT_IMG="$(readlink -m "$6")"

[ -s "$BASE_IMG" ] || { echo "ERROR: minimal base image missing" >&2; exit 1; }
[ -s "$INSTALLER" ] || { echo "ERROR: official installer missing" >&2; exit 1; }
[ -x "$CONSOLE_BIN" ] || { echo "ERROR: Recovery Console binary missing/not executable" >&2; exit 1; }
[ -x "$MAGISKBOOT" ] || { echo "ERROR: magiskboot missing/not executable" >&2; exit 1; }
[ -x "$INTEGRATOR" ] || { echo "ERROR: console integrator missing/not executable" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$(dirname "$OUTPUT_IMG")"

to_raw_cpio() {
  input="$1"
  output="$2"

  if cpio -it < "$input" >/dev/null 2>&1; then
    cp -f "$input" "$output"
  else
    "$MAGISKBOOT" decompress "$input" "$output"
  fi

  [ -s "$output" ] || {
    echo "ERROR: failed to obtain raw ramdisk CPIO from $input" >&2
    return 1
  }
  cpio -it < "$output" >/dev/null 2>&1 || {
    echo "ERROR: decoded ramdisk is not a valid CPIO: $input" >&2
    return 1
  }
}

echo "==> Verifying official installer ramdisk against minimal base"
INSTALLER_RAMDISK_NAME="$(
  unzip -Z1 "$INSTALLER" |
    grep -E '^ramdisk-(twrp|recovery)\.cpio$' |
    head -n1
)"
[ -n "$INSTALLER_RAMDISK_NAME" ] || {
  echo "ERROR: official installer ramdisk missing" >&2
  exit 1
}
unzip -p "$INSTALLER" "$INSTALLER_RAMDISK_NAME" > "$WORK/installer-ramdisk.bin"
[ -s "$WORK/installer-ramdisk.bin" ] || {
  echo "ERROR: official installer ramdisk is empty" >&2
  exit 1
}

python3 - "$BASE_IMG" "$WORK/base-ramdisk.bin" <<'PY'
from pathlib import Path
import struct
import sys

src = Path(sys.argv[1]).read_bytes()
dst = Path(sys.argv[2])

if src[:8] != b"ANDROID!":
    raise SystemExit("ERROR: minimal base is not an Android boot image")

kernel_size = struct.unpack_from("<I", src, 8)[0]
ramdisk_size = struct.unpack_from("<I", src, 16)[0]
page_size = struct.unpack_from("<I", src, 36)[0]

if page_size <= 0:
    raise SystemExit(f"ERROR: invalid boot page size: {page_size}")

align = lambda v: (v + page_size - 1) // page_size * page_size
ramdisk_offset = align(page_size + kernel_size)
ramdisk = src[ramdisk_offset:ramdisk_offset + ramdisk_size]

if len(ramdisk) != ramdisk_size:
    raise SystemExit("ERROR: incomplete base external ramdisk")

dst.write_bytes(ramdisk)
print(f"Base external ramdisk: {len(ramdisk)} bytes")
PY

to_raw_cpio "$WORK/base-ramdisk.bin" "$WORK/base-ramdisk.raw"
to_raw_cpio "$WORK/installer-ramdisk.bin" "$WORK/installer-ramdisk.raw"

cmp -s "$WORK/base-ramdisk.raw" "$WORK/installer-ramdisk.raw" || {
  echo "ERROR: official installer ramdisk does not match minimal base TWRP ramdisk" >&2
  exit 1
}
echo "Verified installer/base external TWRP ramdisk content: identical"

echo "==> Integrating permanent headless Recovery Console"
INTEGRATED_ZIP="$WORK/channel-console.zip"
"$INTEGRATOR"   "$MAGISKBOOT"   "$INSTALLER"   "$CONSOLE_BIN"   "$INTEGRATED_ZIP"   'u:r:recovery:s0'

[ -s "$INTEGRATED_ZIP" ] || {
  echo "ERROR: Recovery Console integrator produced no ZIP" >&2
  exit 1
}
unzip -t "$INTEGRATED_ZIP" >/dev/null

RAMDISK_NAME="$(
  unzip -Z1 "$INTEGRATED_ZIP" |
    grep -E '^ramdisk-(twrp|recovery)\.cpio$' |
    head -n1
)"
[ -n "$RAMDISK_NAME" ] || {
  echo "ERROR: integrated installer ramdisk missing" >&2
  exit 1
}

unzip -p "$INTEGRATED_ZIP" "$RAMDISK_NAME" > "$WORK/final-ramdisk.bin"
[ -s "$WORK/final-ramdisk.bin" ] || {
  echo "ERROR: integrated ramdisk is empty" >&2
  exit 1
}

MAGIC="$(xxd -p -l 8 "$WORK/final-ramdisk.bin" | tr -d '\n')"
case "$MAGIC" in
  5d00008000*) ;;
  *)
    echo "ERROR: expected Channel LZMA-Alone props 5d00008000, magic=$MAGIC" >&2
    exit 1
    ;;
esac

# Channel's real TWRP 3.5.2 external ramdisk is a standard LZMA-Alone stream.
xz --format=lzma -t "$WORK/final-ramdisk.bin"

"$MAGISKBOOT" decompress "$WORK/final-ramdisk.bin" "$WORK/final-ramdisk.raw"
"$MAGISKBOOT" cpio "$WORK/final-ramdisk.raw" "exists system/bin/recovery-console" >/dev/null
"$MAGISKBOOT" cpio "$WORK/final-ramdisk.raw" "exists init.rc" >/dev/null
"$MAGISKBOOT" cpio "$WORK/final-ramdisk.raw" "exists init.recovery.service.rc" >/dev/null

echo "==> Replacing only the external TWRP ramdisk"
python3 - "$BASE_IMG" "$WORK/final-ramdisk.bin" "$OUTPUT_IMG" <<'PY'
from pathlib import Path
import struct
import sys

LIMIT = 32 * 1024 * 1024
base_path = Path(sys.argv[1])
ramdisk_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])

def align(v, n):
    return (v + n - 1) // n * n

def split(data):
    if data[:8] != b"ANDROID!":
        raise SystemExit("ERROR: not an Android boot image")

    kernel_size = struct.unpack_from("<I", data, 8)[0]
    ramdisk_size = struct.unpack_from("<I", data, 16)[0]
    second_size = struct.unpack_from("<I", data, 24)[0]
    page_size = struct.unpack_from("<I", data, 36)[0]
    header_version = struct.unpack_from("<I", data, 40)[0]
    recovery_dtbo_size = struct.unpack_from("<I", data, 1632)[0]
    recovery_dtbo_offset = struct.unpack_from("<Q", data, 1636)[0]
    header_size = struct.unpack_from("<I", data, 1644)[0]

    if header_version != 1 or header_size != 1648:
        raise SystemExit(
            f"ERROR: expected boot header v1/1648, got v{header_version}/{header_size}"
        )
    if page_size <= 0:
        raise SystemExit(f"ERROR: invalid boot page size: {page_size}")

    kernel_offset = page_size
    ramdisk_offset = align(kernel_offset + kernel_size, page_size)
    second_offset = align(ramdisk_offset + ramdisk_size, page_size)
    calculated_dtbo_offset = align(second_offset + second_size, page_size)

    if recovery_dtbo_size:
        if recovery_dtbo_offset != calculated_dtbo_offset:
            raise SystemExit(
                "ERROR: unexpected recovery_dtbo offset "
                f"{recovery_dtbo_offset} != {calculated_dtbo_offset}"
            )
        dtbo_offset = recovery_dtbo_offset
    else:
        dtbo_offset = calculated_dtbo_offset

    tail_offset = dtbo_offset + recovery_dtbo_size

    parts = {
        "header": data[:page_size],
        "kernel": data[kernel_offset:kernel_offset + kernel_size],
        "ramdisk": data[ramdisk_offset:ramdisk_offset + ramdisk_size],
        "second": data[second_offset:second_offset + second_size],
        "dtbo": data[dtbo_offset:dtbo_offset + recovery_dtbo_size],
        "tail": data[tail_offset:],
        "page": page_size,
        "dtbo_size": recovery_dtbo_size,
    }

    if len(parts["kernel"]) != kernel_size:
        raise SystemExit("ERROR: incomplete kernel in boot image")
    if len(parts["ramdisk"]) != ramdisk_size:
        raise SystemExit("ERROR: incomplete ramdisk in boot image")
    if len(parts["second"]) != second_size:
        raise SystemExit("ERROR: incomplete second stage in boot image")
    if len(parts["dtbo"]) != recovery_dtbo_size:
        raise SystemExit("ERROR: incomplete recovery DTBO in boot image")

    return parts

base = base_path.read_bytes()
new_ramdisk = ramdisk_path.read_bytes()
old = split(base)
page = old["page"]

header = bytearray(old["header"])
struct.pack_into("<I", header, 16, len(new_ramdisk))

kernel_offset = page
ramdisk_offset = align(kernel_offset + len(old["kernel"]), page)
second_offset = align(ramdisk_offset + len(new_ramdisk), page)
dtbo_offset = align(second_offset + len(old["second"]), page)

if old["dtbo_size"]:
    struct.pack_into("<Q", header, 1636, dtbo_offset)

output = bytearray(header)
output += old["kernel"]
output += bytes(ramdisk_offset - len(output))
output += new_ramdisk
output += bytes(second_offset - len(output))
output += old["second"]
output += bytes(dtbo_offset - len(output))
output += old["dtbo"]
output += old["tail"]

if len(output) > LIMIT:
    raise SystemExit(
        f"ERROR: final image {len(output)} bytes exceeds 32 MiB by "
        f"{len(output) - LIMIT} bytes"
    )

out_path.write_bytes(output)
new = split(bytes(output))

if new["kernel"] != old["kernel"]:
    raise SystemExit("ERROR: kernel changed during Recovery Console integration")
if new["second"] != old["second"]:
    raise SystemExit("ERROR: second stage changed during Recovery Console integration")
if new["dtbo"] != old["dtbo"]:
    raise SystemExit("ERROR: recovery DTBO changed during Recovery Console integration")
if new["tail"] != old["tail"]:
    raise SystemExit("ERROR: post-DTBO tail changed during Recovery Console integration")
if new["ramdisk"] != new_ramdisk:
    raise SystemExit("ERROR: final ramdisk does not match integrated ramdisk")

before = bytearray(old["header"])
after = bytearray(new["header"])
for off, size in ((16, 4), (1636, 8)):
    before[off:off + size] = bytes(size)
    after[off:off + size] = bytes(size)
if before != after:
    raise SystemExit("ERROR: unexpected static boot header change")

print(f"Minimal base image : {len(base)} bytes")
print(f"Old ramdisk        : {len(old['ramdisk'])} bytes")
print(f"Console ramdisk    : {len(new_ramdisk)} bytes")
print(f"Final image        : {len(output)} bytes")
print(f"32 MiB headroom    : {LIMIT - len(output)} bytes")
print("Kernel unchanged   : YES")
print("Second stage       : unchanged")
print("Recovery DTBO      : unchanged")
print("Post-DTBO tail     : unchanged")
PY

cp "$WORK/final-ramdisk.bin" "$OUTPUT_IMG.ramdisk.bin"
sha256sum "$OUTPUT_IMG" > "$OUTPUT_IMG.sha256"
sha256sum "$OUTPUT_IMG.ramdisk.bin" > "$OUTPUT_IMG.ramdisk.bin.sha256"

echo "Built Channel CLI-minimal + headless Recovery Console:"
echo "  image   : $OUTPUT_IMG"
echo "  ramdisk : $OUTPUT_IMG.ramdisk.bin"
cat "$OUTPUT_IMG.sha256"
