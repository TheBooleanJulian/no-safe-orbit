class_name CyberTheme
extends RefCounted
## The UI's look: near-black glass panels with neon cyan and magenta borders
## and text. Every panel built in code takes its styles from here; the scene
## themes (hud.tscn, shipyard.tscn) use the same colours.

const CYAN := Color(0.0, 0.94, 1.0)
const MAGENTA := Color(1.0, 0.17, 0.84)
const TEXT := Color(0.72, 0.97, 1.0)
const TEXT_DIM := Color(0.45, 0.62, 0.7)
const BG := Color(0.02, 0.02, 0.05, 0.9)
const WARN := Color(1.0, 0.8, 0.25)
const DANGER := Color(1.0, 0.25, 0.45)
const OK := Color(0.3, 1.0, 0.7)


## Glass panel: cyan frame with a thicker accent edge on the left (or the
## given accent colour, e.g. MAGENTA for alerts and enemy information).
static func panel(accent: Color = CYAN, margin: float = 10.0, opacity: float = BG.a) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(BG.r, BG.g, BG.b, opacity)
	s.border_color = accent * Color(1, 1, 1, 0.85)
	s.set_border_width_all(1)
	s.border_width_left = 3
	s.set_corner_radius_all(0)
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.set_content_margin_all(margin)
	s.shadow_color = accent * Color(1, 1, 1, 0.25)
	s.shadow_size = 6
	return s


static func html(c: Color) -> String:
	return "#" + c.to_html(false)


## A plain button in the theme.
static func style_button(b: Button, accent: Color = CYAN) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.03, 0.03, 0.08, 0.95) if state != "hover" else Color(accent.r, accent.g, accent.b, 0.18)
		s.border_color = accent if state != "disabled" else TEXT_DIM
		s.set_border_width_all(1)
		s.set_content_margin_all(6)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
