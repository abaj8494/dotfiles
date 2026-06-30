#!/usr/bin/env bash
# sesh picker (kali) — Rosé Pine theme. Bound to Prefix+V from tmux.conf.
#
# Filter hotkeys inside the picker:
#   ^a all sources   ^t tmux only   ^g configs   ^x zoxide   ^f find dirs
#   ^e edit entry in $EDITOR   ^d kill selected tmux session
#
# tmux popups inherit a minimal PATH; set a full one so sesh/fzf-tmux/fd resolve.
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
EDITOR="${EDITOR:-vim}"

# Intentionally not `set -e`: fzf exits 130 on ESC/Ctrl-C (normal cancel).

# Rosé Pine
THEME='bg:#191724,bg+:#26233a,fg:#908caa,fg+:#e0def4,hl:#9ccfd8,hl+:#c4a7e7,info:#6e6a86,prompt:#31748f,pointer:#eb6f92,marker:#f6c177,spinner:#9ccfd8,header:#6e6a86,border:#403d52,label:#6e6a86,query:#e0def4,separator:#403d52'

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
  --bind="ctrl-e:execute($EDITOR +/'name = \"{2..}\"' ~/.config/sesh/sesh.toml)")

[ -z "$picked" ] && exit 0   # user hit ESC / Ctrl-C
name=$(printf '%s' "$picked" | sed -E 's/^[^ ]+ //')   # strip leading icon
exec sesh connect "$name"
