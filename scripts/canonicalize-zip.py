#!/usr/bin/env python3
"""Normalize a non-ZIP64 deflate ZIP without recompressing its payloads."""
import struct
import sys
import zipfile
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
if source.resolve() == destination.resolve():
    raise SystemExit("Input and output must differ")
entries = []
with zipfile.ZipFile(source) as archive, source.open("rb") as src, destination.open("wb") as dst:
    infos = sorted(archive.infolist(), key=lambda entry: entry.filename)
    if len(infos) >= 65535 or len({info.filename for info in infos}) != len(infos):
        raise SystemExit("Duplicate entries or ZIP64 are unsupported")
    for info in infos:
        if info.is_dir() or info.compress_type not in (0, 8) or info.flag_bits & 1:
            raise SystemExit(f"Unsupported ZIP entry: {info.filename}")
        name = info.filename.encode("ascii")
        offset = dst.tell()
        if max(info.file_size, info.compress_size, offset) >= 0xFFFFFFFF:
            raise SystemExit("ZIP64 is unsupported")
        # DOS epoch 1980-01-01, no extra fields, comments, or data descriptors.
        dst.write(struct.pack("<IHHHHHIIIHH", 0x04034B50, 20, 0, info.compress_type,
                              0, 33, info.CRC, info.compress_size, info.file_size, len(name), 0))
        dst.write(name)
        src.seek(info.header_offset)
        local = src.read(30)
        if local[:4] != b"PK\x03\x04":
            raise SystemExit("Invalid local header")
        name_len, extra_len = struct.unpack_from("<HH", local, 26)
        src.seek(name_len + extra_len, 1)
        remaining = info.compress_size
        while remaining:
            chunk = src.read(min(remaining, 1024 * 1024))
            if not chunk:
                raise SystemExit("Truncated compressed payload")
            dst.write(chunk)
            remaining -= len(chunk)
        entries.append((info, name, offset))
    directory_offset = dst.tell()
    for info, name, offset in entries:
        dst.write(struct.pack("<IHHHHHHIIIHHHHHII", 0x02014B50, (3 << 8) | 20,
                              20, 0, info.compress_type, 0, 33, info.CRC,
                              info.compress_size, info.file_size, len(name), 0, 0,
                              0, 0, 0o100644 << 16, offset))
        dst.write(name)
    directory_size = dst.tell() - directory_offset
    dst.write(struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, len(entries), len(entries),
                          directory_size, directory_offset, 0))
with zipfile.ZipFile(destination) as archive:
    if archive.testzip() is not None:
        raise SystemExit("Canonical ZIP CRC verification failed")
