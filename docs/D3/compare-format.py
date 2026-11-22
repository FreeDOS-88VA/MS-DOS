#!/usr/bin/env python3
"""Compare a D3 FORMAT HDI with an HDFORM HDI made from the same blank image."""
import argparse
from collections import Counter
from pathlib import Path
import struct
import sys


def compare(reference, result):
    if len(reference) != len(result) or len(reference) < 4096:
        raise ValueError('HDI lengths differ or header is truncated')
    header, payload, block = struct.unpack_from('<3I', reference, 8)
    if ((header, block) != (4096, 256) or len(reference) != header + payload
            or payload < 5 * block or payload % block):
        raise ValueError('not a 256-byte SASI HDI')
    media = reference[header + 4 * block]
    try:
        spf, root = {0xd0: (1, 608), 0xd1: (2, 992), 0xd2: (4, 1504),
                     0xd3: (4, 3072)}[media]
    except KeyError as error:
        raise ValueError('reference has no HDFORM media byte') from error
    fat2 = 4 + 4 * spf
    first_root = fat2 + 4 * spf
    first_data = first_root + root * 32 // block
    if first_data > payload // block:
        raise ValueError('HDI too small for the reference layout')
    ranges = [('IPL', 0, 4), ('FAT1', 4, fat2), ('FAT2', fat2, first_root),
              ('root', first_root, first_data), ('data/tail', first_data, payload // block)]
    differences = Counter()
    if reference[:header] != result[:header]:
        differences['HDI header'] = 1
    for area, start, end in ranges:
        lo, hi = header + start * block, header + end * block
        if reference[lo:hi] == result[lo:hi]:
            continue
        differences[area] = sum(reference[i:i + block] != result[i:i + block]
                                for i in range(lo, hi, block))
    return payload // block, differences


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('hdform', type=Path)
    parser.add_argument('format', type=Path)
    args = parser.parse_args()
    try:
        repo = Path(__file__).resolve().parents[2]
        if any(p.resolve().is_relative_to(repo) for p in (args.hdform, args.format)):
            raise ValueError('HDIs must stay outside the repository')
        blocks, differences = compare(args.hdform.read_bytes(), args.format.read_bytes())
    except (OSError, ValueError) as error:
        parser.exit(1, f'{error}\n')
    print(f'{blocks} physical blocks; ' + (', '.join(f'{k}: {v}' for k, v in differences.items())
                                           if differences else 'no differences (including HDI header)'))
    return int(bool(differences))


if __name__ == '__main__':
    sys.exit(main())
