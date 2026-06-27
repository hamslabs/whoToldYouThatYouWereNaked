# Plan: Multi-Channel 1080p Video Streaming System

## Context

Building a turnkey embedded video streaming system for a local WiFi network. 5–6 identical pairs of boards, each pair consisting of an RPi4 (camera capture + encode + stream) and a Rock Pi 4 (receive + decode + HDMI display). The network is dedicated to this traffic only. The system must boot autonomously, synchronize per-pair startup, and self-heal on any error — no human intervention expected in normal operation.

---

## Architecture

```
Pair X
┌──────────────────────────────┐      WiFi (dedicated)      ┌──────────────────────────────┐
│  RPi4                        │  ───── RTSP H.264 ─────►  │  Rock Pi 4                   │
│  192.168.10.1X               │                             │  192.168.10.2X               │
│                              │  ◄──── ready? HTTP ──────  │                              │
│  Pi Camera → mediamtx        │                             │  MPV → DRM → HDMI            │
└──────────────────────────────┘                             └──────────────────────────────┘
```

X = pair number 1–6, stored in `/etc/pair-id` on each board.

---

## Technology Choices

| Concern | Choice | Reason |
|---|---|---|
| OS (RPi4) | Raspberry Pi OS Lite 64-bit | Best libcamera/hardware H.264 encoder support |
| OS (Rock Pi4) | Armbian (Debian Trixie, Minimal CLI) | Ubuntu Jammy no longer available for this board; Debian Trixie is the current headless option |
| Streaming | mediamtx (RTSP server on RPi4) | Native RPi camera source, no extra pipeline code needed |
| Video codec | H.264 via RPi4 hardware encoder | Low CPU, Rock Pi4 hardware decode supported |
| Resolution | 1920×1080 @ 30fps, ~5 Mbps | ~30 Mbps total across 6 pairs — well within WiFi 5 budget |
| Display | MPV with `--vo=drm` | No desktop environment needed; direct framebuffer access |
| Network | Static IPs per pair | No DNS/mDNS dependency; deterministic at boot |
| Startup sync | HTTP readiness probe (Python) | Rock Pi4 signals ready; RPi4 polls before streaming |
| Auto-restart | systemd `Restart=always` + watchdog | Two-layer: process restart + stream-health check |

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
│   ├── install.sh                  # one-time setup; reads /etc/pair-id
│   ├── config/
│   │   └── mediamtx.yml            # RTSP server + RPi camera source config
│   └── systemd/
│       ├── camera-stream.service   # mediamtx; depends on network-online.target
│       └── stream-watchdog.service # watchdog timer unit
│   └── scripts/
│       ├── camera-start.sh         # pre-start: poll Rock Pi readiness endpoint
│       └── watchdog.sh             # check ffprobe stream health; restart if stalled
└── rockpi4/
    ├── install.sh
    ├── systemd/
    │   ├── readiness-server.service  # tiny HTTP server (Python) on :7777
    │   ├── display-stream.service    # MPV fullscreen DRM display
    │   └── display-watchdog.service  # watchdog timer unit
    └── scripts/
        ├── readiness-server.py       # responds 200 OK when board is ready
        ├── display-start.sh          # pre-start: wait for mediamtx stream to appear
        └── watchdog.sh               # check MPV is alive + frames advancing; restart if stuck
```

---

## Startup Sequence (per pair)

1. Both boards power on simultaneously.
2. **Rock Pi4** boots → `readiness-server.service` starts (Python HTTP on `:7777`) → `display-stream.service` starts MPV in reconnect loop waiting for `rtsp://192.168.10.1X:8554/stream`.
3. **RPi4** boots → `camera-start.sh` polls `http://192.168.10.2X:7777/ready` every 2s (timeout: 60s).
4. Once Rock Pi4 responds 200, RPi4 starts `mediamtx` → Pi Camera begins capture → RTSP stream goes live.
5. MPV on Rock Pi4 connects and displays fullscreen.

