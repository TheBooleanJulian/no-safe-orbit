extends TestCase
## Measures: play-test batch 11, part 4 — the cargo hold. The hold's line
## names the contract freight; the quartermaster buys found equipment out of
## the hold; the DEV button gives 100 000 credits; the dealer's catalogue
## pictures are kept by the template's contents.


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _profile() -> PlayerProfile:
	var p := PlayerProfile.new(7)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	return p


func test_the_hold_names_the_freight() -> void:
	var p := _profile()
	assert_true(p.vessel.cargo_summary() == "empty", "an empty hold")
	p.vessel.cargo["freight"] = {"contract": "c1", "m3": 40, "what": "medical supplies"}
	var only_freight := p.vessel.cargo_summary()
	p.vessel.cargo["spare_parts"] = 12
	print("    measured: \"%s\" → \"%s\"" % [only_freight, p.vessel.cargo_summary()])
	assert_true(only_freight.contains("medical supplies") and only_freight.contains("40 m³"), "freight alone is named")
	assert_true(p.vessel.cargo_summary().contains("medical supplies") and p.vessel.cargo_summary().contains("12 spare parts"), "with the rest")


func test_the_quartermaster_buys_found_equipment() -> void:
	var cat := _catalog()
	var p := _profile()
	var rare: StringName = &""
	for id: StringName in ConstructionCatalog.sorted_ids(cat.equipment):
		if (cat.equipment[id] as EquipmentDefinition).rarity == Rarity.Tier.RARE and not (cat.equipment[id] as EquipmentDefinition).legacy:
			rare = id
			break
	p.vessel.cargo["equipment"] = {String(rare): 2}
	var price := p.sell_price(cat.equipment[rare])
	var before := p.credits
	var first := p.sell_cargo_equipment(String(rare), cat)
	var after_one := int(p.vessel.cargo.equipment.get(String(rare), 0))
	var second := p.sell_cargo_equipment(String(rare), cat)
	print("    measured: %s sells for %d cr (shelf %d); credits %d → %d; hold %d → %s" % [rare, price,
		PlayerProfile.VENDOR_PRICES[Rarity.Tier.RARE], before, p.credits, after_one, p.vessel.cargo.get("equipment", "gone")])
	assert_true(first == "" and second == "" and p.credits == before + 2 * price and price > 0, "two sold, paid for")
	assert_true(price < int(PlayerProfile.VENDOR_PRICES[Rarity.Tier.RARE]), "for less than the shelf price")
	assert_true(not p.vessel.cargo.has("equipment") and p.sell_cargo_equipment(String(rare), cat) != "", "the hold is empty: nothing more to sell")
	assert_true(p.owned(rare) == 0, "selling from the hold leaves the bank alone")


func test_the_dev_button_gives_100k() -> void:
	assert_true(Shipyard.DEV_CREDITS == 100000, "DEV +100k")


func test_dealer_pictures_are_kept_by_template() -> void:
	var was := DealerShots.dir
	DealerShots.dir = "user://check_dealer_shots"
	var template := BlueprintIO.list_templates()[0]
	var p := DealerShots.path_for(template)
	assert_true(DealerShots.load_shot(template) == null, "no picture yet")
	var img := Image.create(120, 60, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5))
	var tex := DealerShots.save_shot(template, img, CyberTheme.CYAN)
	var loaded := DealerShots.load_shot(template)
	var shot := loaded.get_image() if loaded != null else null
	print("    measured: %s; corner %s, centre %s, foot %s" % [p.get_file(), shot.get_pixel(0, 0).to_html(false) if shot != null else "-",
		shot.get_pixel(60, 30).to_html(false) if shot != null else "-", shot.get_pixel(60, 58).to_html(false) if shot != null else "-"])
	assert_true(tex != null and shot != null and shot.get_size() == Vector2i(120, 60), "saved and loaded again")
	var dark := Image.create(120, 60, false, Image.FORMAT_RGBA8)
	dark.fill(Color(0.02, 0.03, 0.05))
	assert_true(not DealerShots.has_subject(dark) and DealerShots.has_subject(img), "an empty frame is not kept")
	if shot != null:
		assert_true(shot.get_pixel(0, 0).is_equal_approx(CyberTheme.CYAN), "an accent bracket at the corner")
		assert_true(shot.get_pixel(60, 58).get_luminance() < shot.get_pixel(60, 31).get_luminance(), "a shaded foot")
	assert_true(p.get_file().begins_with(template.get_file().get_basename() + "_") and p != DealerShots.path_for(BlueprintIO.list_templates()[1]),
		"a picture per template, keyed by its contents")
	DirAccess.remove_absolute(p)
	DirAccess.remove_absolute("user://check_dealer_shots")
	DealerShots.dir = was
