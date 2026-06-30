# Setup Guide

All paths are relative to `newSystem/`. Run commands on your Mac unless noted otherwise.

---

## What you need (per pair)

- RPi4 + Rock Pi 4 boards
- 2× micro SD card (16GB+ recommended)
- Mac with SD card reader (or USB adapter)
- **2× Ethernet cables** (for initial setup — boards connect via Ethernet first, then switch to WiFi after install)
- HDMI cable + monitor (Rock Pi4 verification)
- iPhone + cable (for router internet access during Tailscale setup)

> **Why Ethernet?** The boards have no WiFi credentials when first flashed. `install.sh` is what configures WiFi — but you need to SSH in to run it. Plug each board into the router via Ethernet for the initial session. After `install.sh` runs and the board reboots, it connects via WiFi automatically and Ethernet can be unplugged.

---

## Step 1 — OS images

Already in `images/`:

| Board | File |
|---|---|
| RPi4 | `images/rpi4-os-lite-arm64.img.xz` |
| Rock Pi4 Plus | `images/armbian-rockpi4-plus-trixie-minimal.img.xz` |

---

## Step 2 — Flash the SD cards

Two scripts handle this. Both live in `deploy/` and are run from the repo root. Do one card at a time.

### Variables at the top of each script

| Variable | Default | What it is |
|---|---|---|
| `DISK` | `disk5` | Mac disk number for the SD card — find it with `diskutil list` |
| `USER` | `gwart` | Linux username created on the RPi4 (RPi4 script only) |
| `PASSWORD` | `snowden` | Password for that user (RPi4 script only) |

Change `DISK` if your SD card reader shows up as a different number. `USER` and `PASSWORD` set the credentials you'll SSH in with on the RPi4.

### Flash RPi4 card

Insert the SD card, confirm `DISK` is correct, then:

```bash
bash deploy/flash-rpi4.sh
```

This flashes the image, enables SSH, and writes a `userconf` file so the `gwart` account exists on first boot — no extra manual steps.

### Flash Rock Pi4 card

Swap cards, then:

```bash
bash deploy/flash-rockpi4.sh
```

Armbian SSH is enabled by default. On first login (`root` / `1234`) Armbian's setup wizard will prompt for a new root password and offer to create a user — create `gwart` with password `snowden` when asked.

> **Finding your disk number:** run `diskutil list` and look for your SD card by size (e.g. `32.0 GB`). Never use your Mac's internal drive (`disk0`).

---

## Step 3 — First boot: set pair ID

Plug both boards into the router via **Ethernet**, then power them on. Wait ~60s to boot. Both will grab DHCP addresses over Ethernet.

### Find each board's IP

```bash
# On your Mac — scan local network
arp -a
```

Or check your router's DHCP client list.

- RPi4 will show up as `raspberrypi` or similar
- Rock Pi4 will show up as `rockpi4` or `armbian` or similar

### SSH into RPi4

```bash
ssh gwart@<rpi4-ip>   # password: snowden
```

### SSH into Rock Pi4

Default credentials on a fresh Armbian flash: `root` / `1234`. The first-login wizard forces a password change and offers to create a user — create `gwart` / `snowden` when prompted.

```bash
ssh gwart@<rockpi4-ip>   # or root if gwart not yet created
```

---

## Step 4 — Run install.sh

On **each board**, clone the repo, set the pair ID, then run the install script:

### RPi4

```bash
git clone https://github.com/hamslabs/whoToldYouThatYouWereNaked /opt/newsystem
sudo bash /opt/newsystem/deploy/set-pair.sh 1 6   # pair 1 of 6
cd /opt/newsystem/deploy/rpi4
sudo bash install.sh
```

### Rock Pi4

```bash
git clone https://github.com/hamslabs/whoToldYouThatYouWereNaked /opt/newsystem
bash /opt/newsystem/deploy/set-pair.sh 1 6   # pair 1 of 6
cd /opt/newsystem/deploy/rockpi4
bash install.sh
```

