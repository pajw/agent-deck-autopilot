#!/bin/bash
# Auto-name agent-deck sessions so the deck never fills with path-derived
# names like "myrepo-3f".
#
# Claude Code UserPromptSubmit hook. Naming rules:
#   1. Not inside an agent-deck tmux session: no-op.
#   2. Title already contains a ticket key: final, no rename.
#   3. Prompt or git branch reveals a ticket: rename to "KEY-123 <branch-slug>"
#      and lock the title so agent-deck's Claude-name sync can't clobber it
#      (upstream issue #697).
#   4. No ticket but the title is still path-derived (e.g. "myrepo-3f"): rename
#      to the first words of the prompt, unlocked so a later ticket wins.
#
# Grouping used to live here, gated on the session sitting in a default group.
# Agent Deck creates a session in whichever group the cursor is on, so that
# gate was almost never open and almost nothing was ever filed. It is now
# agent-deck-group-session's job, on the Stop hook, where the standing note
# exists and one component owns placement.
#
# Configuration (optional): ~/.config/agent-deck-autopilot.conf, shell syntax.
#   AGENTDECK_TICKET_PREFIX  Jira project key, e.g. "LA". Unset: any KEY-123.
#   AGENTDECK_TICKET_TITLE_CMD  Command taking a ticket key and printing its
#                            summary, used to title the session with what the
#                            work is rather than just its key.
#   AGENTDECK_TITLE_MAX      Characters of summary to keep (default 30).

[ -n "$TMUX" ] || exit 0
AD=$(command -v agent-deck || echo /opt/homebrew/bin/agent-deck)
[ -x "$AD" ] || exit 0
sess=$(tmux display-message -p '#S' 2>/dev/null)
case "$sess" in agentdeck_*) ;; *) exit 0 ;; esac
export AGENTDECK_SUPPRESS_TMUX_WARNING=1
[ -f "$HOME/.config/agent-deck-autopilot.conf" ] && . "$HOME/.config/agent-deck-autopilot.conf"
export AGENTDECK_TICKET_PREFIX AGENTDECK_TICKET_TITLE_CMD AGENTDECK_TITLE_MAX 2>/dev/null

INPUT=$(cat) CUR=$("$AD" session current --json 2>/dev/null) /usr/bin/python3 - "$AD" << 'PY'
import json, os, re, subprocess, sys

ad = sys.argv[1]
try:
    cur = json.loads(os.environ.get("CUR") or "{}")
    hook = json.loads(os.environ.get("INPUT") or "{}")
except json.JSONDecodeError:
    sys.exit(0)

sid, title = cur.get("id"), cur.get("session", "")
if not sid:
    sys.exit(0)

prompt = hook.get("prompt", "") or ""
cwd = hook.get("cwd") or os.getcwd()
branch = ""
try:
    branch = subprocess.run(["git", "-C", cwd, "branch", "--show-current"],
                            capture_output=True, text=True, timeout=5).stdout.strip()
except Exception:
    pass

prefix = (os.environ.get("AGENTDECK_TICKET_PREFIX") or "").strip()
if prefix:
    ticket_pat = rf"\b({re.escape(prefix)})-?(\d{{1,6}})\b"
    prompt_flags = re.I
else:
    # No configured prefix: only match explicit upper-case keys in prose to
    # avoid false positives like "python3-501".
    ticket_pat = r"\b([A-Z][A-Z0-9]{1,9})-(\d{1,6})\b"
    prompt_flags = 0

def find_ticket(text, flags):
    m = re.search(ticket_pat, text, flags)
    return f"{m.group(1).upper()}-{m.group(2)}" if m else None

def run(*args):
    subprocess.run([ad, *args], capture_output=True, timeout=10)

# --- naming -------------------------------------------------------------------
def describe(ticket):
    """What the ticket is about, in the words of whoever wrote it.

    A key alone says which work item a session belongs to and nothing about
    what it is doing, which is the whole problem with "KEY-123" as a title.
    """
    cmd = (os.environ.get("AGENTDECK_TICKET_TITLE_CMD") or "").strip()
    if not cmd:
        return ""
    try:
        out = subprocess.run(["sh", "-c", f'{cmd} "$1"', "sh", ticket],
                             capture_output=True, text=True, timeout=25)
    except Exception:
        return ""
    text = re.sub(r"\s+", " ", (out.stdout or "").strip())
    if out.returncode != 0 or not text:
        return ""
    try:
        limit = int(os.environ.get("AGENTDECK_TITLE_MAX") or 30)
    except ValueError:
        limit = 30
    kept = []
    for word in text.split():
        if len(" ".join(kept + [word])) > limit:
            break
        kept.append(word)
    return " ".join(kept).strip(" ,;:|-")


ticket_in_title = find_ticket(title, re.I)
ticket = ticket_in_title or find_ticket(prompt, prompt_flags) or find_ticket(branch, re.I)

if ticket:
    slug = re.sub(ticket_pat, "", branch, flags=re.I).strip("-_/ ")
    slug = slug.split("/")[-1][:30].strip("-_ ")
    if slug in ("trunk", "main", "master", "develop"):
        slug = ""
    # Only ever overwrite a title this hook would have written itself. Anything
    # else in the title is your wording, and outranks the ticket summary.
    ours = {ticket, f"{ticket} {slug}".strip()}
    if ticket_in_title and title not in ours:
        sys.exit(0)
    desired = f"{ticket} {describe(ticket) or slug}".strip()
    if title != desired:
        run("rename", sid, desired)
        run("session", "set-title-lock", sid, "on")
    sys.exit(0)

# No ticket: only replace titles that affirmatively look path-derived
# ("<dir>", "<dir>-3f"). An empty/unreadable title is NOT treated as degraded;
# session current can race a just-written DB and return blank.
base = os.path.basename(cwd.rstrip("/"))
if not (title and re.fullmatch(rf"{re.escape(base)}(-[0-9a-f]{{2}})?", title)):
    sys.exit(0)
words = re.sub(r"[^\w\s-]", " ", prompt).split()[:5]
new = " ".join(words)[:40].strip()
if new:
    run("rename", sid, new)
PY
exit 0
