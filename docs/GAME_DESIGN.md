# Project Specification: Orbital Engineering Combat Simulator

## Master implementation brief for Claude Code

**Document purpose:** This is the source-of-truth product and technical
specification for building the game. Treat it as an executable project
brief: inspect the repository, establish the foundation, implement in
small validated milestones, and keep this document updated when a
decision changes.

**Title:** NO SAFE ORBIT — *Keep the Delta-V Positive, or Else.*
A hard-sci-fi spacecraft engineering and combat simulator.\
**Engine:** Godot 4.x (pinned to 4.7.2-stable for development and CI),
using GDScript initially. Keep simulation rules
decoupled from Godot scene/rendering code so performance-critical
modules can later move to C# or a native extension if measurements
justify it.\
**Target:** Single-player-first 3D PC game prototype, designed so
multiplayer can be added later without rewriting core simulation logic.\
**Development style:** AI-assisted solo development. Claude Code should
edit project files directly, run the game and tests, inspect
logs/errors, and fix problems rather than returning code snippets for
manual copy/paste.

------------------------------------------------------------------------

# 1. Product vision

Build a 3D spacecraft combat and engineering simulator where the
player's ship is a persistent physical object whose construction
determines how it flies, fights, fails, can be repaired, and can be
boarded.

**Core promise:** *Your ship's construction determines how it flies, how
it fights, how it fails, and whether it survives.*

The game combines: - Direct 6DoF spacecraft piloting. - Orbital
mechanics and finite-flight-time sublight projectiles. - Modular
shipbuilding with exterior hull sections, interior rooms, corridors and
equipment. - Localised physical damage and cascading system failures. -
Abstract crew roles and access simulation, without individually animated
crew. - Persistent ships, salvage, repairs and redesign. - Physical
docking and boarding through a real connection, never teleporting
boarding parties. - EMP and nuclear weapons. - Autonomous drones and
NPC-controlled ship-launched fighters with player-selectable
directives. - Prebuilt ships for players who want to enter combat
quickly, alongside a deep ship designer.

This is not a conventional arcade space shooter with health bars, nor a
character-based boarding shooter. Simulation can be deep internally, but
the UI must make its consequences legible.

## Design pillars

1.  **Engineering has consequences.** Mass, thrust, armour, layout,
    power, heat, ammunition, sensor coverage, access and redundancy
    affect outcomes.
2.  **Physical consistency.** Ships, fighters, drones, missiles and
    projectiles use consistent movement and damage rules.
3.  **Localised damage.** Hits affect actual external structures,
    armour, compartments, connections and equipment, not just a global
    hull-health number.
4.  **Persistent consequences.** Damage, losses, salvage and repairs
    matter between engagements.
5.  **Player agency at the right level.** The player pilots their ship
    directly, manages critical systems and issues high-level directives
    to autonomous craft and crew.
6.  **Construction is a core feature.** A functional shipbuilder belongs
    in the initial playable prototype. Prebuilt ships remain first-class
    choices.
7.  **Physical boarding.** Boarding requires rendezvous, controlled
    relative motion, compatible interfaces or a breach, and a physically
    connected route.
8.  **Simulation unforgiving; interface forgiving.** Avoid arbitrary
    physics, hidden instant actions and opaque failures. Provide clear
    diagnostics, prediction aids and useful UI.
9.  **Scope discipline.** Build one complete, testable vertical slice
    before expanding the universe or catalogue.

------------------------------------------------------------------------

# 2. Scope and non-goals

## Initial playable vertical slice

Build: - One planetary body and one orbital sandbox. - 6DoF ship
controls with flight-assist mode. - One player frigate and one AI enemy
frigate. - One modular hull with 2--3 internal deck layers. - A 3D ship
inspection view and a deck-based construction editor. - Rooms,
corridors, hatches, equipment mounts and structural attachment points. -
Mass, thrust, power and basic heat calculations. - One kinetic cannon,
one guided missile type and basic point defence. - Finite projectile
travel time and basic orbital gravity. - Armour penetration, component
damage, power failure and compartment pressure/access states. - Abstract
crew roles and crew-to-system access checks. - A
repair/salvage/persistence loop. - One drone and one NPC fighter with
basic selectable directives. - Basic EMP effects after the base
electronics damage model works. - Physical docking/gangway boarding
prototype after the access graph works.

## Explicitly out of scope for the first prototype

Do not start with: - A full galaxy, procedural universe or economy. -
Multiplayer implementation. - Full crew character models, animation or
individual NPC pathfinding. - Fully deformable voxel hulls. - Realistic
fluid dynamics or full computational fluid dynamics. - Detailed human
physiology. - Relativistic flight or projectile physics. - Large fleet
battles. - Full campaign diplomacy/politics. - Every weapon and room in
this document. - Destructible planet surfaces. - Fully simulated
interiors at visual-detail level. - A complex crafting tree.

