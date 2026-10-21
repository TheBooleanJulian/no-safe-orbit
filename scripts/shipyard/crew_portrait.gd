class_name CrewPortrait
extends Control
## A placeholder portrait (play-test batch 9): head and shoulders in a
## frame of the post's colour, a skin tone and hair from the person's name
## (the same name always looks the same), initials on the collar.

const SKIN := [Color("f1c7a5"), Color("d9a37e"), Color("b07a55"), Color("8a5a3c"), Color("5c3a26")]
const HAIR := [Color("1b1714"), Color("3b2a20"), Color("6b4a2e"), Color("a87a3d"), Color("c9c2b8"), Color("7a2e1e")]

var person := ""
var role := 0


func _draw() -> void:
	var s := size
	var h := absi(hash(person))
	var ring: Color = CrewRoster.ROLE_COLORS[clampi(role, 0, CrewRoster.ROLE_COLORS.size() - 1)]
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.06, 0.08))
	var skin: Color = SKIN[h % SKIN.size()]
	var hair: Color = HAIR[(h / 7) % HAIR.size()]
	var c := Vector2(s.x * 0.5, s.y * 0.42)
	var r := s.x * 0.2
	# Shoulders (the uniform in the post's colour: the top of a circle
	# standing on the frame's bottom edge), then the head and hair.
	var shoulders := PackedVector2Array()
	var sr := s.x * 0.42
	for k in 17:
		var a := PI + PI * k / 16.0
		shoulders.append(Vector2(s.x * 0.5 + cos(a) * sr, s.y + sin(a) * sr))
	draw_colored_polygon(shoulders, ring.darkened(0.35))
	draw_circle(c, r, skin)
	draw_arc(c, r * 0.98, PI * 1.05, PI * 1.95, 16, hair, r * 0.55)
	draw_rect(Rect2(Vector2.ZERO, s), ring, false, 2.0)
	var initials := ""
	for word in person.split(" ", false):
		initials += word.left(1)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(4, s.y - 4), initials.left(2), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.8))
