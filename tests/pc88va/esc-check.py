#!/usr/bin/env python3
"""Check VA TVRAM/pixels from esc-run.py; NEC parity is judged from screenshots."""
import argparse
import importlib.util
import struct
from pathlib import Path

from PIL import Image

spec = importlib.util.spec_from_file_location('sjis', Path(__file__).with_name('sjis-check.py'))
sjis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sjis)


def tvram(run, n, alt=''):
    return run / f'p{n:02}{alt}.tvram.bin'


def screen(run, n, alt=''):
    with Image.open(run / f'p{n:02}{alt}.screen.bmp') as im:
        return im.convert('RGB').crop((0, im.height-400, 640, im.height))


def blink_enabled(run, n, alt=''):
    data = tvram(run, n, alt).read_bytes()
    return struct.unpack_from('<I', data, 16 + struct.unpack_from('<I', data, 12)[0] + 20)[0]


def check(run, graph=False):
    pages = {n: sjis.rows(tvram(run, n)) for n in range(1, 27)}

    def at(n, y, x, text):
        want = tuple(text.encode('ascii'))
        assert pages[n][y-1][x-1:x-1+len(want)] == want, (run, n, y, x, text)

    def row(n, y, text):
        actual = ''.join(chr(w or 32) for w in pages[n][y-1]).rstrip()
        assert actual == text, (run, n, y, text, actual)

    for y, x, mark in [(3,10,'A'), (4,12,'B'), (1,1,'E'), (6,20,'D'), (24,11,'F'),
                       (9,80,'G'), (15,22,'X'), (1,74,'Y'), (24,35,'Z'), (11,80,'T')]:
        at(1, y, x, mark)
    for y, x, mark in [(6,20,'A'), (9,22,'B'), (7,28,'C'), (7,17,'D'), (8,24,'Z'),
                       (11,1,'X'), (11,80,'Y'), (1,25,'U'), (24,27,'V'), (1,40,'W'),
                       (24,42,'Q'), (14,28,'N'), (15,31,'P'), (15,33,'R')]:
        at(2, y, x, mark)
    at(3, 3, 7, 'S')
    row(3, 9, 'Report at (12,34): 1B 5B 31 32 3B 33 34 52')
    row(3, 11, 'Report at (2,7):   1B 5B 30 32 3B 30 37 52')

    for y, text in [(3,'K    ABCDEFG|'), (5,'0K   ABCDEFG|'), (7,'            |IJ'),
                    (9,'            |'), (11,'3K   ABCDEFG|IJ')]:
        row(4, y, text)
    for n in (5, 6):
        row(n, 4, 'ABOVE')
        row(n, 5, '0123|')
        row(n, 6, '')
    row(7, 4, '')
    row(7, 5, '    |56789')
    row(7, 6, 'BELOW')
    for n in (8, 9):
        row(n, 1, '|')
        for y in range(2, 25):
            row(n, y, '')

    # Attribute mode 0: eight foreground and reversed-background colors;
    # evaluate colors in the glyph boxes, not ROM-specific glyph pixels.
    attr = screen(run, 10)
    palette = [(r, g, b) for b in (0, 1) for g in (0, 1) for r in (0, 1)]
    for i, rgb in enumerate(palette):
        left = 24*i
        for top in (64, 96):
            colors = {tuple(val >= 128 for val in attr.getpixel((x, y)))
                      for y in range(top, top+16) for x in range(left, left+16)}
            assert rgb in colors and colors <= {rgb, (0, 0, 0)}, (run, i, top, colors)
    assert not attr.crop((16*8, 11*16, 640, 12*16)).getbbox()  # erase with reverse
    assert attr.getpixel((39, 12*16)) == (255, 0, 0)  # AFTER remains reversed red
    assert attr.getpixel((40, 12*16)) == (0, 0, 0)    # erased area is normal black
    for suffix in ('', '-alt'):
        assert blink_enabled(run, 13, suffix) == 1 and blink_enabled(run, 14, suffix) == 0
    assert screen(run, 13).crop((0, 144, 8, 160)).getbbox()
    assert not screen(run, 14).crop((0, 144, 8, 160)).getbbox()
    row(13, 8, 'EFGH')
    row(14, 8, 'EFGH')

    for n, lines in [(15, ['R04','A','R05','B','','R06','R07','R08']),
                     (16, ['R04','A06','B','','']), (17, ['R04','R0M','ED6','R07','R08'])]:
        for y, text in enumerate(lines, 4):
            row(n, y, text)
    row(18, 1, ' M')
    at(18, 23, 20, 'bottom')
    at(18, 24, 26, 'D')
    if run.name == 'esc-block':
        row(19, 3, '07       AB')
        row(19, 5, '09       A   B')
        row(19, 6, '          B')
        row(19, 7, '0B       A')
        row(19, 10, '1A       A')
    else:
        row(19, 1, 'B')
        row(19, 10, '')
    row(19, 12, '1E       A')
    row(20, 14, '0C       A B')
    for i in (*range(7), 14, 15, *range(16, 26), 28, 29, 31, 127):
        y, x = (20, 5) if i == 127 else (3 + (i//8)*4, 5 + (i%8)*10)
        assert pages[21][y-1][x-1:x+1] == (i, ord('B')), (run, i)
    row(22, 4, '[L ] [ R]')
    row(22, 6, '[')
    row(22, 8, '   ]')
    for y, text in [(3,'Z OK'), (5,'? OK'), (7,'LONG OK'), (9,'X OK'),
                    (11,'[11;20HESC OK'), (13,'OVER OK'),
                    (15,'6789012345678901234567890zHARD OK')]:  # byte 96 is replayed
        row(23, y, text)
    for n in (24, 25):
        assert len(pages[n]) == 25
        row(n, 22, '23')
        row(n, 23, 'M4')
        row(n, 24, '         BOTTOM')
    row(24, 25, '               D')
    row(25, 25, 'RO|')
    row(26, 1, 'ESCPROBE DONE')
    row(26, 3, 'A:\\>')
    labels = screen(run, 26).crop((0, 384, 640, 400))
    for n in (*range(1, 24), 26):
        assert len(pages[n]) == 24
        row_image = screen(run, n).crop((0, 384, 640, 400))
        if graph and n in (13, 14):
            # The 'g' sits in column 2; all other label pixels stay identical.
            assert row_image.crop((8, 0, 16, 16)).getbbox(), (run, n)
            row_image.paste(labels.crop((8, 0, 16, 16)), (8, 0))
        assert row_image.tobytes() == labels.tobytes(), (run, n)
    print(f'{run.parent.name} {run.name}: positions, reports, erase, color, cursor enable, scroll, '
          'C0, kanji boundaries, recovery, all label rows, and DONE checked')
    return pages


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runs', type=Path)
    parser.add_argument('--graph', action='store_true', help='expect the J2c graph indicator')
    args = parser.parse_args()
    for model in ('va', 'va2'):
        block = check(args.runs/model/'esc-block', args.graph)
        split = check(args.runs/model/'esc-split', args.graph)
        assert all(block[n] == split[n] for n in range(1, 27) if n != 19)
        print(f'{model}: 25/26 block vs. split character grids identical; control page differs as on NEC')
