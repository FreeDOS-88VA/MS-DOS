#!/usr/bin/env python3
"""Run the ESCPROBE pages and (optionally) J2a/J0 regressions on VA and VA2.

Use the arguments of sjis-run.py, with CISTAT from the before/after MASM
listings in BASE_CISTAT and AFTER_CISTAT (e.g. 1000:06B5), and set PYTHONPATH
as for that runner. With no scenario filter, this runs all scenarios.
"""
import importlib.util
import os
from pathlib import Path

here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('sjis', here / 'sjis-run.py')
sjis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sjis)
j04 = sjis.j04


def scenarios():
    yield from sjis.scenarios()
    for name, command in [('esc-block', 'ESCPROBE'), ('esc-split', 'ESCPROBE B')]:
        events = [(600, f'input-line {command}'), (1600, 'shot p01')]
        for n in range(2, 27):
            frame = 1600 + (n-1)*180
            events += [(frame-140, 'key-tap SPACE 3'), (frame, f'shot p{n:02}')]
            if n in (10, 13, 14):  # sample a second cursor/blink phase
                events.append((frame+25, f'shot p{n:02}-alt'))
        yield name, 'test', j04.plan(j04.AFTER_PC, events)


if __name__ == '__main__':
    import sys

    if Path(sys.argv[6]).resolve().is_relative_to(here.parents[1]):
        raise SystemExit('run output must be outside the repository')
    j04.BASE_PC = os.environ['BASE_CISTAT']
    j04.AFTER_PC = os.environ['AFTER_CISTAT']
    j04.scenarios = scenarios
    j04.main()
