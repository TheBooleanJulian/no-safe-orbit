# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/).

**Versions** follow [Semantic Versioning](https://semver.org/), staying at
**0.x.0** until the game is declared ready for 1.0: each promotion of `dev`
to `main` is one release and raises the minor number; work not yet promoted
sits under [Unreleased]. `application/config/version` in `project.godot`
(shown in game) is the latest release.

## [Unreleased]

### Settings menu (2026-10-22)

#### Added
- **Settings menu on Esc**, in flight (the sortie pauses) and at the
  station: Display (fullscreen, UI scale), Graphics (V-Sync, frame-rate cap,
  MSAA, 3D resolution), Audio (master, effects, ambience, alarms), Controls
  (the key bindings), Save data (where everything is saved, last saved,
  open the folder, **Back up now**), Stats, Changelog, About and **Dev
  support** (a feedback and bug-report form), Resume and Quit to desktop.
  Saved per user in `settings.cfg`.
- The exported game includes `CHANGELOG.md` for the Changelog tab.

#### Changed
- **Esc opens the settings menu** (it still frees the mouse); in the refit
  bay it first puts down the tool in hand, as before.
- **Versions follow SemVer** (0.x.0 until 1.0): the changelog is split into
  0.11.0–0.16.0, one per promotion to `main`; the game is 0.16.0.

#### Tests changed (and why)
- New `test_settings_menu` (2): settings saved, read back, clamped and
  applied (UI ×1.25, MSAA 4×, 3D ×0.75, half volume −6 dB, zero muted),
  reset; stats, save data, Back up now (two copies, the save untouched)
  and the changelog as BBCode.
- `smoke_encounter`: Esc opens the menu (8 tabs), the sortie pauses, the
  CONTROLS and STATS tabs fill, Esc closes it and the sortie runs on.
- `smoke_shipyard`: Esc drops the hatch tool, then opens the menu (the
  changelog shows 0.16.0), then closes it.
- `test_pass_a`: ducking is measured from the effects volume setting.

## [0.16.0] — 2026-10-22 — Play-test batch 11: combat rules, crew manifest, refit bay, flight and shipyard

### Play-test batch 11, part 4 — flight and shipyard (2026-10-22)

#### Added
- **Sell found equipment** from the cargo hold to the quartermaster, at 40 %
  of the shelf price (a common part as if it cost 100 cr).
- **Ship dealer catalogue pictures**: each card shows a decorated picture of
  the hull (vignette, faint grid, corner brackets in the card's colour). It
  is drawn once — the first time the card scrolls into sight — and kept in
  `user://dealer_shots`, keyed by the template's contents, so the dealer
  opens without building a 3D view per card.

#### Changed
- **The re-entry plasma is a cone**, its tip just ahead of the nose and
  opening aft, instead of a stretched ball.
- **The docking collar and gangway are octagonal**: a square with its
  corners cut short, almost a rounded square.
- **The dealer shows three cards across** instead of two.
- **The hold's line names the contract freight** ("contract freight:
  medical supplies (40 m³)") in the shipyard and in flight; before, a hold
  with only freight read "empty".
- **The hit cam stays shut while the Tab drawer is open** (it sat over the
  middle of the screen beside the drawer).
- **DEV +100k cr** (was +100).
- The shipyard's 3D views aim their camera without `look_at`, so building
  one before it is on screen no longer logs an engine error.

#### Not reproduced
- Banking the cargo does not repair the ship: before and after banking the
  vessel keeps the same damage and repair jobs (now checked in
  `smoke_campaign`). Banking spare parts makes the REPAIR button affordable,
  but it still has to be pressed.

#### Docs
- KNOWN_ISSUES: batch 11's first-guess numbers, the bank-cargo report (not
  reproduced) and the dealer's timings; ROADMAP: candidates for what comes
  next (not agreed).

#### Tests changed (and why)
- New `test_batch11_cargo` (4): the freight named; selling from the hold
  (480 cr for a rare part, the hold emptied, the bank untouched); DEV 100k;
  dealer pictures saved, loaded, decorated and keyed per template, empty
  frames refused.
- `test_batch10_models`: `test_hexagonal_collar_and_gangway` →
  `test_octagonal_collar_and_gangway` — eight edges, long and short by turns,
  the gangway's faces pointing out.
- `test_batch10_surface`: the re-entry plasma is a cone with its tip into
  the flow.
- `smoke_campaign`: banking leaves the damage as it was; DEV +100k.
- `smoke_encounter`: with the drawer open, the hit cam stays shut
  (mutation-checked: fails without the rule).

### Play-test batch 11, part 3 — the refit bay (2026-10-22)

#### Added
- **Hull pieces**: pressurised blocks 1×1 and 3×3, trusses 1×1 and 3×3, a
  3×3 slope.
- **A shape for each kind of part** (palette icon in its rarity's colour; on
  the deck cells and the top/underside markers).
- **TOP-DOWN 3D**: the parts as built, straight down, editable — the main
  view cycles plan → top-down 3D → isometric.
- **Hangar doors open** as craft leave and come back.

#### Changed
- **Palette text is the part's own colour** — the colour of its cells —
  instead of its rarity's; families share a colour: lasers cyan (turrets,
  laser fighters, laser drones), kinetic guns orange, kinetic fighters,
  bombers and interceptors gold, EW magenta, sensors green, drones by job;
  the dense magazine is the magazine's red; **RCS blocks are white**.
- **Power distribution → Power distro**; the palette is wider with smaller
  text, so long names fit.
- **A hangar needs a way out**: an error if a craft bay's room has no wall,
  floor or roof on the outside; its door (model and launch point) is that
  face.
- **Fin radiators** are drawn standing out from their face (the placement
  ghost too), not along it.
- **The berth's deck plate is see-through**: look under the ship.

#### Tests changed (and why)
- New `test_batch11_refit` (4): colours (the dense magazine's red, lasers
  one cyan, RCS white, text = cell colour), five parts five shapes and an
  icon; the new hull pieces joined and drawn; the frigate's bay opens at its
  underside, walled in it is an error, its door open 2 s after a launch and
  shut after 12; the top-down camera's axes.
- `smoke_shipyard`: a fin's ghost stands 3 out; along the hull, 3 cells.

### Play-test batch 11, part 2 — the crew manifest (2026-10-22)

#### Fixed
- **An enemy boarding us flew off mid-boarding** once every free security
  and general hand was in its party (it no longer "wanted" to board), tearing
  its own gangway: a contact whose gangway is on us now holds station.
  Smaller crews (2 berths a cell) showed it in `smoke_boarding`.

#### Added
- **Resting crew**: crew without a berth rest at the station, unpaid; drag
  them aboard (or ▲) when there is room, or rest someone by dragging their
  badge to Resting crew.
- **Fill berths**: resting crew first, then general hands from the hall.
- **Previous occupations** (flavour) for every crew member and candidate.
- **Crew armoury** (security's station; +10 % boarding strength a cell, up
  to +50 %, attacking or defending) and **cafeteria** (+2 % to everything
  crew skill touches a cell, up to +50 %) rooms.

#### Changed
- **Crew quarters → Crew manifest**, with the hiring hall top right and
  resting crew below it.
- **Crew are yours, not a ship's**: they move with you to the vessel you fly
  (buying a ship, its crew join yours).
- **Two berths a quarters cell** (were three); the manifest follows the
  design on the slip live.
- **The hiring hall never runs dry**: each hire is replaced at once.
- **Names**: 120 × 100 combinations, and none twice among your people.
- **Life support is shown as the Medbay**.

#### Save format
- **Schema 14**: `resting`; crew `occupation`. Older saves: other vessels'
  crews go ashore to rest, the active vessel keeps what its berths hold
  (original kept as `.v13`).

#### Tests changed (and why)
- New `test_batch11_crew` (5): 2 berths a cell and excess ashore; the hall
  refilled after each hire and a destroyer filled with 144 different names;
  resting and boarding, crew moving to a bought destroyer and back; a
  12-cell cafeteria ×1.24 (gun 120 → 149 rpm) and armoury ×1.50 with security
  posted there; v13 → v14.
- `test_boarding` (3 general hands, were 11), `test_progression` (respawn
  fee for 16 berths), `test_m15_scaling` (the destroyer's specialists exactly
  3 × the frigate's): the berths went from 3 to 2 a cell.
- `smoke_shipyard`: the manifest's layout.

### Play-test batch 11, part 1 — combat rules, craft, lasers, flares, battle stations (2026-10-22)

#### Changed
- **No hostile toggle (T)**: a contact turns hostile when you or your craft
  hit it, or when it sees one of your missiles locked on to it inside its
  sensor range (no longer the moment a missile is launched); craft flying
  about don't provoke it.
- **Craft start on their role's order**: fighters and bombers Strike,
  interceptors (Hornet, laser drone) Intercept, recon and EW drones Recon,
  repair and salvage drones Escort; fighters aim at the **weak spot** (the
  target's most damaged system outside its hull).
- **Craft survive more**: fighters 80 hull points (were 40; Hornet 50,
  Mantis 140), drones half as many again; they break off at 70 / 50 / 30 %
  hull by risk (were 60 / 35 / 15) and head home while they still have
  1.5 × the propellant the trip back takes.
- **Lasers in three tiers**: Yb-fibre laser turret (light: 35 mm, 3 km,
  600 kW, uncommon), Nd:YAG pulse laser turret (the old pulse laser: 80 mm,
  5 km), free-electron laser turret (heavy: 170 mm, 8 km, 4 MW, epic). The
  craft lasers are the light (Yb-fibre) tier.
- **Flares one at a time**: 0.25 s apart, from each launcher round the ship
  in turn; Space puts out three; the policy up to three per missile inbound
  (one missile used to empty every tube). Each trails fading sparks; they
  glow brighter.
- **Battle stations** shut the emergency doors between rooms of a kind
  (stacked corridors no longer vent together) and spread general and
  damage-control hands to every room with systems in it and nobody there
  (back to their stations at stand-down).
- **Damage control patches on its own** (C still sends a team at once).

#### Tests changed (and why)
- New `test_batch11_combat` (6): no T action; role defaults; weak spots;
  breaking off at 45 % hull and for the trip home (600 m/s away: yes, 50:
  no); the laser tiers; four flares at 0.0 / 0.27 / 0.52 / 0.77 s from four
  places, with trails; the destroyer's corridors held apart at battle
  stations, the crew spread and back.
- `smoke_main`: a passive target turns hostile on seeing our missile
  (mutation-checked); no T. `smoke_campaign`: hostility set directly.
- `test_m11_countermeasures`: flares go out one at a time; the "too early"
  case puts out one flare (a staggered burst can hand a missile from flare
  to flare until it loses the ship).
- `test_air_wing`: a fighter may break off for the propellant home.
- `smoke_shipyard`: the Weapons palette has the two new lasers.

## [0.15.0] — 2026-10-22 — Play-test batches 9–10, Milestone 13 part 3: contracts, the bank, the Moon's ground, new hulls

### Milestone 13, part 3 — retrieve contracts (2026-10-22)

#### Added
- **Retrieve contracts** from the salvage boss: a pod (flight recorder,
  survey capsule, data core…) lost at a charted station, guarded by one or
  two ships. Accepting sets the course and the fight; in flight the pod's
  beacon is marked 6 km out; **G** alongside it (within the beacon's reach —
  8 km with a salvage drone — and 5 m/s, with 6 m³ free in the hold) stows
  it; it pays once you dock at the station that offered the work. Abandoned
  or lost with the ship, it is gone. Milestone 13 is complete.

#### Tests changed (and why)
- New `test_m13_retrieve` (2): offers (21 of 160 over 40 boards, back to
  the offering station, guarded), accepting (course and guards, nothing
  loaded), delivery only at that station with the pod aboard (mutation-
  checked), lost with the ship.
- `smoke_campaign`: a retrieve sortie — the pod marked 6.0 km out, G
  refusing from there and stowing it alongside, paid on docking.

### Play-test batch 10, part 3 — more hulls at the dealer, super-heavies (2026-10-22)

#### Added
- **Six new hulls** (tools/make_capital_templates.gd), after Elite Dangerous
  and Halo lines: Halberd Frigate (hammerhead prow), Wyvern Battlecruiser
  (tapered bow, swept wings with engines), Anvil Heavy Cruiser (hammerhead,
  short wings), and three super-heavies — Sovereign Supercarrier (forked
  prow, 30 craft), Colossus Battleship (hammerhead, two-deck wings) and
  Leviathan Dreadnought (broad wings, 6 railguns) — the three with a
  three-level bridge tower. 2.7 kt to 12.5 kt, 18,153 to 92,859 cr.

#### Changed
- **The template tool works cell by cell** (prow shapes, wings, tower
  height, extra RCS rows); it still writes the Destroyer, Cruiser and
  Carrier byte for byte as before.
- **The dealer fills in as it opens**: what it knows of each template is
  worked out once a session, cards come one a frame in price order, and a
  card's 3D view (drawn once, closer and from higher up so the shape reads)
  is only built when it scrolls into sight. Before, every card was built at
  once when the shipyard opened.

#### Tests changed (and why)
- New `test_batch10_dealer` (2): the six hulls valid and for sale (compiled
  in 14–78 ms), the super-heavies over 10 kt with the bridge three levels
  up; their shapes (heads 8/10/12 cells over necks 4/6/8; a 4-cell fork;
  wings 18 and 24 cells across against 10 and 12 amidships).
- `smoke_shipyard`: waits for the dealer's twelve cards (one a frame).

### Play-test batch 10, part 2 — the Moon's ground, landing, Earth re-entry (2026-10-21)

#### Added
- **NASA's LOLA elevation map of the Moon** (`data/moon/lola_elevation.bin`,
  5.9 MB: 8 pixels a degree, whole metres; `tools/convert_lola.py` from the
  SVS 4720 CGI Moon Kit) plus seeded detail under 90 m finer than its
  pixels.
- **Lunar landing**: touch down slower than 4 m/s over the turning surface
  and the ship rests there until it thrusts away; faster is a crash. The
  own-ship card's GROUND line (height above ground, vertical speed, speed
  over ground); a GROUND alert below 3 km coming down too fast; notices on
  touchdown, lift-off and impact.
