#!/bin/bash
# Flash RPi4 SD card and pre-configure for first boot.
# Run from the repo root on a Mac.

set -euo pipefail

DISK=disk5
IMAGE=images/rpi4-os-lite-arm64.img.xz
USER=gwart
PASSWORD=snowden

echo "=== Flashing RPi4 to /dev/$DISK ==="
diskutil unmountDisk /dev/$DISK
xzcat "$IMAGE" | sudo dd of=/dev/r${DISK} bs=4m status=progress
sync
echo "Flash complete."

echo "Waiting for bootfs to mount..."
sleep 3
diskutil mountDisk /dev/$DISK 2>/dev/null || true

BOOTFS=/Volumes/bootfs
if [ ! -d "$BOOTFS" ]; then
    echo "ERROR: /Volumes/bootfs not found. Try reinserting the SD card."
    exit 1
fi

touch "$BOOTFS/ssh"
HASH=$(echo "$PASSWORD" | openssl passwd -6 -stdin)
echo "$USER:$HASH" > "$BOOTFS/userconf"
echo "SSH enabled, user '$USER' configured."

diskutil eject /dev/$DISK
echo "Done. Insert SD card into RPi4."
