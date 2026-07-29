#!/bin/bash
# Install the cclight-mac agent to ~/.cclight-mac and wire up Claude Code
# hooks so the LED lights when Claude is waiting for user input.
#
# Safe to re-run: files are overwritten, the venv is reused, and old
# cclight hooks are replaced (not duplicated).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.cclight-mac"
VENV_DIR="$INSTALL_DIR/.venv"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
AGENT_URL="http://127.0.0.1:8123"

# ---- 0. check python ----
echo "==> checking python"
if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 not found." >&2
    echo "please install Python 3.9+ first, e.g.:  brew install python3" >&2
    exit 1
fi
PY_VERSION="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])')"
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)'; then
    echo "error: Python >= 3.9 required, found $PY_VERSION" >&2
    echo "please upgrade, e.g.:  brew install python3" >&2
    exit 1
fi
echo "    python3 $PY_VERSION ok"

# ---- 1. copy agent code ----
echo "==> installing agent to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/agent.py" \
   "$SCRIPT_DIR/requirements.txt" \
   "$SCRIPT_DIR/start_cclight.sh" \
   "$SCRIPT_DIR/stop_cclight.sh" \
   "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/start_cclight.sh" "$INSTALL_DIR/stop_cclight.sh"

# ---- 2. venv + dependencies ----
echo "==> setting up venv at $VENV_DIR"
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"
echo "    dependencies installed"

# ---- 3. Claude Code hooks ----
echo "==> configuring Claude Code hooks in $CLAUDE_SETTINGS"
AGENT_URL="$AGENT_URL" CLAUDE_SETTINGS="$CLAUDE_SETTINGS" python3 <<'PYEOF'
import json
import os
import shutil

path = os.environ["CLAUDE_SETTINGS"]
url = os.environ["AGENT_URL"]
MARKER = "cclight-hook"

# LED on when Claude is waiting for the user, off while it works
mapping = {
    "Notification": "on",       # permission request / waiting for input
    "Stop": "on",               # finished responding, user's turn
    "UserPromptSubmit": "off",  # user submitted, Claude is working
    "SessionStart": "off",
    "SessionEnd": "off",
}

os.makedirs(os.path.dirname(path), exist_ok=True)
settings = {}
if os.path.exists(path):
    shutil.copy2(path, path + ".cclight-backup")
    with open(path) as f:
        content = f.read().strip()
    if content:
        settings = json.loads(content)

hooks = settings.setdefault("hooks", {})
for event, action in mapping.items():
    command = ("curl -s -m 2 -X POST %s/led/%s >/dev/null 2>&1 || true"
               " # %s" % (url, action, MARKER))
    entries = hooks.setdefault(event, [])
    # drop any previous cclight hooks so re-install never duplicates
    for entry in entries:
        entry["hooks"] = [h for h in entry.get("hooks", [])
                          if MARKER not in h.get("command", "")]
    entries[:] = [e for e in entries if e.get("hooks")]
    entries.append({"hooks": [{"type": "command", "command": command}]})

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print("    hooks written (backup: %s.cclight-backup)" % path)
PYEOF

# ---- 4. done ----
echo
echo "install complete."
echo
echo "  agent dir : $INSTALL_DIR"
echo "  venv      : $VENV_DIR"
echo "  hooks     : $CLAUDE_SETTINGS (Notification/Stop -> LED on, UserPromptSubmit -> LED off)"
echo
echo "next steps:"
echo "  1. plug in the cclight-esp32 board via USB"
echo "  2. start the agent:   $INSTALL_DIR/start_cclight.sh"
echo "  3. watch the logs:    tail -f $INSTALL_DIR/agent.log"
echo
echo "restart Claude Code (or start a new session) so the hooks take effect."
