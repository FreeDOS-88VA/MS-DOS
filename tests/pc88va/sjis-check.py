#!/usr/bin/env python3
"""Check J2a captures from sjis-run.py. NEC parity is a visual comparison."""
import argparse
import re
import struct
from pathlib import Path

from PIL import Image
from readfile import raw_image, read_file


def rows(path):
    data = path.read_bytes()
    assert data[:8] == b'VAEGSCN1'
    off = 16 + struct.unpack_from('<I', data, 12)[0]
    frame, _, line_height, _, _, _, size = struct.unpack_from('<7I', data, off)
    text = data[off+28:off+28+size]
    start, height, width = struct.unpack_from('<IHH', text, frame+16)
    assert line_height == 16 and width & 0x3ff == 640
    return [struct.unpack_from('<80H', text, start+160*y)
            for y in range((height & 0x1fe)//line_height)]


def main(run):
    def lines(name):
        return [line[3:].rstrip() for line in (run / (name + '.txt')).read_text().splitlines()[1:]]

    def relevant(name):
        return [line for line in lines(name) if line]

    def words(name):
        return rows(run / (name + '.tvram.bin'))

    def pixels(name):
        with Image.open(run / (name + '.screen.bmp')) as im:
            return im.convert('RGB')

    def labels(name):
        im = pixels(name)
        return im.crop((0, im.height-16, 640, im.height)).tobytes()

    def guest(case, filename):
        return read_file(raw_image((run/case/'disk.d88').read_bytes()), filename)

    print(run.name.upper())
    assert relevant('type/result0')[-4:] == [
        'ASCII [abc 123] / ひらがな / カタカナ',
        '漢字 [表 ソ 能] / ＡＢＣ１２３ / ﾊﾝｶｸｶﾅ',
        'mix:A表BｶCソD能E', 'A:\\>']
    assert relevant('wrap/result0')[-2:] == ['表Z', 'A:\\>']
    edge = words('wrap/result0')
    row = next(i for i, w in enumerate(edge) if w[:79] == (ord('A'),)*79)
    assert edge[row][-1] == 0xfe and edge[row+1][2] == ord('Z')
    assert relevant('split/result0')[-3:] == ['02: 表!', '40: ソ!', 'A:\\>']
    names = relevant('dir-kanji/result1')
    assert names[-1] == 'A:\\>'
    for c in '表ソ能申予−Ｂ':
        assert sum(line.startswith(c+'B ') and 'TXT' in line for line in names) == 1, names
    assert relevant('noerase/result0')[-2:] == ['X表Y', 'A:\\>']
    assert relevant('bs/result0')[-2:] == ['XY', 'A:\\>']
    assert guest('noerase', 'J1LINE.OUT') == b'\x04X\x95\\Y\r'
    assert guest('bs', 'J1LINE.OUT') == b'\x02XY\r'
    erased = next(w for w in words('bs/result0') if w[:2] == (ord('X'), ord('Y')))
    assert erased[2] == 0x20
    print('TYPE, FEh wrap + 表Z, split 02h / 40h, DIR seven names, and two-column erase')

    invalid = relevant('invalid/result0')
    assert invalid[-8:-3] == ['Z-CR:', 'X-LF:', '?????Y', 'DEL:[z]', 'LONE:[\\]'], invalid
    assert invalid[-1] == 'A:\\>'
    invalid_words = words('invalid/result0')
    assert any(w[:6] == (0, 0, 0, 0, 0, ord('Y')) for w in invalid_words)
    high = tuple(b'HIGH:[' + bytes.fromhex('807ca07ca17cb67cdf7cfd7cfe7cff') + b']')
    assert any(w[:len(high)] == high for w in invalid_words)
    ext = next(w for w in invalid_words if w[:5] == tuple(b'EXT:['))
    assert ext[8:14] == (0x2101, 0xa101, ord('|'), 0x2101, 0xa101, ord(']'))
    assert relevant('pending-cls/result0') == ['CLS OK', 'A:\\>']
    assert lines('pending-cls/result0')[0] == 'CLS OK'
    assert relevant('escape-replay/result0')[-2:] == ['REPLAY: [>表!', 'A:\\>']
    print('Malformed bytes recover (NEC control behavior differs); lone trail, high ANK and escape replay')

    gaiji = words('gaiji/registered')
    y = next(i for i, w in enumerate(gaiji) if w[:8] == tuple(b'Chuput: '))
    row = gaiji[y]
    assert row[8:10] == row[18:20] == (0x2156, 0xa156)
    im = pixels('gaiji/registered')
    def glyph(im, col):
        top = im.height - 400 + 16*y  # Debug capture includes top overscan.
        return im.crop((8*col, top, 8*(col+2), top+16)).tobytes()
    result = glyph(im, 8)
    assert result == glyph(im, 18) and result != glyph(pixels('gaiji/restored'), 8)
    assert relevant('gaiji/restored')[-1] == 'A:\\>'
    print('Test-only EB9Fh gaiji: equal ROM/CON glyphs, original font restored')

    assert any('File(s)' in s for s in lines('dir/first'))
    assert relevant('dir/recalled')[-1] == 'A:\\>DIR' and lines('dir/first') == lines('dir/end')
    for name in ('eof-1', 'eof-2', 'eof-3', 'ctrl-z'):
        assert guest(name, 'T.TXT') == b'ABC\r\nDEF\r\n'
        assert relevant(name+'/end')[-3:] == ['ABC', 'DEF', 'A:\\>']
    for name in ('typed', 'backspace', 'end'):
        assert lines('base-regression/'+name) == lines('after-regression/'+name)
    assert relevant('after-regression/backspace')[-1] == 'A:\\>VER'
    assert relevant('after-regression/end')[-2:] == ['MS-DOS Version 4.00', 'A:\\>']
    assert relevant('cancel-break/cancelled')[-1] == 'A:\\>XY\\'
    assert relevant('cancel-break/recalled')[-1].strip() == 'VER'
    assert relevant('cancel-break/break')[-2].endswith('^C')
    assert relevant('cancel-break/end')[-2:] == ['MS-DOS Version 4.00', 'A:\\>']
    print('J0.3 (1, 5, 9): 8/8')

    default = labels('display/boot')
    assert labels('base-boot/prompt') == labels('after-boot/prompt') == default
    assert len(lines('display/boot')) == 24 and relevant('display/boot')[-1] == 'A:\\>'
    assert labels('display/held') != default and labels('display/released') == default
    assert relevant('display/type')[0] == 'TYPE LINE 19'
    assert relevant('display/type')[-2:] == ['TYPE LINE 40', 'A:\\>']
    assert relevant('display/cls') == ['A:\\>'] and lines('display/cls')[1] == 'A:\\>'
    assert guest('display', 'F.TXT') == b'\x1b[2J\x1b[H'
    assert relevant('erase/clear-mark') == ['CLEARED'] and lines('erase/clear-mark')[-1] == 'CLEARED'
    assert relevant('erase/home-mark') == ['HOME', 'CLEARED'] and lines('erase/home-mark')[0] == 'HOME'
    for name in ('dir/first', 'dir/end', 'display/dir', 'display/type', 'display/cls',
                 'display/redirected', 'erase/clear-mark', 'erase/home-mark', 'pending-cls/result0'):
        assert labels(name) == default, name
    for method in ('block', 'byte'):
        assert len(lines('toggle/hide-'+method)) == 25 and not any(labels('toggle/hide-'+method))
        assert len(lines('toggle/show-'+method)) == 24 and labels('toggle/show-'+method) == default
    assert lines('toggle/pre') == lines('toggle/hide')[:24]
    assert lines('toggle/scroll') == [f'LINE #{i:02d}' for i in range(7, 31)] + ['']
    assert lines('toggle/show') == lines('toggle/scroll')[1:] and labels('toggle/show') == default
    print('J0.4 (1–5): 10/10')

    io = guest('j1-key', 'IO.SYS')
    offset = io.index(b'\xfe C1  \x1bS\0')
    table = io[offset:offset+386]
    slots = [table[i:i+16] for i in range(0, 320, 16)] + [table[i:i+6] for i in range(320, 386, 6)]
    names = ([f'F{i}' for i in range(1, 11)] + [f'SF{i}' for i in range(1, 11)] +
             'ROLLUP ROLLDOWN INS DEL UP LEFT RIGHT DOWN HOME HELP SHOME'.split())
    def printable(slot):
        return ''.join(chr(c) if 32 <= c <= 126 and c != 92 else
                       ('\\\\' if c == 92 else f'\\x{c:02X}') for c in slot.split(b'\0', 1)[0])
    assert guest('j1-key', 'KEY.OUT') == ''.join(
        f'{name}  {printable(slot)}\r\n' for name, slot in zip(names, slots)).encode()
    print('KEY: 31/31 default slots match (1 gate check)')
    mem = []
    for phase in ('base', 'after'):
        text = '\n'.join(lines(phase+'-mem/chkdsk'))
        assert '655360 total bytes memory' in text
        mem.append(int(re.search(r'(\d+) bytes free\b', text)[1]))
    assert mem == [530432, 530352]
    print(f'CHKDSK (2/2): {mem[0]} -> {mem[1]} free ({mem[1]-mem[0]:+d} bytes)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runs', type=Path)
    args = parser.parse_args()
    for model in ('va', 'va2'):
        main(args.runs/model)
