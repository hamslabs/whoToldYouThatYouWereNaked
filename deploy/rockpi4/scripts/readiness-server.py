#!/usr/bin/env python3
"""HTTP readiness + status server for Rock Pi4 (port 7777).

GET /ready  -> 200 OK  (signals to RPi4 that this board is up and ready)
GET /status -> JSON with GStreamer display-stream service state
"""

import http.server
import json
import subprocess
import time
from pathlib import Path

PORT = 7777
PAIR_ID = Path("/etc/pair-id").read_text().strip()
BOOT_TIME = time.time()
EVENT_LOG = Path("/var/log/watchdog-events")


def get_recent_events(n=5):
    try:
        lines = EVENT_LOG.read_text().splitlines()
        return lines[-n:] if lines else []
    except Exception:
        return []


def get_cpu_temp():
    try:
        t0 = int(Path("/sys/class/thermal/thermal_zone0/temp").read_text()) / 1000
        t1 = int(Path("/sys/class/thermal/thermal_zone1/temp").read_text()) / 1000
        return round(max(t0, t1), 1)
    except Exception:
        return None


def get_stream_status():
    try:
        result = subprocess.run(
            ["systemctl", "is-active", "display-stream"],
            capture_output=True, text=True, timeout=3
        )
        stream_up = result.stdout.strip() == "active"
        last_error = "" if stream_up else f"display-stream is {result.stdout.strip()}"
    except Exception as e:
        stream_up = False
        last_error = str(e)
    return stream_up, last_error


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if self.path == "/ready":
            self._respond(200, "text/plain", b"OK\n")
        elif self.path == "/status":
            stream_up, last_error = get_stream_status()
            payload = {
                "pair_id": int(PAIR_ID),
                "role": "rockpi4",
                "stream_up": stream_up,
                "uptime_s": int(time.time() - BOOT_TIME),
                "cpu_temp_c": get_cpu_temp(),
                "last_error": last_error,
                "recent_restarts": get_recent_events(),
            }
            body = json.dumps(payload).encode()
            self._respond(200, "application/json", body)
        else:
            self._respond(404, "text/plain", b"Not found\n")

    def _respond(self, code, content_type, body):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    server = http.server.HTTPServer(("", PORT), Handler)
    print(f"Readiness/status server listening on :{PORT}")
    server.serve_forever()
