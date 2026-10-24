#!/usr/bin/env python3
import re
import sys
import pathlib

PAT = re.compile(r'^(\s*)//\s+([A-Za-z_][A-Za-z0-9_]*)\s+—\s+(.*)$')

def fix_line(line: str):
    m = PAT.match(line.rstrip('\n'))
    if not m:
        return None
    indent, _name, rest = m.groups()
    if not rest:
        return None
    rest = rest[0].upper() + rest[1:]
    return f'{indent}// {rest}\n'

def main(paths):
    total = 0
    for p in paths:
        path = pathlib.Path(p)
        if not path.is_file():
            continue
        lines = path.read_text(encoding='utf-8').splitlines(keepends=True)
        changed = 0
        for i, line in enumerate(lines):
            new = fix_line(line)
            if new is not None and new != line:
                lines[i] = new
                changed += 1
        if changed:
            path.write_text(''.join(lines), encoding='utf-8')
            print(f'  {path.name}: {changed} comentarios')
            total += changed
    print(f'total: {total}')

if __name__ == '__main__':
    main(sys.argv[1:])
