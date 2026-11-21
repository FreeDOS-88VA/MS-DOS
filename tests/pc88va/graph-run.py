#!/usr/bin/env python3
"""Run the J2c graph and regression gates. Arguments match wrap-run.py."""
import importlib.util
import os
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('wrap', here / 'wrap-run.py')
wrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wrap)
j04 = wrap.j04


def scenarios():
    yield from wrap.scenarios()
    yield 'graph', 'test', j04.plan(j04.AFTER_PC, [
        (600, 'input-line GRAPHROM N'), (1600, 'shot codes'),
        (1650, 'key-down SHIFT'), (1740, 'shot held'),
        (1800, 'key-up SHIFT'), (1900, 'shot released'),
        (2000, 'key-tap SPACE 3'), (2250, 'shot hidden'),
        (2300, 'key-tap SPACE 3'), (2550, 'shot shown'),
        (2600, 'key-tap SPACE 3'), (2850, 'shot kanji'),
        (2900, 'key-tap SPACE 3'), (3150, 'shot done'),
    ])
    yield 'graph-literal', 'test', j04.plan(j04.AFTER_PC, [
        (600, 'input-line GRAPHROM'), (1600, 'shot codes'),
        (1680, 'key-tap SPACE 3'), (1950, 'shot done'),
    ])


if __name__ == '__main__':
    if Path(sys.argv[6]).resolve().is_relative_to(here.parents[1]):
        raise SystemExit('run output must be outside the repository')
    j04.BASE_PC = os.environ['BASE_CISTAT']
    j04.AFTER_PC = os.environ['AFTER_CISTAT']
    j04.scenarios = scenarios
    j04.main()
