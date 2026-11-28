extends GutTest
## Issue #876: the red system's ring station and cruiser, from the headless trace
## (scenes/dark_station_trace.gd, real physics, the real town scene): the station
## hangs over the port in its own darker metal under its own name, Z docks you in
## its bay, killing its Remnant hands the deck to the locals and moves the map's
## owners, and killing the cruiser's general sets only that cruiser's flag.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/dark_station_trace.txt")


func _n(k: String) -> float:
	return float(t.get(k, "-1"))


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/dark_station_trace.gd first (test_all.sh does)")


func test_the_station_hangs_over_the_port() -> void:
	assert_eq(_n("STATIONS"), 1.0, "one station in the red port's sky")
	assert_eq(t.get("STATION_FILE"), "dark_station")
	assert_almost_eq(_n("STATION_ALTITUDE"), 1000.0, 5.0, "under the cloud deck")
	assert_lt(_n("STATION_FROM_PORT_M"), 600.0, "over the city")


func test_a_copy_with_its_own_name_and_metal() -> void:
	assert_ne(t.get("STATION_NAME", ""), "", "named by the name engine")
	assert_ne(t.get("STATION_NAME"), t.get("HOME_STATION_NAME"), "not the home ring station's name")
	assert_eq(t.get("STATION_FLOORS"), t.get("HOME_FLOORS"), "the same floors")
	assert_eq(_n("STATION_ROOMS"), _n("HOME_ROOMS"), "the same rooms")
	assert_lt(_n("HULL_LUMA"), 0.3, "a darker hull than the shader's own (0.58)")


func test_z_docks_you_in_its_bay() -> void:
	assert_eq(t.get("DOCK_TARGET"), "dark_station")
	assert_eq(t.get("DOCK_STARTED"), "true")
	assert_eq(t.get("DOCK_STATE"), "PARKED")
	assert_lt(_n("DOCK_S"), 60.0)
	assert_lt(_n("DOCK_PAD_ERR_M"), 4.0, "down on the dock pad")
	assert_eq(t.get("PLAYER_ABOARD"), "true")
	assert_eq(t.get("PLAYER_ON_FLOOR"), "true")


func test_taking_the_deck_moves_the_map_owners() -> void:
	assert_eq(t.get("DECK_OWNER_BEFORE"), "remnant")
	assert_eq(t.get("DECK_LOCKED"), "false", "its own place, answering to no front")
	assert_gt(_n("DECK_SOLDIERS"), 10.0, "the deck and the top floor are manned")
	assert_eq(t.get("DECK_OWNER_AFTER"), "locals")
	var before: Dictionary = str_to_var(t.get("MAP_BEFORE", "{}"))
	var after: Dictionary = str_to_var(t.get("MAP_AFTER", "{}"))
	assert_gt(int(before.get("remnant", 0)), 0, "the Remnant hold rooms before")
	assert_eq(int(after.get("remnant", -1)), 0, "and none after")
	assert_eq(int(after.get("locals", 0)), int(before.get("locals", 0)) + int(before.get("remnant", 0)), "the locals have them")
	assert_eq(int(after.get("smugglers", 0)), int(before.get("smugglers", 0)), "the smugglers keep theirs")
	assert_eq(_n("STATIONS_TAKEN"), 1.0)


func test_the_cruiser_is_its_own() -> void:
	assert_eq(t.get("CRUISER"), "true")
	assert_eq(t.get("CRUISER_CFG"), "red_cruiser")
	assert_eq(t.get("CRUISER_FLAG"), "red_cruiser_taken")
	assert_gt(_n("CRUISER_ALTITUDE"), 1250.0, "over the cloud deck")
	assert_lt(_n("CRUISER_ALTITUDE"), 3500.0, "under the black of space: this scene")
	assert_gt(_n("CRUISER_TO_STATION_M"), 2500.0 + 0.0, "out of the station's docking reach")


func test_killing_its_general_sets_only_its_flag() -> void:
	assert_eq(t.get("GENERAL"), "true")
	assert_eq(t.get("CRUISER_TAKEN"), "true")
	assert_eq(t.get("RED_FLAG"), "true")
	assert_eq(t.get("BELT_FLAG"), "false", "the belt cruiser is untouched")
	assert_eq(t.get("STORY_CRUISER"), "false", "the story's cruiser is untouched")
	assert_eq(_n("PAID"), 18000.0, "its own reward")
	assert_eq(t.get("HOLDER"), "locals")
	assert_eq(t.get("BELT_HOLDER"), "remnant")
