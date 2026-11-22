#!/usr/bin/env python3
"""Prepare a disposable 3.3D boot disk and drive NECAIK in NP2kai/X11."""
import argparse
from pathlib import Path
import struct
import subprocess
from tempfile import TemporaryDirectory
import time
from zipfile import ZipFile

from run import ROOT


def sectors(d88):
    for off in filter(None, struct.unpack_from('<164I', d88, 32)):
        track = []
        for _ in range(struct.unpack_from('<H', d88, off + 4)[0]):
            size = struct.unpack_from('<H', d88, off + 14)[0]
            track.append((d88[off + 2], off + 16, size))
            off += 16 + size
        for _, addr, size in sorted(track):
            yield addr, size


def media(archive, output):
    with TemporaryDirectory(dir=output.parent) as temporary, ZipFile(archive) as source:
        work = Path(temporary)
        for disk in (1, 2, 3):
            d88 = source.read(f'DOS33D_{disk}.D88')
            (work / str(disk)).write_bytes(b''.join(d88[a:a+n] for a, n in sectors(d88)))
            if disk == 1:
                boot = bytearray(d88)
        root = work / '1'
        keep = {'IO.SYS', 'MSDOS.SYS', 'COMMAND.COM', 'NECAIK1.DRV', 'NECAIK2.DRV'}
        for name in subprocess.check_output(['mdir', '-ba', '-i', root, '::'], text=True).splitlines():
            if name.removeprefix('::/').upper() not in keep:
                subprocess.run(['mdel', '-i', root, name], check=True)
        for disk, names in [(2, ('NECAI.SYS', 'NECAIKEY.EXE')), (3, ('NECAI33B.DAT',))]:
            for name in names:
                subprocess.run(['mcopy', '-i', work / str(disk), f'::{name}', work / name], check=True)
                subprocess.run(['mcopy', '-i', root, work / name, f'::{name}'], check=True)
        for name, data in [('CONFIG.SYS', b'DEVICE=NECAIK1.DRV\r\nDEVICE=NECAIK2.DRV\r\n'),
                           ('AUTOEXEC.BAT', b'VER\r\n')]:
            (work / name).write_bytes(data)
            subprocess.run(['mcopy', '-oi', root, work / name, f'::{name}'], check=True)
        with root.open('rb') as image:
            for addr, size in sectors(boot):
                data = image.read(size)
                assert len(data) == size
                boot[addr:addr+size] = data
            assert not image.read(1)
        output.write_bytes(boot)


CASES = {
    'toggle': [('narrow', ('e', 'c', 'h', 'o', 'space', 'a', 'BackSpace')),
               ('kana', ('ctrl+Alt_R', 'a', 'i')), ('backspace', ('BackSpace',)),
               ('esc', ('Escape',)), ('narrow-again', ('ctrl+Alt_R', 'x', 'Return'))],
    'conversion': [('reading', (*'echo', 'space', 'ctrl+Alt_R', *'nihongo')),
                   ('xfer', ('Alt_R',)), ('nfer', ('Alt_L',)), ('space', ('space',)),
                   ('return-1', ('Return',)), ('return-2', ('Return',))],
    'return': [('reading', (*'echo', 'space', 'ctrl+Alt_R', *'nihongo')),
               ('converted', ('space',)), ('return-1', ('Return',)), ('return-2', ('Return',))],
    'return-reading': [('reading', (*'echo', 'space', 'ctrl+Alt_R', *'nihongo')),
                       ('return-1', ('Return',)), ('return-2', ('Return',))],
    'nfer': [('reading', (*'echo', 'space', 'ctrl+Alt_R', *'nihongo')),
             ('nfer', ('Alt_L',)), ('space', ('space',))],
}


def keys(window, output, case):
    output.mkdir()
    subprocess.run(['xdotool', 'windowfocus', '--sync', window], check=True)
    for shot, sequence in [('boot', ()), *CASES[case]]:
        for key in sequence:
            subprocess.run(['xdotool', 'keydown', key], check=True)
            time.sleep(.08)
            subprocess.run(['xdotool', 'keyup', key], check=True)
            time.sleep(.12)
        time.sleep(.3)
        subprocess.run(['import', '-window', window, str(output / (shot + '.png'))], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    make = sub.add_parser('media')
    make.add_argument('archive', type=Path)
    drive = sub.add_parser('keys')
    drive.add_argument('window')
    drive.add_argument('case', choices=CASES)
    for p in (make, drive):
        p.add_argument('output', type=lambda s: Path(s).resolve())
    args = parser.parse_args()
    if args.output.is_relative_to(ROOT) or args.output.exists():
        parser.error('output must be a new path outside the repository')
    if args.command == 'media':
        media(args.archive, args.output)
    else:
        keys(args.window, args.output, args.case)
