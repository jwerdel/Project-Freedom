#!/usr/bin/env bash
# The god-game look test's GPU cost breakdown at 1080p (god/god_test.gd --bench): one windowed run
# per configuration, parked off-screen, each line appended to the output file.
# Usage: scripts/god_bench.sh <out file> "<label> <flags>" ...
cd "$(dirname "$0")/.."
export APPDATA="$PWD/.local/appdata" LOCALAPPDATA="$PWD/.local/localappdata"
out="$1"; shift
for run in "$@"; do
 read -r -a parts <<< "$run"
 runtime/Godot.exe --path . --resolution 1920x1080 --position 1880,1040 god/god_test.tscn -- --bench="${parts[0]}" --out="$out" "${parts[@]:1}" 2>&1 | grep -E "GODTEST bench|SCRIPT ERROR"
done
