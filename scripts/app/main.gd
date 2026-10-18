class_name Main
extends Node3D
## Flight sandbox entry point. Wires input → simulation → views each frame.
## The WorldSimulation is the source of truth; everything under this node is
## a view of it, rendered around a floating origin at the player ship.

const PLAYER_ID := &"player"
const TARGET_ID := &"target_01"
const FRIGATE_CONFIG: ShipConfig = preload("res://data/ships/placeholder_frigate.tres")
const SHIP_VIEW_SCENE: PackedScene = preload("res://scenes/ships/ship_view.tscn")

@onready var camera: ChaseCamera = $ChaseCamera
@onready var hud: Hud = $Hud
@onready var dust: DustField = $DustField
@onready var stars: Starfield = $Starfield

var world: WorldSimulation
var player_input := PlayerInput.new()
var _views: Dictionary = {}  # StringName -> ShipView


func _ready() -> void:
	world = WorldSimulation.new()
	world.add_ship(ShipState.create(PLAYER_ID, "PLAYER", FRIGATE_CONFIG))
	# Target: 2.5 km ahead and off-axis, drifting slowly across the bow and
	# turning lazily, so range, range rate and markers all have something to show.
	var target := ShipState.create(
		TARGET_ID, "TGT-01 KESTREL", FRIGATE_CONFIG,
		Vector3(400, 120, -2500), Vector3(-6, 0.5, 2.0), Quaternion(Vector3.UP, 0.9))
	target.angular_velocity = Vector3(0.0, 0.03, 0.01)
	world.add_ship(target)
	world.set_input(TARGET_ID, ShipControlInput.neutral())

	_spawn_view(PLAYER_ID, Color(0.55, 0.6, 0.66), Color(0.2, 0.7, 1.0))
	_spawn_view(TARGET_ID, Color(0.5, 0.45, 0.42), Color(0.95, 0.3, 0.2))
	GameLog.info("main", "Flight sandbox ready: %d ships, fixed dt %.4f s" % [world.ship_ids().size(), world.fixed_dt])


func _spawn_view(id: StringName, hull: Color, accent: Color) -> void:
	var view: ShipView = SHIP_VIEW_SCENE.instantiate()
	view.ship_id = id
	view.name = "ShipView_%s" % id
	view.hull_color = hull
	view.accent_color = accent
	add_child(view)
	_views[id] = view


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player_input.handle_event(event)


func _process(delta: float) -> void:
	world.set_input(PLAYER_ID, player_input.build_input(delta))
	var alpha := world.advance(delta)

	var player := world.get_ship(PLAYER_ID)
	var render_origin := player.interpolated_position(alpha)
	for id: StringName in _views:
		(_views[id] as ShipView).sync_from(world.get_ship(id), alpha, render_origin)

	camera.follow(_views[PLAYER_ID], delta)
	dust.update_origin(render_origin)
	stars.global_position = camera.global_position
	hud.update_display(player, world.get_ship(TARGET_ID), alpha, render_origin, camera, player_input, world.sim_time)
