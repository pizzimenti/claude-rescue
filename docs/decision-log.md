# Decision Log

## Base distro: Arch Linux + archiso

**Decision:** Use Arch Linux with the official archiso tooling.

**Rationale:**
- Freshest kernel and firmware — best support for modern laptop Wi-Fi and NVMe
- archiso is the official, well-maintained Arch live ISO builder
- Minimal base: only what we add ends up in the image
- Rolling release means no stale packages at build time

**Rejected:**
- Alpine: musl libc breaks Node.js / Claude Code
- Debian Live: older kernels = worse hardware support on recent laptops
- Arch derivatives (Manjaro, EndeavourOS): add package delays and extra layers

---

## Networking: NetworkManager

**Decision:** NetworkManager with nmcli/nmtui.

**Rationale:**
- Best laptop Wi-Fi support (handles WPA-Enterprise, hidden SSIDs, etc.)
- nmtui provides a usable interactive interface without X
- nmcli is scriptable from the repair modules
- Persists connection profiles to RESCUE_PERSIST when available

**Rejected:**
- systemd-networkd only: no interactive TUI, poor WPA support
- iwd only: simpler but less scriptable for the launcher

---

## Launcher UX: bash + dialog

**Decision:** ncurses TUI via `dialog` with plain bash modules.

**Rationale:**
- Works in any TTY on any terminal emulator
- No GUI/Wayland/X dependency
- Easy to extend: each workflow is a shell function
- Shell fallback is always one Ctrl-C away

---

## Persistence: ext4 labeled RESCUE_PERSIST

**Decision:** Optional ext4 partition with a fixed label.

**Rationale:**
- Simplest reliable approach; ext4 is universally supported
- Label-based detection avoids UUID fragility across machines
- Graceful degradation: everything works without it (logs go to tmpfs)

---

## Boot/login: root autologin

**Decision:** getty autologin as root, no password prompt.

**Rationale:**
- Recovery context requires root access to everything
- A password gate is friction with no benefit (physical access = game over anyway)
- Matches behavior of standard Arch ISO and other recovery tools

---

## Claude Code install: native installer, not npm (0.2.0)

**Decision:** Install Claude Code via `curl -fsSL https://claude.ai/install.sh
| bash` during `customize_airootfs.sh` instead of `npm install -g
@anthropic-ai/claude-code@X.Y.Z`. Drop `nodejs` and `npm` from the package list.

**Rationale:**
- The native installer is the supported install path going forward;
  Anthropic has indicated the npm package is not the primary distribution.
- The native install is a self-contained binary bundle — no Node.js runtime
  needed at runtime, which removes `nodejs` + `npm` (~100MB + transitive
  deps) from the shipped squashfs.
- One fewer language ecosystem to reason about inside the rescue image.

**Trade-off accepted — no version pinning:** the native installer always
pulls latest at build time. We compensate by reading `claude --version`
after install and writing it into `/root/.claude.json` as
`lastOnboardingVersion`, so the pre-baked onboarding-complete state stays
in lockstep automatically. Build is now self-healing against upstream
version bumps instead of requiring a manual pin update in two places.

**Trade-off accepted — auto-update on a read-only root:** the native
installer ships with a background auto-updater. We set
`DISABLE_AUTOUPDATER=1` in `/etc/profile.d/claude-env.sh` because updates
would only land in the tmpfs overlay and vanish at the next reboot —
pointless write churn and noisy logs.

**Trade-off accepted — install path off default PATH:** the native
installer puts the launcher at `/root/.local/bin/claude` and Claude's
own runtime self-check warns when its install dir isn't on PATH. The
build-time symlink to `/usr/local/bin/claude` resolves the binary for
the shell but doesn't satisfy that internal check, so we also prepend
`/root/.local/bin` to PATH in `/etc/profile.d/claude-env.sh`. Quietest
fix; both paths now point at the same launcher.

---

## Persistence wired in 0.2.0 (brought forward from M5)

**Decision:** Ship the full `RESCUE_PERSIST` mount infrastructure in the
0.2.0 release, rather than waiting for M5. Systemd `persist.mount` unit
mounts `/dev/disk/by-label/RESCUE_PERSIST` at `/persist` with
`ConditionPathExists` + `nofail` for graceful absence.

**Rationale:**
- The Claude-conversation-persistence ask in 0.2.0 needs a durable
  mountpoint somewhere. Building a Claude-specific mount mechanism and
  then ripping it out for a generic one in M5 is strictly more work than
  doing the generic one now.
- Once `/persist` exists, future features (connection profiles, logs,
  notes) reuse it with zero additional plumbing.
- The mount unit is <20 lines and the graceful-degradation semantics are
  well-understood, so the cost of landing it early is negligible.

`claude-persist.service` is a thin oneshot layered on top of
`persist.mount` — it symlinks `/root/.claude/projects` →
`/persist/claude/projects` only when `/persist` actually mounted. Only
the conversation-history subtree is redirected; the rest of
`/root/.claude/` (settings, cache, backups) stays ephemeral, and the
installer's binary bundle is outside `.claude/` entirely (lives at
`/root/.local/share/claude/versions/<version>`) so it's unaffected
either way.

