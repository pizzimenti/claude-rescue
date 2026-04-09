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

```bash
sudo ./scripts/prepare-usb.sh /dev/sdX
```

Confirms before writing. Uses `dd` with 4M block size and `oflag=sync`.

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
