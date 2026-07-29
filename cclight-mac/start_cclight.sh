#!/bin/bash
# Start the cclight-mac agent in the background.
# Logs -> agent.log, PID -> agent.pid (both next to this script).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/agent.pid"
LOG_FILE="$SCRIPT_DIR/agent.log"

# venv lives next to this script when installed (~/.cclight-mac/.venv),
# or at the repo root when running from a checkout
PYTHON=""
for cand in "$SCRIPT_DIR/.venv/bin/python" "$SCRIPT_DIR/../.venv/bin/python"; do
    if [[ -x "$cand" ]]; then
        PYTHON="$cand"
        break
    fi
done

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "cclight agent already running (pid $(cat "$PID_FILE"))"
    exit 0
fi

if [[ -z "$PYTHON" ]]; then
    echo "error: no venv found at $SCRIPT_DIR/.venv or $SCRIPT_DIR/../.venv — run install.sh first" >&2
    exit 1
fi

nohup "$PYTHON" "$SCRIPT_DIR/agent.py" >> "$LOG_FILE" 2>&1 &
PID=$!
echo "$PID" > "$PID_FILE"

sleep 1
if ! kill -0 "$PID" 2>/dev/null; then
    rm -f "$PID_FILE"
    echo "error: agent exited immediately — check $LOG_FILE" >&2
    tail -n 20 "$LOG_FILE" >&2
    exit 1
fi

echo "cclight agent started (pid $PID), log: $LOG_FILE"
