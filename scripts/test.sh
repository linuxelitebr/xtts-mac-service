#!/usr/bin/env bash
# Test battery for the XTTS service.
#
# Verifies:
#   1. Service is loaded in launchd
#   2. Logs show "Compute device: mps" and "Model loaded to MPS"
#   3. HTTP answers on the port
#   4. End to end voice cloning through the API works

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XTTS_DIR="${XTTS_DIR:-$HOME/pinokio/api/xtts.pinokio.git}"
VENV_PYTHON="${VENV_PYTHON:-$XTTS_DIR/env/bin/python}"
LOG_DIR="${LOG_DIR:-$REPO_DIR/logs}"
PORT="${XTTS_PORT:-7861}"
SERVICE_LABEL="com.xtts.tts"
REF_AUDIO="${XTTS_REF_AUDIO:-$XTTS_DIR/examples/female.wav}"

ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*" >&2; FAILED=1; }
bold() { printf "\033[1m%s\033[0m\n" "$*"; }

FAILED=0

bold "1) Service in launchd"
if launchctl list | grep -q "$SERVICE_LABEL"; then
    pid=$(launchctl list | awk -v lbl="$SERVICE_LABEL" '$3==lbl {print $1}')
    if [ "$pid" = "-" ] || [ -z "$pid" ]; then
        fail "label $SERVICE_LABEL exists but no PID (process crashed?)"
    else
        ok "running as PID $pid"
    fi
else
    fail "$SERVICE_LABEL is not loaded (run ./scripts/install.sh)"
fi

bold "2) Logs show GPU MPS"
if [ -f "$LOG_DIR/xtts.out.log" ]; then
    if grep -q "Compute device: mps" "$LOG_DIR/xtts.out.log"; then
        ok "Compute device: mps"
    else
        fail "log is missing 'Compute device: mps'. Might be running on CPU."
    fi
    if grep -q "Model loaded to MPS" "$LOG_DIR/xtts.out.log"; then
        ok "Model loaded to MPS"
    else
        fail "log is missing 'Model loaded to MPS'"
    fi
else
    fail "log $LOG_DIR/xtts.out.log does not exist yet"
fi

bold "3) HTTP answers on :$PORT"
if curl -fsS -o /dev/null --max-time 5 "http://127.0.0.1:$PORT/"; then
    ok "GET / returned 200"
else
    fail "GET http://127.0.0.1:$PORT/ failed"
fi

bold "4) E2E: voice cloning through the API"
if [ -x "$VENV_PYTHON" ]; then
    if "$VENV_PYTHON" "$REPO_DIR/scripts/test_tts.py" \
        --url "http://127.0.0.1:$PORT" \
        --ref-audio "$REF_AUDIO" \
        --out "$REPO_DIR/test-output.wav"; then
        ok "voice cloning E2E completed"
    else
        fail "test_tts.py returned an error"
    fi
else
    fail "venv $VENV_PYTHON is not available"
fi

echo
if [ "$FAILED" -eq 0 ]; then
    bold "==> All green."
    exit 0
else
    bold "==> Failed. Check $LOG_DIR/xtts.err.log."
    exit 1
fi
