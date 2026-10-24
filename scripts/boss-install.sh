#!/usr/bin/env bash
set -eu

DIR=${1:-.}
NOISE='rsvars\.bat|no Delphi installation|global packages on this platform'

cd "$DIR"

if [ ! -f boss.json ]; then
  echo "boss-install: boss.json nao encontrado em $PWD" >&2
  exit 1
fi

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

echo "boss-install: instalando dependencias de $PWD"

set +e
boss install >"$LOG" 2>&1
BOSS_CODE=$?
set -e

NOISE_LINES=$(grep -Eic "$NOISE" "$LOG" || true)
if [ "$NOISE_LINES" -gt 0 ]; then
  echo "boss-install: $NOISE_LINES linha(s) de ruido de Delphi ignoradas"
fi

if grep -q 'Installation completed successfully' "$LOG"; then
  echo "boss-install: OK (exit do boss: $BOSS_CODE)"
  if [ -d modules ]; then
    echo "boss-install: modules/"
    ls -1 modules | sed 's/^/  /'
  fi
  exit 0
fi

echo "boss-install: FALHOU (exit do boss: $BOSS_CODE)" >&2
echo "boss-install: saida relevante (ruido de Delphi removido):" >&2

CLEAN=$(grep -Eiv "$NOISE" "$LOG" \
  | sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\r//g' -e 's/[[:cntrl:]]//g' \
  | grep -v '^[[:space:]]*$' || true)
RELEVANT=$(printf '%s\n' "$CLEAN" \
  | grep -Ei 'failed|fatal|error|not found|denied|unable|unauthor' || true)

if [ -n "$RELEVANT" ]; then
  printf '%s\n' "$RELEVANT" | tail -15 | sed 's/^/  /' >&2
else
  printf '%s\n' "$CLEAN" | tail -25 | sed 's/^/  /' >&2
fi
exit 1
