# agent-deck-autopilot

Keeps an [Agent Deck](https://github.com/asheshgoplani/agent-deck) tidy when it becomes your main funnel into Claude Code: sessions name themselves, sort themselves into groups, and stale ones get wrapped up and archived on a schedule.

Born of a deck with 35 sessions all called `learnamp-xx` in one group. Never again.

## What it does

**Auto-naming and auto-grouping** (`hooks/agentdeck-auto-rename.sh`): a Claude Code `UserPromptSubmit` hook. On each prompt inside an agent-deck session it:

- renames the session to `KEY-123 <what the ticket is about>` when the prompt or git branch mentions a ticket, then locks the title so agent-deck's name sync can't overwrite it (upstream issue #697). The description comes from `AGENTDECK_TICKET_TITLE_CMD`, a command of yours that turns a ticket key into its summary; without one it falls back to the branch slug. A key on its own tells you which work item a session belongs to and nothing about what it is doing, which is the entire problem with a deck full of `LA-39776`;
- never overwrites a title you wrote yourself — only ones it wrote itself;
- otherwise replaces path-derived titles (`myrepo-3f`) with the first words of the prompt;
- classifies sessions still sitting in a default group using your configured keyword rules (first match wins), with an optional fallback group for ticketed work. Sessions you've grouped by hand are never moved.

**Standing session notes** (`bin/agent-deck-session-note`): a Claude Code `Stop` hook that rewrites a short markdown note after every assistant turn — what the session was opened for, the last exchange, the prompt trail, whether it stopped mid-answer.

This exists because wrap-up only fires on sessions that finish politely. A session whose tmux server goes away takes its context with it, and those are the ones you most want back. Writing the note continuously makes death free. Notes outlive the registry row on purpose: `grep` is the recovery path once a session is gone.

It also runs standalone — `--all` to rebuild every note, `--relink` to recover a transcript whose `.sid` pointer was lost by matching project path and start time.

**Naming the unticketed** (`bin/agent-deck-name-session`): a `Stop` hook that titles the sessions no ticket key can describe — spikes, investigations, one-offs — by asking a cheap model to read the standing note and name the work in a few words. `thingy` becomes `conversational jd-writer interface`.

It runs once per session, after a few turns, and locks the result. A title that keeps changing is worse than a bad one, because you stop being able to find anything. `--dry-run` shows what it would do; `AGENTDECK_AUTONAME=0` turns it off.

`--enrich-tickets` backfills ticket summaries onto sessions still titled with a bare key, so configuring `AGENTDECK_TICKET_TITLE_CMD` fixes the deck you already have rather than only the sessions you touch next.

**Ranked triage** (`bin/agent-deck-rank`): scores stale sessions against evidence outside the deck — is the ticket still open, is there an open PR, are there unmerged commits, did it stop mid-answer, is the worktree still on disk. Prints `score, id, title, reasons`.

**Scheduled housekeeping** (`bin/agent-deck-housekeeping`, weekly LaunchAgent):

1. refreshes every session's note, so nothing is retired without a record;
2. purges dead sessions (no tmux pane, idle 14+ days) from the registry, stamping each note with why it went; transcripts and worktrees are kept;
3. moves orphaned per-session state files out of `~/.agent-deck/hooks/` into an archive rather than deleting them — a `.sid` file is the only link from a deck session to its transcript, and deleting it is how a transcript becomes unfindable;
4. ranks the stale live sessions, keeps the top `RANK_KEEP` for you to decide on, and retires the rest: idle ones get a wrap-up command first (default `/wrap-up`, capped by `WRAP_LIMIT`), then everything below the line is archived. Sessions in `waiting` are archived but never typed into — one may be sitting on a permission dialog, and sending keys to it is how accidents happen;
5. reports the few that need a decision through any notifier command you configure, or the log otherwise.

The point of step 4 is that a weekly list of everything stale is an inventory, and an inventory that only grows gets skimmed. Set `ARCHIVE_UNRANKED=0` to get the old flag-everything behaviour back.

## Install

```sh
git clone https://github.com/pajw/agent-deck-autopilot.git
cd agent-deck-autopilot && ./install.sh
```

Then edit `~/.config/agent-deck-autopilot.conf` (see `config.example.conf` for every option) and add the hook to `~/.claude/settings.json` as printed by the installer.

Requires agent-deck v1.10+ (for `session set-title-lock` and `session cleanup`), tmux, python3 and sqlite3.

## Safety notes

- The housekeeping script reads agent-deck's SQLite state read-only; all mutations go through the `agent-deck` CLI.
- Nothing is purged or archived before its note is on disk. If `agent-deck-session-note` is missing, housekeeping says so in the log and carries on — that is the one case where a session can vanish uncaptured.
- Archiving stops the tmux session but keeps everything; `agent-deck session unarchive <id>` restores it.
- If ranking fails or returns nothing, every stale session is kept and flagged. Work is never archived on the strength of a broken scorer.
- Wrap-ups cost a Claude turn each; `WRAP_LIMIT` bounds spend per run.
- Dry-run any time, without touching a session: `ARCHIVE_UNRANKED=0 WRAP_LIMIT=0 DEAD_DAYS=99999 agent-deck-housekeeping`, then read `~/Library/Logs/agent-deck-housekeeping.log`.

## Uninstall

```sh
launchctl unload ~/Library/LaunchAgents/com.agent-deck-autopilot.housekeeping.plist
rm ~/Library/LaunchAgents/com.agent-deck-autopilot.housekeeping.plist
rm ~/.claude/hooks/agentdeck-auto-rename.sh
rm ~/.local/bin/agent-deck-{housekeeping,session-note,rank}
```

and remove the hook entries from `~/.claude/settings.json`. Session notes under `~/.local/share/agent-deck-autopilot/` are left alone; delete them yourself once you are sure you want them gone.
