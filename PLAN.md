# Plan: Multi-Channel 1080p Video Streaming System

## Context

Building a turnkey embedded video streaming system for a local WiFi network. 5–6 identical pairs of boards: RPi4 (camera capture + encode + stream) paired with Rock Pi 4 (receive + decode + HDMI display). Network is dedicated to this traffic. System must boot autonomously, synchronize per-pair startup, and self-heal without human intervention.

---

## Architecture

```
Pair X
┌──────────────────────────────┐      WiFi (dedicated)      ┌──────────────────────────────┐
│  RPi4  192.168.10.1X         │  ───── RTSP H.264 ─────►  │  Rock Pi 4  192.168.10.2X    │
│                              │                             │                              │
│  Pi Camera → mediamtx        │  ◄──── ready? HTTP ──────  │  MPV → DRM → HDMI            │
│  status-server.py :7777      │                             │  readiness-server.py :7777   │
└──────────────────────────────┘                             └──────────────────────────────┘
```

X = pair number 1–6, stored in `/etc/pair-id` on each board.

---

## Technology Choices

| Concern | Choice | Reason |
|---|---|---|
| OS (RPi4) | Raspberry Pi OS Lite 64-bit **Bookworm** | Current release; best libcamera/hardware H.264 encoder support |
| OS (Rock Pi4) | Armbian **Debian Trixie, Minimal CLI** | Ubuntu Jammy no longer available; Debian Trixie is the current headless option |
| Streaming | mediamtx (RTSP server on RPi4) | Native RPi camera source, no extra pipeline code needed |
| Video codec | H.264 via RPi4 VideoCore hardware encoder | Low CPU; Rock Pi4 hardware decode supported |
| Resolution | 1920×1080 @ 30fps, ~5 Mbps | ~30 Mbps total across 6 pairs — well within WiFi 5 budget |
| Display | MPV with `--vo=drm` | No desktop environment needed; direct framebuffer access |
| Network | Static IPs per pair | No DNS/mDNS dependency; deterministic at boot |
| Startup sync | HTTP readiness probe (Python) | Rock Pi4 signals ready; RPi4 polls before streaming |
| Auto-restart | systemd `Restart=always` + watchdog timer | Two-layer: process restart + stream-health check |

---

## IP Addressing

| Board | IP |
|---|---|
| Router | 192.168.10.1 |
| Pair 1 — RPi4 | 192.168.10.11 |
| Pair 1 — Rock Pi4 | 192.168.10.21 |
| Pair 2 — RPi4 | 192.168.10.12 |
| Pair 2 — Rock Pi4 | 192.168.10.22 |
| … | … |

---

## File Structure

```
deploy/
├── rpi4/
│   ├── install.sh
│   ├── config/
│   │   └── mediamtx.yml
│   ├── systemd/
│   │   ├── camera-stream.service     # mediamtx; depends on network-online.target
│   │   ├── stream-watchdog.service   # one-shot health check (run by timer)
│   │   ├── stream-watchdog.timer     # fires every 30s
│   │   └── status-server.service     # HTTP :7777 status endpoint
│   └── scripts/
│       ├── camera-start.sh           # ExecStartPre: polls Rock Pi4 /ready
│       ├── watchdog.sh               # queries mediamtx API; kills+restarts if stalled
│       └── status-server.py          # /ready (always 200) + /status JSON
├── rockpi4/
│   ├── install.sh
│   ├── systemd/
│   │   ├── readiness-server.service  # HTTP :7777 readiness + status
│   │   ├── display-stream.service    # MPV fullscreen DRM display
│   │   ├── display-watchdog.service  # one-shot health check (run by timer)
│   │   └── display-watchdog.timer    # fires every 30s
│   └── scripts/
│       ├── readiness-server.py       # /ready 200 OK + /status JSON
│       ├── display-start.sh          # ExecStartPre: clears DRM framebuffer
│       └── watchdog.sh               # checks MPV IPC time-pos; kills+restarts if frozen
└── dashboard/
    ├── server.py                     # aggregates /status from all pairs, serves UI
    └── index.html                    # auto-refresh table; no JS framework
```

---

## Startup Sequence (per pair)

```
t=0   Both boards power on simultaneously
      │
      ├─ Rock Pi4: readiness-server.service starts (Python HTTP :7777)
      │            display-stream.service starts MPV → enters reconnect loop
      │            (MPV polls rtsp://192.168.10.1X:8554/stream every few seconds)
      │
      └─ RPi4: camera-start.sh polls http://192.168.10.2X:7777/ready every 2s
               (timeout 60s; fail-open after timeout so camera still streams)
                    │
                    └─ 200 OK received → mediamtx starts → RTSP goes live
                                          │
                                          └─ MPV connects → fullscreen display
```

