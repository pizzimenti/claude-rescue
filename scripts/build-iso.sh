#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY_DIR="$REPO_ROOT/overlay"
RELENG_DIR="/usr/share/archiso/configs/releng"
WORK_DIR="$REPO_ROOT/work"
OUT_DIR="$REPO_ROOT/out"
PROFILE_DIR="$WORK_DIR/profile"
# Token file lives in the overlay tree (gitignored). It gets cp -a'd into
# the assembled profile in phase 2 along with the rest of the overlay.
CLAUDE_TOKEN_FILE="$OVERLAY_DIR/airootfs/etc/profile.d/claude-token.sh"

# ---------------------------------------------------------------------------
# Phase 1: pre-flight as the invoking user (no sudo yet).
# We do the interactive Claude OAuth here, while the tty is still cleanly
# owned by the user. Running `claude setup-token` under `sudo -u` from a
# root parent wedges the tty, so we explicitly do this BEFORE elevating.
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo ""
    echo "  You can embed a long-lived Claude Code auth token in the ISO so Claude"
    echo "  launches without prompting for login on the rescue system."
    echo "  This will open a browser to authenticate and generate a 1-year token."
    echo "  The token will be embedded in the ISO — treat the resulting USB like"
    echo "  a password and do not share it."
    echo ""
    read -r -p "==> Pre-configure Claude Code credentials now? [Y/n] " SETUP_CREDS
    SETUP_CREDS="${SETUP_CREDS:-Y}"

    # Always clear any stale token file — a prior build may have embedded
    # one, and the user's current answer is the source of truth. If the
    # stale file was created by an older root-running script, we need sudo.
    if [[ -e "$CLAUDE_TOKEN_FILE" ]]; then
        rm -f "$CLAUDE_TOKEN_FILE" 2>/dev/null || sudo rm -f "$CLAUDE_TOKEN_FILE"
    fi

    if [[ "$SETUP_CREDS" =~ ^[Yy] ]]; then
        if ! command -v claude &>/dev/null; then
            echo ""
            echo "  warn: 'claude' is not installed. Install it first:"
            echo "    npm install -g @anthropic-ai/claude-code"
            echo "  then rebuild to embed credentials."
            echo ""
        else
            # Verify we can actually write the token file BEFORE running
            # setup-token — otherwise we burn a 1-year credential on a
            # write that fails. A prior root-running script version may
            # have left profile.d/ root-owned.
            TOKEN_DIR=$(dirname "$CLAUDE_TOKEN_FILE")
            mkdir -p "$TOKEN_DIR" 2>/dev/null || true
            if ! [[ -w "$TOKEN_DIR" ]]; then
                echo ""
                echo "  error: cannot write to $TOKEN_DIR (not user-writable)."
                echo "  A previous build may have left it root-owned. Fix with:"
                echo "    sudo chown -R \$USER:\$USER overlay/"
                echo "  then re-run this script."
                echo ""
                exit 1
            fi
            echo ""
            echo "  Launching 'claude setup-token' in an isolated HOME so it"
            echo "  performs a fresh browser OAuth (your normal login is untouched)."
            echo "  A browser window will open — authenticate, then return here."
            echo ""
            FRESH_HOME=$(mktemp -d)
            TOKEN_LOG=$(mktemp)
            # Run interactively on the real user's tty. tee captures the
            # printed token without hiding the URL/prompts from the user.
            HOME="$FRESH_HOME" claude setup-token 2>&1 | tee "$TOKEN_LOG"
            # Claude prints the token wrapped across multiple lines, followed
            # by a blank line and "Store this token securely...". We must
            # respect the blank-line boundary — naive whitespace stripping
            # would absorb the trailing prose into the token. awk: start
            # capturing at the line beginning with sk-ant-oat01-, join
            # continuation lines (stripping per-line whitespace), stop at
            # the first blank line.
            TOKEN=$(awk '
                /^sk-ant-oat01-/ { capturing=1 }
                capturing && NF==0 { exit }
                capturing { gsub(/[[:space:]]/, ""); printf "%s", $0 }
            ' "$TOKEN_LOG")
            rm -rf "$FRESH_HOME" "$TOKEN_LOG"
            TOKEN="${TOKEN//[[:space:]]/}"
            if [[ "$TOKEN" == sk-ant-oat01-* ]]; then
                mkdir -p "$(dirname "$CLAUDE_TOKEN_FILE")"
                echo "export CLAUDE_CODE_OAUTH_TOKEN=$TOKEN" > "$CLAUDE_TOKEN_FILE"
                chmod 600 "$CLAUDE_TOKEN_FILE"
                echo "==> Token embedded. Valid for 1 year."
            elif [[ -n "$TOKEN" ]]; then
                echo "  warn: Token format not recognised (expected sk-ant-oat01-...). Skipping."
            else
                echo "  Skipping credential embed."
            fi
        fi
    else
        echo ""
        echo "  When the rescue system boots, authenticate Claude by setting:"
        echo "    export ANTHROPIC_API_KEY=sk-ant-..."
        echo "  or provide credentials when prompted from within Claude Code."
        echo ""
    fi

    echo "==> Re-executing under sudo for mkarchiso..."
    exec sudo "$0" "$@"
fi

# ---------------------------------------------------------------------------
# Phase 2: as root. mkarchiso needs root for chroot/mount/squashfs.
# ---------------------------------------------------------------------------
cleanup() {
    # Unmount any lingering bind mounts from a failed build
    while IFS= read -r mp; do
        umount -l "$mp" 2>/dev/null || true
    done < <(awk '{print $2}' /proc/mounts | grep "^${WORK_DIR}" | sort -r)
    # Return ownership of build artifacts to the invoking user so they can
    # be inspected, moved, or deleted without sudo. Runs on every exit path
    # (success or failure) so partial builds aren't stranded as root.
    if [[ -n "${SUDO_USER:-}" ]]; then
        chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$WORK_DIR" "$OUT_DIR" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# mkarchiso uses per-step stamp files in WORK_DIR to skip already-completed
# steps. If a previous build was killed mid-run, those stamps cause a
# subsequent invocation to no-op ("Validating options... Done!") even though
# nothing was actually produced. Wipe and recreate for a clean build.
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR"
touch "$WORK_DIR/.noindex" "$OUT_DIR/.noindex"

EMBED_CREDS=n
if [[ -f "$CLAUDE_TOKEN_FILE" ]]; then
    EMBED_CREDS=y
fi

# ---------------------------------------------------------------------------
# Assemble the build profile.
#
# We do not vendor the upstream archiso releng profile in this repo. Instead
# we copy it fresh from /usr/share/archiso/configs/releng on every build and
# layer our overlay/ on top. This means:
#   - Bug fixes and new packages from upstream archiso flow in automatically
#     whenever the user runs `pacman -Syu archiso`.
#   - Our repo only tracks files we actually customised, which keeps diffs
#     and code reviews focused on intentional changes.
#
# Caveat: any file we ship in overlay/ is a full replacement, not a patch.
# If upstream releng modifies one of those files (packages.x86_64,
# profiledef.sh, pacman.conf, etc.), we will silently keep our older copy.
# When bumping the archiso package, re-diff our overlay against the new
# releng to catch drift.
# ---------------------------------------------------------------------------
if [[ ! -d "$RELENG_DIR" ]]; then
    echo "  error: $RELENG_DIR not found. Install the 'archiso' package:"
    echo "    sudo pacman -S archiso"
    exit 1
fi

echo "==> Assembling build profile (releng base + overlay)..."
rm -rf "$PROFILE_DIR"
# -f guards against any user/system alias of cp that adds -i, which would
# wedge the build at the overlay overwrite step waiting for prompts.
cp -af "$RELENG_DIR/." "$PROFILE_DIR"
cp -af "$OVERLAY_DIR/." "$PROFILE_DIR"
# We swap the kernel from `linux` to `linux-lts` in packages.x86_64, so the
# upstream linux.preset would reference a kernel that isn't installed and
# break mkinitcpio. Our linux-lts.preset replaces it.
rm -f "$PROFILE_DIR/airootfs/etc/mkinitcpio.d/linux.preset"

echo "==> Building claude-rescue ISO..."
mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

echo ""
echo "==> Build complete. ISO available in $OUT_DIR/"
ls -lh "$OUT_DIR"/*.iso 2>/dev/null || echo "No ISO found — check build output above."
echo ""
if [[ "$EMBED_CREDS" == y ]]; then
    echo "  *** SECURITY WARNING ***"
    echo "  This ISO contains your Claude Code credentials (valid 1 year)."
    echo "  Treat the ISO and any USB written from it like a password."
    echo "  Do not share it or leave it unattended."
else
    echo "  NOTE: Claude Code credentials were not embedded."
    echo "  When the rescue system boots, authenticate Claude by setting:"
    echo "    export ANTHROPIC_API_KEY=sk-ant-..."
    echo "  or provide credentials when prompted from within Claude Code."
fi
