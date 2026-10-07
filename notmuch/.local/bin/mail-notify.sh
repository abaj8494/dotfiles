#!/bin/bash
# mail-notify.sh — macOS preview notifications for newly landed mail.
# Called from the notmuch post-new hook (BEFORE jobsync's retagging).
#
# "New" = new to the INDEX, tracked by the notmuch database revision
# (`lastmod:`), not by the Date header — a message that arrives late still
# gets its banner. A seen-ring suppresses duplicates when later tag churn
# (jobsync classification, phone syncs) bumps the same message's revision.
# Quiet hours 23:00–07:59: nothing is shown and the pointer does NOT advance,
# so the first morning sync surfaces (a capped view of) what landed overnight.
NOTMUCH=/opt/homebrew/bin/notmuch
STATE="$HOME/.cache/mail-notify.rev"
SEEN="$HOME/.cache/mail-notify.seen"
CAP=6
HOUR=${MAIL_NOTIFY_HOUR_OVERRIDE:-$(date +%H)}

if [ "$HOUR" -ge 23 ] || [ "$HOUR" -le 7 ]; then
  exit 0
fi

REV_NOW=$($NOTMUCH count --lastmod '*' 2>/dev/null | awk '{print $NF}')
case "$REV_NOW" in (*[!0-9]*|"") exit 0;; esac
LAST=$(cat "$STATE" 2>/dev/null)
case "$LAST" in (*[!0-9]*|"") echo "$REV_NOW" > "$STATE"; exit 0;; esac   # first run: baseline only
[ "$REV_NOW" -gt "$LAST" ] || exit 0

QUERY="lastmod:$((LAST + 1)).. and tag:inbox and tag:unread and not tag:sent"
TN=/opt/homebrew/bin/terminal-notifier
$NOTMUCH search --format=json --sort=oldest-first "$QUERY" 2>/dev/null \
| CAP=$CAP SEEN="$SEEN" TN="$TN" /usr/bin/python3 -c '
import json, os, subprocess, sys
cap = int(os.environ["CAP"]); seen_path = os.environ["SEEN"]
try: seen = open(seen_path).read().split()
except FileNotFoundError: seen = []
rows = [r for r in json.load(sys.stdin) if (r.get("query") or [None])[0] not in seen]
tn = os.environ.get("TN")
use_tn = False   # Script Editor now has a real banner style; terminal-notifier was never authorized
def esc(s): return (s or "").replace("|", ", ").replace("\\", "\\\\").replace("\"", "\\\"")[:120]
def post(title, message, ident):
    # terminal-notifier has its own app identity with a real banner style;
    # Script Editor (osascript) on this Mac is configured sound-only.
    if use_tn:
        subprocess.run([tn, "-title", (title or "mail")[:120], "-message", (message or "")[:160],
                        "-sound", "default", "-group", "mail-" + str(abs(hash(ident)) % 10**9)],
                       capture_output=True, timeout=10)
    else:
        subprocess.run(["osascript", "-e",
            "display notification \"%s\" with title \"%s\"" % (esc(message), esc(title))],
            capture_output=True, timeout=10)
for r in rows[:cap]:
    post((r.get("authors") or "mail").replace("|", ", "), r.get("subject") or "(no subject)", (r.get("query") or ["x"])[0])
if len(rows) > cap:
    post("Mail", "and %d more" % (len(rows) - cap), "more")
ids = [(r.get("query") or [None])[0] for r in rows if (r.get("query") or [None])[0]]
open(seen_path, "w").write("\n".join((seen + ids)[-500:]))
'
echo "$REV_NOW" > "$STATE"
