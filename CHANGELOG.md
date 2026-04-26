# Changelog

All notable changes to Claude Rescue are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project adheres to [Semantic Versioning](https://semver.org/).

## [0.2.1] - 2026-04-26

Cosmetic-only release. Rebrand the BIOS and UEFI boot menus with a
Claude Rescue visual identity instead of inheriting upstream archiso
branding.

### Added

- Custom BIOS boot splash at `overlay/syslinux/splash.png` —
  green-on-black CRT-phosphor wordmark with amber accents and a
  toolbox illustration. Rendered from the high-resolution master at
  `assets/boot-screen/splash-master.png` via the new
  `scripts/render-splash.sh` (run on demand; the build itself doesn't
  invoke ImageMagick).
- `overlay/efiboot/loader/loader.conf` — overrides upstream archiso's
  default with `timeout 10` (down from 15) and `console-mode max`
  (legible menus on HiDPI UEFI laptops).
- New "Boot menu rebrand" entry in `docs/decision-log.md` covering the
  asymmetric BIOS-vs-UEFI experience and the 640×480 / VBE mode
  trade-off.

### Changed

- `overlay/syslinux/archiso_head.cfg` — overrides upstream with the
  rebranded layout: no `MENU TITLE` (the splash already carries the
  title), VSHIFT/ROWS/HELPMSGROW tuned to fit the splash's reserved
  middle band, color palette shifted to green/amber to match.
- BIOS boot entries (`overlay/syslinux/archiso_sys-linux.cfg`,
  `overlay/syslinux/archiso_pxe-linux.cfg`) — labels changed from
  "Arch Linux install medium (...)" to "Boot Claude Rescue (...)".
- UEFI boot entry (`overlay/efiboot/loader/entries/01-archiso-linux.conf`)
  — same rebrand on the title.
- `docs/architecture.md` — new "Boot menu" section documenting the
  syslinux + systemd-boot setup and the GRUB removal.

### Removed

- `overlay/grub/` — GRUB isn't in the boot path (`profiledef.sh` only
  enables `bios.syslinux` and `uefi.systemd-boot`), so the directory
  was dead weight.
- The accessibility/speakup boot variant (BIOS `archspeech` label and
  UEFI `02-archiso-speech-linux.conf`). Upstream archiso ships a
  parallel speech-enabled entry on every boot path; we drop it for a
  cleaner single-entry rescue menu. `scripts/build-iso.sh` removes
  the upstream UEFI speech entry from the assembled profile (the
  syslinux side is handled by our overriding `archiso_sys-linux.cfg`
  not including the `archspeech` LABEL).

## [0.2.0] - 2026-04-26

The "ergonomics" release. Built on top of the v0.1.0 bootable foundation
to address four pain points found running M1 in the field: stale install
mechanism, no conversation persistence across reboots, no environmental
context for Claude itself, and friction during the build's OAuth step.

### Added

- **Native Claude Code installer** replaces npm-based install. Drops
  `nodejs` and `npm` from the shipped ISO entirely. The build hook now
  runs `curl -fsSL https://claude.ai/install.sh | bash` and
  dynamically writes the installed version into `/root/.claude.json`
  as `lastOnboardingVersion`, so the pre-baked onboarding-complete
  state stays in lockstep with whatever version the installer pulled.
- **Conversation persistence** across reboots when a `RESCUE_PERSIST`-
  labeled ext4 partition is present on the USB stick. New
  `persist.mount` systemd unit mounts that partition at `/persist`
  with graceful absence (`ConditionPathExists` + `nofail`); new
  `claude-persist.service` symlinks `/root/.claude/projects` →
  `/persist/claude/projects` only when the mount actually succeeded
  (gated by `BindsTo=` + `ConditionPathIsMountPoint=`). Works
  transparently with `claude --continue` after a reboot.
- **Self-context `/root/CLAUDE.md`** ships in the squashfs. Tells
  Claude it's running inside a read-only rescue environment, that
  `/mnt` is the target machine being repaired (not the rescue OS),
  where `/persist` lives, and what recovery tools are already on the
  box. Loaded automatically because the launcher invokes Claude from
  `cwd=/root`.
