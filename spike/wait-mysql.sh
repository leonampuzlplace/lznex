#!/usr/bin/env bash
# wait-mysql.sh — espera o container do mysql ficar healthy.
set -u
for i in $(seq 1 40); do
  s=$(docker inspect -f '{{.State.Health.Status}}' lznex-mysql 2>/dev/null || echo "ausente")
  echo "mysql: $s"
  if [ "$s" = "healthy" ]; then
    exit 0
  fi
  sleep 3
done
echo "TIMEOUT esperando o mysql"
exit 1
