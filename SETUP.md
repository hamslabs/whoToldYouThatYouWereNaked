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

Do one card at a time. Insert the SD card, then find its disk number:

```bash
diskutil list
```

Look for your SD card by size (e.g. `32.0 GB`). Note the disk number — it will be something like `/dev/disk2`. **Do not confuse it with your Mac's internal drive.**

### Flash RPi4 card

```bash
# Unmount (don't eject yet)
diskutil unmountDisk /dev/disk2

# Flash — replace disk2 with your actual disk number
xzcat images/rpi4-os-lite-arm64.img.xz | sudo dd of=/dev/rdisk2 bs=4m

# Press Ctrl+T at any time to see progress
```

After `dd` finishes, a volume called `bootfs` mounts on your Mac (FAT32 boot partition). Enable SSH and create a user account — **there is no default `pi` user since Bullseye (April 2022)**:

```bash
# Enable SSH on first boot
touch /Volumes/bootfs/ssh

# Create a user account (skip this if you used Raspberry Pi Imager's Advanced Options)
echo 'mypassword' | openssl passwd -6 -stdin   # copy the output hash
echo 'myuser:$6$...<paste hash here>...' > /Volumes/bootfs/userconf
```

Then eject:
```bash
diskutil eject /dev/disk2
```

### Flash Rock Pi4 card

```bash
diskutil unmountDisk /dev/disk2
xzcat images/armbian-rockpi4-plus-trixie-minimal.img.xz | sudo dd of=/dev/rdisk2 bs=4m
diskutil eject /dev/disk2
```

> Armbian has SSH enabled by default — no extra step needed.

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

Use the username and password you set via Raspberry Pi Imager or the `userconf` file at flash time.

```bash
ssh <username>@<rpi4-ip>
```

Once in:
```bash
echo 1 | sudo tee /etc/pair-id      # change 1 to the pair number (1–6)
echo 6 | sudo tee /etc/pair-count   # total number of pairs you're deploying
```

### SSH into Rock Pi4

Default credentials: user `root`, password `1234`. Armbian will force a password change on first login — set something and note it.

```bash
ssh root@<rockpi4-ip>
```

Once in:
```bash
echo 1 > /etc/pair-id      # change 1 to the pair number (1–6)
echo 6 > /etc/pair-count
```

---

## Step 4 — Run install.sh

On **each board**, clone this repo and run the install script:

### RPi4

```bash
git clone https://github.com/hamslabs/whoToldYouThatYouWereNaked /opt/newsystem
cd /opt/newsystem/deploy/rpi4
sudo bash install.sh
```

### Rock Pi4

```bash
git clone https://github.com/hamslabs/whoToldYouThatYouWereNaked /opt/newsystem
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
