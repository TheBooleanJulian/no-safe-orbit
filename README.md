# NO SAFE ORBIT

*Keep the Delta-V Positive, or Else.*

A hard-sci-fi spacecraft engineering and combat simulator, built in Godot 4.
Your ship's construction determines how it flies, how it fights, how it fails,
and whether it survives.

**Status:** Milestones 0–3 complete — design a ship in the shipyard, then fly
and fight it in a real-scale 400 km Earth orbit under the real sky. Rounds
penetrate armour and wreck the systems in their path; power, heat, pressure
and propellant are simulated. Next: Milestone 4 (persistence and recovery).
See [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Requirements

- Godot **4.7.2-stable** (standard build, GDScript only — no .NET needed).

## Run

Open the folder in Godot 4.7.2 and press F5, or from a terminal:

```bash
godot --path .
```

## Controls (rebind in game with F1; saved per user)

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Main engine / reverse thrusters | W / S | left stick up / down |
| Strafe left / right | A / D | left stick left / right |
| Thrust up / down | Space or R / Ctrl or F | RT / LT |
| Pitch up / down | ↑ / ↓ | right stick down / up |
| Yaw left / right | ← / → | right stick left / right |
| Roll left / right | Q / E | LB / RB |
| Mouse virtual stick | click to capture, Esc to release | — |
| Toggle flight assist | Z | Y |
| Velocity hold: orbit ↔ match target | X | X |
| Fire cannon | Left mouse (once captured) or Enter | A |
| Target hostile on/off | T | B |
| Restart scenario | Backspace | Back |
| Open the shipyard (with the ship you're flying) | B | Start |
| Controls panel (rebinding) | F1 | Guide |

**Propellant:** the Frigate Mk I carries 80 t — about 1.6 km/s of main-engine
Δv; RCS burns three times as much per m/s. Flight assist's target-matching and
every manoeuvre spend it. Empty tanks mean no thrust and no RCS.

**Combat:** T makes the target shoot back. Rounds penetrate armour (thicker at
angles), then breach rooms, destroy hatches and damage whatever systems lie on
their path. Lost reactors, wrecked modules (which cut their power junction)
and overheating (throttle at 380 K, scram at 450 K) take systems offline. The
target panel and the HIT TAKEN lines explain every hit.

**Sky:** stars, Sun and Earth's rotation are real for 2026-10-19 12:00 UTC
(Yale Bright Star Catalogue, NASA Blue Marble; see `data/ATTRIBUTION.md`).

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

## Shipyard

Press **B** in flight. You start from the ship you were flying (the Frigate
Mk I template by default).

| Action | How |
|---|---|
| Pick a part | Palette tabs: Hull / Rooms / Equipment |
| Place | Click on the deck grid (rooms: drag a rectangle). The ghost turns red and the hint bar names the problem before you click. |
| External equipment face | Point near a cell edge for fore/aft/port/starboard, at the centre for dorsal, Shift+centre for ventral |
| Rotate a module | R (while placing, or with a module selected) |
| Select / move / delete | Select tool (S), arrow keys, Delete |
| Remove anything | Right-click |
| Hatches | Hatch tool (H): click near an edge for a door, a cell's centre for a ladder to the deck above |
| Change deck | ▲ / ▼ or PgUp / PgDn |
| Save / load | Top bar (saved to `user://blueprints/`); "Load template" restores the Frigate Mk I |
| Fly it | LAUNCH ▶ (disabled while the design has errors; warnings are allowed) |

Errors (✖) are physically or structurally invalid designs: overlapping or
unattached modules, rooms outside the pressurised hull, equipment that doesn't
fit, no bridge. Warnings (▲) are trade-offs you may accept: power or heat
deficits, rooms the crew can't reach, a cannon firing into your own hull,
off-axis engines. Click an issue to highlight the part.

## Tests

```bash
GODOT=/path/to/godot tools/run_checks.sh
```

Runs, headlessly: project import, unit tests (`tests/unit`), end-to-end
smoke tests of flight (`smoke_main.gd`, through InputMap actions) and the
shipyard (`smoke_shipyard.gd`, including a real mouse click), and a
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
data/                  data, not code: catalog/ (parts), blueprints/ (templates),
                       weapons/, bodies/ (Earth), ships/ (test fixture)
docs/                  GAME_DESIGN (source-of-truth spec), ARCHITECTURE, ROADMAP
scenes/                main (flight), shipyard, ships, ui
shaders/               planet_sky (Earth, 100 km limb, sun, stars)
scripts/simulation/    authoritative flight sim — no rendering, no Input singleton
scripts/construction/  blueprint model, validation, derived stats, JSON I/O
scripts/shipyard/      ship editor logic and shipyard UI
scripts/presentation/  views of sim state (ships, camera, dust, planet sky, tracers)
scripts/ui/            HUD
scripts/app/           wiring: main loop, player input, logging
tests/                 unit tests, smoke test, runner
tools/                 run_checks.sh, capture_screens.gd
```

Also: [`CHANGELOG.md`](CHANGELOG.md), [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md).
