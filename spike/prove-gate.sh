#!/usr/bin/env bash
# prove-gate.sh — prova que o gate de leak funciona num binario que usa Zeos:
# LEAK=1 tem que acusar e derrubar o exit code; sem LEAK tem que passar limpo.
set -u

echo "=== rebuild Debug ==="
lazbuild -B --build-mode=Debug ZeosSpike.lpi 2>&1 | grep -Ei 'fatal|^Error|lines compiled' | tail -3
echo

echo "=== A) LEAK=1 -- esperado: relatorio + exit != 0 ==="
LEAK=1 HEAPTRC=haltonnotreleased ./bin/ZeosSpike-debug > /tmp/a.out 2> /tmp/a.err
echo "exit=$?"
grep -E 'memory blocks|unfreed' /tmp/a.err | sed 's/^/  /' || echo "  (sem relatorio -- -gh NAO esta ativo!)"
echo

echo "=== B) sem LEAK -- esperado: nada + exit 0 ==="
HEAPTRC=haltonnotreleased ./bin/ZeosSpike-debug > /tmp/b.out 2> /tmp/b.err
echo "exit=$?"
if grep -q 'unfreed' /tmp/b.err; then
  grep -E 'memory blocks|unfreed' /tmp/b.err | sed 's/^/  /'
else
  echo "  limpo: nenhum bloco nao liberado"
fi
echo

echo "=== C) build Release (sem -gh) continua funcionando ==="
lazbuild -B --build-mode=Release ZeosSpike.lpi 2>&1 | grep -Ei 'fatal|^Error|lines compiled' | tail -3
./bin/ZeosSpike-release > /dev/null 2>&1
echo "exit=$?"
ls -la bin/
