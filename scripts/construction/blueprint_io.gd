class_name BlueprintIO
extends RefCounted
## Blueprint files: versioned JSON (spec §15). JSON rather than .tres so a
## shared blueprint is plain data and can never execute code on load.
## Player designs live in user://blueprints; prebuilt templates ship in
## res://data/blueprints and are read-only.

const USER_DIR := "user://blueprints"
const TEMPLATE_DIR := "res://data/blueprints"
const DEFAULT_TEMPLATE := "res://data/blueprints/frigate_mk1.json"


static func to_json(bp: ShipBlueprint) -> String:
	return JSON.stringify(bp.to_dict(), "\t", false)


static func from_json(text: String, errors: PackedStringArray) -> ShipBlueprint:
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("Invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		errors.append("Blueprint JSON must be an object")
		return null
	return ShipBlueprint.from_dict(json.data, errors)


static func save(bp: ShipBlueprint, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_json(bp))
	file.close()
	return OK


static func load_file(path: String, errors: PackedStringArray) -> ShipBlueprint:
	if not FileAccess.file_exists(path):
		errors.append("No such blueprint: %s" % path)
		return null
	var bp := from_json(FileAccess.get_file_as_string(path), errors)
	if bp != null:
		BlueprintFix.fit_spans(bp, ConstructionCatalog.default_catalog())
		BlueprintFix.prune_plates(bp, ShipGrid.build(bp, ConstructionCatalog.default_catalog()))
	return bp


## user://blueprints/<safe name>.json for a design name.
static func user_path_for(design_name: String) -> String:
	var safe := design_name.strip_edges().to_lower().validate_filename().replace(" ", "_")
	return USER_DIR.path_join((safe if safe != "" else "unnamed") + ".json")


static func list_user() -> PackedStringArray:
	return _list(USER_DIR)


static func list_templates() -> PackedStringArray:
	return _list(TEMPLATE_DIR)


static func _list(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(dir.path_join(f))
	out.sort()
	return out
