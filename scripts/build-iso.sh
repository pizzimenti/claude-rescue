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
            echo "  warn: 'claude' is not installed on this host. Install it first:"
            echo "    curl -fsSL https://claude.ai/install.sh | bash"
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
            # Make sure the temp files (one of which holds the raw token
            # text) are removed even if the user Ctrl+Cs in the middle of
            # the OAuth flow. EXIT does NOT fire across `exec sudo` later,
            # so we also clean up explicitly before elevating.
            _phase1_cleanup() {
                rm -rf "${FRESH_HOME:-}" "${TOKEN_LOG:-}" 2>/dev/null || true
            }
            trap _phase1_cleanup EXIT INT TERM HUP
            # Resolve the user's preferred browser NOW, while HOME still
            # points at their real config. Without this, `claude setup-token`
            # runs with HOME=$FRESH_HOME (empty), its OAuth helper calls
            # xdg-open, and xdg-open can't find ~/.config/mimeapps.list —
            # so it falls back to the system-wide https handler. On KDE
            # that's Falkon, not Chrome/Firefox/whatever you actually use.
            # Fix: export $BROWSER explicitly. xdg-open (and Claude) honor
            # $BROWSER before touching the mime database, so the isolated
            # HOME no longer leaks into browser selection.
            if [[ -z "${BROWSER:-}" ]] && command -v xdg-settings &>/dev/null; then
                _default_desktop=$(xdg-settings get default-web-browser 2>/dev/null || true)
                for _appdir in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications; do
                    _appfile="$_appdir/$_default_desktop"
                    if [[ -n "$_default_desktop" && -f "$_appfile" ]]; then
                        # Parse the Exec= line per the Desktop Entry
                        # Specification: strip the "Exec=" prefix, drop
                        # field codes (%f %F %u %U %d %D %n %N %i %c %k
                        # %v %m), collapse whitespace.
                        #
                        # We intentionally keep the FULL command (not just
                        # the first token), because Flatpak/Snap browser
                        # entries look like:
                        #   Exec=/usr/bin/flatpak run --branch=stable \
                        #        --command=firefox org.mozilla.firefox %U
                        # Truncating to `flatpak` alone makes BROWSER
                        # unrunnable. xdg-open honors multi-word
                        # $BROWSER values via shell word-splitting.
                        # Constrain to [Desktop Entry] section: per the
                        # Desktop Entry Specification, .desktop files can
                        # contain [Desktop Action *] subsections (right-
                        # click menu items like "New Window") that each
                        # have their own Exec=. Browsers ship [Desktop
                        # Entry] first by convention so the bug rarely
                        # bites, but constraining the match is cheap
                        # insurance. Also convert literal %% to % per spec.
                        _exec=$(awk '
                            /^\[/ { in_entry = ($0 == "[Desktop Entry]") }
                            in_entry && /^Exec=/ {
                                sub(/^Exec=/, "")
                                gsub(/%[a-zA-Z]/, "")
                                gsub(/%%/, "%")
                                gsub(/[[:space:]]+/, " ")
                                sub(/^[[:space:]]+/, "")
                                sub(/[[:space:]]+$/, "")
                                print
                                exit
                            }
                        ' "$_appfile")
                        # Verify only the first word is a real executable;
                        # the rest is arguments and doesn't need to be on
                        # PATH.
                        _first=${_exec%% *}
                        if [[ -n "$_first" ]] && command -v "$_first" &>/dev/null; then
                            export BROWSER="$_exec"
                            break
                        fi
                    fi
                done
                unset _default_desktop _appdir _appfile _exec _first
            fi
            if [[ -n "${BROWSER:-}" ]]; then
                echo "  Using browser: $BROWSER"
            else
                echo "  warn: could not resolve a default browser; claude setup-token"
                echo "        will fall back to the system default (which on KDE is"
                echo "        often Falkon). Set \$BROWSER in your shell if you want"
                echo "        a specific one."
            fi
            # Run interactively on the real user's tty. tee captures the
            # printed token without hiding the URL/prompts from the user.
            # `|| true` keeps a setup-token failure (network down, browser
            # not launching, user aborts the OAuth flow) from killing the
            # whole build via `set -e` — token-embed is optional.
            HOME="$FRESH_HOME" claude setup-token 2>&1 | tee "$TOKEN_LOG" || true
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
            ' "$TOKEN_LOG" 2>/dev/null || true)
            # Eager cleanup — don't let the raw token sit in /tmp for the
            # rest of the build, and don't leak it past the sudo boundary.
            _phase1_cleanup
            trap - EXIT INT TERM HUP
            TOKEN="${TOKEN//[[:space:]]/}"
            if [[ "$TOKEN" == sk-ant-oat01-* ]]; then
                mkdir -p "$(dirname "$CLAUDE_TOKEN_FILE")"
                # Create the token file restricted from the first write.
                # `echo > file; chmod 600` leaves a ~microsecond window where
                # the file exists at mode 0644 (default umask 022) — long
                # enough that another local user racing `cat` could grab a
                # 1-year credential. umask 077 in a subshell makes the
                # initial creation 0600 atomically.
                (
                    umask 077
                    printf 'export CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$TOKEN" > "$CLAUDE_TOKEN_FILE"
                )
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
unmount_workdir() {
    # Unmount any lingering bind mounts under WORK_DIR from a failed build.
    # We do the prefix match in awk (not `grep "^$WORK_DIR"`) so that regex
    # metacharacters in the path — dots, plusses, brackets — are treated
    # as literals. The trailing slash on the prefix prevents matching a
    # sibling directory whose name happens to start with WORK_DIR.
    while IFS= read -r mp; do
        umount -l "$mp" 2>/dev/null || true
    done < <(awk -v wd="${WORK_DIR}/" 'index($2, wd) == 1 { print $2 }' /proc/mounts | sort -r)
}

cleanup() {
    unmount_workdir
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
#
# Critical: unmount any stale bind mounts BEFORE the recursive remove.
# A previous mkarchiso run that died mid-build can leave proc/sys/dev bind
# mounts live under $WORK_DIR; without this, `rm -rf` would walk into them
# and start deleting from the host's /proc, /sys, /dev. The EXIT trap alone
# is not enough — it only fires when this script exits, not before the wipe.
unmount_workdir
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

# ---------------------------------------------------------------------------
# Post-build sanity check: confirm the claude binary actually landed inside
# the assembled airootfs squashfs.
#
# Why this exists: we install claude via the deprecated `customize_airootfs.sh`
# hook (see overlay/airootfs/root/customize_airootfs.sh). If a future archiso
# release silently stops calling that hook, mkarchiso will still exit 0 and
# produce an ISO — but the ISO will boot to a launcher that errors out at
# runtime saying claude is missing. We'd rather fail loudly here at build
# time than ship a broken rescue image.
#
# unsquashfs is part of squashfs-tools, which is a hard dependency of archiso,
# so it is guaranteed to be present whenever this script can run.
# ---------------------------------------------------------------------------
echo "==> Verifying claude binary is present in airootfs squashfs..."
SQUASHFS=$(find "$WORK_DIR" -type f -name 'airootfs.sfs' 2>/dev/null | head -1)
if [[ -z "$SQUASHFS" ]]; then
    echo "  error: airootfs.sfs not found under $WORK_DIR after mkarchiso." >&2
    echo "         archiso may have changed its work-tree layout — update this check." >&2
    exit 1
fi
# Capture grep output to a variable instead of piping to `grep -qE`.
# Why: under `set -o pipefail`, `unsquashfs -l | grep -q` is a race —
# grep closes its stdin on the first match, unsquashfs (which streams
# ~5000 paths) gets SIGPIPE on its next write and exits 141, and
# pipefail reports that 141 as the pipeline status. The `if !` then
# fires the error branch on a successful match. The variable capture
# drains unsquashfs fully, and the pipeline's exit status is just
# grep's (0 = match, 1 = no match, coerced to 0 by `|| true` so the
# outer `set -e` stays happy).
CLAUDE_PATHS=$(unsquashfs -l "$SQUASHFS" 2>/dev/null | grep -E '/(usr/bin|usr/local/bin)/claude$' || true)
if [[ -z "$CLAUDE_PATHS" ]]; then
    echo "  error: claude binary not found inside $SQUASHFS." >&2
    echo "         Either the customize_airootfs.sh hook did not run (archiso may" >&2
    echo "         have removed the deprecated mechanism), or the native installer" >&2
    echo "         (curl https://claude.ai/install.sh | bash) failed inside the" >&2
    echo "         chroot. Check the mkarchiso output above." >&2
    exit 1
fi
echo "==> claude binary present in squashfs."

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
