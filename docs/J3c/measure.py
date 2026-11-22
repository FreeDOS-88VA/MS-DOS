#!/usr/bin/env python3
"""M3: key injection to rendered candidate latency and CHKDSK memory."""
import csv
from pathlib import Path
import sys

import run


# All four have a distinguishable second candidate on the tested matrix.
READINGS = ('kanji', 'henkan', 'gakkou', 'kyouhaiitenkidesu')


class FramePlan(run.Plan):
    def window(self, name, offsets):
        start = self.frame
        self.event('key-down HENKAN', 3)
        self.event('key-up HENKAN', max(offsets) + 5 - 3)
        self.shot(name + '-settled')
        self.screenshots.extend((start + i, f'{name}-{i:03d}.png') for i in offsets)
        self.screenshots.append((self.frame, f'{name}-settled.png'))


def scenarios(cistat, screens):
    p = run.Plan(cistat, screens)
    p.line('CHKDSK', delay=550)
    p.shot('plain')
    p.line('JFP @MODE@', delay=300)
    p.shot('enabled')
    p.line('CHKDSK', delay=550)
    p.shot('enabled-free')
    yield 'memory', p

    for word in READINGS:
        p = FramePlan(cistat, screens)
        p.line('JFP @MODE@', delay=350)
        p.shot('enabled')
        for key in (*'ECHO', 'SPACE', 'ZENKAKU', *word.upper()):
            p.event(f'key-tap {key} 3', 12)
        p.shot('reading')
        # m153 allows 64 screenshot requests. The pilot showed a much
        # slower first conversion on VA for the phrase. Use the same two
        # sample ranges on all machines, and require an adjacent no-hit.
        first = (*range(28), *range(80, 95)) if word == READINGS[-1] else range(43)
        p.window('first', first)
        p.window('next', range(19))
        p.body.append(f'wait-frame {p.frame}')  # Scheduler and debugger exit on the same frame.
        yield 'latency-' + word, p


def report(root, quality_root):
    from PIL import Image
    from quality import checked
    from checks import j3a, verify_selection

    def system_pixels(path):
        with Image.open(path) as image:
            return image.crop((0, image.height - 16, 640, image.height)).convert('RGB').tobytes()

    print('| Configuration | Plain free (bytes) | ROM free (bytes) | FEP free (bytes) |')
    print('|---|---:|---:|---:|')
    for model, ram in run.MATRIX:
        d = root / f'{model}-{ram}'
        both = []
        for mode in run.MODES:
            p = d / mode.lower() / 'memory'
            verify_selection(p / 'enabled', mode)
            both.append((j3a.memory(p / 'plain', ram * 1024),
                         j3a.memory(p / 'enabled-free', ram * 1024)))
        assert both[0][0] == both[1][0], (d, both)
        print(f'| {d.name} | {both[0][0]:,} | {both[0][1]:,} | {both[1][1]:,} |')

    cols = [(f'{model}-{ram}', mode) for model, ram in run.MATRIX for mode in run.MODES]
    print('\n| Reading | ' + ' | '.join(f'{d} {m}' for d, m in cols) + ' |')
    print('|---' * (1 + len(cols)) + '|')
    schedules = {name.removeprefix('latency-'): plan.screenshots
                 for name, plan in scenarios('0:0', False) if name.startswith('latency-')}
    for word in READINGS:
        values = []
        for d, mode in cols:
            p = root / d / mode.lower() / f'latency-{word}'
            verify_selection(p / 'enabled', mode)
            reference = quality_root / d / mode.lower() / f'quality-{word}'
            with (p / 'events.tsv').open(newline='') as stream:
                events = list(csv.DictReader(stream, delimiter='\t'))
            keydowns = [int(e['frame']) for e in events if e['event'] == 'key-down'
                        and e['id'] == 'henkan']
            assert len(keydowns) == 2, p
            durations = []
            previous = None
            for i, (stage, keydown) in enumerate(zip(('first', 'next'), keydowns), 1):
                expected = checked(reference / f'candidate-{i:02d}', mode)[0]
                assert checked(p / (stage + '-settled'), mode)[0] == expected, p
                assert previous != expected, (p, stage, expected)
                previous = expected
                schedule = dict((name, frame) for frame, name in schedules[word])
                assert schedule[f'{stage}-000.png'] == keydown, (p, stage, keydown)
                captured = next(int(e['frame']) for e in events if e['event'] == 'capture'
                                and e['id'] == f'{stage}-settled')
                assert captured < schedule[f'{stage}-settled.png'], (p, stage, captured)
                target = system_pixels(p / f'{stage}-settled.png')
                window = {frame - keydown: system_pixels(p / name) == target
                          for name, frame in schedule.items() if name.startswith(stage + '-')
                          and name[-7:-4].isdigit()}
                found = next((i for i, hit in window.items() if hit), None)
                assert found is not None and window.get(found - 1) is False, (p, stage, window)
                assert all(hit for i, hit in window.items() if i >= found), (p, stage, window)
                durations.append(str(found))
            values.append(' / '.join(durations))
        print('| ' + word + ' | ' + ' | '.join(values) + ' |')


if __name__ == '__main__':
    if sys.argv[1:2] == ['report']:
        report(*map(Path, sys.argv[2:4]))
    else:
        run.main(scenarios)