- **`/etc/profile.d/claude-env.sh`** — sets `DISABLE_AUTOUPDATER=1`
  (read-only squashfs makes auto-update pointless) and prepends
  `/root/.local/bin` to `PATH` (silences Claude's own runtime
  self-check).
- **Persistent test disk in `run-qemu-test.sh`**. Creates and attaches
  a reusable qcow2 labeled `RESCUE_PERSIST` (via guestfish if
  available, else `mkfs.ext4` on the raw image — both unprivileged,
  with runtime-failure fallback between them). Adds `--no-persist`
  flag for graceful-degradation testing.
- **`docs/build.md`** — new section on adding a `RESCUE_PERSIST`
  partition to a USB stick.
- **`docs/decision-log.md`** — entries for native installer choice,
  persistence brought forward from M5, attempted-and-reverted bypass
  mode, and self-context CLAUDE.md.

### Changed

- **`scripts/build-iso.sh`**: pre-flight resolves the user's preferred
  browser via `xdg-settings` before isolating `HOME` for `claude
  setup-token`. Without this, the OAuth flow falls back to KDE's
  Falkon (or whichever the system-wide `https` handler is) instead of
  the user's actual default browser. The Exec parser handles
  Flatpak/Snap multi-word launchers correctly and is constrained to
  the `[Desktop Entry]` section.
- **`scripts/build-iso.sh`**: post-build squashfs verification no
  longer false-negatives on successful builds. The previous `unsquashfs
  -l ... | grep -qE` was racy under `set -o pipefail` (grep closing
  stdin on first match → SIGPIPE to unsquashfs → 141 → pipefail
  reports the pipeline failed). Captures grep output to a variable
  instead.
- `nodejs` and `npm` removed from `overlay/packages.x86_64`.
- `docs/architecture.md` — Claude module and Persistence sections
  rewritten for the new architecture.
- `PLAN.md` — milestone table reflects M5 (Persistence) and M6 (Claude
  module) as DONE in v0.2.0; M2 stays pending.
- `README.md` — architecture table mentions persistence and the new
  installer.

### Attempted, reverted

- **`--dangerously-skip-permissions`** as the default launcher mode.
  Recent Claude Code refuses the flag when euid is 0 as a safety
  backstop, and the rescue ISO autologins as root unconditionally —
  the flag simply broke launch. Per-tool approval prompts are the
  accepted trade-off. The `bypassPermissionsModeAccepted: true` field
  in `.claude.json` is preserved (harmless when unused).

### Notes

- This release brings forward Persistence (M5) and the Claude module
  polish (M6) from the original milestone schedule. The Runtime
  skeleton (M2), Networking (M3), and Storage & repair (M4)
  milestones remain pending.

## [0.1.0] - 2026-04-09

Initial bootable foundation (M1). Tagged retroactively after the M1 PR
was merged.

### Added

- Bootable Arch Linux ISO built with archiso, layered on the upstream
  releng profile via `scripts/build-iso.sh` so upstream archiso fixes
  flow in automatically.
- Root autologin on tty1; zsh + dialog launcher (`/usr/local/bin/rescue`)
  with menu options for launching Claude Code, network setup
  (`nmtui`), and shell.
- NetworkManager as the only enabled networking unit; `dhcpcd`, `iwd`,
  and `wpa_supplicant` retained as diagnostic CLI tools (not enabled).
- Claude Code pre-installed via `customize_airootfs.sh` using `npm
  install -g @anthropic-ai/claude-code@2.1.97` (replaced in v0.2.0).
- Pre-baked `/root/.claude.json` with the matching
  `lastOnboardingVersion` so the first launch goes straight to the
  REPL.
- Optional embedded auth token via `claude setup-token` during build,
  written to gitignored `overlay/airootfs/etc/profile.d/claude-token.sh`.
- `scripts/run-qemu-test.sh` for boot testing in QEMU with KVM
  acceleration when available.
- Initial `docs/architecture.md`, `docs/decision-log.md`,
  `docs/build.md`, `README.md`, `PLAN.md`.

[0.2.1]: https://github.com/pizzimenti/claude-rescue/releases/tag/v0.2.1
[0.2.0]: https://github.com/pizzimenti/claude-rescue/releases/tag/v0.2.0
[0.1.0]: https://github.com/pizzimenti/claude-rescue/releases/tag/v0.1.0
