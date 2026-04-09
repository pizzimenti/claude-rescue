#!/usr/bin/env bash
# customize_airootfs.sh — runs ONCE inside the airootfs chroot during
# `mkarchiso`, immediately after pacstrap and before squashfs creation.
# mkarchiso deletes this file from the final image after running it, so
# nothing in here ships in the booted ISO.
#
# We use this hook to install Claude Code (which is not in the official
# Arch repos and so cannot be added via packages.x86_64) so the rescue
# ISO ships with it pre-installed and never needs network at runtime.
#
# This hook mechanism is marked deprecated in archiso but still works as
# of archiso 87. When archiso removes it we'll need to switch to either
# building a local pacman package from the npm tarball, or pre-installing
# on the host and copying into the work tree before squashfs.
#
# Network: arch-chroot bind-mounts /etc/resolv.conf, so npm install can
# reach the npm registry from inside the chroot.

set -euo pipefail

echo "==> [customize_airootfs.sh] Installing @anthropic-ai/claude-code globally..."
npm install -g @anthropic-ai/claude-code

# Verify the binary actually landed on PATH so the rescue launcher can
# rely on it without a runtime fallback path.
if ! command -v claude >/dev/null 2>&1; then
    echo "  error: claude binary not found on PATH after npm install -g" >&2
    exit 1
fi

echo "==> [customize_airootfs.sh] Claude Code installed at $(command -v claude)"
