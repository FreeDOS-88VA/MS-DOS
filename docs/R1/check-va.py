#!/usr/bin/env python3
"""Cold-boot the R1 disks on both vaeg models and check the sign-on."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import csv
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess

from PIL import Image
from m75_scsi_harness import decode_screen


VERSION = 'MS-DOS Version 4.00'
PROMPT = 'A:\\>'
CISTAT = '1000:06D0'
OUTCHR = '1000:0811'


def banner(record):
    identity = 'unknown (unknown, unknown)'
    if 'msdos_release' in record:
        identity = '{date} ({track}, {short_commit})'.format(**record['msdos_release'])
    return [f'日本語MS-DOS version 4.00 Release {identity}',
            'for NEC PC-88VA Series Personal Computer', 'Ported by Nakata Maho']


def run(vaeg, roms, scratch, model, build):
    product = scratch / build
    record = json.loads((product / 'build-record.json').read_text())
    out = scratch / 'runs' / model / build
    out.mkdir(parents=True)
    shutil.copyfile(product / record['image']['name'], out / 'disk.d88')
    actions = ['debug-script 1', 'limit-frame 2300']
    shots = set()

    def shot(name):
        actions.extend((f'wait-pc {CISTAT} 1', f'capture {name} tvram screen'))
        shots.add(name)

    # Count and inspect every DOS CON output byte up to the displayed prompt.
    # A pre-prompt CISTAT hit is possible during the sign-on write itself.
    boot = ['', VERSION] if build == 'base' else banner(record)
    expected = '\r\n'.join(boot + [PROMPT]).encode('cp932')
    for i in range(len(expected)):
        actions.extend((f'wait-pc {OUTCHR} 1', f'capture byte{i} registers'))
    shot('prompt')
    actions.append('wait-frame 600')
    shot('idle')
    for frame, action, capture, name in (
        (650, 'key-down SHIFT', 700, 'shift'), (730, 'key-up SHIFT', 800, 'released'),
        (850, 'input-line VER', 1100, 'ver'), (1150, 'input-line CLS', 1400, 'cls'),
        (1450, 'input-line CHKDSK', 2200, 'mem'),
    ):
        actions.extend((f'wait-frame {frame}', action, f'wait-frame {capture}'))
        shot(name)
    (out / 'run.debug').write_text('\n'.join(actions + ['exit', '']))
    with (out / 'run.log').open('wb') as log:
        subprocess.run([str(vaeg), '--model', model, '--roms', str(roms), '--no-cfg',
                        '--no-bkupmem', '--nowait', '--fdd1', 'disk.d88',
                        '--debug-script', 'run.debug', '--debug-output-dir', '.'],
                       cwd=out, env=dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy'),
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
    with (out / 'events.tsv').open() as stream:
        events = list(csv.DictReader(stream, delimiter='\t'))
    captures = {event['id']: int(event['frame']) for event in events if event['event'] == 'capture'}
    assert events[-1]['event'] == 'exit' and shots <= captures.keys(), (out, events)
    observed = bytearray()
    for i in range(len(expected)):
        reg = dict(line.split('\t') for line in (out / f'byte{i}.registers.tsv').read_text().splitlines())
        observed.append(int(reg['ax'], 16) & 0xff)
    assert observed == expected, (out, observed, expected)
    return out, captures['prompt'], record


def lines(out, name):
    screen = decode_screen(out / (name + '.tvram.bin'))
    assert screen['lineheight'] == 16 and len(screen['lines']) == 24
    return [line.rstrip('?').rstrip() for line in screen['lines']]


def label_pixels(out, name):
    with Image.open(out / (name + '.screen.bmp')) as image:
        return image.convert('RGB').crop((0, image.height - 16, 640, image.height)).tobytes()


def check_kanji(path):
    data = path.read_bytes()
    header = 16 + struct.unpack_from('<I', data, 12)[0]
    table = struct.unpack_from('<I', data, header)[0]
    start, height, width = struct.unpack_from('<IHH', data, header + 28 + table + 16)
    assert height & 0x1fe == 384 and width & 0x3ff == 640
    # Each JIS word must be followed by its right-half marker (bit 15 set).
    assert struct.unpack_from('<6H', data, header + 28 + start) == (
        0x7c26, 0xfc26, 0x5c2b, 0xdc2b, 0x6c18, 0xec18)


def check(model, runs, scratch):
    base, base_frame, _ = runs[model, 'base']
    default_labels = label_pixels(base, 'prompt')
    assert any(default_labels)
    memory = {}
    for build in ('base', 'main', 'milestone', 'unknown'):
        out, frame, record = runs[model, build]
        boot = lines(out, 'prompt')
        if build == 'base':
            expected = ['', VERSION, PROMPT]
        else:
            if build == 'unknown':
                assert 'msdos_release' not in record
            else:
                rel = record['msdos_release']
                assert rel['track'] == {'main': 'main', 'milestone': 'r1'}[build]
                assert rel['short_commit'] == record['msdos_commit'][:8]
                assert rel['date_source'] == {'main': 'commit-jst', 'milestone': 'lock'}[build]
                lock_dir = {'main': 'msdos4-va', 'milestone': 'milestone'}[build]
                pin = json.loads((scratch / 'experiments' / lock_dir / 'lock.json').read_text())['msdos']
                assert record['msdos_commit'] == pin['commit']
                date = pin.get('release_date') or subprocess.check_output(
                    ['git', '-C', str(scratch / 'components/msdos'), 'log', '-1',
                     '--format=%cd', '--date=format-local:%Y%m%d', pin['commit']],
                    env=dict(os.environ, TZ='Asia/Tokyo'), text=True).strip()
                assert rel['date'] == date
            expected = banner(record) + [PROMPT]
            check_kanji(out / 'prompt.tvram.bin')
        assert boot == expected + [''] * (24 - len(expected)), (model, build, boot)
        assert lines(out, 'idle') == boot
        for shot in ('prompt', 'idle'):
            assert label_pixels(out, shot) == default_labels
        print(f'{model} {build}: frame {frame} ({frame - base_frame:+d}); ' + ' | '.join(boot[:len(expected)]))
        assert label_pixels(out, 'shift') != default_labels
        assert lines(out, 'shift') == boot == lines(out, 'released')
        for shot in ('released', 'ver', 'cls', 'mem'):
            assert label_pixels(out, shot) == default_labels
        ver = [line for line in lines(out, 'ver') if line]
        assert ver == [line for line in expected if line][:-1] + [PROMPT + 'VER', VERSION, PROMPT], ver
        cls = lines(out, 'cls')
        assert cls == ['', PROMPT] + [''] * 22
        chkdsk = '\n'.join(lines(out, 'mem'))
        assert '655360 total bytes memory' in chkdsk
        memory[build] = int(re.search(r'(\d+) bytes free\b', chkdsk)[1])
    print(f'{model}: exact CON bytes to first prompt; VER, CLS and Shift labels OK on all builds')
    print(f'{model}: CHKDSK free bytes {memory} (main change {memory["main"] - memory["base"]:+d} B)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('vaeg', 'roms', 'scratch'):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    models = ('va', 'va2')
    keys = [(model, flavor) for model in models for flavor in ('base', 'main', 'milestone', 'unknown')]
    with ThreadPoolExecutor(4) as pool:
        runs = {key: pool.submit(run, args.vaeg.resolve(), args.roms.resolve(), args.scratch.resolve(), *key)
                for key in keys}
        runs = {k: f.result() for k, f in runs.items()}
    for model in models:
        check(model, runs, args.scratch.resolve())


if __name__ == '__main__':
    main()
