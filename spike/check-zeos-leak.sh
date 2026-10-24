#!/usr/bin/env bash
# check-zeos-leak.sh — recompila o spike com -gh e mede se o Zeos deixa bloco
# nao liberado no encerramento (define se o gate pode ser "zero leak absoluto").
set -u

echo "=== rebuild Debug (com -gh em CustomOptions) ==="
lazbuild -B --build-mode=Debug ZeosSpike.lpi 2>&1 | grep -Ei 'fatal|^Error|lines compiled' | tail -5
echo

echo "=== heaptrc linkado? (conta de simbolos) ==="
nm ./bin/ZeosSpike-debug 2>/dev/null | grep -c 'HEAPTRC' || echo 0
echo

echo "=== rodando ==="
./bin/ZeosSpike-debug > /tmp/z.out 2> /tmp/z.err
code=$?
echo "exit=$code  stdout=$(wc -c < /tmp/z.out)B  stderr=$(wc -c < /tmp/z.err)B"
echo
echo "=== relatorio heaptrc ==="
if grep -q 'unfreed' /tmp/z.err; then
  grep -E 'memory blocks|unfreed|True heap|True free|Should be' /tmp/z.err | sed 's/^/  /'
  echo
  echo "=== primeiras 25 linhas do call trace (de onde vem o bloco) ==="
  sed -n '/Call trace/,$p' /tmp/z.err | head -25 | sed 's/^/  /'
else
  echo "  NENHUM bloco nao liberado -- Zeos nao vaza no encerramento"
fi
echo
echo "=== com HEAPTRC=haltonnotreleased ==="
HEAPTRC=haltonnotreleased ./bin/ZeosSpike-debug > /dev/null 2>/dev/null
echo "exit=$?  (0 = sem leak; 203 = halt por leak)"
