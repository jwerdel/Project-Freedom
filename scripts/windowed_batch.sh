#!/usr/bin/env bash
# One windowed batch per phase (CLAUDE.md, "Godot windows"): every screenshot, GPU timing or
# renderer-only run, one after another, each window at 1440x900 parked off-screen in the
# bottom-right corner (--position) so it stays out of the way. Everything else runs --headless.
# Usage: scripts/windowed_batch.sh "<args for run 1>" "<args for run 2>" ...
#   each argument is passed after `--` (e.g. "--capture --army --name=army").
#   An argument starting with "SCRIPT:" runs that -s script instead (e.g. "SCRIPT:res://x.gd -- 1").
cd "$(dirname "$0")/.."
export APPDATA="$PWD/.local/appdata" LOCALAPPDATA="$PWD/.local/localappdata"
WIN=(--resolution 1440x900 --position 1880,1040)
for run in "$@"; do
 if [[ "$run" == SCRIPT:* ]]; then
  read -r -a parts <<< "${run#SCRIPT:}"
  runtime/Godot.exe --path . "${WIN[@]}" -s "${parts[@]}" 2>&1 | grep -E "CAPTURE|GPU_MS|BENCH|SCRIPT ERROR|SELF_TEST"
 else
  read -r -a parts <<< "$run"
  runtime/Godot.exe --path . "${WIN[@]}" -- "${parts[@]}" 2>&1 | grep -E "CAPTURE|GPU_MS|SCRIPT ERROR|SELF_TEST"
 fi
done
