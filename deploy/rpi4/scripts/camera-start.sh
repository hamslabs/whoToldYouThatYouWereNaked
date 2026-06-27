#!/bin/bash
# ExecStartPre for camera-stream.service
# Polls Rock Pi4 readiness endpoint before starting mediamtx.
# Fail-open: if Rock Pi4 never responds, mediamtx starts anyway.

set -euo pipefail

PAIR_ID=$(cat /etc/pair-id)
ROCK_IP="192.168.10.2${PAIR_ID}"
READY_URL="http://${ROCK_IP}:7777/ready"
TIMEOUT=60
INTERVAL=2
elapsed=0

echo "Waiting for Rock Pi4 at ${READY_URL}..."

while [ $elapsed -lt $TIMEOUT ]; do
    if curl -sf --max-time 2 "$READY_URL" > /dev/null 2>&1; then
        echo "Rock Pi4 ready after ${elapsed}s"
        exit 0
    fi
    sleep $INTERVAL
    elapsed=$((elapsed + INTERVAL))
done

echo "Rock Pi4 not ready after ${TIMEOUT}s — starting mediamtx anyway (fail-open)"
exit 0
