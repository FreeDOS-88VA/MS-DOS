#!/usr/bin/env python3
"""Run K1 on VA/VA2; use K1BYTES.COM and CONKEY.COM on a scratch image."""
import runpy
from pathlib import Path

j3a = runpy.run_path(str(Path(__file__).resolve().parents[2] / 'docs/J3a/run.py'))
Plan = j3a['Plan']


def line(p, text):
    p.line(text, delay=390)


def mode(p, name):
    if name != 'plain':
        line(p, 'JFP ' + ('ROM' if name == 'rom' else 'ON'))
    if name == 'off':
        line(p, 'JFP OFF')


def held(p, mod, *keys):
    p.event('key-down ' + mod, 40)
    p.keys(*keys)
    p.event('key-up ' + mod, 40)


def scenarios():
    for name in ('plain', 'on', 'off', 'rom'):
        p = Plan()
        mode(p, name)
        for graph in (False, True):
            if graph:
                line(p, 'K1BYTES G')
            for api in ('line', 'raw'):
                line(p, 'K1BYTES' + (' R' if api == 'raw' else ''))
                p.keys('A', 'KANA', 'A', 'SHIFT+KANA', 'A')
                held(p, 'KANA', 'A', '3', 'E', '4', 'SHIFT+E')
                p.keys('A')
                held(p, 'GRPH', 'A', '1', 'Q', '0', 'Z', '3', 'SPACE')
                p.keys('A', 'RETURN')
                p.frame += 160  # Let the full BIOS trace scroll onto the screen.
                p.shot(('graph-' if graph else 'kanji-') + api)
        yield name, p

        p = Plan()
        mode(p, name)
        p.keys(*'ECHO', 'SPACE')
        held(p, 'KANA', '3', 'E', '4')
        p.keys('A', 'RETURN')
        p.shot('prompt')
        p.line('COPY CON J.TXT')
        held(p, 'KANA', '3', 'E', '4')
        p.keys('A', 'RETURN', 'F10', 'RETURN')
        p.line('TYPE J.TXT')
        p.shot('copy')
        p.line('EDLIN E.TXT')
        line(p, 'I')
        held(p, 'KANA', '3', 'E', '4')
        p.keys('A', 'RETURN', 'F10', 'RETURN')
        p.line('E')
        p.line('TYPE E.TXT')
        p.shot('edlin')
        yield 'apps-' + name, p

        p = Plan()
        mode(p, name)
        line(p, r'KEY F1 \xFENEW--abc')
        line(p, 'CONKEY K')
        p.keys(*(f'F{i}' for i in range(1, 11)), *(f'SHIFT+F{i}' for i in range(1, 11)))
        p.keys(*'ROLLUP ROLLDOWN INS DEL UP LEFT RIGHT DOWN HOME HELP'.split())
        p.keys(*'SHIFT+UP SHIFT+LEFT SHIFT+RIGHT SHIFT+DOWN SHIFT+HOME'.split())
        p.keys(*'CTRL+UP CTRL+LEFT CTRL+RIGHT CTRL+DOWN CTRL+HOME'.split())
        p.keys('BS', 'ESC', 'CTRL+C', 'Q')
        p.shot('raw')
        yield 'keys-' + name, p

    p = Plan()
    mode(p, 'on')
    p.keys(*'ECHO', 'SPACE', 'ZENKAKU', *'NIHON', 'HENKAN')
    p.shot('candidate')
    p.keys('KETTEI', 'RETURN', 'ZENKAKU')
    p.shot('romaji')
    p.keys(*'ECHO', 'SPACE', 'ZENKAKU')
    held(p, 'KANA', 'A', 'T', 'AT')
    p.shot('kana-reading')
    p.keys('KETTEI', 'RETURN', 'ZENKAKU')
    p.shot('kana-confirmed')
    yield 'composition', p

    p = Plan()
    mode(p, 'rom')
    p.keys(*'ECHO', 'SPACE', 'ZENKAKU', *'NIHON', 'HENKAN')
    p.shot('candidate')
    p.keys('KETTEI', 'RETURN')
    p.shot('confirmed')
    yield 'rom-composition', p

    p = Plan()
    for key in ('BS', 'LEFT', 'DEL'):
        line(p, 'K1BYTES')
        p.keys('SHIFT+A', 'UP', 'SHIFT+B', 'RIGHT', key, 'RETURN')
        p.shot(key.lower())
    yield 'caret-edit', p

    p = Plan()
    line(p, 'K1BYTES G')
    line(p, 'K1BYTES')
    held(p, 'GRPH', 'A')
    p.keys('RETURN')
    p.shot('first-cr')
    p.keys('RETURN')
    p.shot('second-cr')
    line(p, 'K1BYTES R')
    held(p, 'GRPH', 'A')
    p.keys('RETURN')
    p.shot('raw')
    yield 'graph-lead', p

    p = Plan()
    p.line('CHKDSK', delay=1500)
    p.shot('free')
    yield 'memory', p


if __name__ == '__main__':
    j3a['main'].__globals__['scenarios'] = scenarios
    j3a['main']()
