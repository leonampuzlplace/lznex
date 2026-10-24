#!/usr/bin/env bash
set -u

run() {
  local label="$1"; shift
  local env_prefix="$1"; shift
  local bin="$1"; shift
  echo "=== $label"
  if [ -n "$env_prefix" ]; then
    env $env_prefix "$bin" > /tmp/p.out 2> /tmp/p.err
  else
    "$bin" > /tmp/p.out 2> /tmp/p.err
  fi
  local code=$?
  echo "  exit=$code  stdout=$(wc -c < /tmp/p.out)B  stderr=$(wc -c < /tmp/p.err)B"
  if grep -q 'unfreed' /tmp/p.err 2>/dev/null; then
    echo "  relatorio (stderr):"
    grep -E 'memory blocks|unfreed|True heap|Should be' /tmp/p.err | sed 's/^/    /'
  elif grep -q 'unfreed' /tmp/p.out 2>/dev/null; then
    echo "  relatorio (stdout):"
    grep -E 'memory blocks|unfreed|True heap|Should be' /tmp/p.out | sed 's/^/    /'
  else
    echo "  (nenhum relatorio de heaptrc encontrado)"
  fi
  echo
}

run "HeapProbe sem leak"                  ""                           ./bin/HeapProbe
run "HeapProbe com leak"                  "LEAK=1"                     ./bin/HeapProbe
run "HeapProbe com leak + halt"           "LEAK=1 HEAPTRC=haltonnotreleased" ./bin/HeapProbe
run "HeapProbe sem leak + skipifnoleaks"  "HEAPTRC=skipifnoleaks"      ./bin/HeapProbe
run "ZeosSpike-debug (lpi UseHeaptrc)"    ""                           ./bin/ZeosSpike-debug
run "ZeosSpike-debug + halt"              "HEAPTRC=haltonnotreleased"  ./bin/ZeosSpike-debug
