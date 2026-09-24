#!/usr/bin/env python3
import argparse
import gzip
import lzma
import os
import stat
import struct
import subprocess
import tempfile
from pathlib import Path

ANDROID_MAGIC = b"ANDROID!"
CPIO_MAGICS = (b"070701", b"070702")


def align(value, n):
    return (value + n - 1) // n * n


def decompress_ramdisk(data: bytes):
    if data.startswith(b"\x1f\x8b"):
        return gzip.decompress(data), "gzip"
    if data.startswith(b"\xfd7zXZ\x00"):
        return lzma.decompress(data, format=lzma.FORMAT_XZ), "xz"
    if data.startswith(b"\x04\x22\x4d\x18"):
        return external_filter(data, ["lz4", "-d", "-q", "-", "-"]), "lz4-frame"
    if data.startswith(b"\x02\x21\x4c\x18"):
        return external_filter(data, ["lz4", "-d", "-q", "-", "-"]), "lz4-legacy"
    if data.startswith(b"\x89LZO\x00\r\n\x1a\n"):
        return external_filter(data, ["lzop", "-d", "-c"]), "lzo"
    if data.startswith(CPIO_MAGICS):
        return data, "none"
    try:
        raw = lzma.decompress(data, format=lzma.FORMAT_ALONE)
        if raw.startswith(CPIO_MAGICS):
            if len(data) < 13:
                raise SystemExit("Truncated LZMA-alone recovery ramdisk header")
            props = data[0]
            if props >= 9 * 5 * 5:
                raise SystemExit(f"Invalid LZMA-alone properties byte: {props}")
            lc = props % 9
            rest = props // 9
            lp = rest % 5
            pb = rest // 5
            dict_size = struct.unpack_from("<I", data, 1)[0]
            return raw, ("lzma", dict_size, lc, lp, pb)
    except lzma.LZMAError:
        pass
    raise SystemExit("Unsupported/unknown recovery ramdisk compression")


def external_filter(data: bytes, cmd):
    p = subprocess.run(cmd, input=data, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, check=False)
    if p.returncode:
        raise SystemExit(
            f"{' '.join(cmd)} failed ({p.returncode}): "
            f"{p.stderr.decode(errors='replace')}"
        )
    return p.stdout


def compression_name(spec):
    return spec[0] if isinstance(spec, tuple) else spec


def compress_ramdisk(raw: bytes, spec):
    kind = compression_name(spec)
    if kind == "gzip":
        return gzip.compress(raw, compresslevel=9, mtime=0)
    if kind == "xz":
        return lzma.compress(raw, format=lzma.FORMAT_XZ, preset=9)
    if kind == "lzma":
        # Preserve the TeamWin ramdisk's LZMA-alone decoder parameters.
        # Python preset=9 silently changes channel's original 8 MiB dictionary
        # to 64 MiB, which can make the early kernel initramfs decompressor fail.
        if not isinstance(spec, tuple) or len(spec) != 5:
            raise SystemExit("Missing original LZMA-alone parameters")
        _, dict_size, lc, lp, pb = spec
        filters = [{
            "id": lzma.FILTER_LZMA1,
            "dict_size": dict_size,
            "lc": lc,
            "lp": lp,
            "pb": pb,
            "mode": lzma.MODE_NORMAL,
            "nice_len": 64,
            "mf": lzma.MF_BT4,
        }]
        packed = lzma.compress(raw, format=lzma.FORMAT_ALONE, filters=filters)
        expected = bytes([((pb * 5 + lp) * 9 + lc)]) + struct.pack("<I", dict_size)
        if packed[:5] != expected:
            raise SystemExit(
                f"LZMA-alone properties changed during repack: "
                f"expected={expected.hex()} got={packed[:5].hex()}"
            )
        return packed
    if kind == "lz4-frame":
        return external_filter(raw, ["lz4", "-9", "-q", "-", "-"])
    if kind == "lz4-legacy":
        return external_filter(raw, ["lz4", "-l", "-9", "-q", "-", "-"])
    if kind == "lzo":
        return external_filter(raw, ["lzop", "-9", "-c"])
    if kind == "none":
        return raw
    raise AssertionError(kind)


