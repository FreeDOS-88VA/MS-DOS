#!/usr/bin/env python3
"""Check the raw vaeg m153 TVRAM from the D5.1 VA2 three-way boot gate."""

import argparse
import re
import struct
from pathlib import Path


def glyphs(text):
    return list(text.encode('ascii'))


def check(path, choice, release):
    dump = path.read_bytes()
    off = 16 + struct.unpack_from('<I', dump, 12)[0]
    frame, _, line_height, _, _, _, size = struct.unpack_from('<7I', dump, off)
    tvram = dump[off + 28:off + 28 + size]
    start, height, width = struct.unpack_from('<IHH', tvram, frame + 16)
    assert start == 0 and width == 640, (start, width)
    assert (height, line_height) == ((384, 16) if choice == 3 else (380, 20))

    # Check the entire main text buffer, including the rows below the PC-Engine
    # split, and the function-key line in the following row. Check both 16-bit
    # cells of each double-width glyph rather than decoding only ASCII.
    actual = [struct.unpack_from('<80H', tvram, 160 * row) for row in range(26)]
    expected = [[] for _ in actual]
    if choice == 3:
        expected[0] = [0x7c26, 0xfc26, 0x5c2b, 0xdc2b, 0x6c18, 0xec18]
        expected[0] += glyphs(f'MS-DOS version 4.00 Release {release}')
        expected[1] = glyphs('for NEC PC-88VA Series Personal Computer')
        expected[2] = glyphs('Ported by Nakata Maho')
        expected[4] = glyphs('MS-DOS Version 4.00')
        expected[5] = glyphs('C:\\>')
        expected[25] = list(b'    \xfe C1   \xfe CU   \xfe CA   \xfe S1   \xfe SU      '
                            b'\xfeVOID  \xfeNWL   \xfeINS   \xfeREP   \xfe ^Z')
    else:
        clock = bytes(actual[0][63:]).decode('ascii').replace('\0', ' ')
        assert re.fullmatch(r'\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}', clock), clock
        expected[:5] = list(map(glyphs, ('A:' + ' ' * 61 + clock, '-' * 80,
                                         'NEC PC-Engine v1.1',
                                         'Copyright (C) 1987,1988 NEC Corporation', 'Ready')))
        expected[25] = glyphs('    dir a: dir b: copy   delete rename    '
                              'chkdsk chkdsk type   date\r  time\r ')
        expected[25] += [0x3e28, 0xbe28, 0x5111, 0xd111]

    kanji_cells = 0
    for row, (got, want) in enumerate(zip(actual, expected)):
        got = list(got)
        # JIS full-width space is blank only as a complete two-cell pair.
        for col in range(79):
            if got[col:col + 2] == [0x2101, 0xa101]:
                got[col:col + 2] = [0, 0]
        kanji_cells += sum(cell > 0xff for cell in got)
        assert len(want) <= 80
        for col, cell in enumerate(got):
            expected_cell = want[col] if col < len(want) else 0
            assert cell == expected_cell or {cell, expected_cell} <= {0, 32}, (
                f'{path}: row {row}, column {col}: got {cell:#06x}, expected {expected_cell:#06x}')
    assert kanji_cells == (6 if choice == 3 else 4), kanji_cells
    print(f'{path}: PASS (choice {choice}, 26 rows, {kanji_cells} double-width glyph cells)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('choice', type=int, choices=(1, 2, 3))
    parser.add_argument('dump', type=Path)
    parser.add_argument('--release', help='DOS release suffix, e.g. "20261128 (d5, 12d39722)"')
    args = parser.parse_args()
    if args.choice == 3 and not args.release:
        parser.error('choice 3 requires --release')
    check(args.dump, args.choice, args.release)
