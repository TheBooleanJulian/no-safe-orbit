class_name Main
extends Node3D
## Orbital sandbox entry point. Wires input → simulation → views each frame.
## The WorldSimulation is the source of truth; everything under this node is
## a view of it, rendered around a floating origin at the player ship.

const PLAYER_ID := &"player"
const TARGET_ID := &"target_01"
const EARTH: OrbitalBody = preload("res://data/bodies/earth.tres")
const SHIPYARD_SCENE := "res://scenes/shipyard/shipyard.tscn"
const SHIP_VIEW_SCENE: PackedScene = preload("res://scenes/ships/ship_view.tscn")
## Scenario: prograde equatorial orbit at ISS-like altitude, on the day side.
const START_ALTITUDE_M := 400_000.0
## Real sky date (UTC): sets the Sun, the stars' orientation and Earth's spin.
const SCENARIO_EPOCH_UTC := "2026-10-19T12:00:00"
## Sun's in-plane angle behind the start zenith: ~24 minutes before sunset.
const SUN_ANGLE_FROM_UP_DEG := 15.0
const SUN_ENERGY := 1.4

@onready var camera: ChaseCamera = $ChaseCamera
@onready var hud: Hud = $Hud
@onready var dust: DustField = $DustField
@onready var dust_far: DustField = $DustFieldFar
@onready var sky: PlanetSky = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var stars: Starfield = $Starfield
@onready var projectile_view: ProjectileView = $ProjectileView
@onready var hit_flashes: HitFlashes = $HitFlashes
var gangways := GangwayView.new()

## Design the player flies; set by the shipyard before it switches to this
## scene. Null = the default template. Only used to commission the first
## hangar vessel; after that the profile's vessel is flown.
static var launch_blueprint: ShipBlueprint
## Persistent player state (spare parts, loot, hangar vessel); loaded on
## first use from PlayerProfile.path.
static var profile: PlayerProfile

var world: WorldSimulation
var celestial: CelestialFrame
## The target shoots back (toggle with T).
var target_hostile: bool = false
var player_input := PlayerInput.new()
var _views: Dictionary = {}  # StringName -> ShipView
## Compiled designs: {blueprint, grid, stats, config} per ship id.
var _designs: Dictionary = {}
## This sortie's outcome (docked or lost) is already in the profile.
var _sortie_closed := false


static func get_profile() -> PlayerProfile:
	if profile == null:
		profile = PlayerProfile.load_or_new()
	return profile


func _ready() -> void:
	InputBindings.apply_saved()
	gangways.name = "Gangways"
	add_child(gangways)
	celestial = CelestialFrame.for_scenario(CelestialFrame.julian_date_from_iso(SCENARIO_EPOCH_UTC), SUN_ANGLE_FROM_UP_DEG)
	stars.build(celestial)
	hud.celestial = celestial
	sky.configure(EARTH)
	_start_scenario()


func _start_scenario() -> void:
	for view in _views.values():
		(view as ShipView).queue_free()
	_views.clear()
	hud.reset()
	hit_flashes.clear()

	var template := _load_template()
	var p := get_profile()
	hud.profile = p
	var vessel := p.ensure_vessel(launch_blueprint if launch_blueprint != null else template)
	_designs[PLAYER_ID] = _compile(vessel.blueprint, template)
	_designs[TARGET_ID] = _compile(template, template)

	world = WorldSimulation.new()
	var r0 := EARTH.radius_m + START_ALTITUDE_M
	world.set_central_body(EARTH, Vec3d.new(0, r0, 0), Vec3d.new(0, 0, -EARTH.circular_speed(r0)))
	world.anchor_id = PLAYER_ID
	var player := ShipState.create(PLAYER_ID, "PLAYER", _designs[PLAYER_ID].config)
	var systems := _new_systems(PLAYER_ID)
	if _designs[PLAYER_ID].blueprint == vessel.blueprint:
		# The vessel flies as it was left: damage persists between sorties.
		systems.apply_condition(vessel.condition)
		player.propellant_kg = minf(player.propellant_kg, _intact_tank_capacity(systems))
	player.attach_systems(systems)
	world.add_ship(player)
	_spawn_target()
	_sortie_closed = false

	_spawn_view(PLAYER_ID, Color.WHITE)
	_spawn_view(TARGET_ID, Color(1.0, 0.78, 0.72))
	GameLog.info("main", "Orbital sandbox ready: player flies '%s' (%.0f t), %s orbit at %.0f km, fixed dt %.4f s" % [
		_designs[PLAYER_ID].config.display_name, _designs[PLAYER_ID].config.mass_kg / 1000.0,
		EARTH.display_name, START_ALTITUDE_M / 1000.0, world.fixed_dt])


