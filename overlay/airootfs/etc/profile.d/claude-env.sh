# Claude Code runtime environment for the rescue ISO.
#
# The rescue root filesystem is a read-only squashfs with a tmpfs overlay
# for writes. Claude Code's native installer includes a background
# auto-updater that rewrites its own binary bundle on launch — pointless
# in this environment (updates would vanish on reboot) and noisy in logs.
# Disable it unconditionally.
export DISABLE_AUTOUPDATER=1

# Put /root/.local/bin on PATH. The native Claude installer drops its
# launcher at /root/.local/bin/claude, and although we also symlink
# /usr/local/bin/claude → /root/.local/bin/claude in customize_airootfs.sh
# (so `claude` resolves without any PATH changes), Claude's own runtime
# self-check complains on every launch that its install dir isn't on
# PATH. Quietest fix: just put it on PATH. Guarded against double-add
# so re-sourcing profile.d is idempotent.
case ":${PATH}:" in
    *:/root/.local/bin:*) ;;
    *) export PATH="/root/.local/bin:$PATH" ;;
esac
