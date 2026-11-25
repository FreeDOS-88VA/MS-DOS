#!/usr/bin/env python3
"""J3d real keyboard comparison and FAT-byte checks (run and check)."""
from pathlib import Path
import re
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'J3c'))
import run
from checks import P, expect_echo, j3a, labels, load, screen, v
from quality import candidate

run.MATRIX = (('va', 640), ('va2', 640))


def scenarios(pc, screens):
    def plan(selector='ON'):
        p = run.Plan(pc, screens)
        if selector:
            p.line('JFP ' + selector)
        return p

    def shifted(p):
        # Hold Shift through the primitive probe's status read.
        p.event('key-down SHIFT', 20)
        p.keys('SPACE')
        p.event('key-up SHIFT', 40)

    p = plan(None)
    p.line('SPACEAX', 150)
    p.keys('SPACE')
    shifted(p)
    p.keys('HENKAN', 'SHIFT+HENKAN')
    p.event('key-down KANA', 40)
    p.keys('SPACE')
    shifted(p)
    p.keys('A')
    p.event('key-up KANA', 40)
    p.keys('CTRL+SPACE', 'GRPH+SPACE', 'RETURN')
    p.shot('ax')
    yield 'primitive', p

    for name, forward in [('space', 'SPACE'), ('henkan', 'HENKAN')]:
        def previous(p):
            p.keys('SHIFT+HENKAN')

        p = plan()
        p.echo('nihon')
        p.shot('reading')
        for button, phase in [(forward, 'first'), (forward, 'next'), (None, 'previous')]:
            p.keys(button) if button else previous(p)
            p.shot(phase)
        p.keys('RETURN')
        p.shot('confirmed')
        p.keys('RETURN')
        p.shot('echo')
        yield name + '-prompt', p

        p = plan('FEP')
        p.line('COPY CON J.TXT')
        p.keys('ZENKAKU', *'NIHON', forward, forward)
        previous(p)
        p.keys('KETTEI', 'RETURN', 'F10', 'RETURN')
        p.shot('saved')
        yield name + '-file', p

        p = plan()
        p.echo('')
        p.event('key-down KANA', 40)
        p.keys('A')
        p.shot('reading')
        p.keys(forward)
        p.shot('first')
        p.keys(forward)
        p.shot('next')
        previous(p)
        p.shot('previous')
        p.event('key-up KANA', 40)
        p.keys('KETTEI', 'RETURN')
        p.shot('echo')
        yield name + '-kana', p

    for name, selector in [('idle', 'ON'), ('plain', None)]:
        p = plan(selector)
        p.keys(*'ECHO', 'SPACE', 'A', 'SPACE', 'B', 'RETURN')
        p.shot('ascii')
        if selector:
            p.keys(*'ECHO', 'SPACE', 'A', 'ZENKAKU', 'SPACE', 'ZENKAKU', 'B', 'RETURN')
            p.shot('kana')
            p.line('COPY CON IDLE.TXT')
            p.keys('A', 'SPACE', 'B', 'RETURN', 'A', 'ZENKAKU', 'SPACE', 'ZENKAKU', 'B',
                   'RETURN', 'F10', 'RETURN')
            p.shot('saved')
        yield name, p

    p = plan('ROM')
    p.echo('nihon')
    p.keys('SPACE')
    p.shot('space')
    p.keys('HENKAN')
    p.shot('henkan')
    p.keys('KETTEI', 'RETURN')
    p.shot('echo')
    yield 'rom', p

    for name, p in run.scenarios(pc, screens):
        if name == 'phrase':
            p.body = [cmd.replace('input-line JFP @MODE@', 'input-line JFP ON') for cmd in p.body]
            yield name, p


def free(path, total=655360):
    text = '\n'.join(v(path))
    assert f'{total} バイトの総メモリ' in text
    return int(re.search(r'(\d+) バイトの空き\s*$', text, re.MULTILINE)[1])


def check_plain(plain, extra):
    def localized_dir(path):
        lines = v(path)
        return [line.replace('個のファイル', 'File(s)') for line in lines] if path == directory else lines

    for model, _ in run.MATRIX:
        root = plain / model
        directory = root / 'dir/first'
        print(model)
        # Reuse the historical checks with the Japanese DIR and CHKDSK wording.
        with patch.object(j3a, 'relevant', localized_dir), patch.object(j3a, 'memory', free):
            assert j3a.regression(root) == 524032
        for case in ('eof-1', 'eof-2'):
            path = extra / model / case
            assert j3a.get(path, 'T.TXT') == b'ABC\r\nDEF\r\n'
            assert v(path / 'end')[-3:] == ['ABC', 'DEF', P]
        print('Two additional F10 cold boots: PASS')


