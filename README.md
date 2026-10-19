# NO SAFE ORBIT

*Keep the Delta-V Positive, or Else.*

A hard-sci-fi spacecraft engineering and combat simulator, built in Godot 4.
Your ship's construction determines how it flies, how it fights, how it fails,
and whether it survives.

**Status:** Milestones 0–6 complete — design a ship in the shipyard, then fly
and fight it in a real-scale 400 km Earth orbit under the real sky. Rounds
penetrate armour and wreck the systems in their path, and keep flying on their
own orbits afterwards; power, heat, pressure and propellant are simulated.
Disable an enemy, salvage it for spare parts and loot crates, dock, repair,
refit and fly again — your vessel keeps its damage between sorties. A crew
works the ship; dock a gangway and board the enemy room by room; launch a
fighter and a recon drone and give them orders. Next: Milestone 7 (EMP and
advanced weapons). See [`docs/ROADMAP.md`](docs/ROADMAP.md).

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
| Salvage a disabled target / close the loot panel | G | D-pad up |
| Damage control (workshop field repair) | C | D-pad down |
| Extend / release a boarding gangway | V | D-pad left |
| Send the boarding party / order it home | N | D-pad right |
| Divert power to systems / engines / weapons | 1 / 2 / 3 | paddles 1–3 |
| Balance power | 4 | paddle 4 |
| Tactical overview (ship map, power, crew, damage control, air wing) | Tab | left stick click |
| Launch craft / recall craft | L / K | paddle / Misc |
| Restart scenario (docks first: damage carries over) | Backspace | Back |
| Dock at the shipyard (with the ship you're flying) | B | Start |
| Controls panel (rebinding) | F1 | Guide |

**Propellant:** the Frigate Mk I carries 80 t — about 1.6 km/s of main-engine
Δv; the RCS shares the main engines' propellant feed and exhaust velocity
(Isp 900 s), so manoeuvring costs no more per m/s than the mains. Flight assist's target-matching and
every manoeuvre spend it. Empty tanks mean no thrust and no RCS.

**Combat:** T makes the target shoot back. Rounds penetrate armour (thicker at
angles), then breach rooms, destroy hatches and damage whatever systems lie on
their path. Lost reactors, wrecked modules (which cut their power junction)
and overheating (throttle at 380 K, scram at 450 K) take systems offline. The
target panel and the HIT TAKEN lines explain every hit.

**Rounds never expire.** Misses coast on their own orbits — around the planet
and, half an orbit later, possibly back through you. Far from the fight they
are propagated exactly (two-body Kepler) and come back into the simulation
when their orbit returns; the HUD counts rounds near and in far orbit and
warns of any round on a collision course. Firing pushes your ship back
(recoil, including the spin from off-centre mounts), and every hit shoves and
spins the ship it strikes. A round that punches through keeps going, slower.

**Hit cam:** each hit you score opens a small X-ray replay of the target —
the round's path through the hull and every module it damaged or destroyed,
in order (the most severe recent hit wins the window).

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

## Campaign: salvage, loot, repairs

1. **Disable** the target — knock out its guns, its power or its bridge. A
   clean disabling shot pays better than shooting it to pieces.
2. **Salvage**: close to under 500 m, match velocity (X) to under 5 m/s and
   press **G**. The station pays a bounty in credits at once (`100 + 100 ×
   intact`, doubled for a captured ship). `10 + 50 × intact` spare parts, 1–5
   loot crates and the wreck's best intact rare part go into your **cargo
   hold** — at risk until you bank them. The next contact then arrives,
   and each one is tougher (rarer guns, armour, RCS and reactors).
3. **Loot** uses cascading weighted rarity: every crate starts Common and
   climbs a tier with 30 % / 30 % / 25 % / 20 % chances (Common 70 %,
   Uncommon 21 %, Rare 6.75 %, Epic 1.8 %, Legendary 0.45 %), then picks a part
   of that tier by weight. A tier with nothing in it falls back to the one
   below. Hard pity: at least Rare every 10 crates, Legendary every 80. Common
   crates hold spare parts; rarer ones hold equipment units (railgun, torch
   drive, high-Isp engines, Mk II reactor, heat-pipe radiators, armoured
   tanks, …) or blueprints for hull modules and rooms (armoured sections,
   monocoque fuselage, workshop, dense magazine). Duplicate blueprints are
   scrapped for spare parts. The rates and pity countdown are shown with every
   salvage.
4. **Dock** at the station with **B**. The vessel keeps exactly the damage
   it came back with (also when you restart, or quit mid-sortie). The
   station opens on the **debrief**: what you hit, where the hits on you came
   from, what armour stopped, what you lost, and lessons for the shipyard
   (saved under `user://debriefs/`). **Bank cargo** to make the hold's
   contents safe. Buy spare parts with credits.
5. **Death** loses only what is in the cargo hold. The station rehires,
   rebuilds and rearms the same design — rare parts fitted to it included —
   for a respawn fee in credits (50 + 5 per berth). Backspace respawns in
   orbit; B returns to the station. The debrief shows either way.
6. **Repair** at the shipyard's HANGAR & SERVICE panel, paid in spare parts
   (a part's repair costs its new price × how damaged it is). Short of parts?
   Choose what comes first: full restoration, combat readiness, mobility or
   hull integrity. Unrepaired parts fly as they are.
7. **Refit / relaunch**: new parts in an edited design must be paid for at
   launch. Rarer parts can only be used if you own enough units / have the
   blueprint — the validator says what is missing.

In flight, a ship with a **workshop** (a found room blueprint) that is
powered, pressurised and reachable can patch damaged systems to 75 % (**C**):
a damage-control (or engineering) crew member walks there first, it costs
spare parts, and it stops if the workshop or the part's room loses pressure
or the repairer is hurt. Destroyed parts still need the yard.

## Running the ship

- **Damage map** (bottom left, always on): modules by structure, rooms by
  pressure, systems by state, crew as dots.
- **Power** (1 / 2 / 3, 4 to balance): six pips across SYS (turning and
  repair speed), ENG (thrust) and WEP (rate of fire), 0–4 each: 50 % at 0
  pips, 100 % at 2, 150 % at 4.
- **Tactical overview** (Tab): your ship deck by deck, the target (with
  boarding control), power, crew by role and where they are, orders to send
  a general crew member to cover a lost role (bridge, guns, engineering,
  damage control), what damage control patches first, and the boarding
  party size.
- **Bridge crew lost**: the ship AI flies it with half thrust and turn rate,
  assist locked on, until someone takes over the bridge.
- **Reactors explode** at 0 %: blast damage within 15 m, falling off with
  distance.

## Air wing: fighters and drones

The Frigate Mk I carries a **Wasp fighter** and a **recon drone** on external
racks. They fly with the same physics as every ship and can be shot down.

- **L** launches (the rack must work and the ship must be turning slowly);
  **K** recalls. A craft is recovered when it comes within 10 m of its rack
  at under 2 m/s, then rearmed and refuelled for 40 s.
- Orders, per craft, in the tactical overview (Tab): **Strike** (gun runs
  on the target, aimed at hull, guns, engines or reactor), **Intercept**
  (enemy craft first), **Recon** (hold 1.5 km off the target, never fire),
  **Escort** (fly beside you), **Return**. **Risk tolerance**
  (conservative / balanced / aggressive) decides when a craft breaks off on
  its own for damage, propellant or ammunition.
- Out of contact (beyond 30 km, or jammed) for 10 s, a craft falls back to
  returning home.
- **Recon** gives the close look that shows the target's systems: without a
  drone nearby you see them only within 3 km.
- Enemies launch their own fighter from mission 3 once hostile.
- A craft still out when you dock is lost. Lost craft are replaced, and
  damaged ones repaired, at the station.

## Crew and boarding

Every berth holds one crew member with a role: command (bridge), engineering,
damage control, weapons (magazine), security, medical and general crew. They
are not drawn; moving between rooms takes 5 s per room, through pressurised
rooms only. A room that vents wounds or kills whoever is in it. No command
crew on a pressurised bridge hands the ship to the ship AI (half thrust and
turn rate); no weapons crew able to
reach the magazine halves the guns' rate of fire. The dead must be replaced
at the yard (2 spare parts each); the wounded recover when you dock.

**Boarding** a disabled ship:

1. Come alongside with matched velocity. The target panel shows the docking
   tolerances: port gap ≤ 25 m, relative speed ≤ 0.5 m/s, turn rate ≤ 3.4°/s,
   gangway within 20° of square.
2. **V** extends the gangway from your docking collar: mated to the target's
   collar in 10 s, or cut into any outer hull face with a room behind it in
   45 s (that room vents). A target that still has power, thrust and a crew
   in command thrusts away and tears the gangway — disable it first.
3. **N** sends your security and general crew (up to 8). They walk to the
   collar, cross, and fight room by room towards the bridge. Defenders lock
   the doors ahead (20 s to cut each; hatches your guns already destroyed
   are open) and their security falls back to hold the bridge. Fights are
   resolved by numbers and roles, not instant kills: a full crew will
   usually repel eight boarders, so thin them out first — venting their
   quarters, or cutting straight into a bridge that sits under the hull.
The hit-cam window shows the boarded ship's rooms while the fight goes on:
cyan = taken, pulsing magenta = fought over, red = defended. Within 150 m a
**docking cam** shows the view out of your collar with the tolerances, and
every ship's docking collar is hazard-striped with a blinking beacon.

4. Take the bridge and the ship surrenders: salvage it (**G**) for two extra
   crates; your party comes home with the prize. **N** again orders a
   withdrawal; if the gangway is gone, they are stranded. Leaving (B) with
   boarders still across loses them.

Progress is saved to `user://profile.json` (versioned JSON).

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
| Fly it | LAUNCH ▶ (disabled while the design has errors; warnings are allowed; new parts are paid for in spare parts) |
| Repair the hangar vessel | HANGAR & SERVICE panel: pick a priority, then Repair |

Palette colours show rarity (grey Common, green Uncommon, teal Rare, violet
Epic, gold Legendary); rarer equipment shows how many units you own, rarer
hull modules and rooms show "(locked)" until you find their blueprint.

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
smoke tests of flight (`smoke_main.gd`, through InputMap actions), the
shipyard (`smoke_shipyard.gd`, including a real mouse click) and the
Milestone 4 loop (`smoke_campaign.gd`: fight → salvage → dock damaged →
repair and refit → relaunch) and the Milestone 5 boarding
(`smoke_boarding.gd`), and a 600-frame boot of the main scene. Smoke
tests use a throwaway profile, never your save. The script fails on any test failure **and**
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
scripts/progression/   profile, hangar vessel, loot, salvage, repairs and refits
scripts/presentation/  views of sim state (ships, camera, dust, planet sky, tracers)
scripts/ui/            HUD
scripts/app/           wiring: main loop, player input, logging
tests/                 unit tests, smoke test, runner
tools/                 run_checks.sh, capture_screens.gd
```

Also: [`CHANGELOG.md`](CHANGELOG.md), [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md).
