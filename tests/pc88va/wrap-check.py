#!/usr/bin/env python3
"""Check the pending-wrap VA/VA2 captures against WRAPTEST's NEC outcomes."""
import importlib.util
import struct
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location('esc', Path(__file__).with_name('esc-check.py'))
esc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(esc)


def cursor(path):
    data = path.read_bytes()
    off = 16 + struct.unpack_from('<I', data, 12)[0]
    _, _, height, slot, sprites, _, _ = struct.unpack_from('<7I', data, off)
    y, x = struct.unpack_from('<HH', data, off+28+sprites+8*slot)
    # TSP cursor sprite coordinates in this non-interlaced 80x25 mode.
    return (y & 0x1ff)//(height//2)+1, (x & 0x3ff)//8+1


def check(run, method):
    wrap = run/f'wrap-{method}'
    p = {n: esc.sjis.rows(esc.tvram(wrap, n)) for n in range(1, 8)}
    def at(n, row, col, text):
        assert p[n][row-1][col-1:col-1+len(text)] == tuple(text.encode()), (wrap, n, row, col, text)

    for n, reports in [(1, ('04;81', '06;01', '08;81', '09;80', '10;80', '11;81', '12;81', '13;81', '14;81')),
                       (2, ('04;81', '04;81', '07;81', '08;81', '10;81', '09;81', '11;80', '12;81', '13;81'))]:
        for row, report in enumerate(reports, 15):
            at(n, row, 5, report)
    for row in (4, 5, 6, 9, 12, 13, 14, 15):
        at(1, row, 1, 'X')
    for row in (3, 4, 6, 7, 11, 12, 13, 14):
        at(1, row, 80, 'T')
    for row in (9, 10):
        at(1, row, 80, 'X')
    for row in (7, 8):  # K0 and J0 at virtual column 81 leave T intact.
        at(2, row, 80, 'T')

    glyph = (0x3d29, 0xbd29)  # VA TVRAM left and right halves of 表.
    assert p[3][2][79] == 0xfe
    assert p[3][3][:2] == p[3][6][:2] == p[3][8][78:] == glyph
    for row in (4, 7):
        at(3, row, 3, 'X')
    at(3, 6, 80, 'T')
    at(3, 10, 1, 'X')
    at(3, 15, 1, '09;81')

    labels = esc.screen(wrap, 7).crop((0, 384, 640, 400)).tobytes()
    for n, height, state in [(4, 24, 'on'), (6, 25, 'off')]:
        assert len(p[n]) == height
        at(n, 1, 1, f'KEEP TOP (labels {state})')
        at(n, 2, 1, 'SECOND')
        for row in range(3, height):
            at(n, row, 1, 'FILL')
        at(n, height, 1, 'BOTTOM')
        at(n, height, 80, 'T')
        assert cursor(esc.tvram(wrap, n)) == (height, 80)
    assert p[5][:-1] == p[4][1:]  # Exactly one scroll, on X, not on T.
    at(5, 24, 1, 'X')
    at(7, 1, 1, 'WRAPTEST DONE')
    for n in (1, 2, 3, 4, 5, 7):
        assert esc.screen(wrap, n).crop((0, 384, 640, 400)).tobytes() == labels
    assert cursor(esc.tvram(run/f'esc-{method}', 1)) == (11, 80)
    print(f'{run.name} {method}: J2b page 01 cursor, WRAPTEST 6/6 + DONE')


def output(run, name):
    return [''.join(chr(w or 32) for w in row).rstrip()
            for row in esc.sjis.rows(run/name/'result.tvram.bin')]


for model in ('va', 'va2'):
    run = Path(sys.argv[1])/model
    for method in ('block', 'split'):
        check(run, method)
    text = output(run, 'type-edge')
    first = text.index('A'*79 + 'T')
    assert text[first:first+5] == ['A'*79 + 'T', 'X' + 'B'*78 + 'U', 'Z', 'C'*79 + 'T', 'DONE']
    assert [s for s in output(run, 'dir-wide') if s.startswith('Q')] == [
        '    '.join(f'Q{n:07} BIN' for n in group) for group in (range(1, 6), range(6, 11), (11,))]
    print(f'{model}: TYPE exact 80-column break, DIR /W 5+5+1 without extra rows')
