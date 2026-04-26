#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"
# Persistent test disk — reused across runs so we can validate that Claude
# conversations and other /persist state actually survive reboots. Stored
# in out/ because that directory is already gitignored and cleaned with
# other build artifacts.
PERSIST_IMG="$OUT_DIR/rescue-persist.qcow2"
PERSIST_SIZE="256M"

USE_PERSIST=1
QEMU_EXTRA_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --no-persist)
            USE_PERSIST=0
            ;;
        *)
            QEMU_EXTRA_ARGS+=("$arg")
            ;;
    esac
done

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

# ---------------------------------------------------------------------------
# Create the persistent test disk on first run.
#
# Goal: produce a disk image that exposes /dev/disk/by-label/RESCUE_PERSIST
# inside the guest, which is what persist.mount looks for. Two paths,
# both unprivileged:
#
#   1. guestfish (libguestfs) — preferred when available. Builds a real
#      partition table + ext4 filesystem on /dev/sda1 with the label set
#      via mkfs-opts. Mirrors what a USB stick would look like.
#   2. mkfs.ext4 directly on the raw image — bare ext4, no partition
#      table. udev still exposes the label via /dev/disk/by-label/, so
#      persist.mount still resolves correctly. Simpler, and ext4 / e2fsprogs
#      is essentially universal so this path almost always works.
#
# Neither path needs sudo. First run creates the disk, subsequent runs
# reuse it. Delete out/rescue-persist.qcow2 to start from a clean
# persistence state.
# ---------------------------------------------------------------------------
PERSIST_DEVICE_ARGS=()
if (( USE_PERSIST == 1 )); then
    if [[ ! -f "$PERSIST_IMG" ]]; then
        echo "==> Creating persistent test disk at $PERSIST_IMG ($PERSIST_SIZE)..."
        if ! command -v qemu-img &>/dev/null; then
            echo "  error: qemu-img not found (install 'qemu-img' or 'qemu-full')" >&2
            exit 1
        fi
        qemu-img create -f raw "$PERSIST_IMG.raw" "$PERSIST_SIZE" >/dev/null

        if command -v guestfish &>/dev/null; then
            # Unprivileged path via libguestfs. `part-disk` creates one
            # partition spanning the disk, `mkfs-opts` passes the label to
            # mke2fs so blkid reports RESCUE_PERSIST.
            guestfish --rw -a "$PERSIST_IMG.raw" <<'GUESTFISH'
run
part-disk /dev/sda mbr
mkfs-opts ext4 /dev/sda1 blocksize:4096 label:RESCUE_PERSIST
GUESTFISH
        elif command -v mkfs.ext4 &>/dev/null; then
            # Fall back to mkfs.ext4 directly on the raw image, no
            # partition table. This still produces a labeled filesystem
            # that blkid/udev exposes via /dev/disk/by-label, and QEMU
            # presents the whole "disk" as a single filesystem. Simpler
            # and needs no root.
            mkfs.ext4 -q -L RESCUE_PERSIST "$PERSIST_IMG.raw"
        else
            echo "  error: need either 'guestfish' (libguestfs) or 'mkfs.ext4'" >&2
            echo "         to initialize the persist disk. Install one of:" >&2
            echo "           sudo pacman -S libguestfs" >&2
            echo "           sudo pacman -S e2fsprogs   # usually already present" >&2
            exit 1
        fi

        qemu-img convert -f raw -O qcow2 "$PERSIST_IMG.raw" "$PERSIST_IMG"
        rm -f "$PERSIST_IMG.raw"
        echo "==> Persistent disk created. Delete $PERSIST_IMG to reset state."
    else
        echo "==> Reusing persistent disk: $PERSIST_IMG"
    fi
    PERSIST_DEVICE_ARGS=(
        -drive "file=$PERSIST_IMG,if=virtio,format=qcow2"
    )
else
    echo "==> --no-persist: booting without RESCUE_PERSIST disk (graceful-degradation test)"
fi

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
    "${PERSIST_DEVICE_ARGS[@]}" \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -serial "file:$OUT_DIR/serial.log" \
    -display gtk \
    "${QEMU_EXTRA_ARGS[@]}"
