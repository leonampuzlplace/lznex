#!/usr/bin/env bash
# Compila a suite no container e roda com heaptrc.
# Uso: dev-check.sh [<lpr>]   LZNEX_IT/LZNEX_CLIENT vem do ambiente.
set -eu

LPR=${1:-tests/LzNexTests.lpr}
OUT=/work/$(basename "${LPR%.lpr}").bin

cp -r /host/src /host/tests /host/tools /work/ 2>/dev/null || true
mkdir -p /work/out
cd /work

Z=/src/modules/zeoslib/src
fpc -MDelphi -gh -dUseCThreads \
  -Fu/work/src -Fu/work/tests \
  -Fu"$Z/core" -Fu"$Z/parsesql" -Fu"$Z/dbc" -Fu"$Z/plain" \
  -Fu"$Z/component" -Fu"$Z/dbc/generic" \
  -FU/work/out -o"$OUT" "$LPR" > /tmp/build.log 2>&1 || {
    grep -E 'Error|Fatal' /tmp/build.log | head -20
    exit 1
  }

set +e
"$OUT" > /tmp/run.log 2>&1
CODE=$?
set -e

echo "exit=$CODE  (LZNEX_IT='${LZNEX_IT:-}' LZNEX_CLIENT='${LZNEX_CLIENT:-}')"
grep -E 'Number of (run|ignored|failed|errored)' /tmp/run.log || true
echo '--- falhas/erros ---'
grep -vE 'not set: .* skipped|EIgnoredTest' /tmp/run.log \
  | grep -E -B2 -A3 'Exception class|Assertion' | head -80 || true
echo '--- heaptrc ---'
grep -E 'unfreed|True heap|Should be' /tmp/run.log | head -6 || true
