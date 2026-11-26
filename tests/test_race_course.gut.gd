extends GutTest
## Issue #610: a race course from a file. Every gate in order and back over the
## line is one lap; skip one and it is not; the line crossed backwards counts
## nothing; a gate says who went through and how far off centre; a second course
## file with other gates works with no code; the masts are solid; the gates flash.

var ground: WorldGround


func before_each() -> void:
	ground = WorldGround.new()
	ground.setup({ "terrain": { "extent": 6000.0 } })


func _course(data: Dictionary) -> RaceCourse:
	var rc := RaceCourse.new()
	rc.setup(null, ground, data)
	add_child_autofree(rc)
	return rc


## The racing line walked in small steps, `loops` times round, starting a little
## behind the start line (on the grid). `detour` moves the path sideways near
## gate `skip` so it misses it.
func _path(rc: RaceCourse, loops: int, skip: int = -1) -> Array:
	var pts: Array = []
	var g0: Dictionary = rc.gates[0]
	pts.append((g0.pos as Vector3) - (g0.fwd as Vector3) * 12.0)
	var start := _nearest(rc, g0.pos)
	for l in loops:
		for k in rc.line.size():
			pts.append(rc.line[(start + k) % rc.line.size()])
	pts.append(rc.line[start])
	pts.append((g0.pos as Vector3) + (g0.fwd as Vector3) * 12.0)
	var out: Array = []
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var n := int(ceil(a.distance_to(b) / 4.0))
		for s in n:
			out.append(a.lerp(b, float(s) / float(n)))
	out.append(pts[-1])
	if skip >= 0:
		var g: Dictionary = rc.gates[skip]
		for i in out.size():
			var d: float = (out[i] as Vector3).distance_to(g.pos)
			if d < 60.0:
				out[i] = (out[i] as Vector3) + (g.right as Vector3) * (60.0 - d + float(g.half) + 5.0)
	return out


func _nearest(rc: RaceCourse, at: Vector3) -> int:
	var best := 0
	for i in rc.line.size():
		if (rc.line[i] as Vector3).distance_to(at) < (rc.line[best] as Vector3).distance_to(at):
			best = i
	return best


func _run(rc: RaceCourse, laps: RaceLaps, path: Array, key := "you") -> Array:
	var ev: Array = []
	for i in path.size() - 1:
		ev.append_array(rc.step_racer(laps, key, path[i], path[i + 1], key == "you"))
	return ev


func _types(ev: Array, type: String) -> Array:
	return ev.filter(func(e): return str(e.type) == type)


# ---- the course file ---------------------------------------------------------------

func test_the_first_course_is_a_file_by_dorrins_yard() -> void:
	assert_true(RaceCourse.ids().has("hoodoo_run"), "the course file")
	var c := RaceCourse.load_course("hoodoo_run")
	assert_eq(str(c.world), "port_desert")
	assert_eq(int(c.laps), 2)
	assert_between(c.gates.size(), 5, 7, "a start/finish line and 4 to 6 checkpoints")
	assert_gt(c.line.size(), 20, "a racing line")
	var yard := Vector2(-900, -620)
	var start := Vector2(float(c.gates[0].at[0]), float(c.gates[0].at[1]))
	assert_lt(start.distance_to(yard), 250.0, "the start line is a short drive from Dorrin's yard")
	var rc := _course(c)
	var lap := 0.0
	for i in rc.line.size():
		lap += (rc.line[i] as Vector3).distance_to(rc.line[(i + 1) % rc.line.size()])
	assert_between(lap / float(HoverModel.load_config("speeder").max_speed), 55.0, 95.0, "a lap is 60 to 90 s at a stock speeder's top speed")


