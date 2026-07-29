#!/bin/bash
# Stop the background cclight-mac agent started by start_cclight.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/agent.pid"

if [[ ! -f "$PID_FILE" ]]; then
    echo "cclight agent not running (no pid file)"
    exit 0
fi

PID="$(cat "$PID_FILE")"
if ! kill -0 "$PID" 2>/dev/null; then
    echo "cclight agent not running (stale pid $PID), cleaning up"
    rm -f "$PID_FILE"
    exit 0
fi

kill "$PID"
for _ in $(seq 1 10); do
    if ! kill -0 "$PID" 2>/dev/null; then
        rm -f "$PID_FILE"
        echo "cclight agent stopped (pid $PID)"
        exit 0
    fi
    sleep 0.5
done

echo "agent did not exit gracefully, sending SIGKILL"
kill -9 "$PID" 2>/dev/null || true
rm -f "$PID_FILE"
echo "cclight agent killed (pid $PID)"