Design the architecture to avoid blocking these future features, but do
not implement them prematurely.

------------------------------------------------------------------------

# 3. Engine and development workflow

## Engine choice

Use Godot 4.x for the prototype. Use GDScript for fast iteration unless
a measured bottleneck or library requirement justifies C# or a native
extension. Do not build duplicate implementations in multiple engines.

## Claude Code operating instructions

1.  Inspect the existing repository before making changes. Preserve
    useful work and existing conventions.
2.  If the repository is empty, create a clean Godot project with a
    minimal playable scene.
3.  Create and maintain `README.md`, `docs/GAME_DESIGN.md` (this
    specification), `docs/ARCHITECTURE.md`, `docs/ROADMAP.md` and
    `CHANGELOG.md`.
4.  Work in small milestones. At the beginning of each milestone, state
    the acceptance criteria in a short plan, then implement them.
5.  Edit project files directly. Do not merely provide code snippets or
    instructions for the user to paste manually.
6.  After each meaningful change, run automated tests and launch the
    project headlessly or interactively when available. Inspect parse
    errors, runtime errors and logs. Fix failures before proceeding.
7.  Never claim a test passed unless it was actually run. If the
    environment cannot launch Godot, state that limitation and use
    static checks where possible.
8.  Do not overwrite user work, delete unrelated files, or make broad
    refactors without necessity.
9.  Use Git checkpoints after each working milestone. Do not rewrite Git
    history or discard user changes.
10. Prefer small, well-named scripts and typed GDScript. Avoid giant
    manager scripts, unbounded singletons and excessive coupling.
11. Keep tuning values in data resources/configuration where possible
    rather than hard-coding them throughout the codebase.
12. Keep a `KNOWN_ISSUES.md` and update it honestly.
13. If a requirement is ambiguous, make the smallest reversible
    assumption, document it and continue. Ask only when a decision
    blocks safe progress.
14. Prioritise a playable, measurable vertical slice over speculative
    architecture.

------------------------------------------------------------------------

# 4. Technical architecture

Separate the simulation from presentation. The 3D scene is a view of
game state, not the source of truth for it.

Suggested high-level modules (adapt to repository conventions; do not
force an unnecessarily complex folder structure):

``` text
res://
  project.godot
  scenes/
    main/
    ships/
    weapons/
    projectiles/
    shipyard/
    ui/
    effects/
  scripts/
    app/
    simulation/
      world_simulation.gd
      orbital_body.gd
      orbital_dynamics.gd
      ship_state.gd
      ship_dynamics.gd
      projectile_simulation.gd
      damage_simulation.gd
      power_network.gd
      thermal_network.gd
      compartment_graph.gd
      crew_simulation.gd
      boarding_simulation.gd
      autonomous_unit_ai.gd
    construction/
      ship_blueprint.gd
      hull_module_definition.gd
      room_definition.gd
      equipment_definition.gd
      ship_validator.gd
    persistence/
    data/
    ui/
  tests/
  docs/
```

## Core data boundaries

-   `ShipBlueprint`: the reusable design. Contains hull modules, room
    layout, corridors, equipment placements, connections and design
    metadata.
-   `ShipInstance` / `ShipState`: a physical vessel. References a
    blueprint but owns current damage, component condition, ammunition,
    crew, fuel, heat, pressure, cargo, history and location.
-   `SimulationState`: authoritative runtime state at a simulation tick.
-   `ComponentDefinition`: reusable immutable definition for a weapon,
    reactor, engine, sensor, room, armour section, etc.
-   `ComponentInstance`: installed component with condition, damage and
    runtime state.
-   `CompartmentGraph`: room nodes and hatch/corridor/shaft edges,
    including pressure, access, obstruction and control state.
-   `PowerGraph`, `ThermalGraph`, `PropellantGraph` and `DataGraph`:
    separate networks; never assume one network's connectivity implies
    another's.
-   Rendering scenes and meshes are generated from or bound to these
    data models. Do not store essential simulation truth only in a mesh,
    animation or node transform.
-   Use stable IDs for ship, module, room and component identity. Do not
    use scene-tree position as a persistent identifier.

## Simulation clock and precision

-   Use a fixed simulation timestep for critical physics and damage
    updates. Rendering can interpolate between simulation states.
-   Use double-precision numeric calculations where practical for
    orbital state. If Godot's chosen types are insufficient for a
    required precision target, isolate the orbital math in a dedicated
    module before considering native code.
-   Keep simulation time independent of frame rate.
-   Use a floating origin or local coordinate rebasing when distances
    become too large for stable rendering.
-   Avoid running every subsystem at the same frequency. Weapon fire,
    damage, power, AI and visuals can use appropriate rates, provided
    results are deterministic enough for testing.
