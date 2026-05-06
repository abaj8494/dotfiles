# Emacs Configuration — Development Guide

## Installation

Emacs is installed and built through **MacPorts** at `/Applications/MacPorts/Emacs.app`. Key binaries:

| Binary | Path |
|--------|------|
| Emacs | `/Applications/MacPorts/Emacs.app/Contents/MacOS/Emacs` |
| emacsclient | `/Applications/MacPorts/Emacs.app/Contents/MacOS/bin/emacsclient` |

## Daemon Setup

Emacs runs as a **launchd daemon** that starts at login and stays alive in the background. GUI frames are attached via `emacsclient -c`.

### Architecture

```
launchd (at login)
  └─ Emacs --fg-daemon          ← headless, loads full config, runs server
       ├─ emacsclient -c -n     ← GUI frames (opened from Spotlight or terminal)
       ├─ emacsclient --eval    ← cron jobs (sync-daily.sh, etc.)
       └─ server socket         ← /tmp/emacs501/server
```

### Key Files

| File | Purpose |
|------|---------|
| `~/Library/LaunchAgents/org.gnu.emacs.daemon.plist` | launchd agent — starts daemon at login, restarts on crash |
| `~/Applications/EmacsClient.app` | Spotlight-launchable wrapper — runs `emacsclient -c -n` |
| `~/Library/Logs/emacs-daemon.log` | Daemon stdout/stderr log |

### Operations

| Task | Command |
|------|---------|
| Open a GUI frame | Spotlight → "EmacsClient", or `emacsclient -c -n` |
| Close a frame (daemon stays) | `C-x 5 0` |
| Full restart | `M-x kill-emacs`, then launchd auto-restarts |
| Force restart | `launchctl kickstart -k gui/501/org.gnu.emacs.daemon` |
| Check daemon status | `emacsclient --eval '(emacs-pid)'` |
| View daemon log | `tail -f ~/Library/Logs/emacs-daemon.log` |
| Reload config (no restart) | `C-c R` (`aj/reload-config`) |

### Gotchas

- **Don't launch Emacs.app from Spotlight** — that starts a second independent Emacs with a server socket conflict. Use "EmacsClient" instead.
- **`(server-start)` in init.el** is guarded by `(unless (server-running-p) ...)` so it's a no-op when running as `--fg-daemon` (which starts the server automatically).
- **PATH in the daemon** is set explicitly in the plist (`EnvironmentVariables`) because launchd doesn't inherit shell PATH. If you add a new tool (e.g. a new Python), update the plist PATH too.
- **KeepAlive** is set to `SuccessfulExit: false` — the daemon restarts on crash but NOT on clean `M-x kill-emacs` (exit 0).

## Config Structure

```
~/.emacs.d/
  init.el                    ← Entry point, loads modules via (require 'name)
  elisp/
    bootstrap.el             ← straight.el package manager bootstrap
    package-config.el        ← Package declarations (Helm, org-roam, gptel, conda, jupyter, etc.)
    ui-config.el             ← Theme (gruber), fonts, splash screen
    org-config.el            ← Org-mode settings, LaTeX export config, link types
    daily-config.el          ← Daily note entry point. Requires the daily-* submodules
                                below; hosts the file-open hook, navigation, refile-on-DONE
                                glue, propagate-DONE-to-tasks, schedule/deadline date anchoring,
                                and the C-c d / C-c d r keymaps.
    daily-structure.el       ← Heading scaffolding: ensure-heading-*, separators, newpages,
                                blank-line normalizer, daily-date-file-p, under-heading-p
    daily-week.el            ← Week transclude (yearly-file IDs, ISO week resolver, fold-on-open)
    daily-recurring.el       ← tasks.org agenda → due-set, subtree extract/strip, bring-forward
                                (overdue captures + recurring), refresh-daily-recurring
    daily-capture.el         ← org-capture + org-roam-dailies templates, lifecycle hooks,
                                cookie-stripping advice, hook-suppression plumbing,
                                move-capture-to-recurring
    daily-calendar.el        ← Monthly cal table, weather (rsync + OpenWeather fallback,
                                hourly table), mode-line wttr widget, current-hour highlighting
    daily-garmin.el          ← ** Self section: sleep/stress chart, route maps, dashboard,
                                garmindb sync, garmin-activity: org-link type
    daily-anki.el            ← AnkiConnect → 14-day review chart under * TODO Anki
    daily-rmpp.el            ← rMPP push (gmi pull → mbsync → export → scp), aj/ferrari-make,
                                shared log-buffer / sound / edge-tts plumbing
    anki-config.el           ← Anki-editor integration
    email-config.el          ← notmuch + mbsync (Abaj/UNSW IMAP) + gmail-lieer (Gmail API)
    aj-bindings.el           ← Personal global keybindings (C-c Y yank map, C-c b p
                                beancount-deploy, C-c s scan-document via vterm)
    magit-bindings.el        ← Magit keybindings
    ox-hugo-bindings.el      ← ox-hugo export keybindings
    auto-save-config.el      ← Auto-save configuration
    ob-markdown.el           ← Org-babel markdown support
    java-lsp.el              ← Java LSP (eglot + openjdk@21)
    gruber-themes.el         ← Custom theme
    ink.el                   ← Ink integration
    my-home.el               ← Quick-access Dired paths
    custom-vars.el           ← custom-set-variables/faces (auto-generated)
```