- **The ground drawn below 11 km**: a mesh of the real heights out to the
  horizon (115 km at most), the colour map on it, its heights growing in
  over the first 2 km and fading into the flat map at its edge.
- **Earth re-entry cutscene**: crossing 100 km, a plasma sheath builds and
  the hull comes apart module by module over 7 s before the debrief.

#### Changed
- **No instant loss at the Moon's 11 km**: the ground is where the ground
  is. The orbit panel's TERRAIN line is the band the summits reach into.

#### Tests changed (and why)
- New `test_batch10_surface` (5): the map (2880 × 1440; a 1° scan −7.8 …
  10.0 km; 10.4 km near the Selenean summit), a landing from 3 m at 1 m/s
  (landed at 3.3 m/s, 120 s without moving, the frame keeping up; off again
  on the main engines), a crash from 5 km (128 m/s) with no loss at the old
  11 km line, the ground mesh below 11 km (none at 20 km), re-entry
  breaking up all 64 modules. Checked in a windowed render too.
- `smoke_campaign`: losing the ship over Earth now waits for the 7 s
  re-entry cutscene before the debrief (checked that it played).
- `test_release`: the LOLA attribution row needs its credit line too.

### Play-test batch 10, part 1 — crew under fire, boarding, models (2026-10-21)

#### Fixed
- **Crew killed by venting while they should have been suited**: general
  quarters ended the moment no contact was hostile, with its fighters still
  out, its missiles still in flight or the next ship arriving. Now
  **battle stations** hold while anything hostile is about (a hostile ship,
  its craft, a missile, fire taken in the last 10 s) and the crew **stand
  down** only after 10 s confirmed clear.
- **Foam didn't put fires out** when the hit that started the fire also cut
  the room's power: the bottles are self-contained now.

#### Changed
- **Foam is per sortie**: two charges per room every sortie (no more yard
  recharge job); a notice when a fire takes hold and when foam is deployed.
- **Crew fix their own room first**: with a working workshop aboard, fit
  crew in a room with a damaged system patch it where they stand (damage
  control and engineers 0.5 hp/s each, others half; × SYS pips, workshop
  bonus, damage-control tech) up to 75 %; damage-control teams aren't sent
  to it.
- **Boarding takes half the time**: the gangway mates in 5 s (cuts in
  22.5 s), the party crosses in 2.5 s, moves 2.5 s a room, cuts a locked
  hatch in 10 s, and fights resolve twice as fast (same odds). The same
  rules for enemy boarders.
- **Radiator fins fold along their length**, like the flat panel.
- **Models**: engine bells grow with thrust (620 kN 1.30 × 2.06 m to 1.45 MN
  1.50 × 3.43 m) with a gimbal, chamber, feed lines and cooling bands, the
  plume as wide; RCS blocks with five nozzles (the heavy one bigger, with an
  armour cap); gun turrets with mantlet, recoil sleeve, muzzle brake (or
  an emitter lens), sight and hatch; PD with an ammunition drum and a
  fire-control dish; fighters with nose cone, intakes, pylons and stores,
  spine and tail light; drones with an antenna, sensor ball, nozzles and
  framed panels; missiles with a nozzle, a band and canards. The docking
  collar and the gangway are **hexagonal** (the gangway ribbed). The berth's
  gantries and clamp arms are **red truss** with a **rotating beacon** on
  each tower and a clamp pad on the hull.

#### Tests changed (and why)
- New `test_batch10_crew` (3): in-place repair (the reactor 30 → 75 % in
  31 s by its engineer; no team sent; nothing without a workshop), foam
  without power and per sortie (an older save's used charges ignored),
  the boarding timings.
- New `test_batch10_models` (5): the fin's folds run out from the hull (12
  panels 0.4 → 8.4 m, fold lines across its width), engine bells by thrust
  and a plume width each, the hexagonal collar (6 edges, 6-sided hatch)
  and gangway, 4 beacons on 44 red truss bays turning 0.30 rad in 0.1 s,
  craft (fighter 19 parts, drone 27; were 10 and 16) and missiles (still
  two surfaces). Checked in a windowed render too.
- `smoke_encounter`: battle stations hold with every contact passive, a
  hostile missile counts, stand down 10 s after nothing is left.
- `test_feedback_pass`: foam charges are not saved into the next sortie.

### Play-test batch 9, part 7 — effects, the opening range, craft fire rate (2026-10-21)

#### Added
- **EMP static**: a part an EMP has reset crackles with light-blue static
  outside the hull until it recovers; with three or more down it crawls
  over the whole hull.
- **Jump spool-up**: holding B, rings of light gather round the hull, spin
  up and close in on its middle, brightening until the jump.
- **The docking hall behind the berth**: a minimal station interior drawn as
  the 3D view's sky — ribbed walls, two catwalks with amber lamps, a gridded
  deck with teal guide lines, light strips overhead.

#### Changed
- **The encounter's lead starts 4 km out** (was 2.5 km), so the first
  seconds aren't spent inside its guns' and fighters' reach. 5 km was tried
  first: the balance sim's scripted (non-manoeuvring) player then lost the
  mission-5 1v1 to missile salvos.
- **Craft guns fire at half their old rate**: Hornet interceptor 600 → 300
  rpm, Wasp fighter 300 → 150 rpm (yours and the enemy's alike; same
  magazines, so they stay out longer). Balance sim, mission 5: 1 ship won
  in 12 s (as before); 2 ships survived the 480 s limit at 84 % (lost at
  333 s before); 3 ships lost at 401 s (259 s before).

#### Tests changed (and why)
- New `test_batch9_effects` (4): EMP static (10 parts reset → 10 crackling,
  60 arcs; gone on recovery), the jump spool (3 rings, the end ring 20.8 →
  7.5 m from the middle, glow 0.26 → 0.77, gone when B is let go), the
  berth's sky shader, the 4 km opening range and the craft gun rates.
  Shaders and effects also checked by a windowed render.
- `smoke_encounter`: brings the two wingmen alongside at fixed close
  positions instead of `Main.CONTACT_OFFSETS` (which moved out); the checks
  are about the fight once they are close.
- `smoke_campaign`: puts the mission-1 target at the old 2.5 km start
  before the scripted burst — from the new 4 km angle its first round
  disabled the ship before it could fire back, and the checks need its hits.

### Play-test batch 9, part 6 — cargo contracts, remote salvage (2026-10-21)

#### Added
- **Cargo contracts** on the missions board — work without a fight. About
  one offer in three once a second station is charted: 20–90 m³ of freight
  (medical supplies, reactor spares, colonist mail, …) to another station,
  paying 120 cr + 4 cr a m³, more the further the jump. Accepting loads it
  into the hold (refused if there is no room) and sets the course; it pays
  on arriving there (at LAUNCH, after the jump). It has a line of its own in
  the hold, the last to vent; banking leaves it aboard; jettisoning it,
  abandoning the contract or losing the ship fails the contract.

#### Changed
- **Salvage drones carry the salvage beacon**: with one on the wing (aboard
  or out, not lost), **G** reaches a disabled wreck or derelict 8 km off
  instead of 2 km, paying for the whole wreck at once. They no longer cut
  systems off one at a time into spare parts (removed with their 30-part
  load and the delivered-parts hand-over); otherwise they escort. The HUD's
  BEACON line and the 2 km refusal mention the drone.

#### Save format
- None: the freight lives in the hold's cargo dictionary (schema 13).

#### Tests changed (and why)
- New `test_batch9_cargo` (4): offers (40 of 120 over 30 boards, 290–830
  cr, none with one station charted), accepting (a 217 m³ load refused by a
  216 m³ hold; 20 m³ loaded, the course the Moon, the chosen fight size
  kept), delivery (banking keeps it, saved, paid once at the Moon), failure
  (jettisoned, abandoned, lost with the ship). Mutation-checked: a
  `bank_cargo` that wipes the freight fails it.
- `test_m15_drones`: the salvage-drone test now measures the beacon reach (8
  km with the drone, 2 km without or once it is lost) and that a drone out
  for 60 s cuts nothing (90 % → 90 % intact); the old cutting test is gone
  with the behaviour. Mutation-checked.
- `smoke_wing`: the beacon reach follows the wing, instead of salvage
  drones' parts going into the hold.
- `smoke_shipyard`: accepting the first offer — a cargo one keeps the
  chosen fight size and loads its freight (it expected the offer's ship
  count, 0 for cargo).

### Play-test batch 9, part 5 — the bank, a branching tech tree (2026-10-21)

#### Added
- **The station bank** (Hangar & bank): a deposit earning 1 % a sortie,
  compounding (deposit / withdraw any amount), and three loans, one of
  each at a time — Dockyard credit 1,000 cr at 5 % over 5 sorties, Guild
  loan 5,000 cr at 4 % over 10, Shipbuilder's mortgage 25,000 cr at 3 % over
  20 — whose interest and instalments (what is owed over the sorties left)
  are taken on docking; a shortfall adds 10 % of it; repay part or all at
  any time. The directory's Hangar line shows what you owe.

#### Changed
- **The tech tree branches left to right**: from the Shipyard charter
  (150 cr) out to 15 upgrades (43 levels) in four branches, a lane each,
  with lines from each node to what it opens; a node's first level needs
  its parent, each later level the one before. New upgrades: jump
  calibration (−5 % jump Δv a level), PD fire control (+10 % PD rate of
  fire), sensor suites (+10 % range), hangar crews (+15 % craft
  turnaround), crew academy (−20 % training), crew welfare fund (−20 %
  wages), bounty licences (+10 % bounty). Levels bought before keep, and go
  on from there.

#### Save format
- **Schema 13**: the bank's deposit and loans (none in older saves; the
  original kept as `.v12`).

#### Tests changed (and why)
- New `test_batch9_economy` (4): the tree's shape (one root; 1, 3, 6, 12,
  10, 8, 2, 1 levels a column), buying in order, old levels kept, the graph
  a node per level; the newer nodes (jump 487 → 414 m/s, wages −20 %,
  training −40 %, sensors 25 → 30 km, PD 300 → 390 rpm, the gun data
  unchanged); the bank (1,000 → 1,020 in two sorties, a 1,000 cr loan paid
  off in five for 1,163 cr, a missed instalment's penalty, early
  repayment); v12 → v13.
- `test_feedback_pass`: an upgrade needs the charter first.
- `smoke_shipyard`: the station-tech page holds the graph.

### Play-test batch 9, part 4 — pilots, crew quarters, experience, wages (2026-10-21)

