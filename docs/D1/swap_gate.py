#!/usr/bin/env python3
"""Run the one-drive /V gate on VA2 using vaeg debug-script disk swaps."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import re
import subprocess

from copy_gate import compare, screen, tracks
from mkd88 import GEOMETRY, make
from probe import ROOT, pack_va


def run(a, case, boot):
    work = a.scratch / case
    work.mkdir()
    source = make(case)
    baseline = make(case, target=True)[:0x20] + bytearray(164 * 4)
    baseline[0x1c:0x20] = len(baseline).to_bytes(4, 'little')
    for path, data in [('boot.d88', boot), ('source.d88', source), ('target.d88', baseline)]:
        (work / path).write_bytes(data)
    (work / 'vaeg.ini').write_text(f'[NekoProjectII]\nMain_RAM={a.ram}\nMain_RAM_Auto=false\n')
    end = 1550 + a.waves * a.interval
    script = ['debug-script 1', f'limit-frame {end+400}',
              'resource source source.d88', 'resource target target.d88',
              'resource system boot.d88',
              'wait-frame 650', 'input-line DISKCOPY A: A: /V']
    for i in range(a.waves):
        frame = 1550 + a.interval*i
        media = 'source' if i % 2 == 0 else 'target'
        script.extend((f'wait-frame {frame}', f'mount-fdd 1 {media}',
                       f'wait-frame {frame+150}', 'key-tap RETURN 3'))
        if media == 'source' and case in ('hd77', 'exotic'):
            for j in range(8):
                script.extend((f'wait-frame {frame+230+j*25}', 'key-tap I 3'))
    script.extend((f'wait-frame {end}', 'key-tap N 3', f'wait-frame {end+30}',
                   'mount-fdd 1 system', f'wait-frame {end+180}', 'key-tap RETURN 3',
                   f'wait-frame {end+300}', 'exit'))
    (work / 'swap.debug').write_text('\n'.join(script) + '\n')
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy', TMPDIR=str(work))
    with (work / 'swap.log').open('wb') as log:
        subprocess.run([a.vaeg, '--model', 'va2', '--roms', a.roms, '--cfg', 'vaeg.ini',
                        '--no-bkupmem', '--nowait', '--fdd1', 'boot.d88', '--debug-script', 'swap.debug',
                        '--debug-output-dir', '.', '--debug', '--frameskip', 'full',
                        '--screen-tvram-dump', 'swap.tvram'],
                       cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=480)
    error = None
    if (work / 'source.d88').read_bytes() != source:
        error = 'source was modified'
    copied = (work / 'target.d88').read_bytes()
    error = error or compare(source, copied, skip=(0,) if case == 'exotic' else ())
    if case == 'exotic' and next(tracks(copied)):
        error = error or 'mixed-size track was modified'
    text = screen(work / 'swap.tvram')
    (work / 'swap.txt').write_text(text)
    match = re.search(r'Disk swaps after initial source insertion: ([0-9A-F]{4})h', text)
    marker = 'Copy incomplete.' if case in ('hd77', 'exotic') else 'Copy complete.'
    if not match or marker not in text or 'Copy another diskette (Y/N)?' not in text:
        error = error or 'completion prompt or swap count missing'
    if 'Restore the DOS system diskette' not in text or not text.rstrip().endswith('A:\\>'):
        error = error or 'did not restore system disk and return to DOS'
    if f'Main_RAM={a.ram} ' not in (work / 'swap.log').read_text(errors='replace'):
        error = error or 'configured RAM not confirmed by emulator'
    print(f'VA2 {a.ram} KiB {case}:', f'FAIL: {error}' if error else
          f'PASS ({int(match[1], 16)} swaps after initial source insertion)',
          flush=True)
    return not error


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ('scratch', 'base', 'com', 'vaeg', 'roms'):
        p.add_argument(arg, type=lambda v: Path(v).resolve())
    p.add_argument('--ram', type=int, choices=(256, 640), required=True)
    p.add_argument('--waves', type=int, required=True, help='maximum number of insertions to script')
    p.add_argument('--interval', type=int, default=500, help='frames between insertions')
    p.add_argument('cases', choices=tuple(GEOMETRY), nargs='+')
    a = p.parse_args()
    if a.interval < 450 or a.waves < 2:
        p.error('use at least 450 frames between insertions and at least two insertions')
    if a.scratch.is_relative_to(ROOT):
        p.error('scratch must be outside repository')
    a.scratch.mkdir()
    boot = a.scratch / 'boot.d88'
    pack_va(a.base, boot, [('DISKCOPY.COM', a.com.read_bytes()),
                          ('AUTOEXEC.BAT', b'@ECHO OFF\r\n')])
    with ThreadPoolExecutor(4) as pool:
        raise SystemExit(not all(list(pool.map(lambda c: run(a, c, boot.read_bytes()), a.cases))))


if __name__ == '__main__':
    main()
