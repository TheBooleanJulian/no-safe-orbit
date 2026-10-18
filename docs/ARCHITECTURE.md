# Architecture

Source-of-truth spec: [`GAME_DESIGN.md`](GAME_DESIGN.md). This file records how
the code actually implements it, and every simplification currently in force.

## Layers

```text
Input (InputMap) ──► PlayerInput ──► ShipControlInput ─┐
                                                       ▼
                         WorldSimulation (fixed 60 Hz) ── ShipDynamics.step()
                                │  owns ShipState[] by stable id
                                ▼ read-only
            ShipView / ChaseCamera / DustField / Starfield / Hud
```

- **`scripts/simulation/`** is pure state + rules. It never touches nodes,
  meshes or the `Input` singleton, so it runs identically in tests, headless
  servers and (later) multiplayer authority.
- **Presentation** reads interpolated state each frame and never writes back.
- **`Main`** (`scripts/app/main.gd`) is thin wiring: sample input → advance sim
  → sync views → update HUD.

## Core types (current)

| Type | Role |
|---|---|
| `ShipConfig` (Resource, `data/ships/*.tres`) | Immutable tuning: mass, inertia, per-direction thrust, torque, assist rates. Stand-in for blueprint-derived values until Milestone 2. |
| `ShipState` | Physical vessel: stable `id`, position, velocity, orientation, body-frame angular velocity, last thrust/torque, Δv spent. |
| `ShipControlInput` | One tick's command: body-axis translation/rotation in [-1, 1] + assist flag. |
| `ShipDynamics` | Static 6DoF integrator and flight-assist controller. |
| `WorldSimulation` | Fixed-timestep clock, deterministic ship update order, interpolation alpha. |
| `RelativeMotion` | Range, range rate, relative velocity (vector inputs; reusable for projectiles). |

## Conventions

- **Units:** SI throughout — metres, seconds, kilograms, newtons, N·m, kg·m²,
  radians internally (HUD converts to °/s and km for display only).
- **Axes (body and world):** Godot convention — +X right, +Y up, **−Z forward**.
  Rotation commands follow the right-hand rule: +X pitch up, +Y yaw left,
  +Z roll left.
- **Identity:** ships are keyed by `StringName` ids, never by node path.
- **Tuning** lives in `.tres` resources, not literals in logic.

## Time

- `WorldSimulation.advance(frame_delta)` accumulates real time and runs whole
  fixed steps (`1/60 s`), returning an interpolation alpha for rendering.
  Tested: identical state for steady vs jittery frame pacing.
- At most 8 catch-up steps per frame; excess time is discarded and counted in
  `dropped_time` (prevents the spiral of death after a hitch).
- Input is sampled once per rendered frame and held across that frame's ticks.

## Floating origin

Rendering is centred on the player ship: every view is placed at
`sim_position − player_position`. Render-space coordinates therefore stay small
however far the ship travels. The dust field wraps a 1.5 km tile around the
origin, so it stays seamless and fixed in the world frame.

## Simplifications in force (and their gameplay consequence)

| Simplification | Consequence | Revisit |
|---|---|---|
| No gravity; local frame is inertial | Pure Newtonian free flight; nothing to orbit yet | Milestone 1 (orbital) |
| `Vector3` is 32-bit float | Fine at engagement scale (km); **not** adequate for orbital radii (~7×10⁶ m → ~0.5 m resolution) | Before gravity lands — see plan below |
| Diagonal inertia, gyroscopic term (ω × Iω) ignored | Multi-axis tumbles don't precess; spins are "too clean" | When asymmetric hulls exist (M2) |
| Thrust and torque are independent budgets | Rotating doesn't cost translation thrust or vice versa | When thrusters become placed components (M2/M3) |
| Flight assist nulls velocity relative to the fixed local frame | Assist always brakes to "stopped"; there is no target-relative or orbit-relative hold | Must change with gravity (see Known Issues) |
| Δv is counted, propellant is not modelled | No fuel limit yet; Δv spent is shown so the cost of assist is visible | Propellant graph (M2/M3) |
| Semi-implicit Euler | Fine for thrust-only; energy drift unknown under gravity | Orbital milestone: test symplectic/Verlet against energy drift |

## Planned: orbital precision

Keep ship/projectile physics in a **local engagement frame** (float32 vectors,
km-scale coordinates) whose origin and velocity are stored in
**double precision** (GDScript `float` is 64-bit) relative to the planet.
Gravity is evaluated per body as `−μ r/|r|³` using the double-precision frame
origin plus the local offset, and the frame is re-centred when the engagement
drifts too far. This avoids a custom vector class in hot paths. To be proven
with orbit-stability tests before HUD work depends on it.

## Testing

- `tests/run_tests.gd` — headless runner; methods named `test_*` in
  `tests/unit/test_*.gd` (subclasses of `TestCase`). Failure messages state
  measured quantity, expected and actual.
- `tests/smoke/smoke_main.gd` — boots the real main scene and drives it via
  InputMap actions.
- `tools/run_checks.sh` — runs everything and also fails on engine errors in logs.
- `tools/capture_screens.gd` — renders scripted moments to PNG for visual review.
