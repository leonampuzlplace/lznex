#!/usr/bin/env bash
# Verificacao completa: compila tudo, roda tudo, e mede vazamento em cada
# binario. Exit codes lidos sem pipe no meio (pipe troca $? pelo status do
# ultimo comando do pipe).
set -u
cd /work

FAILED=0

say() { printf '\n== %s\n' "$1"; }

run_probe() {
  local name="$1" tag="v$(echo "$1" | tr 'A-Z' 'a-z')" env_it="${2:-}"
  bash spike/check.sh "$tag" "tests/$name.lpr" > "/tmp/$name.b" 2>&1
  if [ $? -ne 0 ]; then
    printf '  %-18s BUILD FALHOU\n' "$name"
    grep -E 'Error:|Fatal:' "/tmp/$name.b" | head -2 | sed 's/^/     /'
    FAILED=1
    return
  fi
  if [ -n "$env_it" ]; then
    env $env_it "./.build/$tag/$name" > "/tmp/$name.o" 2>&1
  else
    "./.build/$tag/$name" > "/tmp/$name.o" 2>&1
  fi
  local code=$?
  local asserts
  asserts=$(grep -oE 'asercoes: [0-9]+|asser[a-z]*oes ok: [0-9]+' "/tmp/$name.o" | grep -oE '[0-9]+' | tail -1)
  printf '  %-18s exit=%-3s asercoes=%-5s %s\n' "$name" "$code" "${asserts:-?}" \
    "$(grep -oE '=== .*(OK|FALHA).* ===' "/tmp/$name.o" | tail -1)"
  [ "$code" -ne 0 ] && FAILED=1
  return 0
}

check_leak() {
  local name="$1" src="$2" env_it="${3:-}"
  local tag="l$(echo "$1" | tr 'A-Z' 'a-z')"
  bash spike/check.sh "$tag" "$src" -gh > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    printf '  %-18s BUILD -gh FALHOU\n' "$name"
    FAILED=1
    return
  fi
  env $env_it HEAPTRC=haltonnotreleased "./.build/$tag/$name" > /dev/null 2> "/tmp/$name.leak"
  local code=$?
  # Criterio correto: exit != 0 (o heaptrc derruba com haltonnotreleased) ou
  # contagem de blocos nao liberados > 0. Presenca de stderr NAO serve:
  # em programa multi-thread o heaptrc imprime o resumo mesmo sem vazamento,
  # porque o contador de "True heap size" estoura.
  local unfreed
  unfreed=$(grep -oE '^[0-9]+ unfreed memory blocks' "/tmp/$name.leak" \
            | grep -oE '^[0-9]+' | head -1)
  unfreed=${unfreed:-0}
  printf '  %-18s exit=%-3s blocos_vazados=%s\n' "$name" "$code" "$unfreed"
  if [ "$code" -ne 0 ] || [ "$unfreed" -ne 0 ]; then
    FAILED=1
    sed 's/^/     /' "/tmp/$name.leak" | head -6
  fi
  return 0
}

say "SONDAS (sem banco e com banco)"
run_probe ProbeValue
run_probe ProbeAst
run_probe ProbeQuery
run_probe ProbeCompiler
run_probe ProbeSchema
run_probe ProbeEndToEnd
run_probe ProbeMigration
run_probe ProbeZeos

say "SUITE FPCUNIT (unitarios)"
bash spike/check.sh vfpcunit tests/LzNexTests.lpr > /tmp/fpcunit.b 2>&1
if [ $? -ne 0 ]; then
  echo "  BUILD FALHOU"; grep -E 'Error:|Fatal:' /tmp/fpcunit.b | head -3; FAILED=1
else
  ./.build/vfpcunit/LzNexTests > /tmp/fpcunit.o 2>&1
  echo "  exit=$?"
  grep -E 'Number of (run tests|errors|failures)' /tmp/fpcunit.o | sed 's/^/  /'
fi

say "SUITE FPCUNIT (com MySQL real: integracao + concorrencia)"
LZNEX_IT=1 ./.build/vfpcunit/LzNexTests > /tmp/fpcunit_it.o 2>&1
echo "  exit=$?"
grep -E 'Number of (run tests|errors|failures)' /tmp/fpcunit_it.o | sed 's/^/  /'
grep -E '^  (integration|concurrency) ' /tmp/fpcunit_it.o | sed 's/^/  /'

say "GATE DE VAZAMENTO (-gh + HEAPTRC=haltonnotreleased)"
check_leak ProbeQuery    tests/ProbeQuery.lpr
check_leak ProbeCompiler tests/ProbeCompiler.lpr
check_leak ProbeSchema   tests/ProbeSchema.lpr
check_leak ProbeZeos     tests/ProbeZeos.lpr
check_leak LzNexTests    tests/LzNexTests.lpr "LZNEX_IT=1"

say "RESULTADO"
if [ $FAILED -eq 0 ]; then
  echo "  TUDO VERDE"
else
  echo "  HOUVE FALHA"
fi
exit $FAILED
