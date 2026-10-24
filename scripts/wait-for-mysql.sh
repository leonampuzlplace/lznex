#!/usr/bin/env bash
# Espera o MySQL aceitar conexao antes da suite de integracao.
#
#   uso: wait-for-mysql.sh [host] [porta] [timeout-em-segundos]
#   env: DB_HOST, DB_PORT, DB_USER, DB_PASS, DB_WAIT_TIMEOUT
set -eu

HOST=${1:-${DB_HOST:-mysql}}
PORT=${2:-${DB_PORT:-3306}}
TIMEOUT=${3:-${DB_WAIT_TIMEOUT:-120}}

# Aceitar o TCP nao basta: o MySQL abre a porta antes de terminar o bootstrap e
# derruba a sessao em seguida. O greeting do protocolo so sai quando ele esta
# pronto de verdade, por isso o fallback exige ler pelo menos um byte.
ready() {
  if command -v mysqladmin >/dev/null 2>&1; then
    mysqladmin ping \
      -h "$HOST" -P "$PORT" --protocol=TCP \
      ${DB_USER:+-u"$DB_USER"} ${DB_PASS:+-p"$DB_PASS"} \
      --silent >/dev/null 2>&1
    return
  fi

  # Subshell: assim o "Connection refused" do bash nao suja a saida, e um
  # `exec` sem comando que falha nao estraga os fds do script.
  (
    exec 3<>"/dev/tcp/$HOST/$PORT" || exit 1
    byte=''
    IFS= read -r -n 1 -t 5 byte <&3 || exit 1
    [ -n "$byte" ] || exit 1
  ) 2>/dev/null
}

DEADLINE=$(( $(date +%s) + TIMEOUT ))
ATTEMPT=0

while :; do
  ATTEMPT=$((ATTEMPT + 1))
  if ready; then
    echo "wait-for-mysql: $HOST:$PORT pronto (tentativa $ATTEMPT)"
    exit 0
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "wait-for-mysql: TIMEOUT de ${TIMEOUT}s esperando $HOST:$PORT" >&2
    exit 1
  fi
  printf 'wait-for-mysql: %s:%s indisponivel, tentativa %d...\n' "$HOST" "$PORT" "$ATTEMPT"
  sleep 2
done
