# dotfiles — orientation for Claude

Personal dotfiles repo, managed with **GNU Stow**. Each top-level directory is a stow *package*; its internal tree mirrors the path from `$HOME` where files should land.

- Remote: `git@github.com:abaj8494/dotfiles.git`
- Default working branch: `macos`
- Platform: macOS (Darwin)

## Stow convention

```
~/dotfiles/<package>/<path-from-$HOME>/<file>   →   $HOME/<path-from-$HOME>/<file>
```

Examples already in the repo:

| Package       | Source in repo                                         | Symlink target                                  |
|---------------|--------------------------------------------------------|-------------------------------------------------|
| `tmux`        | `tmux/.config/tmux/tmux.conf`                          | `~/.config/tmux/tmux.conf`                      |
| `zsh`         | `zsh/.config/zsh/.zshrc`                               | `~/.config/zsh/.zshrc`                          |
| `nvim`        | `nvim/.config/nvim/init.lua`                           | `~/.config/nvim/init.lua`                       |
| `sesh`        | `sesh/.config/sesh/sesh.toml`                          | `~/.config/sesh/sesh.toml`                      |
| `television`  | `television/.config/television/config.toml`            | `~/.config/television/config.toml`              |
| `karabiner`   | `karabiner/.config/karabiner/karabiner.json`           | `~/.config/karabiner/karabiner.json`            |
| `sioyek`      | `sioyek/Library/Application Support/sioyek/…`          | `~/Library/Application Support/sioyek/…`        |
| `watchdog`    | `watchdog/Library/LaunchAgents/com.*.plist`            | `~/Library/LaunchAgents/com.*.plist`            |

Stow folds whole directories where possible — so `~/.config/tmux` is itself the symlink (not each individual file inside). If you later add unrelated files directly under `~/.config/tmux/`, they'd end up tracked in the repo; keep that in mind when extending a package.

## Operating on the repo

```bash
# install / re-link a package (idempotent)
cd ~/dotfiles && stow <package>

# remove symlinks for a package without touching the source tree
cd ~/dotfiles && stow -D <package>

# install every package in one shot
cd ~/dotfiles && stow */
```

When **adding** a config:

1. Create the package dir and mirror the target path. E.g. for a config that should live at `~/.config/foo/bar.toml`:
   ```bash
   mkdir -p ~/dotfiles/foo/.config/foo
   mv ~/.config/foo/bar.toml ~/dotfiles/foo/.config/foo/bar.toml
   cd ~/dotfiles && stow foo
   ```
2. Verify with `readlink ~/.config/foo` — should resolve into `~/dotfiles/foo/…`.

## Package notes

