# Claude Rescue

A lightweight, bootable Linux recovery USB that gets broken machines online and launches
Claude Code for AI-assisted repair. A field-repair appliance, not a desktop distro.

## Quick start

```bash
# Build the ISO (requires root, archiso installed)
./scripts/build-iso.sh

# Test in QEMU
./scripts/run-qemu-test.sh
```

Write the resulting `out/claude-rescue-*.iso` to a USB stick with whatever
tool you prefer — `dd`, [Ventoy](https://www.ventoy.net/),
[balenaEtcher](https://etcher.balena.io/), Fedora Media Writer, Rufus,
etc. The image is a hybrid ISO. See [docs/build.md](docs/build.md) for
notes.

## Architecture

| Concern     | Choice                      |
|-------------|-----------------------------|
| Base distro | Arch Linux + archiso        |
| Launcher UX | bash + dialog (ncurses TUI) |
| Networking  | NetworkManager              |
| Persistence | Labeled ext4 (RESCUE_PERSIST) |
| Boot/login  | Root autologin → launcher   |
| Shell       | zsh + tmux                  |

See [docs/architecture.md](docs/architecture.md) for full details.

## Build requirements

- Arch Linux host
- `archiso` package
- `qemu` (for testing)
- Root access

## Docs

- [Architecture](docs/architecture.md)
- [Build guide](docs/build.md)
- [Decision log](docs/decision-log.md)
