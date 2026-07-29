#!/bin/bash
# Uninstall the cclight Mac agent:
#   1. stop the running agent (if any)
#   2. remove cclight hooks from ~/.claude/settings.json (backup kept)
#   3. delete ~/.cclight-mac
#
# One-command form:
#   curl -fsSL https://raw.githubusercontent.com/kellyxiepei/cclight/main/cclight-mac/uninstall.sh | bash
set -euo pipefail

# everything lives in main() so the script survives deleting its own dir
main() {
    INSTALL_DIR="$HOME/.cclight-mac"
    CLAUDE_SETTINGS="$HOME/.claude/settings.json"

    # ---- 1. stop the agent ----
    PID_FILE="$INSTALL_DIR/agent.pid"
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        PID="$(cat "$PID_FILE")"
        echo "==> stopping agent (pid $PID)"
        kill "$PID" 2>/dev/null || true
        for _ in $(seq 1 10); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.5
        done
        kill -9 "$PID" 2>/dev/null || true
    else
        echo "==> agent not running"
    fi

    # ---- 2. remove cclight hooks from Claude Code settings ----
    if [[ -f "$CLAUDE_SETTINGS" ]]; then
        if command -v python3 >/dev/null 2>&1; then
            echo "==> removing cclight hooks from $CLAUDE_SETTINGS"
            CLAUDE_SETTINGS="$CLAUDE_SETTINGS" python3 <<'PYEOF'
import json
import os
import shutil

path = os.environ["CLAUDE_SETTINGS"]
MARKER = "cclight-hook"

with open(path) as f:
    content = f.read().strip()
settings = json.loads(content) if content else {}

hooks = settings.get("hooks", {})
removed = 0
for event in list(hooks):
    entries = hooks[event]
    for entry in entries:
        kept = [h for h in entry.get("hooks", [])
                if MARKER not in h.get("command", "")]
        removed += len(entry.get("hooks", [])) - len(kept)
        entry["hooks"] = kept
    entries[:] = [e for e in entries if e.get("hooks")]
    if not entries:
        del hooks[event]
if not hooks and "hooks" in settings:
    del settings["hooks"]

if removed:
    shutil.copy2(path, path + ".cclight-backup")
    with open(path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
print("    removed %d cclight hook(s) (backup: %s.cclight-backup)"
      % (removed, path) if removed else "    no cclight hooks found")
PYEOF
        else
            echo "warning: python3 not found, skipping hook cleanup in $CLAUDE_SETTINGS" >&2
        fi
    else
        echo "==> no Claude Code settings file, skipping hook cleanup"
    fi

    # ---- 3. delete install dir ----
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "==> deleting $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    else
        echo "==> $INSTALL_DIR not present"
    fi

    echo
    echo "uninstall complete. restart Claude Code so hook changes take effect."
}

main "$@"
