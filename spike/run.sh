#!/usr/bin/env bash
set -u

cd "$(dirname "$0")/.."

docker compose exec -T spike bash -lc '
  cd /work
  "$@"
  code=$?
  echo "::EXIT=$code"
  exit $code
' _ "$@"
