#!/usr/bin/env python3
"""Check the J3a gate from scratch captures; no ROM or state dumps are inputs."""
import re
import struct
import sys
from pathlib import Path

from PIL import Image
from m75_scsi_harness import decode_screen
from readfile import raw_image, read_file

PROMPT = 'A:\\>'
NIHON = bytes.fromhex('93 fa 96 7b')


def tvram(path):
    return path.with_suffix('.tvram.bin')


def screen(path):
    return [s.rstrip('? ') for s in decode_screen(tvram(path))['lines']]


def relevant(path):
    return [line for line in screen(path) if line]


def label_pixels(path):
    with Image.open(path.with_suffix('.screen.bmp')) as bmp:
        return bmp.convert('RGB').crop((0, bmp.height-16, 640, bmp.height)).tobytes()


def words(path, row):
    data = tvram(path).read_bytes()
    header = 44 + struct.unpack_from('<I', data, 12)[0]
    return struct.unpack_from('<80H', data, header + row * 160)


def label_words(path):
    return words(path, 25)  # Full 25-row main allocation precedes the system row.


def disk(path):
    return raw_image((path / 'disk.d88').read_bytes())


def get(path, filename):
    return read_file(disk(path), filename)


def memory(path, total=655360):
    text = '\n'.join(screen(path))
    assert f'{total} total bytes memory' in text, text
    return int(re.search(r'(\d+) bytes free\b', text)[1])


def regression(r, total=655360):
    def s(p):
        return screen(r / p)

    def v(p):
        return relevant(r / p)

    assert any('File(s)' in line for line in v('dir/first'))
    assert v('dir/recalled')[-1] == PROMPT + 'DIR' and s('dir/first') == s('dir/end')
    for name in ('eof-1', 'eof-2', 'eof-3', 'ctrl-z'):
        assert get(r / name, 'T.TXT') == b'ABC\r\nDEF\r\n'
        assert v(name + '/end')[-3:] == ['ABC', 'DEF', PROMPT]
    for name in ('typed', 'backspace', 'end'):
        # Same editor output; the build identity in the banner differs.
        assert s('base-regression/' + name)[1:] == s('after-regression/' + name)[1:]
    assert v('after-regression/backspace')[-1] == PROMPT + 'VER'
    assert v('after-regression/end')[-2:] == ['MS-DOS Version 4.00', PROMPT]
    assert v('cancel-break/cancelled')[-1] == PROMPT + 'XY\\'
    assert v('cancel-break/recalled')[-1].strip() == 'VER'
    assert v('cancel-break/break')[-2].endswith('^C')
    assert v('cancel-break/end')[-2:] == ['MS-DOS Version 4.00', PROMPT]
    print('1. J0.3 steps 1/5/9: 8/8 (three F10 cold boots, exact T.TXT bytes)')

    base = label_pixels(r / 'base-boot/prompt')
    assert len(s('display/boot')) == 24 and v('display/boot')[-1] == PROMPT
    assert label_pixels(r / 'display/held') != base
    for name in ('after-boot/prompt', 'display/boot', 'display/released', 'display/dir',
                 'display/type', 'display/cls', 'display/redirected', 'erase/clear-mark',
                 'erase/home-mark', 'toggle/show-block', 'toggle/show-byte', 'toggle/show'):
        assert label_pixels(r / name) == base, name
    assert v('display/type')[0] == 'TYPE LINE 19'
    assert v('display/type')[-2:] == ['TYPE LINE 40', PROMPT]
    assert v('display/cls') == [PROMPT] and s('display/cls')[1] == PROMPT
    assert get(r / 'display', 'F.TXT') == b'\x1b[2J\x1b[H'
    assert s('erase/clear-mark')[0] == 'CLEARED' and s('erase/home-mark')[0] == 'HOMERED'
    for which in ('block', 'byte'):
        assert len(s('toggle/hide-' + which)) == 25
        assert not any(label_pixels(r / ('toggle/hide-' + which)))
        assert len(s('toggle/show-' + which)) == 24
    assert s('toggle/pre') == s('toggle/hide')[:24]
    assert s('toggle/scroll') == [f'LINE #{i:02d}' for i in range(7, 31)] + ['']
    assert s('toggle/show') == s('toggle/scroll')[1:]
    print('1. J0.4 steps 1–5: 10/10 (current clear+home behavior)')

    listing = get(r / 'j1-key', 'KEY.OUT')
    io = get(r / 'j1-key', 'IO.SYS')
    offset = io.index(b'\xfe C1  \x1bS\0')
    tab = io[offset:offset + 386]
    slots = [tab[i:i+16] for i in range(0, 320, 16)] + [tab[i:i+6] for i in range(320, 386, 6)]
    names = ([f'F{i}' for i in range(1, 11)] + [f'SF{i}' for i in range(1, 11)] +
             'ROLLUP ROLLDOWN INS DEL UP LEFT RIGHT DOWN HOME HELP SHOME'.split())
    def escaped(slot):
        return ''.join(chr(c) if 32 <= c <= 126 and c != 92 else
                       ('\\\\' if c == 92 else f'\\x{c:02X}') for c in slot.split(b'\0', 1)[0])
    assert listing == ''.join(f'{name}  {escaped(slot)}\r\n' for name, slot in zip(names, slots)).encode()
    print('1. KEY: 1/1 (31/31 entries matching IO.SYS)')
    # The prior runner decodes half-width kana in addition to its normal JIS path.
    lines = (r / 'type/result0.txt').read_text().splitlines()[1:]
    assert [s[3:].strip() for s in lines if s[3:].strip()][-4:] == [
        'ASCII [abc 123] / ひらがな / カタカナ',
        '漢字 [表 ソ 能] / ＡＢＣ１２３ / ﾊﾝｶｸｶﾅ', 'mix:A表BｶCソD能E', PROMPT]
    print('1. J2a step 1: 1/1')
    before, after = [memory(r / f'{name}-mem/chkdsk', total) for name in ('base', 'after')]
    print(f'1. CHKDSK: 2/2 ({total} total; free {before} → {after}, {after-before:+d} bytes)')
    return after


