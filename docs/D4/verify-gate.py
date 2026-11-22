#!/usr/bin/env python3
"""Validate D4 emulator gate artifacts produced in an external scratch directory.

Pass the scratch directory as the only argument. Set PYTHONPATH to the
msdos4-va builder experiment for its D88 reader and MZ image converter.
"""
import importlib.util
from pathlib import Path
import re
import sys

from build import mz_image
from readfile import raw_image, read_file

DOCS = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(DOCS / d) for d in ('D1', 'D2')]
from copy_gate import screen

spec = importlib.util.spec_from_file_location('fatcheck', DOCS / 'D2/check-nec-fat12.py')
fatcheck = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fatcheck)


def verify(scratch):
    source = raw_image((scratch / 'boot.d88').read_bytes())
    ipl = mz_image((scratch / 'build/vahdboot.exe').read_bytes())
    expected = {n: read_file(source, n) for n in ('IO.SYS', 'MSDOS.SYS', 'COMMAND.COM')}
    expected.update({'RESULT.TXT': read_file(source, 'MARK.TXT'),
                     'AUTOEXEC.BAT': read_file(source, 'HDAUTO.BAT'),
                     'CONFIG.SYS': b'BREAK=ON \r\n'})
    print('model\tMB\tinstall\tboot_copy_chkdsk_reboot\tchkdsk_free_clusters\t'
          'final_free_clusters\tfiles_match\tFATs_match')
    for model in ('va', 'va2'):
        cases = [(n, 'raw') for n in (5, 10, 20, 40)] + [(10, 'mounted'), (10, 'sys')]
        for size, mode in cases:
            run = scratch / f'm3-{model}-{size}-{mode}'
            again, copy = (screen(run / f'{stage}.tvram') for stage in ('again', 'copy'))
            image = (run / 'disk.hdi').read_bytes()
            mb, _, free, files = fatcheck.check(image)
            assert image[4096:5120] == ipl and mb == size, run
            assert files == expected, (run, set(files), files.get('CONFIG.SYS'))
            assert all(s in copy for s in ('bytes total disk space', 'D2 READ MARKER', 'C>')), run
            assert all(s in again for s in ('D4 HDD AUTOEXEC', 'BREAK is on', 'C:\\>',
                                            'COMMAND  COM', 'RESULT   TXT')), run
            report = re.search(r'(\d+) available allocation units on disk', copy)
            assert report and int(report[1]) == free + 2, (run, report, free)
            print(model, size, mode, 'PASS', report[1], free, 'PASS', 'PASS', sep='\t')
        run = scratch / f'm3-{model}-40-raw'
        dual, floppy = (screen(run / f'{os}.tvram') for os in ('dual', 'floppy'))
        assert all(s in dual for s in ('D4 HDD AUTOEXEC', 'Directory of  D:\\', 'C:\\>')), model
        assert all(s in floppy for s in ('D4 FLOPPY AUTOEXEC', 'A:\\>', 'D2 READ MARKER')), model
        bad = screen(scratch / f'unrecognized-{model}/sys.tvram')
        assert 'Target is not a mounted NEC-layout SASI volume' in bad, model


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
