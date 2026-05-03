#!/usr/bin/env bash
# Stops the XTTS service. Idempotent: safe to call when already stopped.
# Note: this only unloads the LaunchAgent for the current session. The plist
# stays in place, so the service will come back at next login. To remove
# permanently, use ./scripts/uninstall.sh.

set -euo pipefail

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.xtts.tts.plist"
PLIST_TARGET="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
SERVICE_LABEL="com.xtts.tts"

ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*" >&2; }

if [ ! -f "$PLIST_TARGET" ]; then
    warn "$PLIST_TARGET not found. Nothing to stop."
    exit 0
fi

if ! launchctl list | grep -q "$SERVICE_LABEL"; then
    ok "already stopped"
    exit 0
fi

launchctl unload "$PLIST_TARGET"
ok "stopped"
