#!/usr/bin/env python3
"""M1: real DOS batch command tails and exact FAT readback on vaeg."""
from pathlib import Path
import sys

from media import pack_va
import run
from checks import j3a


def sj(s):
    return s.encode('cp932')


def record(reading, word):
    r, w = sj(reading), sj(word)
    return bytes((len(r), len(w))) + r.ljust(60, b'\0') + w.ljust(60, b'\0')


FIRST = ('なかた', '中田')
SECOND = ('ぴーしー', 'ＰＣ－８８ＶＡ')
HEADER = b'JFPUD\x01'


def cmd(op, pair):
    return f'JFP {op} {" ".join(pair)}'


def files():
    batch = ['@ECHO OFF', 'JFP LIST > EMPTY.TXT', 'MD SUB', 'CD SUB',
             cmd('ADD', FIRST) + ' > \\ADD.TXT',
             cmd('ADD', SECOND) + ' > \\ADD2.TXT', 'CD \\',
             cmd('ADD', FIRST) + ' > DUP.TXT',
             'JFP ADD naka あ > BAD.TXT', 'JFP ADD あ abc >> BAD.TXT',
             'JFP ADD あ >> BAD.TXT', 'JFP ADD あ 亜 亜 >> BAD.TXT',
             cmd('ADD', ('あ' * 31, '亜')) + ' > LONG.TXT',
             cmd('ADD', ('あ', '亜' * 31)) + ' >> LONG.TXT',
             'JFP LIST > BOTH.TXT', cmd('DEL', FIRST) + ' > DEL.TXT',
             cmd('DEL', FIRST) + ' > MISS.TXT', 'JFP LIST > LEFT.TXT']
    others = [('あ', chr(ord('Ａ') + i)) for i in range(8)]
    full = ['@ECHO OFF'] + [cmd('ADD', p) for p in others]
    full += [cmd('ADD', FIRST) + ' > FULL.TXT', 'JFP LIST > ALL.TXT']
    return [(name, sj('\r\n'.join(lines) + '\r\n'))
            for name, lines in [('EDTEST.BAT', batch), ('FULLTEST.BAT', full)]]


def cases(pc, screens):
    for name in ('edtest', 'fulltest'):
        p = run.Plan(pc, screens)
        p.line(name, delay=1000)
        p.shot('end')
        yield name, p


def check(root):
    def listing(*pairs):
        return b''.join(sj(f'{r} : {w}\r\n') for r, w in pairs)

    for model, ram in run.MATRIX:
        p = root / f'{model}-{ram}' / 'plain'
        edit, full = p / 'edtest', p / 'fulltest'
        get = lambda name: j3a.get(edit, name + '.TXT')
        assert get('EMPTY') == b'User dictionary empty.\r\n'
        assert get('ADD') == get('ADD2') == get('DEL') == b'User dictionary saved.\r\n'
        assert get('DUP') == b'Dictionary pair already registered.\r\n'
        assert get('MISS') == b'Dictionary pair not found.\r\n'
        assert get('BOTH') == listing(FIRST, SECOND)
        assert get('LEFT') == listing(SECOND)
        error = b'Expected a full-width hiragana reading and full-width word (1-30 cells each).\r\n'
        assert get('BAD') == error * 4
        assert get('LONG') == error * 2
        assert j3a.get(edit, 'JFPUSER.DIC') == HEADER + record(*SECOND)
        others = [('あ', chr(ord('Ａ') + i)) for i in range(8)]
        assert j3a.get(full, 'FULL.TXT') == b'User dictionary full (8 pairs).\r\n'
        assert j3a.get(full, 'ALL.TXT') == listing(*others)
        assert j3a.get(full, 'JFPUSER.DIC') == HEADER + b''.join(record(*p) for p in others)
        print(f'{model}-{ram}: PASS ADD/DEL/LIST, boot root, rejected duplicate/missing/invalid/oversize/full, exact FAT readback')


if __name__ == '__main__':
    action = sys.argv.pop(1)
    if action == 'pack':
        pack_va(*map(Path, sys.argv[1:]), files())
    elif action == 'run':
        run.main(cases, ('PLAIN',))
    elif action == 'check':
        check(Path(sys.argv[1]))
    else:
        raise SystemExit(f'Unknown action: {action}')
