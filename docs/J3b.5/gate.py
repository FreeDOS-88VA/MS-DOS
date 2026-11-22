#!/usr/bin/env python3
"""Run J3b.5 gates with generated fixtures on disposable FAT disks."""
import csv
import os
from pathlib import Path
import re
import sys

from checks import expect_echo, j3a, v, verify_selection
from format_gate import FIRST, SECOND, files, record as v1, sj
from media import pack_va
from quality import candidate, cells
from resident_gate import THIRD, end_reading
import resident_gate
import run
from safety_gate import user_cases, user_check

HEADER = b'JFPUD\x02'
OLD_HEADER = b'JFPUD\x01'


def v2(reading, word):
    r, w = sj(reading), sj(word)
    return bytes((len(r), len(w))) + r + w + bytes((len(r) + len(w) + 3,))


def dictionary(pairs):
    return HEADER + b''.join(v2(*p) for p in pairs)


PAIRS = [FIRST, SECOND, THIRD]
SLOTS = {0: ('i', 'い'), 32: ('u', 'う'), 63: ('o', 'お')}
FULL = [('あ' * 29 + SLOTS.get(i, (None, 'え'))[1], '亜' * 29 + chr(0x3041 + i))
        for i in range(64)]


def core_pack(base, out):
    edit = files()[0]
    old = OLD_HEADER + b''.join(v1(*p) for p in FULL[:8])
    batch = b'@ECHO OFF\r\nCOPY /B OLD.UD JFPUSER.DIC\r\nJFP LIST > OLD.TXT\r\n'
    batch += sj(f'JFP ADD {SECOND[0]} {SECOND[1]} > ADD.TXT\r\nJFP LIST > NEW.TXT\r\n')
    pack_va(base, out, [edit, ('OLD.UD', old), ('EIGHT.UD', dictionary(FULL[:8])),
                        ('FULL.UD', dictionary(FULL)), ('MIGRATE.BAT', batch),
                        ('OVER.BAT', sj(f'@ECHO OFF\r\nJFP ADD {FIRST[0]} {FIRST[1]} > OVER.TXT\r\n'))])


def core_cases(pc, screens):
    p = run.Plan(pc, screens)
    p.line('edtest', 1200)
    p.shot('end')
    yield 'edtest', p

    p = run.Plan(pc, screens)
    p.line('COPY /B OLD.UD JFPUSER.DIC', 350)
    p.line('JFP ON', 350)
    long_reading(p, 'i', 'v1-hit')
    p.line('migrate', 1200)
    p.shot('end')
    yield 'migrate', p

    p = run.Plan(pc, screens)

    def mem(phase, *cmds):
        for command in cmds:
            p.line(command, 325)
        p.line('CHKDSK', 450)
        p.shot(phase)

    mem('plain')
    mem('empty', 'JFP FEP')
    mem('eight', 'COPY /B EIGHT.UD JFPUSER.DIC', 'JFP ON')
    mem('full', 'COPY /B FULL.UD JFPUSER.DIC', 'JFP ON')
    mem('reuse-smaller', 'COPY /B EIGHT.UD JFPUSER.DIC', 'JFP ON')
    mem('reuse-full', 'COPY /B FULL.UD JFPUSER.DIC', 'JFP ON')
    mem('reload', *['JFP ON'] * 5)
    mem('fresh-full', 'JFP OFF', 'JFP ON')
    p.line('JFP OFF', 325)
    for cmd in ['JFP ON', 'JFP OFF'] * 5:
        p.line(cmd, 325)
    p.shot('cycle-transcript')
    mem('cycles-off')
    mem('rom', 'JFP ROM')
    mem('last', 'JFP OFF')
    yield 'memory', p

    p = run.Plan(pc, screens)
    for command in ('COPY /B EIGHT.UD JFPUSER.DIC', 'JFP ON',
                    'COPY /B FULL.UD JFPUSER.DIC', 'JFP ON', 'MEM /DEBUG > MEM.TXT'):
        p.line(command, 450)
    p.shot('detail')
    yield 'mem-detail', p

    p = run.Plan(pc, screens)
    p.line('COPY /B FULL.UD JFPUSER.DIC', 500)
    p.line('OVER', 500)
    p.line('JFP ON', 500)
    for i, (key, _) in SLOTS.items():
        long_reading(p, key, f'slot-{i+1}')
    yield 'capacity', p


def long_reading(p, key, shot):
    p.keys(*'ECHO', 'SPACE', 'ZENKAKU')
    for c in 'A' * 29 + key.upper():
        p.event(f'key-tap {c} 3', 12)
    p.keys('HENKAN')
    p.shot(shot)
    end_reading(p)


def listing(pairs):
    return b''.join(sj(f'{r} : {w}\r\n') for r, w in pairs)


