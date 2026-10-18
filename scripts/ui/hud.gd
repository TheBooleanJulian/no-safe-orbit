class_name Hud
extends CanvasLayer
## Flight HUD: text readouts plus the world-marker overlay. Reads simulation
## state only; owns no gameplay logic.

@onready var overlay: HudOverlay = $Root/Overlay
@onready var flight_label: Label = $Root/FlightPanel/Margin/FlightLabel
@onready var target_label: Label = $Root/TargetPanel/Margin/TargetLabel


func update_display(
		player: ShipState, target: ShipState, alpha: float, render_origin: Vector3,
		camera: Camera3D, input: PlayerInput, sim_time: float) -> void:
	var v_body := player.body_velocity()
	var w := player.angular_velocity
	flight_label.text = "\n".join([
		"NO SAFE ORBIT  //  FLIGHT SANDBOX",
		"ASSIST     %s   [Z]" % ("ON " if input.flight_assist else "OFF — MANUAL"),
		"SPEED      %.1f m/s" % player.velocity.length(),
		"  fwd      %s" % HudFormat.signed_speed(-v_body.z),
		"  right    %s" % HudFormat.signed_speed(v_body.x),
		"  up       %s" % HudFormat.signed_speed(v_body.y),
		"RATE °/s   P %+5.1f  Y %+5.1f  R %+5.1f" % [rad_to_deg(w.x), rad_to_deg(w.y), rad_to_deg(w.z)],
		"Δv SPENT   %.1f m/s" % player.delta_v_expended,
		"T+         %s" % HudFormat.clock(sim_time),
	])

	overlay.camera = camera
	overlay.ship_render_pos = player.interpolated_position(alpha) - render_origin
	overlay.ship_forward = player.interpolated_orientation(alpha) * Vector3.FORWARD
	overlay.ship_velocity = player.velocity
	overlay.mouse_stick = input.mouse_stick
	overlay.has_target = target != null

	if target == null:
		target_label.text = "NO TARGET"
	else:
		var rng := RelativeMotion.range_between(player.position, target.position)
		var rr := RelativeMotion.range_rate(player.position, player.velocity, target.position, target.velocity)
		var rel_v := RelativeMotion.relative_velocity(player.velocity, target.velocity)
		target_label.text = "\n".join([
			"TARGET     %s" % target.display_name,
			"           %s" % target.config.display_name,
			"RANGE      %s" % HudFormat.distance(rng),
			"RANGE RATE %s  %s" % [HudFormat.signed_speed(rr), HudFormat.closure(rr)],
			"REL SPEED  %.1f m/s" % rel_v.length(),
		])
		overlay.target_render_pos = target.interpolated_position(alpha) - render_origin
		overlay.target_label = HudFormat.distance(rng)
	overlay.queue_redraw()
