#!/usr/bin/env bash
set -u
cd /work

for name in ProbeValue ProbeAst ProbeQuery ProbeCompiler ProbeSchema ProbeMigration ProbeEndToEnd; do
  tag="x$(echo "$name" | tr 'A-Z' 'a-z')"
  bash spike/check.sh "$tag" "tests/$name.lpr" > "/tmp/$name.build" 2>&1
  build=$?
  if [ $build -ne 0 ]; then
    printf '%-16s BUILD FALHOU\n' "$name"
    grep -E 'Error:|Fatal:' "/tmp/$name.build" | head -2 | sed 's/^/                 /'
    continue
  fi
  "./.build/$tag/$name" > "/tmp/$name.out" 2>&1
  code=$?
  fails=$(grep -c 'FALHA' "/tmp/$name.out" || true)
  verdict=$(grep -oE '=== .* (OK|COM FALHA) ===' "/tmp/$name.out" | tail -1)
  printf '%-16s exit=%-3s falhas_no_texto=%-3s %s\n' "$name" "$code" "$fails" "$verdict"
done
