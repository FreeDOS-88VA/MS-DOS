#!/usr/bin/env python3
"""Compare D88 tracks, or run the DISKCOPY A: B: /V gate on vaeg.

PYTHONPATH: builder experiment (for the run command only).
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import struct
import subprocess


def tracks(image):
    if len(image) < 0x2b0 or struct.unpack_from('<I', image, 0x1c)[0] != len(image):
        raise ValueError('expected a single D88 image with a full track table')
    locations = struct.unpack_from('<164I', image, 0x20)
    ordered = sorted(ptr for ptr in locations if ptr)
    if len(ordered) != len(set(ordered)):
        raise ValueError('duplicate track offset')
    ends = dict(zip(ordered, ordered[1:] + [len(image)]))
    for ptr in locations:
        sectors = []
        if ptr:
            end = ends[ptr]
            if not 0x2b0 <= ptr <= end - 16:
                raise ValueError(f'invalid track offset {ptr:#x}')
            count, = struct.unpack_from('<H', image, ptr + 4)
            if not count:
                raise ValueError(f'zero sector count at {ptr:#x}')
            for _ in range(count):
                if ptr + 16 > end:
                    raise ValueError(f'truncated sector header at {ptr:#x}')
                total, = struct.unpack_from('<H', image, ptr + 4)
                size, = struct.unpack_from('<H', image, ptr + 14)
                if total != count or ptr + 16 + size > end:
                    raise ValueError(f'invalid sector extent at {ptr:#x}')
                sectors.append((image[ptr:ptr+4], image[ptr+6], image[ptr+16:ptr+16+size]))
                ptr += 16 + size
        yield sectors


def compare(source, target, skip=()):
    if source[0x1b] != target[0x1b]:
        return 'D88 media types differ'
    for track, (src, dst) in enumerate(zip(tracks(source), tracks(target), strict=True)):
        if track in skip:
            continue
        if len(src) != len(dst):
            return f'track {track:02X}: sector count {len(src)} != {len(dst)}'
        if src and not any(src == dst[j:] + dst[:j] for j in range(len(dst))):
            return f'track {track:02X}: IDs, density or data differ'
    return None


def screen(path):
    data = path.read_bytes()
    assert data[:8] == b'VAEGSCN1', path
    off = 16 + struct.unpack_from('<I', data, 12)[0]
    frame, _, line_height, _, _, _, size = struct.unpack_from('<7I', data, off)
    text = data[off+28:off+28+size]
    start, height, width = struct.unpack_from('<IHH', text, frame + 16)
    assert line_height == 16 and width & 0x3ff == 640, path
    return '\n'.join(''.join(chr(c) if 32 <= c < 127 else ' ' for c in row).rstrip()
                     for y in range((height & 0x1fe) // line_height)
                     for row in (struct.unpack_from('<80H', text, start + 160 * y),))


def run_gate(a):
    from probe import ROOT, pack_va, raw_image, read_file
    from mkd88 import GEOMETRY, make

    if a.scratch.is_relative_to(ROOT):
        raise SystemExit('scratch must be outside the repository')
    a.scratch.mkdir()
    boot = a.scratch / 'probe.d88'
    if a.packaged:
        image = a.base.read_bytes()
        if read_file(raw_image(image), 'DISKCOPY.COM') != a.com.read_bytes():
            raise SystemExit('packaged DISKCOPY.COM differs from the specified executable')
        boot.write_bytes(image)
    else:
        pack_va(a.base, boot, [('DISKCOPY.COM', a.com.read_bytes()),
                              ('AUTOEXEC.BAT', b'@ECHO OFF\r\n')])
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy',
               TMPDIR=str(a.scratch))

    def emulate(work, name, source, target, script):
        (work / f'{name}.debug').write_text('\n'.join((*script, 'exit', '')))
        args = [a.vaeg, '--model', a.model, '--roms', a.roms, '--no-cfg', '--no-bkupmem',
                '--nowait', '--fdd1', source, '--fdd2', target, '--debug-script', f'{name}.debug',
                '--debug-output-dir', '.', '--screen-tvram-dump', f'{name}.tvram']
        with (work / f'{name}.log').open('wb') as log:
            subprocess.run(args + (['--fdctrace'] if a.trace else []), cwd=work, env=env,
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=480)
        assert (work / 'events.tsv').read_text().splitlines()[-1].startswith('exit\t'), work
        result = screen(work / f'{name}.tvram')
        (work / f'{name}.txt').write_text(result)
        return result

    def run(case):
        work = a.scratch / case
        work.mkdir()
        fixture, _, variant = case.partition(':')
        is_boot = fixture == 'boot'
        guard = fixture if fixture in ('mismatch', 'protect', 'not-ready') else variant
        negative = guard in ('mismatch', 'protect', 'not-ready')
        use_boot_source = is_boot or fixture in ('mismatch', 'protect', 'not-ready')
        kind = 'hd80' if use_boot_source else fixture
        original = boot.read_bytes() if use_boot_source else make(kind)
        target = work / 'target.d88'
        baseline = make(('hd80' if kind == 'd16' else 'd16') if guard == 'mismatch' else kind,
                        target=True, protect=guard == 'protect')
        if variant == 'blank' or kind == 'exotic' and not negative:
            blank = bytearray(baseline[:0x20] + bytes(164 * 4))
            struct.pack_into('<I', blank, 0x1c, len(blank))
            baseline = bytes(blank)
        target.write_bytes(baseline)
        (work / 'source.d88').write_bytes(original)
        (work / 'boot.d88').write_bytes(boot.read_bytes())
        script = ['debug-script 1', f'limit-frame {a.frames + 100}',
                  'resource source source.d88', 'wait-frame 650',
                  'input-line DISKCOPY A: B: /V', 'wait-frame 1600']
        if not use_boot_source:
            script.append('mount-fdd 1 source')
        # The emulator ejects immediately, then delays insertion.
        script.extend(('wait-frame 1850', 'key-tap RETURN 3',
                       'wait-frame 2350', 'key-tap RETURN 3'))
        if not negative and kind == 'hd77':
            script.extend(('wait-frame 3400', 'input-line IIIIII'))
        if not negative and kind == 'exotic':
            script.extend(('wait-frame 2600', 'key-tap I 3',
                           'wait-frame 2900', 'key-tap I 3'))
        if case in ('protect', 'not-ready'):
            script.extend(('wait-frame 2600', 'key-tap A 3'))
        if a.repeat:
            script.extend(('wait-frame 3400', 'key-tap Y 3',
                           'wait-frame 3800', 'key-tap RETURN 3',
                           'wait-frame 4300', 'key-tap RETURN 3'))
        script.extend((f'wait-frame {a.frames-25}', 'key-tap N 3', f'wait-frame {a.frames}'))
        text = emulate(work, 'copy', 'boot.d88', 'none' if case == 'not-ready' else 'target.d88', script)
        source_path = work / ('boot.d88' if use_boot_source else 'source.d88')
        assert source_path.read_bytes() == original, 'source was modified'
        if negative:
            prompt = {'mismatch': 'Source and target media modes differ.',
                      'protect': 'Target is write protected.', 'not-ready': 'Target not ready.'}[guard]
            error = None if prompt in text and target.read_bytes() == baseline else 'expected refusal missing'
        else:
            copied = target.read_bytes()
            error = compare(original, copied, skip=(0,) if kind == 'exotic' else ())
            markers = {'hd77': ('Copy incomplete.', '9A 9B 9C 9D 9E 9F'),
                       'exotic': ('Track 00: mixed sector sizes cannot be reproduced.',
                                  'Copy incomplete.', '\n00 02\n')}.get(kind, ('Copy complete.',))
            if not error and kind == 'exotic' and next(tracks(copied)) != next(tracks(baseline)):
                error = 'mixed-size track was modified'
            if a.repeat and text.count('Copy complete.') != 2:
                error = error or 'expected two successful copies'
            for marker in markers:
                if not error and marker not in text:
                    error = f'expected output missing ({marker!r})'
        if not error and is_boot:
            text = emulate(work, 'boot-copy', 'target.d88', 'none',
                           ('debug-script 1', 'limit-frame 900', 'wait-frame 800'))
            if 'MS-DOS Version 4.00' not in text or 'A:\\>' not in text:
                error = 'copied disk did not boot to MS-DOS prompt'
        print(a.model, case, 'FAIL: ' + error if error else 'PASS', flush=True)
        return not error

    with ThreadPoolExecutor(4) as pool:
        return all(list(pool.map(run, a.cases or (*GEOMETRY, 'boot', 'mismatch', 'protect', 'not-ready'))))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='action', required=True)
    cmp = sub.add_parser('compare')
    for arg in ('source', 'target'):
        cmp.add_argument(arg, type=Path)
    run = sub.add_parser('run')
    for arg in ('scratch', 'base', 'com', 'vaeg', 'roms'):
        run.add_argument(arg, type=lambda v: Path(v).resolve())
    run.add_argument('--model', choices=('va', 'va2'), default='va')
    run.add_argument('--frames', type=int, default=4800)
    run.add_argument('--trace', action='store_true')
    run.add_argument('--packaged', action='store_true', help='boot the distribution image unchanged')
    run.add_argument('--repeat', action='store_true', help='accept another copy (boot case only)')
    run.add_argument('cases', nargs='*', metavar='CASE')
    a = p.parse_args()
    if a.action == 'run':
        if a.repeat and a.cases != ['boot']:
            p.error('--repeat requires the boot case only')
        raise SystemExit(not run_gate(a))
    error = compare(a.source.read_bytes(), a.target.read_bytes())
    if error:
        raise SystemExit(error)
    print('D88 tracks match (up to angular rotation)')


if __name__ == '__main__':
    main()
