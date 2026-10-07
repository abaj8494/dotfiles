#!/usr/bin/env bash
# sesh, ported to herdr.
#
# sesh only speaks tmux (`sesh connect` shells out to tmux new-session /
# switch-client), so under herdr the connect half has to be re-implemented on
# top of the `herdr <noun> <verb>` socket API. sesh.toml stays the single
# source of truth: names/paths/startup_command/windows come from
# `sesh list -c -j`, and the handful of things sesh doesn't export
# ([default_session], [[window]] startup_script, [[wildcard]] rules) are read
# out of the TOML with a small awk pass.
#
# Vocabulary map (sesh/tmux -> herdr):  session -> workspace,  window -> tab.
#
#   sesh.sh picker           fzf picker, tokyo-night themed  (prefix+shift+K)
#   sesh.sh pick <name>      what the picker does with a selection (see below)
#   sesh.sh connect <name>   focus that workspace, else create it from sesh.toml
#   sesh.sh last             jump back to the previously-focused workspace
#   sesh.sh startup          pre-create the always-open workspaces, unfocused
#   sesh.sh list [mode]      rows for the picker (all|workspaces|configs|zoxide)
#   sesh.sh preview <row>    preview pane for the picker
#   sesh.sh kill <name>      close a workspace
#
# Startup commands are typed into the pane's interactive shell (`herdr pane
# run` is send-keys, not exec), so shell aliases/functions like `l` and `lc`
# and `~` expansion work exactly as they do under tmux.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/_herdr.sh"       # PATH + herdr_wait_prompt/herdr_run

SESH_TOML="${SESH_TOML:-$HOME/.config/sesh/sesh.toml}"
LAST_FILE="$HOME/.config/herdr/.last-workspace"

# Nerd-font glyph sesh uses for tmux sessions; reused here for live workspaces
# so the picker rows line up with what `sesh list --icons` emits.
ICON_WS=$'\xee\xaf\x88'

# Workspaces pre-created by `startup` (mirrors sesh/scripts/startup.sh).
STARTUP_SESSIONS=(monitoring remarkable flashcards configs Finances jobsync uni)

