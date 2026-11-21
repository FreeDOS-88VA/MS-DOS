#!/usr/bin/env python3
"""Prepare scratch D88s. Never run this in the MS-DOS source tree."""
import argparse
import struct
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory

from readfile import raw_image, read_file
from build import compose, d88

PAIRS = tuple(bytes.fromhex(s) for s in ('955c', '835c', '945c', '905c', '975c', '817c', '8261'))


def batch(lines):
    return b'\r\n'.join(lines) + b'\r\n'


def fixtures(probe, regressions=None):
    make = [b'@ECHO OFF']
    clean = [b'@ECHO OFF']
    for pair in PAIRS:
        directory = b'S' + pair
        # COPY exercises shell file creation independently of the separate
        # redirection-token test below (NEC may treat the pipe trail there
        # differently from an ordinary argument).
        make += [b'MD ' + directory, b'CD ' + directory,
                 b'COPY \\MARK.IN ' + pair + b'a.TXT',
                 b'REN ' + pair + b'a.TXT ' + pair + b'b.TXT',
                 b'TYPE ' + pair + b'b.TXT', b'CD \\']
        clean += [b'DEL ' + directory + b'\\' + pair + b'b.TXT', b'RD ' + directory]
    make += [b'MD J1DEL', b'CD J1DEL', b'ECHO MARK>' + PAIRS[0] + b'.TXT',
             b'ECHO DECOY>AB.TXT', b'DIR *.TXT > ALL.OUT',
             b'DIR ?.TXT > ONE.OUT', b'DEL ?.TXT', b'DIR ??.TXT > TWO.OUT',
             b'DEL ??.TXT', b'CD \\', b'MD J1PIPE', b'CD J1PIPE',
             b'ECHO MARK>' + PAIRS[5] + b'.TXT', b'CD \\']
    files = [('J1DBCS.COM', probe.read_bytes()), ('J1MAKE.BAT', batch(make)),
             ('J1CLEAN.BAT', batch(clean)), ('MARK.IN', b'MARK\r\n'), ('BS.IN', b'X\x95\\\x08Y\r\n'),
             ('ESC.IN', b'X\x95\\\x1bDY\r\n')]
    if regressions:
        files.extend((f, (regressions / f).read_bytes()) for f in
                     ('LABELCHK.COM', 'LONG.TXT', 'CONKEY.COM'))
    return files


def pack_va(image, output, files):
    raw = raw_image(image.read_bytes())
    old = []
    for offset in range(5 * 1024, 11 * 1024, 32):
        entry = raw[offset:offset + 32]
        if not entry[0]:
            break
        if entry[11] & 8:
            label = entry[:11].decode().rstrip()
            date = struct.unpack_from('<H', entry, 24)[0]
            continue
        stem, ext = (p.decode().rstrip() for p in (entry[:8], entry[8:11]))
        name = stem + ('.' + ext if ext else '')
        old.append((name, read_file(raw, name), entry[11]))
    boot = raw[:1024]
    output.write_bytes(d88(compose(boot, old + [(n, d, 32) for n, d in files],
                                   label, date, struct.unpack_from('<I', boot, 39)[0]),
                           'J1-TEST'))


def pack_nec(image, output, files):
    # Preserve the original D88 headers, track order and non-data bytes.
    d = bytearray(image.read_bytes())
    offsets = []
    with TemporaryDirectory(dir=output.parent) as scratch:
        tmp = Path(scratch)
        for track, in struct.iter_unpack('<I', d[0x20:0x2b0]):
            if not track:
                continue
            for _ in range(struct.unpack_from('<H', d, track+4)[0]):
                size = struct.unpack_from('<H', d, track+14)[0]
                offsets.append((track+16, size))
                track += 16 + size
        disk = tmp / 'raw.img'
        disk.write_bytes(b''.join(d[p:p+s] for p,s in offsets))
        subprocess.run(['mdel', '-i', disk, '::README2.DOC', '::EMM386.SYS', '::EMM.SYS'], check=True)
        for name, contents in files:
            path = tmp / name
            path.write_bytes(contents)
            subprocess.run(['mcopy', '-i', disk, path, '::' + name], check=True)
        raw = disk.read_bytes()
        off = 0
        for pos, size in offsets:
            d[pos:pos+size] = raw[off:off+size]
            off += size
        assert off == len(raw)
    output.write_bytes(d)


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('model', choices=('va', 'nec'))
    for arg in ('image', 'output', 'probe'):
        ap.add_argument(arg, type=Path)
    ap.add_argument('--regressions', type=Path)
    args = ap.parse_args()
    output = args.output.resolve()
    if Path(__file__).resolve().parents[2] in output.parents:
        ap.error('output must be outside the repository')
    (pack_va if args.model == 'va' else pack_nec)(args.image, output,
                                                 fixtures(args.probe, args.regressions))
