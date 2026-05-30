#!/usr/bin/env bash
#
# Browse the imported Alfred clipboard history. Shows the 50 most recent
# entries matching your query (newest first) so you can see what's there.
# Use "Copy Clipboard Archive Match" to actually grab one.
#
# @raycast.schemaVersion 1
# @raycast.title Search Clipboard Archive
# @raycast.mode fullOutput
# @raycast.packageName Clipboard Archive
# @raycast.icon 📋
# @raycast.argument1 { "type": "text", "placeholder": "search text" }
# @raycast.description Search your imported Alfred clipboard history (text only).

set -euo pipefail
DB="$HOME/.local/share/raycast-clip-archive/archive.db"
[ -f "$DB" ] || { echo "Archive not built yet — run 'Rebuild Clipboard Archive' first."; exit 0; }

q="${1:-}"
esc="${q//\'/\'\'}"   # escape single quotes for SQL

# Alfred stores ts as Mac CFAbsoluteTime (epoch 2001-01-01); +978307200 -> unix epoch.
sqlite3 -batch -noheader "$DB" \
"SELECT datetime(ts + 978307200,'unixepoch','localtime') || '   ' ||
        replace(replace(substr(item,1,180), char(10),' ⏎ '), char(13),'')
 FROM clips
 WHERE item LIKE '%$esc%'
 ORDER BY ts DESC
 LIMIT 50;" | sed 's/^/• /'
