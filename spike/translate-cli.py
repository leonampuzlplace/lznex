#!/usr/bin/env python3
"""Traduz as mensagens do CLI para ingles.

Substituicao literal e exata, par a par: evita regex pegar texto parecido em
comentario (que fica em pt-BR).
"""
import pathlib
import sys

PAIRS = [
    # help
    ("'lznex -- migrations e seeds para Lazarus/FPC'",
     "'lznex -- migrations and seeds for Lazarus/FPC'"),
    ("'Uso: lznex <comando> [argumentos] [--flags]'",
     "'Usage: lznex <command> [arguments] [--flags]'"),
    ("'  migrate:latest              aplica todas as pendentes num novo batch'",
     "'  migrate:latest              run every pending migration in a new batch'"),
    ("'  migrate:rollback [--all]    desfaz o ultimo batch (ou tudo com --all)'",
     "'  migrate:rollback [--all]    undo the last batch (or everything with --all)'"),
    ("'  migrate:up [nome]           aplica a proxima pendente, ou a informada'",
     "'  migrate:up [name]           run the next pending migration, or the given one'"),
    ("'  migrate:down [nome]         desfaz a ultima aplicada, ou a informada'",
     "'  migrate:down [name]         undo the last applied migration, or the given one'"),
    ("'  migrate:to <nome>           aplica pendentes ate a informada, inclusive'",
     "'  migrate:to <name>           run pending migrations up to the given one'"),
    ("'  migrate:status              lista aplicadas e pendentes'",
     "'  migrate:status              list applied and pending migrations'"),
    ("'  migrate:version             mostra a versao atual'",
     "'  migrate:version             show the current version'"),
    ("'  migrate:unlock              libera lock preso por processo que morreu'",
     "'  migrate:unlock              release a lock left behind by a dead process'"),
    ("'  migrate:make <desc> [--sql] cria uma migration (Pascal, ou par .sql)'",
     "'  migrate:make <desc> [--sql] create a migration (Pascal, or a .sql pair)'"),
    ("'  seed:run [--only=nome]      roda os seeds'",
     "'  seed:run [--only=name]      run the seeds'"),
    ("'  seed:make <desc>            cria um seed'",
     "'  seed:make <desc>            create a seed'"),
    ("'Flags gerais:'", "'General flags:'"),
    ("'  --quiet                     so erros na saida'",
     "'  --quiet                     only errors on output'"),
    ("'  --help                      esta ajuda'",
     "'  --help                      this help'"),
    # comandos
    ("'nada a aplicar: ja esta na ultima versao'",
     "'nothing to run: already at the latest version'"),
    ("'%d migration(s) aplicada(s)'", "'%d migration(s) applied'"),
    ("'nada a desfazer'", "'nothing to undo'"),
    ("'%d migration(s) desfeita(s)'", "'%d migration(s) reverted'"),
    ("'erro: migrate:to exige o nome da migration alvo'",
     "'error: migrate:to requires the target migration name'"),
    ("'  estado   lote  fonte  migration'", "'  state    batch source migration'"),
    ("'  -------  ----  -----  ---------'", "'  -------  ----- ------ ---------'"),
    ("'pendente'", "'pending '"),
    ("'%d aplicada(s), %d pendente(s). Versao atual: %s'",
     "'%d applied, %d pending. Current version: %s'"),
    ("'lock liberado'", "'lock released'"),
    ("'erro: migrate:make exige uma descricao. Ex.: lznex migrate:make create_users'",
     "'error: migrate:make requires a description. Example: lznex migrate:make create_users'"),
    ("'criado: %s.up.sql'", "'created: %s.up.sql'"),
    ("'criado: %s.down.sql'", "'created: %s.down.sql'"),
    ("'migrations .sql sao lidas em runtime: nao precisa recompilar.'",
     "'.sql migrations are read at runtime: no rebuild needed.'"),
    ("'criado: %s'", "'created: %s'"),
    ("'ATENCAO: acrescente \"%s\" ao `uses` do agregador de migrations.'",
     "'WARNING: add \"%s\" to the `uses` clause of the migrations aggregator.'"),
    ("'Unit nao referenciada nao e linkada pelo FPC, logo o initialization'",
     "'A unit nobody references is not linked by FPC, so its initialization'"),
    ("'nao roda e a migration nao se registra.'",
     "'never runs and the migration never registers itself.'"),
    ("'erro: seed:make exige uma descricao'",
     "'error: seed:make requires a description'"),
    ("'%d seed(s) executado(s)'", "'%d seed(s) executed'"),
    ("'comando desconhecido: '", "'unknown command: '"),
    ("'erro de lock: '", "'lock error: '"),
    ("'erro: '", "'error: '"),
    ("'erro inesperado ('", "'unexpected error ('"),
    # stub gerado
    ("'  // ADb.Schema.CreateTable(''exemplo'')'",
     "'  // ADb.Schema.CreateTable(''example'')'"),
    ("'  //   .Str(''nome'', 120).NotNull'",
     "'  //   .Str(''name'', 120).NotNull'"),
    ("'  // ADb.Schema.DropTableIfExists(''exemplo'');'",
     "'  // ADb.Schema.DropTableIfExists(''example'');'"),
    # .lpr
    ("'erro de configuracao: '", "'configuration error: '"),
    ("'Informe por '", "'Provide it through '"),
    ("' ou pelas variaveis LZNEX_HOST, '", "' or the LZNEX_HOST, '"),
    ("'erro ('", "'error ('"),
    # seeds/sql stub
    ("'-- up: '", "'-- up: '"),
]


def main(paths):
    for p in paths:
        path = pathlib.Path(p)
        if not path.is_file():
            continue
        text = path.read_text(encoding='utf-8')
        count = 0
        for old, new in PAIRS:
            if old in text:
                count += text.count(old)
                text = text.replace(old, new)
        if count:
            path.write_text(text, encoding='utf-8')
            print(f'{path.name}: {count} strings traduzidas')


if __name__ == '__main__':
    main(sys.argv[1:])