def core_check(root):
    for model, ram in run.MATRIX:
        profile = f'{model}-{ram}'
        p = root / profile / 'fep'
        def get(case, name):
            return j3a.get(p / case, name)

        error = (b'Expected a full-width hiragana reading and full-width word '
                 b'(1-30 cells each).\r\n')
        text = {'EMPTY': b'User dictionary empty.\r\n', 'ADD': b'User dictionary saved.\r\n',
                'DUP': b'Dictionary pair already registered.\r\n',
                'MISS': b'Dictionary pair not found.\r\n', 'BAD': error * 4, 'LONG': error * 2,
                'BOTH': listing(PAIRS[:2]), 'LEFT': listing([SECOND])}
        text['ADD2'] = text['DEL'] = text['ADD']
        for name, expected in text.items():
            assert get('edtest', name + '.TXT') == expected, (profile, name)
        assert get('edtest', 'JFPUSER.DIC') == dictionary([SECOND])
        assert candidate(p / 'migrate' / 'v1-hit', 'FEP')[0] == FULL[0][1], profile
        assert get('migrate', 'OLD.TXT') == listing(FULL[:8])
        assert get('migrate', 'ADD.TXT') == text['ADD']
        assert get('migrate', 'NEW.TXT') == listing(FULL[:8] + [SECOND])
        assert get('migrate', 'JFPUSER.DIC') == dictionary(FULL[:8] + [SECOND])
        print(f'{profile}\tPASS\tADD/DEL/LIST, validation, exact v2 bytes, padded v1 migration')

        capacity_check(p / 'capacity', profile)

        m = p / 'memory'
        def free(phase):
            screen = '\n'.join(v(m / phase))
            total, avail = (int(re.findall(rf'^[ ]*(\d+) {label}$', screen, re.M)[-1])
                            for label in ('total bytes memory', 'bytes free'))
            # This DOS CHKDSK derives even "total" from the end of its PSP.
            assert 0 <= avail <= total <= ram * 1024, (profile, phase, screen)
            return avail

        plain, empty, eight, full, rom = map(free, ('plain', 'empty', 'eight', 'full', 'rom'))
        fresh = free('fresh-full')
        verify_selection(m / 'rom', 'ROM')
        assert plain == empty == rom == free('last') == free('cycles-off'), (profile, plain, empty, rom)
        assert plain - eight == 32 + 8 * 123 + 8, (profile, plain, eight)
        assert plain - fresh == 32 + 64 * 123, (profile, plain, fresh)
        # CHKDSK reports contiguous room; after growing, the freed old
        # 8-entry block and its header are on the far side of the new one.
        assert fresh - full == plain - eight, (profile, plain, full, fresh)
        assert full == free('reuse-smaller') == free('reuse-full') == free('reload'), profile
        for phase in ('empty', 'eight', 'full', 'reuse-smaller', 'reuse-full', 'fresh-full'):
            assert any(line.startswith('Project FEP on.') for line in v(m / phase)), (profile, phase)
        # The 24-row screen scrolls part of both transcripts away. Count
        # injected commands between captures as well as visible success lines.
        with (m / 'events.tsv').open(newline='', encoding='ascii') as stream:
            events = list(csv.DictReader(stream, delimiter='\t'))
        def inputs_between(first, last):
            stamps = {e['id']: int(e['frame']) for e in events if e['event'] == 'capture'}
            return sum(e['event'] == 'input' and stamps[first] < int(e['frame']) <= stamps[last]
                       for e in events)
        assert inputs_between('reuse-full', 'reload') == 6, profile  # 5 ON + CHKDSK
        assert inputs_between('fresh-full', 'cycle-transcript') == 11, profile  # OFF + 5 pairs
        assert sum(line.startswith('Project FEP on.') for line in v(m / 'reload')) >= 2, profile
        cycle = v(m / 'cycle-transcript')
        assert sum(line.startswith('Project FEP on.') for line in cycle) >= 4, profile
        assert sum(line.startswith('JFP off;') for line in cycle) >= 4, profile
        print(f'{profile}\tPASS\tCHKDSK plain/empty/8/64 fresh/64 grown/ROM '
              f'{plain}/{empty}/{eight}/{fresh}/{full}/{rom}; reuse, five reloads and five ON/OFF cycles')


def capacity_check(p, profile):
    assert j3a.get(p, 'OVER.TXT') == b'User dictionary full (64 pairs).\r\n'
    assert j3a.get(p, 'JFPUSER.DIC') == dictionary(FULL)
    for i in SLOTS:
        assert candidate(p / f'slot-{i+1}', 'FEP')[0] == FULL[i][1], (profile, i)
    print(f'{profile}\tPASS\tfull-size 64 records; slots 1/33/64; ADD 65 rejected')


def detail_check(root):
    for model, ram in run.MATRIX:
        profile = f'{model}-{ram}'
        p = root / profile / 'fep/mem-detail'
        detail = j3a.get(p, 'MEM.TXT')
        assert re.search(rb'^ +001EC0 +INSTALL=', detail, re.M), (profile, detail, v(p / 'detail'))
        print(f'{profile}\tPASS\tMEM /DEBUG enumerated the grown 7,872-byte payload')


