#!/usr/bin/env python3
"""Mostra, com linha e conteudo, as strings ainda em portugues."""
import re
import sys
import pathlib

PT = re.compile(
    r'\b(nao|nenhum|levanta|informad|conexao|tabela|coluna|valor|esperava'
    r'|invalid|precisa|falta|erro|linha|arquivo|versao|migracao|transacao'
    r'|desfaz|aplicad|dialeto|vazio|vazia|duplicad|suportad|fechad|abert'
    r'|ja |apenas|somente|deve|use |usar|sem )', re.IGNORECASE)
LITERAL = re.compile(r"'([^']{6,})'")

for p in sys.argv[1:]:
    path = pathlib.Path(p)
    if not path.is_file():
        continue
    for n, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        if line.lstrip().startswith('//'):
            continue
        for m in LITERAL.finditer(line):
            if PT.search(m.group(1)):
                print(f'{path.name}:{n}: {m.group(1)[:85]}')