die() { printf 'sesh.sh: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- herdr API --

ws_json() { herdr workspace list 2>/dev/null; }

# label -> workspace_id (empty when no such workspace)
ws_id() {
  ws_json | jq -r --arg l "$1" '.result.workspaces[]? | select(.label==$l) | .workspace_id' | head -1
}

focused_label() {
  ws_json | jq -r '.result.workspaces[]? | select(.focused==true) | .label' | head -1
}

ws_cwd() { # workspace_id -> cwd of its first pane
  herdr pane list 2>/dev/null |
    jq -r --arg w "$1" '.result.panes[]? | select(.workspace_id==$w) | .cwd' | head -1
}

remember_last() {
  local cur; cur=$(focused_label)
  [ -n "$cur" ] && [ "$cur" != "${1:-}" ] && printf '%s\n' "$cur" >"$LAST_FILE"
  return 0
}

# ----------------------------------------------------------- sesh.toml bits --

# `[default_session] startup_command` — sesh applies this to any session that
# doesn't set its own and hasn't opted out with disable_startup_command.
default_startup() {
  awk '
    /^\[/ { sect=$0 }
    sect=="[default_session]" && /^[[:space:]]*startup_command[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, ""); gsub(/^["'\'']|["'\'']$/, ""); print; exit
    }
  ' "$SESH_TOML"
}

# window name -> its [[window]] startup_script
window_script() {
  awk -v want="$1" '
    function val(s) { sub(/^[^=]*=[[:space:]]*/, "", s); gsub(/^["'\'']|["'\'']$/, "", s); return s }
    /^\[\[window\]\]/ { if (inw && nm==want) { print sc; hit=1; exit } inw=1; nm=""; sc=""; next }
    /^\[/            { if (inw && nm==want) { print sc; hit=1; exit } inw=0 }
    inw && /^[[:space:]]*name[[:space:]]*=/           { nm=val($0) }
    inw && /^[[:space:]]*startup_script[[:space:]]*=/ { sc=val($0) }
    END { if (!hit && inw && nm==want) print sc }
  ' "$SESH_TOML"
}

# [[wildcard]] blocks -> pattern<TAB>startup_command<TAB>disable<TAB>win1,win2
# (commented-out blocks start with "# " and never match the anchored patterns)
wildcards() {
  awk '
    function val(s) { sub(/^[^=]*=[[:space:]]*/, "", s); gsub(/^["'\'']|["'\'']$/, "", s); return s }
    function flush() { if (pat!="") printf "%s\t%s\t%s\t%s\n", pat, sc, dis, wins; pat=""; sc=""; dis=""; wins="" }
    /^\[\[wildcard\]\]/ { flush(); inw=1; next }
    /^\[/               { flush(); inw=0 }
    inw && /^[[:space:]]*pattern[[:space:]]*=/                  { pat=val($0) }
    inw && /^[[:space:]]*startup_command[[:space:]]*=/          { sc=val($0) }
    inw && /^[[:space:]]*disable_startup_command[[:space:]]*=/  { dis=val($0) }
    inw && /^[[:space:]]*windows[[:space:]]*=/ {
      s=$0; sub(/^[^=]*=[[:space:]]*\[/, "", s); sub(/\].*$/, "", s); gsub(/["[:space:]]/, "", s); wins=s
    }
    END { flush() }
  ' "$SESH_TOML"
}

expand_tilde() { printf '%s' "${1/#\~/$HOME}"; }

# Some sesh startup_commands are tmux layout scripts (monitoring_prep.sh,
# remarkable_prep.sh) that call `tmux send-keys`/`tmux split-window` directly.
# Running one from a herdr pane doesn't fail — it reaches across to the real
# tmux server and rearranges *that*, which is worse. So: if the command's first
# token is a script that invokes tmux, swap in scripts/prep/<name>.sh (a herdr
# API port of the same layout) and, when there isn't one, drop the command
# rather than let it loose.
#
# The test deliberately inspects the *file*, not the command string — the "tmux
# config" session's startup_command is `nvim tmux.conf`, which must survive.
translate_startup() {
  local cmd="$1" first path base port
  [ -n "$cmd" ] || return 0

  first=${cmd%% *}
  path=$(expand_tilde "$first")
  if [ ! -f "$path" ] || ! grep -qE '(^|[^[:alnum:]_/])tmux[[:space:]]' "$path"; then
    printf '%s' "$cmd"
    return 0
  fi

  base=$(basename "$path"); base=${base%.sh}; base=${base%_prep}
  port="$SCRIPT_DIR/prep/$base.sh"
  if [ -x "$port" ]; then
    printf '%s' "$port"
  else
    printf 'sesh.sh: skipping tmux-only startup command %s (no herdr port at %s)\n' \
      "$path" "$port" >&2
  fi
}

# --------------------------------------------------------------- connecting --

# label path startup windows_csv focus(yes|no)
spawn_workspace() {
  local label="$1" path="$2" startup="$3" windows="$4" focus="$5"
  local focus_flag=--focus
  [ "$focus" = no ] && focus_flag=--no-focus

  # herdr silently falls back to $HOME for a missing --cwd ("saved pane cwd does
  # not exist"); a stale sesh.toml entry should say so instead of quietly
  # opening a workspace in the wrong place.
  [ -d "$path" ] || die "'$label': path does not exist: $path"

  local out ws pane
  out=$(herdr workspace create --cwd "$path" --label "$label" "$focus_flag") \
    || die "workspace create failed for '$label'"
  ws=$(printf '%s' "$out" | jq -r '.result.workspace.workspace_id')
  pane=$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id')

  [ -n "$startup" ] && herdr_run "$pane" "$startup"

  # sesh `windows = [...]` -> one herdr tab per entry, each running the
  # matching [[window]] startup_script.
  local w tout tpane script
  IFS=, read -r -a _wins <<<"$windows"
  for w in ${_wins[@]+"${_wins[@]}"}; do
    [ -z "$w" ] && continue
    tout=$(herdr tab create --workspace "$ws" --cwd "$path" --label "$w" --no-focus) || continue
    tpane=$(printf '%s' "$tout" | jq -r '.result.root_pane.pane_id')
    script=$(window_script "$w")
    if [ -n "$script" ] && [ -n "$tpane" ] && [ "$tpane" != null ]; then
      # herdr_run waits on the prompt actually rendering rather than sleeping a
      # flat SPAWN_SETTLE — same guarantee, and it stops charging every extra
      # window a fixed 0.6s whether or not the shell was already up.
      herdr_run "$tpane" "$script"
    fi
  done
}

# name-or-path, focus(yes|no)
connect() {
  local target="$1" focus="${2:-yes}"

  local id; id=$(ws_id "$target")
  if [ -n "$id" ]; then
    [ "$focus" = no ] && return 0
    remember_last "$target"
    herdr workspace focus "$id" >/dev/null
    return 0
  fi

  local json path startup windows disabled label
  json=$(sesh list -c -j 2>/dev/null | jq -c --arg n "$target" 'map(select(.Name==$n)) | .[0] // empty')

  if [ -n "$json" ]; then
    label="$target"
    path=$(jq -r '.Path' <<<"$json")
    startup=$(jq -r '.StartupCommand' <<<"$json")
    windows=$(jq -r '(.WindowNames // []) | join(",")' <<<"$json")
    disabled=$(jq -r '.DisableStartupCommand' <<<"$json")
  else
    # Not a configured session: treat it as a directory, the way sesh treats a
    # zoxide/fd hit — basename becomes the name, [[wildcard]] rules apply.
    path=$(expand_tilde "$target")
    [ -d "$path" ] || die "no sesh session or directory named '$target'"
    path=$(cd "$path" && pwd)
    label=$(basename "$path")
    startup=""; windows=""; disabled=false
    local pat sc dis wins
    while IFS=$'\t' read -r pat sc dis wins; do
      pat=$(expand_tilde "$pat")
      # shellcheck disable=SC2254 -- unquoted on purpose: pattern is a glob
      case "$path" in
        $pat) startup="$sc"; windows="$wins"; [ "$dis" = true ] && disabled=true ;;
      esac
    done < <(wildcards)
    id=$(ws_id "$label")
    if [ -n "$id" ]; then
      [ "$focus" = no ] && return 0
      remember_last "$label"
      herdr workspace focus "$id" >/dev/null
      return 0
    fi
  fi

  if [ "$disabled" = true ]; then
    startup=""
  elif [ -z "$startup" ] || [ "$startup" = null ]; then
    startup=$(default_startup)
  fi
  startup=$(translate_startup "$startup")

  [ "$focus" = yes ] && remember_last "$label"
  spawn_workspace "$label" "$path" "$startup" "$windows" "$focus"
}

cmd_last() {
  [ -f "$LAST_FILE" ] || exit 0
  local target; target=$(<"$LAST_FILE")
  [ -n "$target" ] || exit 0
  connect "$target"
}

cmd_startup() {
  local name
  for name in "${STARTUP_SESSIONS[@]}"; do
    [ -n "$(ws_id "$name")" ] && continue
    # Subshell: one session with a stale path in sesh.toml must not take the
    # rest of the pre-warm down with it (connect exits on a missing path).
    ( connect "$name" no ) || true
  done
  ws_json | jq -r '.result.workspaces[]? | .label'
}

cmd_kill() {
  local id; id=$(ws_id "$1")
  [ -n "$id" ] && herdr workspace close "$id" >/dev/null
}

# ------------------------------------------------------------------ picker ---

# Eat the icon and ALL spaces after it: an agent-less workspace row is
# "ICON␣␣label" (the status mark degrades to a space), and stripping just one
# space handed connect/preview a name with a leading blank — the picker's
# "picked it and nothing happened" failure.
strip_icon() { sed -E 's/^[^ ]+ +//' <<<"$1"; }

list_rows() {
  local mode="${1:-all}"
  case "$mode" in
    workspaces)
      # Live workspaces carry herdr's agent state, which is the one thing this
      # picker knows that sesh's never could. The status glyph is glued to the
      # icon (no space) so strip_icon still yields a clean name.
      ws_json | jq -r '.result.workspaces[]? | [.label, (.agent_status // "")] | @tsv' |
        while IFS=$'\t' read -r label status; do
          case "$status" in
            working)          mark=$'\033[33m\033[39m' ;;   # amber: agent busy
            blocked|waiting)  mark=$'\033[31m\033[39m' ;;   # red: wants you
            idle)             mark=$'\033[32m\033[39m' ;;   # green: agent done
            *)                mark=' ' ;;
          esac
          printf '\033[34m%s\033[39m%s %s\n' "$ICON_WS" "$mark" "$label"
        done
      ;;
    configs) sesh list -c --icons ;;
    zoxide)  sesh list -z --icons ;;
    all)
      local labels
      labels=$(ws_json | jq -r '.result.workspaces[]? | .label')
      list_rows workspaces
      # hide entries that already exist as a live workspace (sesh -d). One awk
      # over the whole stream — a grep+sed pair per row was ~560 forks for a
      # 277-entry zoxide list, and the fzf popup wore all of it as startup lag.
      # (Labels ride in via the environment: BSD awk -v chokes on newlines.)
      { sesh list -c --icons; sesh list -z --icons; } |
        LIVE_LABELS="$labels" awk '
          BEGIN { n = split(ENVIRON["LIVE_LABELS"], a, "\n"); for (i = 1; i <= n; i++) live[a[i]] = 1 }
          { name = $0; sub(/^[^ ]+ +/, "", name); if (!(name in live)) print }
        '
      ;;
  esac
}