#### Added
- **Pilots**: a new post. Every fighter, bomber and interceptor needs a fit
  pilot aboard to launch ("no pilot aboard for Wasp F1 — post someone as
  pilot"); drones fly themselves. The pilot flies out with the craft, comes
  back with it, and dies with it if it is lost. The standard complement has
  a pilot per fighter.
- **Experience and training**: crew rise a level with sorties served (3, 8,
  15) or training at the station (60 / 140 / 260 cr), up to a specialist
  with a title per post (Tactician, Reactor chief, Rigger, Gunnery chief,
  Marine, Surgeon, Bosun, Ace). Levels already sped repairs and treatment;
  now gunners fire 3 % faster and engineers draw 2 % more from the reactors
  per level of their post's average.
- **Wages**: each sortie (on docking) 1 cr per crew member and 2 cr per
  level — a frigate of rookies 24 cr; short of credits, the debrief says by
  how much.

#### Changed
- **Crew quarters**: all eight departments as drop targets, the crew as
  badges with placeholder portraits (a face and hair from the name, the
  post's colour, initials), level, sorties and wage — drag a badge onto a
  department to repost them (no role menus), ▲ to train, ✕ to dismiss.
  Portraits in the hiring hall too.

#### Save format
- **Schema 12**: crew entries carry the sorties they have served; a v11
  vessel with fighters gets general crew posted as pilots (one per fighter,
  as far as it has general crew). The original is kept as `.v11`.

#### Tests changed (and why)
- New `test_batch9_crew` (5): a fighter grounded without a pilot, the pilot
  out and back with it and lost with it, drones need none; the v11 → v12
  migration (one pilot posted, original kept); levels with sorties, wages
  each sortie, training to a specialist; skilled gunners 120 → 131 rpm and
  engineers ×1.06; a department posts a dropped crew member.
- `test_m15_scaling`: the frigate's complement includes its pilot; loops
  over the specialist posts include pilots.
- `test_boarding`: the default frigate crew has a pilot (11 general, 1
  pilot).
- `smoke_wing`: the lost fighter's pilot is lost with it; a new one is
  posted before the replacement launches.
- `smoke_campaign`: the tow checks count the crew's wages paid on docking.

### Play-test batch 9, part 3 — the service bay and the quartermaster (2026-10-21)

#### Changed
- **One service bay** (DRYDOCK) replaces REPAIRS and ARMOURY: three large
  buttons — REPAIR (spare parts), REARM (rounds, point defence, missiles
  and flares) and REFUEL (propellant and the jump reserve, with the Δv it
  gives) — each priced and each buying what the credits allow
  (`ServiceYard.refuel` / `rearm`; the main tank before the reserve;
  rounds, then PD, then missiles); the damage report and the cargo hold
  below.
- **The quartermaster** has a page of its own in the CONCOURSE: the rarer
  parts, and **spare parts in any amount** (a counter in tens, 25 cr per
  10 — `PlayerProfile.buy_spare_parts(amount)`, `parts_price`). The hangar
  no longer sells them.
- The berth's service cards lead to the service bay; refusals say "refuel
  in the SERVICE BAY".

#### Tests changed (and why)
- New `test_batch9_services` (3): partial refuel (main tank first, 65 t for
  65 cr, the magazine untouched); rearm fills rounds and PD at the yard's
  rate and clears the stores record; spare parts priced by amount.
- `smoke_shipyard`: the SERVICE BAY's three buttons, REFUEL and REARM each
  filling only their own stores, no parts button in the hangar, the
  QUARTERMASTER selling 120 parts for 300 cr (replaces the ARMOURY check);
  the directory's SERVICES line.
- `test_m13_jumps`: refusals point to the SERVICE BAY.

### Play-test batch 9, part 2 — the builder (2026-10-21)

#### Changed
- **The 3×1 radiator is a fin**: one cell on the hull, standing its three
  cells straight out (it lay across the hull before; designs saved that way
  keep it). Refused where hull is in the way (`fin_blocked`); rejects as
  much as lying flat. Stored as rotation 4 (`ShipGrid.FIN_ROTATION`).
- **Bigger rooms do more**: every cell beyond a room's first adds, with
  diminishing returns — engine rooms main thrust, reactor rooms reactor
  output (up to +25 %; the stock Frigate +11 % / +15 %, Destroyer +24 %), a
  hangar's free deck its craft's turnaround (up to ×2). The room card and
  the stats panel say what size does (workshops, medbays and bridges
  already scaled; now it is shown). Every design with roomy engine and
  reactor rooms is a little faster and better powered.
- **Point defence draws from the magazine**: 15 % of its mass beside guns
  (all of it without guns), one store for every mount, kept between
  sorties and restocked at the yard. The Frigate: 600 PD rounds (was
  2 × 200 built in) and 1,020 gun rounds (was 1,200). A warning when there
  is PD but no magazine.
- **The grappling arm** lies folded along four cells (a 4 × 1 mount) and,
  holding, unfolds and telescopes out to the target's hull (up to 60 m),
  folding back when it lets go. The Frigate's and Corvette's arms were
  moved to fit (`tools/fit_grapple_arms.gd`); a saved design whose arm no
  longer fits is slid to the nearest spot on load, or flagged.

#### Tests changed (and why)
- New `test_batch9_builder` (4): the fin (one hull cell, three out, valid,
  saved and loaded, flat-panel rejection; refused when blocked; rotation 1
  still lies across); room factors on three templates (engine thrust in
  the stats and in flight; diminishing gains); PD from the magazine (600
  rounds, more with a dense magazine, restocked, warned without); the arm
  (4 cells, the Frigate valid, unfolds to a grip 39 m out and folds back).
- `test_m7_weapons`, `test_m10_contacts`, `test_m9_weapons_crew`,
  `test_turrets_and_collisions`: point-defence rounds are one store
  (`pd_rounds`), not one per mount.
- `smoke_shipyard`: the magazine line now reads "1020 rounds · 600 PD
  rounds"; the radiator search finds "3×1 — fin, 3 out".
- `test_blueprint`, `test_feedback_pass`: main thrust is the engines' times
  the engine rooms' factor.

### Play-test batch 9, part 1 — fixes and quick wins (2026-10-21)

#### Fixed
- **Our point defence fired on the escorted courier**: it had no side, and
  point defence takes an unaligned craft for hostile. It is on our side
  now (craft IFF spares it too). Measured: 300 PD ticks on it in 5 s
  before, none after.
- **Front and 3D views** shown alone now fill the width (they kept their
  narrow fixed widths).
- **Jumping into a fight half empty after a long trip** (asked): LAUNCH
  now docks you at the destination station on arrival, whose yard tops the
  tanks up again (credits allowing) before the sortie — the trip costs
  credits and propellant, not readiness.

#### Changed
- **The CoM orb** in the 3D views carries the centre-of-mass symbol's
  black quarters (seen from any side).
- **No incoming-round alert** (`RND`) in the banner.
- **Missile racks are red, saturation pods green**; each tube shows a
  white missile nose while its share of the load is aboard, fewer as they
  fire. The part info no longer says "a launch every 0.4 s".
- **Heavy RCS blocks come armoured**: 30 hp (was 10), 40 mm of shielding
  (was 5), gunmetal, 2.6 t (was 2.0).
- **The weapon strip shows the fuel left**: `FUEL ▮▮▮▮▮▮▮▯▯▯ 70 % · Δv 870 m/s`.
- **Artifacts show their orbit** once surveyed (apoapsis × periapsis,
  inclination, around what), question marks before.

#### Tests changed (and why)
- New `test_batch9_fixes` (4): PD on the courier (unaligned 300 ticks, ours
  0); missile noses 4 / 2 / 0 full, half, empty, rack red, pod green; heavy
  RCS 30 hp / 40 mm; artifact orbits (ISS 440 × 426 km 51.8°, Roadster
  1.66 × 0.99 AU, Voyager 1 escaping) and the unknown form.
- `smoke_shipyard`: the 3D and front views fill the row (700 of 700 px);
  arrival at the Moon with full tanks (80 of 80 t); the strip shows FUEL.
- `test_pass_a` (every alert follows its condition): a round on a
  collision course now raises no alert (it checked the `RND` alert).

## [0.14.0] — 2026-10-21 — Play-test batch 8: a rescue tow; enemies field the newer kit

### Enemies field the newer kit (2026-10-21)

#### Changed
- **Enemy ships carry the kit added since Milestone 14**, each from a
  mission (as the ship is fitted — wingmen as for earlier missions): a
  repair drone in place of the recon drone from mission 4 (25 %), a laser
  drone from mission 6 (30 %), Lancer laser fighters in the bay from
  mission 8 (30 %), and a gun turned pulse laser from mission 5
  (8 % × (mission − 4), at most 35 %, and only if the reactors carry its
  1,500 kW). These rolls have their own seed, so every enemy fitted before
  is unchanged. Over missions 1–12 the first are: repair drone m6 (a
  wingman), Lancer m8, laser drone m9, pulse laser m11.
- KNOWN_ISSUES: the "capital templates are plain" entry was stale (they
  were rebuilt as battleships, and Mars traffic includes destroyers); the
  laser entry and a Milestone 15 entry are brought up to date.

#### Tests changed (and why)
- New `test_enemy_kit`: the newer kit never before its mission, valid
  designs, lasers only within the reactors' output, all four seen by
  mission 12, deterministic.

### Play-test batch 8 — a rescue tow on call (2026-10-21)

"Currently ship is sometimes stranded and unable to jump back to
shipyard. Give an option to get tow rescued for credits."

#### Added
- **Rescue tow on call**: the jump home is refused under fire (a hostile
  that fired in the last 10 s), and a crippled ship facing one that keeps
  shooting could never leave. Now, holding **B** on through the refusal
  calls a station tug after 8 s (HUD: "JUMP blocked · hold: tow", then
  "TOW 7.2s 904cr"); **Tab › Call rescue tow** calls one any time (the first
  press quotes the fee, a second within 5 s confirms). The fee is the tow's
  (150 cr + 0.5 cr per tonne), twice that under fire; too few credits and
  it takes what there is. No propellant; craft and boarders still out are
  left behind, as in an emergency jump; the hold's excess is vented.

#### Tests changed (and why)
- `smoke_campaign`: under fire the jump is blocked and holding on brings
  the ship home for the hazard fee (904 cr for the Frigate); the Tab
  button quotes first and tows on the second press, at the plain fee
  (462 cr).

## [0.13.0] — 2026-10-21 — Milestones 14–15, play-test batches 6–7: artifacts, derelicts, drones, beam weapons, capital ships

### Milestone 15, part 2 — crew, damage control, medics and PD that scale with the hull (2026-10-21)

#### Changed
- **The standard complement scales with the ship** (`CrewRoster.complement`):
  a bridge watch per 200 modules beyond two; an engineer per reactor and per
  four main engines; a gun crew per two guns and per two launchers; damage
  control per 40 modules; a medic per 40 berths; security per 12 berths.
  A frigate's is unchanged (2 / 2 / 2 / 1 / 4 / 1); a destroyer's is 46
  specialists (was 13), a cruiser's 68, a carrier's 77. The crew page, the
  hiring tally and the stats panel use it.
- **Damage-control teams work at the same time**: one team per two fit
  damage-control crew (a frigate one, a destroyer three, a carrier eight);
  each patches its own system — [C] sends the next free team. The HUD shows
  "+N more" and the overview each system being patched.
- **Every medic treats a patient of their own** at once (was one patient at
  a time for the whole ship).
- **Point defence against the hull's size**: the shipyard stats panel shows
  DEFENCE — PD mounts against those the hull wants (one per 1,500 m² of
  outside surface) and the share of approaches they cover (48 directions;
  in arc and clear of the ship's own hull, as in flight) — and CRAFT (bays
  and racks).

#### Tests changed (and why)
- New `test_m15_scaling` (4): complements by template (frigate unchanged,
  capitals over three times the specialists, rosters filled to them);
  three DC teams patch three systems in 14 s together (mutation-checked:
  one team fails); six medics treat three wounded in one treatment time
  (13 s); PD wanted vs carried and coverage by template (all 100 %, ≤ 10 ms),
  one mount on a frigate 54 %, none 0 %; the carrier's craft.
- `test_m9_weapons_crew`: gunners by guns now one crew per two guns
  (`complement`, which replaced `suggested`).

### Milestone 15, part 1 — repair and salvage drones (2026-10-21)

#### Added
- **Repair drone** (drone rack (repair), uncommon): flies to a damaged
  system outside a friendly hull — your own ship's first — holds 12 m off
  its mount and patches it at 1.5 hp/s to 75 %, the crew's field-repair
  limit, without their walk or airlock. Destroyed parts still need the
  yard; a part the crew is already on is left to them.
- **Salvage drone** (drone rack (salvage), uncommon): strips a disabled
  hostile or a derelict (the wing's target first, else the nearest within
  8 km of your ship), cutting its most valuable system free every 4 s into
  half its worth in spare parts (a reactor is lifted out, no blast). With 30
  aboard, or nothing left to cut, it flies home; the parts go into the hold
  (at risk until banked). A stripped wreck is worth less to a beacon.
- Both escort when there is no work, go back out on their own once
  serviced when there is (auto relaunch), and explain their role in the
  WING tab and the shipyard.

#### Tests changed (and why)
- New `test_m15_drones` (3): two systems patched to exactly 75 % in 20 s,
  a destroyed mast left alone, no crew repair involved, then escort
  (mutation-checked: no patch at 0 hp/s); 6 systems cut, 30 parts
  delivered after 126 s, wreck 90 % → 58 % intact, no reactor blast;
  racks in the catalog under Drones.
- `smoke_wing`: delivered parts go into the hold.

### Play-test batch 7 — jumps in Δv; the nav chart sets a course (2026-10-21)

#### Changed
- **Jumps cost Δv, the same for every ship** ("space travel should be in
  terms of delta v rather than tons of fuel"): 70 m/s plus 160 m/s per
  tenfold of distance — home 70 m/s, Earth ↔ Moon 487 m/s, Earth → Mars
  928 m/s; Voyager 1 2,512 m/s round trip. Each ship pays in propellant by
  the rocket equation at its main-engine Isp (the stock ships, all Isp
  900 s, burn what they did: Frigate 33 t for the Moon). The nav chart,
  route button, artifacts list ("round trip Δv … of this ship's …", amber
  when out of reach), ARMOURY ("JUMP Δv"), refusals, the in-flight JUMP
  alert and the logs speak Δv.
- **The nav chart sets a course; LAUNCH jumps** ("selecting a different
  launch point should not jump until the user presses launch"): clicking a
  body lays in the course (cyan ring and line, "◎ → LUNAR ORBIT · Δv
  487 m/s"); LAUNCH tops the tanks up at the berth, jumps, then flies the
  sortie there. Accepting a contract elsewhere sets its location as the
  course instead of jumping at once. A course is not saved; with none, an
  accepted contract's location is used. A course beyond what the ship
  carries even with full tanks is refused when picked; a jump the tanks
  can't pay at launch is refused with the refuel price.
- The directory's Nav chart line and the berth's next-sortie card show the
  course.

#### Tests changed (and why)
- `test_m13_jumps`: the cost test is now Δv by distance (same for the
  Frigate and the Cutter, 487 m/s; the Cutter burns 8.5 t, the Frigate
  33.2 t), the rocket equation both ways, a lower Isp burns more; the
  contract test checks it sets the course and the launch pays (it used to
  jump on accepting); new `test_the_nav_chart_course_waits_for_launch`.
- `test_m12_shipyard`: an accepted contract sets the launch point (it used
  to move the berth).
- `test_m14_artifacts`: Voyager 1 is refused for needing more Δv (2,512 vs
  1,557 m/s); a survey from the Moon is allowed with a course there.
- `smoke_shipyard`: clicking the Moon lays in a course and leaves the berth
  at Earth (saved as Earth); LAUNCH still flies into lunar orbit; an
  accepted contract sets the course (it used to move the berth).

### Play-test batch 6, part 7 — the shipyard as a place (2026-10-21)

"More gameplay and immersive, and less spreadsheet tabs like."

#### Changed
- **A station directory replaces the row of tabs**: the shipyard's places
  down the left, by district — DRYDOCK (Berth, Refit bay, Repair crews,
  Armoury), CONCOURSE (Mission board, Crew quarters, Ship dealer),
  OPERATIONS (Hangar & bank, Station tech, Nav chart, Salvage odds) — each
  with a live line: amber when it needs you (repair jobs, a restock due,
  offers posted, an empty berth, cargo not banked, an affordable upgrade),
  teal when fine; credits and parts on top. It narrows beside the builder.
  Page headings name the district and place.
- **The berth** (STATION): your ship in a docking bay — deck plate, guide
  lines, gantry towers with clamp arms, work lights — filling the page, with
  its name plate, the service tags and the **dockmaster's log** (dockmaster,
  repair crews, quartermaster, brokers, crew quarters) over the view.
- **Crew quarters**: a roster board — a card per department, who serves
  there against the standard complement (amber when short), their post and
  ✕ to dismiss — and a hiring hall of cards, one per spacer.

#### Fixed
- README: the capital ships were listed as a row of the shipyard's
  sections table; they are a paragraph under it now.

#### Tests changed (and why)
- `smoke_shipyard`: the directory has an entry per section, each with a
  live line, and the berth shows the dockmaster's log (new checks).

### Play-test batch 6, part 6 — beam weapons (2026-10-21)

#### Added
- **Lasers for ships, fighters and drones**: a beam has no round — each
  pulse reaches the first hull on its line at once (no travel time, no
  recoil, nothing for point defence to shoot), with penetration falling to
  half at full reach.

  | Part | Carried by | Pulse | Reach | Penetration (close / full reach) | Cost |
  |---|---|---|---|---|---|
  | Pulse laser turret (epic) | ships, any outer face | 30 a minute | 5 km | 80 / 40 mm | draws 1,500 kW; 1,500 kW of heat while firing; no magazine |
  | Fighter bay (Lancer laser) (rare) | hangar | 90 a minute | 1.5 km | 14 / 7 mm | 40 charges |
  | Drone rack (laser) (rare) | outer face | 60 a minute | 2 km | 14 / 7 mm | 30 charges; flies as an interceptor (missiles first) |

  A craft's charges are recharged aboard from the carrier's power, not its
  magazine. Fire control holds a beam until its locked target is in reach.
  A beam's steering mirror lays it on a craft or missile within 2° of the
  barrel, so a laser drone can hit a missile its nose lags by metres. The
  shipyard part info shows reach, falloff, power and heat; the HUD weapon
  strip shows "on power" for an all-laser ship. Pulses are drawn as bright
  lines that ride with both ships and fade in 0.18 s, with a capacitor
  "zap" aboard.

#### Changed
- **Hangars & craft › Fighters / Drones** is decided by the rack (drone
  racks are drones), so the armed laser drone sorts with the drones.
- **Gun heat** counts only kinetic guns for rounds fired; beam pulses add
  their own mount's heat.

#### Tests changed (and why)
- New `test_beams` (6 tests): a pulse strikes in the tick it fires (56.3 mm
  at 3 km, expected 56.0), no round in flight, no rounds spent; held beyond
  reach, stops at 5 km fired blind; +1,440 kW of power demand over the
  autocannon, +180,000 kW of heat on the pulse's tick (1,500 kW × 2 s);
  a Lancer spends a charge a pulse, passes through a friendly craft (IFF),
  recharges 40/40 with the carrier's magazine untouched; a laser drone shoots
  down a missile (fails with the steering mirror off — mutation-checked);
  parts and palette sections; a pulse is drawn 589 m long and fades.
- `smoke_shipyard` (palette): the Weapons list has 11 entries (the pulse
  laser turret joins the guns).

### Play-test batch 6, part 5 — capital ships as battleships (2026-10-21)

#### Changed
- **Destroyer, Cruiser and Carrier rebuilt** (`tools/make_capital_templates.gd`)
  from "a flat flimsy plank" into battleships: a taller hull (3–4 decks)
  narrowing to a stepped, sloped prow; a two-deck superstructure amidships
  (quarters, bridge on top, mast); 80 mm plates down the flanks and 40 mm on
  top and the bow; a main battery on the centreline — heavy kinetic cannons
  ahead of the superstructure and superfiring on its roof, the Cruiser
  with two railguns — autocannon secondaries in the flanks and a ventral
  pair, 10–16 point-defence mounts, missile racks.

  | | was | now |
  |---|---|---|
  | Destroyer | 960 t, 8 autocannons, no armour | 3,002 t, 3 heavy guns + 8 autocannons, 536 plates, 0.27 g |
  | Cruiser | 2,169 t, 14 autocannons | 4,987 t, 4 heavy guns + 2 railguns + 12 autocannons, 816 plates, 0.26 g |
  | Carrier | 1,954 t, 6 autocannons, 4 hangars | 6,512 t, 2 heavy guns + 10 autocannons, 6 hangars (16 craft), 1,008 plates, 0.20 g |
- **The dealer sells rarer parts with the ship**: a template's non-common
  parts (heavy cannons, railguns, missile racks) are priced at the
  quartermaster's rates plus the margin and banked when you buy it.
  Destroyer 19,466 cr, Cruiser 37,237 cr, Carrier 34,084 cr (crew included).
- **The chase camera sits back in proportion to the ship** (frigates and
  smaller unchanged); the HUD schematic clips to its panel.

#### Tests changed (and why)
- `test_m12_shipyard`: the dealer's price includes the rarer parts; the
  capital-ship test checks a main battery, armoured flanks, a superstructure
  and that the rarer parts come with the ship (it used to require common
  parts only). Compile times: 14.9 / 27.1 / 36.0 ms.
- `test_feedback_pass` (templates fly on a new profile): the fresh profile
  is given the rarer parts the dealer sells with the template before the
  check; without them the capital ships now (deliberately) fail it.

### Play-test batch 6, part 4 — builder: parts list, radiators, armour, wrecks (2026-10-21)

#### Changed
- **The builder's parts list is regrouped**: eight categories, each in
  sections (e.g. Weapons › Guns, Point defence, Missile launchers,
  Countermeasures & EW; Hangars & craft › Fighters, Drones), with headers,
  rarest first within a section.
- **Radiators 1×3 or 3×1**: the long radiators (the 3-cell panel, now named
  "Radiator panel (3 cells)", and the heat-pipe radiator) are listed both
  ways round (along the hull, across it).
- **Armour stands out from bare hull**: gunmetal slabs, glossier, one panel
  per cell, a little thicker (28 / 45 cm).
- **Wrecked blocks keep their shape**: no longer shrunk (leaving gaps), but
  full size, charred and dented — faces pushed in, edges and corners where
  they were, so they still meet their neighbours.

#### Tests changed (and why)
- `smoke_shipyard` (palette): counts pickable rows (section headers are not
  pickable); a search for "radiator" now finds four entries (both
  long radiators, each both ways round); the Weapons list opens on
  its "Guns" section.

### Play-test batch 6, part 3 — reduced-rate auto-fire and fairer multi-ship fights (2026-10-21)

#### Added
- **Auto-fire at a reduced rate**: a policy's auto-fire fires at its own
  share of the guns' rate (default 50 %, POLICY tab, 25 % steps), saving
  rounds and heat; your own trigger always fires at the full rate.
- `tools/balance_sim.gd`: the real flight scene, headless, a scripted
  player against 1–3 ships at missions 3, 5 and 7.

#### Changed
- **Multi-ship encounters are fairer.** Before: a scripted stock Frigate
  lost every 1v2 and 1v3 within 14–20 s. After: 1v2 survives to the 480 s
  limit at missions 3 and 7 (lost at 327 s at mission 5); 1v3 is lost at
  188–273 s; 1v1 is still won in 3–10 s.
  - Only the lead starts close; wingmen arrive from range and must be found.
  - Wingmen are fitted as for earlier missions (mission − 2, − 3): at
    mission 7, 109 and 106 armour plates against the lead's 140.
  - Enemy guns fire as automation: the lead at 70 % of the rated rate,
    wingmen at 45 %.

#### Fixed
- **A breached bridge disabled a ship whose crew were in spacesuits**: at
  general quarters the crew now keep command of a vented bridge. This, not
  the guns, was how most multi-ship fights were lost.

#### Tests changed (and why)
- `smoke_encounter`: checks the wingmen start far out, then brings them
  alongside to test selection and roles as before (stated as scaffolding).

### Play-test batch 6, part 2 — fighters that carry on, a tidy WING tab, screens that scroll (2026-10-21)

#### Added
- **Fighters move on**: once their target is beaten they strike the nearest
  combat-ready enemy; with none left they come home.
- **Fighters rearm on their own**: an empty gun brings a craft home at any
  risk setting; a craft that came home by itself relaunches once refuelled
  and rearmed while there is a fight ("Back out after rearming", on by
  default). Recalled craft stay home.
- **WING tab redone** as a compact table: a row per craft (state, hull ·
  fuel · ammo, order, risk, aim, ▲ out / ▼ in), wing-wide launch / recall /
  order / risk / back-out controls on top, roles as tooltips, "How they fly"
  folded away. A Carrier's twelve craft fit the drawer.
- Tests: `test_wing_batch6.gd` (3; mutation-checked on moving on).

#### Fixed
- **Screens that ran off the bottom**: every Tab-overview tab and the F1
  controls list scroll.

### Play-test batch 6, part 1 — big-fight performance (2026-10-21)

#### Fixed
- **Lag with many fighters and thousands of rounds.** Measured with
  `tools/profile_frames.gd` (new modes `--carrier`, `--carriers`):
  the usual three-ship fight 77 → 139 fps; your Carrier against three
  frigates (15 craft, ~1,750 rounds) ~34 → 50 fps; four carriers (46 craft,
  ~2,100 rounds) 7 → 20 fps.
  - Rounds that can't reach a ship sleep (no hit test, no tidal term) and
    settle the tidal pull on waking; awake rounds reuse last tick's pull and
    test a bounding sphere before the hit box.
  - Point defence fires a third as many, three times heavier rounds (300 rpm,
    0.3 kg, 18 mm penetration, 2.6 m flak radius): the same damage rate, and
    PD rounds had been 69 % of everything in flight. Its magazine holds 200
    rounds (the same 40 s of fire). It gathers its targets once per tick.
  - Craft think at 30 Hz, avoidance at 15 Hz; collisions skip pairs that
    can't collide; tracers are built on the GPU; the HUD ship schematic
    redraws at 10 Hz.
  - At most 3 simulation ticks per frame (was 8; still 8 when
    fast-forwarding): an overloaded fight runs a little slower than real
    time instead of stuttering.
  - Craft on final approach (within 150 m of their rack) stop keeping apart
    from other craft: two landing at neighbouring racks could hold each
    other off for ever.

#### Tests changed (and why)
- `test_m8_polish` (60 Hz budget): the duel's load is now > 40 rounds in
  flight, not > 100 — point defence fires a third as many.
- `test_combat_ai` (flares once armed): the defending ship's point defence
  is off; the heavier PD rounds now kill the missile before flares are due.

### Milestone 14, part 2 — derelicts that stay, are salvaged again and break up (2026-10-20)

#### Added
- **Derelict fields** (`DerelictField`): every beaten ship left behind at
  the end of a sortie stays at its location (six per place, newest kept).
  The next sorties there find the newest two 4–7 km out, silent, unpowered
  and marked on the HUD.
- **Salvage again**: G within 2 km of a derelict (when there's nothing to
  beacon in the fight) salvages it once per sortie — its scrap and crates
  halve for each earlier salvage, no bounty — and strips half of what is
  left. Measured: a wreck salvaged once paid 140 cr the second time.
- **Break-up**: each sortie flown anywhere, a derelict loses 15 % of what is
  left; below 10 % intact, or after 8 sorties, it breaks up and the debrief
  says so.
- Tests: `test_m14_derelicts.gd` (5); `smoke_campaign` finds the first
  sortie's wreck on the relaunch and salvages it again (mutation-checked on
  recording the field).

#### Changed
- Profile schema 11: `derelicts`; v10 saves start with empty fields and
  keep `.v10`.
- Contacts remember their hull template, mission and variant.

#### Tests changed (and why)
- `test_m14_artifacts` schema test: the current schema (now 11), not exactly 10.

### Milestone 14, part 1 — real artifacts to survey (2026-10-20)

#### Added
- **Eleven real objects** where NASA/JPL Horizons puts them on the
  scenario date (state vectors at 2026-10-19 12:00 UT, sources and
  uncertainty recorded per object and in `data/ATTRIBUTION.md`): the ISS
  and Hubble about Earth, LRO about the Moon, MRO and 2001 Mars Odyssey
  about Mars, and — about the Sun — the Tesla Roadster, New Horizons,
  Voyager 1 and 2 and Pioneer 10 and 11. JWST is left out (it sits at the
  Sun–Earth L2 point, which needs a rotating frame), and so is MAVEN (no
  ephemeris after March 2026).
- **Survey sorties** (HANGAR › MAP › ARTIFACTS, "Survey next sortie"): you
  start 3 km behind the object in its real orbit, with no hostile traffic.
  Close to within 500 m (or five times its size), match its speed within
  2 m/s and hold for 20 s with a working sensor mast: the survey fee is
  paid once and its record goes into the codex, shown on the MAP. The
  target card becomes a survey card (range, relative speed, sensor,
  progress, distance from the Sun) and the HUD marks the object.
- **Deep space**: surveys of the Sun-centred objects fly with the Sun as
  the central body (its real gravity; the Sun drawn at its true size, a
  point from Voyager 1; nothing casts a shadow). The jump out and back is
  paid at launch and must fit in the full tanks and the reserve, so these
  need a ship built for range: the Roadster takes 20 % of a ship's mass in
  propellant, Voyager 1 28 % (the Frigate Mk I carries 16 %).
- Real objects are heritage: they can't be damaged, grappled or salvaged.
- Tests: `test_m14_artifacts.gd` (6) — orbits against what is known (ISS
  427 km, 51.8°; Hubble 28.3°; MRO and Odyssey near-polar; Roadster
  0.986–1.664 AU; Voyager 1 172.1 AU, escaping), double precision, survey
  rules, the codex, schema 10; `smoke_survey.gd` (14 checks: the ISS survey
  end to end, Voyager 1 about the Sun, back to Earth), mutation-checked on
  the survey range and on the Sun casting a shadow.

#### Changed
- Profile schema 10: `survey_target` and `codex`; v9 saves have surveyed
  nothing and keep `.v9`.
- `CelestialFrame`: the Sun as a central body (`set_star_sun`),
  `icrs_to_pci_d` in double precision, the Sun's distance for its disc;
  `OrbitalBody.is_star`, `shadow_radius_m`, `disc_radius_m`.
- `tools/run_checks.sh` runs `smoke_survey` (12 stages).

#### Tests changed (and why)
- `test_m13_jumps` schema test: the current schema (now 10), not exactly 9.
- `test_release`: the Horizons row joins the credited sources.

## [0.12.0] — 2026-10-20 — Milestones 11–12, Milestone 13 parts 1–2: countermeasures, the station and dealer, jump fuel, Mars, alerts and audio, Steam preparation

### Milestone 13, part 2 — Mars, brokers, Sun-centred positions (2026-10-20)

#### Added
- **Mars**: a third location — the Martian Shipyard in a 300 km orbit
  (3.41 km/s, 113.4 min) about Mars with its real gravity (μ 42,828 km³/s²),
  radius, IAU pole and 24 h 37 min sol, thin dusty air (entry interface
  125 km, a butterscotch limb, no clouds or sea glint) and the USGS/NASA
  Viking colour mosaic (public domain). Deeper shelves (five parts up to
  epic, ×1.5) and heavier traffic (destroyers among the frigates,
  threat +2).
- **Information brokers** (decision 3): places not on your map are sold as
  charts on HANGAR › MAP — Mars for 1,500 cr. Earth and the Moon stay known
  from the start; contracts follow you to newly charted places.
- **Sun-centred positions**: Standish's Keplerian elements (JPL, 1800–2050)
  for the Earth–Moon barycentre and Mars, solved in double precision
  (`Vec3d`). They give Mars its own Sun (68° from Earth's on the scenario
  date) and the real distance every jump pays for. Earth–Mars at the
  scenario date: 229 million km, 64.6 t of propellant for the Frigate —
  one full tank.
- The map draws a line from Earth to each charted body, labelled with the
  real distance.
- Tests: `test_m13_mars.gd` (6): published Earth–Mars closest approaches
  (2018, 2020, 2025: within 0.02 %), Mars's perihelion and aphelion, the
  Sun agreeing with the Almanac up to precession, doubles vs single
  precision (0 m vs 1.9 km for a ship at Mars), Mars's orbit, air and Sun,
  brokers, traffic and shelves; mutation-checked on Mars's Sun and the
  broker's charge.

#### Changed
- Jump distances are the bodies' real separation at the scenario date
  (Earth–Moon 400,985 km: 33.9 t, was 33.7 t on a fixed 384,400 km).
- `OrbitalBody` gains `air_color` and `clouds_and_seas` (Earth's defaults
  unchanged). The data pack grows from 16.9 to 25.1 MB with the Mars map.

#### Tests changed (and why)
- `test_locations`: three locations in map order; the unknown-id fallback
  uses "jupiter", since "mars" is now real.
- `test_release`: the Mars map's attribution row joins the credited sources.

### Milestone 13, part 1 — jump fuel, per-station shelves and traffic (2026-10-20)

#### Added
- **Jumps burn propellant** (`JumpDrive`, `data/jump/jump_drive.tres`):
  ship mass × (8 kg/t + 18 kg/t per decade of distance in 1,000 km). The
  Frigate Mk I (618 t with full tanks) pays 4.9 t to jump home within a
  location and 33.7 t from Earth to the Moon.
- **A jump-only reserve**: the drive's own cell, a quarter of the tankage
  (20 t on the Frigate); engines and RCS can't burn it. Jumps take the main
  tank first, then the reserve; the yard refills both at launch or in the
  ARMOURY, which now shows the reserve.
- **Refused with the reason** when the propellant can't cover a jump (map
  and contracts: "refuel in the ARMOURY (n cr)"; accepting a contract you
  can't reach leaves the offer up). In flight a **rescue tow** brings the
  ship home instead — 150 cr plus 0.5 cr per tonne, or all the credits
  there are — so nobody is stranded. The jump alert shows the cost
  (`JUMP 3.2s 4.9t`) or the tow (`TOW 3.2s 412cr` for a dry Frigate).
- **Per-station shelves and traffic** (`Location`): the Lunar Shipyard
  stocks four parts up to rare at ×1.2 prices (hiring ×1.2 too); its
  traffic mixes corvettes and frigates one threat level higher. Earth is
  unchanged. The map shows each jump's cost and the station's terms.
- Tests: `test_m13_jumps.gd` (7, mutation-checked on the reserve and the
  relocation charge); `smoke_campaign` checks the jump home burns the
  quoted propellant and that dry tanks call the tow.

#### Changed
- **Backspace (restart) when your ship is still flying is a jump home**
  and is paid like one (it was a free way back).
- Enemy class names follow their hull ("Merlin-class corvette").
- Profile schema 9: the vessel's stores carry `jump_reserve_kg`; v8 saves
  start with a full reserve and keep `.v8`.
- The shipyard map is taller, so labels and costs don't run into the text.

#### Tests changed (and why)
- `test_m12_shipyard` schema test: expects the current schema (9), not 8.

### Steam release preparation (2026-10-20)

#### Added
- Version **0.12.0** (`application/config/version`), shown in the credits.
- Windows executable metadata — company **TheBooleanJulian**, product
  No Safe Orbit, © 2026 TheBooleanJulian — and a **Linux** export preset.
- **Credits & licences** in game (F1 → Credits & licences): the data
  sources, the sound credits and Godot's MIT licence with its third-party
  components; `tools/write_notices.gd` writes the same text as
  `THIRD_PARTY_NOTICES.txt` for the depots.
- **Fullscreen toggle** (F11, rebindable), remembered in
  `user://settings.cfg`.
- `tools/steam_export.sh` and `steam/*.vdf`: release exports for both
  platforms and the filled-in steamcmd scripts (uploading stays manual).
- `docs/STEAM.md`: the Steamworks steps, Auto-Cloud paths, Steam Deck
  notes, store-page text, art sizes and the open decisions.
- Tests: `test_release.gd` (4).

#### Changed
- The interface scales with the window from its 1600 × 900 layout
  (`canvas_items` stretch, `expand`); rendered at 1280 × 800 and
  2560 × 1440, HUD markers stay on their targets.

#### Tests changed (and why)
- `test_input_bindings`: fullscreen joins the keyboard-only actions.

### Play-test batch 5 — smarter craft, IFF, ramming, armed-only flares (2026-10-20)

#### Added
- **Craft never shoot their own side**: a craft holds fire while a friend
  (its carrier, another craft of its side) is within 25 m of the line of
  fire, and its rounds carry an IFF interlock that passes through friendly
  ships and craft.
- **Pathing**: craft keep 70 m from each other and 120 m clear of hulls,
  and Strike flies gun runs — run in, fire, break off at 600 m, come round
  — instead of hovering at standoff.
- **New craft**: the **Hornet interceptor** (6 t, fast light gun, on an
  interceptor rack) hunts missiles aimed at its carrier within 4 km before
  anything else; the **Mantis bomber** (18 t, 45 mm cannon, in a bomber bay)
  opens fire from long range and keeps its distance. The recon drone never
  fires; the EW drone holds station 1.2 km out towards the threat. Enemies
  field interceptors from mission 5 and bombers from mission 7.
- **In-game explanations**: the WING tab shows what each craft's role does
  and a HOW THEY FLY block (every directive, risk tolerance, the IFF and
  clearance rules); the WEAPONS tab and the help card explain flares and
  jamming; the target card shows **JAMMED −n % · burn-through < 3 km**; the
  shipyard part info explains each craft rack.
- Tests: `test_combat_ai.gd` (8), with mutation checks on the IFF skip,
  the clear-shot interlock and the armed-only filter (each caught).

#### Changed
- **Ramming hurts more, and the lighter side most**: 3× the damage per
  joule; the energy is split by (mass × local armour)^1.5, not linearly;
  the blow spreads over modules within three cells (40 %) and external
  systems within two cells. An 8 m/s Cutter-into-Destroyer ram: Cutter
  −35.5 % structure over 2 modules, Destroyer −0.9 %.
- **Auto flares wait until an inbound missile is armed** (a missile just
  off the rail no longer triggers them), and every policy preset, Hold
  included, now fires countermeasures on its own.

#### Tests changed (and why)
- `test_air_wing` strike: the closest approach is now the gun run's
  run-in distance (±150 m) instead of the standoff, the run lasts up to
  300 s, and the craft may break off for propellant as well as ammunition
  (gun runs burn more propellant than hovering).
- `test_m11_countermeasures` presets: every preset has auto
  countermeasures on (Hold had them off).

### Milestone 12 — the station: sections, dealer, missions, capital ships (2026-10-20)

#### Added
- The shipyard is a station with eleven sections; it opens on **STATION**
  (your ship in 3D, repair / rearm / crew / next-sortie cards) and the
  builder is **REFIT**, one section among them (its keys and top-bar tools
  work only there).
- **MISSIONS**: five NPCs (navy liaison, guild factor, bounty broker,
  salvage boss, station security) offer four seeded contracts (bounty,
  capture, escort, defend, salvage); accepting sets the next sortie's
  location, ship count and threat, and pays on its goal; one at a time,
  abandonable, new offers after every sortie.
- **DEALER**: every template for credits with a 3D preview, standard crew
  included; **HANGAR** fleet cards and **scrap** (half the parts back, not
  the last ship); **ARMOURY** rearm-and-refuel now.
- **Capital ships**: Destroyer (960 t), Cruiser (2,169 t) and Carrier
  (1,954 t, four hangars) from standard parts, generated by
  `tools/make_capital_templates.gd`.
- Tests: `test_m12_shipyard.gd` (7); `smoke_shipyard` drives the station
  page, dealer, scrap, missions and armoury.

#### Changed
- Profile schema 8: the mission board and the accepted contract; v7 saves
  get a fresh board and keep `.v7`.

#### Fixed
- Crew rosters scanned every room for every berth: a 300-module hull took
  ~90 ms to spawn, now 10.6 ms (rooms indexed by role).

#### Tests changed (and why)
- `test_locations`: the saved schema is read from `SCHEMA_VERSION` (8).
- `smoke_shipyard`: switches to REFIT before using the builder (the yard
  opens on STATION).

### Milestone 11 — countermeasures and electronic warfare (2026-10-20)

#### Added
- **Flare launcher** (common): 30 flares, three a launch (Space, or the
  policy's auto-countermeasures when a missile is 4 s out), each burning
  6 s and fanning out from the launcher's face; restocked at 1 cr a flare.
- **Seekers**: a missile weighs each enemy flare in its cone once (seeded,
  repeatable): chance = flare signature / (flare + ship signature ×
  seeker discrimination). Ships are brighter when bigger and much brighter
  at full burn. A seduced missile bursts on the flare; flares fired too
  early burn out and the missile finds the ship again. Seekers: saturation
  0.6 (easily fooled), anti-ship and EMP 1.0, nuclear 2.0.
- **EW jammer** (rare, 150 kW): beyond burn-through (3 km, full by 6 km)
  enemy tracks lose up to 75 % confidence and their locks; missiles may
  lose lock (10 %/s at full effect, less for jam-resistant seekers) and
  self-destruct. Hardened masts filter the noise by their hardening.
- **EW drone** (rare, its own rack): jams for ships of its side within 3 km.
- Enemies: flares from mission 3, a jammer on some ships from mission 6,
  auto-flares 3.5 s out.
- HUD: `CM 27 [SPC] · EW ■` on the weapon strip; the missile alert's key
  chip is `[SPC]` when flares are aboard; Tab › WEAPONS lists flares and
  the jammer. `DecoyView` draws flares (white-hot, flickering, cooling).
- Tests: `test_m11_countermeasures.gd` (10).

#### Tests changed (and why)
- `smoke_shipyard`: the Weapons category now lists 10 parts (flare launcher
  and jammer added).

### Pass A — alerts and audio (2026-10-20)

#### Added
- `AlertQueue`: every HUD alert in a fixed grammar (a shape, a short noun,
  one value, the bearing for threats, the key that acts on it; ≤ 26
  characters), at most three shown, deduplicated, priority by level then
  class, held 0.8 s after their condition clears, raised at once and
  lowered after a steady second, non-danger ones acknowledgeable with
  **.** (new action `ack_alert`; `countermeasures` on Space is reserved
  for Milestone 11).
- Non-text cues: an alarm per alert class (threat, damage, systems,
  navigation, information; 1–3 blips by level), threat chevrons on the
  incoming missile or round or at the screen edge towards it, the damage
  map flashing the system the top alert is about, and a persistent STATUS
  line (reactor, breaches, fires, vented rooms).
- Recorded CC0 sound (Kenney's Sci-Fi, Impact and Interface packs; 21
  files, 641 kB, `data/ATTRIBUTION.md`): guns, hits, ricochets, missile
  launches, warheads, reactor blasts, docking, the engine and RCS loops,
  the machinery hum and the alarms; synthesis stays as each slot's
  fallback. Effects, Alarms and Ambience buses; an alarm ducks the others
  by 9 dB.
- Tests: `test_pass_a.gd` (6).

#### Changed
- The banner shows up to three alert chips instead of one sentence; the
  attention line repeats a danger's short line; the own-ship card's alert
  list became the STATUS line; a missile alert shows range until the
  missile is closing in earnest, then time.

#### Fixed
- Audio streams leaked at exit in headless runs: nothing is played
  headless, and every stream is stopped and released on exit.

#### Tests changed (and why)
- `test_sensors_and_hits`: the synthesised-sound test now builds
  `ShipAudio` with `use_samples = false` (synthesis is the fallback).
- `test_input_bindings`: `countermeasures` and `ack_alert` are keys only
  (every pad button is taken), like missiles.
- `smoke_main`: "HIT TAKEN" and the reactor id are read from the alert
  queue (alerts are no longer sentences in the card).
- `smoke_boarding`: the boarders alert reads `BOARD …`.

### Play-test batch 4 — fixes (2026-10-20)

#### Fixed
- **M emptied every magazine:** each press now fires a volley, one launch
  from each pod the missile mode allows (a saturation pod's launch is its
  swarm of eight); sequence mode walks the warhead order press by press.
  `MissileSalvo.volley`; counted salvos (AI, auto-salvo) are unchanged.
- **Invisible enemy rounds:** tracers were capped at 512 in array order, so
  with a dozen point-defence mounts our own rounds filled the cap and an
  enemy railgun round could hit undrawn. Now up to 4,096, incoming rounds
  first (`ProjectileView.draw_order`).
- **Auto-fire and auto-salvo fired at wrecks:** automation now needs a
  fighting target (not a derelict, not disabled: `Main.is_fightable`); the
  player's own trigger still always fires.
- **Slope armour:** a 1×2 wedge's plates sat at each cell's centre, a
  quarter cell above or below the slope (gaps, floating, looking short);
  they now lie on the slope over their own cell and butt with a slim seam.
  Thick plates on 1×1 wedges crossed the plate on the face behind them at
  the ridge; slope plates are trimmed by depth · tan(θ/2) where they meet a
  flat face.

#### Changed
- Missile restock about a quarter of the price: anti-ship 2 cr, EMP 5,
  nuclear 30, saturation 1 (refills 24 / 30 / 90 / 48 cr).
- The nuclear burst: a 160 m white flash and a light reaching 4 km, a
  14-lobe fireball swelling over 3.2 s, three shockwave rings and a shock
  shell out to ~1.6 km, a violet ionisation afterglow; 8 s in all (was the
  reactor explosion at 60 m, 4.5 s); a harder camera shake to 8 km.
- Tests: `test_playtest4.gd` (7).

#### Tests changed (and why)
- `smoke_main`: M fires one missile from the rack, a second press the next
  (was: the salvo empties the rack); "M starts a salvo" accepts a volley
  already finished in the same frame.

## [0.11.0] — 2026-10-20 — Milestones 7–10: EMP, polish, salvos and wrecks, multi-contact encounters; the Moon and Earth in each other's sky

### Moonlight, earthlight and earthshine (2026-10-20)

#### Added
- Reflected light by phase: `CelestialFrame.reflected_fraction` = geometric
  albedo × (radius/distance)² × phase law (`OrbitalBody.geometric_albedo`,
  `phase_law`: the Moon's measured curve with its opposition surge,
  Lambert for Earth). A full Moon gives 2.45e-6 of sunlight (0.31 lux), a
  half Moon ~1/9 of that, full Earth from the Moon ~49 × a full Moon.
- Moonlight lights Earth's night side and ships (a second directional light,
  `Main.sky_light`, only while the Moon is above the horizon; not drawn in
  the sky); at the Moon, earthlight does the same; earthshine lights the far
  body's dark side.
- Shown brightness: night adaptation stands in for the eye's ~20 stops
  (`PlanetSky.perceived_light`: a full Moon at 5 % of the Sun's light,
  Stevens' law exponent 0.5), tinted for night vision (Purkinje).
- README: "The sky is real": what is modelled, what is adjusted on purpose,
  and the checks against published values; five sky screenshots
  (`tools/capture_sky.gd`).
- Tests: `test_locations` +1 (photometry and display mapping, horizon);
  `smoke_shipyard` checks the earthlight on the ship.

#### Changed
- The night side's constant glow is lower (0.006 → 0.002 of albedo):
  moonlight and earthlight now light it.

### The Moon in Earth's sky, Earth in the Moon's (2026-10-20)

#### Added
- Each location draws the other body in its sky (`Location.sky_body`):
  the Moon from Earth orbit (0.5° across), Earth from lunar orbit (1.8°),
  at their real positions for the scenario date, lit by the Sun so they
  show their phase, with their own surface maps and rotation; they pass
  behind the near body, hide the stars behind them and block the Sun.
- `CelestialFrame.moon_geocentric_icrs` (Astronomical Almanac
  low-precision series), `position_of`, `body_fixed_of`;
  `OrbitalBody.ephemeris`.
- Earth seen from afar: clouds swirl (domain warp), follow latitude bands
  (ITCZ, storm belts, clear subtropics) and keep ~30 % cover; from low
  orbit they are unchanged.
- Tests: `test_locations` +2 (the Moon against Meeus's example 47.a and the
  2024-04-08 eclipse / 2024-04-23 full moon; Earth from the Moon opposite
  the Moon from Earth; longitude mutation-checked); `smoke_shipyard` checks
  Earth hangs in the lunar sky.

#### Changed
- `planet_sky.gdshader`: `surface()` takes the body (map, rotation, radius,
  air) so the central and far body share it.

### Play-test batch 3 — map, lunar orbit, big-fight performance (2026-10-20)

#### Added
- **Map** (shipyard HANGAR › MAP; the route button beside LAUNCH opens it):
  click a body to dock at its station and launch from its orbit; pick the
  next encounter's size, **1, 2 or 3 ships** (was set by the mission
  number: two from mission 4, three from 7). Moving between stations is
  free until jump fuel arrives (Milestone 13).
- **Lunar orbit and the Lunar Shipyard**: a 100 km circular orbit
  (1.63 km/s, 118 min) about the Moon at real scale (JPL DE440 μ, mean
  radius 1,737.4 km). No air: no limb glow, haze, clouds or glint; the
  "entry interface" is the terrain floor, 11 km up (the highest summit is
  10.8 km), shown as TERRAIN and called a terrain impact. NASA SVS CGI Moon
  Kit colour map (public domain, `data/ATTRIBUTION.md`).
- `Location` resource (`data/locations/`: station, body, start orbit, map
  position) and `OrbitalBody` rotation data (IAU pole and prime meridian,
  the Moon with its largest periodic term), atmosphere flag and surface map.
- `SystemMap` control; `tools/profile_frames.gd` (rendered frame-time
  profile of a frigate against three ships with wings and salvos).
- Tests: `test_locations.gd` (5), `test_render_batching.gd` (4);
  `smoke_shipyard` drives the map (click the Moon, pick 2 ships), launches
  into lunar orbit against two ships and jumps back to the Lunar Shipyard.

#### Changed
- Profile schema 7: `location`, `known_locations` (Earth and the Moon to
  start) and `encounter_size`; older saves are docked at Earth with one
  ship, and the v6 file is kept as `.v6`.
- `CelestialFrame` works for any body (`for_scenario(…, body)`;
  `pci_to_ecef` is now `pci_to_body_fixed`); Earth's numbers are unchanged
  (tested against the previous values). The sky shader's `earth_map` is
  `surface_map`, with a `has_air` switch.
- Station names come from the location (HUD jump alert, debrief, prize
  crew, salvage notices, shipyard title); fixed strings say "the station".

#### Performance (frigate vs three ships, 50 missiles, 4 craft, ~380 rounds in flight; RTX 3060 Ti, 1600×900, vsync off)
- Before (dev, 20838b8): **23 fps** mean, 95th percentile 157 ms, 170 frames
  over 50 ms in 40 s. After: **75 fps** mean, 95th percentile 20 ms, one
  frame over 50 ms (`tools/profile_frames.gd`).
- Rounds use a uniform-grid broadphase instead of testing every ship;
  `ShipSystems.disabled_reason()` is cached until the ship's state changes;
  docking hull ports are cached and `Docking.best()` assesses only the best
  pair; only one enemy at a time comes alongside to board.
- HUD orbit path and orbit panel refresh 5 × a second (were ~2 ms a frame).
- Each ship's hull modules and armour plates draw as one merged mesh
  (rebuilt from cached triangles when a plate wears or a module wrecks);
  external systems' fixed pieces are merged; missiles share one mesh per
  side and cast no shadows. Draw calls ~1,600 → ~760.
- During flight, `GameLog` prints a frame's lines in one call (a debug
  build flushes stdout on every print; through a pipe that cost ~15 ms a
  line here).

#### Tests changed (and why)
- `test_m10_contacts`: the encounter size is now the player's pick, not the
  mission's (`encounter_size(0/2/9)` → 1/2/3); the schema assertion reads
  `SCHEMA_VERSION` instead of 6.
- `smoke_encounter`: picks three ships (`encounter_size = 3`) instead of
  relying on mission 7.
- `test_celestial`: `pci_to_ecef` renamed `pci_to_body_fixed`; same checks.

### Milestone 10 — multi-contact encounters, ship policies, smarter AI (2026-10-20)

#### Added
- Contact registry (`Encounter`, `Contact`): up to three hostile ships plus
  their craft per encounter (two from mission 4, three from 7), each with
  its own sensor track (ours of it and its of us), hostility, air wing,
  policy, salvo and wreck state. U cycles the ships, then hostile craft;
  the target card shows the selected contact and lists the others; radar,
  world markers and Tab › TARGET show all.
- `ShipPolicy` resource and presets (`data/policies/`: Hold, Defensive,
  Standard, Aggressive): fire discipline, auto point defence (order, range,
  ammunition reserve), auto-salvo (lock quality, range band, warheads,
  count, interval), auto-fire (lock + aim within tolerance). Tab › POLICY;
  saved per vessel. Manual input always overrides.
- Enemy AI is a policy: roles (closer, standoff, flanker) with their own
  fighting ranges and flank bias, focus fire (an escorted courier first),
  never a derelict, missile salvos of 2–4 by policy.
- Point defence engages in policy order and can flak big, slow slugs.
  Ships have a side: point defence never engages its own side.
- `tools/bench_sim.gd` three-hostile encounter; `tools/bench_hull.gd`
  capital-hull spike; `tests/run_tests.gd -- --only=<name>`.
- Tests: `test_m10_contacts.gd` (15), `smoke_encounter.gd` (16 checks, in
  `run_checks.sh`).

#### Changed
- Profile schema 6: each vessel's policy; older vessels get Defensive
  (what they already did), the v5 file is kept as `.v5`.
- `MissileSalvo` takes a count limit and counts missiles (a swarm launch
  counts 8), not launches.
- Simulation tick budget in `bench_sim.gd`: 8 ms (was 16).

#### Tests changed (and why)
- `smoke_main`: T is pressed only if the target isn't hostile yet — our hit
  turns it hostile ("fired upon") and T then toggled it back to passive;
  the old check passed only because the enemy had already hit us. Before T
  the target's gun and conduit are restored: our hits can knock out its
  only gun or cut its power (frame timing decides where they land), and a
  gunless target can't shoot back.

### README screenshots (2026-10-20)

#### Added
- Gameplay screenshots in the README (flight, gunnery, missile salvo,
  damage control, crew, debrief, shipyard) and `tools/capture_readme.gd`,
  which renders them on a scratch profile.

#### Fixed
- Debrief accuracy counted missile strikes as gun hits (e.g. "48 hits from
  7 rounds, 686 %"); missile strikes are now counted on their own
  ("18 missiles launched, 41 struck") and accuracy is rounds only.

### Milestone 9 — play-test batch 2: salvos, wrecks, crew (2026-10-20)

#### Added
- Missile salvos: M fires every missile the mode allows (all,
  conventional, EMP, nuclear, or a sequence in a chosen order); `,` cycles
  the mode; Tab › WEAPONS shows launchers, mode and order. Saved.
- Saturation missile pod (rare): 48 small missiles, 8 per launch.
- Missiles shot down or self-destructing break up in a fireball with sound;
  small warheads show as fireballs.
- Crew: Tab › CREW reorganised — crew map with post-coloured dots, roster
  tree by post (who, where, status), one "send to" control; boarders shown
  as dots on the target map and in the boarding view; the station's crew
  list grouped by post against the standard complement.
- The target card says how many boarders would go before N.

#### Changed
- Launchers hold more (rack 12, EMP 6, nuclear 3) and cycle a launch every
  0.4 s; restocking is cheap (8 / 20 / 150 cr, saturation 2).
- Beaten contacts stay as silent derelict wrecks (guns, point defence and
  craft stop) that drift clear, instead of vanishing.
- Boarding party limit 24 (enemy parties stay at 8).
- Our own missiles are small unlabelled HUD markers; our launches no longer
  flood the ticker.

### Milestone 8 — vertical-slice polish (2026-10-20)

#### Added
- Mission chain with stated goals and rewards: disable, capture, escort a
  courier, survive two waves, then patrols. Shown on the HUD (gold, top
  centre), in the hangar and in the debrief.
- Opt-in guided first sortie (F2): fly, aim, fire, disable, salvage, jump,
  repair — prompts advance on what the player does; skippable; saved.
- Debrief opens with a sortie summary (goal, dealt, taken and from where,
  systems lost, crew); hit-cam caption says how the round got in and lists
  what it broke with state glyphs.
- `tools/bench_sim.gd`: simulation frame-time profile under load (two
  frigates, every gun, 12 missiles; ~1 ms a tick with 200+ rounds).

#### Changed
- Save hardening: profile schema 5 (tutorial and mission progress); a save
  is read back before it replaces the profile, the previous save is kept as
  `.bak`, a damaged profile is replaced by its backup with a clear message,
  an interrupted save is finished on the next start, and an older schema is
  copied aside before migrating.
- Design tokens follow the design system: void #050508, surface #0A0E14,
  teal #00D4C8, gold #F5C842 (magenta and red stay as hostile/danger states).

### Milestone 7 — EMP and advanced weapons (2026-10-20)

#### Added
- Guided missiles: launchers (missile rack, EMP launcher, nuclear launcher;
  uncommon / rare / legendary), fired with **M** at the U target. Missiles
  are small ships in the simulation: proportional-navigation guidance,
  arming, a swept proximity fuse, self-destruct; rounds and point defence
  shoot them down.
- Warheads: anti-ship (penetrator plus blast), EMP (resets unhardened
  electronics, which recover on their own), nuclear (radiation dose behind
  the facing armour, heat, ablation close in, EMP; no momentum).
- EMP hardening: hardened sensor mast and power distribution unit; reactors
  half-hardened.
- HUD: `MSL` weapon-strip entry, MISSILE INBOUND danger alert, EMP RESET
  caution, MSL markers; missile views with exhaust, blue EMP ring, white
  nuclear flash; launch and detonation sounds.
- Enemies carry a missile rack from mission 4 (EMP launcher sometimes from
  mission 6) and fire it with a lock inside 12 km.
- Spent missiles persist in the vessel's condition and are restocked at the
  yard for credits (shown in the hangar's resupply line).

#### Changed
- Enemy gun upgrade: the heavy kinetic cannon (the template already carries
  autocannons).

### Play-test bug fixes (2026-10-20)

#### Fixed
- Tab drawer (and the controls, loot and debrief panels): a click no longer
  re-captures the mouse while a panel is open.
- Armour plates covered by a newly built deck or module are removed with
  that edit (same undo step), and dropped from designs and saves on load.
- Deleting a room deletes its hatches (one undo restores both).
- Engine sound: fuller, louder rumble that rises with the throttle and
  follows every main engine (reverse and side ones too); new RCS hiss.

#### Added
- Shipyard armour palette: **Clear all armour** (undoable).

### Play-test feedback pass (2026-10-20)

#### Added
- Controls: W/S pitch, A/D yaw, Q/E roll, R/F main engine / reverse, IJKL
  strafe; X cycles hold orbit → match target → target markers (yellow
  markers without matching velocity); wheel zoom levels while zoomed;
  closest-approach (CPA) line on the target card; U cycles the lead target
  through enemy craft; craft markers in sensor range.
- Grappling arm (Y): steadies a tumbling ship, matches velocity, lines up
  collars for a gangway, siphons a hulk's propellant and rounds.
- Emergency jump: leaves craft and boarders behind, with a red countdown.
- Crew: spacesuits at general quarters, damage control seals breaches,
  named crew, hiring, shipyard role changes and in-flight reassignment.
- Quartermaster (rarer parts for credits) and upgrades (ship technology,
  captain's training).
- Fires and automatic foam suppression; optional auto-routed coolant loops.
- Main engines on any face with an engine room inside; high-thrust engine.
- Cutter Mk I and Corvette Mk I templates (common parts only).
- Shipyard: zoom/pan, click-and-drag moves, CoM marker [C], top/underside
  toggle [V], rotate/flip buttons; same-type rooms side by side join up.
- Visuals: 3-cell accordion radiators, triangular wedge-side plates, open
  truss lattice, charred/buckled worn plates, rotating radar array, windows
  and running lights that go dark without power, room colours in the
  schematic and hit cam, centre-screen red alerts, smaller dimmer far tracers.

#### Changed
- Guns: light autocannon common (45 mm, 120 rpm), heavy kinetic uncommon
  (90 mm, 60 rpm), railgun 220 mm at 24 rpm — similar damage rates; no
  penetration fall-off; magazines hold mass, not rounds.
- Armoured propellant tank 40 mm; crew quarters 3 berths a cell; medic
  25 s a patient; bigger bridges, workshops and life support work faster.
- Craft carry 1.5× fuel and ammo; crate loot odds 60 % / 90 %.
- Engines balanced on thrust × Isp; owned rare parts usable on any vessel.
- Profile schema 4: saves using the once-common heavy cannon keep their
  units. Boot checks use a throwaway profile, never the real save.

#### Fixed
- Rate of fire compounding on every recompute (no bullets / sudden bursts).

### Added (play-test fixes, 2026-10-20)
- Enemies board a disabled player (from mission 2); crew defence policy
  (hold the bridge / counter-attack); V cuts their gangway.
- Point-defence turrets (two on the Frigate Mk I) engage hostile craft.
- Shipboard sound, synthesised at startup.
- Shipyard: move groups of modules (Shift-click, Ctrl+A); convert old
  sections to blocks.
- Medics treat the wounded in flight; craft fly in formation.

### Fixed (play-test fixes, 2026-10-20)
- The drawer keeps the target card in view; collisions respect wedges;
  a magazine and lead marker per gun type; wrecked modules break up.
- The enemy uses its power pips and works round to your stern.
- Propellant and rounds carry over between sorties and are bought back at
  launch (credits); craft refuel and rearm from their carrier's stores.
- The enemy keeps a fighting range, jinks, holds fire when hot and flees
  when beaten (escapes beyond 40 km).
- Mixed gun batteries: each mount keeps its own gun and, with a lock, its
  own lead.

## [0.10.0] — 2026-10-20 — Operations pass: turrets, blocks and armour, power bus, jump drive

### Added
- Turrets: every gun trains on the mouse aim at its own traverse rate and
  fires once on target; per-gun reticles; guns hold fire when their own hull
  is in the way. Mouse aim cursor; right-drag camera orbit; Shift zoom toggle
  centred on the aim.
- Scans (lock + sensor mast, 4 s): approximate cargo, scrap value, bounty.
- Ship-to-ship collisions with ramming damage.
- Dimensional jump drive (hold B 5 s, out of combat) to Earth Shipyard.
- Salvage beacon (50 % scrap) vs boarding takeover (80 % scrap, better
  crates into the hold, automatic withdrawal); cargo capacity and venting;
  loot carousel; loot tables in the shipyard; DEV +100 cr.
- Hull building blocks (2×2×1 pressurised, 1×2×1 / 1×1×1 wedges, 1×2×1
  truss); angled armour; painted 40 / 80 mm plates.
- Player-routed power bus with distribution units; auto-route.
- 2-cell radiators; internal fighter bay and hangar; models for the sensor
  mast, docked drones, hangar doors, fighter and drone.
- Isometric shipyard view (edits too); build new ships into a hangar fleet.
- Reactor explosion effect and camera shake.

### Changed
- A/D yaw (strafe while the docking camera is up); R/F only for up/down.
- Kinetic cannon 50 rpm, 48 mm; ship AI keeps the guns at half rate.
- Gangway attached: primary weapons locked. Contacts turn hostile when hit.
- Modules attach on any common face; underside equipment placement fixed.
- Passive hull cooling per exposed face; reactor blast scaled per module.
- Profile schema 3 (hangar of vessels); blueprint schema 2 (flips, plates,
  bus).

## [0.9.0] — 2026-10-19 — UI simplification and polish

### Added
- Design tokens (`CyberTheme`) and a code-built Theme; state glyphs.
- Consolidated HUD: own-ship card with actionable alerts, target card with
  sensor-track quality (MEAS / EST / STALE), confidence and lock, weapon
  strip, event ticker; orbit (O), details & combat log (J), help (H).
- Damage-control drawer with clickable schematic and contextual actions
  (dispatch repair, switch loads off to reroute power, divert, isolate).
- Shipyard: searchable categorised palette, key figures, expandable views,
  tabbed hangar (Service / Cargo & Bank / History), primary Launch.
- Sensor mast and tracks; contacts arrive far out and must be detected
  before they engage.
- Ricochets with visible deflected tracers; black hull entry/exit holes.
- Shift zoom for gunnery; yellow target-relative markers in match mode.

### Changed
- RCS Isp 900 s (heavy 950 s): manoeuvring no longer burns more propellant
  per m/s than the main engines.

## [0.8.0] — 2026-10-19 — Milestone 6: fighters, drones and directives

### Added
- Wasp fighter and recon drone on external racks (Frigate Mk I carries
  both); craft fly in the same physics, have hull hit points and can be
  shot down.
- Directives (intercept, strike with subsystem priority, recon, escort,
  return), risk tolerance and automatic disengagement, comms fallback.
- Launch / recovery / servicing; craft losses and damage persist and are
  replaced or repaired at the station. L / K; air-wing controls in Tab.
- Recon drones give the close look at the target's systems.
- Enemy fighters from mission 3.
- `test_air_wing.gd` (11), `smoke_wing.gd`.

## [0.7.0] — 2026-10-19 — Ship control, station economy, cyberpunk UI

### Added
- Power distribution (1/2/3/4), crew orders (cover lost roles), damage
  control pick, boarding party size; tactical overview (Tab).
- Ship AI flies a ship whose bridge crew is lost (half thrust and turn
  rate). Reactors explode at 0 %.
- Station: cargo hold (salvage at risk until banked), credits (bounties,
  spare parts shop), respawn fee; death loses only the cargo and rebuilds
  the same design. Combat log and debrief with lessons for the shipyard.
- Always-visible damage map, boarding overlay in the hit cam, docking cam.
- Procedural hull plating, ship names on the hull, hazard-striped collars
  with beacons, white RCS jets, reactor fireballs.
- Enemies vary and get tougher by mission; salvage strips the wreck's best
  intact rare part.

### Changed
- Medium kinetic cannon: 1000 m/s, 120 rpm (was 1500 m/s, 240 rpm).
- Cyan/magenta UI throughout. The shipyard is the station.
- Destroyed rare parts are rebuilt instead of written off.

## [0.6.0] — 2026-10-19 — Milestone 5: crew and boarding; real-season Earth

### Added
- Abstract crew: roles and stations per berth, routes through the access
  graph (5 s per room, suits for vacuum), casualties when rooms vent,
  command and gun-crew effects, crewed field repairs with travel time,
  casualties saved with the vessel, recruits at the yard.
- Docking collar (Frigate Mk I has one); docking tolerances; gangways that
  mate to collars or cut into the hull; grapples that hold, and tear when a
  target thrusts away; the target AI tries to break contact.
- Boarding: muster, cross, fight room by room (Lanchester attrition, locked
  doors to cut, defenders falling back to the bridge), capture, withdraw,
  stranding; capture bonus on salvage. V / N, HUD lines, gangway tube.
- `test_boarding.gd` (12), `smoke_boarding.gd`.

### Changed
- Earth texture: NASA Blue Marble NG October composite, 5400 × 2700.
- Docking heals the wounded; the stored condition can include crew losses.

## [0.5.0] — 2026-10-19 — Persistent rounds, hit cam, Milestone 4 + loot

### Added
- Rounds never expire: far from the fight they coast on exact two-body
  orbits (`OrbitElements.propagate`) and come back; HUD counts rounds near /
  in far orbit and warns of incoming rounds; a ship can be hit by its own
  returning rounds.
- Recoil and impact physics: firing pushes and spins the firing ship; hits
  push and spin the target; overpenetrating rounds fly on, slower.
- Hit cam: X-ray replay of your latest most-severe hit and the modules it
  damaged.
- Milestone 4 — persistence and recovery: player profile and hangar vessel
  saved as versioned JSON; damage persists between sorties; salvage of
  disabled enemies (G); spare parts; shipyard HANGAR & SERVICE panel with
  priority repairs; paid refits at launch; write-offs for rarer parts lost in
  flight or with the ship; workshop field repairs (C).
- Loot with cascading weighted rarity (Common → Legendary, 30/30/25/20 %
  climb), cascade-down past empty tiers, hard pity (Rare+ / 10, Legendary /
  80), published rates; 14 rarer parts: equipment (railgun, light autocannon,
  torch drive, high-Isp engine, heavy RCS, compact and Mk II reactors,
  heat-pipe radiator, armoured tank), hull blueprints (armoured fuselage and
  nose, monocoque fuselage) and room blueprints (workshop, dense magazine).
- Validator: `blueprint_locked`, `part_not_owned`, `mixed_cannon_types`.
- `smoke_campaign.gd` (M4 exit test); `test_rounds.gd`, `test_progression.gd`.

### Changed
- B docks the ship (its damage is kept); Backspace and quitting dock first.
- Rarity colours in the shipyard palette; owned counts and locked blueprints.

## [0.4.0] — 2026-10-19 — Real sky, known-issue fixes, Milestone 3

### Added
- Real sky for the scenario date: the 9,096 stars of the Yale Bright Star
  Catalogue (J2000), the Sun's true direction, Earth's pole and sidereal
  rotation (`CelestialFrame`, tested against Meeus); NASA Blue Marble
  geography; eclipse darkens ships in Earth's shadow; HUD sunset/sunrise.
- Milestone 3 — damage and ship systems: hull-cell hit detection, armour
  penetration with obliquity, damage along the round's path, room breaches
  and hatch sealing, crew access cut-offs, power networks through module
  junctions with load shedding, ship heat with reactor throttle/scram and
  over-temperature damage, damage-reduced flight config, readable damage
  reports, destroyed parts shown on the model.
- Enemy gunner (T): aims at the lead point with line-of-sight feed-forward.
- Propellant and Δv: tanks, engine/RCS Isp, falling mass, empty = no thrust.
- Shipyard undo/redo; modules carry their contents and turn in place.
- Gamepad defaults; in-game rebinding (F1), saved per user.
- Windows export preset; checks export a .pck and boot from it.

### Changed
- Sandbox orbit is prograde equatorial (it was retrograde relative to Earth's
  spin once the sky was made real).
- Off-axis engine thrust now torques the ship; rotation includes the
  gyroscopic term (RK4); every cannon mount fires.
- Two dust layers so the field no longer visibly repeats.

### Fixed
- Enemy aim lagged crossing targets by rate/gain (~0.6°) and stopped firing;
  feed-forward removes the lag.

## [0.3.0] — 2026-10-19 — Milestone 2: ship blueprint and builder

### Added
- Construction model (`scripts/construction/`): hull module, room and
  equipment definitions (`data/catalog/`), `ShipBlueprint` (versioned JSON),
  `ShipGrid`, `ShipValidator` (errors block launch; warnings are trade-offs),
  `ShipStats` (mass, CoM, inertia, thrust/torque from placed thrusters,
  power/heat, crew/rounds/cargo) compiled into the flight `ShipConfig`.
- Frigate Mk I template (`data/blueprints/frigate_mk1.json`): 392 t, six
  modules, eleven rooms, full crew access, validates with no issues.
- Shipyard (`scenes/shipyard/`, `scripts/shipyard/`): palette, deck grid
  editor (place / select / move / rotate / remove / hatches), placement
  ghost that names the error before you click, side and front views, 3D
  preview, live stats, clickable validation panel, save/load, templates,
  launch (blocked while errors exist).
- Flight: ships are built from their blueprints (geometry and numbers);
  `B` opens the shipyard with the flown design.
- Tests: `test_blueprint.gd` (22), `test_ship_editor.gd` (5),
  `smoke_shipyard.gd` (15 checks); 120 s watchdog on both smoke tests.

### Changed
- The player and target fly the compiled Frigate Mk I instead of the fixed
  placeholder config (which remains as a test fixture).

## [0.2.0] — 2026-10-19 — Milestone 1b: Earth orbit, cannon, fire control

### Added
- Real-scale Earth (`data/bodies/earth.tres`): two-body gravity, 100 km
  Kármán-line entry interface. Sandbox starts in a 400 km circular orbit.
- `LocalFrame`: free-falling, double-precision engagement frame with tidal
  acceleration and automatic rebasing on the player (`Vec3d` for PCI maths).
- `OrbitElements`: apsides, period, time to apsis, time to entry interface,
  projected path points.
- Atmospheric entry: ships and rounds crossing 100 km leave the engagement;
  the HUD predicts it ("ENTRY IN m:ss") and shows a loss screen. Backspace
  restarts.
- Kinetic cannon (`data/weapons/medium_kinetic_cannon.tres`): inherited
  velocity, recoil, rate of fire, magazine, round lifetime; rounds feel
  gravity. Swept hit tests (no tunnelling), hit events and flashes.
- Fire control: intercept time and lead pip; round TOF in the target panel.
- Flat radar (bearing, range, elevation stalk, closing/opening, motion tail).
- Orbit panel (altitude, orbital speed, Ap/Pe with times, period, entry
  status), projected orbit path with Ap/Pe/entry markers, entry warning banner.
- Planet, limb glow, sun and stars rendered as a ray-traced sky shader.
- Input actions: `fire` (LMB, Enter), `toggle_velocity_hold` (X),
  `restart_scenario` (Backspace).
- Tests: `test_orbit.gd`, `test_weapons.gd`, `test_radar.gd` (46 unit tests
  total); smoke test extended to 14 checks.

### Changed
- Godot 4.7.2 (was 4.5.1).
- Flight assist: holds the current orbit by default (no translation damping,
  no Δv while coasting); X switches to matching target velocity.
- Ship translation integrates with kick-drift-kick leapfrog.
- Prograde/retrograde markers show orbital velocity.
- Dust field stays continuous across frame rebases.

### Removed
- Mesh starfield (replaced by stars in the sky shader, which can be hidden by
  the planet).

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