def check(base, after, old_base, old_after):
    old = load('old_check', 'docs/J3b.2/check.py')
    for model, ram in run.MATRIX:
        b, a = (root / f'{model}-{ram}/j3d' for root in (base, after))

        def same(one, two):
            # Ignore build banner only. Compare DOS main text and raw system-row words.
            def main(path):
                lines = [line.split(' Release ')[0] if line.startswith('日本語MS-DOS version') else line
                         for line in screen(path)]
                return [re.sub(r'\d+(?= バイトの空き$)', 'FREE', line) for line in lines]

            assert main(one) == main(two), (one, two)
            assert labels(one) == labels(two), (one, two)

        ax = 'AX: 342000 342001 352000 A52001 342008 342009 1DC108 342020 342010'
        for root in (b, a):
            assert ax in v(root / 'primitive/ax')
        assert candidate(b / 'space-prompt/first', 'FEP') is None
        for name in ('prompt', 'kana'):
            for stage in ('reading', 'first', 'next', 'previous', 'echo'):
                same(a / f'space-{name}/{stage}', a / f'henkan-{name}/{stage}')
                same(a / f'henkan-{name}/{stage}', b / f'henkan-{name}/{stage}')
        same(a / 'space-prompt/confirmed', a / 'henkan-prompt/confirmed')
        p = a / 'space-prompt'
        first, nxt, prev = (candidate(p / stage, 'FEP') for stage in ('first', 'next', 'previous'))
        assert first and first[0] == '日本' and nxt and nxt != first and prev == first, (first, nxt, prev)
        assert v(p / 'confirmed')[-1] == P + 'echo 日本'
        assert expect_echo(p / 'echo', '日本')
        k = a / 'space-kana'
        assert old.system_row(k / 'reading') == '[H] ち'
        expected = ('血', '地', '血') if model == 'va' else ('値', '地', '値')
        assert tuple(candidate(k / stage, 'FEP')[0] for stage in
                     ('first', 'next', 'previous')) == expected
        data = b'\x93\xfa\x96\x7b\r\n'
        for root in (b, a):
            assert j3a.get(root / 'henkan-file', 'J.TXT') == data
        assert j3a.get(a / 'space-file', 'J.TXT') == data
        assert j3a.get(a / 'idle', 'IDLE.TXT') == b'a b\r\na b\r\n'
        for path in ('idle/ascii', 'idle/kana', 'plain/ascii'):
            assert expect_echo(a / path, 'a b')
            same(a / path, b / path)
        assert candidate(a / 'rom/space', 'ROM')[0] == '日本'
        assert expect_echo(a / 'rom/echo', 'にほん')
        for name in ('rom', 'phrase'):
            for capture in (b / name).glob('*.tvram.bin'):
                shot = capture.name.removesuffix('.tvram.bin')
                same(a / name / shot, b / name / shot)
        print(model, ram, 'primitive/candidates/confirm/bytes/idle/plain/ROM/phrase: PASS;',
              repr(first[0]), '->', repr(nxt[0]), '->', repr(prev[0]))
        b, a = (root / model for root in (old_base, old_after))
        cases = sorted(path.name for path in b.iterdir())
        assert len(cases) == 10
        count = 0
        for name in cases:
            for capture in (b / name).glob('*.tvram.bin'):
                shot = capture.name.removesuffix('.tvram.bin')
                same(a / name / shot, b / name / shot)
                assert j3a.label_pixels(a / name / shot) == j3a.label_pixels(b / name / shot)
                count += 1
        for root in (b, a):
            assert v(root / 'api/pass')[-2:] == ['PASS: FEP status, bytes and flush', P]
            # These old plans send one Return, which now only confirms.
            assert j3a.get(root / 'copy', 'J.TXT') == 'にほんご'.encode('shift_jis')
            try:
                j3a.get(root / 'edlin', 'E.TXT')
            except SystemExit as error:
                assert str(error) == 'not found: E.TXT'
            else:
                raise AssertionError('Unexpected EDLIN file from the historical plan')
        assert count == 51
        assert free(b / 'layout-mode/memory') == 524032
        assert free(a / 'layout-mode/memory') == 524032
        print(model, 'unchanged J3b.2 project plans: 51 matching captures (except banner and memory);',
              'FEPBYTE PASS; old COPY/EDLIN matched baseline; free: 524032 on both builds')


def check_edlin(out):
    for model, ram in (('va', 640), ('va2', 256), ('va2', 640)):
        data = j3a.get(out / f'{model}-{ram}/fep/edlin', 'E.TXT')
        assert data == bytes.fromhex('93 FA 96 7B 8C EA 0D 0A 1A'), (model, ram, data)
        print(model, ram, 'E.TXT:', data.hex(' '))


if __name__ == '__main__':
    if sys.argv[1] == 'check':
        check(*map(Path, sys.argv[2:]))
    elif sys.argv[1] == 'check-plain':
        check_plain(*map(Path, sys.argv[2:]))
    elif sys.argv[1] == 'check-edlin':
        check_edlin(Path(sys.argv[2]))
    else:
        run.main(scenarios, ('J3D',))
