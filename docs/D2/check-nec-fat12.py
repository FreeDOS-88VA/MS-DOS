#!/usr/bin/env python3
"""Check a scratch HDFORM HDI directly, without a synthesized BPB.

Optional NAME=SOURCE arguments require an exact file manifest and byte
matches. Use DOS paths with forward slashes for files in subdirectories.
"""
import argparse
import hashlib
from pathlib import Path
import struct

from mkhdi import BLOCK, GEOMETRY, HEADER, LEGACY, TRACK

SECTOR = 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check(image):
    require(len(image) >= HEADER, 'truncated HDI header')
    header, payload, block, track, heads, cyl = struct.unpack_from('<6I', image, 8)
    sizes = [mb for mb, geometry in GEOMETRY.items() if geometry == (cyl, heads)]
    require(header == HEADER and block == BLOCK and track == TRACK and sizes
            and payload == block * track * heads * cyl and len(image) == header + payload,
            'unexpected VA SASI HDI geometry or size')
    mb, = sizes
    sectors, entries, spc, spf, media = LEGACY[mb]
    fat_start = header + SECTOR  # physical block 4
    fat_size = spf * SECTOR
    root_start = fat_start + 2 * fat_size
    data_start = root_start + entries * 32
    cluster_bytes = spc * SECTOR
    last = 1 + (header + sectors * SECTOR - data_start) // cluster_bytes
    fat = image[fat_start:fat_start + fat_size]
    require(fat == image[fat_start + fat_size:root_start], 'FAT copies differ')
    require(fat[:3] == bytes((media, 255, 255)), 'incorrect FAT media/reserved entries')
    owners = {}
    files = {}
    paths = set()

    def fat_entry(cluster):
        pos = cluster + cluster // 2
        value, = struct.unpack_from('<H', fat, pos)
        return value >> 4 if cluster & 1 else value & 0xfff

    def chain(cluster, path):
        chunks = []
        while True:
            require(2 <= cluster <= last, f'{path}: invalid cluster {cluster:#x}')
            require(cluster not in owners,
                    f'{path}: loop or cross-link at {cluster} (owned by {owners.get(cluster)})')
            owners[cluster] = path
            pos = data_start + (cluster - 2) * cluster_bytes
            chunks.append(image[pos:pos + cluster_bytes])
            cluster = fat_entry(cluster)
            if cluster >= 0xff8:
                return b''.join(chunks)

    def directory(data, prefix='', own=0, parent=0):
        dots = {}
        for pos in range(0, len(data), 32):
            entry = data[pos:pos + 32]
            if not entry[0]:
                break
            if entry[0] == 0xe5 or entry[11] & 8:
                continue
            stem = entry[:8].rstrip(b' ')
            ext = entry[8:11].rstrip(b' ')
            # Gate fixtures use ASCII, but existing NEC files may use DBCS.
            name = (stem + (b'.' + ext if ext else b'')).decode('cp932', 'backslashreplace')
            path = prefix + name
            cluster, size = struct.unpack_from('<HI', entry, 26)
            is_dir = bool(entry[11] & 0x10)
            if name in ('.', '..'):
                require(own and is_dir and size == 0 and name not in dots,
                        f'{path}: invalid dot entry')
                dots[name] = cluster
                continue
            require(path not in paths, f'{path}: duplicate entry')
            paths.add(path)
            if is_dir:
                require(size == 0, f'{path}: nonzero directory size')
                directory(chain(cluster, path), path + '/', cluster, own)
            elif size:
                contents = chain(cluster, path)
                require(len(contents) - cluster_bytes < size <= len(contents),
                        f'{path}: chain length does not match file size')
                files[path] = contents[:size]
            else:
                require(cluster == 0, f'{path}: empty file owns a cluster chain')
                files[path] = b''
        if own:
            require(dots == {'.': own, '..': parent}, f'{prefix}: incorrect dot entries')

    directory(image[root_start:data_start])
    lost = [i for i in range(2, last + 1) if i not in owners and fat_entry(i) != 0]
    require(not lost, f'unreferenced non-free clusters: {lost}')
    return mb, len(owners), last - 1 - len(owners), files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('files', metavar='NAME=SOURCE', nargs='*')
    args = parser.parse_args()
    try:
        require(not args.image.resolve().is_relative_to(Path(__file__).resolve().parents[2]),
                'HDI must stay outside the repository')
        mb, used, free, files = check(args.image.read_bytes())
        if args.files:
            expected = dict(spec.split('=', 1) for spec in args.files)
            require(files.keys() == expected.keys(),
                    f'missing: {sorted(expected.keys() - files.keys())}; '
                    f'unexpected: {sorted(files.keys() - expected.keys())}')
            for name, source in expected.items():
                require(files[name] == Path(source).read_bytes(), f'{name}: contents differ')
        print(f'{mb} MB: FAT copies equal; {used} used, {free} free, 0 lost clusters')
        for name, data in sorted(files.items()):
            print(f'{name}\t{len(data)}\t{hashlib.sha256(data).hexdigest()}')
    except (OSError, ValueError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
