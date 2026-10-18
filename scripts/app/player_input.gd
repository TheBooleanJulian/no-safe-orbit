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

## What flight assist holds on uncommanded translation axes.
enum VelocityHold {
	## Coast: keep the current orbit, spend no Δv.
	ORBIT,
	## Null velocity relative to the target (velocity match).
	TARGET,
}

var flight_assist: bool = true
var velocity_hold: VelocityHold = VelocityHold.ORBIT
## x = right, y = up, length ≤ 1. Exposed for the HUD stick indicator.
var mouse_stick: Vector2 = Vector2.ZERO
## Set when a click is consumed to capture the mouse, so it does not also
## fire; cleared once the fire action is released.
var suppress_fire: bool = false


func handle_event(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_flight_assist"):
		flight_assist = not flight_assist
		GameLog.info("input", "Flight assist %s" % ("ON" if flight_assist else "OFF"))
	elif event.is_action_pressed("toggle_velocity_hold"):
		velocity_hold = VelocityHold.TARGET if velocity_hold == VelocityHold.ORBIT else VelocityHold.ORBIT
		GameLog.info("input", "Velocity hold: %s" % VelocityHold.keys()[velocity_hold])
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		mouse_stick += Vector2(rel.x, -rel.y) * MOUSE_SENSITIVITY
		mouse_stick = mouse_stick.limit_length(1.0)


## `target_id` is the ship to match in TARGET hold (empty = none available).
func build_input(frame_delta: float, target_id: StringName = &"") -> ShipControlInput:
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
	var input := ShipControlInput.create(translation, rotation, flight_assist)
	var match_target := flight_assist and velocity_hold == VelocityHold.TARGET and target_id != &""
	input.hold_translation = match_target
	input.hold_target_id = target_id if match_target else &""
	var trigger := Input.is_action_pressed("fire")
	if not trigger:
		suppress_fire = false
	input.fire = trigger and not suppress_fire
	return input
