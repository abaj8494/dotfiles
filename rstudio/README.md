# rstudio

RStudio Desktop config. Only `rstudio-prefs.json` and the `keybindings/` dir are
tracked — RStudio rewrites `rstudio-prefs.json` in place (so it's a real file,
not a stow symlink), while `keybindings/` is linked in as a folded directory:

```
~/.config/rstudio/keybindings  ->  ~/dotfiles/rstudio/.config/rstudio/keybindings
```

RStudio loads keybindings at **startup** — restart the app after editing.

## Keybindings (Emacs-flavoured)

`rstudio_bindings.json` = app commands, `editor_bindings.json` = Ace editor
commands. App commands outrank editor commands on the same chord, so reclaiming
a chord means unbinding the app command **and** adding the editor binding.

| Chord      | Action                     | How                                             |
|------------|----------------------------|-------------------------------------------------|
| `C-c C-c`  | Run Current Line/Selection, keeping cursor in place | `executeCodeWithoutMovingCursor` (was `Alt+Enter`; plain `Cmd+Enter`/`executeCode` still runs + advances) |
| `C-c C-o`  | Move Focus to Next Pane     | `focusNextPane`                                 |
| `C-l`      | Center Selection (recenter)| unbind `consoleClear`, bind `centerselection`   |
| `C-p`      | Move Upwards One Line       | unbind `jumpToMatching`, bind `golineup`        |

## Gotcha: copy appends to the clipboard (Alfred)

**Symptom:** in RStudio (only), copying — `Cmd+C`, right-click Copy, `M-w` —
*appends* to the system clipboard instead of replacing; the pasteboard
accumulates every prior copy. Every other macOS app copies fine.

**Cause:** Alfred's clipboard-history feature interacting with RStudio's copy
path. RStudio's editor is Ace running inside an embedded Chromium web view
(right-click → Inspect works), and Alfred trips that web-view copy path in a way
it never trips native Cocoa text fields — which is why the bug is RStudio-only
even though the trigger is external.

**Fix:** disable Alfred's clipboard management (Alfred Preferences → Features →
Clipboard). See <https://forum.posit.co/t/interaction-between-rstudio-and-alfreds-clipboard-management/36273>.

It is **not** the editor keybinding mode (predates the Emacs toggle), the
reMarkable clip-sync pasteboard daemon, a corrupt RStudio profile, or the
RStudio build — all ruled out by testing.