func test_the_courses_rock_towers_are_hoodoos_off_the_line() -> void:
	var c := RaceCourse.load_course("hoodoo_run")
	var near := 0
	for hd in DesertLandforms.spire_spots(DesertLandforms.load_data()):
		var at: Vector2 = hd.map
		var best := INF
		for i in c.line.size():
			var a := Vector2(float(c.line[i][0]), float(c.line[i][1]))
			var b := Vector2(float(c.line[(i + 1) % c.line.size()][0]), float(c.line[(i + 1) % c.line.size()][1]))
			best = minf(best, Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at))
		if best < 80.0:
			near += 1
			assert_gt(best - float(hd.radius), 12.0, "a tower's skirt beside the line, not on it")
	assert_eq(near, 5, "five towers to weave round")


func test_boulders_keep_off_the_line() -> void:
	var circles := RaceCourse.clear_circles("port_desert")
	assert_gt(circles.size(), 20, "clear circles along the racing line and round the gates")
	assert_eq(RaceCourse.clear_circles("moon").size(), 0, "none on a world with no course")


# ---- counting laps -----------------------------------------------------------------

func test_every_gate_in_order_and_back_over_the_line_is_a_lap() -> void:
	var rc := _course(RaceCourse.load_course("hoodoo_run"))
	var laps := rc.new_laps()
	var ev := _run(rc, laps, _path(rc, 2))
	assert_eq(_types(ev, "start").size(), 1, "off the grid: lap 1 on")
	assert_eq(_types(ev, "gate").size(), (rc.gates.size() - 1) * 2, "every checkpoint, both laps")
	assert_eq(_types(ev, "lap").size(), 2, "two laps")
	assert_eq(_types(ev, "finish").size(), 1, "and finished")
	assert_true(laps.finished("you"))


func test_skip_a_gate_and_the_lap_does_not_count() -> void:
	var rc := _course(RaceCourse.load_course("hoodoo_run"))
	var laps := rc.new_laps()
	var ev := _run(rc, laps, _path(rc, 1, 3))
	assert_eq(_types(ev, "lap").size(), 0, "no lap with gate 3 missed")
	assert_eq(_types(ev, "missed").size(), 1, "over the line with a gate to go")
	assert_eq(laps.next_gate("you"), 3, "the pointer still wants gate 3")


func test_the_line_crossed_backwards_counts_nothing() -> void:
	var rc := _course(RaceCourse.load_course("hoodoo_run"))
	var laps := rc.new_laps()
	var g: Dictionary = rc.gates[0]
	var ahead: Vector3 = (g.pos as Vector3) + (g.fwd as Vector3) * 10.0
	var behind: Vector3 = (g.pos as Vector3) - (g.fwd as Vector3) * 10.0
	var ev := rc.step_racer(laps, "you", ahead, behind, true)
	assert_eq(ev.size(), 0, "backwards: nothing")
	assert_false(laps.racers.you.started, "and the race is not on")
	assert_eq(rc.gate_state(0), "rest", "nor does the line flash")


func test_a_gate_says_who_went_through_and_how_far_off_centre() -> void:
	var rc := _course(RaceCourse.load_course("hoodoo_run"))
	var laps := rc.new_laps()
	var g: Dictionary = rc.gates[0]
	var off: Vector3 = (g.right as Vector3) * float(g.half) * 0.5
	var ev := rc.step_racer(laps, "racer_2", (g.pos as Vector3) - (g.fwd as Vector3) * 3.0 + off,
		(g.pos as Vector3) + (g.fwd as Vector3) * 3.0 + off, false)
	var pass_ev: Array = _types(ev, "pass")
	assert_eq(pass_ev.size(), 1)
	assert_eq(str(pass_ev[0].key), "racer_2", "who")
	assert_almost_eq(float(pass_ev[0].off), 0.5, 0.05, "half way out from the centre")
	assert_eq(rc.gate_state(0), "pass", "it flashes for anyone")
	rc.step_racer(laps, "you", (g.pos as Vector3) - (g.fwd as Vector3) * 3.0, (g.pos as Vector3) + (g.fwd as Vector3) * 3.0, true)
	assert_eq(rc.gate_state(0), "you", "green for you")
	assert_almost_eq(rc.gates[0].half * 2.0, 26.0, 0.01)


