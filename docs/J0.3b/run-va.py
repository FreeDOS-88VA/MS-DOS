#!/usr/bin/env python3
"""Cold-boot VA2 prompt and DOS 0Ah tests. Dependencies: see the report."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import subprocess

from m75_scsi_harness import decode_screen


def plan(name, prefix, erase, probe):
    frame = 600
    script = []

    def act(command, delay=12):
        nonlocal frame
        script.extend((f'wait-frame {frame}', command))
        frame += delay

    def capture(label):
        # J0.3 IO.SYS: CISTAT immediately follows the function-key table.
        act(f'wait-pc 1000:059C 1\ncapture {label} tvram screen')

    def tap(key):
        if key.startswith('SHIFT+'):
            act('key-down SHIFT')
            act(f'key-tap {key.split("+")[1]} 3')
            act('key-up SHIFT')
        else:
            act(f'key-tap {key} 3')

    if probe:
        act('input-line EDBYTES', 300)
    if name == 'ins':
        act('input-line ABCDEF', 300)
    for key in prefix:
        tap(key)
    capture('before')
    if erase:
        tap(erase)
        capture('erased')
    if name == 'ins':
        tap('SHIFT+Z')
        tap('F3')
        capture('recalled')
    act('enter', 180)
    capture('submitted')
    if not probe:
        act('input-line VER', 180)
        capture('alive')
    act('exit')
    return '\n'.join(['debug-script 1', f'limit-frame {frame}', *script, ''])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('vaeg', 'roms', 'boot', 'probe', 'output'):
        p.add_argument(name, type=lambda x: Path(x).resolve())
    p.add_argument('--only', nargs='+', help='run cases whose name starts with a listed prefix')
    args = p.parse_args()
    caret = {
        'up': ('UP', 'UP'), 'right': ('RIGHT', 'RIGHT'),
        'home': ('HOME', 'HOME'), 'shift-home': ('SHIFT+HOME', 'SHIFT+HOME'),
        'mixed': ('SHIFT+A', 'UP', 'SHIFT+B', 'RIGHT'),
    }
    cases = [(f'{name}-{erase.lower()}', keys, erase, probe)
             for name, keys in caret.items() for erase in ('backspace', 'LEFT', 'DELETE', '')
             for probe in (False, True)]
    cases += [(name, ('SHIFT+A', 'SHIFT+B', key), 'backspace', probe)
              for name, key in [('down', 'DOWN'), ('left', 'LEFT'), ('del', 'DELETE'),
                                ('roll-up', 'ROLLUP'), ('roll-down', 'ROLLDOWN'), ('help', 'HELP')]
              for probe in (False, True)]
    cases += [('ins', ('SHIFT+X', 'INS', 'SHIFT+Y'), 'backspace', False)]
    if args.only:
        cases = [case for case in cases if any(case[0].startswith(s) for s in args.only)]

    def run(case):
        name, prefix, erase, probe = case
        out = args.output / ('bytes' if probe else 'prompt') / name.rstrip('-')
        out.mkdir(parents=True)
        shutil.copyfile(args.probe if probe else args.boot, out / 'disk.d88')
        (out / 'case.debug').write_text(plan(name, prefix, erase, probe))
        env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')
        cmd = [str(args.vaeg), '--model', 'va2', '--no-cfg', '--no-bkupmem', '--nowait',
               '--roms', str(args.roms), '--fdd1', 'disk.d88', '--debug-script', 'case.debug',
               '--debug-output-dir', '.']
        with (out / 'run.log').open('wb') as log:
            subprocess.run(cmd, cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=120)
        for dump in out.glob('*.tvram.bin'):
            lines = decode_screen(dump)['lines']
            dump.with_suffix('.txt').write_text('\n'.join(line.rstrip() for line in lines) + '\n')

    with ThreadPoolExecutor(3) as pool:
        list(pool.map(run, cases))


if __name__ == '__main__':
    main()
