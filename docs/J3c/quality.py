#!/usr/bin/env python3
"""Decode system-row candidates and focus from scratch TVRAM; print Markdown."""
from pathlib import Path
import re
import struct
import sys

from run import CORPUS, MATRIX, MODES
from m75_scsi_harness import HEADER, decode_screen


def decode_word(word):
    # vaeg saves V3 character words (JIS row index, JIS column byte),
    # not the original DOS bytes. Invert that mapping to Shift-JIS.
    row, col = word & 0xff, (word >> 8) - 0x20
    if word >> 8 == 0:
        if 0x20 <= row <= 0x7e or 0xa1 <= row <= 0xdf:
            return bytes([row]).decode('cp932')
        return '?'
    if not (1 <= row <= 94 and 1 <= col <= 94):
        return '?'
    lead = (row + 1) // 2 + (0x80 if row < 63 else 0xc0)
    trail = col + ((0x3f if col < 64 else 0x40) if row & 1 else 0x9e)
    return bytes((lead, trail)).decode('cp932', errors='replace')


def cells(path):
    data = path.with_suffix('.tvram.bin').read_bytes()
    if data[:8] != HEADER:
        raise ValueError(f'invalid TVRAM capture: {path}')
    header = 44 + struct.unpack_from('<I', data, 12)[0]
    attrs = struct.unpack_from('<I', data, header - 24)[0]
    row = header + 25 * 160
    words = struct.unpack_from('<80H', data, row)
    return [(decode_word(word), data[row + attrs + i * 2])
            for i, word in enumerate(words)
            if not (i and word == (words[i-1] | 0x8000))]


def candidate(path, mode):
    row = cells(path)
    if mode == 'ROM':
        # 50h = focused, 60h = nonfocused. Stale key labels are outside
        # the contiguous candidate at the beginning of the system row.
        end = next(i for i, (char, attr) in enumerate(row)
                   if attr not in (0x50, 0x60) or char in (' ', '?'))
        chars = ''.join(char for char, _ in row[:end])
        start = next((i for i, (_, attr) in enumerate(row[:end]) if attr == 0x50), None)
        if start is None:
            return None
        stop = next((i for i in range(start, end) if row[i][1] != 0x50), end)
        return chars, (start, stop)
    text = ''.join(char for char, _ in row).rstrip()
    if not text.startswith('[C] '):
        return None
    text = text[4:]
    found = re.search(r'\[([^\[\]]+)\]', text)
    if not found:
        return text, None
    return text[:found.start()] + found[1] + text[found.end():], (
        found.start(), found.end() - 2)


def checked(path, mode):
    value = candidate(path, mode)
    assert value and value[0] and not set(value[0]) & {'?', '\ufffd'}, path
    return value


def verify_mode(path, mode):
    marker = 'JFP on (ROM fallback: default file missing).' if mode == 'ROM' else 'Project FEP on.'
    assert any(marker in s for s in decode_screen(path / 'enabled.tvram.bin')['lines']), path


def main(root):
    cols = [(f'{model}-{ram}', mode) for model, ram in MATRIX for mode in MODES]
    print('| Reading | Expected | ' + ' | '.join(f'{d} {m}' for d, m in cols) + ' |')
    print('|---' * (2 + len(cols)) + '|')
    for word, expected in CORPUS:
        values = []
        for d, mode in cols:
            case = root / d / mode.lower() / f'quality-{word}'
            verify_mode(case, mode)
            captures = [checked(case / f'candidate-{i:02d}', mode)[0] for i in range(1, 11)]
            rank = next((i for i, text in enumerate(captures, 1) if text == expected), '>10')
            values.append(f'{captures[0]} / {rank}')
        print(f'| {word} | {expected} | ' + ' | '.join(values) + ' |')

    print('\n| Reading | Configuration | Mode | Focus walk (first candidate, then Right × 6) |')
    print('|---|---|---|---|')
    for word, _ in CORPUS[-2:]:
        for d, mode in cols:
            case = root / d / mode.lower() / f'segments-{word}'
            verify_mode(case, mode)
            values = []
            for shot in range(7):
                text, span = checked(case / f'focus-{shot}', mode)
                if span:
                    lo, hi = span
                    text = text[:lo] + '[' + text[lo:hi] + ']' + text[hi:]
                if not values or values[-1] != text:
                    values.append(text)
            print(f'| {word} | {d} | {mode} | ' + ' → '.join(values) + ' |')


if __name__ == '__main__':
    main(Path(sys.argv[1]))
