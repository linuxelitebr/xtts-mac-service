#!/usr/bin/env bash
# Quick health check for the XTTS service.

set -euo pipefail

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.xtts.tts.plist"
PLIST_TARGET="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
SERVICE_LABEL="com.xtts.tts"
PORT="${XTTS_PORT:-7861}"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
no()   { printf "  \033[31m✗\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*"; }

bold "Plist"
if [ -f "$PLIST_TARGET" ]; then
    ok "installed at $PLIST_TARGET"
else
    no "not installed (run ./scripts/install.sh)"
    exit 1
fi

bold "LaunchAgent"
line=$(launchctl list | awk -v lbl="$SERVICE_LABEL" '$3==lbl {print}')
if [ -z "$line" ]; then
    no "not loaded"
else
    pid=$(echo "$line"  | awk '{print $1}')
    code=$(echo "$line" | awk '{print $2}')
    if [ "$pid" = "-" ] || [ -z "$pid" ]; then
        warn "loaded but no PID. Last exit code: $code"
    else
        ok "loaded as PID $pid (last exit code: $code)"
    fi
fi

bold "HTTP on :$PORT"
if curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:$PORT/" 2>/dev/null; then
    ok "answering"
    echo "  UI:   http://127.0.0.1:$PORT"
else
    no "not answering"
fi
