class_name ShipBlueprint
extends RefCounted
## A reusable ship design (spec §4, §6): hull modules on a 3D cell grid,
## rooms on decks, hatches between rooms, and installed equipment. Pure data;
## ShipGrid, ShipValidator and ShipStats derive everything else from it.
## Saved as versioned JSON by BlueprintIO.
##
## Cells are Vector3i(x, deck, z): +x starboard, +deck up, +z aft, so the
## nose is at low z, matching the body frame's −Z forward.

const SCHEMA_VERSION := 1


class PlacedModule:
	var id: String
	var def_id: StringName
	## Minimum corner cell of the (rotated) module box.
	var position: Vector3i
	## Quarter turns about +Y, counter-clockwise seen from above (0–3).
	var rotation: int


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


var name: String = "Unnamed design"
var designer: String = ""
var modules: Array[PlacedModule] = []
var rooms: Array[PlacedRoom] = []
var hatches: Array[Hatch] = []
var equipment: Array[PlacedEquipment] = []
var _next_id: int = 1


func add_module(def_id: StringName, position: Vector3i, rotation: int = 0) -> PlacedModule:
	var m := PlacedModule.new()
	m.id = _new_id("m")
	m.def_id = def_id
	m.position = position
	m.rotation = posmod(rotation, 4)
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


func add_equipment(def_id: StringName, cell: Vector3i, face: StringName = &"") -> PlacedEquipment:
	var e := PlacedEquipment.new()
	e.id = _new_id("e")
	e.def_id = def_id
	e.cell = cell
	e.face = face
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
		d.modules.append({"id": m.id, "def": String(m.def_id), "pos": _v3(m.position), "rot": m.rotation})
	for r in rooms:
		d.rooms.append({"id": r.id, "def": String(r.def_id), "deck": r.deck,
			"rect": [r.rect.position.x, r.rect.position.y, r.rect.size.x, r.rect.size.y]})
	for h in hatches:
		d.hatches.append({"id": h.id, "a": _v3(h.a), "b": _v3(h.b)})
	for e in equipment:
		var ed := {"id": e.id, "def": String(e.def_id), "cell": _v3(e.cell)}
		if e.face != &"":
			ed["face"] = String(e.face)
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
	# Older versions would be migrated here; v1 is the first.
	var bp := ShipBlueprint.new()
	bp.name = str(d.get("name", "Unnamed design"))
	bp.designer = str(d.get("designer", ""))
	for md in _list(d, "modules", errors):
		var m := PlacedModule.new()
		m.id = str(md.get("id", ""))
		m.def_id = StringName(str(md.get("def", "")))
		m.position = _to_v3(md.get("pos"), errors, "module %s pos" % m.id)
		m.rotation = posmod(int(md.get("rot", 0)), 4)
		bp.modules.append(m)
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
