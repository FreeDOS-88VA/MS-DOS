#!/usr/bin/env python3
"""Check J3b.2 from scratch captures and FAT bytes (not ROM dumps)."""
import importlib.util
from pathlib import Path
import re
import struct
import sys

from m75_scsi_harness import decode_cell

spec = importlib.util.spec_from_file_location('j3a', Path(__file__).resolve().parents[1] / 'J3a/check.py')
j3a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(j3a)
relevant, screen = j3a.relevant, j3a.screen
label_words, pixels = j3a.label_words, j3a.label_pixels
P = j3a.PROMPT
HIRA, KATA = 'にほんご', 'ニホンゴ'


def system_row(path):
    row = label_words(path)
    return ''.join(decode_cell(struct.pack('<H', w), 0)[0] for i, w in enumerate(row)
                   if not (i and w == (row[i-1] | 0x8000))).rstrip()


def rom_gate(d):
    def v(name):
        return relevant(d / name)

    assert 'JFP on (ROM fallback: default file missing).' in v('prompt/enabled')
    assert system_row(d / 'prompt/candidate').startswith('日本')
    assert v('prompt/candidate')[-1] == P + 'echo'
    assert v('prompt/confirm')[-1] == P + 'echo 日本'
    assert v('prompt/echo')[-3:] == [P + 'echo 日本', '日本', P]
    assert v('edit/bs')[-1] == P + 'echo'
    assert v('edit/bs-confirm')[-1] == P + 'echo あ'
    assert screen(d / 'edit/pending-f1') == screen(d / 'edit/bs')
    assert label_words(d / 'edit/pending-f1') == label_words(d / 'edit/bs')
    for name in ('esc', 'ctrl-c'):
        assert v('edit/' + name)[-1] == P + 'echo あ'
        assert pixels(d / 'edit' / name) == pixels(d / 'prompt/boot')
    assert v('edit/submit')[-3:] == [P + 'echo あ', 'あ', P]
    assert v('edit/idle-ctrl-c')[-2:] == [P + '^C', P]
    assert v('prompt/template-f1')[-1] == P + 'e'
    assert v('prompt/template-f3')[-1] == P + 'echo 日本'
    lines = screen(d / 'prompt/kanji-bs')
    y = max(i for i, line in enumerate(lines) if line)
    assert lines[y] == P + 'echo 日' and j3a.words(d / 'prompt/kanji-bs', y)[11:13] == (32, 32)
    print('2. ROM JFP prompt and editing: 7/7 (J3a steps 2 and 6)')


