#!/usr/bin/env bash
# Roda a suite FPCUnit dentro do container e imprime o exit code como TEXTO.
# `docker compose exec` nao propaga exit code neste ambiente, entao ler $? de
# fora da resultado invalido -- o codigo tem que ser lido aqui dentro.
set -u
cd /home/ljlim/code/study/lznex

echo "############ unitarios (sem banco) ############"
docker compose exec -T spike bash -c '
  /work/.build/fpcunit/LzNexTests
  echo "::EXIT_UNIT=$?"
'

echo
echo "############ unitarios + integracao (MySQL real) ############"
docker compose exec -T -e LZNEX_IT=1 spike bash -c '
  /work/.build/fpcunit/LzNexTests
  echo "::EXIT_IT=$?"
'

echo
echo "############ gate de vazamento (-gh + haltonnotreleased) ############"
docker compose exec -T spike bash -c '
  bash /work/spike/check.sh fpcunitgh /work/tests/LzNexTests.lpr -gh > /dev/null 2>&1
  echo "build_exit=$?"
'
docker compose exec -T -e LZNEX_IT=1 -e HEAPTRC=haltonnotreleased spike bash -c '
  /work/.build/fpcunitgh/LzNexTests > /tmp/leak.out 2> /tmp/leak.err
  echo "::EXIT_LEAK=$?"
  echo "stderr_bytes=$(wc -c < /tmp/leak.err)"
  grep -E "unfreed|memory blocks" /tmp/leak.err | head -4
'
