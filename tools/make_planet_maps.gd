extends SceneTree
## Makes the cloud-top maps of the planets that have no usable global map
## (Milestone 16): Venus (featureless cloud in visible light), Saturn
## (Cassini never released a global colour map of the planet), Uranus and
## Neptune (Voyager 2 saw them from one side). Procedural, not imagery:
## latitude bands in each planet's colours (from Voyager, Cassini and
## Hubble images), warped and mottled by seeded noise sampled on the sphere
## (no seam at the date line), scaled so the map's mean is about the
## planet's albedo (the sky shader lights maps as it does Earth's). Seeded,
## so a re-run makes the same files.
##
##   godot --headless --path . -s res://tools/make_planet_maps.gd

const W := 2048
const H := 1024

# [latitude (deg), colour] stops, south to north.
const SATURN := [[-90, Color(0.6, 0.58, 0.53)], [-62, Color(0.79, 0.7, 0.53)], [-42, Color(0.87, 0.77, 0.57)],
	[-27, Color(0.78, 0.65, 0.45)], [-14, Color(0.92, 0.84, 0.65)], [0, Color(0.96, 0.9, 0.72)], [13, Color(0.92, 0.83, 0.63)],
	[26, Color(0.79, 0.67, 0.46)], [41, Color(0.87, 0.78, 0.58)], [58, Color(0.8, 0.73, 0.6)], [72, Color(0.66, 0.68, 0.7)],
	[90, Color(0.56, 0.61, 0.68)]]
const VENUS := [[-90, Color(0.95, 0.91, 0.78)], [-55, Color(0.93, 0.87, 0.7)], [0, Color(0.92, 0.85, 0.66)],
	[55, Color(0.93, 0.87, 0.7)], [90, Color(0.95, 0.91, 0.78)]]
const URANUS := [[-90, Color(0.62, 0.82, 0.86)], [-30, Color(0.66, 0.85, 0.88)], [0, Color(0.67, 0.86, 0.89)],
	[30, Color(0.68, 0.87, 0.9)], [55, Color(0.73, 0.89, 0.91)], [70, Color(0.8, 0.93, 0.94)], [90, Color(0.82, 0.94, 0.95)]]
const NEPTUNE := [[-90, Color(0.34, 0.5, 0.86)], [-60, Color(0.3, 0.46, 0.83)], [-40, Color(0.26, 0.4, 0.77)],
	[-20, Color(0.29, 0.45, 0.82)], [0, Color(0.31, 0.47, 0.84)], [20, Color(0.29, 0.45, 0.82)], [40, Color(0.26, 0.41, 0.78)],
	[65, Color(0.3, 0.46, 0.83)], [90, Color(0.33, 0.49, 0.85)]]


func _initialize() -> void:
	_make("res://data/saturn/saturn_clouds_procedural.jpg", SATURN, 11, 0.7, 0.03, 0.0, true, 0.58)
	_make("res://data/venus/venus_clouds_procedural.jpg", VENUS, 23, 4.0, 0.05, 0.0, false, 0.75)
	_make("res://data/uranus/uranus_clouds_procedural.jpg", URANUS, 37, 0.5, 0.015, 0.0, false, 0.62)
	_make("res://data/neptune/neptune_clouds_procedural.jpg", NEPTUNE, 41, 1.2, 0.03, 0.05, false, 0.85)
	quit(0)


## `warp_deg`: how far the bands wander in latitude; `mottle`: brightness
## noise; `streaks`: bright cirrus streaks (Neptune); `hexagon`: Saturn's
## north polar hexagon; `gain`: the whole map's brightness.
func _make(path: String, stops: Array, seed_value: int, warp_deg: float, mottle: float, streaks: float, hexagon: bool, gain: float) -> void:
	var warp := _noise(seed_value, 3.0, 4)
	var fine := _noise(seed_value + 1, 9.0, 5)
	var streak := _noise(seed_value + 2, 4.0, 3)
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		var lat := 90.0 - (y + 0.5) / H * 180.0
		var cl := cos(deg_to_rad(lat))
		var sl := sin(deg_to_rad(lat))
		for x in W:
			var lon := (x + 0.5) / W * 360.0 - 180.0
			# A point on the sphere, stretched east–west so features shear
			# into bands as a fast-turning planet's do.
			var p := Vector3(cl * cos(deg_to_rad(lon)), cl * sin(deg_to_rad(lon)), sl * 3.0)
			var lat_w := lat + warp_deg * warp.get_noise_3dv(p)
			var c := _band(stops, lat_w)
			c = c * (1.0 + mottle * fine.get_noise_3dv(p * 2.0))
			if streaks > 0.0 and absf(lat) > 18.0 and absf(lat) < 50.0:
				# Long thin cirrus: smooth along the bands, narrow across.
				var s := streak.get_noise_3dv(Vector3(p.x * 0.6, p.y * 0.6, p.z * 3.0))
				c = c.lerp(Color(0.92, 0.95, 1.0), clampf((s - 0.5) * 5.0, 0.0, 1.0) * streaks * 10.0)
			if hexagon and lat > 70.0:
				# The hexagon's edge: apothem 13° from the pole.
				var k := fposmod(lon + 30.0, 60.0) - 30.0
				var edge := 13.0 / cos(deg_to_rad(k))
				var off := absf((90.0 - lat) - edge)
				c = c.darkened(0.12 * clampf(1.0 - off / 0.9, 0.0, 1.0))
			img.set_pixel(x, y, Color(clampf(c.r * gain, 0.0, 1.0), clampf(c.g * gain, 0.0, 1.0), clampf(c.b * gain, 0.0, 1.0)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := img.save_jpg(ProjectSettings.globalize_path(path), 0.88)
	print("%s: %s" % [path, error_string(err)])


func _band(stops: Array, lat: float) -> Color:
	lat = clampf(lat, -90.0, 90.0)
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if lat <= float(b[0]):
			return (a[1] as Color).lerp(b[1], smoothstep(float(a[0]), float(b[0]), lat))
	return stops[stops.size() - 1][1]


func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.frequency = frequency
	return n