## Next contact: 2.5 km ahead of the player and off-axis on a slightly
## different orbit, crossing the bow at ~25 m/s so range, lead and radar all
## have something to show.
func _spawn_target() -> void:
	var player := world.get_ship(PLAYER_ID)
	var target := ShipState.create(
		TARGET_ID, "TGT-%02d KESTREL" % (get_profile().missions_completed + 1), _designs[TARGET_ID].config,
		player.position + Vector3(400, 120, -2500), player.velocity + Vector3(-25, 1.5, 6.0), Quaternion(Vector3.UP, 0.9))
	target.angular_velocity = Vector3(0.0, 0.03, 0.01)
	target.attach_systems(_new_systems(TARGET_ID))
	world.add_ship(target)
	world.set_input(TARGET_ID, ShipControlInput.neutral())


static func _intact_tank_capacity(systems: ShipSystems) -> float:
	var kg := 0.0
	for e in systems.equipment:
		if e.def.kind == EquipmentDefinition.Kind.PROPELLANT_TANK and not e.destroyed():
			kg += e.def.propellant_capacity_kg
	return kg


static func _load_template() -> ShipBlueprint:
	var errors := PackedStringArray()
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)
	assert(bp != null, "Default template failed to load: %s" % ", ".join(errors))
	return bp


## Validates and compiles a design; a design with errors falls back to `fallback`.
func _compile(bp: ShipBlueprint, fallback: ShipBlueprint) -> Dictionary:
	var catalog := ConstructionCatalog.default_catalog()
	var grid := ShipGrid.build(bp, catalog)
	var stats := ShipStats.compute(bp, grid)
	var report := ShipValidator.validate(bp, catalog, grid, stats)
	if report.has_errors():
		if bp == fallback:
			GameLog.error("main", "Template '%s' is invalid:\n%s" % [bp.name, report.summary()])
		else:
			GameLog.warn("main", "Design '%s' has errors; flying the template instead:\n%s" % [bp.name, report.summary()])
			return _compile(fallback, fallback)
	return {"blueprint": bp, "grid": grid, "stats": stats, "config": stats.to_ship_config(bp.name)}


func _new_systems(id: StringName) -> ShipSystems:
	var d: Dictionary = _designs[id]
	return ShipSystems.create(d.blueprint, d.grid, d.stats, d.config)


func _spawn_view(id: StringName, tint: Color) -> void:
	var view: ShipView = SHIP_VIEW_SCENE.instantiate()
	view.ship_id = id
	view.name = "ShipView_%s" % id
	view.blueprint = _designs[id].blueprint
	view.grid = _designs[id].grid
	view.stats = _designs[id].stats
	view.tint = tint
	add_child(view)
	_views[id] = view


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		player_input.suppress_fire = true  # the capture click is not a shot
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("restart_scenario"):
		GameLog.info("main", "Scenario restarted")
		close_sortie()
		_start_scenario()
		return
	elif event.is_action_pressed("open_shipyard"):
		open_shipyard()
		return
	elif event.is_action_pressed("salvage"):
		_on_salvage_pressed()
		return
	elif event.is_action_pressed("field_repair"):
		start_field_repair()
		return
	elif event.is_action_pressed("dock"):
		toggle_dock()
		return
	elif event.is_action_pressed("board"):
		toggle_boarding()
		return
	elif event.is_action_pressed("toggle_target_ai"):
		target_hostile = not target_hostile
		hud.target_hostile = target_hostile
		GameLog.info("main", "Target %s" % ("HOSTILE — guns free" if target_hostile else "passive"))
		if not target_hostile:
			world.set_input(TARGET_ID, ShipControlInput.neutral())
		return
	elif event.is_action_pressed("toggle_controls"):
		hud.controls.toggle()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	player_input.handle_event(event)


## Leave flight for the shipyard (dock), taking the design being flown.
func open_shipyard() -> void:
	close_sortie()
	launch_blueprint = _designs[PLAYER_ID].blueprint
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(SHIPYARD_SCENE)


