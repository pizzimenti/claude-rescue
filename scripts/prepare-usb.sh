#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"

if [[ $EUID -ne 0 ]]; then
    echo "error: must run as root" >&2
    exec sudo "$0" "$@"
fi

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <device>  (e.g. /dev/sdb)"
    echo ""
    echo "Available block devices:"
    lsblk -d -o NAME,SIZE,MODEL
    exit 1
fi

DEVICE="$1"

if [[ ! -b "$DEVICE" ]]; then
    echo "error: $DEVICE is not a block device" >&2
    exit 1
fi

ISO="$(ls -t "$OUT_DIR"/claude-rescue-*.iso 2>/dev/null | head -1)"
if [[ -z "$ISO" ]]; then
    echo "error: no ISO found in $OUT_DIR — run scripts/build-iso.sh first" >&2
    exit 1
fi

echo "==> Target device: $DEVICE"
lsblk -d "$DEVICE"
echo ""
echo "WARNING: This will ERASE all data on $DEVICE"
read -r -p "Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }

echo "==> Writing $ISO to $DEVICE ..."
dd if="$ISO" of="$DEVICE" bs=4M status=progress oflag=sync
echo "==> Done. USB is ready."
