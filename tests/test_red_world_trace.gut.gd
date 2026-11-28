extends GutTest
## Issue #875: the red desert world, from the headless trace
## (scenes/red_world_trace.gd, real physics, the real town scene): it loads in
## the red system, its town is valid, tall and full of red locals, its five
## Remnant outposts and its own people stand, a skirmish waits on the way up,
## and the mountain pocket costs no more frame than the street.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/red_world_trace.txt")


func _n(k: String) -> float:
	return float(t.get(k, "-1"))


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/red_world_trace.gd first (test_all.sh does)")


func test_it_loads_in_the_red_system() -> void:
	assert_eq(t.get("PLACE"), "port_red")
	assert_eq(t.get("SYSTEM"), "red_reach")
	assert_eq(t.get("TYPE"), "red_desert")
	assert_eq(_n("BALL_R"), 4000.0, "80% of the home world")
	assert_eq(t.get("PLAYER_ON_GROUND"), "true")


func test_a_tall_town_of_red_locals() -> void:
	assert_eq(_n("TOWN_ERRORS"), 0.0, "the generated town validates")
	assert_gt(_n("TOWN_BOXES"), 150.0, "a big city")
	assert_gte(_n("TOWN_TOWERS"), 20.0, "towers over the street")
	assert_gt(_n("TOWN_RED_LOCALS"), 10.0, "its people are the red folk")


func test_five_outposts_and_their_guards() -> void:
	assert_eq(_n("OUTPOSTS_BUILT"), 5.0)
	assert_gte(_n("OUTPOSTS_GUARDS"), 10.0)
	for id in ["spur", "gorge", "dunes", "flats", "far"]:
		assert_string_contains(str(t.get("OUTPOSTS_IDS")), "remnant_outpost_red_" + id)


func test_its_own_people() -> void:
	assert_gte(_n("NATIVES_PACKS"), 2.0)
	assert_string_ends_with(str(t.get("NATIVES_LABEL")), " folk", "named for this world by the name engine")


func test_a_skirmish_on_the_way_up() -> void:
	assert_eq(t.get("ENCOUNTER"), "orbital_skirmish")


func test_mountain_country_without_the_frame_cost() -> void:
	assert_between(_n("MOUNTAINS"), 40.0, 80.0)
	assert_eq(_n("TUNNEL_RANGES"), 6.0)
	assert_gte(_n("POCKET_PEAKS"), 4.0, "the trace stood in a real pocket")
	assert_lt(_n("FRAME_STREET_MS"), 50.0, "the frame budget in the street")
	assert_lt(_n("FRAME_POCKET_MS"), 50.0, "and among the peaks")
