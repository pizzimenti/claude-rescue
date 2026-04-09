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

# Walk the block-device tree from leaf to root and return the topmost
# ancestor of type 'disk'. Handles partitions, LVM, LUKS, and bare disks.
get_parent_disk() {
    lsblk -n -s -o NAME,TYPE "$1" 2>/dev/null | awk '$2 == "disk" { print $1 }' | tail -1
}

# Refuse to write to the disk hosting the currently-booted root filesystem.
# If we can't determine root's disk for some reason (exotic setups), bail —
# better to fail noisily than silently overwrite someone's working system.
ROOT_SOURCE="$(findmnt -n -o SOURCE /)"
ROOT_DISK="$(get_parent_disk "$ROOT_SOURCE")"
TARGET_DISK="$(get_parent_disk "$DEVICE")"

if [[ -z "$TARGET_DISK" ]]; then
    echo "error: could not resolve parent disk of $DEVICE" >&2
    exit 1
fi
if [[ -z "$ROOT_DISK" ]]; then
    echo "error: could not determine which disk hosts / (root source: $ROOT_SOURCE)" >&2
    echo "  Refusing to write blindly — verify manually and use dd directly if you're sure." >&2
    exit 1
fi
if [[ "$TARGET_DISK" == "$ROOT_DISK" ]]; then
    echo "error: $DEVICE is on /dev/$ROOT_DISK, which hosts the running root filesystem." >&2
    echo "  Refusing to overwrite the disk Linux is currently running from." >&2
    exit 1
fi

# Refuse if the target device or any of its partitions are mounted. dd
# would happily corrupt a mounted filesystem; force the user to unmount.
MOUNTED="$(lsblk -n -o MOUNTPOINTS "$DEVICE" 2>/dev/null | grep -v '^[[:space:]]*$' || true)"
if [[ -n "$MOUNTED" ]]; then
    echo "error: $DEVICE (or its partitions) has active mountpoints:" >&2
    echo "$MOUNTED" | sed 's/^/    /' >&2
    echo "  Unmount them before writing the image." >&2
    exit 1
fi

shopt -s nullglob
ISO_CANDIDATES=("$OUT_DIR"/claude-rescue-*.iso)
shopt -u nullglob
if (( ${#ISO_CANDIDATES[@]} == 0 )); then
    echo "error: no ISO found in $OUT_DIR — run scripts/build-iso.sh first" >&2
    exit 1
fi
# Newest by mtime
ISO=""
for candidate in "${ISO_CANDIDATES[@]}"; do
    if [[ -z "$ISO" || "$candidate" -nt "$ISO" ]]; then
        ISO="$candidate"
    fi
done

echo "==> Target device: $DEVICE (parent disk: /dev/$TARGET_DISK)"
lsblk -d "$DEVICE"
echo ""
echo "WARNING: This will ERASE all data on $DEVICE"
read -r -p "Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }

echo "==> Writing $ISO to $DEVICE ..."
dd if="$ISO" of="$DEVICE" bs=4M status=progress oflag=sync
echo "==> Done. USB is ready."
