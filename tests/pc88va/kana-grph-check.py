#!/usr/bin/env python3
"""Check the K1 gate's TVRAM and FAT results from before/after runs."""
from pathlib import Path
import re
import runpy
import sys

check = runpy.run_path(str(Path(__file__).resolve().parents[2] / 'docs/J3a/check.py'))
relevant, words, get = (check[k] for k in ('relevant', 'words', 'get'))
KANA = bytes.fromhex('B1 B2 B3 61')
BODY = bytes.fromhex('61 61 61 C1 B1 B2 B3 A8 61')
GRPH = bytes.fromhex('9E 9C F7 80')
EDITING = bytes.fromhex('1B 50 1B 44 0B 08 0C 0A 1A 0B 08 0C 0A 1E 0B 08 0C 0A 08 1B 03')
KEYS = (
    (0x1D61, 0), (0x1D61, 0), (0x1D61, 0), (0x1DC1, 8),
    (0x03B1, 8), (0x12B2, 8), (0x04B3, 8), (0x12A8, 9),
    (0x1D61, 0), (0x1D9E, 0x10), (0x109C, 0x10), (0x0AF7, 0x10),
    (0x2980, 0x10), (0x3420, 0x10), (0x1D61, 0), (0x1C0D, 0),
)


def bios_trace(shot, rom):
    rows = relevant(shot)
    start = max(i for i, row in enumerate(rows) if row.startswith('TRACE: '))
    fields = rows[start][7:]
    for row in rows[start+1:]:
        if not re.fullmatch('[0-9A-F ]+', row):
            break
        fields += row
    actual = bytes.fromhex(fields.replace(' ', ''))
    expected = bytearray()
    for pair, shift in KEYS:
        word = pair.to_bytes(2, 'little')
        expected += b'\x0a' + word + bytes((0, 0, shift))
        if rom:
            expected += b'\x01' + word[:1] + b'\0' + word + bytes((shift,))
            expected += b'\x00' + word[:1] + b'\0' + word + bytes((shift,))
        else:
            expected += b'\x09' + word + bytes((0, 0, shift))
    assert actual == expected, (shot, actual.hex())
    return len(actual) // 6


def dosbytes(shot):
    line = [row[7:] for row in relevant(shot) if row.startswith('BYTES: ')][-1]
    result = bytes.fromhex(line)
    assert result[0] == len(result) - 2, (shot, result)
    return result[1:]


def byte_rows(shot):
    return [bytes(w & 255 for w in words(shot, i)).rstrip(b' \0') for i in range(24)]


def soft_bytes(shot):
    rows = relevant(shot)
    start = rows.index('Raw CON (q exits):') + 1
    return bytes.fromhex(''.join(rows[start:-1]))


def probes(root, fixed):
    tag = 'K1' if fixed else 'base'
    for mode in ('plain', 'on', 'off', 'rom'):
        d = root / mode
        for screen_mode in ('kanji', 'graph'):
            graph = screen_mode == 'graph'
            expected = BODY + (GRPH if graph or not fixed else b'') + b' a\r'
            lengths = []
            for api in ('line', 'raw'):
                shot = d / f'{screen_mode}-{api}'
                got = dosbytes(shot)
                assert got == expected, (shot, got.hex())
                lengths.append(bios_trace(shot, mode == 'rom'))
            if graph:
                cells = tuple(b'EDIT>' + expected[:-1])
                shot = d / 'graph-line'
                assert any(words(shot, i)[:len(cells)] == cells for i in range(24)), shot
            print(f'{tag:4} {mode:5} {screen_mode:5} 08h/0Ah {expected.hex(" ").upper()} (BIOS trace {max(lengths)} records)')
        d = root / ('apps-' + mode)
        messages = {'on': 'FEP を開始', 'off': 'JFP を解除', 'rom': 'JFP を開始'}
        if mode in messages:
            assert any(row.startswith(messages[mode]) for row in relevant(d / 'prompt')), d
        rows = byte_rows(d / 'prompt')
        assert rows[rows.index(b'A:\\>echo ' + KANA) + 1] == KANA, d
        for shot, name, tail in [('copy', 'J.TXT', b''), ('edlin', 'E.TXT', b'\x1a')]:
            assert get(d, name) == KANA + b'\r\n' + tail, (d, name)
            rows = byte_rows(d / shot)
            assert rows[rows.index(b'A:\\>TYPE ' + name.encode()) + 1] == KANA, (d, shot)
        print(f'{tag:4} {mode:5} ECHO/COPY CON/EDLIN/TYPE exact kana and ASCII bytes')


def regressions(base, fixed):
    for mode in ('plain', 'on', 'off', 'rom'):
        case = f'keys-{mode}/raw'
        expect = soft_bytes(base / case)
        assert expect.startswith(b'abc\x1bT\x1bU\x1bV\x1bW\x1bE\x1bJ\x1bP\x1bQ\x1bZ')
        assert expect.endswith(EDITING)
        assert soft_bytes(fixed / case) == expect, case
        print(f'{mode:5} F1–F10, Shift+F1–F10, KEY F1, editing raw stream identical ({len(expect)} bytes)')
    for key in ('bs', 'left', 'del'):
        case = f'caret-edit/{key}'
        for root in (base, fixed):
            shot = root / case
            assert dosbytes(shot) == b'A\x0bB\r', shot
            assert [row for row in byte_rows(shot) if row.startswith(b'EDIT>')][-1] == b'EDIT>A^KB', shot
    print('BS/LEFT/DEL each remove a complete caret pair (DOS 0Ah and echo cells)')
    for name, marker in [('candidate', '日本'), ('kana-reading', 'ちが')]:
        case = f'composition/{name}'
        assert words(fixed / case, 25) == words(base / case, 25), case
        assert any(word & 0x8000 for word in words(fixed / case, 25)), (case, marker)
    for name, text in [('romaji', '日本'), ('kana-confirmed', 'ちが')]:
        case = f'composition/{name}'
        for root in (base, fixed):
            assert text in relevant(root / case), (root, case, relevant(root / case))
    print('Project FEP romaji/HENKAN/KETTEI and direct kana composition unchanged')
    assert words(base / 'rom-composition/candidate', 25) == words(fixed / 'rom-composition/candidate', 25)
    for tag, root, free in (('base', base, 524032), ('K1', fixed, 524016)):
        assert '日本' in relevant(root / 'rom-composition/confirmed')
        d = root / 'graph-lead'
        assert not any(row.startswith('BYTES:') for row in relevant(d / 'first-cr')), d
        assert dosbytes(d / 'second-cr') == b'\x9e\r\r', d
        assert dosbytes(d / 'raw') == b'\x9e\r', d
        rows = relevant(root / 'memory/free')
        assert f'{free} バイトの空き' in [row.strip() for row in rows], rows
        print(f'{tag} CHKDSK: {free} bytes free')
    print('ROM JFP wide conversion unchanged; graph-mode DOS 0Ah still treats 9E as a lead')


if __name__ == '__main__':
    base, fixed = map(Path, sys.argv[1:3])
    for model in ('va', 'va2'):
        print(f'=== {model} ===')
        probes(base / model, False)
        probes(fixed / model, True)
        regressions(base / model, fixed / model)
