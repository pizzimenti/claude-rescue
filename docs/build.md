# Build Guide

## Prerequisites

- Arch Linux host (native or in a VM/container)
- `archiso` package: `sudo pacman -S archiso`
- `qemu` for testing: `sudo pacman -S qemu-full`
- Root access for `mkarchiso` and USB writing

## Building the ISO

```bash
./scripts/build-iso.sh
```

Output lands in `out/claude-rescue-YYYY.MM.DD.iso`.
Build artifacts go in `work/` (large; excluded from git).

## Testing in QEMU

```bash
./scripts/run-qemu-test.sh
```

Boots the most recent ISO from `out/`. Requires `qemu-system-x86_64`.
KVM acceleration is used automatically if `/dev/kvm` is available.

Terminal: curses mode (no GUI window needed). Exit with `Ctrl-A X`.

## Writing to USB

The ISO is a hybrid image — write it to a USB stick with whichever tool
you already trust. A few options:

- `sudo dd if=out/claude-rescue-*.iso of=/dev/sdX bs=4M status=progress conv=fsync`
- [Ventoy](https://www.ventoy.net/) (drop the `.iso` onto a Ventoy USB)
- [balenaEtcher](https://etcher.balena.io/) (cross-platform GUI)
- [Fedora Media Writer](https://fedoraproject.org/workstation/download), Rufus, etc.

Be sure `/dev/sdX` is the correct whole-disk device and not a partition.

## Adding a persistence partition (RESCUE_PERSIST)

The rescue system mounts any ext4 partition labeled `RESCUE_PERSIST` at
`/persist` and uses it to store durable state — most notably, Claude
Code's conversation history, so repair sessions resume across reboots.
Without a `RESCUE_PERSIST` partition the system still boots and Claude
still runs; conversations just live on tmpfs and are lost at the next
reboot.

The simplest way to add persistence, assuming you've already written the
ISO to a USB stick with `dd` or a similar tool, is to create a second
partition in the free space at the end of the stick:

```bash
# Identify the stick (example: /dev/sdX — replace with yours)
lsblk

# Add a new partition after the ISO. On a dd-written hybrid ISO the
# partition table has two small partitions already; add a third one.
sudo parted /dev/sdX mkpart primary ext4 100% 100%   # adjust start as needed
# (Or use gdisk / cfdisk interactively — pick whatever you're comfortable with.)

# Format and label
sudo mkfs.ext4 -L RESCUE_PERSIST /dev/sdX3

# Verify
sudo blkid /dev/sdX3
# → /dev/sdX3: LABEL="RESCUE_PERSIST" TYPE="ext4" ...
```

Ventoy users can either create the partition on the Ventoy stick's free
space, or format a separate stick as a single ext4 partition labeled
`RESCUE_PERSIST` and plug both in.

On the next boot of the rescue ISO, `mountpoint /persist` should report
success and conversation history will begin accumulating under
`/persist/claude/projects/`.

## Clean rebuild

```bash
sudo rm -rf work/
./scripts/build-iso.sh
```

## Troubleshooting

**`mkarchiso: command not found`** — install archiso: `sudo pacman -S archiso`

**`/dev/kvm` permission denied** — add yourself to the `kvm` group:
`sudo usermod -aG kvm $USER` then re-login

**Build fails with pacman key errors** — initialize pacman keyring:
`sudo pacman-key --init && sudo pacman-key --populate`
