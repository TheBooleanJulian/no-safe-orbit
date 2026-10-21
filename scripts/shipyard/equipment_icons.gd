class_name EquipmentIcons
extends RefCounted
## A shape for each kind of part (play-test batch 11). Parts of one family
## share a colour — the palette text and the placed cells alike — and the
## shape tells them apart: a kinetic gun's triangle, a laser's star, a
## fighter's chevron, a drone's diamond, a missile's arrow and so on. Drawn
## in the palette (an icon in the part's rarity colour) and on the deck.

const ICON_PX := 16

static var _icons: Dictionary = {}


## The shape (in a −1…1 square, y down) for `def`.
static func shape(def: EquipmentDefinition) -> PackedVector2Array:
	var K := EquipmentDefinition.Kind
	match def.kind:
		K.CANNON:
			if def.cannon != null and def.cannon.is_beam():
				return _star(4, 1.0, 0.38)
			return PackedVector2Array([Vector2(0, -1), Vector2(0.9, 0.8), Vector2(-0.9, 0.8)])
		K.POINT_DEFENCE:
			return _circle(5, 0.85)
		K.MISSILE_LAUNCHER:
			return PackedVector2Array([Vector2(0, -1), Vector2(0.65, -0.05), Vector2(0.25, -0.05), Vector2(0.25, 1),
				Vector2(-0.25, 1), Vector2(-0.25, -0.05), Vector2(-0.65, -0.05)])
		K.DECOY_LAUNCHER:
			return PackedVector2Array([Vector2(-0.3, -1), Vector2(0.3, -1), Vector2(0.3, -0.3), Vector2(1, -0.3), Vector2(1, 0.3),
				Vector2(0.3, 0.3), Vector2(0.3, 1), Vector2(-0.3, 1), Vector2(-0.3, 0.3), Vector2(-1, 0.3), Vector2(-1, -0.3), Vector2(-0.3, -0.3)])
		K.JAMMER:
			return PackedVector2Array([Vector2(-1, -0.8), Vector2(0, 0), Vector2(-1, 0.8), Vector2(1, 0.8), Vector2(0, 0), Vector2(1, -0.8)])
		K.CRAFT_MOUNT:
			if CrewRoster.needs_pilot(def):  # a piloted fighter; drones fly themselves
				return PackedVector2Array([Vector2(0, -1), Vector2(1, 0.85), Vector2(0, 0.35), Vector2(-1, 0.85)])
			return PackedVector2Array([Vector2(0, -1), Vector2(0.75, 0), Vector2(0, 1), Vector2(-0.75, 0)])
		K.MAIN_ENGINE:
			return PackedVector2Array([Vector2(-0.4, -1), Vector2(0.4, -1), Vector2(0.95, 1), Vector2(-0.95, 1)])
		K.RCS:
			return PackedVector2Array([Vector2(-0.6, -0.6), Vector2(0.6, -0.6), Vector2(0.6, 0.6), Vector2(-0.6, 0.6)])
		K.REACTOR:
			return _circle(6, 0.95)
		K.PROPELLANT_TANK:
			return _circle(12, 0.85)
		K.RADIATOR:
			return PackedVector2Array([Vector2(-0.35, -1), Vector2(0.35, -1), Vector2(0.35, 1), Vector2(-0.35, 1)])
		K.SENSOR:
			return _star(8, 1.0, 0.55)
		K.POWER_DISTRIBUTION:
			return PackedVector2Array([Vector2(0.2, -1), Vector2(-0.6, 0.15), Vector2(-0.05, 0.15), Vector2(-0.3, 1), Vector2(0.6, -0.2),
				Vector2(0.05, -0.2)])
		K.GRAPPLE:
			return PackedVector2Array([Vector2(-1, -1), Vector2(-0.45, -1), Vector2(0, 0.2), Vector2(0.45, -1), Vector2(1, -1), Vector2(0.2, 1),
				Vector2(-0.2, 1)])
		K.DOCKING_COLLAR:
			return _circle(8, 0.95)
	return _circle(4, 0.8)


## A palette icon: the shape filled in `color` (cached).
static func icon(def: EquipmentDefinition, color: Color) -> ImageTexture:
	var key := "%s|%s" % [def.id, color.to_html()]
	if _icons.has(key):
		return _icons[key]
	var poly := shape(def)
	var img := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
	for y in ICON_PX:
		for x in ICON_PX:
			var p := Vector2((x + 0.5) / ICON_PX * 2.0 - 1.0, (y + 0.5) / ICON_PX * 2.0 - 1.0)
			if Geometry2D.is_point_in_polygon(p * 1.05, poly):
				img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


## Draw the shape at `center`, `radius` px, filled (or outlined).
static func draw(canvas: CanvasItem, def: EquipmentDefinition, center: Vector2, radius: float, color: Color, filled: bool = true) -> void:
	var pts := PackedVector2Array()
	for p in shape(def):
		pts.append(center + p * radius)
	if filled:
		canvas.draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		canvas.draw_polyline(pts, color, 2.0)


static func _circle(n: int, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		var a := TAU * k / n - PI * 0.5
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


static func _star(points: int, outer: float, inner: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in points * 2:
		var a := PI * k / points - PI * 0.5
		out.append(Vector2(cos(a), sin(a)) * (outer if k % 2 == 0 else inner))
	return out
