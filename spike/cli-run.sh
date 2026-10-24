#!/usr/bin/env bash
# Roda o ciclo completo de migrations contra o MySQL e confere o resultado
# direto no banco, nao so pela saida do CLI.
set -u
cd /work
export LZNEX_CONFIG=database/lznex.json
CLI=/work/.build/cli/LzNexCli

run() {
  echo "### lznex $*"
  "$CLI" "$@"
  echo "    exit=$?"
  echo
}

sqlq() {
  mysql -h mysql -uroot -psecret -N -B -e "$1" 2>/dev/null
}

run migrate:status
run migrate:latest
run migrate:status

echo "### tabelas no banco"
sqlq "show tables from lznex;" | sed 's/^/    /'
echo

echo "### colunas de users (a migration .sql adiciona phone)"
sqlq "select column_name from information_schema.columns where table_schema='lznex' and table_name='users' order by ordinal_position;" | tr '\n' ' ' | sed 's/^/    /'
echo
echo

echo "### conteudo da tabela de controle"
sqlq "select name, batch from lznex.migrations order by id;" | sed 's/^/    /'
echo

run migrate:rollback
echo "### tabelas apos rollback do ultimo batch"
sqlq "show tables from lznex;" | sed 's/^/    /'
echo

run migrate:status
