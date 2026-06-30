#!/bin/bash
# Rock Pi4 one-time setup. Run as root after booting Armbian Debian Trixie Minimal CLI.
# Prereqs: /etc/pair-id and /etc/pair-count exist.

set -euo pipefail

if ! command -v netplan &>/dev/null && [ ! -d /etc/netplan ]; then
    echo "ERROR: This doesn't look like an Armbian/netplan system. Are you on the right board?"
    exit 1
fi

WIFI_SSID="gwart"

PAIR_ID=$(cat /etc/pair-id)
PAIR_COUNT=$(cat /etc/pair-count)
ROCK_IP="192.168.10.2${PAIR_ID}"
HOSTNAME="rockpi4-${PAIR_ID}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Rock Pi4 install — pair ${PAIR_ID} ==="

# ── Passwordless sudo for gwart ───────────────────────────────────────────────
echo 'gwart ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/gwart
chmod 440 /etc/sudoers.d/gwart

# ── Hostname ──────────────────────────────────────────────────────────────────
hostnamectl set-hostname "$HOSTNAME"
grep -qxF "127.0.1.1 $HOSTNAME" /etc/hosts || echo "127.0.1.1 $HOSTNAME" >> /etc/hosts

# ── Install dependencies ──────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq python3 curl \
    gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-libav

# ── Install Tailscale ─────────────────────────────────────────────────────────
curl -fsSL https://tailscale.com/install.sh | sh

# ── Scripts ───────────────────────────────────────────────────────────────────
cp "${SCRIPT_DIR}/scripts/readiness-server.py" /usr/local/bin/readiness-server.py
cp "${SCRIPT_DIR}/scripts/display-start.sh"    /usr/local/bin/display-start.sh
cp "${SCRIPT_DIR}/scripts/watchdog.sh"         /usr/local/bin/display-watchdog.sh
chmod 755 /usr/local/bin/readiness-server.py /usr/local/bin/display-start.sh /usr/local/bin/display-watchdog.sh

# ── systemd units ─────────────────────────────────────────────────────────────
cp "${SCRIPT_DIR}/systemd/"*.service /etc/systemd/system/
cp "${SCRIPT_DIR}/systemd/"*.timer   /etc/systemd/system/
systemctl daemon-reload
systemctl enable readiness-server.service
systemctl enable display-stream.service
systemctl enable display-watchdog.timer

# ── WiFi + Static IP via netplan — written last so it doesn't disrupt install ─
WIFI_IFACE=$(ip link | grep -o 'wlan[0-9]' | head -1)
if [ -z "$WIFI_IFACE" ]; then
    echo "WARNING: No WiFi interface found — skipping netplan config"
else
    cat > /etc/netplan/01-wifi-static.yaml <<EOF
network:
  version: 2
  wifis:
    ${WIFI_IFACE}:
      dhcp4: false
      addresses: [${ROCK_IP}/24]
      nameservers:
        addresses: [192.168.10.1]
      routes:
        - to: default
          via: 192.168.10.1
      access-points:
        "${WIFI_SSID}": {}
EOF
    chmod 600 /etc/netplan/01-wifi-static.yaml
fi

echo ""
echo "=== Done. Next steps ==="
echo "1. Connect iPhone to router for internet access"
echo "2. Run: tailscale up --authkey=<REUSABLE_KEY> --hostname=${HOSTNAME} --advertise-tags=tag:newsstream"
echo "3. Reboot: sudo reboot"
