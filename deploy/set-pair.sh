#!/bin/bash
# Set pair ID and count for this board. Run as root on either board.
# Usage: bash set-pair.sh <pair-id> <pair-count>
#   pair-id:    number for this pair (1–6)
#   pair-count: total number of pairs being deployed

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <pair-id> <pair-count>"
    exit 1
fi

PAIR_ID=$1
PAIR_COUNT=$2

if ! [[ "$PAIR_ID" =~ ^[0-9]+$ ]] || ! [[ "$PAIR_COUNT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: both arguments must be integers"
    exit 1
fi

echo "$PAIR_ID" > /etc/pair-id
echo "$PAIR_COUNT" > /etc/pair-count
echo "pair-id=$PAIR_ID  pair-count=$PAIR_COUNT"
