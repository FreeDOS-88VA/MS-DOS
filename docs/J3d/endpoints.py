#!/usr/bin/env python3
"""Compare Space and HENKAN at both ends of the nihon candidate list."""
import sys
from pathlib import Path

import gate
from quality import candidate


def plans(pc, screens):
    for key in ('space', 'henkan'):
        p = gate.run.Plan(pc, screens)
        p.line('JFP ON')
        p.echo('nihon')
        p.keys(key.upper())
        p.shot('first')
        p.keys('SHIFT+HENKAN')
        p.shot('previous')
        for i in range(1, 9):
            p.keys(key.upper())
            p.shot(f'next-{i}')
        yield key, p


def report(root):
    for model, ram in gate.run.MATRIX:
        d = root / f'{model}-{ram}/endpoints'
        steps = ['first', 'previous', *(f'next-{i}' for i in range(1, 9))]
        space, henkan = [[candidate(d / key / step, 'FEP') for step in steps] for key in ('space', 'henkan')]
        assert all(space) and space == henkan
        print(model, ' '.join(c[0] for c in space))


if __name__ == '__main__':
    if sys.argv[1] == 'check':
        report(Path(sys.argv[2]))
    else:
        gate.run.main(plans, ('ENDPOINTS',))
