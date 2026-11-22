#!/usr/bin/env python3
"""Generate original D1 fixtures in a scratch directory (no DOS filesystem)."""
import argparse
from pathlib import Path
import struct

# D88 type, cylinders, sectors/track, N.
GEOMETRY = {
    'hd77': (0x20, 77, 8, 3), 'hd80': (0x20, 80, 8, 3),
    'hc': (0x20, 80, 15, 2), 'dd9': (0x10, 80, 9, 2),
    'dd8': (0x10, 80, 8, 2), 'd16': (0, 40, 16, 1),
    'hd-fm': (0x20, 80, 26, 1), 'exotic': (0x20, 80, 8, 3),
}


def make(name, target=False, protect=False):
    kind, cylinders, count, n = GEOMETRY[name]
    head = bytearray(0x2b0)
    head[:len(name)] = name.encode('ascii')
    head[0x1a:0x1c] = bytes((0x10 if protect else 0, kind))
    body = bytearray()
    for track in range(2 * cylinders):
        c, h = divmod(track, 2)
        ids = [(c, h, r, n) for r in range(1, count + 1)]
        density = 0
        if name == 'hd-fm' and track == 0 and not target:
            ids = [(c, h, r, 0) for r in range(1, 27)]
            density = 0x40
        if name == 'exotic' and not target:
            if track == 0:
                ids = [(c, h, 1 + 2*i, i % 4) for i in range(8)]
            if track == 1:
                ids = [(77, 3, 0xf1 + i, 3) for i in range(8)]
            if track == 2:
                continue
        struct.pack_into('<I', head, 0x20 + 4*track, len(head) + len(body))
        for index, (ic, ih, r, size_code) in enumerate(ids):
            size = 128 << size_code
            crc = 0xb0 if name == 'exotic' and track == 3 and index == 0 and not target else 0
            body += struct.pack('<BBBBHBBB5xH', ic, ih, r, size_code,
                                len(ids), density, 0, crc, size)
            body += bytes((i ^ (i >> 8) ^ track ^ r) & 255 for i in range(size)) if not target else bytes(size)
    struct.pack_into('<I', head, 0x1c, len(head) + len(body))
    return head + body


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('scratch', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.scratch.resolve().is_relative_to(root):
        parser.error('use scratch outside the repository')
    args.scratch.mkdir(parents=True, exist_ok=True)
    for name in GEOMETRY:
        for target in (False, True):
            suffix = '-target' if target else ''
            with (args.scratch / f'{name}{suffix}.d88').open('xb') as out:
                out.write(make(name, target))


if __name__ == '__main__':
    main()