func _notification(what: int) -> void:
	# Quitting mid-sortie docks the ship as it is: no repairs by quitting.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		close_sortie()


## Record how the sortie ended and save: docked with the ship's damage, or
## lost (rarer parts aboard are written off; the design survives).
func close_sortie() -> void:
	if _sortie_closed or world == null:
		return
	_sortie_closed = true
	var p := get_profile()
	var player := world.get_ship(PLAYER_ID)
	var catalog := ConstructionCatalog.default_catalog()
	var lines := PackedStringArray()
	# Boarders still on the other ship are left behind.
	for b in world.boardings:
		if b.link.attacker_id == PLAYER_ID and b.phase != BoardingAction.Phase.RETURNED and b.phase != BoardingAction.Phase.ABORTED:
			for m in b.team:
				if m.location < 0 and m.state != CrewRoster.State.DEAD:
					m.state = CrewRoster.State.DEAD
					lines.append("Boarder %s (%s) left behind" % [m.id, CrewRoster.ROLE_NAMES[m.role]])
	if not player.is_active():
		lines = p.lose_vessel(catalog)
		GameLog.info("main", "Vessel lost — %d rarer parts written off" % lines.size())
	elif _designs[PLAYER_ID].blueprint == p.vessel.blueprint:
		lines = p.dock(player.systems.condition(), catalog)
		GameLog.info("main", "Docked %s after sortie %d%s" % [p.vessel.name, p.vessel.sorties, " (damaged)" if p.vessel.is_damaged() else ""])
	for line in lines:
		GameLog.info("main", line)
	_save_profile()


func _save_profile() -> void:
	var err := get_profile().save()
	if err != OK:
		GameLog.warn("main", "Could not save the profile to %s (%s)" % [PlayerProfile.path, error_string(err)])


func _on_salvage_pressed() -> void:
	if hud.loot.visible:
		hud.loot.visible = false
		return
	var why := Salvage.block_reason(world.get_ship(PLAYER_ID), world.get_ship(TARGET_ID))
	if why != "":
		hud.notice("SALVAGE: " + why, world.sim_time)
		return
	salvage_target()


## Strip the disabled target: spare parts and loot crates by how intact it
## is, then the next contact arrives. Returns the drops.
func salvage_target() -> Array[LootRoller.Drop]:
	var target := world.get_ship(TARGET_ID)
	var p := get_profile()
	for b in world.boardings:
		if b.link.target_id == TARGET_ID and b.phase == BoardingAction.Phase.CAPTURED:
			b.bring_home()  # the prize crew come back with the stores
	var intact := target.systems.intact_fraction()
	var parts := Salvage.spare_parts_for(target.systems)
	p.spare_parts += parts
	var drops := p.pull(Salvage.pulls_for(target.systems), ConstructionCatalog.default_catalog())
	p.missions_completed += 1
	p.vessel.salvaged += 1
	p.vessel.record("Salvaged %s: %d spare parts, %d crates" % [target.display_name, parts, drops.size()])
	_save_profile()
	GameLog.info("main", "Salvaged %s (%d%% intact): %d parts; %s" % [target.display_name, roundi(intact * 100.0), parts,
		", ".join(drops.map(func(d: LootRoller.Drop) -> String: return "%s %s" % [Rarity.name_of(d.rarity), d.describe()]))])
	hud.loot.show_salvage(target.display_name, intact, parts, drops, p)
	world.remove_ship(TARGET_ID)
	hud.reset()
	_spawn_target()
	return drops


## V: extend a gangway to the target, or release the one we have.
func toggle_dock() -> void:
	var link := world.link_for(PLAYER_ID)
	if link != null:
		var b := world.boarding_for(link)
		link.release()
		hud.notice("Gangway released%s" % (" — the boarding party is cut off!" if b != null and not b.finished() and b.room >= 0 else ""), world.sim_time)
		return
	var found := world.dock(PLAYER_ID, TARGET_ID)
	if found.is_empty():
		hud.notice("DOCK: no working docking collar opening into a room", world.sim_time)
	elif not found.has("link"):
		hud.notice("DOCK: " + ", ".join(found.assessment.problems), world.sim_time)


