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


def row_scenario():
    events = []
    for arg, start in ((2, 600), (5, 7800)):
        task = [(0, f'input-line ROWSMODE {arg}'), (600, 'shot pending'),
                (660, 'key-tap SPACE 3'), (900, 'shot hidden'),
                (960, 'key-tap SPACE 3'), (1200, 'shot clear'),
                (1260, 'key-tap SPACE 3'), (1600, 'input-line TYPE MANY.TXT'),
                (2900, 'shot type'), (2960, 'input-line DIR R*.BIN'),
                (4200, 'shot dir'), (4260, 'input-line CLS'), (4570, 'shot cls'),
                (4630, r'input-line KEY F1 echo KEY-OK\r'),
                (5010, 'key-tap F1 3'), (5100, 'shot key'),
                (5160, 'input-line JFP ON'), (5640, 'shot jfp')]
        task += [(5700+40*i, f'key-tap {key} 3')
                 for i, key in enumerate((*'ECHO', 'SPACE', 'ZENKAKU', *'NIHONGO'))]
        task += [(6280, 'shot reading'), (6340, 'key-tap KETTEI 3'),
                 (6400, 'key-tap RETURN 3'), (6460, 'key-tap ZENKAKU 3'),
                 (6520, 'shot echo'), (6600, 'input-line JFP OFF'), (7000, 'shot off')]
        events.extend((start+f, f'{cmd}-{arg}' if cmd.startswith('shot ') else cmd)
                      for f, cmd in task)
    return 'rows-mode', 'test', j04.plan(j04.AFTER_PC, events)


if __name__ == '__main__':
    if Path(sys.argv[6]).resolve().is_relative_to(here.parents[1]):
        raise SystemExit('run output must be outside the repository')
    j04.BASE_PC = os.environ['BASE_CISTAT']
    j04.AFTER_PC = os.environ['AFTER_CISTAT']
    j04.scenarios = lambda: (*scenarios(), row_scenario())
    j04.main()
