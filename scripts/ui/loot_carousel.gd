class_name LootCarousel
extends PanelContainer
## Loot unboxing: its own window in the middle of the screen. What the
## salvage paid first, then each crate is opened on a horizontal carousel
## that spins and slows to a stop on what was inside (a part in its rarity
## colour, or EMPTY). Found loot is listed below as it lands, then the pity
## countdown and the published odds. G closes it (a first G during the spin
## shows everything at once). Built in code; Main opens it.

## Seconds a crate spins, and the pause on its result.
const SPIN_S := 1.8
const HOLD_S := 0.45
const CARD_W := 112.0
const CARD_H := 120.0
const CARD_GAP := 8.0
## Cards on a strip; the result sits at RESULT_INDEX.
const STRIP_CARDS := 44
const RESULT_INDEX := 38

var _title: Label
var _lines: RichTextLabel
var _strip: Control
var _found: RichTextLabel
var _footer: RichTextLabel
var _crates: Array = []
var _strips: Array = []  # per crate: Array of {name, rarity} (rarity -1 = EMPTY)
var _landing: PackedFloat32Array = PackedFloat32Array()
var _current := 0
var _clock := 0.0
var _done := false
var _footer_text := ""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", CyberTheme.panel(CyberTheme.AMBER, CyberTheme.SPACE_L, 0.97))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	_title.add_theme_color_override("font_color", CyberTheme.AMBER)
	_title.add_theme_font_size_override("font_size", 18)
	box.add_child(_title)
	_lines = _rich()
	box.add_child(_lines)
	_strip = Control.new()
	_strip.custom_minimum_size = Vector2(CARD_W * 6.0 + CARD_GAP * 5.0, CARD_H + 30.0)
	_strip.clip_contents = true
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.draw.connect(_draw_strip)
	box.add_child(_strip)
	_found = _rich()
	box.add_child(_found)
	_footer = _rich()
	box.add_child(_footer)


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(CARD_W * 6.0 + CARD_GAP * 5.0, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_color_override("default_color", CyberTheme.TEXT)
	return r


## Open the window: `crates` holds a LootRoller.Drop per crate (null = empty).
func show_rewards(title: String, lines: PackedStringArray, crates: Array, profile: PlayerProfile) -> void:
	_title.text = "◆ " + title
	_lines.text = "\n".join(lines)
	_crates = crates
	_rng.seed = hash(title) + crates.size()
	_build_strips(LootRoller.build_pool(ConstructionCatalog.default_catalog()))
	var pity := profile.pity_countdown()
	_footer_text = "\n".join([
		"Credits [color=#%s]%d[/color]  ·  Rare+ guaranteed in %d crates with loot  ·  Legendary in %d" % [
			CyberTheme.AMBER.to_html(false), profile.credits, pity.x, pity.y],
		"[color=#%s]Rates %s[/color]" % [CyberTheme.TEXT_DIM.to_html(false), LootRoller.rates_text()],
		"[color=#%s][G] close — the post-combat log lists everything found[/color]" % CyberTheme.TEXT_DIM.to_html(false),
	])
	_footer.text = ""
	_current = 0
	_clock = 0.0
	_done = crates.is_empty()
	visible = true
	_render_found()
	if _done:
		_footer.text = _footer_text


func revealed_all() -> bool:
	return _done


## First press during the spin: land everything at once. Then close.
func close() -> void:
	if not _done:
		_current = _crates.size()
		_done = true
		_render_found()
		_footer.text = _footer_text
		_strip.queue_redraw()
		return
	visible = false


## Plain text of the window (tests).
func text() -> String:
	return "\n".join([_title.text, _lines.get_parsed_text(), _found.get_parsed_text(), _footer.get_parsed_text()])


func _build_strips(pool: Array[LootRoller.Drop]) -> void:
	_strips = []
	_landing = PackedFloat32Array()
	for d in _crates:
		var strip := []
		for k in STRIP_CARDS:
			if k == RESULT_INDEX:
				strip.append(_card_for(d))
			elif _rng.randf() < 0.3:
				strip.append({"name": "EMPTY", "rarity": -1})
			else:
				var tier := LootRoller.roll_tier(_rng)
				strip.append(_card_for(LootRoller.pick(_rng, pool, tier)))
		_strips.append(strip)
		# Stop anywhere on the result card, not always dead centre.
		_landing.append(RESULT_INDEX + _rng.randf_range(-0.35, 0.35))


static func _card_for(d: LootRoller.Drop) -> Dictionary:
	if d == null:
		return {"name": "EMPTY", "rarity": -1}
	var name := d.display_name if d.kind != &"spares" else "%d spare parts" % d.amount
	if d.kind == &"room" or d.kind == &"hull":
		name += " (blueprint)"
	return {"name": name, "rarity": d.rarity}


func _process(delta: float) -> void:
	if not visible or _done:
		return
	_clock += delta
	if _clock >= SPIN_S + HOLD_S:
		_clock = 0.0
		_current += 1
		_render_found()
		if _current >= _crates.size():
			_done = true
			_footer.text = _footer_text
	_strip.queue_redraw()


## Strip position in cards: ease-out cubic to the landing point.
func _position() -> float:
	if _current >= _crates.size():
		return _landing[_landing.size() - 1] if not _landing.is_empty() else 0.0
	var t := clampf(_clock / SPIN_S, 0.0, 1.0)
	return _landing[_current] * (1.0 - pow(1.0 - t, 3.0))


func _render_found() -> void:
	# Found loot one per line; empty crates summed on one line.
	var lines := PackedStringArray()
	var shown := mini(_current, _crates.size())
	var empty := 0
	for i in shown:
		var d: LootRoller.Drop = _crates[i]
		if d == null:
			empty += 1
			continue
		var mark := "◆" if d.rarity >= Rarity.Tier.EPIC else "◇"
		lines.append("[color=#%s]%s %s  %s[/color]" % [Rarity.color_of(d.rarity).to_html(false), mark,
			Rarity.name_of(d.rarity).to_upper(), d.describe()])
	if empty > 0:
		lines.append("[color=#%s]○ %d empty crate%s[/color]" % [CyberTheme.TEXT_FAINT.to_html(false), empty, "" if empty == 1 else "s"])
	if shown < _crates.size():
		lines.append("[color=#%s]▒ crate %d of %d — opening…[/color]" % [CyberTheme.TEXT_DIM.to_html(false), shown + 1, _crates.size()])
	_found.text = "\n".join(lines)


func _draw_strip() -> void:
	var w := _strip.size.x
	var h := _strip.size.y
	_strip.draw_rect(Rect2(Vector2.ZERO, _strip.size), CyberTheme.BG * Color(1, 1, 1, 0.9))
	if _strips.is_empty():
		_strip.draw_string(ThemeDB.fallback_font, Vector2(12, h * 0.5), "No crates.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CyberTheme.TEXT_DIM)
		return
	var crate := mini(_current, _strips.size() - 1)
	var strip: Array = _strips[crate]
	var pos := _position()
	var pitch := CARD_W + CARD_GAP
	var center := w * 0.5
	var font := CyberTheme.sans()
	var landed := _current >= _crates.size() or _clock >= SPIN_S
	for k in strip.size():
		var x := center + (k - pos) * pitch - CARD_W * 0.5
		if x > w or x + CARD_W < 0.0:
			continue
		var card: Dictionary = strip[k]
		var rarity: int = card.rarity
		var col := Rarity.color_of(rarity) if rarity >= 0 else CyberTheme.TEXT_FAINT
		var r := Rect2(x, 14.0, CARD_W, CARD_H)
		var win := landed and k == RESULT_INDEX
		_strip.draw_rect(r, CyberTheme.SURFACE)
		_strip.draw_rect(Rect2(r.position, Vector2(CARD_W, 5.0)), col)
		_strip.draw_rect(r, col * Color(1, 1, 1, 1.0 if win else 0.45), false, 2.0 if win else 1.0)
		var tier_text := Rarity.name_of(rarity).to_upper() if rarity >= 0 else "—"
		_strip.draw_string(font, r.position + Vector2(8, 24), tier_text, HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 16, 10, col)
		_strip.draw_multiline_string(font, r.position + Vector2(8, 44), str(card.name), HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 16, 13, 4,
			CyberTheme.TEXT if rarity >= 0 else CyberTheme.TEXT_FAINT)
	# The pointer: amber ticks above and below the centre.
	var a := CyberTheme.AMBER
	_strip.draw_colored_polygon(PackedVector2Array([Vector2(center - 8, 0), Vector2(center + 8, 0), Vector2(center, 12)]), a)
	_strip.draw_colored_polygon(PackedVector2Array([Vector2(center - 8, h), Vector2(center + 8, h), Vector2(center, h - 12)]), a)
	_strip.draw_line(Vector2(center, 12), Vector2(center, h - 12), a * Color(1, 1, 1, 0.35), 1.0)
	_strip.draw_string(font, Vector2(8, h - 4), "CRATE %d / %d" % [crate + 1, _strips.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, CyberTheme.TEXT_DIM)