## N: send a boarding party over a sealed gangway, or order it home.
func toggle_boarding() -> void:
	var link := world.link_for(PLAYER_ID)
	var b := world.boarding_for(link) if link != null else null
	if b != null and not b.finished():
		b.withdraw()
		return
	if link == null or not link.sealed():
		hud.notice("BOARD: needs a sealed gangway first [V]", world.sim_time)
		return
	if world.start_boarding(link) == null:
		hud.notice("BOARD: no fit security or general crew can reach the collar", world.sim_time)


## Damage control: the crew patch the next damaged system in a working
## workshop, for spare parts. Returns false (with a HUD notice) if blocked.
func start_field_repair() -> bool:
	var sys := world.get_ship(PLAYER_ID).systems
	var why := sys.field_repair_block_reason()
	if why != "":
		hud.notice("DAMAGE CONTROL: " + why, world.sim_time)
		return false
	var e := sys.field_repair_target()
	var cost := maxi(ServiceYard.damaged_cost(ServiceYard.equipment_cost(e.def), sys.field_repair_hp(e) / e.max_hp), 1)
	var p := get_profile()
	if cost > p.spare_parts:
		hud.notice("DAMAGE CONTROL: patching %s needs %d spare parts, you have %d" % [e.id, cost, p.spare_parts], world.sim_time)
		return false
	p.spare_parts -= cost
	sys.start_field_repair()
	hud.notice("Damage control: patching %s %s (%d parts)" % [e.def.display_name, e.id, cost], world.sim_time)
	return true


func _process(delta: float) -> void:
	var player := world.get_ship(PLAYER_ID)
	var target := world.get_ship(TARGET_ID)
	var target_id := TARGET_ID if target.is_active() else &""
	world.set_input(PLAYER_ID, player_input.build_input(delta, target_id))
	if target.is_active() and target.systems != null and target.systems.captured:
		world.set_input(TARGET_ID, ShipControlInput.neutral())
	elif world.link_for(TARGET_ID) != null and GunneryAI.can_break_contact(target):
		world.set_input(TARGET_ID, GunneryAI.break_contact(target, player))
	elif target_hostile and target.is_active():
		world.set_input(TARGET_ID, GunneryAI.command(target, player))
	# Freeze the moment the player is lost (Backspace restarts) and while the
	# controls panel is open.
	if not player.is_active() and not _sortie_closed:
		close_sortie()
	var running := player.is_active() and not hud.controls.visible
	var alpha := world.advance(delta) if running else 1.0
	for line in world.take_link_events():
		hud.notice(line, world.sim_time)
		GameLog.info("boarding", line)
	var hits := world.take_hit_events()
	hud.note_hits(hits, PLAYER_ID, world.sim_time)
	for ev in hits:
		hit_flashes.add(ev)
		if ev.shooter_id == PLAYER_ID and ev.report != null and _designs.has(ev.target_id):
			var struck := world.get_ship(ev.target_id)
			hud.hit_cam.show_hit(ev, _designs[ev.target_id], struck.systems, struck.display_name)

	var render_origin := player.interpolated_position(alpha)
	for id: StringName in _views:
		var ship := world.get_ship(id)
		var view: ShipView = _views[id]
		view.visible = ship.is_active()
		view.sync_from(ship, alpha, render_origin)

	camera.follow(_views[PLAYER_ID], delta)
	var continuous := world.continuous_position(render_origin)
	dust.update_origin(continuous)
	dust_far.update_origin(continuous)
	var planet_center := Vec3d.new().minus(world.frame.interpolated_origin(alpha).plus_v3(render_origin)).to_vector3()
	_update_sun(player)
	sky.update_view(planet_center, camera, celestial, world.sim_time)
	stars.update_view(camera, planet_center, EARTH)
	projectile_view.sync(world.projectiles(), alpha, render_origin, player.velocity, camera)
	hit_flashes.update(world, alpha, render_origin, delta)
	gangways.sync(world, alpha, render_origin)
	hud.update_display(world, PLAYER_ID, TARGET_ID, alpha, render_origin, camera, player_input)


## Real Sun direction for the scenario date; dark while the player is in
## Earth's shadow (ships and the planet's night side agree).
func _update_sun(player: ShipState) -> void:
	var dir := celestial.sun_direction_pci(world.sim_time)
	sun.look_at(-dir, Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP)
	sun.light_energy = SUN_ENERGY * CelestialFrame.sunlight_fraction(world.pci_position(player.position), dir, EARTH.radius_m)
