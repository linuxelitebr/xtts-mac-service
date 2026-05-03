#!/usr/bin/env bash
# Removes Coqui XTTS from launchd and (optionally) reverts the patch in app.py.
#
# Usage:
#   ./scripts/uninstall.sh           # only unloads the service
#   ./scripts/uninstall.sh --revert  # also reverts the patch in app.py

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XTTS_DIR="${XTTS_DIR:-$HOME/pinokio/api/xtts.pinokio.git}"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.xtts.tts.plist"
PLIST_TARGET="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
PATCH_FILE="$REPO_DIR/patches/01-mps-and-port.patch"
SERVICE_LABEL="com.xtts.tts"

ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*" >&2; }

if [ -f "$PLIST_TARGET" ]; then
    if launchctl list 2>/dev/null | grep -F "$SERVICE_LABEL" >/dev/null; then
        launchctl unload "$PLIST_TARGET"
        ok "LaunchAgent unloaded"
    fi
    rm -f "$PLIST_TARGET"
    ok "$PLIST_TARGET removed"
else
    warn "$PLIST_TARGET does not exist"
fi

if [ "${1:-}" = "--revert" ]; then
    if [ ! -d "$XTTS_DIR" ]; then
        warn "XTTS_DIR does not exist ($XTTS_DIR), nothing to revert"
        exit 0
    fi
    cd "$XTTS_DIR"
    if patch -p1 --dry-run -R --silent < "$PATCH_FILE" >/dev/null 2>&1; then
        patch -p1 -R < "$PATCH_FILE"
        ok "patch reverted in $XTTS_DIR/app.py"
    else
        warn "patch is not currently applied (or app.py changed). Nothing to revert."
    fi
fi
