#!/usr/bin/env python3
"""Validate the scratch gate; print only typed fixtures, counts and timings."""
import importlib.util
from pathlib import Path
import re
import sys

spec = importlib.util.spec_from_file_location('j3b2', Path(__file__).resolve().parents[1] / 'J3b.2/check.py')
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)
j3a, P = old.j3a, old.P
row, v, pixels, screen = old.system_row, old.relevant, old.pixels, old.screen

KANJI, HIRA = '日本語', 'にほんご'


def counts(path, expected):
    stats = next(line for line in v(path) if line.startswith('MON:'))
    words = [int(s, 16) for s in stats.split()[1:]]
    assert words == expected + [0, 0], (path, words)
    print('   calls 03h–0Ah:', *words[:8], '| nested INT 21h / INT 83h:', *words[8:])


def timing(path, name, function):
    def regs(stage):
        return dict(line.split('\t') for line in (path / (name + '-' + stage + '.registers.tsv'))
                    .read_text().splitlines())
    frames = {i: int(f) for e, f, i, _ in (line.split('\t') for line in
              (path / 'events.tsv').read_text().splitlines()[1:]) if e == 'capture'}
    a, b = regs('in'), regs('out')
    assert int(a['cx'], 16) == function and a['sp'] == b['sp'] and a['ss'] == b['ss']
    return (frames[name + '-out'] - frames[name + '-in'], int(b['clock']) - int(a['clock']))


def expect_echo(path, expected):
    assert v(path)[-3:] == [P + 'echo ' + expected, expected, P], path


def focus(path):
    m = re.fullmatch(r'\[C\] ([^\[\]]*)\[([^\[\]]+)\]([^\[\]]*)', row(path))
    assert m, path
    return m.groups()


