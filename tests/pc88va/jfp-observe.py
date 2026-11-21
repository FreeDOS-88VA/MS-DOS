#!/usr/bin/env python3
"""Summarize selected fields of private J3.0 capture states; never copy a state into Git."""
from pathlib import Path
import struct
import sys

MAGIC = b'J30PROBE-2026\0'
KB = 0xab0
JFP = 0x4400


def section(path, wanted):
    data = path.read_bytes()
    assert data[:16].rstrip(b'\0') == b'VA-EG'
    pos = 48
    while pos + 16 <= len(data):
        name, _, size = struct.unpack_from('<10sHI', data, pos)
        pos += 16
        assert pos + size <= len(data)
        if name.rstrip(b'\0') == wanted:
            return data[pos:pos + size]
        pos += (size + 15) & ~15
    raise ValueError(f'missing {wanted!r} in {path}')


def pointer(mem, at):
    off, seg = struct.unpack_from('<HH', mem, at)
    return (seg << 4) + off


def flag(mem, at):
    return 'set' if pointer(mem, at) else 'null'


def data_pointer(mem, at):
    addr = pointer(mem, at)
    if not addr:
        return 'null'
    # Only publish addresses in the documented low-RAM JFP work area.
    return f'{addr:05X}' if JFP <= addr < JFP + 0x200 else 'out-of-range'


def probe_record(mem, options, active):
    # State may also hold copies in DOS disk buffers. Require paragraph
    # alignment of the COM load and evidence that the probe actually ran.
    at = mem.rfind(MAGIC, 0x10000, 0xa0000)
    while at >= 0:
        start = at + len(MAGIC)
        phase, mode, ax, dx, nkeys, n21 = struct.unpack_from('<BB4H', mem, start)
        start += 10
        stages = mem[start:start + 16].rstrip(b'\0')
        if (at & 15 == 3 and mem[at - 3] == 0xe9
                and nkeys <= 48 and n21 <= 128 and options.startswith(stages)
                and phase in b'.NEQFBGIKRSHJTZPX'):
            if phase not in b'.N' or stages != options:
                return f'probe incomplete at {chr(phase)} (returned {stages.decode() or "none"})'
            start += 16
            calls = mem[start:start + n21]
            start += 128
            out = [f'phase={chr(phase)} GetJFP={ax:04X}/{dx:04X}', f'samples={nkeys}']
            if active or mode == ord('P'):
                out.append('INT21/AH=' + (calls.hex(' ').upper() or 'none'))
                triples = struct.iter_unpack('<4H', mem[start:start + nkeys * 8])
                out += ['unkeyed' if mode != ord('P') and not (v[1] or v[3])
                        else f'{v[0]:04X}/{v[1]:04X}>{v[2]:04X}/{v[3]:04X}' for v in triples]
            if active and options == b'RT':
                # Display only the verified result for the synthetic reading.
                candidate = mem[start + 384:start + 384 + 5]
                out.append('Sug1st=' + ('日本' if candidate == bytes.fromhex('93fa967b00') else 'other'))
            return ' '.join(out)
        at = mem.rfind(MAGIC, 0x10000, at)
    return 'no intact probe record'


def main():
    root = Path(sys.argv[1])
    for path in sorted(root.glob('*/*/*.state')):
        mem = section(path, b'MEMORY')
        callback = KB + 0x1de
        marks = (flag(mem, KB + 0x1da), flag(mem, callback), flag(mem, 0x8d * 4))
        ptrs = tuple(data_pointer(mem, at) for at in range(JFP, JFP + 0x10, 4))
        print(path.relative_to(root), *marks, *ptrs, mem[JFP + 0x10:JFP + 0x13].hex(), end='')
        if path.parent.name not in ('boot', 'dos'):
            print(' ', probe_record(mem, path.parent.name.upper().encode(), bool(pointer(mem, callback))), sep='')
        else:
            print()


if __name__ == '__main__':
    main()
