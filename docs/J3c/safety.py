#!/usr/bin/env python3
"""M5 monitor/fault cases and decoder, also used in the M6 gate."""
from pathlib import Path
import re
import sys

import run
from checks import P, expect_echo, v, verify_selection
from keys import api, api_checks


class MonitorPlan(run.Plan):
    def script(self, mode):
        script = super().script(mode)
        rom = mode == 'ROM'
        return script.replace('input-line @MON@', 'input-line ' + ('ROMMON' if rom else 'FEPMON')).replace(
            'input-line @MONBYTE@', 'input-line ' + ('ROMBYTE' if rom else 'FMONBYTE'))


def scenarios(cistat, screens):
    def start():
        p = MonitorPlan(cistat, screens)
        p.line('JFP @MODE@')
        p.shot('enabled')
        return p

    p = start()
    p.line('@MON@')
    p.keys('ZENKAKU', *'NIHONGO', 'HENKAN')
    p.shot('converted')
    p.keys('HENKAN', 'SHIFT+HENKAN', 'KETTEI')
    p.shot('confirmed')
    p.keys('RETURN')
    p.shot('reported')
    yield 'monitor-line', p

    p = api(start())
    p.body = ['input-line @MONBYTE@' if line == 'input-line CONBYTE' else line for line in p.body]
    yield 'monitor-api', p

    p = start()
    p.only_modes = ('FEP',)
    p.line('BADBIOS')
    p.keys('ZENKAKU', *'NIHONGO', 'HENKAN')
    p.shot('bad-candidate')
    p.keys('KETTEI')
    p.shot('confirmed')
    p.keys('RETURN')
    p.shot('reported')
    p.keys('ZENKAKU')
    p.echo('nihongo')
    p.keys('HENKAN', 'KETTEI', 'RETURN')
    p.shot('recovered')
    yield 'fault-fep', p


def stats(path, mode):
    body, = [line for line in v(path) if line.startswith('MON: ')]
    words = [int(s, 16) for s in body.split()[1:]]
    assert len(words) == (11 if mode == 'ROM' else 10), (path, words)
    return words[:8], words[8:10], words[10] if mode == 'ROM' else None


def monitor_line(p, mode):
    from quality import candidate

    pending = v(p / 'converted')
    confirmed = v(p / 'confirmed')
    assert pending[-1] == 'MON READY' and candidate(p / 'converted', mode)[0] == '日本語', p
    assert confirmed[-2:] == ['MON READY', '日本語'], (p, confirmed)
    out = v(p / 'reported')
    assert out[-3] == '日本語' and out[-1] == P, (p, out)
    calls, nested, kb = stats(p / 'reported', mode)
    if mode == 'FEP':
        assert calls == [1, 1, 1, 1, 0, 0, 0, 0], (p, calls)
    else:
        assert kb > 0, p
    return calls, nested, kb


def monitor_api(p, mode):
    assert all(api_checks(p, mode)), p
    calls, nested, kb = stats(p / 'passed', mode)
    if mode == 'FEP':
        assert calls == [3, 3, 0, 0, 0, 0, 0, 0], (p, calls)
    else:
        assert kb > 0, p
    return calls, nested, kb


def report(root, original):
    from quality import cells

    image = original.read_bytes()
    print('| Configuration | Mode | Context | INT 8Dh calls 03h–0Ah | INT 82h main calls | Nested 21h / 83h | D88 unchanged |')
    print('|---|---|---|---|---:|---:|---|')
    for model, ram in run.MATRIX:
        for mode in run.MODES:
            d = f'{model}-{ram}'
            p = root / d / mode.lower()
            for name, check in [('monitor-line', monitor_line), ('monitor-api', monitor_api)]:
                case = p / name
                verify_selection(case / 'enabled', mode)
                calls, nested, kb = check(case, mode)
                unchanged = (case / 'disk.d88').read_bytes() == image
                print(f'| {d} | {mode} | {name} | {" ".join(map(str, calls))} | {kb if kb is not None else "—"} | '
                      f'{nested[0]} / {nested[1]} | {"yes" if unchanged else "no"} |')

    print('\n| Configuration | FEP malformed-trail injection |')
    print('|---|---|')
    for model, ram in run.MATRIX:
        d = f'{model}-{ram}'
        p = root / d / 'fep' / 'fault-fep'
        verify_selection(p / 'enabled', 'FEP')
        row = ''.join(c for c, _ in cells(p / 'bad-candidate')).rstrip()
        out = v(p / 'reported')
        assert row == '[H] にほんご' and v(p / 'confirmed')[-2:] == ['MON READY', 'にほんご'], p
        assert out[-4] == 'にほんご' and out[-2:] == ['FAULT: injected invalid Shift-JIS trail', P], (p, out)
        assert stats(p / 'reported', 'FEP') == ([1, 1, 0, 0, 0, 0, 0, 0], [0, 0], None), p
        assert expect_echo(p / 'recovered', '日本語'), p
        print(f'| {d} | Reading retained, confirmed as にほんご; next genuine conversion printed 日本語 |')


if __name__ == '__main__':
    if sys.argv[1:2] == ['report']:
        report(*map(Path, sys.argv[2:4]))
    else:
        run.main(scenarios)
