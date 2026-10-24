#!/usr/bin/env bash
# Roda um comando DENTRO do container e imprime o exit code como texto.
#
# Motivo: `docker compose exec` (e `docker exec`) nao propagam o exit code
# neste ambiente -- `bash -c "exit 7"` volta 0 la fora. Logo, verificar
# sucesso pelo $? de fora e invalido; o codigo tem que ser lido aqui dentro.
#
#   uso: bash spike/run.sh <comando...>      (rodado no host, de dentro do repo)
set -u

cd "$(dirname "$0")/.."

docker compose exec -T spike bash -lc '
  cd /work
  "$@"
  code=$?
  echo "::EXIT=$code"
  exit $code
' _ "$@"

# Reimprime um resumo: quem le a saida deve olhar a linha ::EXIT=
