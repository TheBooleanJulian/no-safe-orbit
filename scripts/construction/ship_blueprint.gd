class_name ShipBlueprint
extends RefCounted
## A reusable ship design (spec §4, §6): hull modules on a 3D cell grid,
## rooms on decks, hatches between rooms, and installed equipment. Pure data;
## ShipGrid, ShipValidator and ShipStats derive everything else from it.
## Saved as versioned JSON by BlueprintIO.
##
## Cells are Vector3i(x, deck, z): +x starboard, +deck up, +z aft, so the
## nose is at low z, matching the body frame's −Z forward.

## v2: modules may be flipped; painted armour plates; power bus cells.
const SCHEMA_VERSION := 2
## Armour plate thicknesses the yard fits (mm).
const PLATE_THIN_MM := 40
const PLATE_THICK_MM := 80


class PlacedModule:
	var id: String
	var def_id: StringName
	## Minimum corner cell of the (rotated) module box.
	var position: Vector3i
	## Quarter turns about +Y, counter-clockwise seen from above (0–3).
	var rotation: int
	## Upside down (a wedge's slope faces down instead of up).
	var flip: bool = false


class PlacedRoom:
	var id: String
	var def_id: StringName
	var deck: int
	## x, z, width, depth in cells.
	var rect: Rect2i


class Hatch:
	var id: String
	## The two cells it joins: horizontal neighbours (door) or vertical (ladder).
	var a: Vector3i
	var b: Vector3i


class PlacedEquipment:
	var id: String
	var def_id: StringName
	## Internal: min corner of the footprint. External: the hull cell it is on.
	var cell: Vector3i
	## External only: the face of `cell` it is mounted on; "" when internal.
	var face: StringName = &""
	## Internal only: quarter turns of the footprint about +Y (0–3).
	var rotation: int = 0


var name: String = "Unnamed design"
var designer: String = ""
var modules: Array[PlacedModule] = []
var rooms: Array[PlacedRoom] = []
var hatches: Array[Hatch] = []
var equipment: Array[PlacedEquipment] = []
## Armour plates on exterior hull faces: plate_key(cell, face) -> mm.
var armor: Dictionary = {}
## Power bus conduit cells (player-routed): cell_key(cell) -> true. Empty =
## automatic distribution through the hull (designs from before buses).
var bus: Dictionary = {}
var _next_id: int = 1


static func plate_key(cell: Vector3i, face: StringName) -> String:
	return "%d,%d,%d,%s" % [cell.x, cell.y, cell.z, face]


static func cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


## [cell, face] of a plate key.
static func parse_plate_key(key: String) -> Array:
	var p := key.split(",")
	return [Vector3i(int(p[0]), int(p[1]), int(p[2])), StringName(p[3])]


static func parse_cell_key(key: String) -> Vector3i:
	var p := key.split(",")
	return Vector3i(int(p[0]), int(p[1]), int(p[2]))


func add_module(def_id: StringName, position: Vector3i, rotation: int = 0, flip: bool = false) -> PlacedModule:
	var m := PlacedModule.new()
	m.id = _new_id("m")
	m.def_id = def_id
	m.position = position
	m.rotation = posmod(rotation, 4)
	m.flip = flip
	modules.append(m)
	return m


func add_room(def_id: StringName, deck: int, rect: Rect2i) -> PlacedRoom:
	var r := PlacedRoom.new()
	r.id = _new_id("r")
	r.def_id = def_id
	r.deck = deck
	r.rect = rect
	rooms.append(r)
	return r


func add_hatch(a: Vector3i, b: Vector3i) -> Hatch:
	var h := Hatch.new()
	h.id = _new_id("h")
	h.a = a
	h.b = b
	hatches.append(h)
	return h


func add_equipment(def_id: StringName, cell: Vector3i, face: StringName = &"", rotation: int = 0) -> PlacedEquipment:
	var e := PlacedEquipment.new()
	e.id = _new_id("e")
	e.def_id = def_id
	e.cell = cell
	e.face = face
	e.rotation = posmod(rotation, 4)
	equipment.append(e)
	return e


## Removes the module, room, hatch or equipment with this id.
func remove(id: String) -> bool:
	for list in [modules, rooms, hatches, equipment]:
		for i in list.size():
			if list[i].id == id:
				list.remove_at(i)
				return true
	return false


func find(id: String) -> Variant:
	for list in [modules, rooms, hatches, equipment]:
		for item in list:
			if item.id == id:
				return item
	return null


func duplicate_blueprint() -> ShipBlueprint:
	var errors := PackedStringArray()
	return ShipBlueprint.from_dict(to_dict(), errors)


