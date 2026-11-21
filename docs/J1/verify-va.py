#!/usr/bin/env python3
"""Check the cold-run J1 captures, including all filesystem and regression gates."""
import argparse
from pathlib import Path

from PIL import Image

from check import EXPECTED, OPS, contents
from media import PAIRS
from readfile import raw_image, read_file


def filesystems(gate, test):
    old_files, old_dirs = contents(test)

    def disk(name):
        files, dirs = contents(gate / name / 'disk.d88')
        assert files.keys() >= old_files.keys() and dirs >= old_dirs
        assert all(files[k] == v for k,v in old_files.items())
        return {k:v for k,v in files.items() if k not in old_files}, dirs - old_dirs

    files, dirs = disk('j1-api')
    expected = {(p+b'D',) for p in PAIRS} | {(b'J1WILD',)}
    assert dirs == expected, dirs ^ expected
    names = {(p+b'D',p+b'B.TXT') for p in PAIRS}
    wild = {(b'J1WILD',name) for name in (b'A.TXT', b'AX.TXT', PAIRS[0]+b'.TXT', PAIRS[0]+b'X.TXT')}
    assert files.keys() == names | wild | {(b'J1API.OUT',)}, files.keys() ^ (names | wild)
    r = files[b'J1API.OUT',]
    assert r[:8] == bytes.fromhex('81 9f e0 fc 00 00 51 00')
    assert r[8:-5] == EXPECTED * len(PAIRS), [(p.hex(), dict(zip(OPS, r[8+i*len(OPS):][:len(OPS)]))) for i,p in enumerate(PAIRS)]
    assert r[-5:] == bytes.fromhex('0f 02 0b 08 04')
    print('6300h + country: 81 9f e0 fc 00 00 / 81; FindFirst/Next masks (* ? ?? ?X ??X): 0f 02 0b 08 04')
    print('INT 21h path/file/dir, FCB and raw FAT12 bytes: 7/7 pair variants')

    files, dirs = disk('j1-shell')
    sd = {(b'S'+p,) for p in PAIRS}
    other = {(b'J1DEL',), (b'J1PIPE',)}
    assert dirs == sd | other, dirs
    sc = {(b'S'+p,p+b'B.TXT') for p in PAIRS}
    logs = {(b'J1DEL',name) for name in (b'ALL.OUT', b'ONE.OUT', b'TWO.OUT')}
    pipe = (b'J1PIPE', PAIRS[5]+b'.TXT')
    assert files.keys() == sc | logs | {pipe}, files.keys()
    assert all(files[k] == b'MARK\r\n' for k in sc | {pipe})
    screen = (gate/'j1-shell'/'done0.txt').read_text().splitlines()[1:]
    assert sum(row[3:] == 'MARK' for row in screen) == len(PAIRS), screen
    for name in (b'ALL.OUT', b'ONE.OUT', b'TWO.OUT'):
        raw = files[b'J1DEL',name]
        for word in (PAIRS[0], b'AB'):
            assert (word + b' ' in raw) == (name != b'ONE.OUT'), (name, raw)
    clean, dirs = disk('j1-clean')
    assert dirs == other and clean == {k:v for k,v in files.items() if k not in sc}
    print('COMMAND: 7/7 create/open/rename and 7/7 cleanup; 817c redirection operand intact')
    print('DIR * and ?? list both names; ? lists neither. DEL ? leaves both; DEL ?? removes both.')

    for name in ('bs','esc'):
        files, dirs = disk('j1-'+name)
        assert not dirs and files == {(b'J1LINE.OUT',):b'\x02XY\r'}, files
    print('AH=0Ah redirected Backspace and ESC D: both return 02 58 59 0d')

    assert 'SHARE already installed' in (gate/'j1-share'/'done1.txt').read_text()
    share_files, share_dirs = disk('j1-share')
    api_files, api_dirs = disk('j1-api')
    assert share_files == api_files and share_dirs == api_dirs
    print('Supplemental: SHARE installs and the API run yields identical results with it resident')


