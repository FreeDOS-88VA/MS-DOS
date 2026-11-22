#!/usr/bin/env python3
"""Build and run FDPROBE on original fixtures. PYTHONPATH: builder experiment.

Arguments: new scratch dir, distribution D88, emu2, tool dir (MASM/LINK),
vaeg, ROM directory. Optional case names restrict the matrix.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

from build import mz_image
from readfile import raw_image, read_file
from mkd88 import GEOMETRY, make

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'docs/J1'))
from media import pack_va

TRACKS = (0, 1, 2, 3, 4, 78, 79, 80, 81, 152, 153, 154, 158, 159)


def rows(image):
    for track in TRACKS:
        ptr, = struct.unpack_from('<I', image, 0x20 + 4 * track)
        if not ptr:
            continue
        ids = []
        for _ in range(struct.unpack_from('<H', image, ptr + 4)[0]):
            ids.append(image[ptr:ptr+4])
            fm = bool(image[ptr + 6] & 0x40)
            ptr += 16 + struct.unpack_from('<H', image, ptr + 14)[0]
        yield track, fm, ids


def check(model, name, work, image):
    raw = raw_image((work / 'boot.d88').read_bytes())
    data = read_file(raw, 'IDS.BIN')
    (work / 'IDS.BIN').write_bytes(data)
    actual = {}
    for t, mode, fm, cf, ah, st0, st1, st2, *ids in struct.iter_unpack('12B', data):
        actual.setdefault((t, mode, bool(fm)), []).append((cf, ah, bytes(ids)))
    assert len(actual) == 6 * len(TRACKS), f'incomplete probe: {model} {name}'
    expected = {(t, fm): ids for t, fm, ids in rows(image)}
    mode = {0: 1, 0x10: 0x12, 0x20: 0x23}[image[0x1b]]
    lines = []
    for t in TRACKS:
        for fm in (False, True):
            ids = expected.get((t, fm), [])
            records = actual[t, mode, fm]
            got = [i for cf, ah, i in records if not (cf or ah)]
            if not ids:
                status = 'no-ID' if not got else 'unexpected-ID'
            else:
                status = 'FAIL'
                for start in range(len(ids)):
                    rotated = ids[start:] + ids[:start]
                    if got == rotated + rotated[:1]:
                        status = 'wrap'
                        break
            lines.append(f'{model}\t{name}\t{t}\t{mode:02x}\t{int(fm)}\t'
                         f'{len(ids)}\t{len(got)}\t{status}\t{records[-1][1]:02x}\t'
                         + (','.join(i.hex() for i in got) or '-'))
    return lines


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ('scratch', 'base', 'emu2', 'tools', 'vaeg', 'roms'):
        p.add_argument(arg, type=lambda v: Path(v).resolve())
    p.add_argument('cases', nargs='*', metavar='CASE')
    p.add_argument('--frames', type=int, default=5000)
    a = p.parse_args()
    if a.scratch.is_relative_to(ROOT):
        p.error('scratch must be outside the repository')
    a.scratch.mkdir()
    asm = a.scratch / 'asm'
    asm.mkdir()
    for tool in ('MASM.EXE', 'LINK.EXE'):
        shutil.copyfile(a.tools / tool, asm / tool)
    shutil.copyfile(ROOT / 'tests/pc88va/FDPROBE.ASM', asm / 'FDPROBE.ASM')
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy',
               TMPDIR=str(a.scratch))
    with (asm / 'build.log').open('wb') as log:
        for exe, args in (('MASM.EXE', 'FDPROBE;'), ('LINK.EXE', 'FDPROBE,FDPROBE.EXE;')):
            subprocess.run([a.emu2, asm / exe, args], cwd=asm, env=env,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
    boot = a.scratch / 'probe.d88'
    pack_va(a.base, boot, [('FDPROBE.COM', mz_image((asm / 'fdprobe.exe').read_bytes(), origin=256)),
                           ('AUTOEXEC.BAT', b'@ECHO OFF\r\n')])

    def run(case):
        model, name = case
        work = a.scratch / f'{model}-{name}'
        work.mkdir()
        image = make(name)
        (work / 'source.d88').write_bytes(image)
        shutil.copyfile(boot, work / 'boot.d88')
        (work / 'run.debug').write_text(f'debug-script 1\nlimit-frame {a.frames + 100}\n'
                                        'wait-frame 650\ninput-line FDPROBE > IDS.BIN\n'
                                        f'wait-frame {a.frames}\nexit\n')
        with (work / 'run.log').open('wb') as log:
            subprocess.run([a.vaeg, '--model', model, '--roms', a.roms, '--no-cfg',
                            '--no-bkupmem', '--nowait', '--fdd1', 'boot.d88', '--fdd2', 'source.d88',
                            '--debug-script', 'run.debug', '--debug-output-dir', '.',
                            '--screen-tvram-dump', 'end.tvram'], cwd=work, env=env,
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
        assert (work / 'events.tsv').read_text().splitlines()[-1].startswith('exit\t'), work
        result = check(model, name, work, image)
        print(model, name, flush=True)
        return result

    cases = [(model, name) for model in ('va', 'va2') for name in (a.cases or GEOMETRY)]
    failed = False
    with ThreadPoolExecutor(4) as pool, (a.scratch / 'results.tsv').open('w') as out:
        print('model\timage\ttrack\tmode\tfm\texpected\tactual\tstatus\tlast-AH\tCHRN', file=out)
        for lines in pool.map(run, cases):
            print(*lines, sep='\n', file=out, flush=True)
            failed |= any(line.split('\t')[7] not in ('wrap', 'no-ID') for line in lines)
    if failed:
        raise SystemExit('READ ID matrix mismatch; see results.tsv')


if __name__ == '__main__':
    main()
