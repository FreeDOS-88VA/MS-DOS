#!/usr/bin/env python3
"""Populate a scratch J2a disk with the builder's FAT/D88 helpers via J1."""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'docs/J1'))
from media import PAIRS, batch, pack_nec, pack_va

TEXT = ('ASCII [abc 123] / ひらがな / カタカナ\r\n'
        '漢字 [表 ソ 能] / ＡＢＣ１２３ / ﾊﾝｶｸｶﾅ\r\n'
        'mix:A表BｶCソD能E\r\n').encode('cp932')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('model', choices=('va', 'nec'))
    for arg in ('image', 'output', 'sjisout', 'j1dbcs'):
        parser.add_argument(arg, type=Path)
    parser.add_argument('--regressions', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.is_relative_to(ROOT):
        parser.error('output must be outside the repository')
    make = [b'@ECHO OFF', b'MD J2DIR', b'CD J2DIR']
    make += [b'COPY \\SJIS.TXT ' + pair + b'B.TXT' for pair in PAIRS]
    make += [b'CD \\']
    files = [('SJISOUT.COM', args.sjisout.read_bytes()), ('SJIS.TXT', TEXT),
             ('J2MAKE.BAT', batch(make)), ('J1DBCS.COM', args.j1dbcs.read_bytes()),
             ('NOERASE.IN', b'X\x95\\Y\r\n'), ('BS.IN', b'X\x95\\\x08Y\r\n')]
    if args.regressions:
        files.extend((name, (args.regressions / name).read_bytes()) for name in
                     ('LABELCHK.COM', 'LONG.TXT', 'CONKEY.COM'))
    (pack_va if args.model == 'va' else pack_nec)(args.image, output, files)
