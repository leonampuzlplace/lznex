#!/usr/bin/env bash
# Compila e roda as sondas tests/Probe*.lpr sob heaptrc, uma por linha.
set -eu

# database/ entra porque ProbeMigration le o lznex.json e as migrations de exemplo.
cp -r /host/src /host/tests /host/database /work/ 2>/dev/null || true
cd /work

Z=/src/modules/zeoslib/src
PASS=0
FAIL=0

for lpr in tests/Probe*.lpr; do
  name=$(basename "${lpr%.lpr}")
  mkdir -p "/work/out-$name"
  if ! fpc -MDelphi -gh -dUseCThreads \
      -Fu/work/src -Fu/work/tests \
      -Fu"$Z/core" -Fu"$Z/parsesql" -Fu"$Z/dbc" -Fu"$Z/plain" \
      -Fu"$Z/component" -Fu"$Z/dbc/generic" \
      -FU"/work/out-$name" -o"/work/$name.bin" "$lpr" > "/tmp/$name.build" 2>&1; then
    printf '  BUILD-FAIL  %-18s\n' "$name"
    grep -E 'Error|Fatal' "/tmp/$name.build" | head -5 | sed 's/^/              /'
    FAIL=$((FAIL + 1))
    continue
  fi

  set +e
  "/work/$name.bin" > "/tmp/$name.run" 2>&1
  code=$?
  set -e

  if [ "$code" -eq 0 ]; then
    printf '  PASS  %-18s %s\n' "$name" "$(tail -1 "/tmp/$name.run")"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %-18s exit=%s\n' "$name" "$code"
    tail -8 "/tmp/$name.run" | sed 's/^/          /'
    FAIL=$((FAIL + 1))
  fi
done

echo "sondas: pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