If Rock Pi4 never responds within 60s, RPi4 starts anyway (fail-open) so a display failure doesn't prevent recording.

---

## Auto-Restart Strategy

### Layer 1 — systemd
All services use:
```ini
Restart=always
RestartSec=5
```

### Layer 2 — Watchdog (runs every 30s via systemd timer)

**RPi4 watchdog** (`watchdog.sh`):
- Check `mediamtx` process is running.
- Run `ffprobe rtsp://localhost:8554/stream` — if it times out or errors, kill mediamtx and let systemd restart it.
- Timeout threshold: 10s of no stream data = stall.

**Rock Pi4 watchdog** (`watchdog.sh`):
- Check MPV process is running.
- Query MPV IPC socket (`--input-ipc-server=/tmp/mpvsocket`) for `video-params/w` — if socket unresponsive or returns null for >15s, kill MPV and let systemd restart it.

### MPV reconnect flags (Rock Pi4)
```
--loop=inf
--stream-open-filename=rtsp://192.168.10.1X:8554/stream
--profile=low-latency
--no-cache
--rtsp-transport=tcp
--keep-open=yes
```

MPV will automatically reconnect when the stream comes back after an RPi4 restart — no Rock Pi4 restart needed in that case.

---

## mediamtx Configuration (RPi4)

```yaml
# mediamtx.yml
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

mediamtx handles the libcamera integration natively — no separate capture pipeline script.

---

## Installation

Each board needs only two things set before running `install.sh`:
1. `/etc/pair-id` — a single digit (1–6)
2. WiFi credentials in the OS image (set during flash via `raspi-config` or Armbian first-boot)

`install.sh` on each board:
- Reads `PAIR_ID=$(cat /etc/pair-id)`
- Configures static IP (`/etc/dhcpcd.conf` on RPi4, `/etc/netplan/` on Armbian)
- Installs mediamtx (RPi4) or MPV (Rock Pi4) via apt/binary
- Installs Tailscale and sets hostname (`rpi4-$PAIR_ID` or `rockpi4-$PAIR_ID`)
- Writes systemd units and enables them
- Reboots

After first boot, run `tailscale up --authkey=<reusable-key> --hostname=<board-hostname>` once per board (or bake the auth key into `install.sh`).

---

## Verification

1. Flash both boards, set pair-id=1, boot on the dedicated WiFi network.
2. SSH into RPi4 (`192.168.10.11`): `systemctl status camera-stream` should show `active (running)`.
3. SSH into Rock Pi4 (`192.168.10.21`): `systemctl status display-stream` should show `active (running)`.
4. HDMI output on Rock Pi4 should show live 1080p video.
5. Kill `mediamtx` on RPi4 manually → verify it restarts within 5s and Rock Pi4 reconnects automatically.
6. Kill MPV on Rock Pi4 manually → verify it restarts within 5s.
7. Unplug RPi4 power → verify Rock Pi4 enters reconnect loop → replug RPi4 → verify stream resumes without intervention.
8. Repeat for all 6 pairs simultaneously to confirm no WiFi congestion issues.

---

## Status Web Server

Each board exposes a lightweight HTTP status endpoint so the whole system can be monitored from any device on the Tailscale network (phone, laptop, etc.).

### Per-board status endpoint (port 7777, same as readiness server)

Extend the existing `readiness-server.py` on both board types to serve:

| Path | Returns |
|---|---|
| `GET /ready` | `200 OK` (Rock Pi4 ready to receive) |
| `GET /status` | JSON: `{pair_id, role, stream_up, uptime_s, fps, bitrate_kbps, last_error}` |

- **RPi4**: queries mediamtx's built-in HTTP API (`http://localhost:9997/v3/paths/list`) for stream stats.
- **Rock Pi4**: queries MPV IPC socket for `video-params/w`, `estimated-vf-fps`, and `stream-pos`.

### Central dashboard (optional, runs anywhere on Tailscale)

