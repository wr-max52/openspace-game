extends GutTest
## Issue #882: the red world's roads and races, from the headless trace
## (scenes/roads_races_trace.gd, real physics, the real town scene on the red
## world): every town is on a road and the roads join them all to the port; the
## lamps are two batched draws a road with one shared glow and no real light;
## every road point is open ground with nothing solid on it; a speeder drives
## every road end to end and stays on it; and the first red crew's race runs to
## the finish with its NPC racers.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/roads_races_trace.txt")


func _n(k: String) -> float:
	return float(t.get(k, "-1"))


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/roads_races_trace.gd first (test_all.sh does)")


func test_every_town_is_on_a_road_to_the_port() -> void:
	assert_eq(t.get("PLACE"), "port_red")
	assert_eq(_n("ROADS"), 7.0)
	assert_eq(_n("ROADS_TOWNS"), 7.0, "all seven places have a road")
	assert_eq(_n("ROADS_JOINED"), 7.0, "and every one leads back to the port")
	assert_eq(_n("ROADS_TUNNELS"), 3.0, "the three ranges in the way are tunnelled")
	assert_gt(_n("ROADS_KM"), 10.0)


func test_the_lamps_are_batched_glow() -> void:
	assert_gt(_n("LAMPS"), 300.0)
	assert_eq(_n("LAMP_HEADS"), _n("LAMPS"), "a head on every lamp")
	assert_eq(_n("LAMP_POSTS"), _n("LAMPS"), "and a post")
	assert_eq(_n("LAMP_DRAWS_PER_ROAD"), 2.0, "posts and heads: two MultiMeshes a road")
	assert_eq(_n("LAMP_REAL_LIGHTS"), 0.0, "glow, not lights (RENDER_RULES)")
	assert_eq(_n("LAMP_HEAD_MATERIALS"), 1.0, "one cached glow for them all")


func test_the_roads_are_open_ground() -> void:
	assert_gt(_n("GROUND_POINTS"), 1000.0)
	assert_eq(_n("GROUND_BAD"), 0.0, "a speeder hovers its height along every road")
	assert_eq(_n("GROUND_BLOCKED"), 0.0, "nothing solid on any road")


func test_a_speeder_drives_every_road() -> void:
	assert_eq(_n("DRIVE_ROADS_DONE"), _n("ROADS"), "every road end to end")
	assert_eq(_n("DRIVE_TOWNS_REACHED"), 7.0, "so every town from the port")
	assert_lt(_n("DRIVE_WORST_OFF_M"), 6.0, "never further from the centre line than its half width and a bit")
	assert_eq(_n("DRIVE_WRECKED"), 0.0)


func test_a_red_race_runs_to_the_finish() -> void:
	assert_eq(_n("RACE_CREWS"), 3.0)
	assert_eq(_n("RACE_COURSES"), 3.0)
	assert_eq(t.get("RACE_CREW_FOUND"), "true", "the first crew is at its camp")
	assert_eq(_n("RACE_TUNNELS_ON_LINE"), 3.0, "each course runs a tunnel")
	assert_eq(t.get("RACE_MOUNTED"), "true")
	assert_eq(t.get("RACE_ACCEPT", "x"), "", "the buy-in is taken")
	assert_eq(t.get("RACE_GO"), "true")
	assert_gt(_n("RACE_SECONDS"), 60.0, "two laps take a while")
	assert_ne(t.get("RACE_WINNER", ""), "", "someone wins")
	assert_eq(_n("RACE_NPC_FINISHERS"), 3.0, "the crew's racers all finish")
	assert_eq(t.get("RACE_OUT", "x"), "", "and you were never put out")
