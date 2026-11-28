extends GutTest
## The gear trader's paged menu: Buy or Sell first; Buy lists his goods by section,
## "Buy a rifle" while you lack one, "Upgrade your rifle" and "Buy an extra rifle"
## once you have it; each upgrade page lists that thing's upgrades. The rifle is on
## his shelf at 400 cr, at the port and at the station's booth.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var content


func before_each() -> void:
	WorldState.new_game(WorldState.STORY)
	content = CoreScript.new()
	content.load_from()


func after_each() -> void:
	WorldState.reset()


func _gear() -> GearController:
	var gear := GearController.new()
	gear.content = content
	gear.labels = CoreScript.read_json(GearController.LABELS_PATH).get("labels", {})
	gear.menu = DroidMenu.new()
	add_child_autofree(gear.menu)
	autofree(gear)
	return gear


func _ids(rows: Array) -> Array:
	return rows.map(func(r): return str(r.id))


func _text(rows: Array, id: String) -> String:
	for r in rows:
		if str(r.id) == id:
			return str(r.text)
	return ""


func test_the_first_page_asks_buy_or_sell() -> void:
	var v: Dictionary = content.get_vendor("gear_trader")
	assert_eq(_ids(_gear().trade_options(v)), ["page:buy", "page:sell"])


func test_a_rifle_you_lack_is_for_sale_at_400() -> void:
	var gear := _gear()
	var rows := gear.trade_options(content.get_vendor("gear_trader"), "buy")
	assert_eq(_text(rows, "buy:rifle_blaster"), "Buy a rifle  (400 cr, you have %d)" % WorldState.credits \
		if WorldState.credits < 400 else "Buy a rifle  (400 cr)")
	assert_false(_ids(rows).has("upgrade:rifle_blaster"), "no rifle upgrades before you own one")
	assert_true(_ids(rows).has("upgrade:pistol_blaster"), "the pistol is always yours")
	assert_false(_ids(rows).has("buy:pistol_blaster"), "and not for sale")
	assert_eq(str(rows.back().id), "back")


func test_buying_the_rifle_turns_its_row_into_upgrade_and_extra() -> void:
	var gear := _gear()
	var v: Dictionary = content.get_vendor("gear_trader")
	WorldState.credits = 1000
	assert_eq(gear.buy_item("rifle_blaster", v), "bought")
	assert_eq(WorldState.credits, 600, "400 cr")
	assert_true(WorldState.weapon_allowed("rifle_blaster"), "a story save can draw it now")
	var rows := gear.trade_options(v, "buy")
	assert_true(_ids(rows).has("upgrade:rifle_blaster"))
	assert_eq(_text(rows, "buy:rifle_blaster"), "Buy an extra rifle  (400 cr)")


func test_an_upgrade_page_lists_its_upgrades_and_dims_the_fitted() -> void:
	var gear := _gear()
	var v: Dictionary = content.get_vendor("gear_trader")
	WorldState.credits = 1000
	var rows := gear.trade_options(v, "upgrade:pistol_blaster")
	assert_eq(_ids(rows), ["offer:pistol_recoil", "offer:pistol_damage", "offer:pistol_rate", "back"])
	assert_string_starts_with(_text(rows, "offer:pistol_damage"), "Overcharged cells  (150 cr)")
	assert_eq(gear.buy_offer("pistol_damage"), "bought")
	rows = gear.trade_options(v, "upgrade:pistol_blaster")
	assert_true(rows.any(func(r): return bool(r.get("note", false)) and str(r.text) == "Overcharged cells: fitted"))
	assert_false(_ids(rows).has("offer:pistol_damage"))


func test_grenades_say_how_many_you_carry() -> void:
	WorldState.inventory.add("grenade", 3)
	var rows := _gear().trade_options(content.get_vendor("gear_trader"), "buy")
	assert_string_starts_with(_text(rows, "buy:grenade"), "Buy a grenade  (40 cr")
	assert_string_ends_with(_text(rows, "buy:grenade"), "you carry 3")


func test_pages_turn_and_back_goes_up_one() -> void:
	var gear := _gear()
	var v: Dictionary = content.get_vendor("gear_trader")
	gear.open_trade(v)
	assert_eq(gear.trade_page, "")
	gear._on_trade("page:buy", v)
	assert_eq(gear.trade_page, "buy")
	assert_has(_ids(gear.menu.options), "upgrade:pistol_blaster")
	gear._on_trade("upgrade:pistol_blaster", v)
	assert_eq(gear.trade_page, "upgrade:pistol_blaster")
	assert_eq(gear.menu.body_label.text, "Upgrades for your pistol. Each one is fitted for good.")
	gear._on_trade("back", v)
	assert_eq(gear.trade_page, "buy", "back from an upgrade page: Buy")
	gear._on_trade("back", v)
	assert_eq(gear.trade_page, "", "back from Buy: the first page")
	gear._on_trade("page:sell", v)
	assert_true(gear.menu.options.any(func(r): return bool(r.get("note", false))), "nothing to sell: says so")


func test_he_buys_the_rifle_back() -> void:
	var gear := _gear()
	var v: Dictionary = content.get_vendor("gear_trader")
	WorldState.inventory.add("rifle_blaster")
	assert_has(_ids(gear.trade_options(v, "sell")), "sell:rifle_blaster")


func test_the_station_booth_sells_the_rifle_and_its_upgrades() -> void:
	var gear := _gear()
	var v: Dictionary = content.get_vendor("station_gear_trader")
	WorldState.inventory.add("rifle_blaster")
	assert_has(_ids(gear.trade_options(v, "buy")), "buy:rifle_blaster")
	assert_has(_ids(gear.trade_options(v, "upgrade:rifle_blaster")), "offer:rifle_rate")
	WorldState.credits = 1000
	assert_eq(gear.buy_offer("rifle_rate"), "bought")
	assert_false(_ids(gear.trade_options(content.get_vendor("gear_trader"), "upgrade:rifle_blaster")).has("offer:rifle_rate"),
		"fitted at the station: fitted at the port too")


func test_the_fence_keeps_his_flat_menu() -> void:
	var rows := _ids(_gear().trade_options(content.get_vendor("fence")))
	assert_false(rows.has("page:buy"))
	assert_has(rows, "locked:quantonium_armour")
