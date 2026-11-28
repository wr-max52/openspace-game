extends GutTest
## Issue #835: name your ride. Your ships and speeders each have a name you can type
## over or roll again with the dice in the Ledger. A typed name goes through the
## same filter as generated ones (length, rude words, franchise names) and must be
## free; the new name is what the HUD shows, and it is saved.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")

var content
var rename_calls := 0


func before_each() -> void:
	WorldState.reset()
	WorldState.hangar = "courier"                 # a ship of yours, bought from T-89
	WorldState.bump("speeders_owned")             # and a speeder in slot 0
	WorldState.speeder_fits = [SpeederUpgrades.new_fit("", "speeder")]
	content = CoreContent.new()
	content.load_from()
	rename_calls = 0


func after_each() -> void:
	WorldState.reset()


func _ledger() -> InventoryPanel:
	var ledger := InventoryPanel.new()
	ledger.content = content
	ledger.on_renamed = func(): rename_calls += 1
	add_child_autofree(ledger)
	ledger.refresh()
	return ledger


func test_ships_and_speeders_have_name_fields_and_dice() -> void:
	var ledger := _ledger()
	var ship_key := NameHooks.player_ship_key("courier")
	var speeder_key := NameHooks.speeder_key(0)
	assert_true(ledger.name_fields.has(ship_key), "your ship's row has a name field")
	assert_true(ledger.dice_buttons.has(ship_key), "and a dice button")
	assert_true(ledger.name_fields.has(speeder_key), "your speeder's row too")
	assert_ne(ledger.name_fields[speeder_key].text, "", "speeders get a generated name")
	assert_eq(ledger.name_fields[ship_key].text, NameHooks.vessel(content.get_ship("courier"), ship_key),
		"the field shows the name the HUD reads")


func test_a_typed_name_takes_and_survives_a_save() -> void:
	var ledger := _ledger()
	var key := NameHooks.player_ship_key("courier")
	assert_eq(ledger.rename(key, "  Lucky Gull "), "", "an allowed name takes")
	assert_eq(ledger.name_fields[key].text, "Lucky Gull", "trimmed")
	assert_eq(rename_calls, 1, "the HUD is told to read it again")
	assert_eq(NameHooks.vessel(content.get_ship("courier"), key), "Lucky Gull", "the HUD's own lookup sees it")
	WorldState.from_save(JSON.parse_string(JSON.stringify(WorldState.to_save())))
	assert_eq(NameHooks.vessel(content.get_ship("courier"), key), "Lucky Gull", "and it is saved")


func test_bad_and_taken_names_are_refused() -> void:
	var ledger := _ledger()
	var key := NameHooks.player_ship_key("courier")
	var before: String = ledger.name_fields[key].text
	assert_eq(ledger.rename(key, "Skywalker Run"), "name_bad", "a franchise word")
	assert_eq(ledger.rename(key, "Ab"), "name_bad", "too short")
	assert_eq(ledger.rename(key, "Oda Vell"), "name_taken", "the cantina owner's name")
	assert_eq(ledger.name_fields[key].text, before, "the old name goes back in the field")
	assert_true(ledger.name_notes[key].visible, "and a line says why")
	assert_eq(ledger.name_notes[key].text, Objective.line("name_taken"))
	assert_eq(WorldState.names.by_key[key], before, "nothing changed in the book")
	assert_eq(rename_calls, 0)


func test_the_dice_roll_new_allowed_names() -> void:
	var ledger := _ledger()
	var key := NameHooks.speeder_key(0)
	var first: String = ledger.name_fields[key].text
	var second := ledger.roll_name(key)
	var third := ledger.roll_name(key)
	assert_ne(second, first, "a new name")
	assert_ne(third, second, "and another")
	for n in [second, third]:
		assert_true(WorldState.names.engine.acceptable(n), n + " passes the filter")
	assert_eq(ledger.name_fields[key].text, third, "the field shows it")
	assert_eq(rename_calls, 2)
	assert_eq(int(WorldState.names.to_save().rolls[key]), 2, "the rolls are counted for the save")
