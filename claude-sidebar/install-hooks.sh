#!/bin/bash
# Installs the hook script and registers it for Claude Code's Stop + Notification events
# in ~/.claude/settings.json (a timestamped backup is made first). Safe to run twice.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/sidebar"
mkdir -p "$DEST/events"
cp "$HERE/hooks/sidebar-hook.sh" "$DEST/sidebar-hook.sh"
chmod +x "$DEST/sidebar-hook.sh"

SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"; fi

/usr/bin/python3 - "$SETTINGS" "$DEST/sidebar-hook.sh" <<'PY'
import json, os, sys
path, cmd = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    with open(path) as f:
        txt = f.read().strip()
        data = json.loads(txt) if txt else {}
hooks = data.setdefault("hooks", {})
for event in ("Stop", "Notification"):
    groups = hooks.setdefault(event, [])
    if any(h.get("command") == cmd for g in groups for h in g.get("hooks", [])):
        continue
    groups.append({"hooks": [{"type": "command", "command": cmd}]})
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"Claude Sidebar hooks registered in {path}")
PY
echo "Done. Restart any running Claude Code sessions so they pick up the hooks."
