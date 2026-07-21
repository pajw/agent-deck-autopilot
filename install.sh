#!/usr/bin/env bash
# Symlink the scripts into place, template the LaunchAgent, and print the
# Claude Code settings snippet. Idempotent; safe to re-run after git pull.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.claude/hooks" "$HOME/.local/bin" "$HOME/.config"
ln -sf "$REPO/hooks/agentdeck-auto-rename.sh" "$HOME/.claude/hooks/agentdeck-auto-rename.sh"
ln -sf "$REPO/bin/agent-deck-housekeeping" "$HOME/.local/bin/agent-deck-housekeeping"
[ -f "$HOME/.config/agent-deck-autopilot.conf" ] || cp "$REPO/config.example.conf" "$HOME/.config/agent-deck-autopilot.conf"

plist="$HOME/Library/LaunchAgents/com.agent-deck-autopilot.housekeeping.plist"
sed "s|@HOME@|$HOME|g" "$REPO/launchd/com.agent-deck-autopilot.housekeeping.plist" > "$plist"
launchctl unload "$plist" 2>/dev/null || true
launchctl load "$plist"
echo "LaunchAgent loaded: weekly housekeeping, Fridays 15:00."

cat <<'MSG'

Done. Two manual steps remain:

1. Edit ~/.config/agent-deck-autopilot.conf (ticket prefix, group rules,
   notifier).

2. Register the hook in ~/.claude/settings.json under hooks.UserPromptSubmit:

   { "type": "command",
     "command": "~/.claude/hooks/agentdeck-auto-rename.sh",
     "async": true, "timeout": 20 }

Dry-run the housekeeping any time:  WRAP_LIMIT=0 agent-deck-housekeeping
MSG
