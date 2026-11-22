#!/usr/bin/env python3
"""Run J2d and inherited J2c scenarios; arguments match graph-run.py."""
import importlib.util
import os
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('graph', here / 'graph-run.py')
graph = importlib.util.module_from_spec(spec)
spec.loader.exec_module(graph)
j04 = graph.j04


def scenarios():
    yield from graph.scenarios()
    yield 'romwrite', 'test', j04.plan(j04.AFTER_PC, [
        (600, 'input-line ROMWRITE'), (1600, 'shot putstr'),
        (1700, 'key-tap SPACE 3'), (2500, 'shot chuput'),
        (2600, 'key-tap SPACE 3'), (2900, 'shot done'),
    ])
    for name, command in [('type-long', 'TYPE MANY.TXT'), ('dir-long', 'DIR R*.BIN')]:
        yield name, 'test', j04.plan(j04.AFTER_PC, [
            (600, f'input-line {command}'), (3500, 'shot result'),
        ])


if __name__ == '__main__':
    if Path(sys.argv[6]).resolve().is_relative_to(here.parents[1]):
        raise SystemExit('run output must be outside the repository')
    j04.BASE_PC = os.environ['BASE_CISTAT']
    j04.AFTER_PC = os.environ['AFTER_CISTAT']
    j04.scenarios = scenarios
    j04.main()
