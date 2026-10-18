# NO SAFE ORBIT

*Keep the Delta-V Positive, or Else.*

A hard-sci-fi spacecraft engineering and combat simulator, built in Godot 4.
Your ship's construction determines how it flies, how it fights, how it fails,
and whether it survives.

**Status:** Milestone 0 complete; first slice of Milestone 1 (6DoF flight
sandbox) playable. See [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Requirements

- Godot **4.7.2-stable** (standard build, GDScript only — no .NET needed).

## Run

Open the folder in Godot 4.7.2 and press F5, or from a terminal:

```bash
godot --path .
```

## Controls (all rebindable in Project → Project Settings → Input Map)

| Action | Default |
|---|---|
| Main engine / reverse thrusters | W / S |
| Strafe left / right | A / D |
| Thrust up / down | Space or R / Ctrl or F |
| Pitch up / down | ↑ / ↓ |
| Yaw left / right | ← / → |
| Roll left / right | Q / E |
| Mouse virtual stick | click to capture, Esc to release |
| Toggle flight assist | Z |

**Flight assist ON** (default): uncommanded axes thrust against residual motion
— release the keys and the ship brakes to a stop relative to the local frame,
within its real thrust limits. Braking costs Δv. **Manual**: no hidden damping;
the ship coasts forever and spins until you counter-thrust.

HUD markers: white reticle = where the nose points; green ring = where you are
actually going (prograde), green ⊗ ring = retrograde; orange bracket = target
(arrow at the screen edge when it is off-screen).

## Tests

```bash
GODOT=/path/to/godot tools/run_checks.sh
```

Runs, headlessly: project import, unit tests (`tests/unit`), an end-to-end
smoke test that drives the real main scene through InputMap actions, and a
600-frame boot of the main scene. The script fails on any test failure **and**
on any Godot `ERROR:` / `SCRIPT ERROR` in the logs. Logs: `build/check-logs/`.

Visual capture (needs a display or Xvfb):

```bash
xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-method gl_compatibility \
    -s res://tools/capture_screens.gd      # → build/screens/*.png
```

## Layout

```text
data/ships/            ShipConfig resources (tuning data, not code)
docs/                  GAME_DESIGN (source-of-truth spec), ARCHITECTURE, ROADMAP
scenes/                main, ships, ui
scripts/simulation/    authoritative sim — no rendering, no Input singleton
scripts/presentation/  views of sim state (ships, camera, dust, stars)
scripts/ui/            HUD
scripts/app/           wiring: main loop, player input, logging
tests/                 unit tests, smoke test, runner
tools/                 run_checks.sh, capture_screens.gd
```

Also: [`CHANGELOG.md`](CHANGELOG.md), [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md).
