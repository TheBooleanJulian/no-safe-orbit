class_name DealerShots
extends RefCounted
## The ship dealer's catalogue pictures (play-test batch 11: the dealer was
## slow to open, building a 3D view per card). A card's view is rendered
## once, decorated — a vignette, a faint grid, corner brackets in the card's
## accent — and kept on disk, keyed by the template's MD5; from then on the
## card shows the picture and builds no 3D view at all. A changed template
## (or a new STYLE) gets a new picture; the old one is removed.

## Where the pictures are kept (tests point it elsewhere).
static var dir := "user://dealer_shots"
## Bump to re-render every picture in a new look.
const STYLE := 1
const GRID_PX := 24


## The picture's file for `template` (a blueprint path).
static func path_for(template: String) -> String:
	var key := ("%s|%d" % [FileAccess.get_md5(template), STYLE]).md5_text().left(12)
	return "%s/%s_%s.png" % [dir, template.get_file().get_basename(), key]


## The saved picture for `template`, or null if there is none yet.
static func load_shot(template: String) -> Texture2D:
	var p := path_for(template)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## Whether a rendered view shows a ship: enough pixels well above the
## dark backdrop (a frame drawn too early is empty).
static func has_subject(img: Image) -> bool:
	if img == null or img.is_empty():
		return false
	var lit := 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			if img.get_pixel(x, y).get_luminance() > 0.12:
				lit += 1
	return lit >= 20


## Decorate a rendered view and keep it for `template`; its texture.
static func save_shot(template: String, img: Image, accent: Color) -> Texture2D:
	decorate(img, accent)
	DirAccess.make_dir_recursive_absolute(dir)
	var p := path_for(template)
	# An older picture of the same template is stale now.
	var stem := template.get_file().get_basename() + "_"
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(stem) and f.length() == stem.length() + 16 and dir.path_join(f) != p:
			DirAccess.remove_absolute(dir.path_join(f))
	img.save_png(p)
	return ImageTexture.create_from_image(img)


## The catalogue look, in place: darker towards the edges, a faint grid in
## the accent, a shaded foot for the caption, accent brackets at the corners.
static func decorate(img: Image, accent: Color) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var half := Vector2(w, h) * 0.5
	for y in h:
		var foot := clampf((y - h * 0.78) / (h * 0.22), 0.0, 1.0)
		for x in w:
			var c := img.get_pixel(x, y)
			var shade := clampf(1.0 - 0.4 * ((Vector2(x, y) - half) / half).length_squared(), 0.0, 1.0) * (1.0 - 0.45 * foot)
			c = Color(c.r * shade, c.g * shade, c.b * shade, 1.0)
			if x % GRID_PX == 0 or y % GRID_PX == 0:
				c = c.lerp(accent, 0.07)
			img.set_pixel(x, y, c)
	var arm := maxi(mini(w, h) / 7, 4)
	var t := 2
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(w - arm, 0), Vector2i(0, h - t), Vector2i(w - arm, h - t)]:
		img.fill_rect(Rect2i(corner, Vector2i(arm, t)), accent)
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(w - t, 0), Vector2i(0, h - arm), Vector2i(w - t, h - arm)]:
		img.fill_rect(Rect2i(corner, Vector2i(t, arm)), accent)
