#!/usr/bin/env bash
# Installs Coqui XTTS as a launchd service on macOS, with Apple GPU (MPS) support.
#
# What it does:
#   1. Locates the app directory (Pinokio install by default).
#   2. Applies the patch that switches CPU to MPS and binds to port 7861.
#   3. Renders the plist template with real paths.
#   4. Loads the LaunchAgent (starts now and at every login).
#   5. Waits for Gradio to answer on :7861.
#
# Override paths via env vars:
#   XTTS_DIR=/some/other/xtts.pinokio.git ./scripts/install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XTTS_DIR="${XTTS_DIR:-$HOME/pinokio/api/xtts.pinokio.git}"
VENV_PYTHON="${VENV_PYTHON:-$XTTS_DIR/env/bin/python}"
LOG_DIR="${LOG_DIR:-$REPO_DIR/logs}"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.xtts.tts.plist"
PLIST_TEMPLATE="$REPO_DIR/$PLIST_NAME"
PLIST_TARGET="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
PATCH_FILE="$REPO_DIR/patches/01-mps-and-port.patch"
SERVICE_LABEL="com.xtts.tts"
PORT="${XTTS_PORT:-7861}"

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
ok()    { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn()  { printf "  \033[33m!\033[0m %s\n" "$*"; }
fail()  { printf "  \033[31m✗\033[0m %s\n" "$*" >&2; exit 1; }

bold "==> Checking prerequisites"
[ -d "$XTTS_DIR" ]    || fail "XTTS_DIR does not exist: $XTTS_DIR"
[ -f "$XTTS_DIR/app.py" ] || fail "app.py not found in $XTTS_DIR"
[ -x "$VENV_PYTHON" ] || fail "venv Python not found or not executable: $VENV_PYTHON"
[ -f "$PLIST_TEMPLATE" ] || fail "plist template not found: $PLIST_TEMPLATE"
[ -f "$PATCH_FILE" ]  || fail "patch not found: $PATCH_FILE"

# Sanity check
"$VENV_PYTHON" -c "import torch, gradio, TTS" 2>/dev/null \
    || fail "venv $VENV_PYTHON is missing torch/gradio/TTS. Run the Pinokio install first."
ok "venv ok ($VENV_PYTHON)"

if "$VENV_PYTHON" -c "import torch,sys; sys.exit(0 if torch.backends.mps.is_available() else 1)"; then
    ok "MPS available (will run on the Apple GPU with CPU fallback)"
else
    warn "MPS not available. Will fall back to CPU (slower)."
fi

mkdir -p "$LOG_DIR" "$LAUNCH_AGENTS_DIR"

bold "==> Applying MPS patch to app.py"
cd "$XTTS_DIR"
if patch -p1 --dry-run -R --silent < "$PATCH_FILE" >/dev/null 2>&1; then
    ok "patch already applied, skipping"
else
    if ! patch -p1 --dry-run --silent < "$PATCH_FILE" >/dev/null 2>&1; then
        fail "patch does not apply cleanly to app.py. Upstream may have changed."
    fi
    cp app.py "app.py.bak.$(date +%Y%m%d-%H%M%S)"
    patch -p1 < "$PATCH_FILE"
    ok "patch applied (backup saved as app.py.bak.*)"
fi
cd - >/dev/null

bold "==> Rendering $PLIST_NAME"
sed \
    -e "s|__VENV_PYTHON__|$VENV_PYTHON|g" \
    -e "s|__XTTS_DIR__|$XTTS_DIR|g" \
    -e "s|__LOG_DIR__|$LOG_DIR|g" \
    "$PLIST_TEMPLATE" > "$PLIST_TARGET"
ok "plist generated: $PLIST_TARGET"

bold "==> Loading the LaunchAgent"
if launchctl list | grep -q "$SERVICE_LABEL"; then
    launchctl unload "$PLIST_TARGET" 2>/dev/null || true
    ok "old version unloaded"
fi
launchctl load -w "$PLIST_TARGET"
ok "LaunchAgent loaded (label: $SERVICE_LABEL)"

# XTTS first boot can be slow because it downloads the 1.87GB model the very
# first time. After that, boot is just model-to-MPS and is much faster.
bold "==> Waiting for Gradio to answer on :$PORT (up to 600s, first run may download 1.87GB)"
for i in $(seq 1 600); do
    if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then
        ok "Gradio answered (after ${i}s)"
        break
    fi
    if [ "$i" -eq 600 ]; then
        warn "Gradio did not answer within 600s. Check $LOG_DIR/xtts.err.log."
        exit 2
    fi
    sleep 1
done

bold "==> Status"
launchctl list | grep "$SERVICE_LABEL" || true
echo
echo "UI:        http://127.0.0.1:$PORT"
echo "Logs:      tail -f $LOG_DIR/xtts.{out,err}.log"
echo "Start:     ./scripts/start.sh"
echo "Stop:      ./scripts/stop.sh"
echo "Status:    ./scripts/status.sh"