The script will:
- Configure the static IP for this pair
- Set the hostname (`rpi4-1`, `rockpi4-1`, etc.)
- Install mediamtx (RPi4) or GStreamer (Rock Pi4)
- Install Tailscale
- Install and enable all systemd services
- Print next steps when done

---

## Step 5 — Register Tailscale

**Connect iPhone to router first** (for internet access). Then on each board:

```bash
tailscale up --authkey=<YOUR_REUSABLE_KEY> --hostname=rpi4-1 --advertise-tags=tag:newsstream
```

Replace `rpi4-1` with the board's actual hostname (printed at the end of `install.sh`).

> **Getting an auth key**: Tailscale admin console → Settings → Keys → Generate auth key → check "Reusable" → copy key. One key works for all 12 boards.

Disconnect iPhone from router when done.

---

## Step 6 — Reboot and verify

On each board:
```bash
sudo reboot
```

After reboot the board connects via **WiFi** and gets its static IP. You can unplug the Ethernet cable now. SSH back in using the static IP:

| Pair | RPi4 IP | Rock Pi4 IP |
|---|---|---|
| 1 | 192.168.10.11 | 192.168.10.21 |
| 2 | 192.168.10.12 | 192.168.10.22 |
| 3 | 192.168.10.13 | 192.168.10.23 |
| 4 | 192.168.10.14 | 192.168.10.24 |
| 5 | 192.168.10.15 | 192.168.10.25 |
| 6 | 192.168.10.16 | 192.168.10.26 |

### Check services

```bash
# On RPi4
systemctl status camera-stream
systemctl status status-server
systemctl list-timers stream-watchdog.timer

# On Rock Pi4
systemctl status display-stream
systemctl status readiness-server
systemctl list-timers display-watchdog.timer
```

All should show `active`.

### Check video

HDMI output on Rock Pi4 should show live 1080p video within ~10s of both boards being up.

### Check status endpoint

```bash
curl http://192.168.10.11:7777/status   # RPi4 pair 1
curl http://192.168.10.21:7777/status   # Rock Pi4 pair 1
```

Both return JSON with `"stream_up": true`.

### Self-healing tests

```bash
# Test 1: kill mediamtx on RPi4 — should restart within 5s
sudo systemctl stop camera-stream
sleep 6
systemctl status camera-stream   # expect active (running)

# Test 2: kill GStreamer on Rock Pi4 — should restart within 5s
sudo systemctl kill display-stream
sleep 6
systemctl status display-stream  # expect active (running)
```

---

## Repeat for pairs 2–6

For each additional pair, repeat Steps 2–6 with the pair number incremented. The only thing that changes per pair is the number you write to `/etc/pair-id` in Step 3.

---

## Running the dashboard

From any board or laptop on the Tailscale network:

```bash
git clone https://github.com/hamslabs/whoToldYouThatYouWereNaked /opt/newsystem
cd /opt/newsystem/deploy/dashboard
python3 server.py --port 8080
```

Open `http://localhost:8080` in a browser. The dashboard polls all boards every 5s and shows stream status with green/red indicators.

> The dashboard reads `/etc/pair-count` to know how many pairs to query. If running from your Mac (no `/etc/pair-count`), it defaults to 6.

---

## Troubleshooting

**Board won't connect to WiFi after install**
The script configures `gwart` with the stored credentials. If the board is out of range during install, the connection will come up once it's in range. Check with `nmcli` (RPi4) or `networkctl status` (Rock Pi4).

**`git clone` fails during install (no internet)**
Make sure the iPhone is plugged into the router before running install.sh. The clone step needs internet to reach GitHub.

**SSH times out after static IP is set**
Update your SSH target from the old DHCP address to the static IP from the table above.

**Rock Pi4 shows black screen but service is running**
Stream isn't up yet. Check RPi4 camera-stream status. Rock Pi4 will display video as soon as RPi4's RTSP stream goes live — GStreamer reconnects automatically.

**Watchdog keeps restarting the service**
Check journal logs: `journalctl -u camera-stream -n 50` or `journalctl -u display-stream -n 50`.