def parse_cpio(raw: bytes):
    pos = 0
    names = set()
    max_ino = 0
    trailer_start = None

    while pos + 110 <= len(raw):
        start = pos
        magic = raw[pos:pos + 6]
        if magic not in CPIO_MAGICS:
            # Allow zero padding only after the archive trailer.
            if all(b == 0 for b in raw[pos:]):
                break
            raise SystemExit(f"Invalid newc magic at offset {pos}: {magic!r}")
        pos += 6

        fields = []
        for _ in range(13):
            try:
                fields.append(int(raw[pos:pos + 8], 16))
            except ValueError as e:
                raise SystemExit(f"Invalid newc header at offset {start}") from e
            pos += 8

        ino, mode, uid, gid, nlink, mtime, filesize, devmaj, devmin, rdevmaj, rdevmin, namesize, check = fields
        max_ino = max(max_ino, ino)
        if namesize <= 0 or pos + namesize > len(raw):
            raise SystemExit("Invalid newc filename length")

        name_b = raw[pos:pos + namesize]
        if not name_b.endswith(b"\x00"):
            raise SystemExit("newc filename is not NUL terminated")
        name = name_b[:-1].decode("utf-8", errors="surrogateescape")
        pos = align(pos + namesize, 4)

        if pos + filesize > len(raw):
            raise SystemExit(f"Truncated newc payload for {name}")
        pos = align(pos + filesize, 4)

        if name == "TRAILER!!!":
            trailer_start = start
            return names, max_ino, trailer_start

        names.add(name)

    raise SystemExit("newc TRAILER!!! not found")


def newc_entry(name: str, data: bytes, ino: int, mode=0o100755, uid=0, gid=0):
    name_b = name.encode() + b"\x00"
    values = (
        ino,
        mode,
        uid,
        gid,
        1,   # nlink
        0,   # mtime
        len(data),
        0, 0, 0, 0,
        len(name_b),
        0,   # check
    )
    header = b"070701" + b"".join(f"{v:08x}".encode() for v in values)
    out = bytearray(header)
    out += name_b
    out += b"\x00" * (align(len(out), 4) - len(out))
    out += data
    out += b"\x00" * (align(len(out), 4) - len(out))
    return bytes(out)


def inject_payload(raw: bytes, payload: Path):
    names, max_ino, trailer_start = parse_cpio(raw)

    mapping = [
        ("wifi", "sbin/wifi", 0o755),
        ("busybox.ds", "sbin/busybox.ds", 0o755),
        ("wpa_supplicant.ds", "sbin/wpa_supplicant.ds", 0o755),
        ("wpa_cli.ds", "sbin/wpa_cli.ds", 0o755),
        ("wpa_passphrase.ds", "sbin/wpa_passphrase.ds", 0o755),
        ("wifi-udhcpc.script", "sbin/wifi-udhcpc.script", 0o755),
        ("wcnss-recovery", "sbin/wcnss-recovery", 0o755),
        ("WCNSS_qcom_cfg.ini", "lib/firmware/wlan/prima/WCNSS_qcom_cfg.ini", 0o644),
    ]

    for _, dst, _ in mapping:
        if dst in names:
            raise SystemExit(f"Refusing to overwrite existing ramdisk entry: {dst}")

    injected = bytearray()
    ino = max_ino + 1
    total = 0
    for src, dst, perms in mapping:
        path = payload / src
        if not path.is_file():
            raise SystemExit(f"Missing Wi-Fi payload: {path}")
        data = path.read_bytes()
        total += len(data)
        injected += newc_entry(dst, data, ino, mode=stat.S_IFREG | perms)
        ino += 1
        print(f"Inject: /{dst} ({len(data)} bytes, mode {perms:04o})")

    return raw[:trailer_start] + bytes(injected) + raw[trailer_start:], total


def unpack_boot(base: bytes):
    if base[:8] != ANDROID_MAGIC:
        raise SystemExit("Base image is not Android boot format")

    kernel_size = struct.unpack_from("<I", base, 8)[0]
    ramdisk_size = struct.unpack_from("<I", base, 16)[0]
    second_size = struct.unpack_from("<I", base, 24)[0]
    page_size = struct.unpack_from("<I", base, 36)[0]
    header_version = struct.unpack_from("<I", base, 40)[0]
    if header_version != 1:
        raise SystemExit(f"Expected Android boot header v1, got v{header_version}")

    recovery_dtbo_size = struct.unpack_from("<I", base, 1632)[0]
    recovery_dtbo_offset = struct.unpack_from("<Q", base, 1636)[0]
    header_size = struct.unpack_from("<I", base, 1644)[0]
    if header_size != 1648:
        raise SystemExit(f"Unexpected Android boot header size: {header_size}")
    if page_size < header_size or page_size & (page_size - 1):
        raise SystemExit(f"Unexpected boot page size: {page_size}")

    kernel_off = page_size
    ramdisk_off = align(kernel_off + kernel_size, page_size)
    second_off = align(ramdisk_off + ramdisk_size, page_size)
    recovery_off = align(second_off + second_size, page_size)

    if recovery_dtbo_size and recovery_dtbo_offset != recovery_off:
        raise SystemExit(
            f"recovery_dtbo offset mismatch: header={recovery_dtbo_offset}, calc={recovery_off}"
        )

    kernel = base[kernel_off:kernel_off + kernel_size]
    ramdisk = base[ramdisk_off:ramdisk_off + ramdisk_size]
    second = base[second_off:second_off + second_size]
    recovery_blob_offset = recovery_dtbo_offset if recovery_dtbo_size else recovery_off
    recovery_dtbo = base[recovery_blob_offset:recovery_blob_offset + recovery_dtbo_size]
    tail = base[recovery_blob_offset + recovery_dtbo_size:]

    if len(kernel) != kernel_size or len(ramdisk) != ramdisk_size:
        raise SystemExit("Truncated base image")

    for label, padding in (
        ("kernel", base[kernel_off + kernel_size:ramdisk_off]),
        ("ramdisk", base[ramdisk_off + ramdisk_size:second_off]),
        ("second", base[second_off + second_size:recovery_off]),
    ):
        if any(padding):
            raise SystemExit(f"Non-zero {label} padding in base image")

    return {
        "page_size": page_size,
        "kernel_size": kernel_size,
        "ramdisk_size": ramdisk_size,
        "second_size": second_size,
        "recovery_dtbo_size": recovery_dtbo_size,
        "header": base[:page_size],
        "kernel": kernel,
        "ramdisk": ramdisk,
        "second": second,
        "recovery_dtbo": recovery_dtbo,
        "tail": tail,
    }


