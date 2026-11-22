#!/usr/bin/env python3
"""Materialize JPN-MS.MSG from USA-MS.MSG and the UTF-8 JPN-MS.tsv."""
import re
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
HEADER = re.compile(rb'([A-Z][A-Z0-9]+ +)([0-9a-f]{4})( +[0-9]{4})')
RECORD = re.compile(rb'([0-9]{4}) U [0-9]{4} ')
LITERAL = re.compile(rb'"([^"\r\n]*)"')
SUB = re.compile(rb'%[0-9]')


def catalog():
    result = {}
    for line in (HERE / 'JPN-MS.tsv').read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        key, *strings = line.split('\t')
        if not strings or key in result:
            raise ValueError(key)
        result[key] = [s.encode('shift_jis') for s in strings]
    return result


def render():
    translations = catalog()
    output = bytearray()
    source = (HERE / 'USA-MS.MSG').read_bytes().replace(b'\r\n', b'\n')
    groups = re.split(rb'(?m)^(?=[A-Z][A-Z0-9]+ +[0-9a-f]{4} +[0-9]{4}\n)', source)
    output.extend(groups.pop(0).replace(b'\n', b'\r\n'))
    for block in groups:
        header, body = block.split(b'\n', 1)
        name, _, count = HEADER.fullmatch(header).groups()
        output.extend(name + f'{len(output):04x}'.encode() + count + b'\r\n')
        group = name.strip().decode('ascii')
        for entry in re.split(rb'(?m)^(?=[0-9]{4} U [0-9]{4} )', body):
            match = RECORD.match(entry)
            if match:
                key = f'{group}.{int(match[1])}'
                if key in translations:
                    before = LITERAL.findall(entry)
                    after = translations.pop(key)
                    if len(before) != len(after) or any(b'"' in s for s in after):
                        raise ValueError(f'{key}: literal count/quoting')
                    for src, dst in zip(before, after):
                        if Counter(SUB.findall(src)) != Counter(SUB.findall(dst)) or src.count(b'$') != dst.count(b'$'):
                            raise ValueError(f'{key}: substitution or terminator changed')
                    if len(entry) + sum(map(len, after)) - sum(map(len, before)) > 255:
                        raise ValueError(f'{key}: record too long')
                    strings = iter(after)
                    entry = LITERAL.sub(lambda _: b'"' + next(strings) + b'"', entry)
            output.extend(entry.replace(b'\n', b'\r\n'))
    if translations:
        raise ValueError(f'Unknown message IDs: {sorted(translations)}')
    return output


if __name__ == '__main__':
    (HERE / 'JPN-MS.MSG').write_bytes(render())
