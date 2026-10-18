class_name PlayerInput
extends RefCounted
## Turns keyboard/mouse state into a ShipControlInput. All bindings are named
## InputMap actions (project.godot → Input Map), so they are rebindable.
##
## Mouse acts as a self-centring virtual stick: motion deflects it, and it
## springs back to centre when the mouse stops. With assist on, deflection is a
## turn-rate request, so holding the mouse still holds a steady turn briefly
## then levels off.

const MOUSE_SENSITIVITY := 0.004   # stick units per pixel
const MOUSE_RECENTER_RATE := 3.0   # 1/s exponential return to centre

var flight_assist: bool = true
## x = right, y = up, length ≤ 1. Exposed for the HUD stick indicator.
var mouse_stick: Vector2 = Vector2.ZERO


func handle_event(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_flight_assist"):
		flight_assist = not flight_assist
		GameLog.info("input", "Flight assist %s" % ("ON" if flight_assist else "OFF"))
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		mouse_stick += Vector2(rel.x, -rel.y) * MOUSE_SENSITIVITY
		mouse_stick = mouse_stick.limit_length(1.0)


func build_input(frame_delta: float) -> ShipControlInput:
	mouse_stick *= exp(-MOUSE_RECENTER_RATE * frame_delta)
	var translation := Vector3(
		Input.get_axis("strafe_left", "strafe_right"),
		Input.get_axis("thrust_down", "thrust_up"),
		Input.get_axis("thrust_forward", "thrust_backward"))
	var rotation := Vector3(
		Input.get_axis("pitch_down", "pitch_up") + mouse_stick.y,
		Input.get_axis("yaw_right", "yaw_left") - mouse_stick.x,
		Input.get_axis("roll_right", "roll_left"))
	rotation = rotation.clamp(-Vector3.ONE, Vector3.ONE)
	return ShipControlInput.create(translation, rotation, flight_assist)
