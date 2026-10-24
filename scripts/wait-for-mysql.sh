#!/usr/bin/env bash
set -eu

HOST=${1:-${DB_HOST:-mysql}}
PORT=${2:-${DB_PORT:-3306}}
TIMEOUT=${3:-${DB_WAIT_TIMEOUT:-120}}

ready() {
  if command -v mysqladmin >/dev/null 2>&1; then
    mysqladmin ping \
      -h "$HOST" -P "$PORT" --protocol=TCP \
      ${DB_USER:+-u"$DB_USER"} ${DB_PASS:+-p"$DB_PASS"} \
      --silent >/dev/null 2>&1
    return
  fi

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
