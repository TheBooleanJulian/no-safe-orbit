class_name DockingCam
extends PanelContainer
## Docking camera: when a target is within boarding range, a picture-in-
## picture view out of your docking collar along the gangway axis, with a
## crosshair and the docking tolerances. It renders the main 3D world from a
## second camera (shared World3D); Main places the camera each frame.

const SHOW_RANGE_M := 150.0

var camera: Camera3D
var _viewport: SubViewport
var _readout: Label
var _cross: Control
var _container: SubViewportContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", CyberTheme.panel(CyberTheme.MAGENTA, 6))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var title := Label.new()
	title.text = "DOCKING CAM — [V] gangway · J/L I/K strafe · R/F in / out"
	title.add_theme_color_override("font_color", CyberTheme.MAGENTA)
	title.add_theme_font_size_override("font_size", 12)
	box.add_child(title)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(400, 225)
	_container = container
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.3
	camera.far = 5000.0
	_viewport.add_child(camera)
	_cross = Control.new()
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cross.draw.connect(_draw_cross)
	container.add_child(_cross)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 12)
	_readout.add_theme_color_override("font_color", CyberTheme.TEXT)
	box.add_child(_readout)


func set_compact(compact: bool) -> void:
	if _container != null:
		_container.custom_minimum_size = Vector2(320, 180) if compact else Vector2(400, 225)


## Show the view from `from` (render space) looking along `axis`, with the
## docking assessment (Docking.assess result).
func show_view(from: Vector3, axis: Vector3, up_hint: Vector3, assessment: Dictionary) -> void:
	visible = true
	_viewport.world_3d = get_viewport().world_3d
	var up := up_hint if absf(axis.dot(up_hint)) < 0.95 else Vector3.FORWARD
	camera.look_at_from_position(from + axis * 0.5, from + axis * 10.0, up)
	camera.current = true
	var ok: bool = assessment.get("ok", false)
	_readout.text = "%s   gap %.1f / %.0f m   rel %.2f / %.1f m/s   off-square %.0f° / %.0f°" % [
		"IN TOLERANCE" if ok else "OUT OF TOLERANCE", assessment.get("range", 0.0), Docking.GANGWAY_MAX_M,
		assessment.get("rel_speed", 0.0), Docking.MAX_REL_SPEED_MPS, assessment.get("misalign_deg", 0.0), Docking.MAX_MISALIGN_DEG]
	_readout.add_theme_color_override("font_color", CyberTheme.OK if ok else CyberTheme.WARN)
	_cross.queue_redraw()


func _draw_cross() -> void:
	var c := _cross.size * 0.5
	var col := CyberTheme.MAGENTA
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_cross.draw_line(c + d * 8.0, c + d * 30.0, col, 1.5)
	_cross.draw_arc(c, 46.0, 0.0, TAU, 48, col * Color(1, 1, 1, 0.6), 1.0)
