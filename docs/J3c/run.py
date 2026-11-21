#!/usr/bin/env python3
"""Exercise the same DOS keyboard plans in both JFP modes on vaeg m153."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import csv
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[2]
MATRIX = (('va', 640), ('va2', 256), ('va2', 640))
MODES = ('ROM', 'FEP')

spec = importlib.util.spec_from_file_location('j3a_run', ROOT / 'docs/J3a/run.py')
j3a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(j3a)


class Plan(j3a.Plan):
    def __init__(self, cistat, screens):
        super().__init__()
        self.cistat = cistat
        self.targets = 'tvram screen' if screens else 'tvram'
        self.shots = []

    def shot(self, name):
        if name in self.shots:
            raise ValueError(f'duplicate shot: {name}')
        self.shots.append(name)
        self.event(f'wait-pc {self.cistat} 1\ncapture {name} {self.targets}', 25)

    def script(self, mode):
        # Only the selector differs; no mode-specific keyboard workarounds.
        body = [f'input-line JFP {mode}' if cmd == 'input-line JFP @MODE@' else cmd
                for cmd in self.body]
        return '\n'.join(['debug-script 1', f'limit-frame {self.frame + 300}', *body, 'exit', ''])

    def reading(self, romaji):
        self.keys(*romaji.upper())

    def echo(self, romaji):
        self.keys(*'ECHO', 'SPACE', 'ZENKAKU')
        self.reading(romaji)


def scenarios(cistat, screens):
    def start(hidden=False):
        p = Plan(cistat, screens)
        p.shot('boot')
        if hidden:
            p.line('LABELCHK H')
            p.shot('hidden')
        p.line('JFP @MODE@')
        p.shot('enabled')
        return p

    p = start()
    p.echo('nihongo')
    p.shot('reading')
    p.keys('HENKAN')
    p.shot('first')
    p.keys('HENKAN')
    p.shot('next')
    p.keys('SHIFT+HENKAN')
    p.shot('previous')
    p.keys('KETTEI')
    p.shot('confirmed')
    p.keys('RETURN')
    p.shot('submitted')
    yield 'prompt', p

    p = start()
    p.echo('nihongowohanasu')
    p.shot('reading')
    p.keys('HENKAN')
    p.shot('first')
    for key, name in [('SHIFT+LEFT', 'short'), ('SHIFT+RIGHT', 'long'),
                      ('RIGHT', 'right'), ('LEFT', 'left')]:
        p.keys(key)
        p.shot(name)
    p.keys('KETTEI', 'RETURN')
    p.shot('submitted')
    yield 'phrase', p

    p = start()
    p.echo('ai')
    p.keys('BS')
    p.shot('bs')
    p.keys('F1')
    p.shot('pending-f1')
    p.keys('ESC')
    p.shot('esc')
    p.keys('A', 'CTRL+C')
    p.shot('pending-ctrl-c')
    p.reading('nihongo')
    p.keys('HENKAN', 'RETURN')
    p.shot('first-return')
    p.keys('RETURN')
    p.shot('second-return')
    p.keys('F1')
    p.shot('template-f1')
    p.keys('F3')
    p.shot('template-f3')
    yield 'edit', p

    p = start(hidden=True)
    p.echo('nihongo')
    p.keys('HENKAN')
    p.shot('candidate')
    p.event('key-down SHIFT', 40)
    p.shot('held-shift')
    p.event('key-up SHIFT', 40)
    p.keys('KETTEI', 'RETURN', 'ZENKAKU')
    p.shot('idle')
    p.line('LABELCHK H')
    p.shot('hide-while-enabled')
    p.line('JFP OFF')
    p.shot('off')
    yield 'layout', p

    for name, launch, filename in [('copy', 'COPY CON J.TXT', 'J.TXT'),
                                   ('edlin', 'EDLIN E.TXT', 'E.TXT')]:
        p = start()
        p.line(launch)
        if name == 'edlin':
            p.line('I')
        p.keys('ZENKAKU')
        p.reading('nihongo')
        p.keys('HENKAN')
        p.shot('candidate')
        p.keys('KETTEI', 'RETURN', 'F10', 'RETURN', 'ZENKAKU')
        if name == 'edlin':
            p.line('1L')
            p.shot('list')
            p.line('E')
        p.line(f'TYPE {filename}')
        p.shot('type')
        yield name, p


def run_case(args, case):
    model, ram, mode, name, plan = case
    work = args.output / f'{model}-{ram}' / mode.lower() / name
    work.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(args.disk, work / 'disk.d88')
    (work / 'run.debug').write_text(plan.script(mode), encoding='ascii')
    (work / 'run.ini').write_text(f'[NekoProjectII]\nMain_RAM={ram}\nMain_RAM_Auto=true\n',
                                 encoding='ascii')
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')
    with (work / 'run.log').open('wb') as log:
        subprocess.run([args.vaeg, '--model', model, '--roms', args.roms, '--cfg', 'run.ini',
                        '--no-bkupmem', '--nowait', '--fdd1', 'disk.d88', '--debug-script',
                        'run.debug', '--debug-output-dir', '.'], cwd=work, env=env, stdout=log,
                       stderr=subprocess.STDOUT, timeout=240, check=True)
    with (work / 'events.tsv').open(newline='', encoding='ascii') as stream:
        events = list(csv.DictReader(stream, delimiter='\t'))
    if not events or events[-1]['event'] != 'exit':
        raise RuntimeError(f'{work}: script did not reach exit')
    recorded = [event['id'] for event in events if event['event'] == 'capture']
    if recorded != plan.shots:
        raise RuntimeError(f'{work}: expected captures {plan.shots}, recorded {recorded}')
    if 'ROM set not found' in (work / 'run.log').read_text(errors='replace'):
        raise RuntimeError(f'{work}: missing ROM set')
    for shot in plan.shots:
        suffixes = ('.tvram.bin', '.screen.bmp') if args.screens else ('.tvram.bin',)
        for suffix in suffixes:
            artifact = work / (shot + suffix)
            if not artifact.is_file() or not artifact.stat().st_size:
                raise RuntimeError(f'{artifact}: missing or empty capture')
    return len(recorded)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('vaeg', 'roms', 'disk', 'output'):
        parser.add_argument(name, type=lambda value: Path(value).resolve())
    parser.add_argument('--cistat', required=True, help='VAIO CISTAT segment:offset from the tested build')
    parser.add_argument('--case', action='append', help='run only this scenario (repeatable)')
    parser.add_argument('--screens', action='store_true', help='also save screen BMPs in scratch')
    parser.add_argument('--jobs', type=int, default=6)
    args = parser.parse_args()
    if args.output.is_relative_to(ROOT):
        parser.error('output must be outside the repository')
    if args.output.exists():
        parser.error('output must be a new directory')
    if not re.fullmatch(r'[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}', args.cistat):
        parser.error('--cistat must be a hexadecimal segment:offset')
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    plans = dict(scenarios(args.cistat, args.screens))
    unknown = set(args.case or ()) - plans.keys()
    if unknown:
        parser.error(f'unknown cases: {", ".join(sorted(unknown))}; available: {", ".join(plans)}')
    cases = [(model, ram, mode, name, p) for model, ram in MATRIX for mode in MODES
             for name, p in plans.items() if args.case is None or name in args.case]
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(run_case, args, case) for case in cases]
        total = 0
        for (model, ram, mode, name, _), future in zip(cases, futures):
            shots = future.result()
            total += shots
            print(f'{model:3} {ram:3} KiB  {mode}  {name:6}  exit; {shots:2} TVRAM shots', flush=True)
    print(f'{len(cases)} cases reached exit; {total} TVRAM shots')


if __name__ == '__main__':
    main()
