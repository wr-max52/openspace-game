extends GutTest
## Issue #878: the red world's folklore and its worm, from the headless trace
## (scenes/folklore_trace.gd, real physics, the real town scene on the red
## world): Dool'rey Kah is a worm (about twice the beetle's segments, no legs,
## rings of teeth, the beetle's eyes) out on the open dunes far from the
## mountain country, it rolls along and touching it kills; the Pilgrims' Rest's
## storyteller sits in its cantina and, asked about the worm with no model, names
## it; each town's locals mutter their own lines; the AI characters are briefed.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/folklore_trace.txt")


func _n(k: String) -> float:
	return float(t.get(k, "-1"))


func _true(k: String, msg := "") -> void:
	assert_eq(t.get(k, "missing"), "true", k + (": " + msg if msg != "" else ""))


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/folklore_trace.gd first (test_all.sh does)")


func test_it_is_a_worm_called_doolrey_kah() -> void:
	assert_eq(t.get("PLACE"), "port_red")
	_true("WORM_BUILT")
	assert_eq(t.get("WORM_NAME"), "Dool'rey Kah")
	_true("WORM_IS_WORM")
	assert_gte(_n("WORM_SEGMENTS"), _n("WORM_BEETLE_SEGMENTS") * 2.0, "about twice the beetle's segments")
	assert_eq(_n("WORM_LEGS"), 0.0, "no legs")
	assert_eq(_n("WORM_MANDIBLES"), 0.0)
	assert_eq(_n("WORM_ANTENNAE"), 0.0)
	assert_gte(_n("WORM_TEETH"), 16.0, "rings of cone teeth")
	assert_eq(_n("WORM_EYES"), 4.0, "the beetle's eyes, two pairs")
	assert_gt(_n("WORM_BODY_BALLS"), 28.0, "more balls than the beetle")


func test_it_lives_on_the_open_dunes() -> void:
	assert_gt(absf(_n("WORM_HOME_LON_DEG")), 90.0, "the half of the planet with no mountains")
	var leash := _n("WORM_LEASH_M")
	assert_gt(_n("WORM_HOME_TO_MOUNTAINS_M"), leash + 1000.0, "its leash never reaches the mountain country")
	assert_gt(_n("WORM_HOME_TO_TOWN_M"), leash + 1000.0)
	assert_gt(_n("WORM_HOME_TO_ROAD_M"), leash + 1000.0, "nor a road")
	_true("WORM_ON_DUNES")


func test_it_rolls_along() -> void:
	_true("WORM_MOVED")
	_true("WORM_BODY_FOLLOWS")
	assert_gt(_n("WORM_ROLL_M"), 0.5, "its body rolls in and out of the sand")


func test_touching_it_kills() -> void:
	_true("TOUCH_KILLS")
	assert_true(str(t.get("TOUCH_LINE", "")).contains("Dool'rey Kah"))


func test_the_ai_characters_know_it() -> void:
	_true("BRIEF_NAMES_IT")
	_true("BRIEF_A_WORM")


func test_the_storyteller_tells_of_it() -> void:
	assert_eq(_n("TELLER_COUNT"), 1.0)
	assert_eq(t.get("TELLER_PLACE"), "pilgrims_rest")
	assert_eq(t.get("TELLER_SOLDIER"), "pilgrim_storyteller")
	assert_eq(t.get("TELLER_BODY_NAME"), t.get("TELLER_NAME"))
	_true("TELLER_IN_CANTINA")
	_true("TELLER_ON_HOST", "on the talk host, so [E] talks")
	_true("TELLER_IN_RANGE")
	_true("TELLER_CLEAR_OF_TRADE", "no stall's or bar's [E] reaches his")
	for topic in ["worm", "ghosts", "curse"]:
		assert_true(str(t.get("TELLER_TOPICS", "")).split(",").has(topic), topic + " on the topic menu")
	_true("TELLER_WORM_NAMES_IT", "asked about the worm, he names it")
	_true("TELLER_SAID_NAMES_IT", "and a whole turn with no model does too")
	assert_true(str(t.get("TELLER_GHOST_REPLY", "")).length() > 20)
	assert_true(str(t.get("TELLER_CURSE_REPLY", "")).length() > 20)


func test_each_town_mutters_its_own() -> void:
	assert_eq(_n("LOCALS_TOWNS"), 3.0)
	assert_eq(t.get("LOCALS_KEYS"), "pilgrim,soot,highfold")
	assert_eq(_n("LOCALS_OWN_LINES_HEARD"), 3.0, "every town's locals say a line of their own")
	_true("LOCALS_TOWNS_DIFFER")
	assert_gt(_n("LOCALS_PORT_LINES"), 0.0)
