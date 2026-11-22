#!/usr/bin/env python3
"""M6: historical prompt/edit/monitor/Return gates through all selectors."""
import os
from pathlib import Path
import re
import sys

import run
from checks import P, adopt, expect_echo, j3a, j3b3, labels, pixels, screen, v, verify_selection
from safety import monitor_api, monitor_line, scenarios as monitor_scenarios


def compact(text, profile):
    """Keep the key and CISTAT sequence; shorten only the inter-action waits."""
    schedule = []
    previous = ''
    old_frame = frame = 0
    for line in text.splitlines():
        if line.startswith('wait-frame '):
            stamp = int(line.split()[1])
            gap = stamp - old_frame
            old_frame = stamp
            if profile == 'enabled':
                if previous.startswith('input-line '):
                    gap = min(gap, 350)
                gap = {40: 22, 25: 10}.get(gap, gap)
            elif profile == 'eof':
                if previous.startswith('input-line COPY CON '):
                    gap = min(gap, 350)
                elif previous in ('input-line ABC', 'input-line DEF'):
                    gap = min(gap, 120)
                elif previous in ('key-tap RETURN 3', 'input-line TYPE T.TXT'):
                    gap = min(gap, 375)
                elif previous == 'key-tap F10 3':
                    gap = min(gap, 40)
            elif profile == 'toggle' and previous.startswith('input-line LABELCHK '):
                gap = min(gap, 480)
            frame += gap
            line = f'wait-frame {frame}'
        schedule.append(line)
        previous = line
    return re.sub(r'^limit-frame \d+$', f'limit-frame {max(800, frame + 300)}',
                  '\n'.join(schedule) + '\n', flags=re.M)


class ScriptPlan:
    def __init__(self, script):
        self.text = script
        self.shots = re.findall(r'^capture (\S+)', script, re.M)

    def script(self, _):
        return self.text


class EnabledPlan:
    def __init__(self, plan):
        self.plan = plan
        self.shots = plan.shots

    def script(self, mode):
        return compact(self.plan.script(mode), 'enabled')


def plain(cistat, screens):
    assert screens, 'plain gate requires --screens'
    j3b3.wrap.j04.AFTER_PC = cistat
    wanted = {'after-boot', 'after-regression', 'dir', 'display', 'toggle', 'erase',
              'eof-1', 'eof-2', 'eof-3', 'ctrl-z', 'cancel-break'}
    for name, _, script in j3b3.wrap.scenarios():
        if name == 'display':
            # J0.4 steps 1–5 stop at redirected CLS; no supplemental LABELCHK probes.
            script = script.partition('capture redirected tvram screen\n')[0] + 'capture redirected tvram screen\nexit\n'
        profile = 'eof' if name.startswith('eof-') or name == 'ctrl-z' else name
        if name in wanted:
            yield name, ScriptPlan(compact(script, profile))
        if name in ('eof-1', 'eof-2'):
            yield name.replace('eof-', 'extra-eof-'), ScriptPlan(compact(script, profile))
    p = run.Plan(cistat, screens)
    p.line('JFP')
    p.shot('usage')
    p.keys('ZENKAKU')
    p.line('ECHO PLAIN')
    p.shot('plain')
    yield 'invocation', p


def enabled(cistat, screens):
    assert screens, 'enabled gate requires --screens'
    os.environ['AFTER_CISTAT'] = cistat
    for name, old in run.j3a.scenarios():
        if name in ('prompt', 'edit'):
            yield 'j3a-' + name, adopt(run.Plan(cistat, screens), old,
                **{'input-line JFP ROM': 'input-line JFP @MODE@', 'input-line JFP ON': 'input-line VER'})
    for name, p in run.scenarios(cistat, screens):
        if name == 'prompt':
            yield 'nihongo', p
    for name, p in monitor_scenarios(cistat, screens):
        if name != 'fault-fep':
            yield name, p
    for henkan in (False, True):
        p = run.Plan(cistat, screens)
        p.line('JFP @MODE@')
        p.shot('enabled')
        p.echo('nihongo')
        if henkan:
            p.keys('HENKAN')
        p.shot('pending')
        p.keys('RETURN')
        p.shot('first')
        p.keys('RETURN')
        p.shot('second')
        yield 'return-' + ('candidate' if henkan else 'reading'), p


