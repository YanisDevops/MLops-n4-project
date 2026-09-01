#!/usr/bin/env bash
set -euo pipefail
command -v kubectl >/dev/null 2>&1 || { echo "Erreur: kubectl est requis." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Erreur: curl est requis." >&2; exit 1; }
command -v python >/dev/null 2>&1 || { echo "Erreur: python est requis." >&2; exit 1; }

SERVICE="${SERVICE:-taxi-duration-predictor}"
LOCAL_PORT="${LOCAL_PORT:-8080}"
REQUEST_COUNT="${REQUEST_COUNT:-10}"
REQUEST_DELAY_SECONDS="${REQUEST_DELAY_SECONDS:-0.2}"

[[ "$REQUEST_COUNT" =~ ^[1-9][0-9]*$ ]] || {
  echo "Erreur: REQUEST_COUNT doit être un entier strictement positif." >&2
  exit 1
}
kubectl -n ml-serving get inferenceservice taxi-duration >/dev/null
kubectl -n ml-serving port-forward "svc/$SERVICE" "$LOCAL_PORT:80" >/tmp/mlops-n4-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true' EXIT

READY=false
for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:$LOCAL_PORT/v1/models/taxi-duration" >/dev/null 2>&1; then
    READY=true
    break
  fi
  if ! kill -0 "$PF_PID" 2>/dev/null; then
    echo "Erreur: le port-forward s'est arrêté prématurément." >&2
    cat /tmp/mlops-n4-port-forward.log >&2
    exit 1
  fi
  sleep 1
done

if [[ "$READY" != true ]]; then
  echo "Erreur: le predictor n'est pas accessible après 30 secondes." >&2
  cat /tmp/mlops-n4-port-forward.log >&2
  exit 1
fi

SUCCESS_COUNT=0
FAILURE_COUNT=0

echo "Lancement de $REQUEST_COUNT prédictions..."
for ((request_number = 1; request_number <= REQUEST_COUNT; request_number++)); do
  PICKUP_HOUR=$((request_number % 24))
  PICKUP_DOW=$((request_number % 7))
  TRIP_DISTANCE="$((request_number % 9 + 1)).$((request_number % 10))"
  PAYLOAD="$(printf \
    '{"trip_distance":%s,"pickup_hour":%d,"pickup_dow":%d,"PULocationID":%d,"DOLocationID":%d}' \
    "$TRIP_DISTANCE" "$PICKUP_HOUR" "$PICKUP_DOW" \
    "$((100 + request_number))" "$((200 + request_number))")"

  if RESPONSE="$(curl -fsS -X POST \
    "http://127.0.0.1:$LOCAL_PORT/v1/models/taxi-duration:predict" \
    -H 'Content-Type: application/json' \
    -d "$PAYLOAD")"; then
    if printf '%s' "$RESPONSE" | python -c '
import json
import sys

body = json.load(sys.stdin)
assert isinstance(body.get("predicted_duration"), (int, float))
assert body["predicted_duration"] >= 0
assert isinstance(body.get("latency_ms"), (int, float))
assert body.get("model_alias") or body.get("model_version")
'; then
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      printf '[%d/%d] OK %s\n' "$request_number" "$REQUEST_COUNT" "$RESPONSE"
    else
      FAILURE_COUNT=$((FAILURE_COUNT + 1))
      printf '[%d/%d] RÉPONSE INVALIDE %s\n' "$request_number" "$REQUEST_COUNT" "$RESPONSE" >&2
    fi
  else
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    printf '[%d/%d] ÉCHEC HTTP\n' "$request_number" "$REQUEST_COUNT" >&2
  fi

  if (( request_number < REQUEST_COUNT )); then
    sleep "$REQUEST_DELAY_SECONDS"
  fi
done

echo "Résultat : $SUCCESS_COUNT succès, $FAILURE_COUNT échec(s)."
if (( FAILURE_COUNT > 0 )); then
  exit 1
fi