-   Set a single source of truth for units: metres, seconds, kilograms,
    newtons, joules/watts, kelvin or Celsius consistently documented. Do
    not mix game units silently.
-   Create a testable interface for simulation stepping: `step(delta)`
    or equivalent, with deterministic fixtures where possible.

## Physics vs engine physics

Use Godot physics for collision queries, visual interactions and
suitable local collision behaviour. Do not rely on generic rigid-body
simulation alone for orbital motion or the entire damage model.

The custom ship simulation should own: - Ship translational and
rotational state. - Thrust and torque. - Gravity and orbital
trajectories. - Projectile trajectories. - Damage, penetration and
subsystem failure. - Abstract crew access and boarding. - Power, thermal
and resource networks.

------------------------------------------------------------------------

# 5. Flight and orbital mechanics

## Controls

-   6DoF translation and rotation.
-   Flight assist enabled by default: damp unwanted rotation/translation
    without violating thrust limits.
-   Combat mode: easier target tracking while retaining inertia.
-   Manual mode: direct thrust/torque control.
-   Clearly distinguish ship heading from velocity vector.
-   Support keyboard/mouse initially; make input actions rebindable.

## Orbital model

Start with one spherical central body and Newtonian two-body gravity:

`a_gravity = -mu * r / |r|^3`

Add thrust acceleration to obtain total acceleration. Add atmospheric
drag only if the initial planet has an atmosphere and a simplified drag
model is validated.

Important rule: **there is no universal speed threshold below which
orbit automatically ends.** Orbit depends on position, velocity and
trajectory. Falling below local circular orbital speed does not by
itself guarantee impact; it may create an elliptical orbit.
Deorbit/impact occurs if the trajectory intersects the planet or
atmosphere under the model being used.

-   Circular speed can be used as a reference:
    `v_circular = sqrt(mu / r)`.
-   Display orbital path, periapsis/apoapsis where applicable, relative
    velocity and projected closest approach.
-   Use numerical integration appropriate for the desired stability;
    validate energy/trajectory behaviour with tests.
-   Do not simulate full n-body gravity in the first prototype.

### Decisions (2026-10-19)

-   **Central body: Earth at real scale.** μ = 3.986004418×10¹⁴ m³/s²,
    mean radius 6,371 km (spherical, non-rotating). The sandbox starts in
    a 400 km circular orbit: 7.67 km/s, ~92.4 min period. Consequence:
    within a few-minute engagement, orbital effects show up as slow
    relative drift between ships, not as visibly curving flight paths;
    deliberate orbit changes take tens to hundreds of m/s.
-   **Entry interface: the 100 km Kármán line.** There is no drag model.
    Any trajectory that crosses 100 km altitude counts as atmospheric
    entry: the vessel or round leaves the orbital engagement. Periapsis
    below 100 km is therefore a deorbit, and the HUD predicts the time to
    entry. This is the "model being used" for the impact rule above.
-   **Flight assist under gravity** holds the ship's current orbit by
    default (no translation damping, so no Δv is spent coasting), or
    matches the target's velocity on request. Rotation damping is
    unchanged. Manual mode is unchanged.

## Projectiles and weapons

-   Sublight projectiles inherit the firing ship's instantaneous
    velocity plus muzzle velocity in the firing direction.
-   Projectile flight time is finite. Gravity affects projectiles under
    the same relevant gravitational model.
-   Aiming aids may show line of sight, predicted intercept and
    fire-control solution separately.
-   Intercept predictions are estimates; actual hits depend on
    trajectory and collision geometry.
-   Guided missiles have finite speed, acceleration, turning limits,
    fuel/endurance and sensor/guidance constraints.
-   Beam weapons can use near-instant or light-speed propagation as a
    simplified model, but do not introduce relativity initially.
-   No hitscan for conventional kinetic weapons.

## Presentation aids

HUD should make 3D combat legible with: - World-space target markers. -
Flat radar showing bearing, range, elevation and approach/recede. -
Trajectory/orbital map. - Range, range rate and relative velocity. -
Target heading and velocity direction. - Estimated projectile flight
time and intercept uncertainty. - Sensor confidence and information age.

Sensor damage should degrade information quality, not make basic mouse
controls randomly unresponsive.

------------------------------------------------------------------------

# 6. Shipbuilding system

Shipbuilding is a core feature from the first playable prototype.
Prebuilt ships must also be first-class options, not inferior equipment
for players who do not want to build.

## Three connected construction layers

### A. Hull modules

Examples: nose section, central fuselage, side pods, engine nacelles,
cargo section, structural connector and external mounting section.

Each hull module defines: - External shape/visual envelope. - Volume and
mass. - Structural attachment points. - Equipment mounting points. -
Internal usable space. - Armour/structural properties. - Collision
representation. - Compatible module connection types.