cmd_preview() {
  local name; name=$(strip_icon "$*")
  local id; id=$(ws_id "$name")
  if [ -n "$id" ]; then
    printf '\033[34m%s\033[39m  %s\n\n' "$ICON_WS" "$name"
    herdr pane list 2>/dev/null | jq -r --arg w "$id" '
      .result.panes[]? | select(.workspace_id==$w)
      | "  \(.pane_id)  \(.terminal_title_stripped // "shell")   \(.cwd)"'
    local dir; dir=$(ws_cwd "$id")
    [ -n "$dir" ] && { printf '\n'; eza -lah --git --group-directories-first --icons=auto --color=always "$dir" 2>/dev/null; }
    return 0
  fi
  # sesh's own preview (honours preview_command). It errors out when a
  # preview_command points at something stale, so fall back to a listing of
  # the session path rather than showing an empty pane.
  local out; out=$(sesh preview "$name" 2>/dev/null)
  if [ -n "$out" ]; then printf '%s\n' "$out"; return 0; fi

  local dir; dir=$(expand_tilde "$name")
  [ -d "$dir" ] || dir=$(sesh list -c -j 2>/dev/null | jq -r --arg n "$name" 'map(select(.Name==$n)) | .[0].Path // empty')
  [ -n "$dir" ] && [ -d "$dir" ] &&
    eza -lah --git --group-directories-first --icons=auto --color=always "$dir"
}

