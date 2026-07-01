#!/usr/bin/env python3
"""Central dashboard server.

Aggregates /status from all RPi4 and Rock Pi4 boards and serves index.html.
Reads /etc/pair-count to know how many pairs exist.
Run on any board or laptop on the Tailscale network.

Usage: python3 server.py [--port 8080]
"""

import argparse
import concurrent.futures
import http.server
import json
import threading
import time
import urllib.request
from pathlib import Path

POLL_INTERVAL = 5
STATUS_CACHE = {}
CACHE_LOCK = threading.Lock()

PAIR_COUNT_FILE = Path("/etc/pair-count")


def get_pair_count():
    try:
        return int(PAIR_COUNT_FILE.read_text().strip())
    except Exception:
        return 6  # default to max


def fetch_status(url):
    try:
        with urllib.request.urlopen(url, timeout=3) as r:
            return json.load(r)
    except Exception as e:
        return {"error": str(e), "stream_up": False}


def poll_loop():
    while True:
        pair_count = get_pair_count()
        targets = {}
        for i in range(1, pair_count + 1):
            targets[f"rpi4-{i}"]    = f"http://192.168.10.1{i}:7777/status"
            targets[f"rockpi4-{i}"] = f"http://192.168.10.2{i}:7777/status"

        with concurrent.futures.ThreadPoolExecutor(max_workers=len(targets)) as ex:
            futures = {key: ex.submit(fetch_status, url) for key, url in targets.items()}
        results = {key: fut.result() for key, fut in futures.items()}

        results["_updated"] = time.time()
        results["_pair_count"] = pair_count
        with CACHE_LOCK:
            STATUS_CACHE.clear()
            STATUS_CACHE.update(results)
        time.sleep(POLL_INTERVAL)


DASHBOARD_DIR = Path(__file__).parent


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_POST(self):
        if self.path.startswith("/api/clear/"):
            board = self.path[len("/api/clear/"):]
            with CACHE_LOCK:
                d = STATUS_CACHE.get(board, {})
            pair_id = d.get("pair_id")
            role = d.get("role")
            if not pair_id or not role:
                self._respond(404, "text/plain", b"Unknown board\n")
                return
            prefix = "1" if role == "rpi4" else "2"
            url = f"http://192.168.10.{prefix}{pair_id}:7777/clear-restarts"
            try:
                req = urllib.request.Request(url, method="POST", data=b"")
                urllib.request.urlopen(req, timeout=3)
                with CACHE_LOCK:
                    if board in STATUS_CACHE:
                        STATUS_CACHE[board]["recent_restarts"] = []
                self._respond(200, "text/plain", b"OK\n")
            except Exception as e:
                self._respond(502, "text/plain", str(e).encode())
        else:
            self._respond(404, "text/plain", b"Not found\n")

    def do_GET(self):
        if self.path == "/api/status":
            with CACHE_LOCK:
                body = json.dumps(STATUS_CACHE).encode()
            self._respond(200, "application/json", body)
        elif self.path in ("/", "/index.html"):
            body = (DASHBOARD_DIR / "index.html").read_bytes()
            self._respond(200, "text/html", body)
        else:
            self._respond(404, "text/plain", b"Not found\n")

    def _respond(self, code, content_type, body):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()

    t = threading.Thread(target=poll_loop, daemon=True)
    t.start()

    print(f"Dashboard at http://{args.host}:{args.port}")
    server = http.server.HTTPServer((args.host, args.port), Handler)
    server.serve_forever()
