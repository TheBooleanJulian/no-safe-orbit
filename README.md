# NO SAFE ORBIT

*Keep the Delta-V Positive, or Else.*

A hard-sci-fi spacecraft engineering and combat simulator, built in Godot 4.
Your ship's construction determines how it flies, how it fights, how it fails,
and whether it survives.

**Status:** Milestones 0 and 1 complete — a 6DoF frigate in a real-scale
400 km Earth orbit, with a kinetic cannon, fire control, radar and an orbital
HUD. Next: Milestone 2 (ship blueprint and builder). See
[`docs/ROADMAP.md`](docs/ROADMAP.md).

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
| Velocity hold: orbit ↔ match target | X |
| Fire cannon | Left mouse (once captured) or Enter |
| Restart scenario | Backspace |

**Flight assist ON** (default) damps rotation to the requested turn rate. For
translation it has two holds:

- **HOLD ORBIT** (default): uncommanded axes coast. You stay on whatever orbit
  your burns put you on, and coasting spends no Δv.
- **MATCH TARGET** (X): uncommanded axes thrust to null your velocity relative
  to the target, within real thrust limits. That costs Δv.

**Manual** (Z): no hidden damping at all; spins persist until you counter-thrust.

**Orbit:** you start in a 400 km circular Earth orbit at 7.67 km/s (period
≈92 min). Burn prograde (along the green ring) to raise the far side of your
orbit, retrograde to lower it. The **entry interface is 100 km** (the Kármán
line). If your periapsis drops below it, the HUD warns you and counts down.
Crossing it ends the flight; Backspace restarts.

HUD markers: white reticle = where the nose points; green ring = orbital
prograde (where you're actually going), green ⊗ = retrograde; thin green line =
projected orbit with Ap/Pe markers; orange bracket = target (arrow at the
screen edge when off-screen); gold ◇ = lead (put the reticle on it and fire).
Bottom right: flat radar (stalk = height above/below your plane; ▼ closing,
▲ opening).

## Tests

```bash
GODOT=/path/to/godot tools/run_checks.sh
```

Runs, headlessly: project import, unit tests (`tests/unit`), an end-to-end
smoke test that drives the real main scene through InputMap actions, and a
600-frame boot of the main scene. The script fails on any test failure **and**
on any Godot `ERROR:` / `SCRIPT ERROR` in the logs. Logs: `build/check-logs/`.

Visual capture (needs a display; on a desktop it briefly opens a window):

```bash
godot --path . -s res://tools/capture_screens.gd      # → build/screens/*.png
# headless Linux:
xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-method gl_compatibility \
    -s res://tools/capture_screens.gd
```

## Layout

```text
data/                  tuning data, not code: ships/, weapons/, bodies/ (Earth)
docs/                  GAME_DESIGN (source-of-truth spec), ARCHITECTURE, ROADMAP
scenes/                main, ships, ui
shaders/               planet_sky (Earth, 100 km limb, sun, stars)
scripts/simulation/    authoritative sim — no rendering, no Input singleton
scripts/presentation/  views of sim state (ships, camera, dust, planet sky, tracers)
scripts/ui/            HUD
scripts/app/           wiring: main loop, player input, logging
tests/                 unit tests, smoke test, runner
tools/                 run_checks.sh, capture_screens.gd
```

Also: [`CHANGELOG.md`](CHANGELOG.md), [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md).