All modules use `lexical-binding: t`.

## Key Subsystems

### Daily Notes (`daily-config.el` + `daily-*.el`)

Manages org-roam daily notes with auto-populated structure. `daily-config.el`
is a thin entry point (~420 lines) that requires eight focused submodules
listed in the Config Structure above. Cross-module dependencies flow
`daily-structure → daily-week / daily-recurring → daily-capture →
daily-{calendar, garmin, anki, rmpp}`. Most other modules require
`daily-structure` for heading helpers; `daily-capture`'s reposition path
fans out into recurring + week + structure.

**Module load-order gotcha**: don't put a top-level `(define-key
aj/daily-refresh-map ...)` inside a submodule. The refresh-map is
defvar'd in `daily-config.el`'s body, which runs *after* every
submodule's `(require ...)`. The garmin `C-c d r j` binding originally
lived in `daily-garmin.el` and broke load with `Symbol's value as
variable is void: aj/daily-refresh-map` after the refactor — fixed by
moving the `define-key` into `daily-config.el`'s keymap section and
exposing the lambda as the named command `aj/garmin-refresh-and-jump`
in `daily-garmin.el`.

**Hook chain**: `org-roam-dailies-find-file-hook` → `aj/daily-file-open-hook` which:
1. Detects bare files (`aj/daily-needs-setup-p` — checks for missing `* Journal`)
2. For new files: inserts week transclude, ensures heading structure, populates recurring tasks, calendar
3. For existing files: refreshes recurring, brings forward overdue captures, refreshes calendar
4. Enables `org-transclusion-mode`, saves buffer

**Schedule/deadline date anchoring**: `org-schedule` and `org-deadline`
are around-advised by `aj/daily--anchor-org-read-date`
(`daily-config.el`). When point is in a daily file the calendar prompt
defaults to the daily's filename date instead of today, via
`org-overriding-default-time`. Outside daily files the advice is a
passthrough. Useful right after `C-c d c` (capture-date) where the
captured entry needs `C-c C-s` defaulted to the day you captured into.

**Keybindings** (all under `C-c d` = `org-roam-dailies-map`):

| Key | Function |
|-----|----------|
| `C-c d d` | Go to today's daily |
| `C-c d c` | Capture into a date (creates the daily if needed) |
| `C-c d g` | Go to date (pick from calendar) |
| `C-c d p` | Pull highlights from rMPP + export + push today's daily PDF |
| `C-c d r r` | Refresh recurring tasks |
| `C-c d r c` | Refresh calendar |
| `C-c d r w` | Refresh week overview |
| `C-c d r o` | Bring forward overdue items |
| `C-c d r a` | Insert Anki review chart |
| `C-c d r j` | Refresh Garmin journal data (`C-u` to force sync) |
| `C-c d w` | Insert week transclude |
| `C-c d F` / `B` | Next / previous day |

**rMPP push** (`C-c d p` → `aj/rmpp-push-daily`):
- Step 1: `make ferrari-pull-highlights` (KOReader highlights → sioyek)
- Step 2: `scripts/sync-daily.sh` (emacsclient populates → batch LaTeX export → scp → xochitl)
- Output goes to hidden buffer ` *rmpp-push-daily*`
- Success: Glass.aiff chime
- Failure: Basso.aiff + edge-tts speaks the error
- PATH is overridden per-step to include `~/miniconda3/bin` (for pymupdf/fitz)

**Garmin integration**:
- `aj/garmin-active-gear` — tracks active gear (shoes, etc.) with sport + start date
- `aj/garmin-gear-mileage` — computes cumulative km from Garmin CSV data
- `garmin-activity:` link type — on export, renders as `\includegraphics` if description is a `file:` image
- `aj/garmin-open-activity-dashboard` — generates HTML dashboard via `~/.emacs.d/scripts/garmin-activity-dashboard.py`
- Route maps become centered captioned figures in LaTeX (`#+CAPTION: *Gear: ...* --- N km`)

### Headless Batch Export

