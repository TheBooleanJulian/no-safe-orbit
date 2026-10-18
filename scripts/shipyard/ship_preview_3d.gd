class_name ShipPreview3D
extends SubViewportContainer
## 3D inspection view of the design, built with the same ShipModelBuilder as
## the flight view. Drag to orbit; it turns slowly on its own when idle.

const IDLE_TURN_RATE := 0.25  # rad/s

var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _model: Node3D
var _yaw := 2.4
var _pitch := -0.45
var _distance := 90.0
var _idle := true


func _ready() -> void:
	stretch = true
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.35, 0.45)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.3
	_viewport.add_child(light)
	light.look_at_from_position(Vector3.ZERO, Vector3(-0.5, -1.0, -0.3), Vector3.UP)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.far = 2000.0
	_viewport.add_child(_camera)
	_update_camera()


func show_design(editor: ShipEditor) -> void:
	if _model != null:
		_model.queue_free()
		_model = null
	if editor.blueprint.modules.is_empty():
		return
	var center := editor.grid.hull_bounds_m().get_center()
	_model = ShipModelBuilder.build(editor.blueprint, editor.grid, center).root
	_pivot.add_child(_model)
	_distance = maxf(editor.grid.hull_bounds_m().size.length() * 1.6, 30.0)
	_update_camera()


func _process(delta: float) -> void:
	if _idle and is_visible_in_tree():
		_yaw += IDLE_TURN_RATE * delta
		_update_camera()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		var rel := (event as InputEventMouseMotion).relative
		_yaw -= rel.x * 0.01
		_pitch = clampf(_pitch - rel.y * 0.01, -1.4, 1.4)
		_idle = false
		_update_camera()
		accept_event()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance *= 0.9
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance *= 1.1
		_update_camera()


func _update_camera() -> void:
	if _camera == null:
		return
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	_camera.position = dir * _distance
	_camera.look_at(Vector3.ZERO, Vector3.UP)
