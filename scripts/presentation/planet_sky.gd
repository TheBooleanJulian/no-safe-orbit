class_name PlanetSky
extends WorldEnvironment
## Shows the central body (real geography, turning with the body), its
## atmosphere's limb (if it has one) and the Sun as a ray-traced sky
## (shaders/planet_sky.gdshader). The planet's surface scrolling past is the
## cue for orbital motion; the stars (Starfield) are the cue for rotation.

const SKY_SHADER: Shader = preload("res://shaders/planet_sky.gdshader")

var _material: ShaderMaterial
var _central: OrbitalBody
## The other body in the sky (Location.sky_body), or null.
var sky_body: OrbitalBody
## Its centre relative to the render origin (m), from the last update_view.
var sky_body_center := Vector3.ZERO
## Its reflected light at the render origin (moonlight, or earthlight from
## the Moon) as a fraction of the Sun's light energy, as shown
## (perceived_light), and 0 while it is below the horizon; and its direction.
var sky_body_light := 0.0
var sky_body_light_dir := Vector3.UP
## The central body's centre relative to the render origin (m), as last drawn.
var planet_center := Vector3.ZERO

## Shown brightness of reflected light: the real illuminance is millions of
## times weaker than sunlight (full Moon ~2.4e-6), invisible on a screen
## exposed for the Sun. The eye adapts by some twenty stops between
## sunlight and moonlight; the game stands in for that by showing the full
## Moon's light at NIGHT_LIGHT_FULL_MOON of the Sun's and compressing other
## levels with Stevens' brightness law (perceived ∝ luminance^0.5), so a
## half moon still gives ~1/3 of full-moon light and full Earth from the
## Moon (~50 × a full Moon) about seven times as much.
const NIGHT_LIGHT_FULL_MOON := 0.05
const FULL_MOON_FRACTION := 2.4e-6
## Moonlight and earthlight as the night-adapted eye sees them (Purkinje
## shift: bluish), on hulls and the night side.
const NIGHT_LIGHT_COLOR := Color(0.78, 0.86, 1.0)


static func perceived_light(fraction: float) -> float:
	return NIGHT_LIGHT_FULL_MOON * sqrt(maxf(fraction, 0.0) / FULL_MOON_FRACTION)


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = _material
	# Real-time radiance at the fast-filter size; the shader returns black for
	# the radiance pass, so the per-frame uniform updates stay cheap.
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED


## `other`: the far body drawn in the sky (null for none).
func configure(body: OrbitalBody, other: OrbitalBody = null) -> void:
	sky_body = other
	_central = body
	_material.set_shader_parameter("fill_color", NIGHT_LIGHT_COLOR)
	_material.set_shader_parameter("far_radius", other.radius_m if other != null else 0.0)
	if other != null:
		_material.set_shader_parameter("far_map", other.surface_map)
		_material.set_shader_parameter("far_has_air", 1.0 if other.has_atmosphere else 0.0)
	_material.set_shader_parameter("planet_radius", body.radius_m)
	_material.set_shader_parameter("entry_radius", body.entry_radius_m())
	_material.set_shader_parameter("has_air", 1.0 if body.has_atmosphere else 0.0)
	_material.set_shader_parameter("surface_map", body.surface_map)


## `planet_center_render`: body centre relative to the render origin (m).
func update_view(planet_center_render: Vector3, camera: Camera3D, frame: CelestialFrame, sim_time: float) -> void:
	planet_center = planet_center_render
	_material.set_shader_parameter("planet_center", planet_center_render)
	var height := maxf(camera.get_viewport().get_visible_rect().size.y, 1.0)
	_material.set_shader_parameter("pixel_angle", deg_to_rad(camera.fov) / height)
	_material.set_shader_parameter("pci_to_body", frame.pci_to_body_fixed(sim_time))
	_material.set_shader_parameter("cloud_time", sim_time)
	if sky_body != null:
		var rel := frame.position_of(sky_body, sim_time)  # central body → far body
		sky_body_center = planet_center_render + rel
		_material.set_shader_parameter("far_center", sky_body_center)
		_material.set_shader_parameter("far_to_body", frame.body_fixed_of(sky_body, sim_time))
		var sun := frame.sun_direction_pci(sim_time)
		# The far body lights the central body's night side (moonlight on
		# Earth, earthlight on the Moon) and the central body lights the far
		# body's (earthshine on the Moon's dark side, the "ashen glow").
		var near_fill := perceived_light(CelestialFrame.reflected_fraction(sky_body, rel, sun))
		var far_fill := perceived_light(CelestialFrame.reflected_fraction(_central, -rel, sun))
		_material.set_shader_parameter("near_fill", near_fill)
		_material.set_shader_parameter("near_fill_dir", rel.normalized())
		_material.set_shader_parameter("far_fill", far_fill)
		_material.set_shader_parameter("far_fill_dir", -rel.normalized())
		sky_body_light_dir = sky_body_center.normalized()
		sky_body_light = near_fill if not below_horizon(planet_center_render, _central.radius_m, sky_body_center) else 0.0


## Whether `point` (render space, e.g. the far body's centre) is hidden from
## the render origin by the central body (centre `planet_center`, `radius`).
static func below_horizon(planet_center: Vector3, radius: float, point: Vector3) -> bool:
	var dir := point.normalized()
	var oc := -planet_center
	var b := oc.dot(dir)
	return b < 0.0 and b * b - (oc.dot(oc) - radius * radius) > 0.0
