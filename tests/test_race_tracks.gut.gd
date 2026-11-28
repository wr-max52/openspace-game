extends GutTest
## Issue #853: race tracks. A course works out three tracks from the rocks on it,
## every point clear of them and through every gate; a racer on a track drives a
## lap of a boulder-choked loop without getting stuck; a course file's `tracks`
## goes over rules.json's.

const DT := 1.0 / 60.0
const SIDE := 400.0

var ground: WorldGround


func before_each() -> void:
	ground = WorldGround.new()
	ground.setup({ "terrain": { "extent": 6000.0 } })


## A square loop SIDE m a side, its legs lined with boulders 8 m either side of the
## line and one on the line itself halfway down each leg, none near a gate.
func _rocky_course() -> RaceCourse:
	var c := { "id": "rocky", "label": "Rocky", "world": "port_desert", "laps": 1, "gate_width": 26.0,
		"antenna_height": 7.0, "grid": { "slots": 4, "back_m": 10.0, "row_m": 9.0, "side_m": 4.5 }, "gates": [] }
	var corners: Array = [Vector2(0, 0), Vector2(0, -SIDE), Vector2(SIDE, -SIDE), Vector2(SIDE, 0)]
	for k in corners.size():
		c.gates.append({ "id": "g%d" % k, "at": [corners[k].x, corners[k].y] })
	var rocks: Array = []
	for k in corners.size():
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % corners.size()]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var along := 40.0
		while along < SIDE - 40.0:
			for off: float in [-8.0, 8.0]:
				var p := a + dir * along + side * off
				rocks.append({ "center": _sand(p), "up": Vector3.UP, "radius": 1.5, "height": 4.0 })
			along += 12.0
		var mid := a + dir * SIDE * 0.5
		rocks.append({ "center": _sand(mid), "up": Vector3.UP, "radius": 1.0, "height": 4.0 })
	ground.add_boulders(rocks)
	ground.invalidate_index()
	var rc := RaceCourse.new()
	rc.setup(null, ground, c)
	add_child_autofree(rc)
	return rc


func _sand(p: Vector2) -> Vector3:
	return Vector3(p.x, ground.terrain.height_at(p.x, p.y), p.y)


func test_three_tracks_clear_of_rock_through_every_gate() -> void:
	var rc := _rocky_course()
	var tracks := rc.race_tracks()
	assert_eq(tracks.size(), 3, "a left, a middle and a right track")
	var body := float(rc.tracks_cfg().get("body_m", 1.6))
	for t in tracks.size():
		var hits := 0
		for p in tracks[t]:
			if ground.hit((p as Vector3) + Vector3.UP * 1.05, body) != "":
				hits += 1
		assert_eq(hits, 0, "track %d: every point clear of the rocks" % t)
		for g in rc.gates:
			var best := INF
			for p in tracks[t]:
				best = minf(best, (p as Vector3).distance_to(g.pos))
			assert_lt(best, float(g.half) - 2.0, "track %d runs through gate %s" % [t, g.id])
	assert_same(rc.race_tracks(), tracks, "worked out once and kept")
	var middle: Array = tracks[1]
	var mid_rock := _sand(Vector2(0.0, -SIDE * 0.5))
	var nearest := INF
	for p in middle:
		nearest = minf(nearest, (p as Vector3).distance_to(mid_rock))
	assert_gt(nearest, 2.5, "the middle track weaves round the rock on the line")


func test_a_racer_on_a_track_laps_the_rocks_without_getting_stuck() -> void:
	var rc := _rocky_course()
	var tracks := rc.race_tracks()
	for t in tracks.size():
		for model: String in ["racer", "hauler"]:
			var m := HoverModel.new(HoverModel.load_config(model), ground)
			var slot := rc.grid_slot(1)
			m.place(slot.pos, float(slot.yaw))
			var b := SpeederBrain.new(m, "pro", 7)
			b.follow_track(tracks[t])
			var laps := rc.new_laps()
			laps.add_racer("r")
			var last := m.position
			var done := false
			var tt := 0.0
			while not done and tt < 150.0:
				var c := b.update(DT)
				m.set_command(float(c.throttle), float(c.steer), bool(c.boost))
				m.step(DT)
				for e in rc.step_racer(laps, "r", last, m.position):
					done = done or str(e.type) == "finish"
				last = m.position
				tt += DT
			assert_true(done, "track %d, %s: a full lap" % [t, model])
			assert_eq(b.stuck_events, 0, "track %d, %s: never stuck on a rock" % [t, model])


func test_a_course_file_sets_its_own_lanes() -> void:
	var leaps := RaceCourse.new()
	leaps.setup(null, ground, RaceCourse.load_course("far_leaps"))
	add_child_autofree(leaps)
	assert_eq(leaps.tracks_cfg().get("lanes_m"), [-9.0, 0.0, 9.0], "the Far Leaps' lanes run over its rows of ramps")
	assert_eq(leaps.tracks_cfg().get("step_m"), RaceCrew.rules().tracks.step_m, "the rest from rules.json")
