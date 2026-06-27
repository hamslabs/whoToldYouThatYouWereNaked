#!/bin/bash
# MPV stream health check via IPC socket.
# Run by display-watchdog.timer every 30s.
# Detects frozen video by comparing time-pos across successive runs.

set -uo pipefail

STATE_FILE=/run/mpv-watchdog-pos

get_pos() {
    echo '{"command":["get_property","time-pos"]}' \
        | socat -t2 - UNIX-CONNECT:/tmp/mpvsocket 2>/dev/null \
        | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if d.get('error') == 'success' and d.get('data') is not None:
        print(d['data'])
except Exception:
    pass
" 2>/dev/null
}

pos=$(get_pos)
prev=$(cat "$STATE_FILE" 2>/dev/null || echo "")
echo "$pos" > "$STATE_FILE"

if [ -z "$pos" ]; then
    # MPV IPC not responding — process may be down; systemd Restart=always handles it
    echo "MPV IPC unavailable (stream not yet connected or MPV restarting)"
    exit 0
fi

if [ "$pos" = "$prev" ] && [ -n "$prev" ]; then
    echo "time-pos frozen at ${pos} — restarting display-stream"
    systemctl restart display-stream
else
    echo "Stream healthy: time-pos=${pos}"
fi
