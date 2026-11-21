#!/usr/bin/env python3
"""Run J2a plus the requested J0 regressions with the J0.4 vaeg harness."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('j04', ROOT / 'docs/J0.4/run-va.py')
j04 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(j04)
# From the MS-DOS 4 IO.SYS listing, physical entry at 1000h:offset.
j04.BASE_PC = '1000:06B4'
j04.AFTER_PC = '1000:06B5'
original = j04.scenarios
original_cell = j04.decode_screen.__globals__['decode_cell']


def decode_cell(raw, offset):
    lo, hi = raw[offset:offset+2]
    if hi == 0 and 0xa1 <= lo <= 0xdf:
        return bytes([lo]).decode('cp932'), 1
    try:
        return original_cell(raw, offset)
    except UnicodeDecodeError:  # The upstream ASCII/JIS probe cannot decode gaiji.
        return '?', 1


j04.decode_screen.__globals__['decode_cell'] = decode_cell


def scenarios():
    for name, image, script in original():
        if name not in ('native-U', 'native-V', 'fkeys'):
            yield name, image, script
    pc = j04.AFTER_PC
    for name, commands in (
        ('type', ['TYPE SJIS.TXT']), ('wrap', ['SJISOUT W']),
        ('split', ['SJISOUT S']), ('invalid', ['SJISOUT I']),
        ('pending-cls', ['SJISOUT C']), ('escape-replay', ['SJISOUT R']),
        ('native', ['SJISOUT P']), ('dir-kanji', ['J2MAKE', 'DIR J2DIR']),
        ('noerase', ['J1DBCS L < NOERASE.IN']), ('bs', ['J1DBCS L < BS.IN']),
        ('j1-key', ['KEY > KEY.OUT']),
    ):
        events = []
        for i, command in enumerate(commands):
            events += [(600 + 2800*i, f'input-line {command}'),
                       (3100 + 2800*i, f'shot result{i}')]
        yield name, 'test', j04.plan(pc, events)
    yield 'gaiji', 'test', j04.plan(pc, [
        (600, 'input-line SJISOUT G'), (1500, 'shot registered'),
        (1550, 'key-tap SPACE 3'), (1750, 'shot restored'),
    ])


if __name__ == '__main__':
    j04.scenarios = scenarios
    j04.main()
