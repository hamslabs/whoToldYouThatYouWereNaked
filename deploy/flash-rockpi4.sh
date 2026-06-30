#!/bin/bash
# Flash Rock Pi4 SD card.
# Run from the repo root on a Mac.

set -euo pipefail

DISK=disk5
IMAGE=images/armbian-rockpi4-plus-trixie-minimal.img.xz

echo "=== Flashing Rock Pi4 to /dev/$DISK ==="
diskutil unmountDisk /dev/$DISK
xzcat "$IMAGE" | sudo dd of=/dev/r${DISK} bs=4m status=progress
sync

diskutil eject /dev/$DISK
echo "Done. Insert SD card into Rock Pi4."
echo "First login: root / 1234 (Armbian will prompt for password change)"
echo "After password change it will ask to create a user — enter: gwart / snowden"