### B. Interior rooms and access

-   Deck-based 2D grids stacked into a 3D interior.
-   Rooms, corridors, hatches, ladders/vertical shafts and bulkheads.
-   Orientation need not imply gravity.
-   Connections define whether a crew team can traverse from one
    compartment to another.
-   Room geometry and structural occupancy must agree with the hull
    envelope.

### C. Installed systems

-   Reactors, engines, RCS, power distribution, radiators, weapons,
    magazines, sensors, workshops, fuel tanks, cargo, life support,
    docking hardware and other equipment.
-   Position affects mass distribution, access, vulnerability,
    wiring/piping, heat and structural loads.

## Editor interface

Provide: - Top, side and front orthographic views. - Deck selection and
cross-section view. - 3D inspection/preview. - Grid snapping and module
attachment. - Place/move/rotate/remove tools. - Equipment and room
palette. - Mass, thrust, power, heat and storage summary. - Validation
panel with actionable messages. - Save/load blueprint. - Launch a test
flight using the current design. - Load a prebuilt template and modify
it.

## Validation

At minimum validate: - Modules attach to compatible structural
connectors. - No unsupported or disconnected hull modules unless
explicitly allowed by a rule. - Equipment fits within allowed mounting
volume. - Weapon firing arcs are not obstructed by the ship's own
geometry. - Rooms lie inside valid hull volume. - Connections connect
valid neighbouring rooms or interfaces. - No required system is
disconnected from its power source. - Engine and weapon resource
requirements can be met or are clearly marked as unavailable. - Crew
roles and required access routes are reported. - Mass and centre of mass
are calculated. - Propulsion/torque capability is shown. - Pressure
boundaries and docking access are valid.

Warnings should not automatically forbid unconventional designs unless
the design is physically or structurally invalid. The game should expose
trade-offs rather than enforce a single optimal layout.

## Hull modelling approach

Start with modular hull sections and grid-based interior components, not
freeform voxel construction. Keep the visual exterior separate from the
structural representation. Use simplified collision geometry and an
explicit structural attachment graph.

The same underlying model must drive construction, flight mass
properties, damage, repairs and persistence.

------------------------------------------------------------------------

# 7. Damage and ship systems

## Damage resolution

Do not use a single global hit-point bar as the primary damage model. A
ship can still have a summary condition indicator, but damage should
resolve against physical and logical components.

A hit should: 1. Intersect the external geometry or collision
representation. 2. Resolve impact direction, projectile energy and
armour layers. 3. Determine whether the projectile stops, penetrates,
fragments or transfers damage. 4. Damage the struck hull section,
compartment boundary or equipment. 5. Continue the penetration path if
applicable. 6. Affect nearby systems only when justified by the
simplified model. 7. Update power, heat, pressure, access and fire
state. 8. Produce readable feedback about what failed and why.

Start with deterministic simplified penetration calculations. Keep the
model data-driven and testable. Avoid pretending to be a full
finite-element solver.

## Damage types and consequences

-   Kinetic impact and penetration.
-   Explosive fragmentation and blast effects.
-   Thermal damage and overheating.
-   Electrical/electronic disruption.
-   Structural failure and module detachment.
-   Pressure loss and depressurisation.
-   Fire and secondary damage.
-   Radiation hazards for relevant weapon effects.

## Compartment states

Each compartment can track: - Pressure/atmosphere state. -
Fire/smoke/hazard state where implemented. - Structural integrity. -
Accessibility. - Hatch/door state. - Friendly/enemy/contested control
state during boarding. - Installed systems and damage. - Crew roles
currently assigned or able to reach it.

A breached outer hull does not automatically destroy every object
inside. Interior bulkheads and local protection matter. A projectile
should only damage internal objects if its trajectory and penetration
justify it.

## Power and thermal systems

Power graph: - Reactors and batteries produce/store energy. - Loads
request power. - Cables/buses/breakers transmit or interrupt power. -
Damage can isolate local systems. - Priorities determine which loads
shed during shortage.

Thermal graph: - Reactors, engines, lasers and other systems generate
heat. - Coolant loops and heat exchangers transfer heat. - Radiators
reject heat. - Damage or retraction reduces cooling. - Overheated
systems throttle, shut down or become damaged according to their
definitions.

Start with a simple stable model. Every added variable must have a
visible gameplay consequence.

------------------------------------------------------------------------

# 8. Crew simulation without individual character models

Do not build individual animated crew or individual navigation agents in
the initial version. Crew are abstract personnel with counts, roles,
qualifications and access constraints.

## Roles

-   Command.
-   Engineering.
-   Damage control.
-   Weapons operation where relevant.
-   Security/boarding.
-   Medical.
-   General crew.

