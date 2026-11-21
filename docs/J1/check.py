#!/usr/bin/env python3
"""Decode J1 probe results and check exact FAT12 paths on scratch captures."""
import argparse
import struct
from pathlib import Path

from media import PAIRS
from readfile import raw_image

OPS = ('md', 'create', 'cd', 'cwd', 'open', 'rename', '!old', 'reopen', 'create2',
       'delete', 'parse', 'fcreate', 'fclose', 'fopen', 'fclose', 'fparse2', 'frename',
       'fopen2', 'fclose2', 'asciiz-open', 'fdelete', '!fopen', 'root', 'md2',
       'rendir', 'cd2', 'rd2')
EXPECTED = bytes([0]*6 + [2] + [0]*14 + [255] + [0]*5)


def contents(image):
    raw = raw_image(Path(image).read_bytes())
    bps, spc, reserved, fats, nroot, _, _, fatsecs = struct.unpack_from('<HBHBHHBH', raw, 11)
    fat = raw[reserved*bps:(reserved+fatsecs)*bps]
    root = (reserved+fats*fatsecs)*bps
    data = root + (nroot*32 + bps-1)//bps*bps
    size = bps * spc
    files, dirs = {}, set()
    used = set()

    def chain(cluster):
        out = bytearray()
        while 2 <= cluster < 0xff8:
            assert cluster not in used, f'crosslinked/looped cluster {cluster}'
            used.add(cluster)
            pos = data + (cluster-2)*size
            out.extend(raw[pos:pos+size])
            val = struct.unpack_from('<H', fat, cluster*3//2)[0]
            cluster = val >> 4 if cluster & 1 else val & 0xfff
        return out

    def walk(directory, path):
        for off in range(0,len(directory),32):
            ent = directory[off:off+32]
            if not ent[0]:
                break
            if ent[0] == 0xe5 or ent[11] & 8 or ent[:11] in (b'.          ', b'..         '):
                continue
            base, ext = ent[:8].rstrip(b' '), ent[8:11].rstrip(b' ')
            key = path + (base + (b'.' + ext if ext else b''),)
            assert key not in files and key not in dirs, f'duplicate entry {key}'
            cluster, count = struct.unpack_from('<HI', ent, 26)
            payload = chain(cluster)
            if ent[11] & 0x10:
                dirs.add(key)
                walk(bytes(payload), key)
            else:
                files[key] = bytes(payload[:count])
    walk(raw[root:root+nroot*32], ())
    return files, dirs


def api(files, dirs):
    data = files.get((b'J1API.OUT',), b'')
    if len(data) != 8 + len(PAIRS)*len(OPS) + 5:
        print('API result absent or truncated:', len(data))
        return
    print('table:', data[:6].hex(' '), 'country:', int.from_bytes(data[6:8], 'little'))
    for i, p in enumerate(PAIRS):
        begin = 8+i*len(OPS)
        record = data[begin:begin+len(OPS)]
        d = (p+b'D',)
        actual = [k[-1] for k in files if k[:-1] == d] + [k[-1] for k in dirs if k[:-1] == d]
        assert len(record) == len(EXPECTED)
        print(p.hex(), 'errors:', ','.join(f'{n}={a:02x}' for n,a,e in zip(OPS, record, EXPECTED) if a != e) or 'none',
              'nested disk entries:', [x.hex() for x in sorted(actual)],
              'temporary dirs gone:', all((prefix+p,) not in dirs for prefix in (b'T', b'U')))
    print('FindFirst/Next masks (*, ?, ??, ?X, ??X):', data[-5:].hex(' '))


def shell(files, dirs):
    for p in PAIRS:
        key = (b'S'+p,)
        actual = [k[-1] for k in files if k[:-1] == key] + [k[-1] for k in dirs if k[:-1] == key]
        payload = files.get(key+(p+b'B.TXT',))
        print(p.hex(), 'shell dir:', key in dirs, 'entries:', [x.hex() for x in sorted(actual)], 'payload:', payload)
    for log in (b'ALL.OUT', b'ONE.OUT', b'TWO.OUT'):
        data = files.get((b'J1DEL',log), b'')
        print(log.decode(), '955c in listing:', PAIRS[0]+b' ' in data,
              'AB in listing:', b'AB ' in data, 'length:', len(data))
    print('wildcard DEL survivors:', [k[-1].hex() for k in sorted(files) if k[:-1] == (b'J1DEL',) and k[-1].endswith(b'.TXT')])
    print('redirection operand:', [(k[-1].hex(), v) for k, v in files.items() if k[:-1] == (b'J1PIPE',)])


def new_entries(files, dirs, original):
    ref_f, ref_d = contents(original)
    paths = (files.keys() - ref_f.keys()) | (dirs - ref_d)
    print('new paths:', ', '.join('/'.join(seg.hex() for seg in p) for p in sorted(paths)))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('image', type=Path)
    ap.add_argument('--original', type=Path)
    args = ap.parse_args()
    files, dirs = contents(args.image)
    if (b'J1API.OUT',) in files:
        api(files,dirs)
    if (b'J1DEL',) in dirs:
        shell(files,dirs)
    for name in (b'J1LINE.OUT', b'J1BS.OUT', b'J1ESC.OUT'):
        if (name,) in files:
            print(name.decode(), files[name,].hex(' '))
    if args.original:
        new_entries(files, dirs, args.original)


if __name__ == '__main__':
    main()
