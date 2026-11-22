#!/usr/bin/env python3
"""M2: foreground reload, resident candidate ordering and corrupt fallback."""
from pathlib import Path
import sys

from format_gate import FIRST, SECOND, HEADER, cmd, record, sj
from media import pack_va
from checks import P, expect_echo, j3a, v
from quality import candidate
import run

THIRD = (FIRST[0], '甲')


def fixtures():
    lines = ['@ECHO OFF'] + [cmd('ADD', p) for p in (FIRST, SECOND, THIRD)]
    return [('REGTEST.BAT', sj('\r\n'.join(lines) + '\r\n')),
            ('BADTEST.BAT', b'@ECHO OFF\r\nCOPY /B BAD.UD A:\\JFPUSER.DIC\r\n'),
            ('BAD.UD', HEADER + record(*THIRD) + b'\x02')]


def kana(p, romaji):
    p.keys(*('MINUS' if c == '-' else c for c in romaji.upper()))


def reading(p, romaji, shot):
    p.keys(*'ECHO', 'SPACE', 'ZENKAKU')
    kana(p, romaji)
    p.keys('HENKAN')
    p.shot(shot)


def end_reading(p):
    p.keys('KETTEI', 'RETURN', 'ZENKAKU')


def cases(pc, screens):
    p = run.Plan(pc, screens)
    p.line('JFP FEP', 500)
    reading(p, 'nakata', 'empty')
    end_reading(p)
    p.line('REGTEST', 700)
    reading(p, 'nakata', 'not-reloaded')
    p.keys('HENKAN')
    p.shot('not-reloaded-next')
    end_reading(p)
    p.line('JFP ON', 500)
    reading(p, 'nakata', 'first')
    for key, name in [('RIGHT', 'whole'), ('SHIFT+HENKAN', 'first-prev'),
                      ('HENKAN', 'second'), ('HENKAN', 'bios-first'),
                      ('HENKAN', 'bios-next'), ('SHIFT+HENKAN', 'bios-prev'),
                      ('SHIFT+HENKAN', 'back-second'), ('SHIFT+HENKAN', 'back-first')]:
        p.keys(key)
        p.shot(name)
    end_reading(p)
    p.shot('confirmed')
    p.line('JFP OFF', 400)
    p.line('JFP FEP', 500)
    reading(p, 'pi-shi-', 'prolonged')
    p.keys('RETURN')
    p.shot('return-confirm')
    p.keys('RETURN', 'ZENKAKU')
    p.shot('prolonged-submitted')
    reading(p, 'nihongo', 'miss')
    end_reading(p)
    p.shot('miss-submitted')
    yield 'resident', p

    p = run.Plan(pc, screens)
    p.line('REGTEST', 700)
    p.line('JFP ON', 500)
    p.line('BADTEST', 500)
    p.line('JFP ON', 500)
    p.shot('rejected')
    reading(p, 'nakata', 'fallback')
    end_reading(p)
    p.line('JFP OFF', 400)
    p.line('JFP FEP', 500)
    p.shot('rejected-cold')
    reading(p, 'nakata', 'fallback-cold')
    end_reading(p)
    yield 'corrupt', p


def check(root):
    for model, ram in run.MATRIX:
        p = root / f'{model}-{ram}' / 'fep'
        r, c = p / 'resident', p / 'corrupt'
        def cand(shot):
            result = candidate(r / shot, 'FEP')
            assert result, shot
            return result
        for shot in ('first', 'whole', 'first-prev', 'back-first'):
            assert cand(shot)[0] == FIRST[1], (shot, cand(shot))
        for shot in ('second', 'back-second'):
            assert cand(shot)[0] == THIRD[1], (shot, cand(shot))
        assert cand('empty') == cand('not-reloaded') == cand('bios-first') == cand('bios-prev')
        assert cand('bios-next') != cand('bios-first')
        assert cand('not-reloaded-next') == cand('bios-next')
        assert expect_echo(r / 'confirmed', FIRST[1])
        # The emulator's JIS decoder names U+2212 for the full-width minus cell.
        minus = SECOND[1].replace('－', '−')
        assert cand('prolonged')[0] in (SECOND[1], minus)
        assert v(r / 'return-confirm')[-1] in (P + 'echo ' + SECOND[1], P + 'echo ' + minus)
        assert any(expect_echo(r / 'prolonged-submitted', w) for w in (SECOND[1], minus))
        assert cand('miss')[0] == '日本語' and expect_echo(r / 'miss-submitted', '日本語')
        for shot, fallback in [('rejected', 'fallback'), ('rejected-cold', 'fallback-cold')]:
            assert 'Invalid JFPUSER.DIC.' in v(c / shot)
            assert any('Project FEP on.' in line for line in v(c / shot))
            assert candidate(c / fallback, 'FEP') == cand('empty')
        assert j3a.get(r, 'JFPUSER.DIC') == HEADER + b''.join(record(*pair) for pair in (FIRST, SECOND, THIRD))
        print(f'{model}-{ram}: PASS registration/reload, user↔BIOS order, confirm, built-in miss, corrupt fallback')


if __name__ == '__main__':
    action = sys.argv.pop(1)
    if action == 'pack':
        pack_va(*map(Path, sys.argv[1:]), fixtures())
    elif action == 'run':
        run.main(cases, ('FEP',))
    elif action == 'check':
        check(Path(sys.argv[1]))
    else:
        raise SystemExit(f'Unknown action: {action}')
