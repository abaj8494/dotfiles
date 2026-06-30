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
| `C-c d r G` | Push the priority heading **at point** to the Tasks calendar (red all-day) |
| `C-c d r g` | Sweep **all** priority headings in the daily to the Tasks calendar |
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

**Google Calendar push** (`org-config.el`, the gcal section):
- Priority headings (`[#A-C]`) in a daily push to the dedicated **Tasks** calendar (`aj/gcal-id-tasks`) as **red all-day events** (colorId 11). org-gcal has no native colour support, so a contained `cl-letf` advice on `org-gcal--post-event` (`aj/gcal--inject-color-advice`) injects `colorId` into the POST JSON — *not* an edit to the straight checkout (which is clobbered on update). (Was the shared **J** calendar before the Tasks split; `aj/gcal-hide-done-chore` still recognises legacy J-tagged events so completing one off an old daily deletes it.)
- `aj/gcal-push-chore-at-point` (`C-c d r G`) pushes the heading at point; `aj/gcal-sweep-daily-chores` (`C-c d r g`) sweeps the whole daily. The sweep matches any `[#A-C]` heading that is `TODO`/`WAIT` **or keyword-less** (so a plain `*** [#B] NSU Winter` is scheduled without becoming a carried-forward chore), and excludes `DONE`/`CANCEL` and the `* Capture` section (those are hand-scheduled via `C-c C-s`).
- org-gcal-post-at-point is **async** (returns a deferred); the sweep chains posts **sequentially** (`aj/gcal--sweep-chain`) so concurrent entry-id/ETag writebacks don't race.
- Idempotency via `aj/gcal--needs-push-p` keys off a `:gcal-synced-date:` property (written by `aj/gcal--stamp-synced-date` in the post's success callback), **not** `SCHEDULED`. An item re-pushes when it has no `entry-id`, no `gcal-synced-date`, or a `gcal-synced-date` that differs from the daily's date; a match is skipped. **Why not SCHEDULED**: the recurring carry-forward (`daily-recurring.el`) copies the `:PROPERTIES:` drawer (incl. `entry-id`/`ETag`) verbatim while the sweep's own `org-schedule` re-anchors `SCHEDULED` to today *before* the move PATCH lands — so a SCHEDULED-based check saw "today == today" and skipped, stranding the event on the previous day. `gcal-synced-date` records what date the event actually sits on; carry-forward inherits the OLD date → mismatch → forced move. (Pre-existing pushed items have no `gcal-synced-date` yet, so they re-sync once on the next sweep.)
- `aj/gcal-maybe-sweep-on-open` (hooked into `aj/daily-file-open-hook`) auto-sweeps on opening **today's or a future** daily, deferred to a 1s idle timer; past dailies are never auto-swept, and credentials load (possibly prompting once) only when something is actually pending. Toggle with `aj/gcal-auto-sweep-on-open`.
- **Loopback-pinentry / token-decrypt gotcha**: org-gcal reads its refresh token by decrypting `oauth2-auto.plist` (plstore) on **every** token fetch — its upstream plstore cache is disabled (`(or nil …)` in `oauth2-auto--plstore-read`). Emacs uses **loopback** pinentry (`epa-pinentry-mode` = loopback), so that decrypt's passphrase prompt must reach the minibuffer. From a **deferred/process-filter or timer callback the minibuffer is unusable**, so the decrypt dies with `epg-error "Can't decrypt" "Exit"` — exactly the failure mode the capture-finalize prewarm (below) was built to dodge. Fix: `aj/gcal-prewarm-token-cache` does one synchronous `oauth2-auto--plstore-read` from interactive context; gpg-agent then caches the unlocked key (`max-cache-ttl 86400` = 24h) and serves it to the async posts with no prompt. It's called up front in `aj/gcal-sweep-daily-chores`, `aj/gcal-push-chore-at-point`, `aj/gcal-hide-done-chore`, and `aj/gcal-maybe-sweep-on-open` — the last warms in the **find-file hook**, not the idle timer, so the prompt lands cleanly. `aj/gcal-load-credentials` alone does **not** suffice: it's a no-op once `aj/gcal-credentials-loaded` is set (which persists for the daemon's life), so it does no decrypt and never re-warms a cold agent.
- The carry-forward scan (`aj/get-overdue-recurring-tasks`, daily-recurring.el) is **state-aware, most-recent-first**: the newest occurrence of each `(parent . heading)` decides its fate, so a chore completed yesterday isn't resurrected from a stale older daily.
- **Hide-on-done** (`aj/gcal-hide-done-chore`, on `org-after-todo-state-change-hook`): marking a J-managed chore `DONE`/`CANCEL` **deletes its calendar event** so the HA kiosk card only shows outstanding chores. It deletes via `org-gcal--delete-event` + a manual `:org-gcal:`-drawer/identity strip (`aj/gcal--strip-event-at-marker`), **deliberately not** `org-gcal-delete-at-point` — the latter ends in `org-gcal--maybe-remove-entry`, which with `org-gcal-remove-api-cancelled-events t` would delete the whole org subtree (and its async `:finally` defeats any `let`-binding). The org heading + its DONE record are kept. No-op when `aj/daily-hook-suppress` is set, so the carry-forward source-CANCEL doesn't delete an event that's about to be MOVED forward.
  - **Hook-ordering requirement (subtle, cost real deletions)**: `aj/gcal-hide-done-chore` reads `entry-id`/`calendar-id` **at point**, so it must run while point is still on the chore. It's pinned to run **first** on `org-after-todo-state-change-hook` via a negative depth (`(add-hook … #'aj/gcal-hide-done-chore -50)`). At the default depth it ran *after* `my/org-roam-copy-todo-to-today` (the DONE-copy lambda for `* Recurring`/`* Capture`), which fires a nested `org-roam-dailies--capture` and **leaked point onto the `* Tasks` heading** — so hide-done read a nil `entry-id` there, its inner `when` failed, and the calendar event was **silently never deleted** (no error, no message; completed chores lingered on the J calendar). Two independent fixes guard this now: (1) the negative depth, and (2) `my/org-roam-copy-todo-to-today` was made leak-free — it captures the source buffer/point/marker up front and restores them in an `unwind-protect`, instead of relying on `save-window-excursion` (which restores only the window config). Fixing that leak also un-broke the function's own cross-file copy: the old code compared `today-file` against the *leaked* `(buffer-file-name)` (today's), so it always saw today-vs-today and skipped the refile; it now compares against the captured `source-file`, so completing a recurring item in a *past* daily again copies it into today's `* Tasks`.
  - **Backlog reality**: because this bug ran for a while, many `DONE`/`CANCEL` chores across old dailies still carry live `entry-id`s. A one-off cleanup must **dedupe by event id and act only on each id's newest occurrence** — carry-forward reuses one Google event id across days (the event MOVES forward), so an id that's `CANCEL` on old days but `TODO` on today's daily is still active and must NOT be deleted. Delete with `etag = nil` (unconditional; avoids the HTTP-412 stale-etag branch of `org-gcal--delete-event`, the only path that rewrites the org buffer) so no daily files get mtime-bumped (which would retrigger the reMarkable sync). HTTP 410 on delete = event already gone; harmless.

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
