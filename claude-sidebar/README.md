# Claude Sidebar

A small always-on-top sidebar for macOS. It sits on the edge of your screen, shows your Claude Code usage, and slides out when a task finishes or when Claude needs your input.

Written from scratch in about 900 lines of Swift, so you can read all of it. It uses **no third-party packages** and only talks to Anthropic (to read your plan usage). It only reads files Claude Code already writes on your Mac.

## What it shows

- **Plan usage.** The same Session and Weekly bars as the Claude app's *Settings → Usage* page. These limits are shared by the Claude desktop app, claude.ai, Cowork and Claude Code. The sidebar reads them with the login Claude Code saved in your Keychain, so you need Claude Code installed and signed in once. That login is only ever sent to `api.anthropic.com`. This uses the same unofficial endpoint as Claude Code's `/usage` screen, so an Anthropic update could break it.
- **Current 5-hour session.** A ring that fills as you use Claude, the time left until the window resets, and your burn rate. Claude plans meter usage in 5-hour windows, so this is the number that matters for hitting limits.
- **Today.** Estimated cost, token count, and a breakdown by model (Opus, Sonnet, Haiku).
- **Last 7 days.** A small bar chart.
- **Recent activity.** A list of "Task done" and "Needs your input" alerts from every Claude Code session.

When the sidebar is collapsed it's a thin tab with a mini ring and a green dot for unread alerts. When an alert arrives, the sidebar slides open, plays a sound, shows a card with Claude's last message, and collapses again after about 7 seconds. If your mouse is over it, it stays open.

> The dollar figures are API-equivalent estimates based on token counts in your local logs. They are not your bill. Anthropic doesn't expose your exact plan percentage locally, so the ring's 100% mark is either **Auto** (your busiest previous 5-hour session) or a value you pick in ⚙️ → *100% session mark*.

## Requirements

- macOS 13 (Ventura) or newer
- Xcode, or just the Command Line Tools: `xcode-select --install`

## Install

```bash
cd claude-sidebar
./build.sh                          # builds build/ClaudeSidebar.app
./install-hooks.sh                  # lets Claude Code tell the sidebar when tasks finish
cp -R build/ClaudeSidebar.app /Applications/
open /Applications/ClaudeSidebar.app
```

The app is ad-hoc signed because you built it yourself. If macOS blocks it the first time, right-click the app, choose **Open**, then click **Open** again.

Restart any running `claude` sessions after `install-hooks.sh` so they load the hooks.

## Settings (⚙️ in the sidebar header)

- **100% session mark.** Auto, or a fixed dollar amount per 5-hour window.
- **Dock to.** Right or left edge of the screen.
- **Play sound.** On or off.
- **Also send macOS notifications.** Also posts a normal Notification Center banner.
- **Launch at login.**
- **Show test notification.** Checks that the pop-out works.
- **Quit.**

## How it works

| Piece | What it does |
|---|---|
| `UsageStore.swift` | Every 15 seconds, reads new lines from `~/.claude/projects/**/*.jsonl` (plus `~/.config/claude` and `$CLAUDE_CONFIG_DIR`). Removes duplicate responses, groups usage into 5-hour sessions, and totals tokens and cost. |
| `hooks/sidebar-hook.sh` | A 5-line shell script that Claude Code runs on its `Stop` and `Notification` hooks. It saves the hook's JSON into `~/.claude/sidebar/events/`. |
| `EventWatcher.swift` | Picks up those files, deletes them, and turns each one into a pop-out. It reads the end of the session transcript to show Claude's last message. |
| `SidebarController.swift` | The floating, non-activating panel. It shows on every Space and over full-screen apps, and never steals focus. |
| `Views.swift` | The SwiftUI interface. |

`install-hooks.sh` backs up `~/.claude/settings.json` to `settings.json.bak.<timestamp>` and then adds these entries:

```json
"hooks": {
  "Stop":         [{ "hooks": [{ "type": "command", "command": "~/.claude/sidebar/sidebar-hook.sh" }] }],
  "Notification": [{ "hooks": [{ "type": "command", "command": "~/.claude/sidebar/sidebar-hook.sh" }] }]
}
```

## Uninstall

1. Quit the app from ⚙️ → Quit, then delete `/Applications/ClaudeSidebar.app`.
2. Remove the two `sidebar-hook.sh` entries from `~/.claude/settings.json`.
3. `rm -rf ~/.claude/sidebar`