A single-page HTML dashboard (`dashboard/index.html` + `dashboard/server.py`) that:
- Polls all 6 boards' `/status` endpoints every 5s
- Shows a table: pair | RPi4 status | Rock Pi4 status | fps | bitrate | last error
- Auto-refreshes; green/red indicators per stream
- Served by a tiny Python HTTP server — runs on any board or a laptop

```
deploy/
└── dashboard/
    ├── server.py        # aggregates /status from all pairs, serves the UI
    └── index.html       # auto-refresh table, no JS framework needed
```

The dashboard reads `/etc/pair-count` (value: 5 or 6) and `/etc/pair-id` to know which peers to query.

---

## Future: Face Detection (RPi5 + AI Kit)

**Not implemented now** — but the architecture is designed to accommodate it without changes.

### How it fits

mediamtx natively supports **multiple concurrent readers** on the same RTSP path. The AI board simply opens an additional RTSP connection to any (or all) RPi4 streams:

```
RPi4-1 (mediamtx) ──► Rock Pi4-1 (display)
                   ──► RPi5 AI board (face detection)  ← second reader, zero impact on display
```

### What to keep in mind during implementation

- Do **not** put any AI processing on the streaming RPi4s or display Rock Pi4s — keep them single-purpose.
- The AI board (RPi5 + Hailo-8L) will subscribe to RTSP streams from mediamtx; no changes needed to the sender side.
- mediamtx path config already supports multiple readers by default — no extra configuration needed.
- When the time comes, add an `ai/` section to `deploy/` with the RPi5 pipeline (GStreamer + Hailo SDK). The AI board gets its own Tailscale node and its own pair-id range (e.g., `ai-1`).
- Consider whether face detection output (bounding boxes, identities) needs to be overlaid on the Rock Pi4 display or just logged — this determines whether the data path eventually loops back to the display side.

---

## Tailscale (Remote Management)

Tailscale runs on all boards for SSH access and remote management. It does **not** affect stream performance because:
- Stream traffic flows over local IPs (`192.168.10.x`) — Tailscale never sees it.
- Tailscale on ARM uses ~0.1–2% CPU at idle with no data routed through it.
- No WireGuard encryption overhead on the video path.

### Installation
`install.sh` installs Tailscale via the official script on both RPi OS and Armbian:
```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### Configuration
Each board is registered once manually (`tailscale up --authkey=<key>`) during initial setup. After that, it auto-reconnects on boot.

### Internet access via iPhone USB tethering

The router is normally air-gapped. Internet is provided on-demand by connecting an iPhone via USB to the router (confirmed supported). When the iPhone is connected, the router's WAN is the iPhone's cellular connection and all boards reach the internet normally.

**When to connect the iPhone:**
- Initial Tailscale registration for all boards (one-time setup)
- Tailscale key renewal (~every 6 months — Tailscale will warn in advance)
- OS/package updates (scheduled maintenance)
- Any other internet-dependent operation

**When iPhone is disconnected (normal operation):**
- All video streams are unaffected — they use local IPs only.
- Tailscale nodes that have previously exchanged keys maintain direct WireGuard tunnels to each other on the local subnet, so SSH between boards still works.
- External access (from a phone or laptop outside the network) is unavailable until iPhone is reconnected.

### Key notes
- Use a Tailscale tag (e.g. `tag:newsstream`) to group all boards in the Tailscale ACL for easy access control.
- Tailscale hostname convention: `rpi4-1`, `rpi4-2`, …, `rockpi4-1`, `rockpi4-2`, … derived from pair-id.
- Headscale (self-hosted coordination server) is **not needed** — the iPhone tethering approach covers all internet-dependent Tailscale operations without the complexity of a self-hosted server.

---

## Open Items (deferred)

The user mentioned additional requirements not yet specified. Implementation should be kept modular so these can be layered on:
- Possible: audio support, channel switching, stream recording.
- Remote management via Tailscale SSH is now baseline; decide whether to add a web dashboard later.