class Report:
    def __init__(self, caption):
        self.caption = caption
        self.total = self.passed = self.differences = 0

    def check(self, name, ok, differs=False):
        self.total += 1
        self.passed += bool(ok)
        self.differences += bool(differs and not ok)
        status = 'PASS' if ok else 'DIFF' if differs else 'FAIL'
        print(f'{self.caption}\t{status}\t{name}')

    def finish(self):
        print(f'{self.caption}\tTOTAL\t{self.passed}/{self.total}')
        return self.passed + self.differences == self.total


def plain_report(p, reference, label):
    r = Report(label + ' plain')
    def s(name): return screen(p / name)
    def a(name): return v(p / name)
    def px(name): return pixels(p / name)
    r.check('J0.3/1 DIR/F3', any('File(s)' in line for line in a('dir/first'))
            and a('dir/recalled')[-1] == P + 'DIR' and s('dir/first') == s('dir/end'))
    for name in ('eof-1', 'eof-2', 'eof-3', 'extra-eof-1', 'extra-eof-2', 'ctrl-z'):
        r.check('J0.3/5,9 ' + name, j3a.get(p / name, 'T.TXT') == b'ABC\r\nDEF\r\n'
                and a(name + '/end')[-3:] == ['ABC', 'DEF', P])
    r.check('J0.3/9 editor baseline', all(s('after-regression/' + shot)[1:] ==
            screen(reference / 'base-regression' / shot)[1:] for shot in ('typed', 'backspace', 'end'))
            and a('after-regression/backspace')[-1] == P + 'VER'
            and a('after-regression/end')[-2:] == ['MS-DOS Version 4.00', P])
    r.check('J0.3/9 Ctrl-X', a('cancel-break/cancelled')[-1] == P + 'XY\\'
            and a('cancel-break/recalled')[-1].strip() == 'VER')
    r.check('J0.3/9 Ctrl-C', a('cancel-break/break')[-2].endswith('^C')
            and a('cancel-break/end')[-2:] == ['MS-DOS Version 4.00', P])
    base = pixels(reference / 'base-boot/prompt')
    r.check('J0.4 boot labels + 24 rows', px('after-boot/prompt') == base == px('display/boot')
            and len(s('display/boot')) == 24 and a('display/boot')[-1] == P)
    r.check('J0.4 Shift and release', px('display/held') != base and px('display/released') == base)
    r.check('J0.4 DIR/scroll and TYPE', px('display/dir') == px('display/type') == base
            and a('display/dir')[-1] == P and any('File(s)' in line for line in a('display/dir'))
            and a('display/type')[0] == 'TYPE LINE 19' and a('display/type')[-2:] == ['TYPE LINE 40', P])
    r.check('J0.4 CLS', px('display/cls') == base and a('display/cls') == [P] and s('display/cls')[1] == P)
    r.check('J0.4 redirected CLS', px('display/redirected') == base and j3a.get(p / 'display', 'F.TXT') == b'\x1b[2J\x1b[H')
    r.check('J0.4 clear + home', px('erase/clear-mark') == px('erase/home-mark') == base
            and s('erase/clear-mark')[0] == 'CLEARED' and s('erase/home-mark')[0] == 'HOMERED')
    for kind in ('block', 'byte'):
        h, show = f'toggle/hide-{kind}', f'toggle/show-{kind}'
        r.check('J0.4 hide/show ' + kind, len(s(h)) == 25 and not any(px(h)) and len(s(show)) == 24 and px(show) == base)
    r.check('J0.4 hide preserves text', s('toggle/pre') == s('toggle/hide')[:24])
    r.check('J0.4 row 25 scroll / show', s('toggle/scroll') == [f'LINE #{i:02d}' for i in range(7, 31)] + ['']
            and s('toggle/show') == s('toggle/scroll')[1:] and px('toggle/show') == base)
    r.check('Plain boot and revised JFP usage', 'Usage: JFP ON | ROM | FEP | OFF' in a('invocation/usage')
            and any('ON selects FEP' in line for line in a('invocation/usage'))
            and a('invocation/plain')[-3:] == [P + 'ECHO PLAIN', 'PLAIN', P])
    return r.finish()


