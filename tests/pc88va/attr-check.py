#!/usr/bin/env python3
"""Check NEC-style underline, blink and colored reverse on ESCPROBE page 10."""
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location('esc', Path(__file__).with_name('esc-check.py'))
esc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(esc)

for model in ('va', 'va2'):
    for method in ('block', 'split'):
        run = Path(sys.argv[1])/model/f'esc-{method}'
        phases = [esc.screen(run, 10, alt) for alt in ('', '-alt')]
        blink = set()
        for im in phases:
            def stripe(row, col, count, rgb):
                y = 16*row-1  # VA BIOS puts the horizontal line on the final raster.
                pixels = [im.getpixel((x, y)) for x in range(8*(col-1), 8*(col-1+count))]
                assert {tuple(v >= 128 for v in px) for px in pixels} == {rgb}, (run, row, col)

            stripe(3, 1, 7, (0, 0, 0))    # Plain 00 TEST.
            stripe(3, 17, 7, (1, 1, 1))   # SGR 4 alone.
            stripe(16, 1, 10, (1, 1, 1))  # Separate 4 starts from normal.
            stripe(16, 12, 4, (1, 0, 0))  # Combined 31;4 preserves red.
            stripe(7, 4, 2, (1, 0, 0))    # Plain reverse red fills that raster.
            stripe(9, 1, 11, (0, 0, 0))   # Reverse red + black underline.
            stripe(9, 13, 11, (0, 0, 0))  # Same, reordered parameters.
            blink.add(bool(im.crop((24*8, 32, 31*8, 48)).getbbox()))
        assert blink == {False, True}, (run, blink)
        print(f'{model} {method}: page 10 underline, reverse/colored combinations, and both blink phases')
