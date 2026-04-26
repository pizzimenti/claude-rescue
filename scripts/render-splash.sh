#!/usr/bin/env bash
# render-splash.sh — regenerate overlay/syslinux/splash.png from the
# high-resolution master in assets/boot-screen/splash-master.png.
#
# This is a build-time author tool, NOT something invoked by build-iso.sh.
# We keep both the master and the rendered build asset checked in so the
# build itself doesn't depend on ImageMagick. Re-run this whenever the
# master changes (or when bumping to a higher VBE mode).
#
# Output: 640x480 PNG, the resolution vesamenu.c32 expects by default.
# vesamenu can use higher modes (800x600, 1024x768) via `MENU RESOLUTION`
# in archiso_head.cfg, but 640x480 is universally supported by every
# real-world BIOS and is the safe default for a rescue tool that needs
# to boot on whatever hardware shows up.
#
# Lanczos resampling preserves edge contrast better than the default
# downscaler — important when the source is a high-fidelity design with
# fine details (scanlines, small UI text) that will already lose
# resolution.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$REPO_ROOT/assets/boot-screen/splash-master.png"
OUTPUT="$REPO_ROOT/overlay/syslinux/splash.png"
TARGET_SIZE="640x480"

if [[ ! -f "$SOURCE" ]]; then
    echo "error: splash master not found at $SOURCE" >&2
    exit 1
fi

if ! command -v magick &>/dev/null; then
    echo "error: ImageMagick 'magick' command not found." >&2
    echo "       Install: sudo pacman -S imagemagick" >&2
    exit 1
fi

# Resize, force RGB color type, and explicitly set png:color-type=2
# (truecolor, no alpha) — vesamenu.c32 doesn't always render PNGs with
# alpha or unusual color modes correctly, so we normalize.
magick \
    "$SOURCE" \
    -resize "$TARGET_SIZE" \
    -filter Lanczos \
    -type TrueColor \
    -define png:color-type=2 \
    "$OUTPUT"

echo "==> Rendered $OUTPUT"
magick identify "$OUTPUT" | sed 's/^/    /'
