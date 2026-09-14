#!/usr/bin/env python3
"""Pad an odd Mach-O indirect-symbol table so LINKEDIT strings stay aligned."""

from __future__ import annotations

import struct
import sys
from pathlib import Path


MH_MAGIC_64 = 0xFEEDFACF
LC_SYMTAB = 0x2
LC_SEGMENT_64 = 0x19


def load_commands(data: bytes) -> list[tuple[int, int]]:
    if struct.unpack_from("<I", data, 0)[0] != MH_MAGIC_64:
        raise ValueError("not a little-endian Mach-O 64 file")
    count = struct.unpack_from("<I", data, 16)[0]
    commands: list[tuple[int, int]] = []
    offset = 32
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, offset)
        commands.append((offset, command))
        offset += size
    return commands


def fix(path: Path) -> bool:
    data = bytearray(path.read_bytes())
    symtab_offset = None
    linkedit_offset = None
    for offset, command in load_commands(data):
        if command == LC_SYMTAB:
            symtab_offset = offset
        elif (
            command == LC_SEGMENT_64
            and data[offset + 8 : offset + 24].rstrip(b"\0") == b"__LINKEDIT"
        ):
            linkedit_offset = offset

    if symtab_offset is None or linkedit_offset is None:
        raise ValueError("LC_SYMTAB or __LINKEDIT segment is missing")

    string_offset, string_size = struct.unpack_from(
        "<II", data, symtab_offset + 16
    )
    if string_offset % 8 == 0:
        return False
    if string_offset % 8 != 4:
        raise ValueError(
            f"unsupported string table alignment: {string_offset}"
        )
    if string_offset + string_size != len(data):
        raise ValueError("string table is not the final Mach-O payload")

    data[string_offset:string_offset] = b"\0\0\0\0"
    struct.pack_into("<I", data, symtab_offset + 16, string_offset + 4)
    linkedit_size = struct.unpack_from("<Q", data, linkedit_offset + 48)[0]
    struct.pack_into("<Q", data, linkedit_offset + 48, linkedit_size + 4)
    path.write_bytes(data)
    return True


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <mach-o>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    changed = fix(path)
    print("patched" if changed else "already aligned")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
