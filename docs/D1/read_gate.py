#!/usr/bin/env python3
"""Run DISKCOPY B: /T against original D88 fixtures.

PYTHONPATH: builder experiment. Supply an already assembled DISKCOPY.COM.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import struct
import subprocess

from probe import ROOT, pack_va, raw_image, read_file
from mkd88 import GEOMETRY, make


def checksum(data):
    value = 0
    for byte in data:
        value = (((value << 1) | (value >> 15)) + byte) & 0xffff
    return value


def expected_tracks(image, tracks):
    for track in range(tracks):
        ptr, = struct.unpack_from('<I', image, 0x20 + 4 * track)
        sectors = []
        density = 0
        if ptr:
            count, = struct.unpack_from('<H', image, ptr + 4)
            for _ in range(count):
                size, = struct.unpack_from('<H', image, ptr + 14)
                data = image[ptr+16:ptr+16+size]
                sectors.append((image[ptr:ptr+4], checksum(data), 0))
                density = 0x80 if image[ptr+6] & 0x40 else 0
                ptr += 16 + size
        yield density, sectors


def check(text, expected, abort):
    lines = text.splitlines()
    if abort:
        assert lines and lines[-1] != 'DONE', 'Abort did not stop diagnostics'
    else:
        assert lines and lines.pop() == 'DONE', 'read gate did not finish'
    assert len(lines) == len(expected), ('track count', len(lines), len(expected))
    for i, (line, (density, sectors)) in enumerate(zip(lines, expected, strict=True)):
        t, d, n, *entries = line.split()
        assert int(t, 16) == i and int(n, 16) == len(entries) == len(sectors), line
        if sectors:
            assert int(d, 16) == density, line
        got = []
        for entry in entries:
            ids, value, status = entry.split(':')
            got.append((bytes.fromhex(ids), int(value, 16), int(status, 16)))
        if got:
            assert any(got == sectors[j:] + sectors[:j] for j in range(len(sectors))), (
                i, got, sectors)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ('scratch', 'base', 'com', 'vaeg', 'roms'):
        p.add_argument(arg, type=lambda v: Path(v).resolve())
    p.add_argument('--model', choices=('va', 'va2'), default='va')
    p.add_argument('--frames', type=int, default=4500)
    p.add_argument('--trace', action='store_true')
    p.add_argument('cases', nargs='*', metavar='CASE')
    a = p.parse_args()
    if a.scratch.is_relative_to(ROOT):
        p.error('scratch must be outside the repository')
    a.scratch.mkdir()
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy',
               TMPDIR=str(a.scratch))
    boot = a.scratch / 'probe.d88'
    pack_va(a.base, boot, [('DISKCOPY.COM', a.com.read_bytes()),
                          ('AUTOEXEC.BAT', b'@ECHO OFF\r\n')])

    def run(case):
        abort = case == 'abort'
        name = 'exotic' if abort else case
        work = a.scratch / case
        work.mkdir()
        image = make(name)
        (work / 'source.d88').write_bytes(image)
        shutil.copyfile(boot, work / 'boot.d88')
        script = ['debug-script 1', f'limit-frame {a.frames + 100}', 'wait-frame 650',
                  'input-line DISKCOPY B: /T > TRACKS.TXT']
        if abort or name in ('exotic', 'hd77'):
            script.extend(('wait-frame 1200', 'input-line A' if abort else 'input-line IIIIII'))
        script.extend((f'wait-frame {a.frames}', 'exit', ''))
        (work / 'run.debug').write_text('\n'.join(script))
        args = [a.vaeg, '--model', a.model, '--roms', a.roms, '--no-cfg', '--no-bkupmem',
                '--nowait', '--fdd1', 'boot.d88', '--fdd2', 'source.d88', '--debug-script',
                'run.debug', '--debug-output-dir', '.', '--screen-tvram-dump', 'end.tvram']
        with (work / 'run.log').open('wb') as log:
            subprocess.run(args + (['--fdctrace'] if a.trace else []), cwd=work, env=env,
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=300)
        assert (work / 'events.tsv').read_text().splitlines()[-1].startswith('exit\t'), work
        raw = raw_image((work / 'boot.d88').read_bytes())
        data = read_file(raw, 'TRACKS.TXT')
        (work / 'TRACKS.TXT').write_bytes(data)
        expected = list(expected_tracks(image, 2 if abort else 80 if name == 'd16' else 160))
        check(data.decode('ascii'), expected, abort)
        print(a.model, case, len(expected), 'PASS', flush=True)

    with ThreadPoolExecutor(4) as pool:
        list(pool.map(run, a.cases or (*GEOMETRY, 'abort')))


if __name__ == '__main__':
    main()