def enabled_report(p, label, selector):
    from quality import candidate, cells

    mode = 'FEP' if selector == 'ON' else selector
    r = Report(label + ' ' + selector + ' (' + mode + ')')

    def last(path): return v(p / path)[-1]

    for path in ('j3a-prompt', 'nihongo', 'monitor-line', 'monitor-api', 'return-reading', 'return-candidate'):
        verify_selection(p / path / 'enabled', mode)
    cand = candidate(p / 'j3a-prompt/candidate', mode)
    r.check('J3a/2 日本 candidate, confirm and ECHO', cand and cand[0] == '日本'
            and last('j3a-prompt/candidate') == P + 'echo' and last('j3a-prompt/confirm') == P + 'echo 日本'
            and expect_echo(p / 'j3a-prompt/echo', '日本'))
    q = p / 'j3a-edit'
    bs_text = ''.join(c for c, _ in cells(q / 'bs'))
    r.check('J3a/6 reading BS', bs_text.startswith('あ' if mode == 'ROM' else '[H] あ')
            and last('j3a-edit/bs') == P + 'echo' and last('j3a-edit/bs-confirm') == P + 'echo あ')
    r.check('J3a/6 pending F1', labels(q / 'pending-f1') == labels(q / 'bs') and screen(q / 'pending-f1') == screen(q / 'bs'))
    r.check('J3a/6 ESC', last('j3a-edit/esc') == P + 'echo あ' and pixels(q / 'esc') == pixels(p / 'j3a-prompt/boot'))
    r.check('J3a/6 pending and idle Ctrl-C', last('j3a-edit/ctrl-c') == P + 'echo あ'
            and pixels(q / 'ctrl-c') == pixels(p / 'j3a-prompt/boot') and expect_echo(q / 'submit', 'あ')
            and v(q / 'idle-ctrl-c')[-2:] == [P + '^C', P])
    r.check('J3a/6 F1/F3 template', last('j3a-prompt/template-f1') == P + 'e'
            and last('j3a-prompt/template-f3') == P + 'echo 日本')
    bs = p / 'j3a-prompt/kanji-bs'
    y = max(i for i, line in enumerate(screen(bs)) if line)
    r.check('J3a/6 DBCS BS', v(bs)[-1] == P + 'echo 日' and j3a.words(bs, y)[11:13] == (32, 32))
    q = p / 'nihongo'
    cands = [candidate(q / shot, mode) for shot in ('first', 'next', 'previous')]
    r.check('J3b.3/2 日本語, next/previous, KETTEI + Return', all(cands) and cands[0][0] == cands[2][0] == '日本語'
            and last('nihongo/confirmed') == P + 'echo 日本語' and expect_echo(q / 'submitted', '日本語'))
    for name, check in [('monitor-line', monitor_line), ('monitor-api', monitor_api)]:
        _, nested, _ = check(p / name, mode)
        r.check(f'J3b.3/5 {name}: nested DOS/text {nested[0]}/{nested[1]}', nested == [0, 0],
                differs=(mode == 'ROM' and nested[0] == 0 and nested[1] > 0))
    for kind, text in [('reading', 'にほんご'), ('candidate', '日本語')]:
        q = p / ('return-' + kind)
        r.check(f'J3b.3/8 Return ({kind})', v(q / 'first')[-1] == P + 'echo ' + text and expect_echo(q / 'second', text))
    q = p / 'j3a-prompt'
    normal = pixels(q / 'boot')
    r.check('JFP OFF / no active input', 'JFP off; plain CON input.' in v(q / 'off')
            and v(q / 'disabled')[-3:] == [P + 'ECHO PLAIN', 'PLAIN', P]
            and all(pixels(q / shot) == normal for shot in ('off', 'off-release', 'disabled'))
            and pixels(q / 'off-shift') != normal)
    return r.finish()


if __name__ == '__main__':
    sub = sys.argv.pop(1)
    if sub == 'run-enabled':
        run.main(lambda *a: ((name, EnabledPlan(p)) for name, p in enabled(*a)), ('ON', 'ROM', 'FEP'))
    elif sub == 'run-plain':
        run.main(plain, ('PLAIN',))
    elif sub == 'report':
        enabled_root, plain_root, reference = map(Path, sys.argv[1:4])
        ok = True
        for model, ram in run.MATRIX:
            d = f'{model}-{ram}'
            ok &= plain_report(plain_root / d / 'plain', reference / d, d)
            for selector in ('ON', 'ROM', 'FEP'):
                ok &= enabled_report(enabled_root / d / selector.lower(), d, selector)
        sys.exit(0 if ok else 1)
    else:
        raise SystemExit(f'unknown subcommand: {sub}')
