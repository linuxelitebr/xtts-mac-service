#!/usr/bin/env bash
# Brings the XTTS service up and waits until it answers on the port.
# Idempotent: if it's already up, returns 0 immediately. Safe for hooks
# and batch jobs that need the service alive before they hit the API.
#
# Env:
#   XTTS_PORT       port to check (default 7861)
#   WAIT_TIMEOUT    seconds to wait for HTTP after starting (default 120)
#   QUIET           if set to 1, only prints on error
#
# Exit codes:
#   0  service is up
#   1  service was not installed (no plist)
#   2  service was started but did not answer in WAIT_TIMEOUT seconds

set -euo pipefail

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.xtts.tts.plist"
PLIST_TARGET="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
SERVICE_LABEL="com.xtts.tts"
PORT="${XTTS_PORT:-7861}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"
QUIET="${QUIET:-0}"

say()  { [ "$QUIET" = "1" ] || printf "%s\n" "$*"; }
ok()   { [ "$QUIET" = "1" ] || printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*" >&2; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*" >&2; }

http_up() { curl -fsS -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/" 2>/dev/null; }
is_loaded() { launchctl list | grep -q "$SERVICE_LABEL"; }
has_pid() {
    local pid
    pid=$(launchctl list | awk -v lbl="$SERVICE_LABEL" '$3==lbl {print $1}')
    [ -n "$pid" ] && [ "$pid" != "-" ]
}

if http_up; then
    ok "already up on :$PORT"
    exit 0
fi

if [ ! -f "$PLIST_TARGET" ]; then
    fail "$PLIST_TARGET not found. Run ./scripts/install.sh first."
    exit 1
fi

if ! is_loaded; then
    say "Loading LaunchAgent..."
    launchctl load -w "$PLIST_TARGET"
    ok "loaded"
fi

if ! has_pid; then
    say "Kickstarting service..."
    launchctl kickstart "gui/$(id -u)/$SERVICE_LABEL" >/dev/null 2>&1 || true
fi

say "Waiting up to ${WAIT_TIMEOUT}s for HTTP on :$PORT..."
for i in $(seq 1 "$WAIT_TIMEOUT"); do
    if http_up; then
        ok "up on :$PORT (after ${i}s)"
        exit 0
    fi
    sleep 1
done

fail "Service did not answer within ${WAIT_TIMEOUT}s. Check logs/xtts.err.log."
exit 2
