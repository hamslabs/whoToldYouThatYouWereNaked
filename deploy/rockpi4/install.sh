#!/bin/bash
# Rock Pi4 one-time setup. Run as root after booting Armbian Debian Trixie Minimal CLI.
# Prereqs: /etc/pair-id and /etc/pair-count exist.

set -euo pipefail

WIFI_SSID="gwart"
WIFI_PASSWORD="ImNotNaked"

PAIR_ID=$(cat /etc/pair-id)
PAIR_COUNT=$(cat /etc/pair-count)
ROCK_IP="192.168.10.2${PAIR_ID}"
HOSTNAME="rockpi4-${PAIR_ID}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Rock Pi4 install — pair ${PAIR_ID} ==="

# ── WiFi + Static IP via netplan (Armbian default) ────────────────────────────
WIFI_IFACE=$(ip link | grep -o 'wlan[0-9]' | head -1)
if [ -z "$WIFI_IFACE" ]; then
    echo "ERROR: No WiFi interface found"
    exit 1
fi

# Remove any existing netplan configs to avoid conflicts
rm -f /etc/netplan/*.yaml

cat > /etc/netplan/01-static.yaml <<EOF
network:
  version: 2
  wifis:
    ${WIFI_IFACE}:
      dhcp4: false
      addresses: [${ROCK_IP}/24]
      gateway4: 192.168.10.1
      nameservers:
        addresses: [192.168.10.1]
      access-points:
        "${WIFI_SSID}":
          password: "${WIFI_PASSWORD}"
EOF
chmod 600 /etc/netplan/01-static.yaml
netplan apply

# ── Hostname ──────────────────────────────────────────────────────────────────
hostnamectl set-hostname "$HOSTNAME"

# ── Install dependencies ──────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq mpv python3 socat curl

# ── Install Tailscale ─────────────────────────────────────────────────────────
curl -fsSL https://tailscale.com/install.sh | sh

# ── Scripts ───────────────────────────────────────────────────────────────────
install -m 755 "${SCRIPT_DIR}/scripts/readiness-server.py" /usr/local/bin/readiness-server.py
install -m 755 "${SCRIPT_DIR}/scripts/display-start.sh"    /usr/local/bin/display-start.sh
install -m 755 "${SCRIPT_DIR}/scripts/watchdog.sh"         /usr/local/bin/display-watchdog.sh

# ── systemd units ─────────────────────────────────────────────────────────────
cp "${SCRIPT_DIR}/systemd/"*.service /etc/systemd/system/
cp "${SCRIPT_DIR}/systemd/"*.timer   /etc/systemd/system/
systemctl daemon-reload
systemctl enable readiness-server.service
systemctl enable display-stream.service
systemctl enable display-watchdog.timer

echo ""
echo "=== Done. Next steps ==="
echo "1. Connect iPhone to router for internet access"
echo "2. Run: tailscale up --authkey=<REUSABLE_KEY> --hostname=${HOSTNAME} --advertise-tags=tag:newsstream"
echo "3. Reboot: sudo reboot"