**Fail-open**: If Rock Pi4 never responds within 60s, RPi4 starts mediamtx anyway so a display-side failure doesn't prevent capture.

---

## Auto-Restart Strategy

### Layer 1 — systemd

All services:
```ini
Restart=always
RestartSec=5
```

### Layer 2 — Watchdog (systemd timer, every 30s)

**RPi4 `watchdog.sh`** — uses mediamtx's built-in HTTP API (no ffprobe, no extra readers):
```bash
#!/bin/bash
result=$(curl -sf --max-time 5 http://localhost:9997/v3/paths/list)
# mediamtx returns tracks:[] when camera isn't encoding
tracks=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['items'][0]['tracks'])" 2>/dev/null)
if [ -z "$tracks" ] || [ "$tracks" = "[]" ]; then
    systemctl restart camera-stream
fi
```

**Rock Pi4 `watchdog.sh`** — compares `time-pos` across two 15s samples to detect frozen video:
```bash
#!/bin/bash
STATE_FILE=/run/mpv-watchdog-pos
get_pos() {
    echo '{"command":["get_property","time-pos"]}' \
        | socat -t2 - UNIX-CONNECT:/tmp/mpvsocket 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',''))" 2>/dev/null
}
pos=$(get_pos)
prev=$(cat "$STATE_FILE" 2>/dev/null || echo "")
echo "$pos" > "$STATE_FILE"

# Only flag as stuck if MPV has a position (stream is connected) but it hasn't advanced
if [ -n "$pos" ] && [ "$pos" = "$prev" ]; then
    systemctl restart display-stream
fi
```

The watchdog runs every 30s; consecutive equal `time-pos` values (two 30s intervals apart) mean the stream is frozen → restart.

### MPV command (Rock Pi4)

```bash
mpv rtsp://192.168.10.1X:8554/stream \
    --vo=drm \
    --fullscreen \
    --profile=low-latency \
    --cache=no \
    --rtsp-transport=tcp \
    --loop=inf \
    --keep-open=yes \
    --input-ipc-server=/tmp/mpvsocket
```

> **Note**: `--stream-open-filename` is not a valid MPV flag — the RTSP URL is the first positional argument. `--cache=no` replaces the deprecated `--no-cache`. `--loop=inf` + `--keep-open=yes` cause MPV to reconnect automatically when the stream drops; no Rock Pi4 restart needed when RPi4 comes back.

### display-start.sh (Rock Pi4 ExecStartPre)

Clears the DRM framebuffer so no stale frame shows during reconnect:
```bash
#!/bin/bash
# Clear primary framebuffer to black before MPV takes over
dd if=/dev/zero of=/dev/fb0 bs=1M count=8 2>/dev/null || true
```

---

## mediamtx Configuration (RPi4)

```yaml
# mediamtx.yml
api:
  address: :9997          # used by watchdog and status-server

rtsp:
  address: :8554

paths:
  stream:
    source: rpiCamera
    rpiCamera:
      width: 1920
      height: 1080
      fps: 30
      bitrate: 5000000
      codec: H264
```

---

## Status Server

Both boards expose port 7777. On Rock Pi4 this is `readiness-server.py` (already needed for startup sync). On RPi4 it's `status-server.py` (new file, same structure).

| Path | Returns |
|---|---|
| `GET /ready` | `200 OK` plain text (Rock Pi4 only; RPi4 always returns 200 for symmetry) |
| `GET /status` | JSON: `{"pair_id": N, "role": "rpi4"\|"rockpi4", "stream_up": true\|false, "uptime_s": N, "fps": N, "bitrate_kbps": N, "last_error": "..."}` |

- **RPi4**: `stream_up` from `GET localhost:9997/v3/paths/list` (non-empty `tracks`). `fps`/`bitrate_kbps` from the same response.
- **Rock Pi4**: `stream_up` from MPV IPC `time-pos` being non-null. `fps` from `estimated-vf-fps`.

### Dashboard

`dashboard/server.py` aggregates all pairs' `/status` every 5s and serves `index.html`. Reads `/etc/pair-count` (set by install.sh) to know how many boards to query. Runs on any board or laptop on the Tailscale network.

---

## Installation