Roles may overlap on small ships. Crew complement should be meaningful,
and a crew member assigned to one task may not be simultaneously
available elsewhere unless explicitly modelled.

## Crew-access graph

Rooms are nodes; corridors, hatches and shafts are edges. Each
connection has states such as open, sealed, blocked, damaged or unsafe.
Access is recalculated when those states change.

Task effectiveness depends on: - Crew count and role/qualification. -
Whether the team can reach the target system. - Abstract travel time. -
Pressure, fire or other hazards. - Whether the relevant system is
powered and repairable. - Tools/spare parts availability where relevant.

Crew are not teleported between rooms. Simulate route availability and
task timing abstractly; do not render individual crew movement.

## Repair and damage control

-   Repair tasks have duration, required role, tools/parts and access
    requirements.
-   Crew can seal breaches, isolate fires, reroute power or repair
    components when equipped and able to reach the location.
-   Tasks may be interrupted by new damage or lost access.
-   Repair prioritisation should be player-directed or use a simple
    transparent default policy.

------------------------------------------------------------------------

# 9. Boarding: physical, deliberate and counterable

Boarding parties must never teleport from one ship to another.

## Boarding sequence

1.  Suppress or disable enough of the target to create an opportunity.
2.  Rendezvous with the target using actual relative position and
    velocity.
3.  Match relative motion and orient suitable docking interfaces.
4.  Secure a compatible docking collar or extend a physical gangway.
5.  Connect the two access networks through an airlock/vestibule.
6.  Open the required hatches or attempt forced entry.
7.  Resolve abstract boarding-team movement and compartment control
    through the access graph.
8.  Capture objectives, withdraw or lose the team.

## Connection requirements

-   Relative position, velocity and orientation must fall within
    configurable tolerances.
-   Ports must be physically compatible and unobstructed.
-   The connection can be damaged or severed.
-   The attacker must maintain a viable connection while boarding is
    active.
-   If the target can still manoeuvre, it may attempt to break contact.
-   Boarding parties cannot instantly return to their ship if the route
    is cut.

## Anti-exploit rules

-   Docking ports need functional vestibules, pressure boundaries and
    inner hatches.
-   Ports may connect to isolated compartments; do not force every port
    to have a direct corridor to the bridge.
-   Isolation, depressurisation and sealing are valid defensive actions
    with operational costs.
-   No single room automatically kills every attacker. Outcomes depend
    on local crew strength, equipment, visibility, geometry and
    preparation.
-   Attackers can reconnoitre, cut through barriers, breach an
    alternative hull section or select another port, at meaningful cost.
-   Reinforcements require a valid route and simulated travel time.
-   Defenders can prepare ambushes, but pay in mass, volume, personnel
    and flexibility.
-   Attackers can retreat or abandon the attempt when physically
    feasible.
-   A boarding attempt is a strategic commitment: personnel and
    resources are exposed and unavailable for other tasks.

Boarding combat should be an abstract tactical simulation, not a
first-person shooter.

------------------------------------------------------------------------

# 10. Weapons catalogue

Implement only a subset in the initial vertical slice, but use
extensible data definitions.

## Kinetic weapons

-   Light autocannon / point-defence cannon.
-   Medium kinetic cannon.
-   Railgun or mass driver.
-   Armour-piercing penetrator.
-   Fragmentation or proximity-fused projectile, later.

Traits: finite flight time, recoil, ammunition mass, firing arc, muzzle
velocity, penetration, reload and magazine access.

## Missiles

-   Short-range interceptor.
-   Guided anti-ship missile.
-   Kinetic impactor.
-   EMP warhead.
-   Nuclear warhead.
-   Decoy or sensor payload.

Traits: finite acceleration and speed, turn limits, guidance, endurance,
seeker behaviour, countermeasure vulnerability, ammunition storage and
reloading.

## Directed energy

-   Laser point defence.
-   Precision laser weapon.
-   High-power thermal weapon, later.

Traits: line of sight, power, cooling, dwell time and range-dependent
effects. Do not make energy weapons free or instant in every respect.

## Electronic warfare

-   Radar/sensor jamming.
-   Communications disruption.
-   Decoys and false signatures.
-   Tracking interference.

EW should affect information quality and guidance, not arbitrarily turn
off every enemy system.

## EMP

EMP is a disruption weapon, not a universal shutdown button. - Effects
depend on range, exposure, shielding, hardening, isolation and
redundancy. - Exposed or insufficiently protected electronics may reset
or malfunction temporarily. - Sensors, communications, fire control and
power controllers may be affected. - Mechanical systems do not
automatically stop unless their control electronics are affected. -
Systems should have recovery states and diagnostic feedback. - Shielding
and redundancy cost mass, volume or money.

## Nuclear weapons

