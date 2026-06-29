#!/bin/bash
# RPi4 one-time setup. Run as root after booting Raspberry Pi OS Lite Bookworm.
# Prereqs: /etc/pair-id and /etc/pair-count exist.

set -euo pipefail

WIFI_SSID="gwart"
WIFI_PASSWORD="ImNotNaked"

PAIR_ID=$(cat /etc/pair-id)
PAIR_COUNT=$(cat /etc/pair-count)
RPI_IP="192.168.10.1${PAIR_ID}"
ROCK_IP="192.168.10.2${PAIR_ID}"
HOSTNAME="rpi4-${PAIR_ID}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== RPi4 install — pair ${PAIR_ID} ==="

# ── WiFi + Static IP via NetworkManager (Bookworm default) ───────────────────
if nmcli -g NAME con show | grep -qx "$WIFI_SSID"; then
    nmcli con mod "$WIFI_SSID" \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$WIFI_PASSWORD" \
        ipv4.method manual \
        ipv4.addresses "${RPI_IP}/24" \
        ipv4.gateway 192.168.10.1 \
        ipv4.dns 192.168.10.1
else
    nmcli con add type wifi \
        con-name "$WIFI_SSID" \
        ifname wlan0 \
        ssid "$WIFI_SSID" \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$WIFI_PASSWORD" \
        ipv4.method manual \
        ipv4.addresses "${RPI_IP}/24" \
        ipv4.gateway 192.168.10.1 \
        ipv4.dns 192.168.10.1
fi
nmcli con up "$WIFI_SSID" || echo "WiFi not in range yet — will connect automatically after reboot"

# ── Hostname ──────────────────────────────────────────────────────────────────
hostnamectl set-hostname "$HOSTNAME"

# ── Install dependencies ──────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq curl python3 socat

# ── Install mediamtx ─────────────────────────────────────────────────────────
MEDIAMTX_VERSION="v1.19.2"
ARCH="arm64"
TARBALL="mediamtx_${MEDIAMTX_VERSION}_linux_${ARCH}.tar.gz"
curl -fsSL "https://github.com/bluenviron/mediamtx/releases/download/${MEDIAMTX_VERSION}/${TARBALL}" \
    -o /tmp/mediamtx.tar.gz
tar -xzf /tmp/mediamtx.tar.gz -C /tmp mediamtx
install -m 755 /tmp/mediamtx /usr/local/bin/mediamtx
rm -f /tmp/mediamtx.tar.gz /tmp/mediamtx

# ── Install Tailscale ─────────────────────────────────────────────────────────
curl -fsSL https://tailscale.com/install.sh | sh

# ── Config files ──────────────────────────────────────────────────────────────
mkdir -p /etc/mediamtx
cp "${SCRIPT_DIR}/config/mediamtx.yml" /etc/mediamtx/mediamtx.yml

# ── Scripts ───────────────────────────────────────────────────────────────────
install -m 755 "${SCRIPT_DIR}/scripts/camera-start.sh"   /usr/local/bin/camera-start.sh
install -m 755 "${SCRIPT_DIR}/scripts/watchdog.sh"        /usr/local/bin/stream-watchdog.sh
install -m 755 "${SCRIPT_DIR}/scripts/status-server.py"   /usr/local/bin/status-server.py

# ── Substitute ROCK_IP placeholder in camera-start.sh ────────────────────────
# (camera-start.sh reads /etc/pair-id at runtime, no sed needed)

# ── systemd units ─────────────────────────────────────────────────────────────
cp "${SCRIPT_DIR}/systemd/"*.service /etc/systemd/system/
cp "${SCRIPT_DIR}/systemd/"*.timer   /etc/systemd/system/
systemctl daemon-reload
systemctl enable camera-stream.service
systemctl enable stream-watchdog.timer
systemctl enable status-server.service

echo ""
echo "=== Done. Next steps ==="
echo "1. Connect iPhone to router for internet access"
echo "2. Run: tailscale up --authkey=<REUSABLE_KEY> --hostname=${HOSTNAME} --advertise-tags=tag:newsstream"
echo "3. Reboot: sudo reboot"
