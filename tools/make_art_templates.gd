extends SceneTree
## Templates for your own art (CustomAssets), written to art_templates/
## (Godot ignores the folder):
## - textures/<slot>_base.png — the game's texture today, at a good size to
##   paint over (tiling: what leaves one edge comes back on the other);
## - textures/<slot>_guide.png — a transparent overlay of tile edges, the
##   metre grid and notes: put it on a layer above, hide it before saving;
## - models/<part id>.png — each external part as the game builds it today,
##   from above, the side and the bow, on a 1 m grid (bold: 3 m cells), with
##   its origin and axes: model to that;
## - manifest.json — the slots and parts, for the spreadsheet
##   (art_templates/custom_assets.xlsx).
## Needs a display (it renders):
##   godot --path . -s res://tools/make_art_templates.gd

const OUT := "res://art_templates/"
const PANEL := 560
const TEAL := Color(0.0, 0.83, 0.78)
const GOLD := Color(0.96, 0.78, 0.26)
const BG := Color(0.02, 0.02, 0.03)

var cat: ConstructionCatalog


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	cat = ConstructionCatalog.default_catalog()
	CustomAssets.dir = "res://art_templates/none/"  # the game's own, not yours
	CustomAssets.reset()
	for sub in ["", "textures", "models"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + sub))
	var ignore := FileAccess.open(OUT + ".gdignore", FileAccess.WRITE)
	ignore.close()
	var textures := []
	for row: Array in CustomAssets.TEXTURE_SLOTS:
		textures.append(await _texture(row))
	var parts := []
	var ids: Array = cat.equipment.keys()
	ids.sort()
	for id: StringName in ids:
		var def: EquipmentDefinition = cat.equipment[id]
		if def.is_external():
			parts.append(await _part(def))
	var audio := []
	for row: Array in CustomAssets.AUDIO_SLOTS:
		audio.append({"slot": row[0], "kind": row[1], "when": row[2], "length": row[3], "now": row[4]})
	var f := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"audio": audio, "textures": textures, "parts": parts}, "  "))
	f.close()
	print("art templates: %d textures, %d parts" % [textures.size(), parts.size()])
	quit()


# --- Textures -------------------------------------------------------------------

func _texture(row: Array) -> Dictionary:
	var slot: String = row[0]
	var size: int = row[4]
	var base := _base_image(slot, size)
	base.save_png(OUT + "textures/%s_base.png" % slot)
	var guide := await _render_2d(Vector2i(size, size), Color(0, 0, 0, 0), func(c: Control) -> void: _draw_guide(c, row))
	guide.save_png(OUT + "textures/%s_guide.png" % slot)
	return {"slot": slot, "where": row[1], "tile": row[2], "tinted": row[3], "size": size,
		"base": "art_templates/textures/%s_base.png" % slot, "guide": "art_templates/textures/%s_guide.png" % slot}


## The game's texture today, scaled up (nearest) to `size`; a plain light
## grey where there is none.
func _base_image(slot: String, size: int) -> Image:
	var src: Image
	match slot:
		"hull_plates", "armour_plates":
			src = ShipModelBuilder.plates_image_texture().get_image()
		"hazard_stripes":
			src = ShipModelBuilder.hazard_image_texture().get_image()
		"gangway_ribs":
			src = GangwayView.rib_image_texture().get_image()
		_:
			src = Image.create(8, 8, false, Image.FORMAT_RGB8)
			src.fill(Color(0.85, 0.85, 0.85))
	src = src.duplicate()
	src.clear_mipmaps()
	src.resize(size, size, Image.INTERPOLATE_NEAREST)
	return src