Nuclear weapons are scarce strategic weapons, not guaranteed one-hit
kills. - Include finite-speed guided delivery and interception
opportunities. - Model radiation, thermal exposure and
distance/line-of-sight effects. - Do not model a conventional
atmospheric blast wave in vacuum. - Effects depend on detonation
geometry, shielding, exposure and target structure. - Consider campaign
scarcity, expense and mission/political consequences later. - Keep
nuclear effects distinct from ordinary explosive damage.

## Point defence

-   Autocannons, interceptor missiles and laser interception.
-   Requires sensors, tracking, suitable firing arcs, ammunition/power
    and reaction time.
-   No point-defence system can cover every direction simultaneously
    without cost.

------------------------------------------------------------------------

# 11. Drones and ship-launched fighters

Use the same core spacecraft simulation as the player's ship. The
AI/controller differs; the physical rules do not.

## Drones

-   Reconnaissance drone.
-   Electronic warfare drone.
-   Interceptor drone.
-   Repair/inspection drone.
-   Salvage drone.
-   Attack drone, later.

Drone constraints: storage, mass, power, propellant/endurance, sensor
capability, communications, maintenance and loss risk. Drones may be
jammed, intercepted or damaged.

## NPC-controlled fighters

The player issues directives; AI handles detailed flight and combat.

Initial directives: - **Intercept:** engage hostile fighters or incoming
threats. - **Strike:** attack a designated ship or subsystem. -
**Recon:** scout and maintain target contact. - **Escort:** protect a
friendly ship. - **Return:** disengage and recover at the carrier.

Command parameters: - Target priority. - Risk tolerance: conservative,
balanced or aggressive. - Formation: defensive screen, tight, dispersed
or independent. - Rules of engagement. - Ammunition/propellant reserve
and return threshold.

AI must consider target visibility, local threats, damage, ammunition,
fuel/endurance, carrier distance and directive. If communications are
disrupted, use a defined fallback policy rather than making units inert.

## Carrier and support infrastructure

-   Fighter hangar or external craft mounts.
-   Launch and recovery interface.
-   Drone bay.
-   Flight-control system.
-   Mission-planning/command interface.
-   Maintenance workshop and spare parts.
-   Fuel/propellant and ammunition stores.
-   Docking and service arms.

Launch/recovery should require clear physical space and valid relative
motion. Fighters can be lost, damaged, repaired, rearmed and persist
between missions. A small ship may carry one or two craft; dedicated
carriers trade weapons, armour, cargo or propulsion for air-wing
capacity.

------------------------------------------------------------------------

# 12. Room and support infrastructure catalogue

Use data-driven definitions. Add equipment gradually.

## Core systems

-   Command/bridge.
-   Reactor.
-   Power distribution.
-   Engine room.
-   RCS/manoeuvring systems.
-   Thermal management.
-   Sensors/fire control.
-   Communications/data systems.

## Weapons and ammunition

-   Weapon mounts.
-   Magazines.
-   Reload handling.
-   EMP system/launcher.
-   Missile launchers.
-   Fighter/drone control.

## Survivability

-   Armour panels and spaced armour.
-   Reinforced bulkheads.
-   Damage-control station.
-   Workshop.
-   Spare-parts store.
-   Emergency batteries/generator.
-   Fire suppression.
-   Pressure control.
-   Airlock and boarding vestibule.
-   Emergency shelter.
-   Radiation monitoring/shielding where relevant.

## Crew and boarding

-   Crew quarters.
-   Medical bay.
-   Security station/armory.
-   Brig.
-   Crew staging area.
-   Boarding airlock.
-   Docking collar and gangway interface.

## Logistics

-   Cargo bay.
-   Hangar/drone bay.
-   Fabrication/salvage processing bay, later.
-   Fuel/propellant storage.
-   Life support.
-   EVA locker.
-   External maintenance arm.
-   Data/blueprint storage.

## External systems

-   Main engines and RCS thrusters.
-   Radiators.
-   Sensor/antenna arrays.
-   Docking collars.
-   Gangways.
-   Robotic arms.
-   External drone/fighter mounts.

Every room or component must provide a capability, resource capacity,
connection or meaningful defensive property. Avoid decorative rooms that
consume development effort without affecting gameplay.

------------------------------------------------------------------------

# 13. Ship archetypes and progression

Provide templates for: - Interceptor: high thrust-to-mass, low endurance
and limited armour. - Line frigate: balanced combat, defence and
systems. - Missile boat: large magazine and sensors, vulnerable when
depleted or tracked. - Boarding vessel: security crew, docking gear and
protected access. - Carrier: fighter storage, recovery, maintenance and
command. - Drone tender/EW ship: sensors, drones and electronic
warfare. - Salvage/support ship: cargo, workshops, robotic arms and
repair supplies.

