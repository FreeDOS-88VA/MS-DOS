#!/usr/bin/env python3
"""Cold-boot ROM JFP checks on disposable VA and VA2 copies outside the repository."""
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import subprocess
import sys


class Plan:
    def __init__(self):
        self.frame = 600
        self.body = []

    def event(self, command, delay):
        self.body.extend((f'wait-frame {self.frame}', command))
        self.frame += delay

    def line(self, line, delay=850):
        self.event('input-line ' + line, delay)

    def keys(self, *keys):
        for key in keys:
            if '+' in key:
                mod, key = key.split('+')
                cmd = f'key-down {mod}\nkey-tap {key} 3\nkey-up {mod}'
            else:
                cmd = f'key-tap {key} 3'
            self.event(cmd, 40)

    def shot(self, name):
        pc = os.environ['AFTER_CISTAT']  # 1000h:offset from VAIO's MASM listing
        self.event(f'wait-pc {pc} 1\ncapture {name} tvram screen', 25)

    def nihon(self):
        self.keys(*'NIHON', 'HENKAN', 'KETTEI')


def scenarios():
    p = Plan()
    p.shot('boot')
    p.line('JFP ON')
    p.shot('missing')
    p.line('JFP ROM')
    p.shot('enabled')
    p.keys(*'ECHO', 'SPACE', 'ZENKAKU')
    p.shot('zenkaku')
    p.keys('N')
    p.shot('n')
    p.keys(*'IHON', 'HENKAN')
    p.shot('candidate')
    p.keys('KETTEI')
    p.shot('confirm')
    p.keys('RETURN')
    p.shot('echo')
    p.keys('F1')
    p.shot('template-f1')
    p.keys('F3')
    p.shot('template-f3')
    p.keys('BS')
    p.shot('kanji-bs')
    p.keys('RETURN', 'ZENKAKU')
    p.line('JFP OFF')
    p.shot('off')
    p.event('key-down SHIFT', 40)
    p.shot('off-shift')
    p.event('key-up SHIFT', 40)
    p.shot('off-release')
    p.keys('ZENKAKU')
    p.line('ECHO PLAIN')
    p.shot('disabled')
    yield 'prompt', p

    p = Plan()
    p.line('JFP ROM')
    p.line('COPY CON J.TXT')
    p.keys('ZENKAKU')
    p.nihon()
    p.keys('RETURN', 'F10', 'RETURN', 'ZENKAKU')
    p.line('TYPE J.TXT')
    p.shot('type')
    p.keys(*'ECHO', 'SPACE', 'X', 'SPACE', 'SHIFT+PERIOD', 'SPACE', 'ZENKAKU')
    p.nihon()
    p.keys('RETURN', 'ZENKAKU')
    p.line('DIR')
    p.shot('dir')
    yield 'files', p

    p = Plan()
    p.line('JFP ROM')
    p.line('EDLIN E.TXT')
    p.line('I')
    p.keys('ZENKAKU')
    p.nihon()
    p.keys('RETURN', 'F10', 'RETURN', 'ZENKAKU')
    p.shot('insert')
    p.line('1L')
    p.shot('list')
    p.line('E')
    p.line('TYPE E.TXT')
    p.shot('type')
    yield 'edlin', p

    p = Plan()
    p.line('LABELCHK H')
    p.shot('hidden')
    p.line('JFP ROM')
    p.shot('reserved')
    p.keys(*'ECHO', 'SPACE', 'ZENKAKU', 'A', 'I', 'BS')
    p.shot('bs')
    p.keys('F1')
    p.shot('pending-f1')
    p.keys('KETTEI')
    p.shot('bs-confirm')
    p.keys('A', 'ESC')
    p.shot('esc')
    p.keys('A', 'CTRL+C')
    p.shot('ctrl-c')
    p.keys('RETURN', 'ZENKAKU')
    p.shot('submit')
    p.keys('CTRL+C')
    p.shot('idle-ctrl-c')
    p.line('LABELCHK L')
    p.line('LABELCHK H')
    p.shot('deferred-hide')
    p.line('JFP OFF')
    p.shot('hidden-again')
    yield 'edit', p

    p = Plan()
    p.line('JFP ROM')
    p.line('JFPBYTE')
    p.keys('ZENKAKU', *'NIHON', 'HENKAN')
    p.shot('waiting')
    p.keys('KETTEI')
    p.shot('first')
    p.nihon()
    p.shot('flushed')
    p.keys('ZENKAKU', 'X')
    p.shot('done')
    yield 'byte-api', p

    for wide in (False, True):
        p = Plan()
        p.line('JFP ROM')
        p.line('CONKEY K')
        if wide:
            p.keys('ZENKAKU')
        p.keys(*(f'F{i}' for i in range(1, 11)), *(f'SHIFT+F{i}' for i in range(1, 11)))
        p.keys(*'ROLLUP ROLLDOWN INS DEL UP LEFT RIGHT DOWN HOME HELP'.split())
        p.keys(*'SHIFT+UP SHIFT+LEFT SHIFT+RIGHT SHIFT+DOWN SHIFT+HOME'.split())
        p.keys(*'CTRL+UP CTRL+LEFT CTRL+RIGHT CTRL+DOWN CTRL+HOME'.split())
        p.keys('BS', 'ESC', 'CTRL+C')
        if wide:
            p.keys('ZENKAKU')
        p.keys('Q')
        p.shot('raw')
        yield ('wide-keys' if wide else 'narrow-keys'), p

    p = Plan()
    p.line('JFP ROM')
    p.line(r'KEY F1 \xFENEW--abc')
    p.keys('F1')
    p.shot('defined')
    p.keys('CTRL+X')
    p.line('CHKDSK', delay=1100)
    p.shot('memory')
    yield 'key-memory', p


def main():
    vaeg, roms, disk, out = (Path(arg).resolve() for arg in sys.argv[1:5])
    if out.is_relative_to(Path(__file__).resolve().parents[2]):
        raise SystemExit('scratch must be outside the repository')
    wanted = sys.argv[5:]
    cases = [(model, name, p) for model in ('va', 'va2') for name, p in scenarios()
             if not wanted or name in wanted]
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')

    def run(case):
        model, name, p = case
        work = out / model / name
        work.mkdir(parents=True)
        shutil.copyfile(disk, work / 'disk.d88')
        script = ['debug-script 1', f'limit-frame {p.frame + 180}', *p.body, 'exit', '']
        (work / 'run.debug').write_text('\n'.join(script))
        with (work / 'run.log').open('wb') as log:
            subprocess.run([vaeg, '--model', model, '--roms', roms, '--no-cfg', '--no-bkupmem',
                            '--nowait', '--fdd1', 'disk.d88', '--debug-script', 'run.debug',
                            '--debug-output-dir', '.'], cwd=work, env=env, stdout=log,
                           stderr=subprocess.STDOUT, timeout=180, check=True)
        events = (work / 'events.tsv').read_text().splitlines()
        assert events[-1].startswith('exit\t'), work
        assert 'ROM set not found' not in (work / 'run.log').read_text(), work
        for cmd in script:
            if '\ncapture ' in cmd:
                shot = cmd.split('\ncapture ')[1].split()[0]
                assert (work / f'{shot}.tvram.bin').is_file(), (work, shot)
        print(model, name, flush=True)

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(run, cases))


if __name__ == '__main__':
    main()
