#!/usr/bin/env python3
"""Check J2c graph bytes, ROM glyphs, and the label-row indicator."""
import importlib.util
import sys
from pathlib import Path

from PIL import Image

spec = importlib.util.spec_from_file_location('esc', Path(__file__).with_name('esc-check.py'))
esc = importlib.util.module_from_spec(spec)


def crop(run, shot):
    with Image.open(run/f'{shot}.screen.bmp') as im:
        return im.convert('RGB').crop((0, im.height-400, 640, im.height))


spec.loader.exec_module(esc)
glyph = (0x3d29, 0xbd29)
for model in ('va', 'va2'):
    run = Path(sys.argv[1])/model
    for method in ('block', 'split'):
        for page in (13, 14):
            r = run/f'esc-{method}'
            data = esc.sjis.rows(esc.tvram(r, page))
            assert data[5][:8] == (ord('C'), 0xa6, *glyph, ord('D'), 0xa6, 0x95, 0x5c)
        print(f'{model} {method}: J2b pages 13–14 restore kanji / display high-byte ANK')
    graph = run/'graph'
    literal = run/'graph-literal'
    rows = esc.sjis.rows(graph/'codes.tvram.bin')
    for row, start in enumerate((0x80, 0x90, 0xe0, 0xf0), 1):
        assert rows[row][6:38] == tuple(x for code in range(start, start+16) for x in (code, ord('|')))
    box = (48, 16, 304, 80)
    assert crop(graph, 'codes').crop(box).tobytes() == crop(literal, 'codes').crop(box).tobytes()
    for shot, marked in [('codes', True), ('held', True), ('released', True),
                         ('hidden', False), ('shown', True), ('kanji', False), ('done', False)]:
        screen = crop(graph, shot)
        assert bool(screen.crop((8, 384, 16, 400)).getbbox()) == marked, (model, shot)
        height = len(esc.sjis.rows(graph/f'{shot}.tvram.bin'))
        assert height == (25 if shot == 'hidden' else 24), (model, shot, height)
    assert crop(graph, 'held').crop((16, 384, 640, 400)).tobytes() != crop(graph, 'codes').crop((16, 384, 640, 400)).tobytes()
    assert crop(graph, 'released').crop((0, 384, 640, 400)).tobytes() == crop(graph, 'codes').crop((0, 384, 640, 400)).tobytes()
    kanji = tuple(b'KANJI: ') + glyph + (ord('|'),)
    assert any(row[:len(kanji)] == kanji for row in esc.sjis.rows(graph/'kanji.tvram.bin'))
    print(f'{model}: all 64 graph codes match direct ROM Litout; marker survives shift/hide/show and clears after )0')
