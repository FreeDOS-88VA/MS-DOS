#!/usr/bin/env python3
"""M4: same real-key interaction scripts and byte probes for both front ends."""
from pathlib import Path
import re
import sys

import run
from checks import P, expect_echo, j3a, labels, pixels, screen, v, verify_selection

KANJI = '日本語'
FUNCTIONS = [f'{shift}F{i}' for shift in ('', 'SHIFT+') for i in range(1, 11)]
ARROWS = ['LEFT', 'RIGHT', 'UP', 'DOWN', 'SHIFT+LEFT', 'SHIFT+RIGHT']
PENDING = [('fkeys', FUNCTIONS[:10]), ('shift-fkeys', FUNCTIONS[10:19]),
           ('shift-f10', FUNCTIONS[19:]), ('arrows', ARROWS)]
IDLE_KEYS = FUNCTIONS + 'ROLLUP ROLLDOWN INS DEL UP LEFT RIGHT DOWN HOME HELP'.split()
IDLE_KEYS += [f'{m}+{k}' for m in ('SHIFT', 'CTRL') for k in ('UP', 'LEFT', 'RIGHT', 'DOWN', 'HOME')]
IDLE_KEYS += ['BS', 'ESC', 'CTRL+C']
IDLE_BYTES = [b'\x1b' + bytes([c]) for c in b'STUVWEJPQZ']
IDLE_BYTES += [b'dir a:\r', b'dir b:\r', b'copy ', b'del ', b'ren ', b'chkdsk a:\r',
               b'chkdsk b:\r', b'type ', b'date\r', b'time\r']
IDLE_BYTES += [b'', b'', b'\x1bP', b'\x1bD', b'\x0b', b'\x08', b'\x0c', b'\x0a', b'\x1a', b'']
IDLE_BYTES += [b'\x0b', b'\x08', b'\x0c', b'\x0a', b'\x1e', b'\x0b', b'\x08', b'\x0c', b'\x0a', b'',
               b'\x08', b'\x1b', b'\x03']


def api(p):
    p.line('CONBYTE')
    p.shot('ready')
    p.keys('ZENKAKU', *'NIHONGO', 'HENKAN')
    p.shot('first')
    p.keys('KETTEI', *'NIHONGO', 'HENKAN')
    p.shot('pending')
    p.event('key-down SHIFT', 40)
    p.event('key-up SHIFT', 40)
    p.shot('second')
    p.keys(*'NIHONGO', 'HENKAN', 'KETTEI')
    p.shot('flushed')
    p.keys('A', 'KETTEI')
    p.frame += 100
    p.shot('passed')
    return p


def scenarios(cistat, screens):
    def start():
        p = run.Plan(cistat, screens)
        p.line('JFP @MODE@')
        p.shot('enabled')
        return p

    for name, p in run.scenarios(cistat, screens):
        if name in ('edit', 'layout', 'prompt', 'phrase', 'copy', 'edlin'):
            yield name, p

    p = start()
    p.keys(*'ECHO', 'SPACE', 'ZENKAKU')
    p.shot('wide-idle')
    p.keys('ZENKAKU', 'A')
    p.shot('narrow-a')
    p.keys('BS', 'ZENKAKU', 'A')
    p.shot('wide-a')
    p.keys('ESC', 'ZENKAKU', 'X', 'RETURN')
    p.shot('narrow-again')
    p.keys('CTRL+C')
    p.shot('idle-break')
    p.line(r'KEY F1 \xFENEW--abc')
    p.keys('F1')
    p.shot('defined')
    yield 'toggle-key', p

    p = start()
    p.echo('a')
    p.shot('before')
    p.keys('ZENKAKU')
    p.shot('after')
    yield 'toggle-pending', p

    for width in ('narrow', 'wide'):
        p = start()
        p.line('CONKEY K')
        if width == 'wide':
            p.keys('ZENKAKU')
        for i, key in enumerate(IDLE_KEYS):
            p.keys(key)
            p.shot(f'key-{i:02}')
        if width == 'wide':
            p.keys('ZENKAKU')
        p.keys('Q')
        p.shot('raw')
        yield width + '-keys', p

    for group, keys in PENDING:
        p = start()
        p.echo('')
        for i, key in enumerate(keys):
            if i:
                p.keys('ESC')
            p.reading('ai')
            shot = key.lower().replace('+', '-')
            p.shot('before-' + shot)
            p.keys(key)
            p.shot(shot)
        yield 'pending-' + group, p

    yield 'con-api', api(start())