func _draw_guide(c: Control, row: Array) -> void:
	var slot: String = row[0]
	var n: float = row[4]
	var font := ThemeDB.fallback_font
	var fs := maxi(int(n / 40.0), 11)
	# Tile edges (they meet the opposite edge).
	c.draw_rect(Rect2(1, 1, n - 2, n - 2), TEAL, false, 2.0)
	var steps := 0
	match slot:
		"hull_plates":
			steps = 4  # 3 m panels in a 12 m tile
		"armour_plates":
			steps = 1
		"part_surface":
			steps = 2  # 1 m in a 2 m tile
		"gangway_ribs":
			steps = 0
	for k in range(1, steps):
		var at := n * k / steps
		c.draw_line(Vector2(at, 0), Vector2(at, n), GOLD, 2.0)
		c.draw_line(Vector2(0, at), Vector2(n, at), GOLD, 2.0)
	if slot == "gangway_ribs":
		c.draw_rect(Rect2(0, 0, n, n / 8.0), Color(GOLD, 0.35))
		c.draw_string(font, Vector2(8, n / 8.0 + fs + 4), "the rib: one per tile, every 2 m along the tube (down the image)", HORIZONTAL_ALIGNMENT_LEFT, n - 16, fs, GOLD)
	if slot == "armour_plates":
		var bevel := n * 0.08
		c.draw_rect(Rect2(bevel, bevel, n - 2 * bevel, n - 2 * bevel), GOLD, false, 2.0)
	var lines := PackedStringArray([slot, String(row[2]), "tinted: " + String(row[3]), "tiles: left meets right, top meets bottom",
		"save as data/custom/textures/%s.png" % slot])
	if slot == "hull_plates":
		lines.append("gold lines: the 3 m cell panels")
	if slot == "armour_plates":
		lines.append("gold frame: keep the plate's edge in it")
	var y := n * 0.5 - lines.size() * (fs + 4) * 0.5
	for line in lines:
		var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_rect(Rect2(n * 0.5 - w * 0.5 - 4, y - fs, w + 8, fs + 6), Color(0, 0, 0, 0.85))
		c.draw_string(font, Vector2(n * 0.5 - w * 0.5, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEAL if line == slot else Color.WHITE)
		y += fs + 6


# --- Part reference sheets ------------------------------------------------------

## The part on the top face of a slab of hull (big enough for its patch or
## run), built as the game does; three orthographic views.
func _part(def: EquipmentDefinition) -> Dictionary:
	var bp := ShipBlueprint.new()
	bp.name = String(def.id)
	var span := maxi(def.size_cells, 1)
	var run := maxi(def.length_cells, 1)
	for x in maxi(span, 3):
		for z in maxi(maxi(span, run), 3):
			bp.add_module(&"hull_block_1x1", Vector3i(x, 0, z))
	var e := bp.add_equipment(def.id, Vector3i(0, 0, 0), &"dorsal", 0)
	var grid := ShipGrid.build(bp, cat)
	var model := ShipModelBuilder.build(bp, grid, Vector3.ZERO)
	for light in model.nav_lights:
		light.visible = false  # the slab's running lights: not the part
	var i := bp.equipment.find(e)
	var origin := grid.equipment_position_m(i)
	var node: Node3D = model.parts[e.id]
	var box := _aabb(node)
	var reach := maxf(maxf(box.size.x, box.size.z), box.size.y) + 3.0
	reach = maxf(reach, 8.0)
	var centre := box.get_center()
	var views := [
		["from above (bow up the page)", Vector3(0, 1, 0), Vector3(0, 0, -1), "+x", "−z"],
		["from starboard (bow to the right)", Vector3(1, 0, 0), Vector3(0, 1, 0), "−z", "+y"],
		["from the bow (looking aft)", Vector3(0, 0, -1), Vector3(0, 1, 0), "−x", "+y"],
	]
	var sheet := Image.create(PANEL * 3, PANEL + 70, false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	for k in views.size():
		var v: Array = views[k]
		var img := await _render_part(model.root, centre, reach, v, origin, def)
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(PANEL * k, 70))
	var head := await _render_2d(Vector2i(PANEL * 3, 70), BG, func(c: Control) -> void:
		var font := ThemeDB.fallback_font
		c.draw_string(font, Vector2(16, 30), "%s — %s" % [def.display_name, def.id], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, TEAL)
		c.draw_string(font, Vector2(16, 56), "%s · covers %d × %d face%s%s · save as data/custom/models/%s.glb (metres, real size; origin = gold cross)%s" % [
			["light", "medium", "large"][span - 1], span, span * run if run > 1 else span, "" if span * span * run == 1 else "s",
			"" if run == 1 else " (runs %d cells along Z)" % run, def.id,
			" · head: %s_turret.glb on the pivot (teal cross), barrel along −Z" % def.id if _has_pivot(node) else ""],
			HORIZONTAL_ALIGNMENT_LEFT, PANEL * 3 - 32, 15, Color.WHITE))
	head.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(head, Rect2i(Vector2i.ZERO, head.get_size()), Vector2i.ZERO)
	sheet.save_png(OUT + "models/%s.png" % def.id)
	var moving := []
	for child in node.get_children():
		if not (child is MeshInstance3D and child.get_child_count() == 0):
			moving.append(String(child.name))
	var turret := _has_pivot(node)
	model.root.free()
	return {"id": String(def.id), "name": def.display_name, "kind": EquipmentDefinition.Kind.keys()[def.kind].to_lower(),
		"tier": ["light", "medium", "large"][span - 1], "covers": "%d × %d" % [span, span * run], "length_cells": run,
		"rarity": Rarity.Tier.keys()[def.rarity].to_lower(), "turret": turret, "kept": moving,
		"reference": "art_templates/models/%s.png" % def.id, "size_m": [snappedf(box.size.x, 0.1), snappedf(box.size.y, 0.1), snappedf(box.size.z, 0.1)]}


func _has_pivot(node: Node3D) -> bool:
	return node.get_node_or_null("TurretPivot") != null or node.get_node_or_null("PdPivot") != null


func _aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var t := _to_root(mi)
		var b := t * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _to_root(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p is Node3D and p.get_parent() != null and (p as Node3D).name != "ShipModel":
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _render_part(model_root: Node3D, centre: Vector3, reach: float, view: Array, origin: Vector3, def: EquipmentDefinition) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(PANEL, PANEL)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.3
	vp.add_child(light)
	light.look_at_from_position(Vector3.ZERO, Vector3(-0.4, -1.0, -0.6), Vector3.UP)
	var copy := model_root.duplicate() as Node3D
	vp.add_child(copy)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = reach
	vp.add_child(cam)
	var dir: Vector3 = view[1]
	cam.look_at_from_position(centre + dir * 60.0, centre, view[2])
	cam.make_current()
	# Grid and labels over the render: metres on the view's axes.
	var overlay := Control.new()
	overlay.size = Vector2(PANEL, PANEL)
	vp.add_child(overlay)
	var to_px := func(p: Vector3) -> Vector2:
		var local := cam.global_transform.affine_inverse() * p
		return Vector2(PANEL * 0.5 + local.x / reach * PANEL, PANEL * 0.5 - local.y / reach * PANEL)
	overlay.draw.connect(func() -> void:
		var right := cam.global_transform.basis.x
		var up := cam.global_transform.basis.y
		var lo := -ceilf(reach)
		for k in range(int(lo) - 3, int(-lo) + 4):
			for axis in [right, up]:
				var other: Vector3 = up if axis == right else right
				var along := float(k)
				var base_w := (axis as Vector3) * (snappedf((centre.dot(axis)), 1.0) + along)
				var w := base_w + other * centre.dot(other)
				var p: Vector2 = to_px.call(w)
				var bold := posmod(int(roundf(w.dot(axis))), 3) == 0
				var col := Color(GOLD, 0.45) if bold else Color(1, 1, 1, 0.08)
				if axis == right:
					overlay.draw_line(Vector2(p.x, 0), Vector2(p.x, PANEL), col, 1.0)
				else:
					overlay.draw_line(Vector2(0, p.y), Vector2(PANEL, p.y), col, 1.0)
		var o: Vector2 = to_px.call(origin)
		overlay.draw_line(o + Vector2(-10, 0), o + Vector2(10, 0), GOLD, 2.0)
		overlay.draw_line(o + Vector2(0, -10), o + Vector2(0, 10), GOLD, 2.0)
		var font := ThemeDB.fallback_font
		overlay.draw_string(font, Vector2(12, 24), String(view[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		overlay.draw_string(font, Vector2(12, PANEL - 14), "grid 1 m · gold 3 m (a cell) · → %s  ↑ %s" % [view[3], view[4]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8)))
	for p in copy.find_children("TurretPivot", "Node3D", true, false) + copy.find_children("PdPivot", "Node3D", true, false):
		var pv := p as Node3D
		overlay.draw.connect(func() -> void:
			var q: Vector2 = to_px.call(_to_root(pv).origin)
			overlay.draw_line(q + Vector2(-8, -8), q + Vector2(8, 8), TEAL, 2.0)
			overlay.draw_line(q + Vector2(-8, 8), q + Vector2(8, -8), TEAL, 2.0))
	overlay.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


func _render_2d(size: Vector2i, bg: Color, painter: Callable) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = bg.a < 1.0
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var back := ColorRect.new()
	back.color = bg
	back.size = Vector2(size)
	vp.add_child(back)
	var c := Control.new()
	c.size = Vector2(size)
	vp.add_child(c)
	c.draw.connect(func() -> void: painter.call(c))
	c.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img
