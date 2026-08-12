#!/usr/bin/env bash
# Symlink the scripts into place, template the LaunchAgent, and print the
# Claude Code settings snippet. Idempotent; safe to re-run after git pull.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.claude/hooks" "$HOME/.local/bin" "$HOME/.config"
ln -sf "$REPO/hooks/agentdeck-auto-rename.sh" "$HOME/.claude/hooks/agentdeck-auto-rename.sh"
ln -sf "$REPO/bin/agent-deck-housekeeping" "$HOME/.local/bin/agent-deck-housekeeping"
ln -sf "$REPO/bin/agent-deck-session-note" "$HOME/.local/bin/agent-deck-session-note"
ln -sf "$REPO/bin/agent-deck-rank" "$HOME/.local/bin/agent-deck-rank"
ln -sf "$REPO/bin/agent-deck-name-session" "$HOME/.local/bin/agent-deck-name-session"
ln -sf "$REPO/bin/agent-deck-group-session" "$HOME/.local/bin/agent-deck-group-session"
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

2. Register two hooks in ~/.claude/settings.json.

   hooks.UserPromptSubmit — names the session from its ticket:

   { "type": "command",
     "command": "~/.claude/hooks/agentdeck-auto-rename.sh",
     "async": true, "timeout": 20 }

   hooks.Stop — keeps its standing note current, so a session that dies
   without a wrap-up still leaves a readable record, then titles unticketed
   sessions from that note and files it into a group. Order matters: both
   the namer and the grouper read what the note writes.

   { "type": "command",
     "command": "~/.local/bin/agent-deck-session-note",
     "async": true, "timeout": 20 },
   { "type": "command",
     "command": "~/.local/bin/agent-deck-name-session",
     "async": true, "timeout": 150 },
   { "type": "command",
     "command": "~/.local/bin/agent-deck-group-session",
     "async": true, "timeout": 150 }

Dry-run the housekeeping any time, without touching a session:

   ARCHIVE_UNRANKED=0 WRAP_LIMIT=0 DEAD_DAYS=99999 agent-deck-housekeeping

then read ~/Library/Logs/agent-deck-housekeeping.log.
MSG