def api_checks(p, mode):
    from quality import candidate

    return (
        v(p / 'first')[-1] == 'FIRST' and v(p / 'pending')[-1] == 'PENDING'
        and all((result := candidate(p / shot, mode)) and result[0] == KANJI
                for shot in ('first', 'pending')),
        v(p / 'second')[-1] == 'SECOND' and labels(p / 'second') == labels(p / 'enabled'),
        v(p / 'flushed')[-1] == 'FLUSHED' and labels(p / 'flushed') == labels(p / 'enabled')
        and v(p / 'passed')[-2:] == ['PASS: CON status, bytes and flush', P],
    )


def report(root):
    from quality import candidate, cells

    results = {}

    def record(key, passed, evidence, diff=False):
        status = 'differs' if diff else 'pass' if passed else 'fail'
        results.setdefault(key, []).append(f'{status}: {evidence}'.replace('|', r'\|'))

    cols = [(f'{model}-{ram}', mode) for model, ram in run.MATRIX for mode in run.MODES]
    for d, mode in cols:
        p = root / d / mode.lower()

        def main(shot):
            return v(p / shot)[-1]

        def system_raw(shot):
            return ''.join(c for c, _ in cells(p / shot)).rstrip()

        def system(shot):
            line = system_raw(shot)
            return line if mode == 'FEP' else re.split(r' {2,}|\?', line, maxsplit=1)[0].rstrip()

        def unchanged(a, b):
            return labels(p / a) == labels(p / b) and screen(p / a) == screen(p / b)

        verify_selection(p / 'prompt/enabled', mode)
        toggle = main('toggle-key/narrow-a') == P + 'echo a' and system('toggle-key/wide-a').endswith('あ')
        toggle &= expect_echo(p / 'toggle-key/narrow-again', 'x')
        record('ZENKAKU idle', toggle, 'ASCII `a` → `あ` → ASCII `x`' if toggle else str(main('toggle-key/narrow-again')))
        same = unchanged('toggle-pending/before', 'toggle-pending/after')
        record('ZENKAKU pending', same, 'reading unchanged' if same else
               f'row `{system_raw("toggle-pending/after").strip()}`', diff=not same)
        bs = system('edit/bs')
        record('BS pending', bs.endswith('あ') and main('edit/bs') == P + 'echo', f'`{bs}`')
        for name, shot in [('ESC', 'esc'), ('Ctrl-C', 'pending-ctrl-c')]:
            ok = main('edit/' + shot) == P + 'echo' and labels(p / ('edit/' + shot)) == labels(p / 'edit/enabled')
            record(name + ' pending', ok, 'cancelled; DOS `echo` remains' if ok else main('edit/' + shot))
        ok = v(p / 'toggle-key/idle-break')[-2:] == [P + '^C', P]
        record('Ctrl-C idle', ok, '`^C`, new prompt' if ok else main('toggle-key/idle-break'))
        first, second = main('edit/first-return'), main('edit/second-return')
        confirmed = first == P + 'echo ' + KANJI and expect_echo(p / 'edit/second-return', KANJI)
        submitted = expect_echo(p / 'edit/first-return', KANJI)
        record('Return pending candidate', confirmed, 'confirm → submit' if confirmed else
               'first Return submits' if submitted else f'`{first}` → `{second}`', diff=submitted)
        for key, text in [('F1', 'e'), ('F3', 'echo ' + KANJI)]:
            got = main('edit/template-' + key.lower())
            record(key + ' template after converted line', got == P + text, f'`{got}`')
        got = main('toggle-key/defined')
        ok = got == P + 'abc' and labels(p / 'toggle-key/defined')[4:10] == tuple(b'\xfeNEW--')
        record('KEY-defined F1', ok, '`abc` + `NEW--` label' if ok else f'`{got}`')

        for group, keys in PENDING:
            for key in keys:
                name = key.lower().replace('+', '-')
                shot = 'pending-' + group + '/' + name
                base = 'pending-' + group + '/before-' + name
                assert system(base).endswith('あい') and main(base) == P + 'echo', (p, base, system(base), main(base))
                same = unchanged(base, shot)
                row = system(shot)
                # A front-end-only redraw/change is a difference, not DOS key leakage.
                evidence = ('unchanged' if same else 'reading text unchanged; labels changed'
                            if row == system(base) and main(shot) == P + 'echo'
                            else f'`{row}`; `{main(shot)}`')
                record(key + ' during reading', same, evidence, diff=not same and main(shot) == P + 'echo')
        for width in ('narrow', 'wide'):
            def payload(shot, ended=False):
                lines = v(p / (width + '-keys/' + shot))
                start = lines.index('Raw CON (q exits):') + 1
                if ended:
                    assert lines[-1] == P, (p, width, lines)
                    lines = lines[:-1]
                return bytes.fromhex(''.join(lines[start:]))
            old = b''
            for i, (key, expected) in enumerate(zip(IDLE_KEYS, IDLE_BYTES, strict=True)):
                now = payload(f'key-{i:02}')
                assert now.startswith(old), (p, width, key, old, now)
                produced = now[len(old):]
                record(f'{key} idle ({width})', produced == expected, produced.hex(' ') or 'no bytes')
                old = now
            assert payload('raw', ended=True) == old, (p, width)
        focus = [candidate(p / ('phrase/' + shot), mode) for shot in ('first', 'short', 'long', 'right', 'left')]
        ok = all(focus) and focus[0][1] != focus[1][1] and focus[2][1] != focus[3][1] and focus[3][1] != focus[4][1]
        def format_focus(value):
            if not value:
                return 'no candidate'
            t, span = value
            return t if not span else t[:span[0]] + '[' + t[slice(*span)] + ']' + t[span[1]:]
        record('Shift+Left/Right, Right/Left in candidate', ok, ' → '.join(map(format_focus, focus)))

        before = pixels(p / 'prompt/enabled')
        pending = pixels(p / 'prompt/first')
        after = pixels(p / 'prompt/confirmed')
        ok = before == after and pending != before
        record('Labels before/during/after', ok, 'row restored' if ok else 'row not restored')
        ok = pixels(p / 'layout/candidate') == pixels(p / 'layout/held-shift')
        record('Hold Shift during candidate', ok, 'row unchanged' if ok else 'row changed', diff=not ok)
        h = p / 'layout'
        ok = [len(screen(h / s)) for s in ('hidden', 'enabled', 'hide-while-enabled', 'off')] == [25, 24, 24, 25]
        ok &= 'JFP off; plain CON input.' in v(h / 'off')
        record('ESC[>1h hidden labels / OFF', ok, '25 → 24 → 24 → 25 rows' if ok else 'unexpected layout or OFF')
        for label, ok in zip(('INT 21h 06h/07h/0Bh', 'INT 21h 0Ch candidate flush', 'INT 21h 0Ch cached trail flush'),
                             api_checks(p / 'con-api', mode)):
            record(label, ok, 'probe checkpoint reached' if ok else main('con-api/passed'))
        for name, file, suffix in [('copy', 'J.TXT', b'\r\n'), ('edlin', 'E.TXT', b'\r\n\x1a')]:
            try:
                data = j3a.get(p / name, file)
            except SystemExit:
                data = b''
            tail = v(p / (name + '/type'))[-3:]
            ok = data == KANJI.encode('shift_jis') + suffix and tail == [P + 'TYPE ' + file, KANJI, P]
            if name == 'edlin':
                ok &= any(re.fullmatch(r'\s+1: ' + KANJI, line) for line in v(p / 'edlin/list'))
            record(name.upper(), ok, f'`{data.hex(" ")}`')
    print('| Key or interaction | ' + ' | '.join(f'{d} {m}' for d, m in cols) + ' |')
    print('|---' * (1 + len(cols)) + '|')
    for key, row in results.items():
        print('| ' + ' | '.join([key, *row]) + ' |')


if __name__ == '__main__':
    if sys.argv[1:2] == ['report']:
        report(Path(sys.argv[2]))
    else:
        run.main(scenarios)
