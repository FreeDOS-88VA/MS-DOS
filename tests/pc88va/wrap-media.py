#!/usr/bin/env python3
"""Add pending-wrap fixtures to scratch NEC or VA test media."""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'docs/J1'))
from media import pack_nec, pack_va

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('model', choices=('nec', 'va'))
for arg in ('image', 'output', 'wraptest'):
    ap.add_argument(arg, type=Path)
ap.add_argument('--escape-probe', type=Path, help='add ESCPROBE.COM if not already present')
args = ap.parse_args()
output = args.output.resolve()
if output.is_relative_to(ROOT):
    ap.error('output must be outside the repository')
files = [('WRAPTEST.COM', args.wraptest.read_bytes()),
         ('EDGELONG.TXT', b'A'*79 + b'TX' + b'B'*78 + b'UZ\r\n' + b'C'*79 + b'T\r\nDONE\r\n')]
files += [(f'Q{i:07}.BIN', b'') for i in range(1, 12)]
if args.escape_probe:
    files.append(('ESCPROBE.COM', args.escape_probe.read_bytes()))
(pack_va if args.model == 'va' else pack_nec)(args.image, output, files)
