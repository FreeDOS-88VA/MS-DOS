#!/usr/bin/env python3
"""J0.5 scenarios; use the PR #82 binary and see ../J0.5-key-command.md."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys

from m75_scsi_harness import decode_screen

HERE = Path(__file__).resolve().parent


def script(pc, *events):
    lines = ['debug-script 1', f'limit-frame {events[-1][0] + 400}']
    for frame, action in events:
        lines.append(f'wait-frame {frame}')
        if action.startswith('@'):
            lines.extend((f'wait-pc {pc} 1', f'capture {action[1:]} tvram screen'))
        else:
            lines.append(action)
    return '\n'.join(lines + ['exit', ''])


def main():
    vaeg, roms, base, after, test, drive_b, output = map(
        lambda p: Path(p).resolve(), sys.argv[1:8])
    pc = sys.argv[8]  # 1000:xxxx, CISTAT offset from the VAIO MASM listing
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')

    def run(model, name, image, plan, second=None):
        out = output / model / name
        out.mkdir(parents=True)
        shutil.copyfile(image, out / 'disk.d88')
        args = []
        if second:
            shutil.copyfile(second, out / 'b.d88')
            args = ['--fdd2', 'b.d88']
        (out / 'run.debug').write_text(plan)
        with (out / 'run.log').open('wb') as log:
            subprocess.run([str(vaeg), '--model', model, '--roms', str(roms), '--no-cfg',
                            '--no-bkupmem', '--nowait', '--fdd1', 'disk.d88', *args,
                            '--debug-script', 'run.debug', '--debug-output-dir', '.'],
                           cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=180)
        events = (out / 'events.tsv').read_text().splitlines()
        expected = set(re.findall(r'^capture (\S+)', plan, re.M))
        captured = {event.split('\t')[2] for event in events if event.startswith('capture\t')}
        if not events[-1].startswith('exit\t') or expected != captured:
            raise RuntimeError(f'{out}: did not reach exit or missed capture: {expected - captured}')
        for dump in out.glob('*.tvram.bin'):
            lines = decode_screen(dump)['lines']
            dump.with_suffix('.txt').write_text('\n'.join(line.rstrip('? ') for line in lines) + '\n')
        print(model, name, flush=True)
        return out / 'disk.d88'

    def model_run(model):
        run(model, 'vector', base, script('1000:059E',
            (600, 'input-line DCKEYS V'), (1400, '@vector')))
        run(model, 'api', test, script(pc,
            (600, 'input-line DCKEYS'), (2300, '@updated'),
            (2350, 'key-tap F1 3'), (2400, '@f1'),
            (2430, 'key-down CTRL'), (2440, 'key-tap X 3'), (2450, 'key-up CTRL'),
            (2500, 'key-down SHIFT'), (2520, 'key-tap F1 3'), (2580, '@sf1'),
            (2600, 'key-up SHIFT'), (2640, 'key-down CTRL'), (2650, 'key-tap X 3'),
            (2660, 'key-up CTRL'), (2710, 'input-line DCKEYS L'), (3400, '@labels')))
        run(model, 'unknown', test, script(pc,
            (600, 'input-line DCKEYS U'), (1400, '@unknown')))
        run(model, 'pending', test, script(pc,
            (600, 'input-line DCKEYS P'), (1100, 'key-down SHIFT'),
            (1120, 'key-tap F1 3'), (1140, 'key-up SHIFT'),
            (1200, 'key-tap Z 3'), (1300, '@pending')))
        run(model, 'hidden-write', test, script(pc,
            (600, 'input-line LABELCHK H'), (1300, '@hidden'),
            (1350, 'input-line DCKEYS L'), (2050, '@after-write'),
            (2100, 'input-line LABELCHK L'), (2800, '@shown')))
        saved = run(model, 'key-save', after, script(pc,
            (600, 'input-line KEY'), (1500, '@list'),
            (1550, 'input-line KEY > BEFORE.TXT'), (2600, '@list-file'),
            (2650, r'input-line KEY SF1 dir b:\r'), (3150, '@set'),
            (3200, 'key-down SHIFT'), (3220, '@key-label'),
            (3250, 'key-tap F1 3'), (3280, 'key-up SHIFT'), (4350, '@dir-b'),
            (4400, 'input-line KEY /SAVE MY.KEY'), (5400, '@saved')), drive_b)
        run(model, 'key-load', saved, script(pc,
            (600, 'key-down SHIFT'), (650, '@reboot-defaults'), (670, 'key-up SHIFT'),
            (750, 'input-line KEY MY.KEY'), (1650, '@loaded'),
            (1690, 'key-down SHIFT'), (1710, '@loaded-label'),
            (1740, 'key-tap F1 3'), (1760, 'key-up SHIFT'), (2900, '@loaded-dir-b'),
            (3000, 'input-line KEY > AFTER.TXT'), (4000, '@restored'),
            (4100, 'input-line KEY BEFORE.TXT'), (4900, '@bad-file'),
            (5000, 'input-line KEY > STILL.TXT'), (5900, '@unchanged')), drive_b)

    with ThreadPoolExecutor(2) as pool:
        list(pool.map(model_run, ('va', 'va2')))


if __name__ == '__main__':
    main()
