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
ap.add_argument('--graph-probe', type=Path, help='add GRAPHROM.COM for the graph-mode check')
ap.add_argument('--rom-write', type=Path, help='add J2d direct BIOS and long scrolling fixtures')
args = ap.parse_args()
output = args.output.resolve()
if output.is_relative_to(ROOT):
    ap.error('output must be outside the repository')
files = [('WRAPTEST.COM', args.wraptest.read_bytes()),
         ('EDGELONG.TXT', b'A'*79 + b'TX' + b'B'*78 + b'UZ\r\n' + b'C'*79 + b'T\r\nDONE\r\n')]
files += [(f'Q{i:07}.BIN', b'') for i in range(1, 12)]
if args.escape_probe:
    files.append(('ESCPROBE.COM', args.escape_probe.read_bytes()))
if args.graph_probe:
    files.append(('GRAPHROM.COM', args.graph_probe.read_bytes()))
if args.rom_write:
    files.extend([('ROMWRITE.COM', args.rom_write.read_bytes()),
                  ('MANY.TXT', b''.join(f'TYPE LINE {i:02}\r\n'.encode() for i in range(1, 41)))])
    files.extend((f'R{i:07}.BIN', b'') for i in range(1, 41))
(pack_va if args.model == 'va' else pack_nec)(args.image, output, files)