def project_gate(d, normal_free):
    def v(name):
        return relevant(d / name)

    def row(name):
        return system_row(d / name)

    def echo(name, string):
        assert v(name)[-3:] == [P + 'echo ' + string, string, P], (name, v(name))

    assert row('prompt/reading') == '[H] ' + HIRA
    assert v('prompt/reading')[-1] == P + 'echo'
    echo('prompt/hira', HIRA)
    assert row('prompt/f7') == '[K] ' + KATA
    assert v('prompt/committed')[-1] == P + 'echo ' + KATA
    echo('prompt/kata', KATA)
    for i, string in enumerate(('きょう', 'っし', 'ん', 'っ', 'こー', 'ん', 'しちつふじゃっ')):
        echo(f'spellings/case{i}', string)
    assert row('kana/reading') == '[H] ちが'
    echo('kana/confirmed', 'ちが')
    assert row('edit/bs') == row('edit/ignored') == '[H] あ'
    assert v('edit/bs') == v('edit/ignored') and v('edit/bs')[-1] == P + 'echo'
    for name in ('edit/esc', 'edit/cancel-break'):
        assert v(name)[-1] == P + 'echo あ'
        assert pixels(d / name) == pixels(d / 'prompt/idle')
    assert v('edit/break')[-3] == 'あ' and v('edit/break')[-2].endswith('^C')
    assert v('edit/break')[-1] == P
    assert v('edit/template')[-1] == P + 'echo あ'
    lines = screen(d / 'edit/erase-confirmed')
    y = max(i for i, line in enumerate(lines) if line)
    assert lines[y] == P + 'echo' and j3a.words(d / 'edit/erase-confirmed', y)[9:11] == (32, 32)
    print('3. Project prompt: 13/13 (hira/F7, seven spelling fixtures, direct kana, BS/ESC/Ctrl-C)')

    for stage, expected in [('first', '[1] ' + KATA), ('next', '[2] ' + HIRA), ('prev', '[1] ' + KATA)]:
        assert row('candidates/' + stage) == expected
        assert v('candidates/' + stage)[-1] == P + 'echo'
    echo('candidates/confirmed', HIRA)
    print('4. Stub HENKAN/Shift+HENKAN/confirm: 1/1')

    data = j3a.get(d / 'copy', 'J.TXT')
    assert data == HIRA.encode('shift_jis') + b'\r\n'
    assert v('copy/type')[-3:] == [P + 'TYPE J.TXT', HIRA, P]
    print('5. COPY CON / F10 / TYPE: 1/1; J.TXT =', data.hex(' '))

    assert any(re.fullmatch(r'\s+1:\*' + KATA, line) for line in v('edlin/insert'))
    assert any(re.fullmatch(r'\s+1: ' + KATA, line) for line in v('edlin/list'))
    assert v('edlin/type')[-3:] == [P + 'TYPE E.TXT', KATA, P]
    data = j3a.get(d / 'edlin', 'E.TXT')
    assert data == KATA.encode('shift_jis') + b'\r\n\x1a'
    print('6. EDLIN / TYPE: 1/1; E.TXT =', data.hex(' '))

    normal = pixels(d / 'prompt/idle')
    for name in ('prompt/hira', 'prompt/committed', 'prompt/kata', 'layout-mode/reserved',
                 'layout-mode/cancelled', 'layout-mode/deferred', 'prompt/idle-release'):
        assert pixels(d / name) == normal, name
    assert pixels(d / 'prompt/reading') == pixels(d / 'prompt/shift') != normal
    assert pixels(d / 'prompt/idle-shift') != normal
    assert len(screen(d / 'layout-mode/hidden')) == 25
    assert not any(pixels(d / 'layout-mode/hidden'))
    for name in ('layout-mode/released', 'layout-mode/rom-released'):
        assert len(screen(d / name)) == 25 and screen(d / name)[24] == P, name
        assert pixels(d / name) != normal   # Row 25 now contains DOS text, not labels.
    for name in ('layout-mode/reserved', 'layout-mode/reading', 'layout-mode/deferred'):
        assert len(screen(d / name)) == 24
        assert screen(d / name)[0] == screen(d / 'layout-mode/hidden')[0]
    assert row('layout-mode/reading') == '[H] あ'
    print('7. System row: 2/2 (labels before/during/after; deferred hide restored on OFF)')

    assert v('api/first-reading')[-1] == 'FIRST' and row('api/first-reading') == '[H] ' + HIRA
    assert v('api/pending')[-1] == 'PENDING' and row('api/pending') == '[H] し'
    assert v('api/second')[-1] == 'SECOND' and pixels(d / 'api/second') == normal
    assert v('api/flushed')[-1] == 'FLUSHED' and pixels(d / 'api/flushed') == normal
    assert v('api/pass')[-2:] == ['PASS: FEP status, bytes and flush', P]
    print('8. DOS byte API: 3/3 (status/order, pending flush, cached trail flush; width kept)')

    busy = 'Cannot select input mode. Use JFP OFF before switching.'
    assert busy in v('layout-mode/refuse-rom')
    assert busy in v('layout-mode/refuse-project')
    assert 'JFP on (ROM fallback: default file missing).' in v('layout-mode/refuse-project')
    assert j3a.memory(d / 'layout-mode/memory') == normal_free
    print(f'Supplemental: mode exclusion in both directions; project mode free {normal_free} bytes')
    full = 'あ' * 29 + 'い'
    assert row('capacity/full') == '[H] ' + full
    echo('capacity/confirmed', full)
    print('Supplemental: 30-cell limit, including atomic rejection of KYO with one cell left')


if __name__ == '__main__':
    plain, extra, rom, project = map(Path, sys.argv[1:])
    for model in ('va', 'va2'):
        print('\n' + model.upper())
        free = j3a.regression(plain / model)
        for name in ('eof-1', 'eof-2'):
            path = extra / model / name
            assert j3a.get(path, 'T.TXT') == b'ABC\r\nDEF\r\n'
            assert relevant(path / 'end')[-3:] == ['ABC', 'DEF', P]
        print('1. Two more F10 cold boots: 2/2 (five total, exact T.TXT bytes)')
        rom_gate(rom / model)
        project_gate(project / model, free)
        print('Gate: 52/52')
