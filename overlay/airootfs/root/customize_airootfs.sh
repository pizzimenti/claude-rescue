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
# building a local pacman package, or pre-installing on the host and
# copying into the work tree before squashfs.
#
# Network: arch-chroot bind-mounts /etc/resolv.conf, so the curl installer
# can reach claude.ai from inside the chroot.

set -euo pipefail

# ---------------------------------------------------------------------------
# Install Claude Code via Anthropic's native installer.
#
# We previously used `npm install -g @anthropic-ai/claude-code@X.Y.Z` which
# let us pin a specific version and keep the pre-baked .claude.json's
# `lastOnboardingVersion` in lockstep. The native installer does NOT support
# version pinning — it always installs whatever is latest at build time.
# To keep the pre-baked onboarding state in sync without manual bumps, we
# read the installed version from `claude --version` after install and
# rewrite the JSON in place. This makes the build self-healing against
# upstream Claude version bumps.
#
# The native installer places a launcher symlink at $HOME/.local/bin/claude
# pointing at the actual binary bundle under
# $HOME/.local/share/claude/versions/<version>. That works fine for root
# on the running system, but $HOME/.local/bin is outside the default PATH
# for most contexts. We symlink /usr/local/bin/claude → the launcher so
# `claude` resolves on a stable system path unambiguously, and so the
# `unsquashfs | grep /claude$` check in build-iso.sh keeps matching.
# (We also prepend /root/.local/bin to PATH at runtime via
# /etc/profile.d/claude-env.sh — that quiets Claude's own self-check
# warning about its install dir not being on PATH; the symlink alone
# doesn't satisfy that check.)
# ---------------------------------------------------------------------------
echo "==> [customize_airootfs.sh] Installing Claude Code via native installer..."
curl -fsSL https://claude.ai/install.sh | bash

# Resolve the installed binary. $HOME is /root inside the chroot; the
# installer puts the launcher at $HOME/.local/bin/claude. We prefer an
# explicit path check over `command -v` because PATH inside the chroot
# may not include ~/.local/bin.
CLAUDE_BIN=""
for candidate in /root/.local/bin/claude /usr/local/bin/claude /usr/bin/claude; do
    if [[ -x "$candidate" ]]; then
        CLAUDE_BIN="$candidate"
        break
    fi
done

if [[ -z "$CLAUDE_BIN" ]]; then
    echo "  error: claude binary not found after running installer" >&2
    echo "  searched: /root/.local/bin/claude /usr/local/bin/claude /usr/bin/claude" >&2
    exit 1
fi

# Symlink into /usr/local/bin so the rescue launcher (and any shell user)
# finds claude on a stable path regardless of where the installer put it.
if [[ "$CLAUDE_BIN" != /usr/local/bin/claude ]]; then
    ln -sf "$CLAUDE_BIN" /usr/local/bin/claude
fi

# Query the actual installed version and write it into /root/.claude.json
# as `lastOnboardingVersion`. Must match what Claude reports, or the
# onboarding dialog will re-pop on first launch (exactly the regression
# the pre-baked JSON exists to prevent).
#
# `claude --version` output has varied across releases (e.g. bare "2.1.97",
# "2.1.97 (Claude Code)", etc.), so extract the first semver-shaped token
# rather than assuming a field position.
#
# We capture --version output to a variable first, then awk-extract from
# the variable. The seemingly-equivalent `claude --version | grep -oE
# ... | head -1` reintroduces the same SIGPIPE+pipefail race we fixed in
# build-iso.sh's post-build squashfs check: head -1 closes stdin on the
# first match -> grep gets SIGPIPE on its next write -> exits 141 ->
# pipefail propagates 141 as the substitution's status -> set -e kills
# the build. A future Claude release that prints multiple semver-like
# tokens would silently break ISO builds.
_version_output=$("$CLAUDE_BIN" --version 2>/dev/null || true)
CLAUDE_VERSION=$(awk 'match($0,/[0-9]+\.[0-9]+\.[0-9]+/){print substr($0,RSTART,RLENGTH);exit}' <<<"$_version_output")
if [[ -z "$CLAUDE_VERSION" ]]; then
    echo "  error: could not determine claude version from \`claude --version\`" >&2
    exit 1
fi

echo "==> [customize_airootfs.sh] Claude Code ${CLAUDE_VERSION} installed at ${CLAUDE_BIN}"
echo "==> [customize_airootfs.sh] Pinning .claude.json lastOnboardingVersion=${CLAUDE_VERSION}"

# Regenerate /root/.claude.json with the correct lastOnboardingVersion.
# We don't sed-edit the existing file because sed-substituting JSON values
# is fragile, and we don't have jq or python guaranteed in the base image.
# Since we own this file's entire structure, regenerating it is both
# simpler and more robust. Keep the fields in lockstep with the pre-baked
# version committed at overlay/airootfs/root/.claude.json.
cat > /root/.claude.json <<JSON
{
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "${CLAUDE_VERSION}",
  "bypassPermissionsModeAccepted": true,
  "projects": {
    "/root": {
      "hasTrustDialogAccepted": true,
      "hasClaudeMdExternalIncludesApproved": true,
      "hasClaudeMdExternalIncludesWarningShown": true
    }
  }
}
JSON
