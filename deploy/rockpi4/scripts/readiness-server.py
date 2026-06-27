#!/usr/bin/env python3
"""HTTP readiness + status server for Rock Pi4 (port 7777).

GET /ready  -> 200 OK  (signals to RPi4 that this board is up and ready)
GET /status -> JSON with MPV playback state from IPC socket
"""

import http.server
import json
import os
import socket
import time
from pathlib import Path

PORT = 7777
PAIR_ID = Path("/etc/pair-id").read_text().strip()
BOOT_TIME = time.time()
MPV_SOCKET = "/tmp/mpvsocket"


def mpv_query(prop):
    """Send a get_property command to MPV IPC socket. Returns value or None."""
    try:
        cmd = json.dumps({"command": ["get_property", prop]}).encode() + b"\n"
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            s.connect(MPV_SOCKET)
            s.sendall(cmd)
            raw = s.recv(4096)
        resp = json.loads(raw.decode().strip())
        if resp.get("error") == "success":
            return resp.get("data")
    except Exception:
        pass
    return None


def get_mpv_status():
    time_pos = mpv_query("time-pos")
    fps = mpv_query("estimated-vf-fps") or 0
    stream_up = time_pos is not None
    last_error = "" if stream_up else "MPV not playing or IPC socket unavailable"
    return stream_up, round(fps, 1), last_error


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if self.path == "/ready":
            self._respond(200, "text/plain", b"OK\n")
        elif self.path == "/status":
            stream_up, fps, last_error = get_mpv_status()
            payload = {
                "pair_id": int(PAIR_ID),
                "role": "rockpi4",
                "stream_up": stream_up,
                "uptime_s": int(time.time() - BOOT_TIME),
                "fps": fps,
                "bitrate_kbps": 0,
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
    print(f"Readiness/status server listening on :{PORT}")
    server.serve_forever()
