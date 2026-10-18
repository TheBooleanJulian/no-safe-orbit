class_name Main
extends Node3D
## Orbital sandbox entry point. Wires input → simulation → views each frame.
## The WorldSimulation is the source of truth; everything under this node is
## a view of it, rendered around a floating origin at the player ship.

const PLAYER_ID := &"player"
const TARGET_ID := &"target_01"
const FRIGATE_CONFIG: ShipConfig = preload("res://data/ships/placeholder_frigate.tres")
const EARTH: OrbitalBody = preload("res://data/bodies/earth.tres")
const SHIP_VIEW_SCENE: PackedScene = preload("res://scenes/ships/ship_view.tscn")
## Scenario: circular equatorial orbit at ISS-like altitude, on the day side.
const START_ALTITUDE_M := 400_000.0
## Direction towards the sun (PCI axes). Planet is −Y from the start point,
## prograde is −Z, so this puts the start ~20 minutes before sunset.
const SUN_DIRECTION := Vector3(-0.5, 0.75, 0.2)

@onready var camera: ChaseCamera = $ChaseCamera
@onready var hud: Hud = $Hud
@onready var dust: DustField = $DustField
@onready var sky: PlanetSky = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var projectile_view: ProjectileView = $ProjectileView
@onready var hit_flashes: HitFlashes = $HitFlashes

var world: WorldSimulation
var player_input := PlayerInput.new()
var _views: Dictionary = {}  # StringName -> ShipView


func _ready() -> void:
	sun.look_at(-SUN_DIRECTION.normalized(), Vector3.UP)
	sky.configure(EARTH)
	_start_scenario()


func _start_scenario() -> void:
	for view in _views.values():
		(view as ShipView).queue_free()
	_views.clear()
	hud.reset()
	hit_flashes.clear()

	world = WorldSimulation.new()
	var r0 := EARTH.radius_m + START_ALTITUDE_M
	world.set_central_body(EARTH, Vec3d.new(0, r0, 0), Vec3d.new(0, 0, -EARTH.circular_speed(r0)))
	world.anchor_id = PLAYER_ID
	world.add_ship(ShipState.create(PLAYER_ID, "PLAYER", FRIGATE_CONFIG))
	# Target: 2.5 km ahead and off-axis on a slightly different orbit, crossing
	# the bow at ~25 m/s so range, lead and radar all have something to show.
	var target := ShipState.create(
		TARGET_ID, "TGT-01 KESTREL", FRIGATE_CONFIG,
		Vector3(400, 120, -2500), Vector3(-25, 1.5, 6.0), Quaternion(Vector3.UP, 0.9))
	target.angular_velocity = Vector3(0.0, 0.03, 0.01)
	world.add_ship(target)
	world.set_input(TARGET_ID, ShipControlInput.neutral())

	_spawn_view(PLAYER_ID, Color(0.55, 0.6, 0.66), Color(0.2, 0.7, 1.0))
	_spawn_view(TARGET_ID, Color(0.5, 0.45, 0.42), Color(0.95, 0.3, 0.2))
	GameLog.info("main", "Orbital sandbox ready: %d ships, %s orbit at %.0f km, fixed dt %.4f s" % [
		world.ship_ids().size(), EARTH.display_name, START_ALTITUDE_M / 1000.0, world.fixed_dt])


func _spawn_view(id: StringName, hull: Color, accent: Color) -> void:
	var view: ShipView = SHIP_VIEW_SCENE.instantiate()
	view.ship_id = id
	view.name = "ShipView_%s" % id
	view.hull_color = hull
	view.accent_color = accent
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
	player_input.handle_event(event)


func _process(delta: float) -> void:
	var player := world.get_ship(PLAYER_ID)
	var target := world.get_ship(TARGET_ID)
	var target_id := TARGET_ID if target.is_active() else &""
	world.set_input(PLAYER_ID, player_input.build_input(delta, target_id))
	# Freeze the moment the player is lost; Backspace restarts.
	var alpha := world.advance(delta) if player.is_active() else 1.0
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
	dust.update_origin(world.continuous_position(render_origin))
	var planet_center := Vec3d.new().minus(world.frame.interpolated_origin(alpha).plus_v3(render_origin))
	sky.update_view(planet_center.to_vector3(), camera)
	projectile_view.sync(world.projectiles(), alpha, render_origin, player.velocity, camera)
	hit_flashes.update(world, alpha, render_origin, delta)
	hud.update_display(world, PLAYER_ID, TARGET_ID, alpha, render_origin, camera, player_input)
