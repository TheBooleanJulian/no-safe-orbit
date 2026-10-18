# Known issues

Honest list of limitations in the current build. Design simplifications are
also tabulated in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Open

- **No gravity yet.** The sandbox is inertial free space; there is no planet or
  orbit. (Milestone 1b.)
- **Float32 positions.** `Vector3` is single precision. Adequate for the current
  km-scale sandbox, not for orbital radii. A double-precision frame origin is
  planned before gravity is added (ARCHITECTURE.md → Planned: orbital precision).
- **Flight assist will fight gravity.** Assist currently drives velocity to zero
  in the fixed local frame. Under gravity that would burn continuously. It must
  hold velocity relative to an orbital or target reference instead. (Milestone 1b, item 2.)
- **No propellant limit.** Δv spent is tracked and displayed but nothing runs out.
- **Gyroscopic coupling ignored** (diagonal inertia only).
- **Target ship is passive** — no AI, it drifts and turns slowly.
- **No weapons yet.**
- **Visual verification is partial.** Frames were reviewed only under the
  Compatibility (OpenGL) renderer with software GL via Xvfb. The Forward+
  renderer the project defaults to was boot-tested headlessly (dummy renderer)
  but not visually inspected. Mouse feel has not been tested by a human.
- **Rebinding only via Project Settings** — no in-game rebinding UI; no gamepad
  bindings yet.
- **Dust field repeats** every 1.5 km per axis; distance fade hides the seams but
  a sharp eye may spot the repetition.
- **No audio.**

## Environment notes

- In containers without a sound card Godot logs ALSA errors and falls back to the
  dummy audio driver. Harmless; `run_checks.sh` runs with `--headless`, which
  avoids it.
