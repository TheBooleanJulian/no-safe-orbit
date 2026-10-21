class_name TechGraph
extends Control
## The tech tree drawn left to right (play-test batch 9): a column per tier,
## a node per level — teal when bought, gold when it can be bought now,
## dim while its prerequisite is missing — with lines from each node to
## what it opens. Clicking a gold node buys it (`bought`).

signal buy_pressed(id: String)

const COLUMN_W := 168.0
const ROW_H := 58.0
const NODE := Vector2(156, 50)
## A lane (row) per upgrade, its levels left to right along it; branches
## kept next to their parents, the charter in the middle.
const LANES := ["radiators", "reactor", "jump", "thrusters", "hangar_crews", "pd_control", "gunnery", "charter", "sensors",
	"damage_control", "medicine", "academy", "welfare", "salvage", "bounty"]

var profile: PlayerProfile
## [id, level] -> node centre, for the lines.
var _centres: Dictionary = {}
var _owned: Dictionary = {}


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_centres.clear()
	_owned.clear()
	var deepest := 0
	var lowest := 0
	for n in TechTree.NODES:
		var lane := LANES.find(n.id)
		if lane < 0:
			lane = LANES.size() + TechTree.NODES.find(n)
		for k in range(1, TechTree.levels(n.id) + 1):
			var t := TechTree.tier(n.id, k)
			var row := lane
			deepest = maxi(deepest, t)
			lowest = maxi(lowest, row)
			var at := Vector2(t * COLUMN_W, row * ROW_H)
			_centres[[n.id, k]] = at + NODE * 0.5
			var have := profile.tech_level(n.id)
			_owned[[n.id, k]] = have >= k
			var b := Button.new()
			b.name = "%s_%d" % [n.id, k]
			b.position = at
			b.size = NODE
			b.custom_minimum_size = NODE
			b.clip_text = true
			b.focus_mode = Control.FOCUS_NONE
			var next := have + 1 == k
			var why := TechTree.block_reason(n.id, profile.tech) if next else ""
			var cost := TechTree.next_cost(k - 1, n.id)
			b.text = "%s %s\n%s" % [n.name, TechTree.roman(k) if TechTree.levels(n.id) > 1 else "",
				"✔ bought" if have >= k else ("%d cr" % cost if next and why == "" else "locked")]
			b.tooltip_text = "%s %s — %s%s" % [n.name, TechTree.roman(k), n.text, "" if why == "" else "\n%s" % why]
			if have >= k:
				CyberTheme.style_button(b, CyberTheme.CYAN, true)
			elif next and why == "":
				CyberTheme.style_button(b, CyberTheme.AMBER)
				b.disabled = profile.credits < cost
				var id: String = n.id
				b.pressed.connect(func() -> void: buy_pressed.emit(id))
			else:
				CyberTheme.style_button(b, CyberTheme.CYAN)
				b.disabled = true
			add_child(b)
	custom_minimum_size = Vector2((deepest + 1) * COLUMN_W, (lowest + 1) * ROW_H)
	queue_redraw()


func _draw() -> void:
	for key: Array in _centres:
		var req := TechTree.requirement(str(key[0]), int(key[1]))
		if req.is_empty() or not _centres.has([str(req[0]), int(req[1])]):
			continue
		var from: Vector2 = _centres[[str(req[0]), int(req[1])]] + Vector2(NODE.x * 0.5, 0)
		var to: Vector2 = _centres[key] - Vector2(NODE.x * 0.5, 0)
		var mid := (from.x + to.x) * 0.5
		var col := CyberTheme.CYAN if _owned.get(key, false) else CyberTheme.TEXT_FAINT
		draw_polyline(PackedVector2Array([from, Vector2(mid, from.y), Vector2(mid, to.y), to]), col, 2.0, true)