def jfp(d, free):
    def v(p):
        return relevant(d / p)

    normal = label_pixels(d / 'prompt/boot')
    assert 'JFP default-file open failed; plain CON input.' in v('prompt/missing')
    assert label_pixels(d / 'prompt/missing') == normal
    assert 'JFP on (ROM fallback: default file missing).' in v('prompt/enabled')
    assert v('prompt/candidate')[-1] == PROMPT + 'echo'
    assert v('prompt/confirm')[-1] == PROMPT + 'echo 日本'
    assert v('prompt/echo')[-3:] == [PROMPT + 'echo 日本', '日本', PROMPT]
    print('2. Prompt: 1/1 (ECHO 日本; strict missing-file path also checked)')

    assert v('files/type')[-3:] == [PROMPT + 'TYPE J.TXT', '日本', PROMPT]
    payload = get(d / 'files', 'J.TXT')
    assert payload == NIHON + b'\r\n'
    print('3. COPY CON / F10 / TYPE: 1/1 (J.TXT = ' + payload.hex(' ') + ')')

    assert any(line.startswith('日本 ') for line in v('files/dir'))
    raw = disk(d / 'files')
    entries = [raw[p:p+32] for p in range(5*1024, 11*1024, 32)]
    entry, = [e for e in entries if e[:11] == NIHON.ljust(11)]
    cluster, size = struct.unpack_from('<HI', entry, 26)
    pos = (11 + cluster - 2) * 1024
    assert size == 4 and raw[pos:pos+size] == b'x \r\n'
    print('4. DIR / root name: 1/1 (93 fa 96 7b padded to 11 bytes)')

    assert any(re.fullmatch(r'\s+1:\*日本', line) for line in v('edlin/insert'))
    assert any(re.fullmatch(r'\s+1: 日本', line) for line in v('edlin/list'))
    assert v('edlin/type')[-3:] == [PROMPT + 'TYPE E.TXT', '日本', PROMPT]
    payload = get(d / 'edlin', 'E.TXT')
    assert payload == NIHON + b'\r\n\x1a'
    print('5. EDLIN I / 1L / E / TYPE: 1/1 (E.TXT = ' + payload.hex(' ') + ')')

    assert v('edit/bs')[-1] == PROMPT + 'echo'
    assert v('edit/bs-confirm')[-1] == PROMPT + 'echo あ'
    assert screen(d / 'edit/pending-f1') == screen(d / 'edit/bs')
    assert label_words(d / 'edit/pending-f1') == label_words(d / 'edit/bs')
    for which in ('esc', 'ctrl-c'):
        assert v('edit/' + which)[-1] == PROMPT + 'echo あ'
        assert label_pixels(d / ('edit/' + which)) == normal
    assert v('edit/submit')[-3:] == [PROMPT + 'echo あ', 'あ', PROMPT]
    assert v('edit/idle-ctrl-c')[-2:] == [PROMPT + '^C', PROMPT]
    assert v('prompt/template-f1')[-1] == PROMPT + 'e'
    assert v('prompt/template-f3')[-1] == PROMPT + 'echo 日本'
    lines = screen(d / 'prompt/kanji-bs')
    y = max(i for i, line in enumerate(lines) if line)
    row = words(d / 'prompt/kanji-bs', y)
    assert lines[y] == PROMPT + 'echo 日' and row[11:13] == (32, 32), row[:14]
    print('6. Editing: 6/6 (reading BS, ESC, Ctrl-C incl. idle, pending F1, F1/F3 template, two-column BS)')

    for name in ('enabled', 'zenkaku', 'confirm', 'echo'):
        assert label_pixels(d / ('prompt/' + name)) == normal
    assert label_pixels(d / 'prompt/candidate') != normal
    y = max(i for i, line in enumerate(screen(d / 'prompt/confirm')) if line)
    assert label_words(d / 'prompt/candidate')[:4] == words(d / 'prompt/confirm', y)[9:13]
    for name in ('hidden', 'hidden-again'):
        assert len(screen(d / ('edit/' + name))) == 25
        assert not any(label_pixels(d / ('edit/' + name)))
    for name in ('reserved', 'bs', 'deferred-hide'):
        assert len(screen(d / ('edit/' + name))) == 24
        assert screen(d / ('edit/' + name))[0] == screen(d / 'edit/hidden')[0]
    assert label_pixels(d / 'edit/deferred-hide') == normal
    print('7. Labels: 2/2 (shown/overwritten/restored; reserved row for hidden + deferred hide)')

    assert 'JFP off; plain CON input.' in v('prompt/off')
    for name in ('off', 'off-release', 'disabled'):
        assert label_pixels(d / ('prompt/' + name)) == normal
    assert label_pixels(d / 'prompt/off-shift') != normal
    assert v('prompt/disabled')[-3:] == [PROMPT + 'ECHO PLAIN', 'PLAIN', PROMPT]
    print('8. Disable: 1/1 (plain prompt, normal/Shift label restoration)')

    assert v('byte-api/waiting')[-1] == 'FIRST'
    assert v('byte-api/done')[-2:] == ['PASS: JFP bytes, status and flush', PROMPT]
    payload = b''.join(b'\x1b'+bytes([c]) for c in b'STUVWEJPQZ')
    payload += b'dir a:\rdir b:\rcopy del ren chkdsk a:\rchkdsk b:\rtype date\rtime\r'
    payload += b'\x1bP\x1bD\x0b\x08\x0c\x0a\x1a\x0b\x08\x0c\x0a\x1e\x0b\x08\x0c\x0a\x08\x1b\x03'
    for width in ('narrow', 'wide'):
        lines = v(width+'-keys/raw')
        i = lines.index('Raw CON (q exits):')
        assert lines[-1] == PROMPT
        assert bytes.fromhex(''.join(lines[i+1:-1])) == payload
    assert v('key-memory/defined')[-1] == PROMPT + 'abc'
    assert label_words(d / 'key-memory/defined')[4:10] == tuple(b'\xfeNEW--')
    assert memory(d / 'key-memory/memory') == free
    print('Supplemental: exact 43-tap streams in narrow and wide; DBCS peek/flush with no file calls; KEY F1; no extra enabled CHKDSK memory cost')


if __name__ == '__main__':
    enabled, plain = map(Path, sys.argv[1:3])
    for model in ('va', 'va2'):
        print('\n' + model.upper())
        after = regression(plain / model)
        jfp(enabled / model, after)
        print('Gate: 35/35')
