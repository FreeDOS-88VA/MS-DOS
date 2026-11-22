#!/usr/bin/env python3
"""M3: monitor actual user hits, verify app file bytes and check memory."""
from pathlib import Path
import sys

import run
from checks import j3a, v
from format_gate import FIRST, SECOND, HEADER, record, sj
from media import pack_va
from quality import candidate
from resident_gate import THIRD, fixtures, kana
from safety import stats


def user_cases(pc, screens):
    def start():
        p = run.Plan(pc, screens)
        p.line('JFP @MODE@', 400)
        return p

    for name, reading in [('user-only', 'pi-shi-'), ('user-bridge', 'nakata')]:
        p = start()
        p.line('USERMON', 400)
        p.keys('ZENKAKU')
        kana(p, reading)
        p.keys('HENKAN')
        p.shot('first')
        if name == 'user-bridge':
            p.keys('HENKAN')
            p.shot('user-second')
            p.keys('HENKAN', 'HENKAN')
            p.shot('bios')
            p.keys('SHIFT+HENKAN', 'SHIFT+HENKAN')
            p.shot('back')
        p.keys('KETTEI', 'RETURN')
        p.shot('report')
        yield name, p

    for name, launch, filename in [('copy', 'COPY CON J.TXT', 'J.TXT'),
                                   ('edlin', 'EDLIN E.TXT', 'E.TXT')]:
        p = start()
        p.line(launch, 400)
        if name == 'edlin':
            p.line('I', 300)
        p.keys('ZENKAKU')
        kana(p, 'pi-shi-')
        p.keys('HENKAN')
        p.shot('candidate')
        p.keys('KETTEI', 'RETURN', 'F10', 'RETURN', 'ZENKAKU')
        if name == 'edlin':
            p.line('1L', 300)
            p.shot('list')
            p.line('E', 400)
        p.line(f'TYPE {filename}', 400)
        p.shot('type')
        yield name, p


def mem_cases(pc, screens):
    p = run.Plan(pc, screens)
    for phase, command in [('plain', None), ('empty', 'JFP FEP'), ('loaded', 'REGTEST')]:
        if command:
            p.line(command, 550)
        if phase == 'loaded':
            p.line('JFP ON', 350)
            p.shot('loaded-active')
        p.line('CHKDSK', 850)
        p.shot(phase)
    yield 'memory', p


def user_pack(base, out, monitor, persisted):
    data = j3a.get(persisted, 'JFPUSER.DIC')
    assert data == HEADER + b''.join(record(*p) for p in (FIRST, SECOND, THIRD))
    pack_va(base, out, [('USERMON.COM', monitor.read_bytes()), ('JFPUSER.DIC', data)])


def user_check(root, disk):
    def text_forms(text):
        return (text, text.replace('－', '−'))

    for model, ram in run.MATRIX:
        profile = f'{model}-{ram}'
        p = root / profile / 'fep'
        for name, first, confirmed, expected in [
                ('user-only', SECOND[1], SECOND[1], [0] * 8),
                ('user-bridge', FIRST[1], THIRD[1], [1, 1, 1, 1, 0, 0, 0, 0])]:
            q = p / name
            assert v(q / 'first')[-1] == 'USER MON READY', q
            assert candidate(q / 'first', 'FEP')[0] in text_forms(first), q
            if name == 'user-bridge':
                for shot in ('user-second', 'back'):
                    assert candidate(q / shot, 'FEP')[0] == THIRD[1], (q, shot)
                assert candidate(q / 'bios', 'FEP')[0] not in (THIRD[1], FIRST[1]), q
            report = v(q / 'report')
            assert report[-4] in text_forms(confirmed), (q, report)
            assert report[-2] == 'OUTER INT 21h: zero (both controls passed)', (q, report)
            calls, nested, _ = stats(q / 'report', 'FEP')
            assert calls == expected and nested == [0, 0], (q, calls, nested)
            assert (q / 'disk.d88').read_bytes() == disk.read_bytes(), q
            print(f'{profile}\t{name}\tPASS\tROM calls {" ".join(map(str, calls))}; '
                  'firmware nested DOS/text 0/0; whole CON read nested DOS 0; disk unchanged')
        data = sj(SECOND[1]) + b'\r\n'
        assert j3a.get(p / 'copy', 'J.TXT') == data
        assert j3a.get(p / 'edlin', 'E.TXT') == data + b'\x1a'
        for name in ('copy', 'edlin'):
            assert candidate(p / name / 'candidate', 'FEP')[0] in text_forms(SECOND[1])
            assert v(p / name / 'type')[-2] in text_forms(SECOND[1])
        print(f'{profile}\tCOPY CON / EDLIN\tPASS\texact FAT bytes and TYPE')


def mem_check(root):
    for model, ram in run.MATRIX:
        profile = f'{model}-{ram}'
        p = root / profile / 'fep' / 'memory'
        free = [j3a.memory(p / phase, ram * 1024) for phase in ('plain', 'empty', 'loaded')]
        active = v(p / 'loaded-active')
        assert active[-6:-3] == ['User dictionary saved.'] * 3, active
        assert active[-3].endswith('JFP ON') and active[-2].startswith('Project FEP on.'), active
        assert j3a.get(p, 'JFPUSER.DIC') == HEADER + b''.join(record(*pair) for pair in (FIRST, SECOND, THIRD))
        assert len(set(free)) == 1
        print(f'{profile}\tCHKDSK plain/empty/loaded\tPASS\t' + '/'.join(map(str, free)))


if __name__ == '__main__':
    action = sys.argv.pop(1)
    if action == 'pack-user':
        user_pack(*map(Path, sys.argv[1:]))
    elif action == 'pack-mem':
        pack_va(*map(Path, sys.argv[1:]), fixtures()[:1])
    elif action == 'run-user':
        run.main(user_cases, ('FEP',))
    elif action == 'run-mem':
        run.main(mem_cases, ('FEP',))
    elif action == 'check-user':
        user_check(*map(Path, sys.argv[1:]))
    elif action == 'check-mem':
        mem_check(Path(sys.argv[1]))
    else:
        raise SystemExit(f'Unknown action: {action}')