---

## Permission bypass: attempted, reverted (0.2.0)

**Decision:** The rescue launcher invokes plain `claude`, NOT `claude
--dangerously-skip-permissions`. Per-tool approval prompts remain.

**Original intent:** we wanted bypass mode by default. Threat model didn't
justify the prompts (physical access to a running rescue USB already means
total system control via autologin-root); UX was the whole point of the
0.2.0 ergonomics bundle; and Claude has explicit `/root/CLAUDE.md` guidance
about `/` vs `/mnt/*` as a replacement guardrail.

**Why it didn't work:** recent Claude Code refuses
`--dangerously-skip-permissions` when euid is 0, as a safety backstop.
The rescue ISO autologins as root unconditionally — that's not negotiable
in a recovery context — so the flag simply breaks launch. Dropping the
flag is the only path that keeps Claude running at all.

**What we kept:** `bypassPermissionsModeAccepted: true` in the pre-baked
`/root/.claude.json` stays. It's harmless when unused, and preserved so a
user who manually `su`s to a non-root account and opts into bypass mode
there doesn't hit the first-run acceptance dialog.

**Follow-up options if we want this back:**
- Create a non-root rescue user and run the launcher as that user with
  sudo available for privileged operations. Biggest UX cost but proper
  fix.
- Watch upstream Claude Code for a way to opt into bypass mode as root
  (e.g. an explicit env var or config acknowledging the risk).
- Land additional in-process guardrails via `CLAUDE.md` so the
  per-prompt friction is the only thing separating the user from a
  mostly-autonomous repair loop — arguably where we are now.

---

## Self-context file: /root/CLAUDE.md (0.2.0)

**Decision:** Ship a `CLAUDE.md` at `/root/CLAUDE.md` explaining the
rescue environment to Claude: what it is, what `/mnt` vs `/` means, where
persistence lives, what recovery tools are already present, how to
approach destructive operations on a target disk.

**Rationale:**
- Without this, every rescue session starts with the user spending
  several minutes re-explaining a genuinely unusual setup (squashfs+tmpfs,
  target at /mnt, autologin-as-root, ephemeral network state).
- `CLAUDE.md` is Claude Code's documented project-local instructions
  mechanism, loaded automatically when Claude runs from the directory
  containing it.
- The launcher always invokes Claude with cwd=/root, so `/root/CLAUDE.md`
  loads reliably on the menu-launched path.

**Chose `/root/CLAUDE.md` over `/etc/claude-code/CLAUDE.md`:** the
`/etc/claude-code/` managed-policy location is mentioned in some Claude
docs but its loading semantics are less well-attested than the
project-local convention. The trade-off is that users who `cd /mnt/...`
and run claude directly (outside the launcher) will miss the context —
acceptable, because they can re-orient Claude manually, and arguably the
target machine's own CLAUDE.md (if any) should take precedence in that
context anyway.

---

## Boot menu rebrand (0.2.1)

**Decision:** Replace the upstream archiso boot-menu branding (Arch
Linux logo, "Arch Linux install medium" titles) with Claude Rescue
identity. Custom 640×480 splash PNG for syslinux/BIOS; rebranded entry
titles plus tighter `loader.conf` for systemd-boot/UEFI. Remove
`overlay/grub/` since GRUB isn't in the boot path.

**Rationale:**
- The boot menu is the first thing the user sees. Shipping with
  upstream Arch branding made the rescue ISO feel like a generic Arch
  install medium rather than a purpose-built tool — a small but real
  hit to "is this the right thing I just booted?" confidence.
- Removing dead `overlay/grub/` (verified unreferenced — `profiledef.sh`
  only enables `bios.syslinux` and `uefi.systemd-boot`) clarifies that
  GRUB isn't a maintained boot path here, so reviewers don't waste time
  reasoning about it.

**Asymmetry trade-off accepted:** syslinux supports a graphical splash
(via `vesamenu.c32` and a 640×480 PNG background); systemd-boot does
not — it's a plain text terminal with no banner mechanism. So BIOS
users get the full visual identity, UEFI users get rebranded entry
titles only. Building a parallel ASCII-art experience for systemd-boot
would have minimal payoff (UEFI boot is fast; most users barely see
the menu) and limited mechanism (no pre-menu output is supported).

**Pipeline:** the high-resolution master lives at
`assets/boot-screen/splash-master.png`; `scripts/render-splash.sh`
resizes it to the 640×480 target and writes
`overlay/syslinux/splash.png`, which is committed so the build itself
doesn't need ImageMagick. Re-run the script when the master changes.

**Why 640×480 and not higher:** vesamenu can use 800×600 / 1024×768
modes via `MENU RESOLUTION`, but 640×480 is the only VBE mode that's
universally supported on every BIOS we might encounter. This is a
rescue tool — it has to boot on whatever obscure or ancient hardware
the user pulls out of a closet — so we trade fidelity for compatibility.

**Color palette:** menu chrome (`MENU COLOR`) shifted to green/amber to
match the splash's phosphor aesthetic. The default vesamenu palette is
white-on-blue, which clashed visibly with the green splash background.
