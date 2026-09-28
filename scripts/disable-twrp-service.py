#!/usr/bin/env python3
import argparse
import gzip
import io
import lzma
import struct
from pathlib import Path

CPIO_MAGIC = (b"070701", b"070702")


def align4(v):
    return (v + 3) & ~3


def align(v, n):
    return (v + n - 1) // n * n


def parse_boot(data: bytes):
    if data[:8] != b"ANDROID!":
        raise SystemExit("not an Android boot image")

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
            f"expected Android boot header v1/1648, got v{header_version}/{header_size}"
        )

    ko = page_size
    ro = align(ko + kernel_size, page_size)
    so = align(ro + ramdisk_size, page_size)
    expected_dtbo = align(so + second_size, page_size)
    do = recovery_dtbo_offset if recovery_dtbo_size else expected_dtbo

    if recovery_dtbo_size and do != expected_dtbo:
        raise SystemExit(
            f"unexpected recovery_dtbo offset: {do} != {expected_dtbo}"
        )

    tail_off = do + recovery_dtbo_size
    return {
        "kernel_size": kernel_size,
        "ramdisk_size": ramdisk_size,
        "second_size": second_size,
        "page_size": page_size,
        "dtbo_size": recovery_dtbo_size,
        "kernel": data[ko:ko + kernel_size],
        "ramdisk": data[ro:ro + ramdisk_size],
        "second": data[so:so + second_size],
        "dtbo": data[do:do + recovery_dtbo_size],
        "tail": data[tail_off:],
        "header": data[:page_size],
    }


def lzma_params(header: bytes):
    if len(header) < 5:
        raise ValueError("LZMA header too small")
    prop = header[0]
    if prop >= 9 * 5 * 5:
        raise ValueError(f"invalid LZMA property byte: {prop}")
    lc = prop % 9
    rem = prop // 9
    lp = rem % 5
    pb = rem // 5
    dict_size = int.from_bytes(header[1:5], "little")
    return lc, lp, pb, dict_size


def decompress_ramdisk(blob: bytes):
    if blob.startswith(CPIO_MAGIC):
        return blob, ("raw", None)
    if blob.startswith(b"\x1f\x8b"):
        return gzip.decompress(blob), ("gzip", None)
    if blob.startswith(b"\xfd7zXZ\x00"):
        return lzma.decompress(blob, format=lzma.FORMAT_XZ), ("xz", None)

    # Channel TWRP 3.5.2 uses LZMA-Alone.
    try:
        raw = lzma.decompress(blob, format=lzma.FORMAT_ALONE)
        return raw, ("lzma", lzma_params(blob[:5]))
    except Exception as exc:
        raise SystemExit(f"unsupported external ramdisk compression: {exc}")


def recompress_ramdisk(raw: bytes, fmt):
    kind, params = fmt
    if kind == "raw":
        return raw
    if kind == "gzip":
        return gzip.compress(raw, compresslevel=9, mtime=0)
    if kind == "xz":
        return lzma.compress(raw, format=lzma.FORMAT_XZ, preset=9)
    if kind == "lzma":
        lc, lp, pb, dict_size = params
        filters = [{
            "id": lzma.FILTER_LZMA1,
            "dict_size": dict_size,
            "lc": lc,
            "lp": lp,
            "pb": pb,
            "mode": lzma.MODE_NORMAL,
            "nice_len": 273,
            "mf": lzma.MF_BT4,
        }]
        return lzma.compress(raw, format=lzma.FORMAT_ALONE, filters=filters)
    raise AssertionError(kind)


def parse_newc(raw: bytes):
    pos = 0
    entries = []
    while True:
        if raw[pos:pos + 6] not in CPIO_MAGIC:
            raise SystemExit(f"invalid newc magic at offset {pos}")
        h = raw[pos:pos + 110]
        if len(h) != 110:
            raise SystemExit("truncated newc header")
        fields = [int(h[i:i + 8], 16) for i in range(6, 110, 8)]
        (
            ino, mode, uid, gid, nlink, mtime, filesize,
            devmajor, devminor, rdevmajor, rdevminor, namesize, check
        ) = fields
        pos += 110

        name_bytes = raw[pos:pos + namesize]
        if len(name_bytes) != namesize or not name_bytes.endswith(b"\0"):
            raise SystemExit("invalid newc filename")
        name = name_bytes[:-1].decode("utf-8", "surrogateescape")
        pos = align4(pos + namesize)

        data = raw[pos:pos + filesize]
        if len(data) != filesize:
            raise SystemExit(f"truncated newc payload for {name}")
        pos = align4(pos + filesize)

        entry = {
            "magic": h[:6].decode(),
            "ino": ino,
            "mode": mode,
            "uid": uid,
            "gid": gid,
            "nlink": nlink,
            "mtime": mtime,
            "devmajor": devmajor,
            "devminor": devminor,
            "rdevmajor": rdevmajor,
            "rdevminor": rdevminor,
            "check": check,
            "name": name,
            "data": data,
        }
        entries.append(entry)
        if name == "TRAILER!!!":
            break
    return entries


