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

- Alpine: musl libc — was a hard blocker in M1 (Node.js / Claude Code's
  npm install), and remains a concern for the native Claude binary
  (Anthropic's prebuilt is glibc-linked).
- Debian Live: older kernels = worse laptop Wi-Fi
- Arch derivatives (Manjaro, EndeavourOS): delays packages, adds layers

## Milestones

| # | Name               | Status                              |
|---|--------------------|-------------------------------------|
| 1 | Foundation         | DONE (v0.1.0)                       |
| 2 | Runtime skeleton   | pending                             |
| 3 | Networking         | pending                             |
| 4 | Storage & repair   | pending                             |
| 5 | Persistence        | DONE in v0.2.0 (brought forward)    |
| 6 | Claude module      | DONE in v0.2.0 (brought forward)    |
| 7 | Polish & hardening | pending                             |

**Release history**

- **v0.1.0 (M1)** — bootable Arch ISO, autologin, NetworkManager, dialog
  launcher, Claude Code via npm.
- **v0.2.0** — native Claude installer (dropped npm/nodejs);
  `RESCUE_PERSIST` → `/persist` mount with graceful degradation; Claude
  conversation persistence via `/root/.claude/projects` symlink;
  self-context `/root/CLAUDE.md`; `DISABLE_AUTOUPDATER=1` and
  `/root/.local/bin` on PATH for Claude's runtime self-checks. (Bypass
  mode was attempted but reverted — recent Claude refuses
  `--dangerously-skip-permissions` under euid 0; see decision log.)

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
9. Write `README.md`, `docs/architecture.md`, `docs/decision-log.md`, `docs/build.md`
10. Create empty scaffold dirs for M2+ (runtime/, systemd/, tests/, examples/, .github/)
11. Build first ISO, verify boot in QEMU

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
5. MOTD displays the rescue banner; `rescue` launches the dialog menu
6. `claude` is present on `$PATH` (baked in at build time, not fetched at boot)
7. If a token was embedded, `Launch Claude Code` enters the REPL with no
   onboarding prompt; otherwise it prompts for `ANTHROPIC_API_KEY`