def build_boot(parts, kernel: bytes, ramdisk: bytes):
    page = parts["page_size"]
    second = parts["second"]
    recovery_dtbo = parts["recovery_dtbo"]

    header = bytearray(parts["header"])
    struct.pack_into("<I", header, 8, len(kernel))
    struct.pack_into("<I", header, 16, len(ramdisk))

    ramdisk_off = align(page + len(kernel), page)
    second_off = align(ramdisk_off + len(ramdisk), page)
    recovery_off = align(second_off + len(second), page)

    if parts["recovery_dtbo_size"]:
        struct.pack_into("<Q", header, 1636, recovery_off)

    out = bytearray(header)
    out += kernel
    out += b"\x00" * (ramdisk_off - len(out))
    out += ramdisk
    out += b"\x00" * (second_off - len(out))
    out += second
    out += b"\x00" * (recovery_off - len(out))
    out += recovery_dtbo
    out += parts["tail"]
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, type=Path)
    ap.add_argument("--kernel", required=True, type=Path)
    ap.add_argument("--payload", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()

    base = args.base.read_bytes()
    new_kernel = args.kernel.read_bytes()
    parts = unpack_boot(base)

    clone = build_boot(parts, parts["kernel"], parts["ramdisk"])
    if clone != base:
        raise SystemExit("Base-image reconstruction check failed before Wi-Fi changes")

    raw, compression = decompress_ramdisk(parts["ramdisk"])
    if not raw.startswith(CPIO_MAGICS):
        raise SystemExit("Decompressed ramdisk is not a newc CPIO archive")

    modified_raw, payload_size = inject_payload(raw, args.payload)
    modified_ramdisk = compress_ramdisk(modified_raw, compression)

    # Verify our own result before touching the boot image.
    verify_raw, verify_kind = decompress_ramdisk(modified_ramdisk)
    if verify_kind != compression:
        raise SystemExit(
            f"Ramdisk compression parameters changed: "
            f"base={compression!r} repacked={verify_kind!r}"
        )
    verify_names, _, _ = parse_cpio(verify_raw)
    required = {
        "sbin/wifi", "sbin/busybox.ds", "sbin/wpa_supplicant.ds",
        "sbin/wpa_cli.ds", "sbin/wpa_passphrase.ds",
        "sbin/wifi-udhcpc.script", "sbin/wcnss-recovery",
        "lib/firmware/wlan/prima/WCNSS_qcom_cfg.ini",
    }
    missing = sorted(required - verify_names)
    if missing:
        raise SystemExit(f"Ramdisk verification missing: {missing}")

    output = build_boot(parts, new_kernel, modified_ramdisk)
    if len(output) > 33554432:
        raise SystemExit(
            f"Output is {len(output)} bytes, larger than the 32 MiB boot partition"
        )

    args.output.write_bytes(output)

    print(f"Boot page size       : {parts['page_size']}")
    print(f"Base kernel size     : {parts['kernel_size']}")
    print(f"New kernel size      : {len(new_kernel)}")
    print(f"Ramdisk compression  : {compression_name(compression)}")
    if compression_name(compression) == "lzma":
        _, dict_size, lc, lp, pb = compression
        print(f"LZMA dictionary      : {dict_size} bytes")
        print(f"LZMA lc/lp/pb        : {lc}/{lp}/{pb}")
    print(f"Base ramdisk size    : {parts['ramdisk_size']}")
    print(f"Wi-Fi payload raw    : {payload_size}")
    print(f"New ramdisk size     : {len(modified_ramdisk)}")
    print(f"Recovery DTBO size   : {parts['recovery_dtbo_size']}")
    print(f"Final image size     : {len(output)}")
    print(f"Output               : {args.output}")


if __name__ == "__main__":
    main()
