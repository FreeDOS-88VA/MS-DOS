#!/usr/bin/env python3
"""Capture J4 guest output. All output and disk copies go to a scratch directory."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import shutil
import subprocess

from m75_scsi_harness import decode_screen

CORE = [
    ('boot', []),
    ('dir', ['DIR /W']),
    ('vol-ver', ['VOL', 'VER']),
    ('missing', ['NOSUCH']),
    ('parse', ['DIR /!']),
    ('date', ['DATE']),
    ('time', ['TIME']),
    ('copy', ['COPY NOSUCH.TXT COPY.TXT']),
    ('chkdsk', ['CHKDSK']),
    ('abort', ['DIR B:', '@a', 'ECHO AFTER-A']),
    ('retry-fail', ['DIR B:', '@r', '@f', 'ECHO AFTER-F']),
]


def capture(vaeg, roms, disk, out, model, commands, pc='1000:0A73'):
    out.mkdir(parents=True)
    shutil.copyfile(disk, out / 'disk.d88')
    frame = 600
    interval = 350
    plan = ['debug-script 1', f'limit-frame {frame + interval * len(commands) + 800}']
    for i, command in enumerate(['', *commands]):
        if command == '@enter':
            plan.append('enter')
        elif command.startswith('@'):
            plan.append('key-tap ' + command[1:].upper() + ' 3')
        elif command:
            plan.append('input-line ' + command)
        plan += [f'wait-frame {frame}', f'wait-pc {pc} 1', f'capture step{i} tvram screen']
        frame += interval
    (out / 'run.debug').write_text('\n'.join(plan + ['exit', '']))
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')
    with (out / 'run.log').open('wb') as log:
        subprocess.run([str(vaeg), '--roms', str(roms), '--model', model, '--no-cfg',
                        '--no-bkupmem', '--nowait', '--fdd1', 'disk.d88',
                        '--debug-script', 'run.debug', '--debug-output-dir', '.'],
                       cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=180)
    for i in range(len(commands) + 1):
        dump = out / f'step{i}.tvram.bin'
        lines = decode_screen(dump)['lines']
        dump.with_name(f'step{i}.txt').write_text('\n'.join(s.rstrip('? ') for s in lines) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ('vaeg', 'roms', 'disk', 'output'):
        parser.add_argument(arg, type=lambda p: Path(p).resolve())
    parser.add_argument('--model', choices=('va', 'va2'), action='append')
    args = parser.parse_args()
    with ThreadPoolExecutor(4) as pool:
        jobs = [pool.submit(capture, args.vaeg, args.roms, args.disk,
                            args.output / model / name, model, commands)
                for model in args.model or ('va', 'va2') for name, commands in CORE]
        for job in jobs:
            job.result()


if __name__ == '__main__':
    main()