def selectors_check(root):
    for model, ram in run.MATRIX:
        profile = f'{model}-{ram}'
        for selector in ('ON', 'FEP', 'ROM'):
            mode = 'FEP' if selector == 'ON' else selector
            p = root / profile / selector.lower() / 'prompt'
            verify_selection(p / 'enabled', mode)
            first, nxt, previous = (candidate(p / s, mode) for s in ('first', 'next', 'previous'))
            assert first and first[0] == '日本語' and previous == first and nxt, p
            assert expect_echo(p / 'submitted', '日本語'), p
            print(f'{profile}\tPASS\tfull distribution JFP {selector}, candidate keys and confirm')


def timing_cases(pc, screens):
    # Both breakpoints are project VAIO listing offsets, not ROM addresses.
    points = os.environ['JFP_SCAN_POINTS'].split(',')
    assert len(points) == 2 and all(re.fullmatch(r'[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}', x) for x in points)
    p = run.Plan(pc, screens)
    p.line('COPY /B FULL.UD JFPUSER.DIC', 500)
    p.line('JFP ON', 500)
    p.shot('enabled')
    p.echo('a' * 30)  # All 64 readings match in the first 59 of 60 bytes.
    p.shot('reading')
    p.event('key-down HENKAN\n' + '\n'.join(f'wait-pc {addr} 1\ncapture {name} {p.targets}'
            for addr, name in zip(points, ('scan-entry', 'bios-entry'))), 100)
    p.shots.extend(('scan-entry', 'bios-entry'))
    p.event('key-up HENKAN', 25)
    yield 'worst-miss', p


def timing_check(root):
    p = root / 'va-640/fep/worst-miss'
    verify_selection(p / 'enabled', 'FEP')
    assert 'あ' * 30 in ''.join(ch for ch, _ in cells(p / 'reading'))
    assert j3a.get(p, 'JFPUSER.DIC') == dictionary(FULL)
    with (p / 'events.tsv').open(newline='', encoding='ascii') as stream:
        frames = {row['id']: int(row['frame']) for row in csv.DictReader(stream, delimiter='\t')
                  if row['event'] == 'capture'}
    print(f"va-640\t{frames['bios-entry'] - frames['scan-entry']} elapsed frame ticks\t"
          '64 records, 60 bytes compared per record; scan entry to BIOS entry')


if __name__ == '__main__':
    action = sys.argv.pop(1)
    if action == 'pack':
        core_pack(*map(Path, sys.argv[1:]))
    elif action == 'pack-corrupt-v2':
        fixtures = [(name, dictionary([THIRD]) + b'\x02' if name == 'BAD.UD' else data)
                    for name, data in resident_gate.fixtures()]
        pack_va(*map(Path, sys.argv[1:]), fixtures)
    elif action == 'pack-user':
        base, out, monitor = map(Path, sys.argv[1:])
        pack_va(base, out, [('USERMON.COM', monitor.read_bytes()), ('JFPUSER.DIC', dictionary(PAIRS))])
    elif action == 'run':
        run.main(core_cases, ('FEP',))
    elif action == 'run-timing':
        run.MATRIX = (('va', 640),)
        run.main(timing_cases, ('FEP',))
    elif action == 'run-user':
        run.main(user_cases, ('FEP',))
    elif action == 'check':
        core_check(Path(sys.argv[1]))
    elif action == 'check-selectors':
        selectors_check(Path(sys.argv[1]))
    elif action == 'check-capacity':
        for model, ram in run.MATRIX:
            profile = f'{model}-{ram}'
            capacity_check(Path(sys.argv[1]) / profile / 'fep/capacity', profile)
    elif action == 'check-detail':
        detail_check(Path(sys.argv[1]))
    elif action == 'check-timing':
        timing_check(Path(sys.argv[1]))
    elif action == 'check-resident':
        resident_gate.HEADER, resident_gate.record = HEADER, v2
        resident_gate.check(Path(sys.argv[1]))
    elif action == 'check-corrupt-v2':
        root, reference = map(Path, sys.argv[1:])
        for model, ram in run.MATRIX:
            profile = f'{model}-{ram}'
            p = root / profile / 'fep/corrupt'
            expected = candidate(reference / profile / 'fep/resident/empty', 'FEP')
            assert expected, profile
            for rejected, fallback in [('rejected', 'fallback'), ('rejected-cold', 'fallback-cold')]:
                assert 'Invalid JFPUSER.DIC.' in v(p / rejected), (profile, rejected)
                verify_selection(p / rejected, 'FEP')
                assert candidate(p / fallback, 'FEP') == expected, (profile, fallback)
            print(f'{profile}\tPASS\ttruncated v2 rejected on reload and cold load')
    elif action == 'check-user':
        user_check(*map(Path, sys.argv[1:]))
    else:
        raise SystemExit(f'Unknown action: {action}')
