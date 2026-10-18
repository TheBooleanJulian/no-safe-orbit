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

## Design the player flies; set by the shipyard before it switches to this
## scene. Null = the default template.
static var launch_blueprint: ShipBlueprint

var world: WorldSimulation
var celestial: CelestialFrame
## The target shoots back (toggle with T).
var target_hostile: bool = false
var player_input := PlayerInput.new()
var _views: Dictionary = {}  # StringName -> ShipView
## Compiled designs: {blueprint, grid, stats, config} per ship id.
var _designs: Dictionary = {}


func _ready() -> void:
	InputBindings.apply_saved()
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
	_designs[PLAYER_ID] = _compile(launch_blueprint if launch_blueprint != null else template, template)
	_designs[TARGET_ID] = _compile(template, template)

	world = WorldSimulation.new()
	var r0 := EARTH.radius_m + START_ALTITUDE_M
	world.set_central_body(EARTH, Vec3d.new(0, r0, 0), Vec3d.new(0, 0, -EARTH.circular_speed(r0)))
	world.anchor_id = PLAYER_ID
	var player := ShipState.create(PLAYER_ID, "PLAYER", _designs[PLAYER_ID].config)
	player.attach_systems(_new_systems(PLAYER_ID))
	world.add_ship(player)
	# Target: 2.5 km ahead and off-axis on a slightly different orbit, crossing
	# the bow at ~25 m/s so range, lead and radar all have something to show.
	var target := ShipState.create(
		TARGET_ID, "TGT-01 KESTREL", _designs[TARGET_ID].config,
		Vector3(400, 120, -2500), Vector3(-25, 1.5, 6.0), Quaternion(Vector3.UP, 0.9))
	target.angular_velocity = Vector3(0.0, 0.03, 0.01)
	target.attach_systems(_new_systems(TARGET_ID))
	world.add_ship(target)
	world.set_input(TARGET_ID, ShipControlInput.neutral())

	_spawn_view(PLAYER_ID, Color.WHITE)
	_spawn_view(TARGET_ID, Color(1.0, 0.78, 0.72))
	GameLog.info("main", "Orbital sandbox ready: player flies '%s' (%.0f t), %s orbit at %.0f km, fixed dt %.4f s" % [
		_designs[PLAYER_ID].config.display_name, _designs[PLAYER_ID].config.mass_kg / 1000.0,
		EARTH.display_name, START_ALTITUDE_M / 1000.0, world.fixed_dt])


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
		_start_scenario()
		return
	elif event.is_action_pressed("open_shipyard"):
		open_shipyard()
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


## Leave flight for the shipyard, taking the design being flown.
func open_shipyard() -> void:
	launch_blueprint = _designs[PLAYER_ID].blueprint
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(SHIPYARD_SCENE)


func _process(delta: float) -> void:
	var player := world.get_ship(PLAYER_ID)
	var target := world.get_ship(TARGET_ID)
	var target_id := TARGET_ID if target.is_active() else &""
	world.set_input(PLAYER_ID, player_input.build_input(delta, target_id))
	if target_hostile and target.is_active():
		world.set_input(TARGET_ID, GunneryAI.command(target, player))
	# Freeze the moment the player is lost (Backspace restarts) and while the
	# controls panel is open.
	var running := player.is_active() and not hud.controls.visible
	var alpha := world.advance(delta) if running else 1.0
	var hits := world.take_hit_events()
	hud.note_hits(hits, PLAYER_ID, world.sim_time)
	for ev in hits:
		hit_flashes.add(ev)

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
	hud.update_display(world, PLAYER_ID, TARGET_ID, alpha, render_origin, camera, player_input)


## Real Sun direction for the scenario date; dark while the player is in
## Earth's shadow (ships and the planet's night side agree).
func _update_sun(player: ShipState) -> void:
	var dir := celestial.sun_direction_pci(world.sim_time)
	sun.look_at(-dir, Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP)
	sun.light_energy = SUN_ENERGY * CelestialFrame.sunlight_fraction(world.pci_position(player.position), dir, EARTH.radius_m)