`~/Documents/remarkable-paper-pro/scripts/batch-pdf-init.el` is a minimal init for `Emacs --batch -Q` that loads only what's needed for org→PDF export:
- org, org-transclusion, org-roam (from straight's build dirs)
- lualatex via latexmk
- Custom link types (`garmin-activity:`, `elisp:`) so they don't become BROKEN LINK markers
- Smart quotes, 6 headline levels, RedViolet hyperlinks

This file must be kept in sync with `daily-config.el` and `org-config.el` for any export-affecting settings. The `sync-daily.sh` cron uses emacsclient to populate daily files (triggers hooks) then batch Emacs for the heavy LaTeX compilation.

### Package Manager

Uses **straight.el** (not package.el). Packages are cloned to `~/.emacs.d/straight/repos/` and built to `~/.emacs.d/straight/build/`. The batch init adds build dirs to `load-path` manually.

### Org-roam

- Directory: `~/Documents/new-site/content-org/`
- Database: `~/.emacs.d/org-roam.db`
- Dailies directory: `~/Documents/new-site/content-org/daily/`
- ID resolution: `org-roam-id.el` advises `org-id-find` to query `org-roam.db`, loaded automatically via `(require 'org-roam)`

### LaTeX Preview System (`org-config.el`)

There are **two parallel preview pipelines** for LaTeX in org buffers. They're orthogonal — understand which one handles which syntax before touching either.

#### 1. Built-in Org preview (`org-latex-preview`)

Handles inline/display math: `\(...\)`, `\[...\]`, `$...$`.

- Process alist entry: `luamagick` (custom, added to `org-preview-latex-process-alist`)
  - `lualatex` → `magick` (PDF → PNG)
  - **Argument order matters**: `magick -density %D %f -trim -antialias -quality 100 %O`. In ImageMagick 7, `-trim` is an *operator* and must come **after** the input file `%f`. Putting it before (as IM6 `convert` allowed) produces `"no images found for operation '-trim'"` and silently drops the output — visible as "File … wasn't produced  Please adjust 'luamagick'" in *Messages*.
- Auto-toggle on cursor enter/leave: `org-fragtog` (upstream package) with `org-fragtog-preview-delay = 0.2`.
- `:foreground 'auto` on `org-format-latex-options` so the text color follows the Emacs default face (dark mode compatible).

#### 2. Custom environment preview (`aj/latex--render-preview` + friends)

Handles `\begin{envname}...\end{envname}` blocks that org-latex-preview **ignores**: `tikzpicture`, `algorithm`, and theorem-style envs (`proof`, `theorem`, `lemma`, `definition`, `examples`, `remark`, `result`, `corollary`, `proposition`).

Key pieces (all in `elisp/org-config.el`):

| Function | Role |
|---|---|
| `aj/latex-preview-environments` | Alist of known env names → preview config (packages + docclass, or `:use-buffer-preamble t`) |
| `aj/latex--find-environment-at-point` | Returns `(ENV-NAME BEG END)` or nil. **Known quirk**: from point sitting inside `\begin{...}` itself, `re-search-backward` won't find the current env (match ends after point) — it finds the previous one. Callers must `goto-char` *past* the `\begin{...}` tag. |
| `aj/latex--render-preview` | Async: `lualatex` → `magick`, injects `\color[HTML]{...}` from `aj/latex--fg-color-command` so text matches Emacs foreground |
| `aj/latex--buffer-preview-preamble` | For theorem-style envs: reuses buffer's `#+LATEX_HEADER` lines (minus `\geometry`) so custom colors/mdframed/theorem styles render correctly |
| `aj/latex--create-overlay` | Places PNG/SVG as a display overlay; scale from `aj/latex-preview-scale` (default 0.5) |
| `aj/latex-preview-buffer` | `C-c C-x C-l` — previews both standard org fragments AND all queued environments (async, `aj/latex-preview-parallel-jobs` concurrent) |

#### Fragtog-for-environments (custom hook)

`org-fragtog` only toggles standard org fragments. To get the same mouse-in/mouse-out behavior for `\begin{...}...\end{...}` environments, there's a custom `post-command-hook`: `aj/latex-fragtog-hook`.

Design notes (learned the hard way — don't undo these):

- **Comparison by name + BEG only** (`aj/latex-fragtog--same-env-p`), never by END. Editing inside an env shifts END on every keystroke; comparing the full tuple causes a spurious "leave-and-re-enter" transition on every character typed, which thrashes the preview.
- **Uses a marker for BEG**, not a raw position. Edits elsewhere in the buffer shift positions; markers track the real location across the preview-delay timer.
- **Timer goto-char jumps past `\begin{envname}`**, not to BEG itself. `re-search-backward` would otherwise find the *previous* matching env (its match would extend past point).
- **Guard against re-render race**: when the timer fires, it checks whether the user's *current* point is inside the same env (via `aj/latex--find-environment-at-point`). If the user stepped back in during the delay, skip re-render. The guard must check the user's point, **not** the `goto-char`'d position — those are different.
- **Initial render on buffer open**: `aj/latex-preview-buffer-on-open` (hooked to `org-mode-hook`, runs on an idle timer so it doesn't block file open). Without this, environments show as source until first toggle.

#### PDF viewer

`C-c C-e l o` opens exported PDFs in `sioyek` via `(add-to-list 'org-file-apps '("\\.pdf\\'" . "sioyek %s"))`. There used to be a Chrome entry above this in the same file — removed. If a new entry gets prepended and takes priority, inspect `org-file-apps` via `emacsclient --eval` to find the offender.
