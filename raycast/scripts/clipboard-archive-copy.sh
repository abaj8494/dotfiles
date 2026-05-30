#!/usr/bin/env bash
#
# Copy the most recent archived clipboard entry matching your query back onto
# the clipboard. Refine the query if the wrong one comes back (it always takes
# the newest match). Use "Search Clipboard Archive" first to see candidates.
#
# @raycast.schemaVersion 1
# @raycast.title Copy Clipboard Archive Match
# @raycast.mode silent
# @raycast.packageName Clipboard Archive
# @raycast.icon 📎
# @raycast.argument1 { "type": "text", "placeholder": "search text" }
# @raycast.description Copy the newest archived clip matching the query.

set -euo pipefail
DB="$HOME/.local/share/raycast-clip-archive/archive.db"
[ -f "$DB" ] || { echo "Archive not built yet — run 'Rebuild Clipboard Archive' first."; exit 0; }

q="${1:-}"
esc="${q//\'/\'\'}"

match=$(sqlite3 -batch -noheader "$DB" \
  "SELECT item FROM clips WHERE item LIKE '%$esc%' ORDER BY ts DESC LIMIT 1;")

if [ -n "$match" ]; then
  printf '%s' "$match" | pbcopy
  printf 'Copied: %.60s' "$match"
else
  echo "No archived clip matches \"$q\""
fi
