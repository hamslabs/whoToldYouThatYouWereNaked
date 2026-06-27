#!/usr/bin/env python3
"""HTTP status server for RPi4 (port 7777).

GET /ready  -> 200 OK  (always; for symmetry with Rock Pi4)
GET /status -> JSON stream health from mediamtx API
"""

import http.server
import json
import os
import subprocess
import time
import urllib.request
from pathlib import Path

PORT = 7777
PAIR_ID = Path("/etc/pair-id").read_text().strip()
BOOT_TIME = time.time()


def get_mediamtx_status():
    try:
        with urllib.request.urlopen(
            "http://localhost:9997/v3/paths/list", timeout=3
        ) as r:
            data = json.load(r)
        items = data.get("items", [])
        if not items:
            return False, 0, 0, ""
        item = items[0]
        tracks = item.get("tracks", [])
        stream_up = len(tracks) > 0
        # mediamtx v1 doesn't expose per-path fps/bitrate in paths/list;
        # use readersCount as a proxy for activity
        readers = item.get("readersCount", 0)
        return stream_up, 0, 0, ""
    except Exception as e:
        return False, 0, 0, str(e)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if self.path == "/ready":
            self._respond(200, "text/plain", b"OK\n")
        elif self.path == "/status":
            stream_up, fps, bitrate_kbps, last_error = get_mediamtx_status()
            payload = {
                "pair_id": int(PAIR_ID),
                "role": "rpi4",
                "stream_up": stream_up,
                "uptime_s": int(time.time() - BOOT_TIME),
                "fps": fps,
                "bitrate_kbps": bitrate_kbps,
                "last_error": last_error,
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
    print(f"Status server listening on :{PORT}")
    server.serve_forever()
