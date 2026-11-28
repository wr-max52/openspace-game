extends GutTest
## Issue #877: the mountain towns, from the headless trace
## (scenes/mountain_towns_trace.gd, real physics, the real town scene on the red
## world): all seven places stand on their peaks with their folk and their
## stalls, the glass lift carries you from the sand to the top and you can walk
## off its bridge into the town, the road up Sootwell's peak is ground and a
## clear way the whole climb, and the town costs no more frame than the street.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/mountain_towns_trace.txt")


func _n(k: String) -> float:
	return float(t.get(k, "-1"))


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/mountain_towns_trace.gd first (test_all.sh does)")


func test_every_place_stands_with_its_folk() -> void:
	assert_eq(t.get("PLACE"), "port_red")
	assert_eq(_n("PLACES"), 7.0, "three towns and four ledge hamlets")
	assert_eq(_n("PLACES_BUILT"), 7.0)
	assert_gt(_n("PEOPLE"), 40.0, "people up there")
	assert_eq(_n("FOLKS"), 7.0, "each place's own director")
	assert_gt(_n("FOLKS_WALKERS"), 10.0, "residents walk their strolls")
	assert_gte(_n("VENDORS"), 10.0, "a keeper at every stall and a barkeep at each cantina")
	assert_eq(_n("VENDORS_GIVEN"), _n("VENDORS"), "and they trade")


func test_the_lift_goes_from_the_sand_to_the_top() -> void:
	assert_eq(_n("LIFTS"), 2.0, "the Pilgrims' Rest and Highfold")
	assert_gt(_n("LIFT_CLIMB_M"), 25.0, "a real climb")
	assert_eq(t.get("LIFT_AT_TOP"), "true")
	assert_eq(_n("LIFT_RIDES"), 1.0, "with the player on it")
	assert_lt(absf(_n("LIFT_PLAYER_DY")), 0.3, "standing on its car at the top")
	assert_eq(t.get("LIFT_ON_FLOOR"), "true")
	assert_lt(_n("LIFT_SECONDS"), 15.0)


func test_off_the_bridge_and_in_at_the_gate() -> void:
	assert_eq(t.get("TOP_BRIDGE_ON_FLOOR"), "true")
	assert_lt(absf(_n("TOP_BRIDGE_DY")), 0.3, "the bridge is level with the top")
	assert_eq(t.get("TOP_GATE_ON_FLOOR"), "true")
	assert_lt(absf(_n("TOP_GATE_HEIGHT")), 0.3, "the town's floor is the ship's ground too")


func test_the_road_up_is_ground_and_clear_the_whole_way() -> void:
	assert_gt(_n("ROAD_POINTS"), 100.0)
	assert_gt(_n("ROAD_CLIMB_M"), 25.0)
	assert_gt(_n("ROAD_LEN_M"), 250.0, "a long climb round the peak")
	assert_eq(_n("ROAD_BAD_GROUND"), 0.0, "a speeder's ground the whole way")
	assert_eq(_n("ROAD_BLOCKED"), 0.0, "nothing in a speeder's way")
	assert_eq(_n("ROAD_BAD_COLLIDER"), 0.0, "and something to walk on")
	assert_lt(_n("ROAD_END_TO_GATE_M"), 6.0, "it runs into the town's gate")
	assert_lt(absf(_n("ROAD_START_SAND_DY")), 0.3, "it starts on the sand")


func test_the_town_costs_no_more_than_the_street() -> void:
	assert_lt(_n("FRAME_TOWN_MS"), maxf(_n("FRAME_STREET_MS") * 1.5, 25.0))
	assert_lt(_n("FRAME_TOWN_MS"), 50.0, "the frame budget")
