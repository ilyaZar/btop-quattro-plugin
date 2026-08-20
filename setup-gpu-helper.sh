#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target_dir=${XDG_DATA_HOME:-"$HOME/.local/share"}/ilyazar-btop
target=$target_dir/gpu-telemetry

mkdir -p "$target_dir"
cc -O2 -std=c11 -Wall -Wextra -Werror \
  "$script_dir/gpu-telemetry.c" -ldl -o "$target"

needs_perfmon=false
[ -d /sys/bus/event_source/devices/i915 ] && needs_perfmon=true

if "$needs_perfmon"; then
  sudo setcap cap_perfmon=ep "$target"
fi

printf 'installed %s\n' "$target"
getcap "$target" 2>/dev/null || true
