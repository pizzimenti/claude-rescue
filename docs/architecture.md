# Architecture

## Overview

Claude Rescue is a bootable Arch Linux ISO built with archiso. It boots directly to a root
shell (no login prompt) and launches an ncurses repair menu backed by a suite of shell
modules.

## Boot sequence

1. BIOS/UEFI → GRUB/syslinux → Linux kernel + initramfs
2. systemd starts; getty@tty1 autologins as root
3. zsh sources `/etc/zsh/zshrc`, prints `/etc/motd`, then runs `/root/.zlogin`
4. `.zlogin` launches `/usr/local/bin/rescue` (the dialog-based menu)

## Components

### Launcher (`runtime/launcher/`)
ncurses TUI built with `dialog`. Presents repair workflows as menu items.
Shell fallback always available.

### Network (`runtime/network/`)
NetworkManager manages all interfaces. `nmtui` for interactive Wi-Fi setup.
`nmcli` for scripted use. Ethernet DHCP works automatically on boot.

### Storage & repair (`runtime/storage/`, `runtime/repair/`)
Wrappers around standard tools: `cryptsetup`, `lvm2`, `parted`, `btrfs-progs`,
`ddrescue`, `testdisk`, `smartmontools`.

### Persistence (`runtime/persistence/`)
Optional ext4 partition labeled `RESCUE_PERSIST`. If present, `/persist` is mounted
and used for logs, config, and Claude session state. Gracefully absent if not found.

### Claude module (`runtime/claude/`)
Claude Code is installed at ISO build time via `customize_airootfs.sh`
(pinned `@anthropic-ai/claude-code` version), so the `claude` binary is
present on `$PATH` immediately after boot — no network round-trip required
to launch the REPL. If credentials were embedded during the build, the
launcher drops straight into Claude Code; otherwise it prompts for
`ANTHROPIC_API_KEY`. Session state will be stored in `/persist/claude`
once the persistence layer lands (M2+).

## Filesystem layout (live)

```
/           squashfs (read-only, overlaid with tmpfs for writes)
/persist    ext4 on RESCUE_PERSIST partition (optional)
/mnt        mount point for target machine's filesystems
```
