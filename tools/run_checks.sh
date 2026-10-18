#!/usr/bin/env bash
# Runs every automated check headlessly and fails on test failures OR on any
# Godot script/parse/runtime error printed to the log.
#   GODOT=/path/to/godot tools/run_checks.sh
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
LOG_DIR="build/check-logs"
mkdir -p "$LOG_DIR"
status=0

run_step() {
	local name="$1"; shift
	local log="$LOG_DIR/$name.log"
	"$@" >"$log" 2>&1
	local code=$?
	local errors
	errors=$(grep -E "SCRIPT ERROR|Parse Error|^ERROR:|^USER ERROR|Failed loading" "$log" || true)
	if [[ $code -ne 0 || -n "$errors" ]]; then
		echo "✗ $name (exit $code) — see $log"
		[[ -n "$errors" ]] && echo "$errors" | head -20
		status=1
	else
		echo "✓ $name"
	fi
}

run_step import    "$GODOT" --headless --path . --import
run_step unit      "$GODOT" --headless --path . -s res://tests/run_tests.gd
run_step smoke     "$GODOT" --headless --path . -s res://tests/smoke/smoke_main.gd
run_step boot_main "$GODOT" --headless --path . --quit-after 600

grep -hE "tests, |smoke: " "$LOG_DIR/unit.log" "$LOG_DIR/smoke.log" 2>/dev/null
exit $status
