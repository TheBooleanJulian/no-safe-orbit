# Roadmap

Full milestone definitions: [`GAME_DESIGN.md` §17](GAME_DESIGN.md#17-milestone-roadmap).
A milestone is not done until its acceptance results are verified by tests that
were actually run.

## Milestone 0 — Repository and project health ✅ (2026-10-19)

- [x] Repository inspected (empty — only the spec existed)
- [x] Godot 4.5.1 project, folder layout, `.gitignore`, git repo
- [x] Docs: README, GAME_DESIGN (spec), ARCHITECTURE, ROADMAP, CHANGELOG, KNOWN_ISSUES
- [x] Bootable main scene
- [x] Headless test harness + smoke test + log-error gate (`tools/run_checks.sh`)
- [x] Logging (`GameLog`, file logging enabled)

Exit criteria met: project imports and boots headlessly with zero engine
errors; 20 unit tests + 7 smoke checks pass.

## Milestone 1 — Flight sandbox 🟡 in progress

### 1a — done (2026-10-19)
- [x] Simulation state separated from rendering (`scripts/simulation/`)
- [x] Fixed-timestep world clock with render interpolation
- [x] 6DoF translation and rotation with per-direction thrust limits
- [x] Flight assist (translation + rotation) and manual mode
- [x] Controllable placeholder frigate, passive target ship
- [x] HUD: speed and body-axis velocity, angular rates, Δv spent, target
      range / range rate / relative speed; heading reticle; prograde/retrograde;
      target bracket and off-screen arrow
- [x] Floating render origin, dust field motion cue, starfield

### 1b — next: acceptance criteria

1. **Orbital gravity.** One spherical body, `a = −μ r/|r|³`, with the
   double-precision frame plan in ARCHITECTURE.md.
   - Test: a no-thrust circular orbit keeps |r| within ±0.1 % and specific
     orbital energy drift under 10⁻⁴ (relative) over 10 orbits.
   - Test: a prograde burn raises the opposite apsis; a retrograde burn lowers it.
   - Test: dropping below circular speed yields an ellipse, **not** an impact,
     unless periapsis falls below the planet radius (spec §5 rule).
   - Test: an intersecting trajectory is detected as impact.
2. **Flight assist under gravity** holds velocity relative to a chosen
   reference (local orbital frame or target), not "stopped in inertial space".
   - Test: assist with no input does not burn continuously against gravity.
3. **Kinetic cannon** (data-driven definition: muzzle velocity, rate of fire,
   magazine).
   - Test: projectile initial velocity = ship velocity + muzzle velocity × nose
     direction (exact).
   - Test: flight time is finite and matches range / closing speed in a
     straight-line case; gravity acts on projectiles.
   - Test: swept-segment hit detection catches a fast round against a target
     box with no tunnelling at the fixed timestep.
4. **Fire control aid:** lead indicator and time-of-flight estimate for a
   constant-velocity target, shown separately from line of sight.
   - Test: known-geometry intercept prediction within 1 m / 0.01 s.
5. **Flat radar** showing bearing, range, elevation, approach/recede.
6. **Orbital HUD:** apoapsis/periapsis readout and projected path line.

Exit criteria (from spec): ship movement is understandable; trajectories and
projectile timing pass tests.

## Milestones 2–8

Not started. See GAME_DESIGN.md §17.