These are templates, not rigid classes. Custom ships should be judged by
engineering consequences, not arbitrary bonuses.

## Player modes

-   **Pilot:** select a prebuilt ship, customise loadout and fight.
-   **Engineer:** modify existing hulls and optimise layout/systems.
-   **Shipwright:** construct hulls, systems and fleet blueprints.

## Persistence

Keep blueprint and physical vessel separate: - Blueprint retains design
and designer metadata. - Physical ship retains current damage,
components, ammunition, cargo, crew, history and condition. -
Destruction may lose installed components/upgrades but should not
automatically erase the blueprint. - Record repairs, replaced/salvaged
components and battle history. - Ship names and history should make
vessels feel owned and persistent.

------------------------------------------------------------------------

# 14. User interface and cognitive load

3D simulation must not require the player to understand every system
simultaneously.

## Flight HUD

-   World view and target markers.
-   Radar with bearing/range/elevation and approach/recede.
-   Target panel with range, relative velocity, heading, projectile
    flight time and intercept estimate.
-   Ship condition, power, heat, propulsion and ammunition.
-   Clear indicators for sensor uncertainty and component failures.

## Shipyard UI

Use a 2.5D construction interface over a genuinely 3D model: -
Orthographic top/side/front views. - Deck layers and cross-sections. -
3D inspection mode. - Grid snapping, module palette and validation. -
Resource budget and mass/centre-of-mass summary. - Quick switch to
prebuilt templates.

## Combat management

-   Detailed engineering should mostly happen in shipyard or safe
    recovery.
-   PvE can support optional tactical pause for orders.
-   PvP, if added, should use quick commands and automation rather than
    pausing the world.
-   Do not require the player to manually operate every reactor, pump,
    weapon or fighter continuously.
-   Provide automation policies with explicit priorities and
    understandable outcomes.

## Tutorials

Introduce systems progressively: 1. Translation, rotation and inertia.
2. Targeting and finite-time intercepts. 3. Orbital movement. 4.
Construction, mass and thrust. 5. Damage and repair. 6. Power/thermal
networks. 7. Drones and fighters. 8. Boarding and compartment control.

------------------------------------------------------------------------

# 15. Persistence, salvage and repair loop

Core loop:

**Design → Validate → Fly → Fight → Take damage → Recover → Salvage →
Repair → Redesign**

-   Salvage yields recoverable components and materials based on wreck
    condition and access.
-   Recovery requires proximity, compatible equipment or a
    docking/service interface.
-   Repair time, spare parts, crew access and workshop capability
    matter.
-   Destroyed components cannot be repaired without replacement or a
    defined restoration process.
-   A workshop should not magically create all components without
    materials.
-   Repair choices can prioritise combat readiness, mobility, sensors or
    full restoration.
-   Store save data in a versioned format and provide migration handling
    when schemas change.
-   Test saving and reloading both blueprints and damaged ship
    instances.

------------------------------------------------------------------------

# 16. AI, testing and acceptance criteria

Automated tests are mandatory for the core simulation. Do not rely only
on visually inspecting the game.

## Minimum test suites

### Orbital/flight

-   No-thrust orbit remains bounded under suitable initial conditions.
-   Thrust changes trajectory in the expected direction.
-   Numerical integration does not drift unacceptably over a defined
    test period.
-   Projectile inherits shooter velocity and has finite flight time.
-   Relative motion/intercept prediction behaves correctly for simple
    known scenarios.

### Ship construction

-   Valid blueprint can be saved and loaded without data loss.
-   Invalid module attachment is detected.
-   Room/access connections are valid.
-   Mass and centre of mass are calculated consistently.
-   Missing power connections are reported.
-   Obstructed weapon arcs are reported.

### Damage

-   Armour stops a projectile when the configured penetration is
    insufficient.
-   A penetrating projectile can damage a component along its path.
-   Destroying a power bus affects connected loads but not independent
    networks.
-   A breach changes pressure/access state according to adjacent
    boundaries.
-   Heat accumulation can throttle or shut down a system.
-   Shielded and unshielded electronics respond differently to EMP.

### Crew/boarding

-   Crew cannot access a room through a sealed or destroyed connection.
-   Repair task cannot begin if required crew/access/tools are
    unavailable.
-   Docking fails outside relative position/velocity/orientation
    tolerances.
-   Boarding begins only when a physical connection exists.
-   Disconnecting the gangway changes access and can strand a team.
-   Ambushes are not automatic kills; outcomes depend on configured
    tactical factors.

### Autonomous units

-   Fighter follows intercept/strike/recon/escort/return directives.
-   Damaged or low-resource craft can disengage under conservative
    rules.
-   Drone can be lost, damaged or recovered.
-   Communications disruption triggers defined fallback behaviour.

### Persistence

