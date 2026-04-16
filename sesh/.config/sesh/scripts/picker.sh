#!/usr/bin/env bash
# sesh picker styled to match the tokyo-night status bar.
# Bound to `Prefix+T` from tmux.conf.
#
# Palette (tokyo-night "night" theme, matched to the tmux status bar):
#   bg        #1A1B26  (status bar background)
#   bg+       #2A2F41  (selected row -- darker grey accent)
#   border    #414868  (lighter grey -- matches status-bar separators)
#   fg        #a9b1d6  text
#   accent    #7aa2f7  blue (hl)
#
# Filter hotkeys inside the picker:
#   ^a  all sesh sources (default)
#   ^t  tmux sessions only
#   ^g  configs only
#   ^x  zoxide only
#   ^f  fd -- fuzzy-pick any dir under $HOME
#   ^e  edit the selected session's entry in sesh.toml in nvim
#   ^d  kill the selected tmux session (then reload)

# Intentionally not `set -e`: fzf exits 130 when the user hits ESC/Ctrl-C,
# which is a normal cancellation, not an error we want to propagate.

THEME='bg:#1A1B26,bg+:#2A2F41,fg:#a9b1d6,fg+:#c0caf5,hl:#7aa2f7,hl+:#bb9af7,info:#787c99,prompt:#7dcfff,pointer:#f7768e,marker:#e0af68,spinner:#73daca,header:#787c99,border:#414868,label:#787c99,query:#a9b1d6,separator:#414868'

picked=$(sesh list --icons | fzf-tmux -p 80%,70% \
  --no-sort --ansi \
  --border=rounded \
  --border-label=' sesh ' \
  --border-label-pos=3 \
  --preview-window='right:55%,border-left' \
  --preview='sesh preview {}' \
  --prompt='⚡  ' \
  --header='  ^a all  ^t tmux  ^g configs  ^x zoxide  ^f find  ^e edit  ^d kill' \
  --color="$THEME" \
  --bind='tab:down,btab:up' \
  --bind='ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)' \
  --bind='ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)' \
  --bind='ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' \
  --bind='ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)' \
  --bind='ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
  --bind='ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡  )+reload(sesh list --icons)' \
  --bind="ctrl-e:execute(nvim +/'name = \"{2..}\"' ~/.config/sesh/sesh.toml)")

[ -z "$picked" ] && exit 0   # user hit ESC / Ctrl-C

# Strip the leading icon + space that --icons adds so `sesh connect` gets a clean name.
name=$(printf '%s' "$picked" | sed -E 's/^[^ ]+ //')

exec sesh connect "$name"
