#!/usr/bin/env bash
# Bônus: gera carga em GET /api/messages para provar o HPA escalando.
# Prioriza `hey` se disponível; senão cai para um loop de curl em paralelo.
#
# Uso:
#   helm upgrade mural infra/helm/mural -n mural --reuse-values --set autoscaling.enabled=true
#   kubectl -n mural get hpa -w &
#   ./infra/loadtest/loadtest.sh
set -euo pipefail

URL="${1:-http://mural.localtest.me/api/messages}"
DURATION="${2:-120s}"
CONCURRENCY="${3:-50}"

if command -v hey >/dev/null 2>&1; then
  echo "Usando hey contra $URL por $DURATION com concorrência $CONCURRENCY"
  hey -z "$DURATION" -c "$CONCURRENCY" "$URL"
else
  echo "hey não encontrado; usando loop de curl em paralelo (Ctrl+C para parar)"
  echo "Acompanhe com: kubectl -n mural get hpa -w"
  end=$((SECONDS + ${DURATION%s}))
  while [ $SECONDS -lt "$end" ]; do
    for _ in $(seq 1 "$CONCURRENCY"); do
      curl -s -o /dev/null "$URL" &
    done
    wait
  done
fi
