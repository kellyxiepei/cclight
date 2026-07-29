#!/bin/bash
# Burn main.py onto the ESP32-C3 over USB and reset it.
#
# Usage:
#   ./burn.sh              # auto-detect port (/dev/tty.usbmodem*)
#   ./burn.sh <port>       # explicit port, e.g. ./burn.sh /dev/tty.usbmodem1101
#
# The board must already have MicroPython flashed (see README.md).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PYTHON="$SCRIPT_DIR/../.venv/bin/python"

# ---- locate a python with mpremote (install into the repo venv if needed) ----
if [[ ! -x "$VENV_PYTHON" ]]; then
    echo "error: venv not found at $SCRIPT_DIR/../.venv — create it first:" >&2
    echo "  python3 -m venv $SCRIPT_DIR/../.venv" >&2
    exit 1
fi
if ! "$VENV_PYTHON" -m mpremote version >/dev/null 2>&1; then
    echo "==> installing mpremote into the venv"
    "$VENV_PYTHON" -m pip install -q mpremote
fi

# ---- pick the serial port ----
PORT="${1:-${CCLIGHT_PORT:-}}"
if [[ -z "$PORT" ]]; then
    PORTS=(/dev/tty.usbmodem*)
    if [[ ! -e "${PORTS[0]}" ]]; then
        echo "error: no /dev/tty.usbmodem* device found — is the board plugged in?" >&2
        exit 1
    fi
    if [[ ${#PORTS[@]} -gt 1 ]]; then
        echo "error: multiple serial ports found, pass one explicitly:" >&2
        printf '  %s\n' "${PORTS[@]}" >&2
        echo "usage: ./burn.sh <port>" >&2
        exit 1
    fi
    PORT="${PORTS[0]}"
fi
echo "==> using port $PORT"

# ---- warn if something (e.g. the cclight-mac agent) is holding the port ----
if command -v lsof >/dev/null 2>&1 && lsof "$PORT" >/dev/null 2>&1; then
    echo "error: $PORT is busy — another process has it open." >&2
    echo "if the cclight-mac agent is running, stop it first:" >&2
    echo "  ~/.cclight-mac/stop_cclight.sh   (or cclight-mac/stop_cclight.sh)" >&2
    exit 1
fi

# ---- burn ----
echo "==> copying main.py to the board"
"$VENV_PYTHON" -m mpremote connect "$PORT" cp "$SCRIPT_DIR/main.py" :main.py
echo "==> resetting board"
"$VENV_PYTHON" -m mpremote connect "$PORT" reset
echo
echo "burn complete — main.py is running on the board."
echo "quick test:  screen $PORT 115200   (type PING, expect PONG; exit: Ctrl-A K)"
