class_name ConstructionCatalog
extends RefCounted
## All hull module, room and equipment definitions, keyed by id. Loaded by
## scanning data/catalog/{hull,rooms,equipment}/ so adding a part is just
## adding a .tres file.

const ROOT := "res://data/catalog"

var hull: Dictionary = {}       # StringName -> HullModuleDefinition
var rooms: Dictionary = {}      # StringName -> RoomDefinition
var equipment: Dictionary = {}  # StringName -> EquipmentDefinition

static var _default: ConstructionCatalog


## Shared catalog of the shipped data (definitions are immutable).
static func default_catalog() -> ConstructionCatalog:
	if _default == null:
		_default = ConstructionCatalog.new()
		_default._load_dir("%s/hull" % ROOT, _default.hull)
		_default._load_dir("%s/rooms" % ROOT, _default.rooms)
		_default._load_dir("%s/equipment" % ROOT, _default.equipment)
		for p in _default.validate():
			GameLog.error("catalog", p)
	return _default


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	for table in [hull, rooms, equipment]:
		for def in table.values():
			problems.append_array(def.validate())
	return problems


## Sorted ids, for stable palette order.
static func sorted_ids(table: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for k in table:
		ids.append(k)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


func _load_dir(path: String, into: Dictionary) -> void:
	for file in DirAccess.get_files_at(path):
		# Exported builds list remapped resources as "*.tres.remap".
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var res := load(path.path_join(name))
		if res == null or not ("id" in res):
			GameLog.error("catalog", "Not a definition: %s" % path.path_join(name))
			continue
		if into.has(res.id):
			GameLog.error("catalog", "Duplicate definition id '%s' in %s" % [res.id, path])
			continue
		into[res.id] = res