Each board requires before running `install.sh`:
1. `/etc/pair-id` — single digit 1–6
2. `/etc/pair-count` — total number of pairs (5 or 6) — **needed by dashboard**
3. WiFi credentials baked into OS image at flash time
4. User account created at flash time — **no default `pi` user since Bullseye (April 2022)**. Use Raspberry Pi Imager's Advanced Options to set username/password, or add a `userconf` file to the boot partition:
   ```bash
   # Generate a SHA-512 hashed password
   echo 'mypassword' | openssl passwd -6 -stdin
   # Write to boot partition (adjust disk path as needed)
   echo 'myuser:$6$...<hash>...' > /Volumes/bootfs/userconf
   ```

### RPi4 `install.sh` steps

```bash
PAIR_ID=$(cat /etc/pair-id)
RPI_IP="192.168.10.1${PAIR_ID}"
ROCK_IP="192.168.10.2${PAIR_ID}"

# Static IP — Raspberry Pi OS Bookworm uses NetworkManager (not dhcpcd)
nmcli con mod "$(nmcli -g NAME con show | head -1)" \
    ipv4.method manual \
    ipv4.addresses "${RPI_IP}/24" \
    ipv4.gateway 192.168.10.1 \
    ipv4.dns 192.168.10.1

# Install mediamtx (download latest binary from GitHub releases)
# Install python3, socat, curl (apt)
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --authkey=<REUSABLE_KEY> --hostname="rpi4-${PAIR_ID}"

# Copy config/scripts/units; sed-replace 1X/2X placeholders with actual IPs
# systemctl enable + start all units
```

### Rock Pi4 `install.sh` steps

Same structure; static IP via `/etc/netplan/` (Armbian uses netplan):
```yaml
# /etc/netplan/01-static.yaml
network:
  version: 2
  ethernets: {}
  wifis:
    wlan0:
      dhcp4: false
      addresses: [192.168.10.2X/24]
      gateway4: 192.168.10.1
```

Both scripts use `sed` to replace `1X`/`2X` placeholders in copied config files with the actual pair-id digit.

---

## Tailscale (Remote Management)

Stream traffic uses local IPs (`192.168.10.x`) — Tailscale never touches it. Zero impact on video performance.

**Internet access**: Router is normally air-gapped. Connect iPhone via USB for internet on-demand (confirmed supported by router).

**Use iPhone for**:
- Initial Tailscale registration (one-time per board)
- Tailscale key renewal (~6 months)
- OS/package updates

**Without iPhone**: Boards that have previously registered can route WireGuard traffic to each other over the local subnet (Tailscale peer-to-peer). External access from outside the network requires iPhone.

**Tag**: `tag:newsstream` for ACL grouping. Hostnames: `rpi4-1` … `rpi4-6`, `rockpi4-1` … `rockpi4-6`.

---

## Verification

1. Flash pair 1, set `/etc/pair-id=1` and `/etc/pair-count=1`, boot both boards.
2. `ssh <username>@192.168.10.11` → `systemctl status camera-stream` — expect `active (running)`. (Use the username set via Imager or `userconf` at flash time — no default `pi` user.)
3. `ssh user@192.168.10.21` → `systemctl status display-stream` — expect `active (running)`.
4. HDMI on Rock Pi4 shows live 1080p video.
5. **Watchdog test**: `systemctl stop camera-stream` on RPi4 → verify systemd restarts it within 5s.
6. **MPV reconnect test**: `kill $(pidof mpv)` on Rock Pi4 → verify MPV restarts within 5s.
7. **Power-cycle test**: Pull RPi4 power → Rock Pi4 enters reconnect loop → restore RPi4 power → verify stream resumes without touching Rock Pi4.
8. **Watchdog timer test**: `systemctl start stream-watchdog` on RPi4 (manual trigger) → confirm it exits 0 when stream is healthy.
9. **Scale test**: Repeat with all 6 pairs running simultaneously; confirm no WiFi congestion (monitor with `iw dev wlan0 station dump` on router).
10. **Status endpoint**: `curl http://192.168.10.11:7777/status` → valid JSON with `stream_up: true`.

---

## Future: Face Detection (RPi5 + AI Kit)

mediamtx supports multiple concurrent readers. The AI board subscribes to existing RTSP paths — zero changes to sender or display side:

```
RPi4-1 (mediamtx) ──► Rock Pi4-1 (display)
                   ──► RPi5 AI board (face detection)  ← second reader, no impact
```

Add `deploy/ai/` when ready (GStreamer + Hailo SDK). AI board gets its own Tailscale node.

---

## Open Items (deferred)

- Audio support
- Channel switching
- Stream recording
- Web dashboard deployment target (currently runs on any Tailscale node)
