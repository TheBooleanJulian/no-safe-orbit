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
	# Ignore exactly one known-benign engine error: on Windows virtual drives
	# (e.g. Google Drive) Godot cannot query the filesystem type.
	errors=$(awk '/^ERROR:/ { held = $0; next }
		held != "" { if ($0 !~ /get_filesystem_type/) print held; held = "" }
		{ print } END { if (held != "") print held }' "$log" \
		| grep -E "SCRIPT ERROR|Parse Error|^ERROR:|^USER ERROR|Failed loading" || true)
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
run_step shipyard  "$GODOT" --headless --path . -s res://tests/smoke/smoke_shipyard.gd
run_step campaign  "$GODOT" --headless --path . -s res://tests/smoke/smoke_campaign.gd
run_step boarding  "$GODOT" --headless --path . -s res://tests/smoke/smoke_boarding.gd
run_step wing      "$GODOT" --headless --path . -s res://tests/smoke/smoke_wing.gd
run_step encounter "$GODOT" --headless --path . -s res://tests/smoke/smoke_encounter.gd
run_step survey    "$GODOT" --headless --path . -s res://tests/smoke/smoke_survey.gd
run_step boot_main "$GODOT" --headless --path . --quit-after 600 -- --profile=user://check_boot_profile.json
# Exported data: pack the project with the export preset (no templates
# needed) and boot from the pack, so missing include filters fail here.
mkdir -p build/export
run_step export    "$GODOT" --headless --path . --export-pack "Windows Desktop" build/export/NoSafeOrbit.pck
run_step pck_boot  "$GODOT" --headless --main-pack build/export/NoSafeOrbit.pck --quit-after 300 -- --profile=user://check_boot_profile.json
if ! grep -q "Orbital sandbox ready" "$LOG_DIR/pck_boot.log"; then
	echo "✗ pck_boot did not reach the flight scene"
	status=1
fi

grep -hE "tests, |smoke: |smoke_shipyard: |smoke_campaign: |smoke_boarding: |smoke_wing: |smoke_encounter: |smoke_survey: " "$LOG_DIR/unit.log" "$LOG_DIR/smoke.log" "$LOG_DIR/shipyard.log" "$LOG_DIR/campaign.log" "$LOG_DIR/boarding.log" "$LOG_DIR/wing.log" "$LOG_DIR/encounter.log" "$LOG_DIR/survey.log" 2>/dev/null
exit $status
