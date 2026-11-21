#!/usr/bin/env python3
"""Run J1 and the selected J0 regressions using the J0.4 vaeg harness."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location('j04', Path(__file__).resolve().parents[1] / 'J0.4/run-va.py')
j04 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(j04)
j04.BASE_PC = j04.AFTER_PC = '1000:06B4'
original = j04.scenarios


def scenarios():
    for name, image, script in original():
        if name not in ('native-U', 'native-V', 'fkeys'):
            yield name, image, script
    p = j04.AFTER_PC
    for name, commands in (
        ('j1-api', ['J1DBCS']),
        ('j1-shell', ['J1MAKE']),
        ('j1-clean', ['J1MAKE', 'J1CLEAN']),
        ('j1-bs', ['J1DBCS L < BS.IN']),
        ('j1-esc', ['J1DBCS L < ESC.IN']),
        ('j1-key', ['KEY > KEY.OUT']),
        ('j1-share', ['SHARE', 'SHARE', 'J1DBCS']),
    ):
        events = []
        for i, command in enumerate(commands):
            events += [(600 + i * 2600, f'input-line {command}'),
                       (3100 + i * 2600, f'shot done{i}')]
        yield name, 'test', j04.plan(p, events)


j04.scenarios = scenarios
j04.main()