- **`sesh`** — [joshmedeski/sesh](https://github.com/joshmedeski/sesh) tmux session manager. `sesh.toml` declares named sessions and `[[wildcard]]` patterns; `[[window]]` blocks are named window presets reusable via `windows = [...]`. Helper scripts in `sesh/.config/sesh/scripts/` (e.g. `picker.sh`, `remarkable_prep.sh`, `startup.sh`, `monitoring_prep.sh`). `startup.sh` pre-creates the seven always-open sessions (monitoring, remarkable, flashcards, configs, Finances, jobsync, uni) — it runs from `tmux.conf` via `run-shell -b` after TPM, with a 3s delay to let continuum finish. The default `startup_command` is `nvim '+Telescope find_files'`.
  - **`startup_script` gotcha**: sesh honors `startup_script` only on `[[window]]` blocks, **not** on `[[session]]`. For multi-pane session layouts, set `startup_command` to the prep-script path — sesh send-keys that path into pane 0, the shell executes it, the script uses explicit `tmux -t SESSION:...` targets to split/send-keys, and send-keys queued at pane 0 fire after the script exits (so you can pre-type a command that runs in pane 0 once layout is built). See `monitoring_prep.sh` / `remarkable_prep.sh`.
- **`television`** — [alexpasmantier/television](https://github.com/alexpasmantier/television) fuzzy picker. Cables live at `television/.config/television/cable/*.toml` — each defines a `[source]` command, `[preview]`, `[keybindings]`, and `[actions.*]`. Custom cables here: `c-pick`, `dotfiles-pick`, `content-org`, `sesh`, `clip-pages`, `clip-files`, `tmux-sessions`.
- **`tmux`** — prefix is `C-a`. Key session bindings:
  - `Prefix+K` → gum popup sesh picker
  - `Prefix+T` → themed fzf-tmux sesh picker (calls `~/.config/sesh/scripts/picker.sh`)
  - `Prefix+C-t` → tv channel picker in a popup
  - `Prefix+C-l` → `sesh last` (jump to previously-attached sesh session)
  - `startup.sh` runs via `run-shell -b` after TPM (3s delay). Continuum auto-restore is **off** — only auto-save (every 5 min) is active. Manual restore: `Prefix+C-r`.
  - **Popup PATH gotcha**: `display-popup -E` runs commands under a stripped PATH (`~/.opencode/bin:/opt/homebrew/bin:/bin:/usr/bin`) — `~/.local/bin` is *not* included. Binaries installed there (e.g. `tv`) must be invoked by absolute path or wrapped, otherwise the popup snaps shut with a silent "command not found".
- **`zsh`** — oh-my-zsh + powerlevel10k. Note: the `z` plugin is loaded by oh-my-zsh, then `unalias z` + `eval "$(zoxide init zsh)"` replaces it with zoxide (while keeping `z` as the invocation). The old z database (`zsh/.config/zsh/.z`) was imported into zoxide via `zoxide import --from=z --merge`. Also: a `tmux()` shell function wraps the CLI so that bare `tmux` (no args, outside tmux) runs `tmux attach` first — this avoids spawning an unnamed `0` session alongside the pre-warmed sesh sessions. `tmux <args>` still passes through unchanged.
- **`watchdog`** — LaunchAgents only. Two agents:
  - `com.aayushbajaj.watchdog-serve.plist` — local watchdog dashboard server (port 9847) under launchd with `KeepAlive`. The `collect` agent (sampling every 5min) was set up outside this repo and lives as a plain file in `~/Library/LaunchAgents/com.aayushbajaj.system-health-monitor.plist`.
  - `com.aayushbajaj.daily-init.plist` — fires `scripts/daily-init.sh` at **00:00** daily to create today's org-roam daily (so it exists without the user pressing `C-c d d`). `StartCalendarInterval` fires the missed run on wake if asleep at midnight. Runs under **`/bin/zsh`** (not bash) because the script's instant-deploy step needs Full Disk Access, which launchd only grants to zsh and which propagates down the chain via shebang resolution. Load with `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.aayushbajaj.daily-init.plist`.
- **`nvim-archived-20251209/`** — snapshot of a previous nvim config, kept for reference; not meant to be stowed.
- **`stow-packages/`** — currently empty; placeholder.
- **`scripts/`** — standalone helper scripts, not a stow package per se. Referenced by absolute path (e.g. the `daily-init` LaunchAgent points at `scripts/daily-init.sh`).
  - **`daily-init.sh`** — midnight daily generator. Drives the live Emacs daemon via `(org-roam-dailies--capture (current-time) t)` (the goto path behind `C-c d d`, which runs `aj/daily-file-open-hook` for full setup), then invokes ferrari's `sync-daily.sh` (via **shebang**, never `bash <path>` — preserves the FDA responsible-process tag) for an instant reMarkable push instead of waiting for the next wake-watch tick. **Generates only when the org is absent** — re-running the goto on an existing daily would `save-buffer` and bump mtime, which the rmsync pipeline keys off (see `ferrari/CLAUDE.md` "Don't fire wake-watch on org-newer-than-pdf"). Socket discovery uses `getconf DARWIN_USER_TEMP_DIR` so it finds the daemon regardless of `$TMPDIR`.

## Not managed by stow (intentionally)

- `~/.oh-my-zsh` (managed by omz itself)
- `~/powerlevel10k` (managed by its installer)
- tmux plugins under `~/.config/tmux/plugins/` (tpm manages them)
- neovim plugins (lazy.nvim manages them; only `lazy-lock.json` is committed)
- Homebrew, conda, nvm, bun, cargo, go — installed out-of-band; only their shell init lines live in `.zshrc`
- Secrets (`JOBSYNC_API_KEY`, etc.) — currently inlined in `.zshrc` and committed; **treat with care** when forking or sharing.

## Editing while stowed

Because paths like `~/.config/<pkg>` are symlinks into this repo, any edit through the symlinked path writes back to the repo. Editing `~/.config/tmux/tmux.conf` and editing `~/dotfiles/tmux/.config/tmux/tmux.conf` are the same operation.

## Commit hygiene

- Branch is `macos`; there's long-running WIP on it (emacs config evolution, sioyek keys, etc.) — treat pre-existing unstaged changes as the user's in-progress work and do **not** sweep them into unrelated commits.
- Commits should describe the *why* succinctly. No `Co-Authored-By` trailer (user preference).
