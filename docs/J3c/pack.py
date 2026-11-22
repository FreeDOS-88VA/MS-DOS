#!/usr/bin/env python3
"""Add test-only files to a disposable project gate D88, never a NEC disk."""
import argparse
from pathlib import Path

from run import ROOT
from media import pack_va
from readfile import raw_image, read_file


REGRESSION_FILES = ('LABELCHK.COM', 'LONG.TXT', 'CONKEY.COM')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base', type=Path)
    parser.add_argument('output', type=lambda s: Path(s).resolve())
    parser.add_argument('files', nargs='*', type=Path)
    parser.add_argument('--reg-from', type=Path, help='take the named J0 regression fixtures from this project disk')
    args = parser.parse_intermixed_args()
    if args.output.is_relative_to(ROOT) or args.output.exists():
        parser.error('output must be a new path outside the repository')
    files = [(p.name, p.read_bytes()) for p in args.files]
    if args.reg_from:
        reference = raw_image(args.reg_from.read_bytes())
        files.extend((n, read_file(reference, n)) for n in REGRESSION_FILES)
    pack_va(args.base, args.output, files)


if __name__ == '__main__':
    main()
