#!/usr/bin/env python3
"""Pause CON with a pending candidate, queue real keys, then resume."""
from pathlib import Path
import sys

import gate
from quality import candidate

# VAIO listing (DOS code), immediately after INT 82h in CISTAPRIM/CISTAG.
SENSE = '1000:0AF2'
GET = '1000:0AFD'
SPACE_CASES = ('plain', 'shift-held', 'shift-released', 'shift-late',
               'ctrl-held', 'ctrl-released', 'grph-held', 'grph-released')
TWO_SPACE_CASES = ('two-spaces', 'two-spaces-shift-late')
CPU_STATE = 'ax bx cx dx si di bp sp ds es ss cs flags'.split()


def plans(pc, screens):
    for name in (*SPACE_CASES, *TWO_SPACE_CASES, 'henkan-released', 'reference'):
        p = gate.run.Plan(pc, screens)
        p.line('JFP ON')
        p.line('POLL')
        p.keys('ZENKAKU', *'KANJI', 'HENKAN')
        p.shot('previous')
        p.keys('HENKAN')
        p.shot('before')
        if name == 'reference':
            p.keys('HENKAN')
            p.shot('next')
            p.keys('HENKAN')
            p.shot('next-twice')
            yield name, p
            continue
        p.event('key-down CTRL', 40)
        p.event('key-up CTRL', 40)
        mod, _, mode = name.partition('-')
        mod = 'SHIFT' if mod == 'henkan' else mod.upper()
        if mode in ('held', 'released'):
            p.event(f'key-down {mod}', 20)
        p.keys('HENKAN' if name == 'henkan-released' else 'SPACE')
        if name == 'two-spaces':
            p.event('key-down SHIFT', 20)
            p.keys('SPACE')
            p.event('key-up SHIFT', 40)
        elif name == 'two-spaces-shift-late':
            p.keys('SPACE')
            mod, mode = 'SHIFT', 'late'
        if mode == 'released':
            p.event(f'key-up {mod}', 40)
        if mode == 'late':
            p.event(f'key-down {mod}', 20)
        p.event('key-down KANA', 0)
        for i in range(1, 3 if name in TWO_SPACE_CASES else 2):
            for func, addr in (('sense', SENSE), ('get', GET)):
                shot = f'{func}-{i}'
                p.event(f'wait-pc {addr} 1\ncapture {shot} registers tvram', 0)
                p.shots.append(shot)
        p.shot('after')
        p.event('key-up KANA', 40)
        if mode in ('held', 'late'):
            p.event(f'key-up {mod}', 40)
        yield name, p


def registers(path):
    return dict(line.split('\t', 1) for line in path.read_text().splitlines())


def check(root):
    for model, ram in gate.run.MATRIX:
        d = root / f'{model}-{ram}/delayed'

        def cand(case, shot):
            value = candidate(d / case / shot, 'FEP')
            assert value, (model, case, shot)
            return value

        previous, before, nxt, twice = (cand('reference', s) for s in
                                       ('previous', 'before', 'next', 'next-twice'))
        assert len({previous, before, nxt, twice}) == 4, model
        plain_regs = {func: registers(d / 'plain' / f'{func}-1.registers.tsv')
                      for func in ('sense', 'get')}
        for name in (*SPACE_CASES, *TWO_SPACE_CASES, 'henkan-released'):
            code = 'a520' if name == 'henkan-released' else '3420'
            assert cand(name, 'before') == before, (model, name)
            two = name in TWO_SPACE_CASES
            expected = twice if two else previous if name == 'henkan-released' else nxt
            assert cand(name, 'after') == expected, (model, name, expected)
            if two:
                assert cand(name, 'sense-2') == nxt, (model, name)
            for i in range(1, 3 if two else 2):
                for func in ('sense', 'get'):
                    regs = registers(d / name / f'{func}-{i}.registers.tsv')
                    assert regs['ax'] == code, (model, name, func, regs)
                    if func == 'sense':
                        assert not int(regs['flags'], 16) & 1, (model, name, regs)
                    if name in SPACE_CASES:
                        diff = [reg for reg in CPU_STATE if regs[reg] != plain_regs[func][reg]]
                        assert not diff, (model, name, func, diff)
        print(model, 'delayed polling PASS:', before[0], '->', nxt[0], '->', twice[0],
              '(two Spaces); queued Shift+HENKAN ->', previous[0])


if __name__ == '__main__':
    if sys.argv[1] == 'check':
        check(Path(sys.argv[2]))
    else:
        gate.run.main(plans, ('DELAYED',))
