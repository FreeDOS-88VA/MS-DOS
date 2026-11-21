#!/usr/bin/env python3
"""Run J3b.3 in scratch, using VAIO PCs from the tested MASM listings."""
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

old = load('j3b2', 'docs/J3b.2/run.py')
wrap = load('wrap', 'tests/pc88va/wrap-run.py')

MATRIX = [('va', 640), ('va2', 256), ('va2', 640)]

def timed(p, key, name):
    if '+' in key:
        mod, key = key.split('+')
        p.event('key-down ' + mod, 1)
    else:
        mod = None
    p.event(f'key-down {key}\nwait-pc {os.environ["FEP_INT"]} 1\n'
            f'capture {name}-in registers\nwait-pc {os.environ["FEP_RET"]} 1\n'
            f'capture {name}-out registers', 4)
    p.event('key-up ' + key + (f'\nkey-up {mod}' if mod else ''), 45)


def project():
    for word in ('NIHONGO', 'KANJI', 'HENKAN', 'TOUKYOU', 'PEPEPUPU', 'A'*30):
        p = old.plan()
        p.shot('idle')
        old.echo(p, *word, narrow=True)
        p.shot('reading')
        timed(p, 'HENKAN', 'begin')
        p.shot('candidate')
        if word == 'NIHONGO':
            p.event('key-down SHIFT', 10)
            p.shot('held')
            p.event('key-up SHIFT', 10)
            timed(p, 'HENKAN', 'next')
            timed(p, 'SHIFT+HENKAN', 'prev')
            p.shot('back')
            timed(p, 'KETTEI', 'commit')
        else:
            p.keys('KETTEI')
        p.shot('confirmed')
        p.keys('RETURN')
        p.shot('echo')
        yield 'fep-' + (word.lower() if len(word) < 30 else 'full'), p

    p = old.plan()
    p.line('FEPMON')
    p.keys('ZENKAKU', *'NIHONGOWOHANASU', 'HENKAN')
    p.shot('first')
    p.keys('SHIFT+LEFT')
    p.shot('short')
    p.keys('SHIFT+RIGHT')
    p.shot('long')
    p.keys('RIGHT')
    p.shot('right')
    p.keys('HENKAN')
    p.shot('alternate')
    p.keys('LEFT')
    p.shot('left')
    for i in range(30):
        p.keys('HENKAN')
        p.shot(f'forward-{i:02d}')
    for i in range(30):
        p.keys('SHIFT+HENKAN')
        p.shot(f'backward-{i:02d}')
    p.keys('RETURN')
    p.shot('confirmed')
    p.keys('RETURN')
    p.shot('passed')
    yield 'fep-mon', p

    p = old.plan()
    p.line('FEPBYTE')
    p.keys('ZENKAKU', *'NIHONGO', 'HENKAN')
    p.shot('first-candidate')
    p.keys('KETTEI', *'NIHONGO', 'HENKAN')
    p.shot('pending')
    p.event('key-down SHIFT', 40)
    p.event('key-up SHIFT', 40)
    p.shot('second')
    p.keys(*'NIHONGO', 'HENKAN', 'KETTEI')
    p.shot('flushed')
    p.keys(*'KANJI', 'HENKAN')
    p.shot('before-edit')
    p.keys('A')
    p.shot('edited')
    p.keys('KETTEI')
    p.frame += 100
    p.shot('passed')
    yield 'fep-api', p

    for name, start, size in [('copy', 'COPY CON J.TXT', 'J'), ('edlin', 'EDLIN E.TXT', 'E')]:
        p = old.plan()
        p.line(start)
        if name == 'edlin':
            p.line('I')
        p.keys('ZENKAKU', *'NIHONGO', 'HENKAN', 'RETURN', 'RETURN', 'F10', 'RETURN', 'ZENKAKU')
        if name == 'edlin':
            p.shot('insert')
            p.line('1L')
            p.shot('list')
            p.line('E')
        p.line(f'TYPE {size}.TXT')
        p.shot('type')
        yield 'fep-' + name, p

    for name, p in old.scenarios():
        if name == 'layout-mode':
            yield 'fep-layout', p

    p = old.plan()
    old.echo(p, *'NIHONGO', narrow=True)
    p.keys('RETURN')
    p.shot('plain-confirmed')
    p.keys('RETURN')
    p.shot('plain-echo')
    yield 'fep-return', p


def plan_script(p):
    return '\n'.join(['debug-script 1', f'limit-frame {p.frame + 300}', *p.body, 'exit', ''])


def main():
    vaeg, roms, base, final, test, output = [Path(arg).resolve() for arg in sys.argv[1:7]]
    if output.is_relative_to(ROOT):
        raise SystemExit('scratch must be outside the repository')
    wrap.j04.BASE_PC = os.environ['BASE_CISTAT']
    wrap.j04.AFTER_PC = os.environ['AFTER_CISTAT']
    images = {'base': base, 'after': final, 'test': test}
    wanted = set('base-boot after-boot base-mem after-mem dir display toggle erase eof-1 eof-2 '
                 'eof-3 ctrl-z cancel-break base-regression after-regression type j1-key'.split())
    scenarios = {name: (image, script) for name, image, script in wrap.scenarios() if name in wanted}
    for i in (1, 2):
        scenarios[f'extra-eof-{i}'] = scenarios[f'eof-{i}']
    scenarios.update((f'rom/{name}', ('test', plan_script(p))) for name, p in old.j3a.scenarios()
                     if name in ('prompt', 'edit'))
    scenarios.update((name, ('test', plan_script(p))) for name, p in project())
    selected = sys.argv[7:]
    cases = [(model, ram, n, *rest) for model, ram in MATRIX for n, rest in scenarios.items()
             if not selected or n in selected]
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')

    def run(case):
        model, ram, name, image, script = case
        out = output / f'{model}-{ram}' / name
        out.mkdir(parents=True)
        shutil.copyfile(images[image], out / 'disk.d88')
        (out / 'run.debug').write_text(script)
        (out / 'run.ini').write_text(f'[NekoProjectII]\nMain_RAM={ram}\nMain_RAM_Auto=true\n')
        with (out / 'run.log').open('wb') as log:
            subprocess.run([vaeg, '--model', model, '--roms', roms, '--cfg', 'run.ini',
                            '--no-bkupmem', '--nowait', '--fdd1', 'disk.d88', '--debug-script',
                            'run.debug', '--debug-output-dir', '.'], timeout=240, check=True,
                           cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT)
        events = (out / 'events.tsv').read_text().splitlines()
        expected = set(re.findall(r'^capture (\S+)', script, re.M))
        captured = {event.split('\t')[2] for event in events if event.startswith('capture\t')}
        assert events[-1].startswith('exit\t') and expected == captured, (out, expected - captured)
        for dump in out.glob('*.tvram.bin'):
            screen = wrap.j04.decode_screen(dump)['lines']
            dump.with_name(dump.name.replace('.tvram.bin', '.txt')).write_text(
                f'main rows={len(screen)}\n' + '\n'.join(f'{i:02d} {s.rstrip("? ")}'
                                                        for i, s in enumerate(screen, 1)) + '\n')
        print(model, ram, name, flush=True)

    with ThreadPoolExecutor(6) as pool:
        list(pool.map(run, cases))

if __name__ == '__main__':
    main()
