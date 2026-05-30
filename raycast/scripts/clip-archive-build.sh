#!/usr/bin/env bash
#
# Rebuild the local searchable archive of Alfred's clipboard *text* history.
# Safe to re-run any time (rebuilds from scratch); run it again before you
# finally retire Alfred to capture anything copied in the meantime.
#
# The archive lives under ~/.local/share (chmod 600) and is intentionally
# NOT in the dotfiles repo -- clipboard history can contain secrets.
#
# Raycast metadata (so it can also be run from Raycast):
# @raycast.schemaVersion 1
# @raycast.title Rebuild Clipboard Archive
# @raycast.mode compact
# @raycast.packageName Clipboard Archive
# @raycast.icon 🗄️
# @raycast.description Re-import Alfred clipboard text history into the local archive.

set -euo pipefail

SRC="$HOME/Library/Application Support/Alfred/Databases/clipboard.alfdb"
DEST_DIR="$HOME/.local/share/raycast-clip-archive"
DEST="$DEST_DIR/archive.db"

[ -f "$SRC" ] || { echo "Alfred clipboard DB not found: $SRC" >&2; exit 1; }
mkdir -p "$DEST_DIR"

rm -f "$DEST.tmp"
sqlite3 "$DEST.tmp" <<SQL
CREATE TABLE clips (item TEXT, ts INTEGER, app TEXT);
ATTACH DATABASE '$SRC' AS alfred;
INSERT INTO clips (item, ts, app)
  SELECT item, ts, app FROM alfred.clipboard
  WHERE dataType = 0 AND item IS NOT NULL AND item <> '';
DETACH DATABASE alfred;
CREATE INDEX clips_ts ON clips (ts);
SQL

mv -f "$DEST.tmp" "$DEST"
chmod 600 "$DEST"

count=$(sqlite3 "$DEST" "SELECT count(*) FROM clips;")
echo "Archived $count text clipboard entries -> $DEST"
