extends GutTest
## Issue #802: on foot on the far side of the ball (scenes/far_walk_trace.gd, real
## physics). 60 m sprints through Cragfall's and Farleap's yards and over open
## far-side sand go as smoothly as by the port and at Saltpan: no snags, no
## fall-pose flashes, near full speed. Before the fix they made 0.4 to 3 m/s of the
## 7 asked, snagging nearly every tick.

const TRACE := "res://test_results/far_walk_trace.txt"
const WALKS := ["NEAR", "SALTPAN", "CRAGFALL", "FARLEAP", "OPEN"]

var t: Dictionary = {}


func before_all() -> void:
	var f := FileAccess.open(TRACE, FileAccess.READ)
	if f == null:
		return
	for l in f.get_as_text().split("\n", false):
		var kv := l.split("=", true, 1)
		if kv.size() == 2:
			t[kv[0]] = kv[1]


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scripts/test_all.sh (or the trace) first")
	assert_eq(t.get("TERRAIN"), "true")


func test_the_villages_and_their_ground_are_there() -> void:
	for k in ["SALTPAN", "CRAGFALL", "FARLEAP"]:
		assert_eq(t.get(k + "_FOUND"), "true", k)
		assert_eq(t.get(k + "_OUTPOST_GROUND"), "true", k + ": its own ground, under the near one")


func test_far_walks_are_far() -> void:
	assert_gt(float(t.get("CRAGFALL_KM_ROUND", 0)), 12.0)
	assert_gt(float(t.get("FARLEAP_KM_ROUND", 0)), 13.0)
	assert_gt(float(t.get("OPEN_KM_ROUND", 0)), 12.0)


func test_every_walk_gets_there_without_snagging() -> void:
	for k in WALKS:
		assert_eq(t.get(k + "_SETTLED"), "true", k + ": stood on the ground before walking")
		assert_eq(t.get(k + "_REACHED"), "true", k + ": 60 m in time")
		assert_lt(int(t.get(k + "_STALLS", 9999)), 10, k + ": ticks that barely moved")
		assert_lt(int(t.get(k + "_AIR_FRAMES", 9999)), 5, k + ": no fall-pose flashes")


func test_near_full_speed() -> void:
	# Cragfall's line climbs ~12 m out of the gate, so it is held to a little less.
	for k in WALKS:
		var floor_speed := 5.5 if k == "CRAGFALL" else 6.3
		assert_gt(float(t.get(k + "_SPEED", 0)), floor_speed, k + " m/s of " + str(t.get(k + "_ASKED")))


func test_the_village_troopers_stand_on_the_sand() -> void:
	var off := float(t.get("CRAGFALL_GUARDS_OFF_GROUND", 99))
	assert_gte(off, 0.0, "Cragfall has troopers")
	# One stands in the outpost's block, on its floor 15 cm up; the rest on the sand.
	assert_lt(off, 0.25, "and nobody fell through or floats (#761)")
	var on: PackedStringArray = str(t.get("CRAGFALL_GUARDS_ON_FLOOR", "0/1")).split("/")
	assert_eq(on[0], on[1], "every one of them on a floor")