def emit_newc(entries):
    out = bytearray()
    for e in entries:
        name_b = e["name"].encode("utf-8", "surrogateescape") + b"\0"
        data = e["data"]
        nums = [
            e["ino"], e["mode"], e["uid"], e["gid"], e["nlink"], e["mtime"],
            len(data), e["devmajor"], e["devminor"], e["rdevmajor"],
            e["rdevminor"], len(name_b), e["check"],
        ]
        out += e["magic"].encode()
        out += b"".join(f"{n:08x}".encode() for n in nums)
        out += name_b
        out += bytes(align4(len(out)) - len(out))
        out += data
        out += bytes(align4(len(out)) - len(out))
    return bytes(out)


def strip_recovery_service(text: str):
    lines = text.splitlines(True)
    out = []
    removed = False
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("service recovery /system/bin/recovery"):
            removed = True
            i += 1
            while i < len(lines):
                nxt = lines[i]
                if nxt.startswith((" ", "\t")) or nxt.strip() == "":
                    i += 1
                    continue
                break
            out.append("# RCTools minimal: TWRP recovery service removed\n")
            out.append("# /system/bin/recovery is kept only for manual compatibility.\n")
            out.append("\n")
            continue
        out.append(line)
        i += 1
    if not removed:
        raise SystemExit("service recovery /system/bin/recovery stanza not found")
    return "".join(out)


def patch_cpio(raw: bytes):
    entries = parse_newc(raw)
    target = None
    for e in entries:
        if e["name"] in ("init.recovery.service.rc", "/init.recovery.service.rc"):
            target = e
            break
    if target is None:
        raise SystemExit("init.recovery.service.rc not found in external ramdisk")

    text = target["data"].decode("utf-8", "strict")
    if "service recovery /system/bin/recovery" not in text:
        raise SystemExit("TWRP recovery service stanza already absent/unexpected")
    target["data"] = strip_recovery_service(text).encode()

    # Add a tiny marker so final-image validation can prove this specific patch.
    trailer_index = next(i for i, e in enumerate(entries) if e["name"] == "TRAILER!!!")
    marker = {
        "magic": "070701",
        "ino": max((e["ino"] for e in entries), default=0) + 1,
        "mode": 0o100444,
        "uid": 0,
        "gid": 0,
        "nlink": 1,
        "mtime": 0,
        "devmajor": 0,
        "devminor": 0,
        "rdevmajor": 0,
        "rdevminor": 0,
        "check": 0,
        "name": "rctools.twrp-service-disabled",
        "data": b"RCTools minimal: TWRP recovery service disabled\n",
    }
    entries.insert(trailer_index, marker)
    return emit_newc(entries)


def rebuild_boot(original: bytes, parts, new_ramdisk: bytes):
    page = parts["page_size"]
    header = bytearray(parts["header"])
    struct.pack_into("<I", header, 16, len(new_ramdisk))

    ko = page
    ro = align(ko + len(parts["kernel"]), page)
    so = align(ro + len(new_ramdisk), page)
    do = align(so + len(parts["second"]), page)

    if parts["dtbo_size"]:
        struct.pack_into("<Q", header, 1636, do)

    out = bytearray(header)
    out += parts["kernel"]
    out += bytes(ro - len(out))
    out += new_ramdisk
    out += bytes(so - len(out))
    out += parts["second"]
    out += bytes(do - len(out))
    out += parts["dtbo"]
    out += parts["tail"]
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")
    args = ap.parse_args()

    src = Path(args.input).read_bytes()
    parts = parse_boot(src)
    raw, fmt = decompress_ramdisk(parts["ramdisk"])
    patched_raw = patch_cpio(raw)
    patched_blob = recompress_ramdisk(patched_raw, fmt)
    out = rebuild_boot(src, parts, patched_blob)

    if len(out) > 32 * 1024 * 1024:
        raise SystemExit(
            f"patched image exceeds 32 MiB: {len(out)} bytes"
        )

    # Re-parse final boot and prove kernel/second/DTBO/tail are untouched.
    final = parse_boot(out)
    for key in ("kernel", "second", "dtbo", "tail"):
        if final[key] != parts[key]:
            raise SystemExit(f"{key} changed while disabling TWRP service")

    final_raw, _ = decompress_ramdisk(final["ramdisk"])
    if b"service recovery /system/bin/recovery" in final_raw:
        raise SystemExit("TWRP recovery service stanza survived final ramdisk")
    if b"rctools.twrp-service-disabled" not in final_raw:
        raise SystemExit("RCTools TWRP-service-disabled marker missing")

    Path(args.output).write_bytes(out)
    print(f"External ramdisk before: {len(parts['ramdisk'])} bytes")
    print(f"External ramdisk after : {len(final['ramdisk'])} bytes")
    print(f"Final image            : {len(out)} bytes")
    print(f"32 MiB headroom        : {32 * 1024 * 1024 - len(out)} bytes")
    print("TWRP recovery service  : removed")
    print("Recovery binary        : retained")
    print("Kernel/second/DTBO/tail: unchanged")


if __name__ == "__main__":
    main()
