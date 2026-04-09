# Claude Rescue — Implementation Plan

> Relaunch Claude Code from this directory to begin implementation.

## What this is

A lightweight, bootable Linux recovery USB that gets broken machines online and launches
Claude Code for AI-assisted repair. A field-repair appliance, not a desktop distro.

## Architecture (decided, do not re-litigate)

| Concern        | Choice                        | Reason                                              |
|----------------|-------------------------------|-----------------------------------------------------|
| Base distro    | Arch Linux + archiso          | Freshest kernel/firmware, official tooling, minimal |
| Launcher UX    | bash + dialog (ncurses TUI)   | Works in any TTY, modular actions, shell fallback   |
| Networking     | NetworkManager + nmcli/nmtui  | Best laptop Wi-Fi support, scriptable, persists     |
| Persistence    | Labeled ext4 (RESCUE_PERSIST) | Simple, reliable, graceful degradation w/o it       |
| Boot/login     | Root autologin → launcher     | Recovery needs root everywhere                      |
| Shell          | zsh + tmux                    | Better completion/prompting; session management     |

### Rejected alternatives

- Alpine: musl libc breaks Node.js / Claude Code
- Debian Live: older kernels = worse laptop Wi-Fi
- Arch derivatives (Manjaro, EndeavourOS): delays packages, adds layers

## Milestones

| # | Name               | Status  |
|---|--------------------|---------|
| 1 | Foundation         | NEXT    |
| 2 | Runtime skeleton   | pending |
| 3 | Networking         | pending |
| 4 | Storage & repair   | pending |
| 5 | Persistence        | pending |
| 6 | Claude module      | pending |
| 7 | Polish & hardening | pending |

## Milestone 1 tasks

1. `sudo pacman -S archiso` on host
2. `git init` this repo
3. Track only customisations in `overlay/`; assemble at build time by layering
   `overlay/` on top of a fresh copy of `/usr/share/archiso/configs/releng`
   (so upstream archiso fixes flow in automatically)
4. Customize `overlay/packages.x86_64` (recovery tools, networking, hardware inspection)
5. Customize `overlay/profiledef.sh` (label, hostname, branding)
6. Set up `overlay/airootfs/`:
   - `etc/hostname` → `claude-rescue`
   - `etc/locale.conf`
   - `etc/motd` (banner)
   - `etc/systemd/system/getty@tty1.service.d/autologin.conf`
   - `etc/zsh/zshrc` (prompt, history, completion)
   - `root/.zlogin` (placeholder launcher entry point)
7. Create `scripts/build-iso.sh`
8. Create `scripts/run-qemu-test.sh`
9. Create `scripts/prepare-usb.sh`
10. Write `README.md`, `docs/architecture.md`, `docs/decision-log.md`, `docs/build.md`
11. Create empty scaffold dirs for M2+ (runtime/, systemd/, tests/, examples/, .github/)
12. Build first ISO, verify boot in QEMU

## Target repo layout

```
claude-rescue/
├── PLAN.md                        ← you are here
├── README.md
├── docs/
│   ├── architecture.md
│   ├── decision-log.md
│   ├── build.md
│   ├── testing.md
│   ├── recovery-workflows.md
│   ├── persistence.md
│   ├── networking.md
│   └── claude-integration.md
├── overlay/                       ← layered on /usr/share/archiso/configs/releng at build time
│   ├── profiledef.sh              (only files we customise are tracked)
│   ├── packages.x86_64
│   ├── pacman.conf
│   ├── grub/
│   ├── efiboot/
│   ├── syslinux/
│   └── airootfs/
│       ├── etc/
│       │   ├── hostname
│       │   ├── motd
│       │   ├── mkinitcpio.d/linux-lts.preset
│       │   ├── zsh/zshrc
│       │   └── systemd/system/    (NetworkManager wants + networkd masks)
│       ├── usr/local/bin/rescue   (dialog launcher)
│       └── root/
│           ├── .zlogin
│           └── .claude.json       (pre-baked Claude Code onboarding state)
├── scripts/
│   ├── build-iso.sh
│   ├── run-qemu-test.sh
│   ├── prepare-usb.sh
│   └── validate-config.sh
├── runtime/
│   ├── launcher/
│   ├── network/
│   ├── storage/
│   ├── repair/
│   ├── persistence/
│   ├── claude/
│   ├── logging/
│   └── firstboot/
├── systemd/
├── tests/
│   ├── unit/
│   ├── integration/
│   └── smoke/
├── examples/
└── .github/
    └── workflows/
```

## Verification for Milestone 1

1. `scripts/build-iso.sh` produces `out/claude-rescue-*.iso`
2. `scripts/run-qemu-test.sh` boots the ISO in QEMU
3. Boots to root shell with no login prompt (autologin)
4. Recovery tools present: `cryptsetup`, `lvm2`, `nmcli`, `parted`, `btrfs-progs`, etc.
5. Placeholder banner displays in `.zlogin`, drops to zsh
