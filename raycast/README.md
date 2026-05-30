# raycast

Raycast config that lives in the repo. **Not a stow package** — Raycast is
pointed at `scripts/` from its own preferences, not via a `$HOME` symlink.

## Script Commands (`scripts/`)

A bare-bones bridge for the clipboard history that was migrated out of Alfred.
Raycast's own clipboard history can't be imported into (its store is internal /
encrypted), so the old history lives in a separate local archive that these
commands search.

| Command | Mode | What it does |
|---|---|---|
| `clip-archive-build.sh`        | compact    | (Re)imports Alfred's clipboard **text** history into the archive. Re-run before retiring Alfred. |
| `clipboard-archive-search.sh`  | fullOutput | Lists up to 50 matching entries (newest first) so you can see what's there. |
| `clipboard-archive-copy.sh`    | silent     | Copies the newest archived entry matching the query back onto the clipboard. |

The archive is a SQLite DB at `~/.local/share/raycast-clip-archive/archive.db`
(`chmod 600`). It is **deliberately outside this repo** — clipboard history can
contain passwords and tokens, so it must never be committed.

Source of truth at import time:
`~/Library/Application Support/Alfred/Databases/clipboard.alfdb` (table
`clipboard`, `dataType = 0` rows). Images / file-URLs aren't text-recoverable
from that DB and are skipped.

## Setup in Raycast

1. Install Raycast, run it once, grant Accessibility permission.
2. **Settings → Extensions → Script Commands → Add Directory** →
   `~/dotfiles/raycast/scripts`.
3. Run **Rebuild Clipboard Archive** once (or `./scripts/clip-archive-build.sh`).
4. Give the search/copy commands aliases or hotkeys if you use them often.

## Native features replacing Alfred (no config needed)

- **App launching** — default behaviour.
- **Calculator** — type the expression in the root search.
- **Emoji** — built-in *Search Emoji & Symbols*; Enter copies. Assign a hotkey.
- **Clipboard History** — enable the built-in extension and bind a hotkey
  (e.g. ⌘⇧V). Records going forward; the archive above covers the back-catalogue.
