#!/bin/sh
# Claude Code hook: drops the hook's JSON payload into a folder the sidebar app watches.
# Local only - nothing is sent anywhere.
dir="$HOME/.claude/sidebar/events"
mkdir -p "$dir"
f="$dir/$(date +%s)-$$"
cat > "$f.tmp" && mv "$f.tmp" "$f.json"
exit 0