# kanagawa, matching [theme] name in config.toml. Deliberately NOT the
# tokyo-night palette of sesh/scripts/picker.sh — under tmux the picker is
# blue/violet, under herdr it's ink-wash, and you can tell which multiplexer
# popped it up without reading anything.
THEME='bg:#1F1F28,bg+:#2D4F67,fg:#DCD7BA,fg+:#DCD7BA,hl:#7E9CD8,hl+:#957FB8,info:#727169,prompt:#98BB6C,pointer:#E46876,marker:#E6C384,spinner:#7AA89F,header:#727169,border:#54546D,label:#727169,query:#DCD7BA,separator:#54546D'

cmd_picker() {
  local self="$0" picked
  picked=$("$self" list all | fzf \
    --no-sort --ansi \
    --height=100% \
    --border=rounded \
    --border-label=' sesh ' \
    --border-label-pos=3 \
    --preview-window='right:55%,border-left' \
    --preview="$self preview {}" \
    --prompt='⚡  ' \
    --header='  ^a all  ^s workspaces  ^g configs  ^x zoxide  ^f find  ^e edit  ^d close' \
    --color="$THEME" \
    --bind='tab:down,btab:up' \
    --bind="ctrl-a:change-prompt(⚡  )+reload($self list all)" \
    --bind="ctrl-s:change-prompt(🐄  )+reload($self list workspaces)" \
    --bind="ctrl-g:change-prompt(⚙️  )+reload($self list configs)" \
    --bind="ctrl-x:change-prompt(📁  )+reload($self list zoxide)" \
    --bind='ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
    --bind="ctrl-d:execute-silent($self kill {2..})+change-prompt(⚡  )+reload($self list all)" \
    --bind="ctrl-e:execute(nvim +/'name = \"{2..}\"' $SESH_TOML)")

  [ -z "$picked" ] && exit 0
  connect_picked "$(strip_icon "$picked")"
}

# What the picker does with a pick. The two cases are not alike:
#
#   already live  -> `workspace focus` is a 10ms socket call. Do it right here.
#                    Detaching this is what broke "pick a live workspace and
#                    nothing happens": the popup's process group is killed on
#                    exit, taking the not-yet-detached child with it.
#   not yet live  -> creating costs ~2s, nearly all of it inside
#                    herdr_wait_prompt waiting for p10k to render before the
#                    startup command can be typed (send-keys needs a live
#                    shell). tmux never shows this because `sesh connect`
#                    returns immediately. Detach it so the popup closes now;
#                    the workspace appears and takes focus ~50ms later.
connect_picked() {
  local target="$1" id
  id=$(ws_id "$target")
  if [ -n "$id" ]; then
    remember_last "$target"
    herdr workspace focus "$id" >/dev/null
    exit 0
  fi
  herdr_detach "$0" connect "$target"
  exit 0
}

# tmux: bind-key "K" display-popup -E -w 40% "sesh connect $(sesh list -i | gum filter …)"
cmd_gum() {
  local picked
  picked=$("$0" list all | gum filter --limit 1 --placeholder 'Pick a sesh' --prompt='⚡ ')
  [ -z "$picked" ] && exit 0
  connect_picked "$(strip_icon "$picked")"
}

# -------------------------------------------------------------------- main ---

case "${1:-picker}" in
  picker)  cmd_picker ;;
  gum)     cmd_gum ;;
  pick)    shift; [ $# -ge 1 ] || die "pick needs a name"; connect_picked "$*" ;;
  connect) shift; [ $# -ge 1 ] || die "connect needs a name"; connect "$*" ;;
  last)    cmd_last ;;
  startup) cmd_startup ;;
  list)    shift; list_rows "${1:-all}" ;;
  preview) shift; cmd_preview "$*" ;;
  kill)    shift; [ $# -ge 1 ] && cmd_kill "$*" ;;
  *)       die "unknown command: $1" ;;
esac
