class_name TerrainMap
extends RefCounted
## A body's surface heights (play-test batch 10): NASA's LOLA elevation map
## of the Moon (data/moon/lola_elevation.bin, made by tools/convert_lola.py
## from the SVS 4720 CGI Moon Kit: 8 pixels a degree, ~3.8 km at the
## equator, whole metres), sampled bilinearly, plus seeded detail finer than
## its pixels so the ground close up isn't smooth. Heights are metres
## relative to the body's mean radius. Rows are decoded the first time they
## are needed (each is stored as differences along it).

## Amplitude (m) and feature size (m) of the procedural detail.
const DETAIL_M := 90.0
const DETAIL_SCALE_M := 2500.0
const MAGIC := "NSOLOLA1"

static var _cache: Dictionary = {}

var width: int = 0
var height: int = 0
## The body's mean radius (m), for the detail's scale.
var radius_m: float = 1_737_400.0
var _packed: PackedByteArray
var _rows: Dictionary = {}  # row -> PackedFloat32Array
var _noise: FastNoiseLite


## A body with no elevation map (Mercury, Phobos, Deimos): the mean-radius
## sphere and the fine seeded detail alone.
static func bare(p_radius_m: float) -> TerrainMap:
	var key := "bare:%f" % p_radius_m
	if _cache.has(key):
		return _cache[key]
	var map := TerrainMap.new()
	map.radius_m = p_radius_m
	map._noise = _detail_noise()
	_cache[key] = map
	return map


static func _detail_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = 1969
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	n.frequency = 1.0
	return n


## The map at `path` (cached), or null if it can't be read.
static func load_map(path: String) -> TerrainMap:
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		GameLog.warn("terrain", "Can't open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 12 or bytes.slice(0, 8).get_string_from_ascii() != MAGIC:
		GameLog.warn("terrain", "%s is not an elevation map" % path)
		return null
	var map := TerrainMap.new()
	map.width = bytes.decode_u16(8)
	map.height = bytes.decode_u16(10)
	map._packed = bytes.slice(12).decompress_dynamic(map.width * map.height * 2 + 1024, FileAccess.COMPRESSION_GZIP)
	if map._packed.size() != map.width * map.height * 2:
		GameLog.warn("terrain", "%s: expected %d × %d heights" % [path, map.width, map.height])
		return null
	map._noise = _detail_noise()
	_cache[path] = map
	return map


## The mapped height (m) at a pixel, rows and columns from the top left.
func pixel(x: int, y: int) -> float:
	var row: PackedFloat32Array = _rows.get(clampi(y, 0, height - 1), PackedFloat32Array())
	if row.is_empty():
		row = _decode_row(clampi(y, 0, height - 1))
	return row[posmod(x, width)]


func _decode_row(y: int) -> PackedFloat32Array:
	var row := PackedFloat32Array()
	row.resize(width)
	var h := 0
	var at := y * width * 2
	for x in width:
		h += _packed.decode_s16(at + x * 2)
		row[x] = h
	_rows[y] = row
	return row


## Height (m) of the map alone at latitude / longitude (degrees).
func mapped_height(lat_deg: float, lon_deg: float) -> float:
	if width == 0:
		return 0.0  # bare: no map
	var fx := (lon_deg + 180.0) / 360.0 * width - 0.5
	var fy := (90.0 - lat_deg) / 180.0 * height - 0.5
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - x0
	var ty := fy - y0
	var top := lerpf(pixel(x0, y0), pixel(x0 + 1, y0), tx)
	var bottom := lerpf(pixel(x0, y0 + 1), pixel(x0 + 1, y0 + 1), tx)
	return lerpf(top, bottom, ty)


## Height (m) of the ground along a unit body-fixed direction (x towards the
## prime meridian on the equator, z north): the map and the fine detail.
func height_at(dir: Vector3) -> float:
	var lat := rad_to_deg(asin(clampf(dir.z, -1.0, 1.0)))
	var lon := rad_to_deg(atan2(dir.y, dir.x))
	var p := dir * (radius_m / DETAIL_SCALE_M)
	return mapped_height(lat, lon) + DETAIL_M * _noise.get_noise_3d(p.x, p.y, p.z)
