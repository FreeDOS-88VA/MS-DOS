#!/usr/bin/env python3
"""Run the J2b and J2c gates. Arguments and environment match esc-run.py."""
import importlib.util
import os
import re
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('esc', here / 'esc-run.py')
esc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(esc)
j04 = esc.j04


def scenarios():
    for name, image, script in esc.scenarios():
        if name == 'display':
            # CON queries the BIOS cursor before each glyph. Let the bottom
            # part of TYPE finish before sampling CISTAT (also used mid-write).
            def delay(match):
                frame = int(match[2])
                return f'{match[1]} {frame + (900 if frame >= 3200 else 0)}'
            script = re.sub(r'^(wait-frame|limit-frame) (\d+)$', delay, script, flags=re.M)
        yield name, image, script
    for mode, command in [('block', 'WRAPTEST'), ('split', 'WRAPTEST B')]:
        events = [(600, f'input-line {command}'), (1600, 'shot p01')]
        for n in range(2, 8):
            frame = 1600 + 240*(n-1)
            events += [(frame-200, 'key-tap SPACE 3'), (frame, f'shot p{n:02}')]
        yield f'wrap-{mode}', 'test', j04.plan(j04.AFTER_PC, events)
    for name, command in [('type-edge', 'TYPE EDGELONG.TXT'), ('dir-wide', 'DIR /W Q*.BIN')]:
        yield name, 'test', j04.plan(j04.AFTER_PC, [(600, f'input-line {command}'), (2900, 'shot result')])


if __name__ == '__main__':
    if Path(sys.argv[6]).resolve().is_relative_to(here.parents[1]):
        raise SystemExit('run output must be outside the repository')
    j04.BASE_PC = os.environ['BASE_CISTAT']
    j04.AFTER_PC = os.environ['AFTER_CISTAT']
    j04.scenarios = scenarios
    j04.main()