func test_outside_the_antennas_is_not_through_the_gate() -> void:
	var rc := _course(RaceCourse.load_course("hoodoo_run"))
	var laps := rc.new_laps()
	var g: Dictionary = rc.gates[0]
	var wide: Vector3 = (g.right as Vector3) * (float(g.half) + 4.0)
	assert_eq(rc.step_racer(laps, "you", (g.pos as Vector3) - (g.fwd as Vector3) * 3.0 + wide,
		(g.pos as Vector3) + (g.fwd as Vector3) * 3.0 + wide).size(), 0, "round the side: nothing")


func test_a_second_course_file_works_with_no_code() -> void:
	var square := {
		"id": "test_square", "label": "Test Square", "world": "test", "laps": 1, "gate_width": 20.0,
		"gates": [{ "id": "start", "at": [0, 300] }, { "id": "c1", "at": [300, 0] }, { "id": "c2", "at": [0, -300] }, { "id": "c3", "at": [-300, 0] }],
		"line": [],
	}
	for k in 24:
		var a := deg_to_rad(90.0 - k * 15.0)
		square.line.append([cos(a) * 300.0, sin(a) * 300.0])
	var rc := _course(square)
	assert_eq(rc.gates.size(), 4)
	var laps := rc.new_laps()
	var ev := _run(rc, laps, _path(rc, 1))
	assert_eq(_types(ev, "lap").size(), 1, "one lap of a course that is not in any file")
	assert_true(laps.finished("you"))


# ---- masts, grid, drawing ------------------------------------------------------------

func test_the_antenna_masts_are_solid() -> void:
	var rc := _course(RaceCourse.load_course("hoodoo_run"))
	var g: Dictionary = rc.gates[2]
	var mast: Vector3 = (g.pos as Vector3) + (g.right as Vector3) * float(g.half)
	assert_ne(ground.hit(mast + Vector3(0, 1.0, 0), 1.3), "", "a speeder bumps the mast")
	assert_eq(ground.hit((g.pos as Vector3) + Vector3(0, 1.0, 0), 1.3), "", "and drives through the middle")


func test_the_grid_is_behind_the_line_facing_through_it() -> void:
	var rc := _course(RaceCourse.load_course("hoodoo_run"))
	var g: Dictionary = rc.gates[0]
	assert_eq(rc.grid_slots(), 4, "four slots: you and three racers")
	for i in 4:
		var s := rc.grid_slot(i)
		assert_lt(((s.pos as Vector3) - (g.pos as Vector3)).dot(g.fwd), -5.0, "slot %d is behind the line" % i)
		var m := HoverModel.new(HoverModel.load_config("speeder"), ground)
		m.place(s.pos, float(s.yaw))
		assert_gt(m.forward().dot(g.fwd), 0.99, "slot %d faces through it" % i)


func test_gates_are_drawn_only_when_asked_and_flash_back_to_rest() -> void:
	var rc := _course(RaceCourse.load_course("hoodoo_run"))
	assert_false(rc.built, "nothing drawn with nobody near")
	rc.build_gates()
	assert_true(rc.built)
	assert_eq(rc.get_children().size(), rc.gates.size(), "one root per gate")
	rc.flash(1, true)
	assert_eq(rc.gate_state(1), "you")
	await wait_seconds(1.3)
	assert_eq(rc.gate_state(1), "rest", "faded back")
	rc.drop_gates()
	await wait_physics_frames(2)
	assert_false(rc.built)


# ---- flat ground -----------------------------------------------------------------

