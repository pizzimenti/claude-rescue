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
