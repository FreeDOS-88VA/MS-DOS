#!/usr/bin/env python3
"""Generate original blank, NEC-layout or BPB-based SASI test HDIs."""
import argparse
from pathlib import Path
import struct

# The 20 MB entry is the geometry vaeg maps to VA BIOS type 2.
GEOMETRY = {5: (153, 4), 10: (310, 4), 20: (615, 4), 40: (615, 8)}
LEGACY = {5: (4950, 608, 8, 1, 0xd0), 10: (9900, 992, 8, 2, 0xd1),
          20: (19800, 1504, 8, 4, 0xd2), 40: (39593, 3072, 16, 4, 0xd3)}
HEADER = 4096
BLOCK = 256
TRACK = 33


def fat_volume(image, start, count, bits):
    """Create an empty 512-byte-sector FAT filesystem in count physical blocks."""
    sectors = count // 2
    spc = 1
    # Target at most ~4000 clusters for FAT12 and ~32K for FAT16.
    while sectors // spc > (4000 if bits == 12 else 32760):
        spc *= 2
    root = 512
    spf = ((sectors // spc + 2) * bits + 4095) // 4096
    clusters = (sectors - 1 - 2 * spf - root // 16) // spc
    if not (0 < clusters < 4085 if bits == 12 else 4085 <= clusters < 65525):
        raise ValueError(f'{sectors} sectors do not make a FAT{bits} fixture')
    vbr = bytearray(512)
    vbr[:11] = b'\xeb\x3c\x90VA-D2   '
    struct.pack_into('<HBHBHHBHHHII', vbr, 11, 512, spc, 1, 2, root,
                     sectors if sectors < 65536 else 0, 0xf8, spf, 1, 1, 0,
                     sectors if sectors >= 65536 else 0)
    struct.pack_into('<BBB I 11s 8s', vbr, 36, 0x80, 0, 0x29, 0xd2000000 + start,
                     b'NO NAME    ', f'FAT{bits}   '.encode())
    vbr[62:66] = b'\xfa\xf4\xeb\xfd'  # Non-bootable fixture.
    vbr[510:] = b'\x55\xaa'
    offset = HEADER + start * BLOCK
    image.seek(offset)
    image.write(vbr)
    for copy in range(2):
        image.seek(offset + (1 + copy * spf) * 512)
        image.write(b'\xf8\xff\xff' + (b'\xff' if bits == 16 else b''))


def make(path, size, layout='blank', bits=16):
    cylinders, heads = GEOMETRY[size]
    blocks = cylinders * heads * TRACK
    payload = blocks * BLOCK
    with Path(path).open('xb') as image:
        image.write(struct.pack('<8I', 0, 0, HEADER, payload, BLOCK,
                                TRACK, heads, cylinders))
        image.truncate(HEADER + payload)
        if layout == 'nec':
            _, _, _, spf, media = LEGACY[size]
            for copy in range(2):
                image.seek(HEADER + (1 + copy * spf) * 1024)
                image.write(bytes((media, 255, 255)))
        elif layout == 'native':
            fat_volume(image, 4, blocks - 4, bits)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('size', type=int, choices=GEOMETRY)
    parser.add_argument('--layout', choices=('blank', 'nec', 'native'), default='blank')
    parser.add_argument('--fat', type=int, choices=(12, 16), default=16)
    args = parser.parse_args()
    make(args.output, args.size, args.layout, args.fat)
