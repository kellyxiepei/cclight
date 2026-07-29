#!/bin/bash
# Start the cclight-mac agent in the background.
# Logs -> agent.log, PID -> agent.pid (both next to this script).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="$SCRIPT_DIR/../.venv/bin/python"
PID_FILE="$SCRIPT_DIR/agent.pid"
LOG_FILE="$SCRIPT_DIR/agent.log"

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "cclight agent already running (pid $(cat "$PID_FILE"))"
    exit 0
fi

if [[ ! -x "$PYTHON" ]]; then
    echo "error: $PYTHON not found — create the venv and install requirements first" >&2
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
