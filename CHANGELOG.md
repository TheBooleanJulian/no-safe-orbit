# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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

### Added
- Enemies board a disabled player (from mission 2); crew defence policy
  (hold the bridge / counter-attack); V cuts their gangway.
- Point-defence turrets (two on the Frigate Mk I) engage hostile craft.
- Shipboard sound, synthesised at startup.
- Shipyard: move groups of modules (Shift-click, Ctrl+A); convert old
  sections to blocks.
- Medics treat the wounded in flight; craft fly in formation.

### Fixed
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
