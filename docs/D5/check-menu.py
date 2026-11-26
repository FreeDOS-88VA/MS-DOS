#!/usr/bin/env python3
"""Check a D5 scratch HDI and compare captures against pre-SYS scratch HDIs.

Example: check-menu.py disk.hdi --owner 0 --last 2 1=first.hdi 2=second.hdi
Pass each comparison image from immediately before that MS-DOS capture.
No private data, fingerprints or paths are printed.
"""
import argparse
import importlib.util
from pathlib import Path
import struct
import sys

DOCS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DOCS / 'D2'))
spec = importlib.util.spec_from_file_location('fatcheck', DOCS / 'D2/check-nec-fat12.py')
fatcheck = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fatcheck)

NAMES = ['ENGINEIO.SYS', 'PCENGINE.SYS', 'ADVGBIOS.SYS', 'PCENGINE.COM']
STATESIZ = 4096


def crc16(data):
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0xa001 if crc & 1 else 0)
    return crc


def outside(path):
    path = Path(path).resolve()
    fatcheck.require(not path.is_relative_to(DOCS.parent), 'HDI must stay outside the repository')
    return path.read_bytes()


def verify(image, owner, last, captures):
    require = fatcheck.require
    mb, used, free, files = fatcheck.check(image)
    require(not {'BOOTMENU.JRN', 'VASYS.JRN'}.intersection(files), 'allocation journal still present')
    state = files['BOOTMENU.DAT']
    require(len(state) == STATESIZ and state[:4] == b'VBM1', 'bad menu state header')
    require(state[4:8] == bytes((owner, last, 0, 0)), 'unexpected ownership, default or phase')
    require(state[118] in (0, 1) and state[119] == 0, 'unknown state version or switch flags')
    require(crc16(state[:254]) == struct.unpack_from('<H', state, 254)[0], 'bad state CRC')
    _, roots, _, fat_sectors, _ = fatcheck.LEGACY[mb]
    root = fatcheck.HEADER + (1 + 2 * fat_sectors) * 1024
    present = {0}
    for num in (1, 2, 3):
        r = 16 + (num - 1) * 34
        if not state[r]:
            require(num not in captures, f'entry {num} absent')
            continue
        present.add(num)
        ipl = state[num * 1024:(num + 1) * 1024]
        require(crc16(ipl) == struct.unpack_from('<H', state, r + 16)[0], f'bad IPL CRC for {num}')
        ref_files = None
        if num in captures:
            reference = captures[num]
            require(ipl == reference[fatcheck.HEADER:fatcheck.HEADER + 1024], f'saved IPL differs for {num}')
            ref_files = fatcheck.check(reference)[3]
        for j, real in enumerate(NAMES):
            name = real if num == owner else f'VA{num}{j}0000.SYS'
            slot, expected_crc = struct.unpack_from('<HH', state, r + 18 + 4 * j)
            require(slot < roots, f'{name}: out-of-range root slot')
            entry = image[root + 32 * slot:root + 32 * (slot + 1)]
            stem, ext = name.split('.')
            require(entry[:11] == f'{stem:8}{ext:3}'.encode(), f'{name}: wrong root slot')
            attr = 0x21 if j == 3 else 0x27
            if owner != num:
                attr |= 2
            require(entry[11] == attr and crc16(entry[12:]) == expected_crc,
                    f'{name}: attributes or metadata differ')
            require(files.get(name), f'{name}: absent or empty')
            if ref_files is not None:
                require(files[name] == ref_files[real], f'{name}: captured payload differs')
    require(owner in present and last in present, 'unregistered owner or default')
    if owner == 0:
        require(not set(NAMES).intersection(files), 'unparked PC-Engine file while DOS owns the volume')
    print(f'{mb} MB: {used} used, {free} free; FATs, menu state and captures match')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image')
    parser.add_argument('--owner', type=int, choices=range(4), required=True)
    parser.add_argument('--last', type=int, choices=range(4), required=True)
    parser.add_argument('captures', nargs='*', metavar='ID=IMAGE')
    args = parser.parse_intermixed_args()
    try:
        captures = {}
        for item in args.captures:
            id_text, path = item.split('=', 1)
            num = int(id_text)
            if not 1 <= num <= 3 or num in captures:
                raise ValueError('Capture IDs must be distinct and in 1..3')
            captures[num] = outside(path)
        verify(outside(args.image), args.owner, args.last, captures)
    except (KeyError, OSError, ValueError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
