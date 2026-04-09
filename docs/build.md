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
