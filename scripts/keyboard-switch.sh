#!/usr/bin/env bash
# keyboard-switch.sh — Swap aerospace preset, karabiner profile, and macOS keyboard layout
# in lockstep with the ZSA Moonlander plug state. Driven by ~/.hammerspoon/init.lua.
#
# Usage: keyboard-switch.sh {moonlander|laptop}

set -euo pipefail

mode="${1:-}"

case "$mode" in
  moonlander)
    aerospace_preset='qwerty'
    karabiner_profile='debug'
    layout='Australian'
    ;;
  laptop)
    aerospace_preset='dvorak'
    karabiner_profile='bajaj'
    layout='dvorak-nude'
    ;;
  *)
    echo "usage: $0 {moonlander|laptop}" >&2
    exit 2
    ;;
esac

aerospace_config="$HOME/.config/aerospace/aerospace.toml"
aerospace_bin='/opt/homebrew/bin/aerospace'
karabiner_cli='/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli'
keyboard_switcher="$HOME/.local/bin/keyboardSwitcher"

# 1. Aerospace: rewrite preset line through the stow symlink (cp follows symlinks,
# so the link stays intact and the change lands in the dotfiles repo), then reload.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
sed "s/^key-mapping\.preset = '[^']*'/key-mapping.preset = '${aerospace_preset}'/" \
  "$aerospace_config" > "$tmp"
cp "$tmp" "$aerospace_config"
"$aerospace_bin" reload-config

# 2. Karabiner profile
"$karabiner_cli" --select-profile "$karabiner_profile"

# 3. macOS keyboard layout
"$keyboard_switcher" select "$layout"

echo "[keyboard-switch] mode=${mode} aerospace=${aerospace_preset} karabiner=${karabiner_profile} layout=${layout}"
