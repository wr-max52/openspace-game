extends GutTest
## Issue #880: the red system's asteroid field, from the headless trace
## (scenes/field_trace.gd, real physics, the real town scene on the field): a
## place of its own on the field type with no ground, a few hundred rocks round a
## dock town on the biggest; low gravity, your feet stick to the rock under you and
## a run and a jump off one rock carries you onto the next; drift clear of them
## all and your ship reels you back; three wrecks to walk into; a ship sets down
## on a rock, bumps one slowly and crashes into one fast; four Remnant outposts on
## the biggest rocks, each one taken; and the field's jobs on the bar board, the
## salvage run paying out.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/field_trace.txt")


func _n(k: String) -> float:
	return float(t.get(k, "-1"))


func _true(k: String, msg := "") -> void:
	assert_eq(t.get(k, "missing"), "true", k + (": " + msg if msg != "" else ""))


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/field_trace.gd first (test_all.sh does)")


func test_the_field_is_its_own_place() -> void:
	assert_eq(t.get("FIELD_PLACE"), "scatter_field")
	assert_eq(t.get("FIELD_TYPE"), "field")
	assert_eq(t.get("FIELD_SYSTEM"), "red_reach", "in the red system")
	_true("FIELD_OWN_PLACE", "the field loads as a place of its own")
	assert_eq(t.get("FIELD_SPHERE"), "FieldSphere")
	_true("FIELD_NO_GROUND_MESH", "no ground out here, only rocks")


func test_a_few_hundred_rocks() -> void:
	assert_gt(_n("FIELD_ROCKS") + _n("FIELD_SMALL_ROCKS"), 300.0, "a few hundred rocks")
	assert_gt(_n("FIELD_ROCKS"), 100.0, "plenty big enough to stand on")
	assert_eq(_n("FIELD_ROCK_COLLIDERS"), _n("FIELD_ROCKS"), "every big rock is solid")
	assert_eq(_n("FIELD_GRAVITY_BODIES"), _n("FIELD_ROCKS"), "and pulls you onto it")
	assert_eq(t.get("FIELD_BAD_BOXES", "x"), "", "no inside-out collision boxes")
	_true("FIELD_DECK_ON_ROCK", "the dock town sits on the biggest rock")
	_true("FIELD_SPAWN_HELD", "you wake standing on the deck")
	assert_eq(_n("FIELD_WRECKS"), 3.0)
	assert_almost_eq(_n("FIELD_GRAVITY"), 4.0, 0.01, "low gravity, from the field's data")


func test_a_run_and_a_jump_carries_you_to_the_next_rock() -> void:
	_true("HOP_PAIR_FOUND")
	_true("HOP_STOOD_ON_A", "feet stick to the rock under you")
	assert_almost_eq(_n("HOP_LOW_GRAVITY"), 4.0, 0.01)
	_true("HOP_LEFT_A")
	assert_gt(_n("HOP_AIR_S"), 1.0, "a long, slow float across the gap")
	_true("HOP_LANDED_ON_B", "a step off one rock drifts you onto the next")
	_true("HOP_STILL_ON_B", "and you stay there")
	_true("HOP_UNHURT", "low gravity: no fall damage")
	_true("HOP_JETPACK_REFUELS_IN_AIR", "the jetpack tops up in the air out here")
	_true("HOP_NOT_REELED")


func test_drift_clear_and_your_ship_reels_you_in() -> void:
	_true("REEL_PULLED_BACK")
	assert_lt(_n("REEL_AFTER_S"), 10.0)
	assert_lt(_n("REEL_BY_SHIP_M"), 20.0, "back beside your ship")
	_true("REEL_STANDING")
	_true("REEL_FROM_BELOW", "falling away under the deck counts too")


func test_three_wrecks_to_walk_into() -> void:
	assert_eq(_n("WRECK_PADS_OK"), 3.0, "each wreck's pad lies on its rock")
	assert_eq(_n("WRECK_CELLS_ON_FLOOR"), 6.0, "the salvage cells lie on a floor")
	_true("WRECK_STOOD_ON_PAD")


func test_a_ship_lands_on_a_rock_bumps_one_and_crashes_into_one() -> void:
	_true("SHIP_CAN_LAND")
	assert_eq(t.get("SHIP_LAND_STATE"), "PARKED", "set down on a big rock's top")
	assert_lt(_n("SHIP_ON_ROCK_M"), 6.0)
	_true("SHIP_BUMPED_ROCK", "a big rock is solid to a ship")
	assert_lt(_n("SHIP_BUMP_SPEED"), 32.0, "slowly")
	assert_eq(t.get("SHIP_STATE_AFTER_BUMP"), "FLYING", "a slow bump stops her, no crash")
	_true("SHIP_OUTSIDE_ROCK", "she stays outside it")
	assert_eq(t.get("SHIP_CRASH_STATE"), "CRASHED", "a fast run into it wrecks her")
	assert_true(str(t.get("SHIP_CRASH_HIT", "")).begins_with("field/"))


func test_four_outposts_each_taken() -> void:
	assert_eq(t.get("OUTPOST_FRONT", "").split(",").size(), 4, "the field front holds four outposts")
	assert_eq(t.get("OUTPOST_FRONT_PLANET"), "field")
	assert_eq(_n("OUTPOST_BUILT"), 4.0)
	assert_eq(_n("OUTPOST_ON_ROCKS"), 4.0, "each on a big rock")
	assert_gt(_n("OUTPOST_TROOPERS"), 0.0, "manned")
	assert_eq(_n("OUTPOST_TAKEN"), 4.0, "each outpost can be taken")
	assert_eq(_n("OUTPOST_HELD"), 4.0)
	assert_eq(_n("JOB_CLEAR_PAID"), 500.0, "Clear the rock pays")
	_true("JOB_CLEAR_DONE")


func test_the_field_jobs_and_the_salvage_run_pays() -> void:
	assert_eq(t.get("JOB_BOARD_HERE"), "j_field_clear,j_field_crate,j_field_pilot,j_field_salvage")
	assert_eq(_n("JOB_BOARD_ELSEWHERE"), 0.0, "the field's jobs only on the field's board")
	_true("JOB_SALVAGE_TAKEN")
	_true("JOB_SALVAGE_STARTED")
	_true("JOB_SALVAGE_POINTER", "the pointer leads to the wreck")
	assert_eq(_n("JOB_SALVAGE_CARRIED"), 2.0)
	_true("JOB_SHIP_PARKED")
	assert_eq(_n("JOB_SALVAGE_PAID"), 450.0, "the salvage run pays")
	_true("JOB_SALVAGE_BACK_ON_BOARD", "and comes back round")
