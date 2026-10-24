#!/usr/bin/env bash
# Roda os binarios de teste com o gate de vazamento ligado.
#
# Com -gh linkado e HEAPTRC=haltonnotreleased, vazamento derruba o processo com
# exit 203 e sem vazamento o exit e 0 e nada e impresso. Logo "exit != 0" cobre
# tanto assert quebrado quanto memoria nao liberada.
#
# O gate SO funciona em binario compilado com -gh, ou seja o build mode Debug.
# Binario sem heaptrc e rodado e reportado, mas avisado como gate inerte.
#
#   uso: run-tests.sh [binario...]        (sem argumento: glob em $TEST_BIN_DIR)
#   env: TEST_BIN_DIR (default bin), HEAPTRC
set -eu

BIN_DIR=${TEST_BIN_DIR:-bin}
export HEAPTRC=${HEAPTRC:-haltonnotreleased}

collect() {
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
    return 0
  fi
  local f
  for f in "$BIN_DIR"/Probe* "$BIN_DIR"/Test*; do
    if [ -f "$f" ] && [ -x "$f" ]; then
      printf '%s\n' "$f"
    fi
  done
}

BINS=()
while IFS= read -r line; do
  BINS+=("$line")
done < <(collect "$@")

if [ "${#BINS[@]}" -eq 0 ]; then
  echo "run-tests: nenhum binario de teste em '$BIN_DIR' (Probe*/Test*)" >&2
  echo "run-tests: compile os tests/*.lpi antes, ou passe os binarios como argumento" >&2
  exit 1
fi

echo "run-tests: HEAPTRC=$HEAPTRC"
echo "run-tests: ${#BINS[@]} binario(s)"
echo

PASS=0
FAIL=0
LEAK=0
FAILED=()

OUT=$(mktemp)
ERR=$(mktemp)
trap 'rm -f "$OUT" "$ERR"' EXIT

for bin in "${BINS[@]}"; do
  name=$(basename "$bin")

  if ! [ -x "$bin" ]; then
    echo "  SKIP  $name (nao executavel)"
    continue
  fi

  gate='gh'
  if ! grep -aq 'Heap dump by heaptrc unit' "$bin"; then
    gate='SEM -gh'
  fi

  set +e
  "$bin" >"$OUT" 2>"$ERR"
  code=$?
  set -e

  case "$code" in
    0)
      printf '  PASS  %-28s [%s]\n' "$name" "$gate"
      PASS=$((PASS + 1))
      ;;
    203)
      printf '  LEAK  %-28s exit=203\n' "$name"
      LEAK=$((LEAK + 1))
      FAILED+=("$name (vazamento)")
      grep -hE 'memory blocks|unfreed|True heap|Should be' "$ERR" "$OUT" 2>/dev/null \
        | head -8 | sed 's/^/          /' || true
      ;;
    *)
      printf '  FAIL  %-28s exit=%s\n' "$name" "$code"
      FAIL=$((FAIL + 1))
      FAILED+=("$name (exit $code)")
      tail -15 "$ERR" | sed 's/^/          /'
      tail -15 "$OUT" | sed 's/^/          /'
      ;;
  esac

  if [ "$gate" = 'SEM -gh' ]; then
    echo "          aviso: sem heaptrc, o gate de vazamento nao vale neste binario"
  fi
done

echo
echo "run-tests: pass=$PASS fail=$FAIL leak=$LEAK"

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "run-tests: FALHOU"
  printf '  - %s\n' "${FAILED[@]}"
  exit 1
fi

echo "run-tests: OK"
