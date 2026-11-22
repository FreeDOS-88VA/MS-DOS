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
FIXED_WIDTH = {'MEM.11', 'MEM.12', 'MEM.13', 'MEM.14', 'TREE.7'}


def literal(text):
    # Significant final ASCII spaces are written as \\s in the catalog.
    text = re.sub(r'(?:\\s)+$', lambda m: ' ' * (len(m[0]) // 2), text)
    return text.encode('shift_jis')


def catalog():
    result = {}
    for line in (HERE / 'JPN-MS.tsv').read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        key, *strings = line.split('\t')
        if not strings or key in result:
            raise ValueError(key)
        result[key] = [literal(s) for s in strings]
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
                        if key in FIXED_WIDTH and len(src) != len(dst):
                            raise ValueError(f'{key}: fixed layout width changed')
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


def localize_asm(tree):
    """Replace only catalogued quoted DB fields, in the disposable export."""
    files = {}
    path = None
    for line in (HERE / 'JPN-ASM.tsv').read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        if line.startswith('@'):
            path = (tree / line[1:]).resolve()
            if not path.is_relative_to(tree.resolve()) or path.suffix != '.ASM':
                raise ValueError(f'Invalid ASM path: {line}')
            continue
        if path is None:
            raise ValueError('ASM translation before file header')
        src, dst = map(literal, line.split('\t'))
        source = files.get(path)
        if source is None:
            source = path.read_bytes()
        if src.count(b'$') != dst.count(b'$') or src.count(b'%s') != dst.count(b'%s'):
            raise ValueError(f'{path}: terminator or format field changed: {src!r}')
        candidates = [(quote + src + quote, quote + dst + quote) for quote in (b"'", b'"')
                      if quote not in src and quote not in dst]
        matches = []
        lines = source.splitlines(keepends=True)
        for i, row in enumerate(lines):
            if not re.match(rb'(?i)^[ \t]*(?:[\w$?@]+[ \t]+)?DB[ \t]+', row):
                continue
            for old, new in candidates:
                matches.extend((i, old, new) for _ in range(row.count(old)))
        if len(matches) != 1:
            raise ValueError(f'{path}: expected one quoted DB field: {src!r}')
        i, old, new = matches[0]
        lines[i] = lines[i].replace(old, new, 1)
        files[path] = b''.join(lines)
    for path, source in files.items():
        path.write_bytes(source)


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export-tree', type=Path,
                        help='also translate ASM sources in this disposable exported tree')
    args = parser.parse_args()
    if args.export_tree and (args.export_tree.resolve() != HERE.parents[2]
                             or (args.export_tree / '.git').exists()):
        parser.error('--export-tree must be the disposable export containing this script')
    msg = render()
    if args.export_tree:
        localize_asm(args.export_tree)
    (HERE / 'JPN-MS.MSG').write_bytes(msg)
