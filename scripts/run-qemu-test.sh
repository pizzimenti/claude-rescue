#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"

# Glob directly instead of parsing `ls` — handles spaces/newlines in paths
# safely and avoids the shellcheck SC2012 footgun. nullglob makes the array
# empty (rather than literal-glob) when there are no matches.
shopt -s nullglob
ISO_CANDIDATES=("$OUT_DIR"/claude-rescue-*.iso)
shopt -u nullglob
if (( ${#ISO_CANDIDATES[@]} == 0 )); then
    echo "error: no ISO found in $OUT_DIR — run scripts/build-iso.sh first" >&2
    exit 1
fi
# Pick the newest by mtime — same selection `ls -t | head -1` was doing.
ISO=""
for candidate in "${ISO_CANDIDATES[@]}"; do
    if [[ -z "$ISO" || "$candidate" -nt "$ISO" ]]; then
        ISO="$candidate"
    fi
done

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
