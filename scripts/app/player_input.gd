class_name PlayerInput
extends RefCounted
## Turns keyboard/mouse state into a ShipControlInput. All bindings are named
## InputMap actions (project.godot → Input Map), so they are rebindable.
##
## Steering is on the keys: A/D yaw (strafe while the docking camera is up),
## arrows pitch and yaw, Q/E roll, R/F up/down. The captured mouse moves an
## aim cursor: the turrets train on whatever is under it. Holding the right
## button and moving the mouse orbits the camera around the ship instead; a
## right click without dragging puts it back behind. Zoomed (Shift), the
## camera centres on the aim and the mouse turns the view itself, finely.

## Aim cursor pixels per mouse pixel.
const AIM_SENSITIVITY := 1.0
## Camera orbit radians per mouse pixel while the right button is held.
const ORBIT_SENSITIVITY := 0.005
const ORBIT_PITCH_LIMIT := 1.3
## A right click that moved less than this (px) resets the orbit.
const ORBIT_CLICK_PX := 6.0
## Zoomed, the mouse turns the view this much slower than an orbit drag.
const ZOOM_LOOK_FACTOR := 0.3

## What flight assist holds on uncommanded translation axes.
enum VelocityHold {
	## Coast: keep the current orbit, spend no Δv.
	ORBIT,
	## Null velocity relative to the target (velocity match).
	TARGET,
}

var flight_assist: bool = true
var velocity_hold: VelocityHold = VelocityHold.ORBIT
## Aim cursor, pixels from the screen centre; Main sets `aim_limit` (half the
## view) each frame so it stays on screen.
var aim_offset: Vector2 = Vector2.ZERO
var aim_limit: Vector2 = Vector2(640, 360)
## How far out the aim point is (m): the target's range when there is one.
var aim_range_m: float = 2000.0
## Camera orbit around the ship: x = yaw, y = pitch (radians).
var camera_orbit: Vector2 = Vector2.ZERO
## Gunnery zoom (toggled with Shift). `zoom_changed` is set on each toggle
## so Main can centre the view on the aim.
var zoomed: bool = false
var zoom_changed: bool = false
## Set when a click is consumed to capture the mouse, so it does not also
## fire; cleared once the fire action is released.
var suppress_fire: bool = false
var _orbiting := false
var _orbit_drag := 0.0


func handle_event(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_flight_assist"):
		flight_assist = not flight_assist
		GameLog.info("input", "Flight assist %s" % ("ON" if flight_assist else "OFF"))
	elif event.is_action_pressed("toggle_velocity_hold"):
		velocity_hold = VelocityHold.TARGET if velocity_hold == VelocityHold.ORBIT else VelocityHold.ORBIT
		GameLog.info("input", "Velocity hold: %s" % VelocityHold.keys()[velocity_hold])
	elif event.is_action_pressed("zoom_aim"):
		zoomed = not zoomed
		zoom_changed = true
	elif event.is_action_pressed("orbit_camera"):
		_orbiting = true
		_orbit_drag = 0.0
	elif event.is_action_released("orbit_camera"):
		_orbiting = false
		if _orbit_drag < ORBIT_CLICK_PX:
			camera_orbit = Vector2.ZERO
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		if _orbiting or zoomed:
			var k := ORBIT_SENSITIVITY * (ZOOM_LOOK_FACTOR if zoomed and not _orbiting else 1.0)
			_orbit_drag += rel.length()
			camera_orbit.x -= rel.x * k
			camera_orbit.y = clampf(camera_orbit.y - rel.y * k, -ORBIT_PITCH_LIMIT, ORBIT_PITCH_LIMIT)
		else:
			aim_offset = (aim_offset + rel * AIM_SENSITIVITY).clamp(-aim_limit, aim_limit)


## `target_id` is the ship to match in TARGET hold (empty = none available).
## `docking`: the docking camera is up, so A/D strafe instead of yawing.
func build_input(_frame_delta: float, target_id: StringName = &"", docking: bool = false) -> ShipControlInput:
	var steer := Input.get_axis("steer_left", "steer_right")
	var translation := Vector3(
		steer if docking else 0.0,
		Input.get_axis("thrust_down", "thrust_up"),
		Input.get_axis("thrust_forward", "thrust_backward"))
	var rotation := Vector3(
		Input.get_axis("pitch_down", "pitch_up"),
		Input.get_axis("yaw_right", "yaw_left") - (0.0 if docking else steer),
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
