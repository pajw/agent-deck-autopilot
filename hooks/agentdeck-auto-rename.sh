#!/bin/bash
# Auto-name and auto-group agent-deck sessions so the deck never fills with
# path-derived names like "myrepo-3f" in the default group.
#
# Claude Code UserPromptSubmit hook. Naming rules:
#   1. Not inside an agent-deck tmux session: no-op.
#   2. Title already contains a ticket key: final, no rename.
#   3. Prompt or git branch reveals a ticket: rename to "KEY-123 <branch-slug>"
#      and lock the title so agent-deck's Claude-name sync can't clobber it
#      (upstream issue #697).
#   4. No ticket but the title is still path-derived (e.g. "myrepo-3f"): rename
#      to the first words of the prompt, unlocked so a later ticket wins.
# Grouping rules (only while the session sits in a default group):
#   first matching AGENTDECK_GROUP_RULES entry wins; otherwise a ticketed
#   session goes to AGENTDECK_TICKET_GROUP if set. Sessions you have already
#   moved to a group by hand are never touched.
#
# Configuration (optional): ~/.config/agent-deck-autopilot.conf, shell syntax.
#   AGENTDECK_TICKET_PREFIX  Jira project key, e.g. "LA". Unset: any KEY-123.
#   AGENTDECK_GROUP_RULES    "group=regex;group=regex" (ordered, first wins).
#   AGENTDECK_TICKET_GROUP   Group for ticketed sessions with no rule match.

[ -n "$TMUX" ] || exit 0
AD=$(command -v agent-deck || echo /opt/homebrew/bin/agent-deck)
[ -x "$AD" ] || exit 0
sess=$(tmux display-message -p '#S' 2>/dev/null)
case "$sess" in agentdeck_*) ;; *) exit 0 ;; esac
export AGENTDECK_SUPPRESS_TMUX_WARNING=1
[ -f "$HOME/.config/agent-deck-autopilot.conf" ] && . "$HOME/.config/agent-deck-autopilot.conf"
export AGENTDECK_TICKET_PREFIX AGENTDECK_GROUP_RULES AGENTDECK_TICKET_GROUP 2>/dev/null

INPUT=$(cat) CUR=$("$AD" session current --json 2>/dev/null) /usr/bin/python3 - "$AD" << 'PY'
import json, os, re, subprocess, sys

ad = sys.argv[1]
try:
    cur = json.loads(os.environ.get("CUR") or "{}")
    hook = json.loads(os.environ.get("INPUT") or "{}")
except json.JSONDecodeError:
    sys.exit(0)

sid, title, group = cur.get("id"), cur.get("session", ""), cur.get("group", "")
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

# --- grouping: only lift sessions out of the default buckets -----------------
if group in ("", "my-sessions", "others"):
    text = f"{title} {prompt} {branch}".lower()
    target = None
    for rule in (os.environ.get("AGENTDECK_GROUP_RULES") or "").split(";"):
        if "=" not in rule:
            continue
        g, rx = rule.split("=", 1)
        try:
            if re.search(rx, text):
                target = g.strip()
                break
        except re.error:
            continue
    if not target and (find_ticket(text, re.I) or "/deliver" in text):
        target = (os.environ.get("AGENTDECK_TICKET_GROUP") or "").strip() or None
    if target:
        run("group", "move", sid, target)

# --- naming -------------------------------------------------------------------
if re.search(ticket_pat, title, re.I):
    sys.exit(0)

ticket = find_ticket(prompt, prompt_flags) or find_ticket(branch, re.I)

if ticket:
    slug = re.sub(ticket_pat, "", branch, flags=re.I).strip("-_/ ")
    slug = slug.split("/")[-1][:30].strip("-_ ")
    if slug in ("trunk", "main", "master", "develop"):
        slug = ""
    run("rename", sid, f"{ticket} {slug}".strip())
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
