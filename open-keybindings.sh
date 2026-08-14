#!/bin/bash

set -euo pipefail

bindings_file="${1:-$HOME/.config/hypr/bindings.lua}"
target_line=1

if [[ -r $bindings_file ]]; then
  target_line=$(awk '
    {
      line = tolower($0)
      matches_btop = line ~ /btop/
      matches_activity = line ~ /"activity"/
      matches_shortcut = line ~ /super[[:space:]]*\+[[:space:]]*ctrl[[:space:]]*\+[[:space:]]*t/
      if (matches_btop || matches_activity || matches_shortcut) {
        print NR
        exit
      }
    }
  ' "$bindings_file")

  if [[ -z $target_line ]]; then
    target_line=$(awk 'END { print NR + 1 }' "$bindings_file")
  fi
fi

if command -v nvim >/dev/null 2>&1; then
  exec omarchy-launch-tui --app-id=org.omarchy.btop-keybindings \
    nvim "+$target_line" "$bindings_file"
fi

exec omarchy-launch-config-editor "$bindings_file"
