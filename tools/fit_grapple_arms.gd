extends SceneTree
## One-off (play-test batch 9): the grappling arm grew to four cells along
## the hull. Refit it on the templates where it no longer fits: the first
## spot (its own face first, then the others; along, then across) where the
## design validates with no new error, then re-route the power bus.
##   godot --headless --path . -s res://tools/fit_grapple_arms.gd

func _initialize() -> void:
	var cat := ConstructionCatalog.default_catalog()
	for name in ["frigate_mk1", "corvette_mk1", "cutter_mk1"]:
		var path := "res://data/blueprints/%s.json" % name
		var bp := BlueprintIO.load_file(path, PackedStringArray())
		var arm: ShipBlueprint.PlacedEquipment = null
		for e in bp.equipment:
			if e.def_id == &"grapple_arm":
				arm = e
		if arm == null:
			continue
		var before := ShipValidator.validate(bp, cat)
		if not before.has_errors() and before.warnings().is_empty():
			print("%s: the arm fits" % name)
			continue
		var grid := ShipGrid.build(bp, cat)
		var cells: Array = grid.module_at.keys()
		cells.sort()
		var faces: Array[StringName] = [arm.face]
		for f: StringName in [&"port", &"starboard", &"dorsal", &"ventral", &"fore"]:
			if not faces.has(f):
				faces.append(f)
		var placed := false
		for face in faces:
			for rot in [0, 1]:
				for cell: Vector3i in cells:
					arm.cell = cell
					arm.face = face
					arm.rotation = rot
					if not ShipValidator.validate(bp, cat).has_errors():
						placed = true
						break
				if placed:
					break
			if placed:
				break
		if not placed:
			print("%s: NO SPOT" % name)
			continue
		if not bp.bus.is_empty():
			ShipEditor.new(bp, cat).auto_route_bus()
		var after := ShipValidator.validate(bp, cat)
		print("%s: arm on the %s face at %s (rotation %d) — %s" % [name, arm.face, arm.cell, arm.rotation, after.summary() if not after.issues.is_empty() else "clean"])
		if not after.has_errors():
			BlueprintIO.save(bp, path)
	quit()