-   Blueprint and physical vessel state persist independently.
-   Damage, inventory and component replacement survive save/load.
-   Versioned saves detect unsupported schema versions safely.

## Design validation experiments

-   Test two same-budget frigates with different room layouts against
    identical attacks.
-   Test a heavily armoured ship against a high-mass kinetic weapon and
    a missile.
-   Test redundant vs single-bus power layouts under identical component
    damage.
-   Test EMP against shielded, unshielded and redundant electronic
    configurations.
-   Test whether point defence, fighters and missiles have distinct
    tactical niches.
-   Test boarding against both an isolated vestibule and a multi-route
    layout.
-   Ensure no one design dominates every scenario.

Every test should state what is being measured, expected result and
actual result.

------------------------------------------------------------------------

# 17. Milestone roadmap

## Milestone 0 --- Repository and project health

-   Inspect project/repository.
-   Establish Godot project, folders, version control and docs.
-   Create a bootable minimal scene.
-   Add a basic test harness and logging. **Exit criteria:** project
    launches cleanly; basic tests run; documentation matches repository.

## Milestone 1 --- Flight sandbox

-   6DoF movement and flight assist.
-   One central body and gravity.
-   One target ship.
-   Kinetic cannon with finite flight time.
-   Radar/target panel. **Exit criteria:** ship movement is
    understandable; trajectories and projectile timing pass tests.

## Milestone 2 --- Ship blueprint and builder

-   Modular hull.
-   Deck grid, rooms, corridors, hatches.
-   Equipment placement.
-   Save/load blueprint.
-   Mass and thrust calculations.
-   Prebuilt frigate template. **Exit criteria:** player can modify a
    ship, validate it, save it and launch it.

## Milestone 3 --- Physical damage and ship systems

-   Armour layers and penetration.
-   Component damage.
-   Power graph.
-   Basic thermal model.
-   Pressure and access state. **Exit criteria:** two different layouts
    react differently to identical attacks for explainable reasons.

## Milestone 4 --- Persistence and recovery

-   Ship instance separate from blueprint.
-   Damage persists.
-   Salvage, spare parts and repair tasks.
-   Workshop and service interface. **Exit criteria:** complete a combat
    mission, return damaged, repair/reconfigure and relaunch.

## Milestone 5 --- Crew and boarding

-   Abstract crew roles.
-   Access graph and repair task assignment.
-   Docking tolerances and physical gangway.
-   Boarding team and compartment-control simulation. **Exit criteria:**
    boarding is physical, counterable and influenced by layout.

## Milestone 6 --- Drones, fighters and directives

-   Autonomous craft share physics.
-   Fighter directives and target priorities.
-   Drone reconnaissance/inspection.
-   Launch, recovery, repair and rearming. **Exit criteria:** player can
    command an NPC fighter and recover or lose it persistently.

## Milestone 7 --- EMP and advanced weapons

-   Electronics hardening and recovery.
-   EMP missile.
-   Guided missile and interception.
-   Nuclear weapon as a later high-cost strategic option. **Exit
    criteria:** weapons have distinct effects and viable counterplay.

## Milestone 8 --- Vertical-slice polish

-   Mission objectives.
-   Tutorial flow.
-   Clear damage reports.
-   UI, audio, effects and performance profiling.
-   Save/load hardening. **Exit criteria:** a new player can design or
    choose a ship, fight, take damage, recover, repair and understand
    what happened.

Do not begin the next milestone while the current milestone has major
regressions or no verified acceptance results.

------------------------------------------------------------------------

# 18. Initial task for Claude Code

Begin now with **Milestone 0 and the smallest part of Milestone 1**.

1.  Inspect the current working directory and repository before editing.
2.  Report a concise inventory of the existing project and identify
    whether it is an empty repository or an existing Godot project.
3.  Preserve useful existing work.
4.  Set up or validate the Godot 4 project, documentation and Git
    workflow.
5.  Create a minimal bootable 3D scene with a controllable spacecraft
    placeholder.
6.  Implement basic 6DoF movement with flight assist and clearly
    separated simulation state.
7.  Add one target marker and a basic HUD showing ship velocity and
    target range.
8.  Add automated tests for simple movement/state calculations where
    feasible.
9.  Run the project and tests, inspect errors, fix issues and report
    actual outcomes.
10. Update `docs/ROADMAP.md`, `CHANGELOG.md` and `KNOWN_ISSUES.md`.
11. Stop at the milestone boundary. Do not implement the entire design
    in one pass.

## Final instruction

Optimise for a small but real playable result. Use data-driven
definitions, explicit simulation state, stable IDs, tests and small
increments. Avoid speculative abstractions, unnecessary dependencies,
giant scripts and unverified claims. Whenever a system is simplified,
document the simplification and its gameplay consequence. The game
should grow through validated vertical slices, not through a large
volume of generated code.