def regressions(gate, reg):
    def lines(case):
        return [l[3:].rstrip() for l in (reg/(case+'.txt')).read_text().splitlines()[1:]]

    def relevant(case):
        return [l for l in lines(case) if l]

    def row(case):
        with Image.open(reg/(case+'.screen.bmp')) as im:
            return im.convert('RGB').crop((0, im.height-16, 640, im.height)).tobytes()

    def guest_file(dirpath, filename):
        return read_file(raw_image((dirpath/'disk.d88').read_bytes()), filename)

    assert any('34 File(s)' in line for line in lines('dir/first'))
    assert relevant('dir/recalled')[-1] == 'A:\\>DIR' and lines('dir/first') == lines('dir/end')
    for k in ('eof-1', 'eof-2', 'eof-3', 'ctrl-z'):
        assert guest_file(reg/k, 'T.TXT') == b'ABC\r\nDEF\r\n'
        assert relevant(k+'/end')[-3:] == ['ABC', 'DEF', 'A:\\>']
    for k in ('typed','backspace','end'):
        assert lines('base-regression/'+k) == lines('after-regression/'+k)
    assert relevant('after-regression/typed')[-1] == 'A:\\>VERX'
    assert relevant('after-regression/backspace')[-1] == 'A:\\>VER'
    assert relevant('after-regression/end')[-2:] == ['MS-DOS Version 4.00', 'A:\\>']
    assert relevant('cancel-break/cancelled')[-1] == 'A:\\>XY\\'
    assert relevant('cancel-break/recalled')[-1].strip() == 'VER'
    assert relevant('cancel-break/break')[-2].endswith('^C')
    assert relevant('cancel-break/end')[-2:] == ['MS-DOS Version 4.00', 'A:\\>']
    print('J0.3: DIR/F3/Enter, F10 COPY CON on three cold boots, Ctrl-Z COPY CON, BS/VER, Ctrl-X and Ctrl-C')

    default = row('display/boot')
    assert row('base-boot/prompt') == row('after-boot/prompt') == default
    assert len(lines('display/boot')) == 24 and relevant('display/boot')[-1] == 'A:\\>'
    assert row('display/held') != default and row('display/released') == default
    assert relevant('display/type')[0] == 'TYPE LINE 19'
    assert relevant('display/type')[-2:] == ['TYPE LINE 40', 'A:\\>']
    assert relevant('display/cls') == ['A:\\>'] and lines('display/cls')[1] == 'A:\\>'
    assert guest_file(reg/'display', 'F.TXT') == b'\x1b[2J\x1b[H'
    assert relevant('erase/clear-mark') == ['CLEARED'] and lines('erase/clear-mark')[-1] == 'CLEARED'
    assert relevant('erase/home-mark') == ['HOME', 'CLEARED'] and lines('erase/home-mark')[0] == 'HOME'
    for k in ('dir/first', 'dir/end', 'display/dir', 'display/type', 'display/cls',
              'display/redirected', 'erase/clear-mark', 'erase/home-mark'):
        assert row(k) == default, k
    for method in ('block','byte'):
        assert len(lines('toggle/hide-'+method)) == 25 and not any(row('toggle/hide-'+method))
        assert len(lines('toggle/show-'+method)) == 24 and row('toggle/show-'+method) == default
    assert lines('toggle/pre') == lines('toggle/hide')[:24]
    assert lines('toggle/scroll') == [f'LINE #{i:02d}' for i in range(7, 31)] + ['']
    assert lines('toggle/show') == lines('toggle/scroll')[1:] and row('toggle/show') == default
    print('J0.4: 24+1 labels, Shift/release, DIR/TYPE, CLS/redirected CLS/bytewise markers, hide/show and reflow')

    # Compare KEY stdout with the default table embedded in the unchanged IO.SYS.
    io = guest_file(gate/'j1-key', 'IO.SYS')
    offset = io.index(b'\xfe C1  \x1bS\0')
    table = io[offset:offset+386]
    assert len(table) == 386
    names = ([f'F{i}' for i in range(1, 11)] + [f'SF{i}' for i in range(1, 11)] +
             'ROLLUP ROLLDOWN INS DEL UP LEFT RIGHT DOWN HOME HELP SHOME'.split())
    slots = [table[i:i+16] for i in range(0,320,16)] + [table[i:i+6] for i in range(320,386,6)]
    def printable(slot):
        return ''.join(chr(c) if 32 <= c <= 126 and c != 92 else
                       ('\\\\' if c == 92 else f'\\x{c:02X}') for c in slot.split(b'\0',1)[0])
    assert guest_file(gate/'j1-key', 'KEY.OUT') == ''.join(
        f'{n}  {printable(s)}\r\n' for n,s in zip(names,slots)).encode()
    print('KEY: all 31 entries identical to the default IO.SYS table')
    for phase, mem in [('base', 531872), ('after', 530432)]:
        text = (gate/(phase+'-mem')/'chkdsk.txt').read_text()
        assert '655360 total bytes memory' in text and f'{mem} bytes free' in text
    print('CHKDSK: 531872 -> 530432 bytes free (-1440); 655360 bytes total')


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    for arg in ('gate', 'reg', 'test'):
        ap.add_argument(arg, type=Path)
    args = ap.parse_args()
    for m in ('va','va2'):
        print(m.upper())
        filesystems(args.gate/m, args.test)
        regressions(args.gate/m, args.reg/m)
