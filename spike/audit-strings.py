#!/usr/bin/env python3
import re
import sys
import pathlib

PT = re.compile(
    r'\b(nao|nenhum|nenhuma|levanta|informad[oa]|conexao|tabela|coluna|valor'
    r'|esperava|invalid[oa]|precisa|falta|faltando|erro|linha|linhas|arquivo'
    r'|versao|migracao|transacao|desfaz|aplicad[oa]|dialeto|consulta|vazio'
    r'|vazia|duplicad[oa]|suportad[oa]|fechad[oa]|abert[oa]|ja |apenas'
    r'|somente|deve|devem|use |usar|sem )', re.IGNORECASE)

LITERAL = re.compile(r"'([^']{6,})'")

def main(paths):
    grand = 0
    for p in sorted(paths):
        path = pathlib.Path(p)
        if not path.is_file():
            continue
        text = path.read_text(encoding='utf-8', errors='replace')
        hits = []
        for line_no, line in enumerate(text.splitlines(), 1):
            stripped = line.lstrip()
            if stripped.startswith('//'):
                continue
            for m in LITERAL.finditer(line):
                s = m.group(1)
                if PT.search(s):
                    hits.append((line_no, s[:70]))
        if hits:
            print(f'{path.name:38s} {len(hits):4d}')
            grand += len(hits)
    print(f'{"TOTAL":38s} {grand:4d}')

if __name__ == '__main__':
    main(sys.argv[1:])
