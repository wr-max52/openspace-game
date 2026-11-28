extends GutTest
## Issue #703: selling the gun in your hand puts it away; selling something else
## leaves the gun out.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const VENDOR := { "id": "test_buyer", "buys": ["*"] }

var content


func before_each() -> void:
	WorldState.reset()
	content = CoreScript.new()
	content.load_from()


func after_each() -> void:
	WorldState.reset()


func _gear(weapons: PlayerWeapons) -> GearController:
	var gear := GearController.new()
	gear.content = content
	var raw = CoreScript.read_json(GearController.LABELS_PATH)
	gear.labels = raw.get("labels", {})
	gear.on_sold = func(id: String): weapons.put_away(id)
	autofree(gear)
	return gear


func _drawn(weapons: PlayerWeapons, id: String) -> void:
	weapons.holder.request(id)
	weapons.holder.update(1.0)
	assert_eq(weapons.holder.current, id, "%s is out" % id)


func test_selling_the_gun_in_your_hand_holsters_it() -> void:
	var weapons: PlayerWeapons = autofree(PlayerWeapons.new())
	var gear := _gear(weapons)
	WorldState.inventory.add("sniper_rifle")
	_drawn(weapons, "sniper_rifle")
	assert_eq(gear.sell_item("sniper_rifle", VENDOR), "sold")
	weapons.holder.update(1.0)
	assert_eq(weapons.holder.current, "", "sold: it is put away")


func test_selling_something_else_keeps_the_gun_out() -> void:
	var weapons: PlayerWeapons = autofree(PlayerWeapons.new())
	var gear := _gear(weapons)
	WorldState.inventory.add("quartz")
	_drawn(weapons, "pistol_blaster")
	assert_eq(gear.sell_item("quartz", VENDOR), "sold")
	weapons.holder.update(1.0)
	assert_eq(weapons.holder.current, "pistol_blaster", "the pistol stays in your hand")