## The highest and lowest sand (m above the ball) across a footprint round gate
## `g` of course `c`: `back` metres behind the line to 8 m past it, 15 m either side.
## Measured on the ground (the far side's map is stretched across).
func _relief(sp: PlanetSphere, c: Dictionary, gi: int, back: float) -> float:
	var fr := _gate_frame(sp, c, gi)
	var lo := INF
	var hi := -INF
	for i in 13:
		for j in 9:
			var q: Vector3 = fr[0] + fr[2] * lerpf(-15.0, 15.0, i / 12.0) + fr[1] * lerpf(-back, 8.0, j / 8.0)
			var h := sp.elevation((q - sp.center).normalized())
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


## Gate `gi` of course `c` on the bare ball: [point, the way the line runs, across it].
func _gate_frame(sp: PlanetSphere, c: Dictionary, gi: int) -> Array:
	var line2: Array = []
	for p in c.line:
		line2.append(Vector2(float(p[0]), float(p[1])))
	var gd := RaceCourse._ground_dir(sp, line2, Vector2(float(c.gates[gi].at[0]), float(c.gates[gi].at[1])))
	var at: Vector3 = gd[1]
	var fwd: Vector3 = gd[0]
	return [at, fwd, fwd.cross((at - sp.center).normalized()).normalized()]


## Gates (and the start's grid) sit where the dunes are nearly level already, so the
## pad under them never cuts a notch through a crest.
func test_every_gate_is_on_nearly_flat_sand() -> void:
	var planet := PlanetGen.build(PlanetGen.home_id())
	var sp := PlanetTerrain.for_planet(planet).sphere
	sp.flat_sites = []
	# The sand as the dunes make it, but for the level sand round a mountain a
	# course runs through (the gates at a tunnel's mouths stand on it) and a
	# course's own level floors (the far side's wash and straights).
	sp.flat_sites = DesertLandforms.mountain_flat_sites(planet, sp) + RaceCourse.floor_sites("port_desert", sp)
	for c in RaceCourse.courses_for("port_desert"):
		assert_lt(_relief(sp, c, 0, 40.0), 2.5, "%s: the start line and its grid are on flat sand" % c.id)
		for gi in range(1, c.gates.size()):
			assert_lt(_relief(sp, c, gi, 8.0), 3.5, "%s %s: on flat sand" % [c.id, c.gates[gi].id])


## How far apart (m, up the ball) the sand under gate `gi`'s two antennas is.
func _across(sp: PlanetSphere, c: Dictionary, gi: int) -> float:
	var fr := _gate_frame(sp, c, gi)
	var right: Vector3 = fr[2] * float(c.get("gate_width", 26.0)) * 0.5
	return absf(sp.elevation((fr[0] + right - sp.center).normalized()) - sp.elevation((fr[0] - right - sp.center).normalized()))


## And the planet levels a pad under each, so both antennas stand at one height.
## A gate in a course range's tunnel stands on the range's level floor instead:
## one plane for the whole range, so far from its middle it tilts with the ball
## a few degrees along the line, but the two antennas still stand level.
func test_the_planet_levels_a_pad_under_every_gate() -> void:
	var planet := PlanetGen.build(PlanetGen.home_id())
	var sp := PlanetTerrain.for_planet(planet).sphere
	var ranges: Array = DesertLandforms.mountain_flat_sites(planet, sp)
	for c in RaceCourse.courses_for("port_desert"):
		assert_lt(_relief(sp, c, 0, 25.0), 0.3, "%s: the start line and grid are level" % c.id)
		for gi in range(1, c.gates.size()):
			var at := Vector2(float(c.gates[gi].at[0]), float(c.gates[gi].at[1]))
			if ranges.any(func(site): return (site.rect as Rect2).has_point(at) if site.get("frame") == null \
					else sp._frame_dist(site.frame, at.x, at.y) <= 0.0):
				assert_lt(_across(sp, c, gi), 0.3, "%s %s: both antennas level on the range's floor" % [c.id, c.gates[gi].id])
			else:
				assert_lt(_relief(sp, c, gi, 4.0), 0.3, "%s %s: level" % [c.id, c.gates[gi].id])
	assert_eq(RaceCourse.flat_sites("moon", sp).size(), 0, "none on a world with no course")
