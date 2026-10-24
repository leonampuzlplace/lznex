#!/usr/bin/env python3
"""Procura identificadores em portugues no codigo Pascal.

Ignora comentarios (// ... , { ... }, (* ... *)) e literais de string, porque
comentario em pt-BR e a regra e literal pode ser texto de mensagem.
"""
import re
import sys
import pathlib

# Radicais portugueses que nao existem (ou nao significam o mesmo) em ingles.
WORDS = [
    'acao', 'acentua', 'achou', 'ajuda', 'aninhad', 'antes', 'aplicad', 'apos',
    'arquivo', 'asercao', 'assercao', 'atualiza', 'aviso', 'banco', 'busca',
    'caminho', 'carga', 'coluna', 'comando', 'commitad', 'conexao', 'conferir',
    'consulta', 'contagem', 'correto', 'criar', 'cursor_', 'dado', 'depois',
    'descarta', 'desfaz', 'devolve', 'dentro', 'erro', 'escolha', 'esperado',
    'estado', 'falha', 'fonte', 'funciona', 'guarda', 'idioma', 'inicio',
    'insere', 'isolad', 'leitura', 'levanta', 'liberar', 'ligad', 'limite',
    'linha', 'lido', 'marca', 'maximo', 'mistur', 'nenhum', 'nome', 'nota',
    'obtido', 'ordena', 'pendente', 'pronto', 'proprio', 'quantidade',
    'recriar', 'resultado', 'retorna', 'salva', 'segura', 'sequencia',
    'seguranc', 'tabela', 'tamanho', 'tentativa', 'thread_', 'total_', 'valor',
    'vazia', 'vazio', 'verifica', 'vistas', 'volta',
]
PAT = re.compile('|'.join(WORDS), re.IGNORECASE)

# Identificador Pascal
IDENT = re.compile(r'\b[A-Za-z_][A-Za-z0-9_]*\b')


def strip_noise(line: str) -> str:
    """Remove comentario de linha e literais de string."""
    line = re.sub(r"'[^']*'", "''", line)
    i = line.find('//')
    if i >= 0:
        line = line[:i]
    line = re.sub(r'\{[^}]*\}', '', line)
    line = re.sub(r'\(\*.*?\*\)', '', line)
    return line


def main(paths):
    in_block = False
    total = 0
    for p in paths:
        path = pathlib.Path(p)
        if not path.is_file():
            continue
        hits = []
        in_block = False
        for n, raw in enumerate(path.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
            # comentario de bloco { } em varias linhas
            if in_block:
                if '}' in raw:
                    in_block = False
                continue
            if raw.lstrip().startswith('{') and '}' not in raw:
                in_block = True
                continue
            code = strip_noise(raw)
            for m in IDENT.finditer(code):
                ident = m.group(0)
                if len(ident) < 4:
                    continue
                if PAT.search(ident):
                    hits.append((n, ident, raw.strip()[:90]))
        if hits:
            print(f'\n=== {path}  ({len(hits)} ocorrencias)')
            seen = set()
            for n, ident, ctx in hits:
                if ident.lower() in seen:
                    continue
                seen.add(ident.lower())
                print(f'  {n:5d}  {ident:38s} | {ctx}')
            total += len(hits)
    print(f'\ntotal de ocorrencias: {total}')


if __name__ == '__main__':
    main(sys.argv[1:])
