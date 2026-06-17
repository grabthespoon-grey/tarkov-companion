#!/usr/bin/env bash
# Headless smoke test runner. Temporarily points run/main_scene at the smoke
# test scene, runs Godot headless, then restores project.godot.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJ="project.godot"
BACKUP="$(mktemp)"
cp "$PROJ" "$BACKUP"
restore() { cp "$BACKUP" "$PROJ"; rm -f "$BACKUP"; }
trap restore EXIT

# Swap the main scene to the smoke test.
sed -i '' 's#run/main_scene="res://scenes/main.tscn"#run/main_scene="res://test/smoke_test.tscn"#' "$PROJ"

LOG="$(mktemp)"
"$GODOT" --headless --quit-after 600 >"$LOG" 2>&1 || true

echo "===== smoke results ====="
grep -E "SMOKE:|SMOKE_DONE" "$LOG" || echo "(no SMOKE output — boot/parse error below)"
echo "===== runtime errors (if any) ====="
grep -iE "SCRIPT ERROR|push_error|Parse Error|Invalid|nil|out of bounds" "$LOG" | grep -viE "GodotSteam" || echo "(none)"

# Exit non-zero if any test failed or no done-line.
if grep -q "SMOKE_DONE pass=.* fail=0" "$LOG"; then
	echo "RESULT: ALL PASS"
	exit 0
else
	echo "RESULT: FAILURES (see above)"
	exit 1
fi
