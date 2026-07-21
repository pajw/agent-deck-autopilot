# agent-deck-autopilot

Keeps an [Agent Deck](https://github.com/asheshgoplani/agent-deck) tidy when it becomes your main funnel into Claude Code: sessions name themselves, sort themselves into groups, and stale ones get wrapped up and archived on a schedule.

Born of a deck with 35 sessions all called `learnamp-xx` in one group. Never again.

## What it does

**Auto-naming and auto-grouping** (`hooks/agentdeck-auto-rename.sh`): a Claude Code `UserPromptSubmit` hook. On each prompt inside an agent-deck session it:

- renames the session to `KEY-123 <branch-slug>` when the prompt or git branch mentions a ticket, then locks the title so agent-deck's name sync can't overwrite it (upstream issue #697);
- otherwise replaces path-derived titles (`myrepo-3f`) with the first words of the prompt;
- classifies sessions still sitting in a default group using your configured keyword rules (first match wins), with an optional fallback group for ticketed work. Sessions you've grouped by hand are never moved.

**Scheduled housekeeping** (`bin/agent-deck-housekeeping`, weekly LaunchAgent):

1. purges dead sessions (no tmux pane, idle 14+ days) from the registry; transcripts and worktrees are kept;
2. removes orphaned per-session state files under `~/.agent-deck/hooks/`;
3. sends a wrap-up command (default `/wrap-up`, assumed to exist as a skill or slash command in your Claude Code setup) into live sessions idle 7+ days, then archives the ones that complete. Capped per run, and only sessions in `idle` status are touched: a session in `waiting` may be sitting on a question or permission dialog, and typing into one is how accidents happen, so those are flagged to you instead;
4. reports the sweep through any notifier command you configure, or the log otherwise.

## Install

```sh
git clone https://github.com/pajw/agent-deck-autopilot.git
cd agent-deck-autopilot && ./install.sh
```

Then edit `~/.config/agent-deck-autopilot.conf` (see `config.example.conf` for every option) and add the hook to `~/.claude/settings.json` as printed by the installer.

Requires agent-deck v1.10+ (for `session set-title-lock` and `session cleanup`), tmux, python3 and sqlite3.

## Safety notes

- The housekeeping script reads agent-deck's SQLite state read-only; all mutations go through the `agent-deck` CLI.
- Archiving stops the tmux session but keeps everything; `agent-deck session unarchive <id>` restores it.
- Wrap-ups cost a Claude turn each; `WRAP_LIMIT` bounds spend per run.
- Dry-run any time: `WRAP_LIMIT=0 agent-deck-housekeeping`, then read `~/Library/Logs/agent-deck-housekeeping.log`.

## Uninstall

```sh
launchctl unload ~/Library/LaunchAgents/com.agent-deck-autopilot.housekeeping.plist
rm ~/Library/LaunchAgents/com.agent-deck-autopilot.housekeeping.plist
rm ~/.claude/hooks/agentdeck-auto-rename.sh ~/.local/bin/agent-deck-housekeeping
```

and remove the hook entry from `~/.claude/settings.json`.
