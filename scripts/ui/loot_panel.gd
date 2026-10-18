class_name LootPanel
extends PanelContainer
## Salvage results: spare parts recovered, then each loot drop revealed in
## turn in its rarity colour, with the pity countdown and the published drop
## rates. Built in code; Main opens it and closes it with the salvage key.

const REVEAL_INTERVAL_S := 0.45

var _label: RichTextLabel
var _header: PackedStringArray = PackedStringArray()
var _drops: Array[LootRoller.Drop] = []
var _footer: PackedStringArray = PackedStringArray()
var _shown := 0
var _clock := 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.05, 0.94)
	style.border_color = Rarity.color_of(Rarity.Tier.LEGENDARY) * Color(1, 1, 1, 0.8)
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(520, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


## Show what salvaging `wreck_name` produced.
func show_salvage(wreck_name: String, intact: float, parts: int, drops: Array[LootRoller.Drop], profile: PlayerProfile) -> void:
	_header = PackedStringArray([
		"[b]SALVAGE — %s[/b]   wreck %d%% intact" % [wreck_name, roundi(intact * 100.0)],
		"+%d spare parts recovered" % parts,
		"%d salvage crate%s:" % [drops.size(), "" if drops.size() == 1 else "s"],
	])
	_drops = drops
	var pity := profile.pity_countdown()
	_footer = PackedStringArray([
		"",
		"Spare parts %d  ·  Rare+ guaranteed in %d  ·  Legendary in %d" % [profile.spare_parts, pity.x, pity.y],
		"[color=#8899aa]Rates %s[/color]" % LootRoller.rates_text(),
		"[color=#8899aa][G] close — next contact inbound[/color]",
	])
	_shown = 0
	_clock = 0.0
	visible = true
	_render()


func revealed_all() -> bool:
	return _shown >= _drops.size()


func _process(delta: float) -> void:
	if not visible or revealed_all():
		return
	_clock += delta
	if _clock >= REVEAL_INTERVAL_S:
		_clock = 0.0
		_shown += 1
		_render()


func _render() -> void:
	var lines := _header.duplicate()
	for i in _drops.size():
		if i < _shown:
			var d := _drops[i]
			var mark := "◆" if d.rarity >= Rarity.Tier.EPIC else "◇"
			lines.append("  [color=#%s]%s %s  %s[/color]" % [Rarity.color_of(d.rarity).to_html(false), mark,
				Rarity.name_of(d.rarity).to_upper(), d.describe()])
		else:
			lines.append("  [color=#556070]▒ opening…[/color]" if i == _shown else "  [color=#556070]▒[/color]")
	if revealed_all():
		lines.append_array(_footer)
	_label.text = "\n".join(lines)


## Plain text of the panel (tests).
func text() -> String:
	return _label.get_parsed_text()
