#!/usr/bin/env python3
"""Check J0.5 captures. PYTHONPATH must include the builder for readfile.py."""
import hashlib
from pathlib import Path
import struct
import sys

from PIL import Image
from readfile import raw_image, read_file


def guest_file(run, name):
    return read_file(raw_image((run / 'disk.d88').read_bytes()), name)


def records(data):
    assert len(data) % 808 == 0
    return [(struct.unpack_from('<4H', data, p), data[p+8:p+808])
            for p in range(0, len(data), 808)]


def main(gate, reg, nec, nec_unknown, image):
    nec = records(nec.read_bytes())
    unknown_ref, = records(nec_unknown.read_bytes())
    dflt = nec[0][1][:386]
    io = read_file(raw_image(image.read_bytes()), 'IO.SYS')
    assert len(dflt) == 386 and io.count(dflt) == 1
    print('Default compact table SHA-256:', hashlib.sha256(dflt).hexdigest())
    for model in ('va', 'va2'):
        d, r = gate/model, reg/model
        print('\n' + model.upper())

        def text(p):
            return (d/(p + '.tvram.txt')).read_text()

        def labels(p):
            data = (d/(p + '.tvram.bin')).read_bytes()
            base = 44 + struct.unpack_from('<I', data, 12)[0] + 0xfa0
            return data[base:base+160:2]

        def lines(p):
            return [l[3:].rstrip() for l in (r/(p + '.txt')).read_text().splitlines()[1:]]

        def relevant(p):
            return [l for l in lines(p) if l]

        def row(p):
            with Image.open(r/(p + '.screen.bmp')) as im:
                return im.convert('RGB').crop((0, im.height-16, 640, im.height)).tobytes()

        assert 'DCh: immediate IRET' in text('vector/vector')
        assert 'Matches DBh and DDh' in text('vector/vector')
        print('Baseline vector: immediate IRET, shared with DBh and DDh')
        va = records(guest_file(d/'api', 'DC.OUT'))
        assert len(va) == len(nec) == 20
        for ((ax, cx, axout, fl), data), (ref, refdata) in zip(va, nec):
            assert (ax, cx, axout, fl & 0xfff) == (*ref[:3], ref[3] & 0xfff)
            if ax == 0x100:
                assert data == b'\xcc'*800 and refdata == bytes(514) + b'\xcc'*286
            else:
                assert data == refdata, (model, ax, cx)
        assert va[1][1] == dflt[:16] + b'\xcc'*784
        assert va[0][1] == dflt + b'\xcc'*414
        assert va[16][1][:16] == b'ABCDEFGHIJKLMNO\0'
        assert va[16][1][16:] == va[0][1][16:]
        assert va[19][1][:16] == b'\xfeNEW  f-one\0\0\0\0\0'
        assert va[19][1][160:176] == b'\xfeSHIFTs-one\0\0\0\0\0'
        assert va[19][1][16:160] == va[0][1][16:160]
        assert va[19][1][176:] == va[0][1][176:]
        print('DCh: 19/19 compatible records (including guards, AX, low FLAGS); 0100h data-buffer case intentionally differs')
        print('Overlength: 15 bytes + NUL; rest of table and guard unchanged')
        assert 'A:\\>f-one\n' in text('api/f1') and b'NEW' in labels('api/f1')
        assert '    s-one\n' in text('api/sf1') and b'SHIFT' in labels('api/sf1')
        assert b'date\r' in labels('api/labels') and b'time\r' in labels('api/labels')
        print('Physical F1/Shift+F1: f-one and s-one with NEW/SHIFT labels; raw CR present in rendered label cells')
        u, = records(guest_file(d/'unknown', 'DC.OUT'))
        assert u == ((0x1234, 0x55ff, 0x1234, 0x247), b'\xcc'*800)
        assert (*unknown_ref[0][:3], unknown_ref[0][3] & 0xfff) == u[0]
        assert unknown_ref[1] == u[1]
        assert 'Pending input dropped, ordinary z received' in text('pending/pending')
        assert len(text('hidden-write/hidden').splitlines()) == 25
        assert len(text('hidden-write/after-write').splitlines()) == 25
        assert len(text('hidden-write/shown').splitlines()) == 24
        assert b'date\r' in labels('hidden-write/shown')
        print('Hidden write: kept 25 main rows; show restored the changed labels at row 25')
        print('Unknown CL preserves AX, low FLAGS and buffer; a write discards pending expansion')

        def printable(slot):
            out = bytearray()
            for c in slot.split(b'\0')[0]:
                out += bytes((c,)) if 32 <= c <= 126 and c != 92 else (
                    b'\\\\' if c == 92 else f'\\x{c:02X}'.encode())
            return out

        names = ([f'F{i}' for i in range(1, 11)] + [f'SF{i}' for i in range(1, 11)] +
                 'ROLLUP ROLLDOWN INS DEL UP LEFT RIGHT DOWN HOME HELP SHOME'.split())
        default_list = b''.join(name.encode() + b'  ' + printable(slot) + b'\r\n'
            for name, slot in zip(names, [dflt[i:i+16] for i in range(0, 320, 16)] +
                                       [dflt[i:i+6] for i in range(320, 386, 6)]))
        first = guest_file(d/'key-save', 'BEFORE.TXT')
        assert first == default_list and 'SHOME  \\x1E' in text('key-save/list')
        changed = dflt[:160] + b'dir b:\r'.ljust(16, b'\0') + dflt[176:]
        assert guest_file(d/'key-save', 'MY.KEY') == b'VAKEY\x01' + changed
        assert b'dir b:' in labels('key-save/key-label')[:20]
        assert 'BONLY    TXT' in text('key-save/dir-b')
        assert b'dir a:' in labels('key-load/reboot-defaults')[:20]
        assert b'dir b:' in labels('key-load/loaded-label')[:20]
        assert 'BONLY    TXT' in text('key-load/loaded-dir-b')
        final = guest_file(d/'key-load', 'AFTER.TXT')
        assert final == first.replace(b'SF1  dir a:', b'SF1  dir b:')
        assert 'KEY: not a VA key file' in text('key-load/bad-file')
        assert guest_file(d/'key-load', 'STILL.TXT') == final
        print('KEY: 31 default lines, one changed slot (exact save bytes), B: marker before and after reboot/load, invalid file rejected without mutation')

        assert any('34 File(s)' in l for l in lines('dir/first'))
        assert lines('dir/recalled')[-1] == 'A:\\>DIR' and lines('dir/first') == lines('dir/end')
        for k in ('eof-1', 'eof-2', 'eof-3', 'ctrl-z'):
            assert guest_file(r/k, 'T.TXT') == b'ABC\r\nDEF\r\n'
            assert relevant(k+'/end')[-3:] == ['ABC', 'DEF', 'A:\\>']
        for k in ('typed', 'backspace', 'end'):
            assert lines('base-regression/'+k) == lines('after-regression/'+k)
        assert relevant('after-regression/typed')[-1] == 'A:\\>VERX'
        assert relevant('after-regression/backspace')[-1] == 'A:\\>VER'
        assert relevant('after-regression/end')[-2:] == ['MS-DOS Version 4.00', 'A:\\>']
        assert relevant('cancel-break/cancelled')[-1] == 'A:\\>XY\\'
        assert relevant('cancel-break/recalled')[-1].strip() == 'VER'
        assert relevant('cancel-break/break')[-2].endswith('^C')
        assert relevant('cancel-break/end')[-2:] == ['MS-DOS Version 4.00', 'A:\\>']
        actual = bytes.fromhex(''.join(lines('fkeys/end')[4:8]))
        slots = [dflt[i:i+16] for i in range(0, 320, 16)]
        assert actual == b''.join((s[6:] if s[0] == 0xfe else s).split(b'\0')[0] for s in slots)
        print('J0.3: F3 recalled DIR; all 3 F10 EOF boots and Ctrl-Z saved ABC/DEF CRLF; BS/VER, Ctrl-X and Ctrl-C matched; 20/20 default F-key payloads')

        default = row('display/boot')
        assert len(lines('display/boot')) == 24 and relevant('display/boot')[-1] == 'A:\\>'
        assert row('display/held') != default and row('display/released') == default
        assert relevant('display/type')[0] == 'TYPE LINE 19'
        assert relevant('display/type')[-2:] == ['TYPE LINE 40', 'A:\\>']
        assert relevant('display/cls') == ['A:\\>'] and lines('display/cls')[1] == 'A:\\>'
        assert guest_file(r/'display', 'F.TXT') == b'\x1b[2J\x1b[H'
        assert relevant('erase/clear-mark') == ['CLEARED'] and lines('erase/clear-mark')[-1] == 'CLEARED'
        assert relevant('erase/home-mark') == ['HOME', 'CLEARED'] and lines('erase/home-mark')[0] == 'HOME'
        for k in ('dir/first', 'dir/end', 'display/type', 'display/cls', 'display/redirected',
                  'erase/clear-mark', 'erase/home-mark'):
            assert row(k) == default
        for method in ('block', 'byte'):
            assert len(lines('toggle/hide-'+method)) == 25
            assert not any(row('toggle/hide-'+method))
            assert len(lines('toggle/show-'+method)) == 24 and row('toggle/show-'+method) == default
        assert lines('toggle/pre') == lines('toggle/hide')[:24]
        sc = lines('toggle/scroll')
        assert sc == [f'LINE #{i:02d}' for i in range(7, 31)] + ['']
        assert lines('toggle/show') == sc[1:] and row('toggle/show') == default
        print('J0.4: 24+1 boot/Shift/release, DIR/TYPE, CLS + redirected bytes + bytewise markers, both hide/show paths and row-25 reflow')
        for phase, mem in [('base', 532160), ('after', 531872)]:
            l = lines(phase+'-mem/chkdsk')
            assert '655360 total bytes memory' in [x.strip() for x in l]
            assert f'{mem} bytes free' in [x.strip() for x in l]
        print('CHKDSK: 532160 -> 531872 free, delta -288 B (655360 total)')


if __name__ == '__main__':
    main(*map(Path, sys.argv[1:]))
