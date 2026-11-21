#!/usr/bin/env python3
"""Cold-boot J0.4 scenarios with vaeg PR #82; see ../J0.4-label-line.md."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys

from m75_scsi_harness import decode_screen

HERE = Path(__file__).resolve().parent
DOCS = HERE.parent
BASE_PC = '1000:059C'   # CISTAT offsets from the VAIO assembler listings
AFTER_PC = '1000:059E'


def plan(pc, events):
    body = ['debug-script 1', f'limit-frame {max(800, events[-1][0] + 100)}']
    for frame, action in events:
        if frame:
            body.append(f'wait-frame {frame}')
        if action.startswith('shot '):
            body.extend((f'wait-pc {pc} 1', f'capture {action[5:]} tvram screen'))
        else:
            body.append(action)
    return '\n'.join(body + ['exit', ''])


def prior(name, pc, shots=()):
    path = DOCS / 'J0.3' / f'{name}.debug'
    body = path.read_text().removesuffix('exit\n')
    for frame, label in shots:
        # The original script may already wait beyond a capture point.
        insert = f'wait-frame {frame}\nwait-pc {pc} 1\ncapture {label} tvram screen\n'
        mark = next((m.start() for m in re.finditer(r'^wait-frame (\d+)', body, re.M)
                     if int(m[1]) > frame), len(body))
        body = body[:mark] + insert + body[mark:]
    return body + 'exit\n'


def scenarios():
    a = AFTER_PC
    yield 'base-boot', 'base', plan(BASE_PC, [(0, 'shot prompt')])
    yield 'after-boot', 'after', plan(a, [(0, 'shot prompt')])
    for label, pc in [('base', BASE_PC), ('after', a)]:
        yield f'{label}-mem', label, plan(pc, [(600, 'input-line CHKDSK'), (1700, 'shot chkdsk')])
    yield 'dir', 'after', prior('dir', a, [(1150, 'first'), (1370, 'recalled'), (2049, 'end')])
    yield 'display', 'test', plan(a, [
        (600, 'shot boot'), (630, 'key-down SHIFT'), (700, 'shot held'),
        (730, 'key-up SHIFT'), (800, 'shot released'), (850, 'input-line DIR'),
        (1500, 'shot dir'), (1550, 'key-tap F3 3'), (1600, 'shot recall'),
        (1650, 'enter'), (2300, 'shot dir-again'), (2350, 'input-line TYPE LONG.TXT'),
        (3200, 'shot type'), (3250, 'input-line CLS'), (3600, 'shot cls'),
        (3650, 'input-line CLS > F.TXT'), (4400, 'shot redirected'),
        (4450, 'input-line LABELCHK N'), (5100, 'shot thirty'),
        (5150, 'input-line LABELCHK F'), (5800, 'shot fallback'),
    ])
    yield 'toggle', 'test', plan(a, [
        (600, 'input-line LABELCHK H'), (1300, 'shot hide-block'),
        (1350, 'input-line LABELCHK L'), (2050, 'shot show-block'),
        (2100, 'input-line LABELCHK B'), (2800, 'shot hide-byte'),
        (2850, 'input-line LABELCHK C'), (3550, 'shot show-byte'),
        (3600, 'input-line LABELCHK P'), (4300, 'shot pre'),
        (4350, 'key-tap SPACE 3'), (4420, 'shot hide'),
        (4470, 'key-tap SPACE 3'), (4540, 'shot scroll'),
        (4590, 'key-tap SPACE 3'), (4660, 'shot show'),
        (4710, 'key-tap SPACE 3'), (4780, 'shot prompt'),
    ])
    for mode in ('U', 'V'):
        yield f'native-{mode}', 'test', plan(a, [
            (600, 'input-line LABELCHK N'), (1300, 'shot before'),
            (1350, f'input-line LABELCHK {mode}'), (2050, 'shot hide'),
            (2100, 'key-tap SPACE 3'), (2170, 'shot show'),
            (2220, 'key-tap SPACE 3'), (2290, 'shot clear'),
            (2340, 'key-tap SPACE 3'), (2410, 'shot home'),
            (2460, 'key-tap SPACE 3'), (2530, 'shot home-mark'),
        ])
    yield 'erase', 'test', plan(a, [
        (600, 'input-line LABELCHK N'), (1300, 'shot before'),
        (1350, 'input-line LABELCHK E'), (2050, 'shot clear-mark'),
        (2100, 'key-tap SPACE 3'), (2170, 'shot home-mark'),
    ])
    for n in range(1, 4):
        yield f'eof-{n}', 'after', prior('eof', a, [(3500, 'end')])
    yield 'ctrl-z', 'after', prior('eof-ctrl-z', a, [(3500, 'end')])
    yield 'fkeys', 'test', prior('fkey-bytes', a, [(2020, 'end')])
    yield 'cancel-break', 'after', prior('cancel-break', a, [
        (1090, 'typed'), (1200, 'cancelled'), (1340, 'recalled'), (1450, 'break'), (2119, 'end'),
    ])
    for label, pc in [('base', BASE_PC), ('after', a)]:
        yield f'{label}-regression', label, plan(pc, [
            (600, 'key-down SHIFT'), (620, 'key-tap V 3'), (640, 'key-tap E 3'),
            (660, 'key-tap R 3'), (680, 'key-tap X 3'), (700, 'key-up SHIFT'),
            (870, 'shot typed'), (900, 'key-tap BS 3'), (950, 'shot backspace'),
            (1000, 'enter'), (1400, 'shot end'),
        ])


def main():
    vaeg, roms, base, after, test, output = map(lambda x: Path(x).resolve(), sys.argv[1:7])
    images = {'base': base, 'after': after, 'test': test}
    wanted = sys.argv[7:]
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')

    def run(case):
        model, name, image, script = case
        out = output / model / name
        out.mkdir(parents=True)
        shutil.copyfile(images[image], out / 'disk.d88')
        (out / 'run.debug').write_text(script)
        with (out / 'run.log').open('wb') as log:
            subprocess.run([str(vaeg), '--model', model, '--roms', str(roms), '--no-cfg',
                            '--no-bkupmem', '--nowait', '--fdd1', 'disk.d88',
                            '--debug-script', 'run.debug', '--debug-output-dir', '.'],
                           cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=240)
        events = (out / 'events.tsv').read_text().splitlines()
        expected = set(re.findall(r'^capture (\S+)', script, re.M))
        captured = {event.split('\t')[2] for event in events if event.startswith('capture\t')}
        if not events[-1].startswith('exit\t') or expected != captured:
            raise RuntimeError(f'{out}: did not reach exit or missed capture: {expected - captured}')
        for dump in out.glob('*.tvram.bin'):
            screen = decode_screen(dump)
            # The upstream decoder uses '?' for unused NUL-filled cells.
            text = [f"main rows={len(screen['lines'])}",
                    *(f"{n:02d} {line.rstrip('?').rstrip()}" for n, line in enumerate(screen['lines'], 1))]
            dump.with_name(dump.name.replace('.tvram.bin', '.txt')).write_text('\n'.join(text) + '\n')
        print(model, name, flush=True)

    cases = [(model, name, image, script) for model in ('va', 'va2')
             for name, image, script in scenarios() if not wanted or name in wanted]
    with ThreadPoolExecutor(4) as pool:
        list(pool.map(run, cases))


if __name__ == '__main__':
    main()