def check(d, total):
    free = j3a.regression(d, total)
    for n in (1, 2):
        p = d / f'extra-eof-{n}'
        assert j3a.get(p, 'T.TXT') == b'ABC\r\nDEF\r\n'
        assert v(p / 'end')[-3:] == ['ABC', 'DEF', P]
    print('1. Additional F10 cold boots: 2/2')
    old.rom_gate(d / 'rom')

    p = d / 'fep-nihongo'
    assert row(p / 'reading') == '[H] ' + HIRA
    assert focus(p / 'candidate') == focus(p / 'back') == ('', KANJI, '')
    assert v(p / 'candidate')[-1] == P + 'echo'
    assert v(p / 'confirmed')[-1] == P + 'echo ' + KANJI
    expect_echo(p / 'echo', KANJI)
    print('2. 1/1: nihongo → 日本語 on first HENKAN, next/previous, KETTEI, Return')

    timing_rows = []
    for reading, expected in [('nihongo', KANJI), ('kanji', '漢字'), ('henkan', '変換'),
                              ('toukyou', '東京'), ('pepepupu', 'ぺぺぷぷ'), ('full', 'あ'*30)]:
        path = d / ('fep-' + reading)
        candidate = row(path / 'candidate')
        assert candidate[4:].replace('[', '').replace(']', '') == expected, path
        expect_echo(path / 'echo', expected)
        timing_rows.append((reading, *timing(path, 'begin', 4)))
    print('3. 4/4: kanji, henkan, toukyou on first HENKAN; nonsense reading unchanged')

    mon = d / 'fep-mon'
    phrase = '日本語を話す'
    assert focus(mon / 'first')[:2] == ('', '日本語を')
    prefix, shorter, suffix = focus(mon / 'short')
    assert not prefix and suffix and 0 < len(shorter) < len('日本語を')
    assert row(mon / 'long') == row(mon / 'first')
    assert focus(mon / 'right')[0] == '日本語を'
    assert focus(mon / 'alternate') == ('日本語を', '話す', '')
    assert focus(mon / 'left') == ('', '日本語を', '話す')
    for direction in ('forward', 'backward'):
        for i in range(30):
            stage = mon / f'{direction}-{i:02}'
            a, _, c = focus(stage)
            assert not a and c == '話す' and v(stage)[-1] == 'MON READY', stage
    assert row(mon / 'left') == row(mon / 'backward-29')
    print('4. 1/1: 30 forward + 30 backward, no premature bytes, stable session')

    api = d / 'fep-api'
    assert v(mon / 'passed')[-3] == phrase and v(mon / 'passed')[-1] == P
    print('5. 2/2: positive-control hooks, master-off at endpoints, and zero nested interrupts')
    counts(mon / 'passed', [1, 1, 31, 30, 1, 1, 1, 1])
    counts(api / 'passed', [4, 4, 0, 0, 0, 0, 0, 0])

    for case, name, suffix in [('copy', 'J', b'\r\n'), ('edlin', 'E', b'\r\n\x1a')]:
        path = d / ('fep-' + case)
        data = j3a.get(path, name + '.TXT')
        assert data == KANJI.encode('shift_jis') + suffix
        assert v(path / 'type')[-3:] == [P + 'TYPE ' + name + '.TXT', KANJI, P]
        if case == 'edlin':
            assert any(re.fullmatch(r'\s+1: ' + KANJI, line) for line in v(path / 'list'))
        print(f'6. {case}: 1/1; {name}.TXT = {data.hex(" ")}')

    normal = pixels(p / 'idle')
    assert pixels(p / 'candidate') == pixels(p / 'held') != normal
    assert pixels(p / 'confirmed') == normal
    layout = d / 'fep-layout'
    assert len(screen(layout / 'hidden')) == 25 and not any(pixels(layout / 'hidden'))
    for name in ('reserved', 'reading', 'deferred'):
        assert len(screen(layout / name)) == 24
        assert screen(layout / name)[0] == screen(layout / 'hidden')[0]
    for name in ('reserved', 'cancelled', 'deferred'):
        assert pixels(layout / name) == normal
    assert len(screen(layout / 'released')) == 25 and screen(layout / 'released')[24] == P
    print('7. Labels: 2/2 (held Shift, restored; hidden layout reservation/deferred hide/OFF)')

    assert v(api / 'first-candidate')[-1] == 'FIRST' and focus(api / 'first-candidate')[1] == KANJI
    assert v(api / 'pending')[-1] == 'PENDING' and focus(api / 'pending')[1] == KANJI
    for stage, marker in [('second', 'SECOND'), ('flushed', 'FLUSHED')]:
        assert v(api / stage)[-1] == marker and pixels(api / stage) == normal
    assert v(api / 'passed')[-2:] == ['PASS: FEP status, bytes and flush', P]
    assert focus(api / 'before-edit')[1] == '漢字' and row(api / 'edited') == '[H] かんじあ'
    print('7. CON API: 3/3 (byte order/repeated peek, pending candidate flush, cached trail flush)')

    assert v(d / 'fep-return/plain-confirmed')[-1] == P + 'echo ' + HIRA
    expect_echo(d / 'fep-return/plain-echo', HIRA)
    assert v(mon / 'confirmed')[-3:] == [P + 'FEPMON', 'MON READY', phrase]
    print('8. Return: 2/2 (reading and candidate both confirm before second Return submits)')
    busy = 'Cannot select input mode. Use JFP OFF before switching.'
    assert all(busy in v(layout / name) for name in ('refuse-rom', 'refuse-project'))
    assert j3a.memory(layout / 'memory', total) == free
    print('Gate: 48/48')
    print('Supplemental: phrase movement/resize, 30 cells, mode exclusion/memory, candidate edit: 4/4')
    for name, fn in [('next', 5), ('prev', 6), ('commit', 3)]:
        timing_rows.append((name, *timing(p, name, fn)))
    print('Clock bracket: guest frame boundaries / vaeg clocks (BIOS only)')
    for name, frames, clocks in timing_rows:
        print(f'   {name}: {frames} / {clocks}')


if __name__ == '__main__':
    for model, ram in [('va', 640), ('va2', 256), ('va2', 640)]:
        print(f'\n{model.upper()} {ram} KiB')
        check(Path(sys.argv[1]) / f'{model}-{ram}', ram * 1024)
