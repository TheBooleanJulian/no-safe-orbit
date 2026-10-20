#!/usr/bin/env bash
# Builds the Steam depots for No Safe Orbit (publisher: TheBooleanJulian).
#
#   GODOT=/path/to/godot STEAM_APP_ID=1234560 bash tools/steam_export.sh
#
# 1. Release exports for Windows and Linux into build/steam/{windows,linux},
#    each with THIRD_PARTY_NOTICES.txt (credits and the Godot licences).
# 2. With STEAM_APP_ID set, the steamcmd scripts from steam/*.vdf, filled in,
#    in build/steam/scripts/ (depot IDs default to the app ID + 1 and + 2).
#
# Needs Godot's export templates for this engine version (Editor → Manage
# Export Templates). It never uploads: the steamcmd command it prints is run
# by hand, with your own Steam login (docs/STEAM.md).
set -euo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
OUT=build/steam
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)

rm -rf "$OUT/windows" "$OUT/linux" "$OUT/scripts"
mkdir -p "$OUT/windows" "$OUT/linux" "$OUT/scripts" "$OUT/output"

TEMPLATES_HINT="are the export templates for this Godot version installed? (Editor → Manage Export Templates)"
"$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/windows/NoSafeOrbit.exe" \
	|| { echo "✗ Windows export failed — $TEMPLATES_HINT"; exit 1; }
"$GODOT" --headless --path . --export-release "Linux" "$OUT/linux/NoSafeOrbit.x86_64" \
	|| { echo "✗ Linux export failed — $TEMPLATES_HINT"; exit 1; }
for f in "$OUT/windows/NoSafeOrbit.exe" "$OUT/windows/NoSafeOrbit.pck" \
		"$OUT/linux/NoSafeOrbit.x86_64" "$OUT/linux/NoSafeOrbit.pck"; do
	if [ ! -s "$f" ]; then
		echo "✗ $f missing — $TEMPLATES_HINT"
		exit 1
	fi
done
for p in windows linux; do
	"$GODOT" --headless --path . -s res://tools/write_notices.gd -- "$OUT/$p/THIRD_PARTY_NOTICES.txt"
done
echo "✓ No Safe Orbit $VERSION exported to $OUT/windows and $OUT/linux"

if [ -z "${STEAM_APP_ID:-}" ]; then
	echo "Set STEAM_APP_ID to also write the steamcmd scripts."
	exit 0
fi
WIN_DEPOT_ID="${STEAM_WIN_DEPOT_ID:-$((STEAM_APP_ID + 1))}"
LINUX_DEPOT_ID="${STEAM_LINUX_DEPOT_ID:-$((STEAM_APP_ID + 2))}"
for f in app_build depot_windows depot_linux; do
	sed -e "s/@APP_ID@/$STEAM_APP_ID/g" -e "s/@WIN_DEPOT_ID@/$WIN_DEPOT_ID/g" \
		-e "s/@LINUX_DEPOT_ID@/$LINUX_DEPOT_ID/g" -e "s/@VERSION@/$VERSION/g" \
		"steam/$f.vdf" > "$OUT/scripts/$f.vdf"
done
echo "✓ steamcmd scripts in $OUT/scripts (app $STEAM_APP_ID, depots $WIN_DEPOT_ID, $LINUX_DEPOT_ID)"
echo "Upload (uses your own Steam login; nothing is stored here):"
echo "  steamcmd +login <your_steam_build_account> +run_app_build \"$(pwd)/$OUT/scripts/app_build.vdf\" +quit"
