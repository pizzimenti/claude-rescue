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
Optional ext4 partition labeled `RESCUE_PERSIST`. If present, mounted
automatically at `/persist` by the shipped `persist.mount` systemd unit
(`overlay/airootfs/etc/systemd/system/persist.mount`). The mount uses
`ConditionPathExists=/dev/disk/by-label/RESCUE_PERSIST` plus `nofail`, so
boot never blocks on a missing or damaged persistence partition. When the
partition is absent, `/persist` is a plain empty directory on tmpfs and
callers are expected to degrade gracefully.

Currently `/persist` is used for Claude Code conversation history (see
below). Future callers — NetworkManager connection profiles, repair logs,
user notes — will write under `/persist/<namespace>/`.

### Claude module (`runtime/claude/`)
Claude Code is installed at ISO build time via `customize_airootfs.sh`
using Anthropic's native installer (`curl -fsSL https://claude.ai/install.sh
| bash`) — the `@anthropic-ai/claude-code` npm package is no longer the
supported install path. The installer drops a self-contained binary at
`/root/.local/share/claude/versions/<version>` with a launcher symlink at
`/root/.local/bin/claude`. The build hook then symlinks
`/usr/local/bin/claude` → `/root/.local/bin/claude` so `claude` is on
`$PATH` unambiguously and so the post-build squashfs verification can
locate it under a stable system path. No Node.js runtime ships in the ISO.

The native installer does not support version pinning, so `customize_airootfs.sh`
reads the installed version from `claude --version` after install and writes
it into `/root/.claude.json` as `lastOnboardingVersion`. This keeps the
pre-baked onboarding-complete state in lockstep with whatever version the
installer pulled, so the first launch goes straight to the REPL instead of
re-prompting the onboarding flow.

`/etc/profile.d/claude-env.sh` does two small environment fixes for the
runtime: (1) `DISABLE_AUTOUPDATER=1` because the root filesystem is
read-only squashfs and any update would land in the tmpfs overlay and
vanish on reboot; (2) prepends `/root/.local/bin` to `PATH` so Claude's
own runtime self-check stops complaining that its install dir isn't on
PATH (the `/usr/local/bin/claude` symlink would resolve `claude` for the
shell, but Claude looks specifically for its install directory on PATH).

If credentials were embedded during the build, the launcher drops straight
into Claude Code; otherwise it prompts for `ANTHROPIC_API_KEY`. The
launcher invokes plain `claude` — we considered
`--dangerously-skip-permissions` (the rescue system is ephemeral root, so
per-tool approval prompts serve no real threat model) but recent Claude
Code refuses that flag when euid is 0, and the rescue ISO autologins as
root unconditionally, so the flag simply breaks launch. Per-tool prompts
are the accepted trade-off. The pre-baked `/root/.claude.json` still
carries `bypassPermissionsModeAccepted: true` (harmless when unused) so
that a user who manually drops to a non-root shell and opts in doesn't
hit the first-run acceptance dialog.

Conversation history persists across reboots when a `RESCUE_PERSIST`
partition is present: the `claude-persist.service` oneshot symlinks
`/root/.claude/projects` → `/persist/claude/projects` after `persist.mount`
succeeds. Only the `projects/` subtree is redirected — the rest of
`/root/.claude/` (settings, cache, backups) stays ephemeral, and the
installer's binary bundle lives entirely outside `.claude/` anyway.

Gating relies on two complementary systemd directives. `BindsTo=persist.mount`
ties the service's lifecycle to the mount: if the mount stops (or, more
importantly, was condition-skipped because there's no RESCUE_PERSIST
partition), this service is also skipped. We use `BindsTo=` rather than
the more obvious `Requires=` because per systemd.unit(5), a
condition-skipped unit is treated as "successfully" inactive for
`Requires=` purposes — a `Requires=` dependent runs anyway. `BindsTo=`
treats it as inactive and skips. As a belt-and-suspenders check the
service also has `ConditionPathIsMountPoint=/persist`, so it refuses to
run unless `/persist` is a real mountpoint (not a tmpfs directory). On
machines without a persistence partition, conversations are tmpfs-only.

A `CLAUDE.md` at `/root/CLAUDE.md` ships in the squashfs and is loaded
automatically as the project-local instructions file when the launcher
invokes Claude from the default `/root` cwd. It tells Claude what
environment it's in (rescue ISO, not a dev box), which paths matter
(`/mnt` = target, `/persist` = durable, everything else = tmpfs), and
what recovery tools are already on the box.

## Filesystem layout (live)

```
/           squashfs (read-only, overlaid with tmpfs for writes)
/persist    ext4 on RESCUE_PERSIST partition (optional)
/mnt        mount point for target machine's filesystems
```
