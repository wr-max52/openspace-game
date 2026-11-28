extends GutTest
## Issue #879: the tide world's round sea, from the headless trace
## (scenes/sea_trace.gd, real physics, the real town scene on the tide world): the
## water type made a ball, a smooth sea with nothing lethal to a ship; the speeder
## pad out front at the deck's level with its ramp down to the water, the spots
## and the loaner on it; five Remnant outposts on pontoons out on the open sea, a
## Territory front; a speeder crosses a kilometre of sea to the nearest outpost and
## back without sinking, its rider standing on the pontoon between; a person on
## foot in the water drowns and wakes by the landing bay, and nobody drowns on the deck.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/sea_trace.txt")


func _n(k: String) -> float:
	return float(t.get(k, "-1"))


func _true(k: String, msg := "") -> void:
	assert_eq(t.get(k, "missing"), "true", k + (": " + msg if msg != "" else ""))


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/sea_trace.gd first (test_all.sh does)")


func test_the_tide_world_is_a_round_sea() -> void:
	assert_eq(t.get("PLACE"), "port_tide")
	assert_eq(t.get("TYPE"), "water_ball")
	assert_eq(t.get("SYSTEM"), "red_reach", "the red system's second world")
	_true("SEA_IS_BALL")
	assert_lt(_n("SEA_LEVEL_M"), 0.0, "the sea lies under the deck")
	assert_gt(_n("SEA_LEVEL_M"), -4.0, "but only a little: the deck sits low on the water")
	_true("SEA_SMOOTH", "open water everywhere off the pads")
	assert_eq(t.get("SEA_SHADER"), "res://src/systems/look/shaders/sea.gdshader")
	_true("SEA_NO_SAND", "no dunes or landforms on a sea")
	assert_eq(_n("SEA_NO_GLASS"), 0.0, "no glass wall round an open deck")
	_true("SEA_NOT_LETHAL", "a ship can set down on the water")
	assert_eq(t.get("SEA_STYLE"), "favela_rust")


func test_the_speeder_pad_out_front() -> void:
	_true("PAD_BUILT")
	_true("PAD_OUT_FRONT", "past the deck's front edge, on the gate")
	assert_almost_eq(_n("PAD_LEVEL_M"), 0.0, 0.05, "level with the deck")
	_true("PAD_RAMP_TO_SEA", "its ramp comes down to the water")
	assert_eq(_n("PAD_SPOTS"), 5.0)
	assert_eq(_n("PAD_SPOTS_ON_PAD"), 5.0, "the speeders you own wait on it")
	_true("PAD_LOANER_ON_PAD", "the town's loaner waits on it")
	assert_between(_n("PAD_LOANER_HEIGHT_M"), 0.3, 2.0, "hovering over the pad, not sunk in it")


func test_five_outposts_on_pontoons_are_a_front() -> void:
	assert_eq(t.get("OUTPOST_FRONT", "").split(",").size(), 5, "the tide front holds five outposts")
	assert_eq(_n("OUTPOST_COUNT"), 5.0, "all five stand on the planet")
	assert_eq(_n("OUTPOST_ON_PONTOONS"), 5.0, "each on a pontoon out of the sea")
	assert_eq(_n("OUTPOST_IN_OPEN_SEA"), 5.0, "with open sea round each")
	var d: PackedStringArray = t.get("OUTPOST_DIST_M", "").split(",")
	assert_gte(float(d[0]), 1000.0, "even the nearest is a real ride out")


func test_a_speeder_crosses_a_kilometre_of_sea_and_back() -> void:
	_true("RIDE_MOUNTED")
	_true("RIDE_OUT_ARRIVED", "reached the nearest outpost's pontoon")
	assert_gte(_n("RIDE_OUT_SEA_M"), 1000.0, "a kilometre of open sea")
	assert_lt(_n("RIDE_OUT_SECONDS"), 90.0)
	assert_gt(_n("RIDE_OUT_LOW_M"), 0.2, "never touched the water")
	assert_between(_n("RIDE_SWELL_RANGE_M"), 0.1, 2.0, "it lifts and settles on the swell")
	_true("RIDE_DISMOUNT")
	_true("RIDE_STOOD_ON_PONTOON", "stepping off on the pontoon is not stepping into the sea")
	assert_lt(_n("RIDE_ON_PONTOON_M"), 30.0)
	_true("RIDE_REMOUNTED")
	_true("RIDE_BACK_ARRIVED", "and back to the pad")
	assert_gt(_n("RIDE_BACK_LOW_M"), 0.2)
	_true("RIDE_ALIVE")
	_true("RIDE_NOT_DROWNED")


func test_on_foot_in_the_water_you_drown_and_wake_at_the_bay() -> void:
	_true("DROWN_OUT_AT_SEA", "out on the open sea")
	assert_lt(_n("DROWN_WOKE_BY_BAY_M"), 3.0, "woke by the landing bay")
	_true("DROWN_OFF_THE_DECK", "stepping off the deck's side")
	assert_lt(_n("DROWN_WOKE_AGAIN_M"), 3.0)
	assert_true(t.get("DROWN_LINE", "").contains("sea"), "the sea's own line")
	_true("DROWN_NOT_ON_DECK", "nobody drowns standing on the deck")
