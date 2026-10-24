#!/usr/bin/env bash
# Roda o ciclo de migrations pelo CLI e confere o estado REAL do banco
# consultando pelo container do mysql (nao pelo spike, cujo cliente mariadb
# pode esbarrar no caching_sha2_password).
set -u
cd /home/ljlim/code/study/lznex

cli() {
  docker compose exec -T -w /work -e LZNEX_CONFIG=database/lznex.json \
    spike /work/.build/cli/LzNexCli "$@"
}

q() {
  docker compose exec -T mysql mysql -uroot -psecret -N -B -e "$1" 2>&1 \
    | grep -v '^mysql: \[Warning\]'
}

echo "### estado inicial: zerando a base"
q "drop database if exists lznex; create database lznex character set utf8mb4;" >/dev/null
echo

echo "### lznex migrate:latest"
cli migrate:latest
echo

echo "### tabelas criadas (esperado: migrations, migrations_lock, posts, users)"
q "show tables from lznex;" | sed 's/^/    /'
echo

echo "### colunas de users (a migration .sql deve ter acrescentado phone)"
q "select column_name from information_schema.columns where table_schema='lznex' and table_name='users' order by ordinal_position;" | tr '\n' ' ' | sed 's/^/    /'
echo; echo

echo "### DDL real da tabela users (prova o schema builder)"
q "show create table lznex.users\G" | sed 's/^/    /'
echo

echo "### FK de posts (prova References/InTable/OnDelete)"
q "select constraint_name, referenced_table_name, delete_rule from information_schema.referential_constraints where constraint_schema='lznex';" | sed 's/^/    /'
echo

echo "### tabela de controle"
q "select name, batch from lznex.migrations order by id;" | sed 's/^/    /'
echo

echo "### lznex migrate:rollback"
cli migrate:rollback
echo
echo "### tabelas apos rollback (esperado: so migrations e migrations_lock)"
q "show tables from lznex;" | sed 's/^/    /'