func to_dict() -> Dictionary:
	var d := {
		"schema_version": SCHEMA_VERSION,
		"name": name,
		"designer": designer,
		"modules": [],
		"rooms": [],
		"hatches": [],
		"equipment": [],
	}
	for m in modules:
		var md := {"id": m.id, "def": String(m.def_id), "pos": _v3(m.position), "rot": m.rotation}
		if m.flip:
			md["flip"] = true
		d.modules.append(md)
	if not armor.is_empty():
		var plates := []
		var keys := armor.keys()
		keys.sort()
		for key in keys:
			var cf := parse_plate_key(key)
			plates.append([cf[0].x, cf[0].y, cf[0].z, String(cf[1]), int(armor[key])])
		d["armor"] = plates
	if not bus.is_empty():
		var cells := []
		var keys := bus.keys()
		keys.sort()
		for key in keys:
			var c := parse_cell_key(key)
			cells.append([c.x, c.y, c.z])
		d["bus"] = cells
	for r in rooms:
		d.rooms.append({"id": r.id, "def": String(r.def_id), "deck": r.deck,
			"rect": [r.rect.position.x, r.rect.position.y, r.rect.size.x, r.rect.size.y]})
	for h in hatches:
		d.hatches.append({"id": h.id, "a": _v3(h.a), "b": _v3(h.b)})
	for e in equipment:
		var ed := {"id": e.id, "def": String(e.def_id), "cell": _v3(e.cell)}
		if e.face != &"":
			ed["face"] = String(e.face)
		if e.rotation != 0:
			ed["rot"] = e.rotation
		d.equipment.append(ed)
	return d


## Builds a blueprint from parsed JSON. Problems are appended to `errors`;
## returns null if the data cannot be used (e.g. unsupported schema version).
static func from_dict(d: Dictionary, errors: PackedStringArray) -> ShipBlueprint:
	var version := int(d.get("schema_version", 0))
	if version <= 0:
		errors.append("Not a blueprint: missing schema_version")
		return null
	if version > SCHEMA_VERSION:
		errors.append("Blueprint schema v%d is newer than this build supports (v%d)" % [version, SCHEMA_VERSION])
		return null
	# v1 → v2: no flips, no plates, no bus (automatic distribution).
	var bp := ShipBlueprint.new()
	bp.name = str(d.get("name", "Unnamed design"))
	bp.designer = str(d.get("designer", ""))
	for md in _list(d, "modules", errors):
		var m := PlacedModule.new()
		m.id = str(md.get("id", ""))
		m.def_id = StringName(str(md.get("def", "")))
		m.position = _to_v3(md.get("pos"), errors, "module %s pos" % m.id)
		m.rotation = posmod(int(md.get("rot", 0)), 4)
		m.flip = bool(md.get("flip", false))
		bp.modules.append(m)
	for pd in d.get("armor", []):
		if pd is Array and (pd as Array).size() == 5:
			bp.armor[plate_key(Vector3i(int(pd[0]), int(pd[1]), int(pd[2])), StringName(str(pd[3])))] = int(pd[4])
		else:
			errors.append("armour plate entries must be [x, deck, z, face, mm]")
	for cd in d.get("bus", []):
		if cd is Array and (cd as Array).size() == 3:
			bp.bus[cell_key(Vector3i(int(cd[0]), int(cd[1]), int(cd[2])))] = true
		else:
			errors.append("bus entries must be [x, deck, z]")
	for rd in _list(d, "rooms", errors):
		var r := PlacedRoom.new()
		r.id = str(rd.get("id", ""))
		r.def_id = StringName(str(rd.get("def", "")))
		r.deck = int(rd.get("deck", 0))
		var rect: Array = rd.get("rect", [])
		if rect.size() != 4:
			errors.append("room %s: rect must be [x, z, width, depth]" % r.id)
			continue
		r.rect = Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
		bp.rooms.append(r)
	for hd in _list(d, "hatches", errors):
		var h := Hatch.new()
		h.id = str(hd.get("id", ""))
		h.a = _to_v3(hd.get("a"), errors, "hatch %s a" % h.id)
		h.b = _to_v3(hd.get("b"), errors, "hatch %s b" % h.id)
		bp.hatches.append(h)
	for edd in _list(d, "equipment", errors):
		var e := PlacedEquipment.new()
		e.id = str(edd.get("id", ""))
		e.def_id = StringName(str(edd.get("def", "")))
		e.cell = _to_v3(edd.get("cell"), errors, "equipment %s cell" % e.id)
		e.face = StringName(str(edd.get("face", "")))
		e.rotation = posmod(int(edd.get("rot", 0)), 4)
		bp.equipment.append(e)
	bp._reset_next_id()
	return bp


func _new_id(prefix: String) -> String:
	var id := "%s%d" % [prefix, _next_id]
	_next_id += 1
	return id


## Continue numbering after the highest numeric suffix already in use.
func _reset_next_id() -> void:
	var highest := 0
	for list in [modules, rooms, hatches, equipment]:
		for item in list:
			var digits: String = item.id.right(item.id.length() - 1)
			if digits.is_valid_int():
				highest = maxi(highest, digits.to_int())
	_next_id = highest + 1


static func _v3(v: Vector3i) -> Array:
	return [v.x, v.y, v.z]


static func _to_v3(value: Variant, errors: PackedStringArray, what: String) -> Vector3i:
	if value is Array and (value as Array).size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	errors.append("%s must be [x, deck, z]" % what)
	return Vector3i.ZERO


static func _list(d: Dictionary, key: String, errors: PackedStringArray) -> Array:
	var value: Variant = d.get(key, [])
	if value is Array:
		return (value as Array).filter(func(x: Variant) -> bool: return x is Dictionary)
	errors.append("'%s' must be a list" % key)
	return []
