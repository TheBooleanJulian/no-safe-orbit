class_name CyberTheme
extends RefCounted
## Design tokens for every UI surface: semantic colours, type, spacing,
## panel surfaces and state glyphs. Scenes take `build_theme()`; panels built
## in code take `panel()` and `style_button()`.
##
## Semantics (never colour alone — every state also has a glyph or label):
##   CYAN     friendly ship and system information
##   MAGENTA  hostile contacts
##   AMBER    caution (degraded, estimates that matter, warnings)
##   RED      immediate danger (critical, destroyed, incoming)
## Type: sans-serif for headings and actions, monospace for telemetry and
## logs. Glow is kept off panels; accents are borders and text, not fills.

# --- Colour -------------------------------------------------------------------
const CYAN := Color(0.0, 0.94, 1.0)
const MAGENTA := Color(1.0, 0.17, 0.84)
const AMBER := Color(1.0, 0.76, 0.22)
const RED := Color(1.0, 0.3, 0.3)
const TEXT := Color(0.8, 0.95, 1.0)
const TEXT_DIM := Color(0.5, 0.62, 0.68)
const TEXT_FAINT := Color(0.36, 0.44, 0.5)
const BG := Color(0.02, 0.025, 0.045, 0.86)
const SURFACE := Color(0.035, 0.045, 0.07, 0.94)
## Border opacity for panel frames and dividers.
const BORDER_ALPHA := 0.4
# Compatibility aliases (older panels).
const WARN := AMBER
const DANGER := RED
const OK := CYAN

# --- Type ---------------------------------------------------------------------
const SANS_FAMILIES := ["Space Grotesk", "Inter", "Segoe UI", "Helvetica Neue", "Arial", "Sans-Serif"]
const MONO_FAMILIES := ["JetBrains Mono", "Cascadia Mono", "Consolas", "DejaVu Sans Mono", "Menlo", "Monospace"]
const SIZE_TITLE := 15
const SIZE_BODY := 13
const SIZE_SMALL := 11

# --- Spacing --------------------------------------------------------------------
const SPACE_XS := 4
const SPACE_S := 8
const SPACE_M := 12
const SPACE_L := 16
const RADIUS := 3

# --- State glyphs (paired with colour) ------------------------------------------
const GLYPH_OK := "■"
const GLYPH_DEGRADED := "▲"
const GLYPH_CRITICAL := "◆"
const GLYPH_DESTROYED := "✕"
const GLYPH_OFFLINE := "○"
const GLYPH_CREW := "●"

static var _sans: SystemFont
static var _mono: SystemFont
static var _theme: Theme


static func sans() -> SystemFont:
	if _sans == null:
		_sans = SystemFont.new()
		_sans.font_names = PackedStringArray(SANS_FAMILIES)
		_sans.font_weight = 500
	return _sans


static func mono() -> SystemFont:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(MONO_FAMILIES)
	return _mono


## Panel surface: dark glass, thin border at BORDER_ALPHA, a 2 px accent
## edge on the left. `accent` = MAGENTA for hostile information.
static func panel(accent: Color = CYAN, margin: float = SPACE_S, opacity: float = BG.a) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(BG.r, BG.g, BG.b, opacity)
	s.border_color = Color(accent.r, accent.g, accent.b, BORDER_ALPHA)
	s.set_border_width_all(1)
	s.border_width_left = 2
	s.set_corner_radius_all(RADIUS)
	s.set_content_margin_all(margin)
	return s


static func html(c: Color) -> String:
	return "#" + c.to_html(false)


## BBCode: text in a colour.
static func tint(text: String, c: Color) -> String:
	return "[color=%s]%s[/color]" % [html(c), text]


