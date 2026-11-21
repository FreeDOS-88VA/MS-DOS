#!/bin/bash
# Run under xvfb-run on a dedicated display, with the J0.2 D88 as argument 2.
# Arguments: vaeg executable, D88 (scratch copy), ROM directory, output directory.
set -euo pipefail
vaeg=$1; disk=$2; roms=$3; out=$4
mkdir -p "$out"
SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy "$vaeg" --model va2 --no-cfg --no-bkupmem \
  --roms "$roms" --fdd1 "$disk" >"$out/run.log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" || true' EXIT
win=$(timeout 15 xdotool search --sync --onlyvisible --pid "$pid" | head -1)
xdotool windowfocus --sync "$win"
sleep 6
key() { xdotool keydown "$1"; sleep .12; xdotool keyup "$1"; sleep .18; }
shot() { sleep .4; import -window "$win" "$out/$1.png"; }
key shift+v; key shift+e; key shift+r; key Return
sleep 2
key shift+x; key shift+y; shot cancel-before
key ctrl+x; shot cancel-after
key Escape; key shift+u; shot cancel-recall
key ctrl+c; shot break-after
key shift+v; key shift+e; key shift+r; key Return; shot break-recovery
