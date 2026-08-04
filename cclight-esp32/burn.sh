#!/bin/bash
# Burn main.py onto the ESP32-C3 over USB and reset it.
#
# Usage:
#   ./burn.sh                    # burn main.py (board must have MicroPython)
#   ./burn.sh --firmware         # ALSO erase flash + install latest MicroPython first
#   ./burn.sh [--firmware] <port>  # explicit port, e.g. /dev/tty.usbmodem1101
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PYTHON="$SCRIPT_DIR/../.venv/bin/python"
FW_CACHE_DIR="$SCRIPT_DIR/.firmware"
FW_PAGE="https://micropython.org/download/ESP32_GENERIC_C3/"

FLASH_FIRMWARE=0
PORT=""
for arg in "$@"; do
    case "$arg" in
        --firmware) FLASH_FIRMWARE=1 ;;
        *) PORT="$arg" ;;
    esac
done

# ---- venv + tools ----
if [[ ! -x "$VENV_PYTHON" ]]; then
    echo "error: venv not found at $SCRIPT_DIR/../.venv — create it first:" >&2
    echo "  python3 -m venv $SCRIPT_DIR/../.venv" >&2
    exit 1
fi
if ! "$VENV_PYTHON" -m mpremote version >/dev/null 2>&1; then
    echo "==> installing mpremote into the venv"
    "$VENV_PYTHON" -m pip install -q mpremote
fi
if [[ "$FLASH_FIRMWARE" == "1" ]] && ! "$VENV_PYTHON" -m esptool version >/dev/null 2>&1; then
    echo "==> installing esptool into the venv"
    "$VENV_PYTHON" -m pip install -q esptool
fi

find_port() {
    local ports=(/dev/tty.usbmodem*)
    [[ -e "${ports[0]}" ]] || return 1
    if [[ ${#ports[@]} -gt 1 ]]; then
        echo "error: multiple serial ports found, pass one explicitly:" >&2
        printf '  %s\n' "${ports[@]}" >&2
        echo "usage: ./burn.sh [--firmware] <port>" >&2
        exit 1
    fi
    echo "${ports[0]}"
}

wait_for_port() {  # wait up to 15s for a usbmodem port to (re)appear
    for _ in $(seq 1 30); do
        local p
        if p="$(find_port)"; then
            echo "$p"
            return 0
        fi
        sleep 0.5
    done
    return 1
}

# ---- pick the serial port ----
if [[ -z "$PORT" ]]; then
    PORT="${CCLIGHT_PORT:-}"
fi
if [[ -z "$PORT" ]]; then
    if ! PORT="$(find_port)"; then
        echo "error: no /dev/tty.usbmodem* device found — is the board plugged in?" >&2
        exit 1
    fi
fi
echo "==> using port $PORT"

# ---- warn if something (e.g. the cclight-mac agent) is holding the port ----
if command -v lsof >/dev/null 2>&1 && lsof "$PORT" >/dev/null 2>&1; then
    echo "error: $PORT is busy — another process has it open." >&2
    echo "if the cclight-mac agent is running, stop it first:" >&2
    echo "  ~/.cclight-mac/stop_cclight.sh   (or cclight-mac/stop_cclight.sh)" >&2
    exit 1
fi

# ---- optional: erase flash + install latest MicroPython ----
if [[ "$FLASH_FIRMWARE" == "1" ]]; then
    echo "==> looking up latest MicroPython firmware for ESP32_GENERIC_C3"
    FW_PATH="$(curl -fsSL "$FW_PAGE" \
        | grep -oE 'resources/firmware/ESP32_GENERIC_C3-[A-Za-z0-9.\-]+\.bin' \
        | head -1)"
    if [[ -z "$FW_PATH" ]]; then
        echo "error: could not find a firmware .bin link on $FW_PAGE" >&2
        exit 1
    fi
    FW_FILE="$FW_CACHE_DIR/$(basename "$FW_PATH")"
    if [[ -f "$FW_FILE" ]]; then
        echo "    using cached $(basename "$FW_FILE")"
    else
        echo "    downloading $(basename "$FW_FILE")"
        mkdir -p "$FW_CACHE_DIR"
        curl -fsSL -o "$FW_FILE" "https://micropython.org/$FW_PATH"
    fi
    echo "==> erasing flash (this wipes EVERYTHING on the chip)"
    "$VENV_PYTHON" -m esptool --chip esp32c3 --port "$PORT" erase_flash
    echo "==> writing $(basename "$FW_FILE")"
    # port re-enumerates after erase; re-resolve it
    PORT="$(wait_for_port)" || { echo "error: port did not reappear after erase" >&2; exit 1; }
    "$VENV_PYTHON" -m esptool --chip esp32c3 --port "$PORT" write_flash -z 0 "$FW_FILE"
    echo "==> waiting for MicroPython to boot"
    sleep 2
    PORT="$(wait_for_port)" || { echo "error: port did not reappear after flashing" >&2; exit 1; }
    echo "    firmware installed, port $PORT"
fi

# ---- interrupt whatever is running so mpremote can enter raw REPL ----
"$VENV_PYTHON" - "$PORT" <<'PYEOF'
import sys, time
import serial
s = serial.Serial(sys.argv[1], 115200, timeout=1)
for _ in range(3):
    s.write(b"\x03")
    time.sleep(0.3)
s.reset_input_buffer()
s.close()
PYEOF

# ---- burn (resume mode: no soft reset, so a blocking main.py can't restart) ----
echo "==> copying main.py to the board"
"$VENV_PYTHON" -m mpremote connect "$PORT" resume cp "$SCRIPT_DIR/main.py" :main.py
echo "==> resetting board"
"$VENV_PYTHON" -m mpremote connect "$PORT" resume reset || true
sleep 2
PORT="$(wait_for_port)" || { echo "error: port did not reappear after reset" >&2; exit 1; }

# ---- verify: PING must answer PONG ----
echo "==> verifying (PING)"
"$VENV_PYTHON" - "$PORT" <<'PYEOF'
import sys, time
import serial
s = serial.Serial(sys.argv[1], 115200, timeout=1)
for attempt in range(8):
    time.sleep(0.5)
    s.reset_input_buffer()
    s.write(b"PING\r\n")
    reply = s.readline().decode(errors="replace").strip()
    if reply == "PONG":
        print("    PING -> PONG, firmware is running")
        sys.exit(0)
print("    no PONG after 8 attempts (last reply: %r)" % reply)
sys.exit(1)
PYEOF

echo
echo "burn complete — main.py is running on the board."
