#!/usr/bin/env python3
"""Verify direct text BIOS scrolling and both DOS row-mode interaction runs."""
import argparse
import importlib.util
from pathlib import Path

from PIL import Image

spec = importlib.util.spec_from_file_location('esc', Path(__file__).with_name('esc-check.py'))
esc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(esc)


def screen(case, name):
    with Image.open(case/f'{name}.screen.bmp') as im:
        return im.convert('RGB').crop((0, im.height-400, 640, im.height))


def lines(case, name):
    return [line[3:].rstrip() for line in (case/f'{name}.txt').read_text().splitlines()[1:]]


def scroll(case, name, height, filename):
    content = lines(case, name)
    assert len(content) == height and content[-1] == 'A:\\>', content
    if filename:
        assert content[-3].lstrip().startswith('40 File(s)'), content
        for row, i in zip(content[:-3], range(44-height, 41)):
            assert row.startswith(f'R{i:07} BIN'), (case, row, i)
    else:
        assert content[:-2] == [f'TYPE LINE {i:02}' for i in range(43-height, 41)], content


def check_direct(run):
    labels = screen(run/'after-boot', 'prompt').crop((0, 384, 640, 400)).tobytes()
    for call, prefix in [('putstr', 'P'), ('chuput', 'C')]:
        case = run/'romwrite'
        assert lines(case, call) == [f'{prefix}{i:02}' for i in range(10, 33)] + ['']
        assert screen(case, call).crop((0, 384, 640, 400)).tobytes() == labels
    for cmd in ('type', 'dir'):
        case = run/f'{cmd}-long'
        scroll(case, 'result', 24, cmd == 'dir')
        assert screen(case, 'result').crop((0, 384, 640, 400)).tobytes() == labels
    print(f'{run.name}: Putstr/Chuput lines 10–32, long TYPE and DIR, labels unchanged')


def check_rows(case):
    for arg, rows, raster in ((2, 19, 20), (5, 24, 16)):
        def view(name):
            return lines(case, f'{name}-{arg}')

        def pic(name):
            return screen(case, f'{name}-{arg}')

        def labels(name):
            return pic(name).crop((0, 400-raster, 640, 400))

        pending = view('pending')
        assert pending == ['TOP', 'SECOND'] + ['']*(rows-3) + [' '*79+'T']
        red_cell = pic('pending').crop((632, (rows-1)*raster, 640, rows*raster))
        assert (255, 0, 0) in {color for _, color in red_cell.getcolors()}
        assert view('hidden') == ['SECOND'] + ['']*(rows-3) + [' '*79+'T', 'X', ' '*79+'U']
        assert view('clear') == ['ROWS OK'] + ['']*(rows-1)
        assert esc.cursor_blink(case/f'clear-{arg}.tvram.bin') == 0
        assert labels('clear').crop((8, 0, 16, raster)).getbbox()
        fields = (16, 0, 640, raster)
        assert labels('clear').crop(fields).tobytes() == labels('pending').crop(fields).tobytes()
        for name in ('type', 'dir', 'cls'):
            assert labels(name).tobytes() == labels('pending').tobytes()
        scroll(case, f'type-{arg}', rows, False)
        scroll(case, f'dir-{arg}', rows, True)
        assert [line for line in view('cls') if line] == ['A:\\>']
        assert 'KEY-OK' in view('key') and not any('I/O error' in line for line in view('key'))
        assert any('Project FEP on' in line for line in view('jfp'))
        assert labels('reading').tobytes() != labels('jfp').tobytes()
        assert 'にほんご' in view('echo') and len(view('echo')) == rows
        assert any('JFP off' in line for line in view('off'))
        print(f'{case.parent.name}: {rows+1} rows, DSR at both bottom edges, wrap and red attr, '
              'labels/graph, erase/CLS, TYPE/DIR, KEY F1 and JFP ON')


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('runs', type=Path)
    ap.add_argument('--rows', type=Path, help='separate ROWSMODE scenario output root')
    args = ap.parse_args()
    for model in ('va', 'va2'):
        check_direct(args.runs/model)
        if args.rows:
            check_rows(args.rows/model/'rows-mode')
