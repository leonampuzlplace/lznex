#!/usr/bin/env python3
"""Ajusta asserções de sonda que casavam o TEXTO em portugues das mensagens.

As mensagens foram traduzidas para ingles; as asserções passam a procurar o
fragmento ingles equivalente.
"""
import pathlib

EDITS = {
    'tests/ProbeQuery.lpr': [
        ("Pos('nao esta ligada', E.Message)", "Pos('not bound to a connection', E.Message)"),
    ],
    'tests/ProbeCompiler.lpr': [
        ("ELzNexBuilder,\n    'comentario'", "ELzNexBuilder,\n    'comment delimiter'"),
        ("'comentario'", "'comment delimiter'"),
        ("'nao permitido'", "'not allowed'"),
        ("ELzNexCompile, 'tabela'", "ELzNexCompile, 'table'"),
        ("'tabela'", "'table'"),
    ],
    'tests/ProbeMigration.lpr': [
        ("Pos('irreversivel', Msg)", "Pos('irreversible', Msg)"),
        ("Pos('coluna email nao existe', Msg)", "Pos('coluna email nao existe', Msg)"),
    ],
}


def main():
    root = pathlib.Path('.')
    for rel, pairs in EDITS.items():
        path = root / rel
        if not path.is_file():
            print(f'  AUSENTE {rel}')
            continue
        text = path.read_text(encoding='utf-8')
        changed = 0
        for old, new in pairs:
            if old == new:
                continue
            n = text.count(old)
            if n:
                text = text.replace(old, new)
                changed += n
        if changed:
            path.write_text(text, encoding='utf-8')
        print(f'  {rel}: {changed} asserções ajustadas')


if __name__ == '__main__':
    main()
