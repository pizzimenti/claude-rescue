#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"

ISO="$(ls -t "$OUT_DIR"/claude-rescue-*.iso 2>/dev/null | head -1)"
if [[ -z "$ISO" ]]; then
    echo "error: no ISO found in $OUT_DIR — run scripts/build-iso.sh first" >&2
    exit 1
fi

echo "==> Booting: $ISO"

# Check for KVM acceleration
ACCEL_OPTS=()
if [[ -w /dev/kvm ]]; then
    ACCEL_OPTS=(-enable-kvm -cpu host)
    echo "==> KVM acceleration enabled"
else
    echo "warn: /dev/kvm not available, running without acceleration"
fi

exec qemu-system-x86_64 \
    "${ACCEL_OPTS[@]}" \
    -m 2G \
    -smp 2 \
    -cdrom "$ISO" \
    -boot d \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -serial file:serial.log \
    -display gtk \
    "$@"
