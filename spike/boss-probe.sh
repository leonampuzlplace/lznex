#!/usr/bin/env bash
# boss-probe.sh — mede empiricamente o que o Boss faz ao instalar o Zeos:
#   fase 1: Zeos SEM boss.json  -> quantos paths entram no OtherUnitFiles?
#   fase 2: Zeos COM boss.json (simula o fork) -> cai para os 4 do mainsrc?
set -u
cd /work/boss-test

echo "############ FASE 1: Zeos sem boss.json ############"
rm -rf modules boss-lock.json
boss install 2>&1 | tail -20
echo
echo "--- pasta criada em modules/ ---"
ls -1 modules/ 2>/dev/null
echo
echo "--- OtherUnitFiles injetado no .lpi ---"
grep -o 'OtherUnitFiles Value="[^"]*"' Probe.lpi | sed 's/OtherUnitFiles Value="//; s/"$//' | tr ';' '\n' | sed 's/^/  /'
echo
echo "--- CONTAGEM de paths ---"
grep -o 'OtherUnitFiles Value="[^"]*"' Probe.lpi | sed 's/OtherUnitFiles Value="//; s/"$//' | tr ';' '\n' | grep -c . || true
echo
echo "--- versao resolvida (boss-lock.json) ---"
cat boss-lock.json 2>/dev/null
echo
echo

echo "############ FASE 2: injetando boss.json no modulo (simula o fork) ############"
MOD=$(ls -1 modules/ | grep -i zeos | head -1)
if [ -z "$MOD" ]; then
  echo "ERRO: nao achei o modulo do zeos em modules/"
  exit 1
fi
cat > "modules/$MOD/boss.json" <<'JSON'
{
  "name": "zeoslib",
  "description": "ZeosLib 8.0 com boss.json para unit path limpo",
  "version": "8.0.0",
  "homepage": "https://zeoslib.sourceforge.io",
  "mainsrc": "src/core;src/parsesql;src/plain;src/dbc",
  "projects": [],
  "dependencies": {}
}
JSON
echo "boss.json escrito em modules/$MOD/"
echo

# Zera o OtherUnitFiles para ver o que o Boss escreve do zero.
sed -i 's#<OtherUnitFiles Value="[^"]*"/>##' Probe.lpi
boss install 2>&1 | tail -12
echo
echo "--- OtherUnitFiles AGORA ---"
grep -o 'OtherUnitFiles Value="[^"]*"' Probe.lpi | sed 's/OtherUnitFiles Value="//; s/"$//' | tr ';' '\n' | sed 's/^/  /'
echo
echo "--- CONTAGEM de paths AGORA ---"
grep -o 'OtherUnitFiles Value="[^"]*"' Probe.lpi | sed 's/OtherUnitFiles Value="//; s/"$//' | tr ';' '\n' | grep -c . || true
