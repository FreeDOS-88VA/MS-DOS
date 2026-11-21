#!/usr/bin/env python3
"""Exercise the project FEP on writable scratch disks with real VA keys."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location('j3a', Path(__file__).resolve().parents[1] / 'J3a/run.py')
j3a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(j3a)


def plan():
    p = j3a.Plan()
    p.line('JFP FEP')
    return p


def echo(p, *keys, narrow=False):
    if not narrow:
        p.keys('ZENKAKU')        # Return to ASCII for the command name.
    p.keys(*'ECHO', 'SPACE', 'ZENKAKU', *keys)


def scenarios():
    p = plan()
    p.shot('idle')
    echo(p, *'NIHONGO', narrow=True)
    p.shot('reading')
    p.event('key-down SHIFT', 40)
    p.shot('shift')
    p.event('key-up SHIFT', 40)
    p.keys('RETURN')
    p.shot('hira')
    echo(p, *'NIHONGO', 'F7')
    p.shot('f7')
    p.keys('KETTEI')
    p.shot('committed')
    p.keys('RETURN')
    p.shot('kata')
    p.event('key-down SHIFT', 40)
    p.shot('idle-shift')
    p.event('key-up SHIFT', 40)
    p.shot('idle-release')
    yield 'prompt', p

    p = plan()
    for idx, (word, special) in enumerate([('KYOU', ()), ('SSHI', ()), ('NN', ()), ('XTU', ()),
                                           ('KO', ('MINUS',)), ('N', ('SHIFT+7',)),
                                           ('SITITUHUZYALTSU', ())]):
        echo(p, *word, *special, narrow=(idx == 0))
        p.keys('RETURN')
        p.shot(f'case{idx}')
    yield 'spellings', p

    p = plan()
    echo(p, 'A', 'I', 'K', 'BS', 'BS', narrow=True)
    p.shot('bs')
    p.keys('F1', 'ZENKAKU')      # Both stay internal with a reading pending.
    p.shot('ignored')
    p.keys('KETTEI', 'K', 'ESC')
    p.shot('esc')
    p.keys('I', 'CTRL+C')
    p.shot('cancel-break')
    p.keys('RETURN', 'CTRL+C')
    p.shot('break')
    p.keys('F3')                # The same DOS template key, even in wide mode.
    p.shot('template')
    p.keys('BS')
    p.shot('erase-confirmed')
    yield 'edit', p

    p = plan()
    echo(p, *'NIHONGO', 'HENKAN', narrow=True)
    p.shot('first')
    p.keys('HENKAN')
    p.shot('next')
    p.keys('SHIFT+HENKAN')
    p.shot('prev')
    p.keys('HENKAN', 'KETTEI', 'RETURN')
    p.shot('confirmed')
    yield 'candidates', p

    p = plan()
    echo(p, narrow=True)
    p.event('key-down KANA', 40)
    p.keys('A', 'T', 'AT')       # ﾁ, ｶ, dakuten -> ちが.
    p.event('key-up KANA', 40)
    p.shot('reading')
    p.keys('RETURN')
    p.shot('confirmed')
    yield 'kana', p

    p = plan()
    p.line('COPY CON J.TXT')
    p.keys('ZENKAKU', *'NIHONGO', 'RETURN', 'F10', 'RETURN', 'ZENKAKU')
    p.line('TYPE J.TXT')
    p.shot('type')
    yield 'copy', p

    p = plan()
    p.line('EDLIN E.TXT')
    p.line('I')
    p.keys('ZENKAKU', *'NIHONGO', 'F7', 'RETURN', 'F10', 'RETURN', 'ZENKAKU')
    p.shot('insert')
    p.line('1L')
    p.shot('list')
    p.line('E')
    p.line('TYPE E.TXT')
    p.shot('type')
    yield 'edlin', p

    p = j3a.Plan()
    p.line('LABELCHK H')
    p.shot('hidden')
    p.line('JFP FEP')
    p.shot('reserved')
    p.line('JFP ROM')
    p.shot('refuse-rom')
    p.keys('ZENKAKU', 'A')
    p.shot('reading')
    p.keys('ESC', 'ZENKAKU')
    p.shot('cancelled')
    p.line('LABELCHK L')
    p.line('LABELCHK H')
    p.shot('deferred')
    p.line('CHKDSK', delay=1100)
    p.shot('memory')
    p.line('JFP OFF')
    p.shot('released')
    p.line('JFP ROM')
    p.line('JFP FEP')
    p.shot('refuse-project')
    p.line('JFP OFF')
    p.shot('rom-released')
    yield 'layout-mode', p

    p = plan()
    p.line('FEPBYTE')
    p.shot('ready')
    p.keys('ZENKAKU', *'NIHONGO')
    p.shot('first-reading')
    p.keys('KETTEI', *'SHI')
    p.shot('pending')
    p.event('key-down SHIFT', 40)
    p.event('key-up SHIFT', 40)
    p.shot('second')
    p.keys(*'NIHONGO', 'KETTEI')
    p.shot('flushed')
    p.keys('A', 'KETTEI')
    p.frame += 100              # Let COMMAND finish printing its new prompt.
    p.shot('pass')
    yield 'api', p

    p = plan()
    echo(p, *('A' * 29), *'KYOIA', narrow=True)
    p.shot('full')
    p.keys('RETURN')
    p.shot('confirmed')
    yield 'capacity', p


if __name__ == '__main__':
    j3a.scenarios = scenarios
    j3a.main()
