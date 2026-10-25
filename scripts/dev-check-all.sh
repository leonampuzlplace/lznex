#!/usr/bin/env bash
# Roda dev-check.sh contra os cinco bancos. Os servidores vem do compose
# (docker compose up -d mysql postgres firebird3 firebird5).
set -eu

cd "$(dirname "$0")/.."

run() {
  local client=$1 host=${2:-}
  echo "########## $client ${host:+@ $host}"
  timeout 900 docker run --rm --network lznex_default \
    -v "$PWD":/host -w /work \
    -e HEAPTRC=haltonnotreleased -e LZNEX_IT=1 \
    -e LZNEX_CLIENT="$client" ${host:+-e DB_HOST="$host"} \
    lznex-builder bash /host/scripts/dev-check.sh 2>&1 | tail -20
}

run sqlite
run mysql mysql
run postgresql postgres
run firebird firebird5
run firebird firebird3
