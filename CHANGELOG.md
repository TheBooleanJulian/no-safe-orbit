# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [0.1.0] — 2026-10-19 — Milestone 0 + Milestone 1a

### Added
- Godot 4.5.1 project "No Safe Orbit" with rebindable InputMap actions.
- Simulation core (`scripts/simulation/`): `ShipConfig` resource, `ShipState`,
  `ShipControlInput`, `ShipDynamics` (6DoF, per-direction thrust limits,
  flight assist and manual modes), `WorldSimulation` (fixed 60 Hz timestep,
  interpolation, catch-up cap), `RelativeMotion` (range, range rate).
- Placeholder frigate tuning data: `data/ships/placeholder_frigate.tres`
  (250 t, 1 g main engine, 0.2 g RCS).
- Flight sandbox scene: player frigate, passive drifting target, chase camera,
  floating render origin, wrapping dust field, starfield, twin engine plumes.
- HUD: velocity (total and per body axis), angular rates, Δv spent, sim clock,
  assist state; target range / range rate / relative speed; heading reticle,
  prograde/retrograde markers, target bracket with off-screen edge arrow,
  mouse virtual-stick indicator; on-screen controls help.
- Test harness: `tests/run_tests.gd` (20 unit tests), `tests/smoke/smoke_main.gd`
  (end-to-end through the real scene), `tools/run_checks.sh` (also fails on
  engine errors in logs), `tools/capture_screens.gd` (visual review frames).
- Docs: README, GAME_DESIGN (title set to NO SAFE ORBIT), ARCHITECTURE,
  ROADMAP, KNOWN_ISSUES.

### Fixed
- HUD overlay built a negative-size `Rect2` on viewports smaller than the edge
  margin (caught by the log-error gate in headless runs).
