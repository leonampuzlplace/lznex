#!/usr/bin/env bash
set -u

TAG=${1:?uso: check.sh <tag> <arquivo> [flags]}
FILE=${2:?uso: check.sh <tag> <arquivo> [flags]}
shift 2

ROOT=/work
OUT="$ROOT/.build/$TAG"
LOG="$OUT/compile.log"
mkdir -p "$OUT"

ZEOS=/opt/zeos/src

fpc -B -Mdelphi -Sh \
    -FU"$OUT" \
    -FE"$OUT" \
    -Fi"$ZEOS" \
    -Fu"$ROOT/src" \
    -Fu"$ROOT/tests" \
    -Fu"$ROOT/tools" \
    -Fu"$ROOT/database" \
    -Fu"$ROOT/database/migrations" \
    -Fu"$ZEOS/core" -Fu"$ZEOS/parsesql" -Fu"$ZEOS/plain" -Fu"$ZEOS/dbc" \
    -dUseCThreads \
    "$@" \
    "$FILE" > "$LOG" 2>&1
status=$?

grep -E 'Error:|Fatal:' "$LOG" | head -20
grep -Ev '^Compiling |^Target OS|^Free Pascal|^Copyright|^$|Error:|Fatal:' "$LOG" \
  | grep -Ev 'Note: (Local variable|Private|Call to)' \
  | grep -Ev 'Hint: ' \
  | tail -15

if [ $status -ne 0 ]; then
  echo "### FALHOU (exit $status) -- log completo em $LOG"
fi
exit $status
