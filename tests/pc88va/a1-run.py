#!/usr/bin/env python3
"""A1 vaeg gates; J0.4 runner arguments, plus CISTAT offsets in the env."""
import importlib.util
import os
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('j04', root / 'docs/J0.4/run-va.py')
j04 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(j04)


def scenarios():
    for label, var in [('base', 'BASE_CISTAT'), ('after', 'AFTER_CISTAT')]:
        yield f'{label}-mem', label, j04.plan(os.environ[var], [
            (600, 'input-line CHKDSK'), (1700, 'shot chkdsk')])
    pc = os.environ['AFTER_CISTAT']
    yield 'prn-mock', 'test', j04.plan(pc, [
        (600, 'input-line PRNMCK'), (1800, 'shot result')])
    yield 'aux-mock', 'test', j04.plan(pc, [
        (600, 'input-line AUXMCK'), (1800, 'shot result')])
    for name, arg in [('usage', '/?'), ('valid', '9600'), ('invalid', '9600x')]:
        yield f'speed-{name}', 'test', j04.plan(pc, [
            (600, f'input-line SPEED {arg}'), (1600, 'shot result'),
        ])
    yield 'prn-rom', 'test', j04.plan(pc, [
        (600, 'input-line ECHO A1>PRN'), (1200, 'shot echo'),
        (1250, 'input-line ECHO A1>A1.TXT'),
        (1800, 'input-line TYPE A1.TXT > PRN'), (2400, 'shot type'),
        (2450, 'input-line COPY A1.TXT PRN'), (3100, 'shot copy'),
        (3150, 'key-down CTRL'), (3151, 'key-tap P 3'), (3155, 'key-up CTRL'),
        (3200, 'input-line ECHO A1'), (3700, 'shot ctrlp'),
    ])


if __name__ == '__main__':
    if Path(sys.argv[6]).resolve().is_relative_to(root):
        raise SystemExit('output must be outside the repository')
    j04.scenarios = scenarios
    j04.main()
    for model in ('va', 'va2'):
        expected = {
            'prn-mock': 'PRNMCK: P', 'aux-mock': 'AUXMCK: P',
            'speed-usage': 'Usage: SPEED', 'speed-invalid': 'Usage: SPEED',
            'speed-valid': '>SPEED 9600',
        }
        for name, marker in expected.items():
            if sys.argv[7:] and name not in sys.argv[7:]:
                continue
            path = Path(sys.argv[6]) / model / name / 'result.txt'
            text = path.read_text()
            if marker not in text or (name == 'speed-valid' and (
                    'Usage: SPEED' in text or 'BIOS rejected' in text)):
                raise SystemExit(f'{path}: {name} did not pass')
