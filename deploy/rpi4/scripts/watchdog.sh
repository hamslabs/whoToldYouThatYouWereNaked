#!/bin/bash
# Stream health check via mediamtx HTTP API.
# Run by stream-watchdog.timer every 30s.
# Restarts camera-stream if mediamtx reports no active tracks.

set -uo pipefail

EVENT_LOG=/var/log/watchdog-events

log_restart() {
    echo "$(date -Iseconds) $1" | tee -a "$EVENT_LOG"
}

result=$(curl -sf --max-time 5 http://localhost:9997/v3/paths/list 2>/dev/null) || {
    log_restart "restarted camera-stream: mediamtx API unreachable"
    systemctl restart camera-stream
    exit 0
}

tracks=$(echo "$result" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    items = d.get('items', [])
    if items:
        print(json.dumps(items[0].get('tracks', [])))
    else:
        print('[]')
except Exception as e:
    print('[]')
" 2>/dev/null)

if [ "$tracks" = "[]" ] || [ -z "$tracks" ]; then
    log_restart "restarted camera-stream: no active tracks"
    systemctl restart camera-stream
else
    echo "Stream healthy: tracks=${tracks}"
fi
