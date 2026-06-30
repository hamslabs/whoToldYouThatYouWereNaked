#!/bin/bash
# GStreamer stream health check.
# Run by display-watchdog.timer every 30s.
# Detects dead pipeline by checking for active RTSP TCP connection to RPi4.

set -uo pipefail

PAIR_ID=$(cat /etc/pair-id)
RPI_IP="192.168.10.1${PAIR_ID}"
EVENT_LOG=/var/log/watchdog-events

log_restart() {
    echo "$(date -Iseconds) $1" | tee -a "$EVENT_LOG"
}

if ! systemctl is-active --quiet display-stream; then
    log_restart "restarted display-stream: service not active"
    systemctl restart display-stream
    exit 0
fi

if ss -tn state established "dst ${RPI_IP}:8554" 2>/dev/null | grep -q "${RPI_IP}"; then
    echo "Stream healthy: RTSP connection active to ${RPI_IP}:8554"
else
    log_restart "restarted display-stream: no RTSP connection to ${RPI_IP}:8554"
    systemctl restart display-stream
fi