static func style_button(b: Button, accent: Color = CYAN, primary: bool = false) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := StyleBoxFlat.new()
		var fill := Color(accent.r, accent.g, accent.b, 0.85 if primary else 0.0)
		if state == "hover":
			fill = Color(accent.r, accent.g, accent.b, 1.0 if primary else 0.16)
		elif state == "pressed":
			fill = Color(accent.r, accent.g, accent.b, 0.6 if primary else 0.28)
		elif state == "disabled":
			fill = Color(0.1, 0.12, 0.15, 0.8) if primary else Color(0, 0, 0, 0)
		s.bg_color = Color(SURFACE.r, SURFACE.g, SURFACE.b, 0.9).blend(fill) if not primary else fill
		s.border_color = Color(accent.r, accent.g, accent.b, 0.9 if state == "focus" else (BORDER_ALPHA if state == "disabled" else 0.7))
		s.set_border_width_all(2 if state == "focus" else 1)
		s.set_corner_radius_all(RADIUS)
		s.content_margin_left = SPACE_M
		s.content_margin_right = SPACE_M
		s.content_margin_top = SPACE_XS + 1
		s.content_margin_bottom = SPACE_XS + 1
		b.add_theme_stylebox_override(state, s)
	var text := Color(0.02, 0.03, 0.05) if primary else accent
	b.add_theme_color_override("font_color", text)
	b.add_theme_color_override("font_hover_color", Color(0.02, 0.03, 0.05) if primary else Color.WHITE)
	b.add_theme_color_override("font_pressed_color", text)
	b.add_theme_color_override("font_focus_color", text)
	b.add_theme_color_override("font_disabled_color", TEXT_FAINT)
	b.add_theme_font_override("font", sans())


## The shared Theme: mono telemetry labels, sans buttons and headings
## (Label variation "Heading"), themed panels, lists, inputs and tabs.
static func build_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = mono()
	t.default_font_size = SIZE_BODY
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel())
	# Headings and actions: sans.
	t.set_type_variation("Heading", "Label")
	t.set_font("font", "Heading", sans())
	t.set_font_size("font_size", "Heading", SIZE_TITLE)
	t.set_color("font_color", "Heading", CYAN)
	t.set_type_variation("Caption", "Label")
	t.set_font_size("font_size", "Caption", SIZE_SMALL)
	t.set_color("font_color", "Caption", TEXT_DIM)
	for type in ["Button", "OptionButton", "TabBar", "TabContainer", "CheckBox", "MenuButton"]:
		t.set_font("font", type, sans())
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(SURFACE.r, SURFACE.g, SURFACE.b, 0.95)
	flat.border_color = Color(CYAN.r, CYAN.g, CYAN.b, BORDER_ALPHA)
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(RADIUS)
	flat.set_content_margin_all(SPACE_XS + 1)
	var hover := flat.duplicate()
	hover.bg_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.14)
	var focus := flat.duplicate()
	focus.border_color = CYAN
	focus.set_border_width_all(2)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, flat)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, hover)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("disabled", type, flat)
		t.set_color("font_color", type, CYAN)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, TEXT_FAINT)
	t.set_stylebox("normal", "LineEdit", flat)
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("panel", "ItemList", flat)
	t.set_stylebox("focus", "ItemList", focus)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_stylebox("panel", "TabContainer", panel(CYAN, SPACE_S, 0.9))
	t.set_color("font_selected_color", "TabContainer", CYAN)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	var tab_sel := flat.duplicate()
	tab_sel.border_color = CYAN
	tab_sel.border_width_bottom = 2
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", flat)
	t.set_stylebox("tab_hovered", "TabContainer", hover)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", mono())
	t.set_font("bold_font", "RichTextLabel", sans())
	t.set_font_size("normal_font_size", "RichTextLabel", SIZE_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", SIZE_BODY + 1)
	_theme = t
	return t


## Component state for a system: [glyph, colour, word].
static func equipment_state(e: ShipSystems.EquipmentState) -> Array:
	if e.destroyed():
		return [GLYPH_DESTROYED, RED, "destroyed"]
	if not e.powered:
		return [GLYPH_OFFLINE, TEXT_DIM, "unpowered"]
	var frac := e.hp / e.max_hp
	if frac < 0.35:
		return [GLYPH_CRITICAL, RED, "critical"]
	if frac < 1.0:
		return [GLYPH_DEGRADED, AMBER, "degraded"]
	return [GLYPH_OK, CYAN, "functional"]
