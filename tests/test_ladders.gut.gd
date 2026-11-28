extends GutTest
## Climbing ladders: the registry (src/systems/world/ladders.gd), the climb
## (src/systems/player/ladder_climb.gd), the body on it (CharacterBody.climb_on),
## the pose (BodyAnimator.climb_pose) and the ladders the skimmer outposts and
## the station fill put down (StationHull.ladders, StationFill.ladders).

const Ladders := preload("res://src/systems/world/ladders.gd")
const LadderClimb := preload("res://src/systems/player/ladder_climb.gd")
const PlayerClimber := preload("res://src/systems/player/player_climber.gd")
const CharBody := preload("res://src/systems/player/character_body.gd")
const StationFill := preload("res://src/systems/world/station_fill.gd")
const TownBuildings := preload("res://src/systems/world/town_buildings.gd")
const DT := 1.0 / 60.0


## A ladder 4 m high at the origin, climbed facing +X.
func _ladder(h := 4.0) -> Dictionary:
	return Ladders.world_of(Ladders.spec(Vector3.ZERO, Vector3.RIGHT, h))


func _run(c, secs: float, climb_in: float, clear := true) -> Dictionary:
	var r := {}
	var steps := int(secs / DT)
	for i in steps:
		r = c.step(DT, climb_in, false, clear)
		if r.done or r.let_go:
			return r
	return r


func test_a_spec_faces_the_rungs_and_stands_back_from_them() -> void:
	var w := _ladder()
	assert_almost_eq((w.fwd as Vector3).distance_to(Vector3.RIGHT), 0.0, 0.001, "faced along +X")
	assert_almost_eq((w.up as Vector3).distance_to(Vector3.UP), 0.0, 0.001, "up the ladder")
	var s := Ladders.stand_at(w, 1.0)
	assert_almost_eq(s.x, -Ladders.STAND, 0.001, "hung back from the rungs")
	assert_almost_eq(s.y, 1.0, 0.001, "feet a metre up")
	var e := Ladders.exit_at(w)
	assert_almost_eq(e.x, Ladders.EXIT, 0.001, "out past the rungs at the top")
	assert_almost_eq(e.y, 4.0, 0.001, "on the floor it leads to")
	assert_true(Ladders.at_foot(w, Vector3(-0.6, 0, 0.1)), "in front of it at its foot")
	assert_false(Ladders.at_foot(w, Vector3(-0.6, 0, 1.2)), "off to one side")
	assert_false(Ladders.at_foot(w, Vector3(0.6, 0, 0)), "behind its rungs")
	assert_true(Ladders.at_top(w, Vector3(1.0, 4.0, 0)), "on the floor at its top")
	assert_false(Ladders.at_top(w, Vector3(1.0, 0.0, 0)), "not at its foot")


func test_hold_w_climbs_rung_over_rung_and_out_at_the_top() -> void:
	var w := _ladder()
	var c = LadderClimb.new()
	c.start_bottom(w, Vector3(-0.7, 0, 0.1))
	assert_eq(c.phase_name(), "MOUNT", "stepping on")
	var r := _run(c, 0.4, 1.0)
	assert_eq(c.phase_name(), "CLIMB", "on the rungs")
	assert_almost_eq((r.pos as Vector3).x, -Ladders.STAND, 0.01, "hung square in front of it")
	var u0: float = c.u
	_run(c, 1.0, 1.0)
	assert_almost_eq(c.u - u0, c.n("climb_speed", 1.8), 0.25, "climbs at its speed")
	r = _run(c, 6.0, 1.0)
	assert_true(r.done, "off at the top")
	assert_eq(c.phase_name(), "OFF")
	assert_almost_eq((r.pos as Vector3).distance_to(Ladders.exit_at(w)), 0.0, 0.01, "stood on the floor past it")
	assert_eq(c.climbs, 1)


func test_let_go_of_w_and_you_hang_there() -> void:
	var c = LadderClimb.new()
	c.start_bottom(_ladder(), Vector3(-0.5, 0, 0))
	_run(c, 1.2, 1.0)
	_run(c, 0.3, 0.0)
	var u: float = c.u
	_run(c, 1.0, 0.0)
	assert_almost_eq(c.u, u, 0.001, "not sliding, not climbing")
	assert_eq(c.phase_name(), "CLIMB")


func test_no_room_at_the_top_and_you_hang_from_the_top_rungs() -> void:
	var c = LadderClimb.new()
	c.start_bottom(_ladder(), Vector3(-0.5, 0, 0))
	var r := _run(c, 6.0, 1.0, false)
	assert_false(r.done, "still on it")
	assert_eq(c.phase_name(), "CLIMB")
	assert_almost_eq(c.u, c.top_u(), 0.001, "as high as the hands go")


func test_e_at_the_top_swings_you_round_onto_it_then_s_slides_you_down() -> void:
	var w := _ladder(6.0)
	var c = LadderClimb.new()
	c.start_top(w, Vector3(1.0, 6.0, 0), Vector3.LEFT)       # walked up to it, facing the hole
	assert_eq(c.phase_name(), "TOP_IN")
	assert_almost_eq(c.facing().distance_to(Vector3.LEFT), 0.0, 0.01, "facing the way you came")
	_run(c, 1.0, 0.0)
	assert_eq(c.phase_name(), "CLIMB", "on the rungs")
	assert_almost_eq(c.u, c.top_u(), 0.01, "a few rungs down from the top")
	assert_almost_eq(c.facing().distance_to(Vector3.RIGHT), 0.0, 0.01, "turned round to face it")
	c.step(DT, -1.0, false)
	assert_has(c.events, "slide", "a slide begins")
	_run(c, 0.6, -1.0)
	assert_lt(c.speed, -3.0, "speeding up down the rails")
	assert_true(c.sliding)
	var r := _run(c, 4.0, -1.0)
	assert_true(r.done, "off at the foot")
	assert_almost_eq((r.pos as Vector3).y, 0.0, 0.01, "on the floor at the foot")
	assert_eq(c.slides, 1)


func test_let_go_of_s_and_the_slide_grips() -> void:
	var c = LadderClimb.new()
	c.start_top(_ladder(10.0), Vector3(1.0, 10.0, 0), Vector3.LEFT)
	_run(c, 1.0, 0.0)
	_run(c, 0.5, -1.0)
	var r := _run(c, 0.8, 0.0)
	assert_false(r.done)
	assert_eq(c.speed, 0.0, "stopped")
	assert_false(c.sliding)
	assert_gt(c.u, 1.0, "partway down")


func test_space_lets_go_backward() -> void:
	var c = LadderClimb.new()
	c.start_bottom(_ladder(), Vector3(-0.5, 0, 0))
	_run(c, 1.2, 1.0)
	var r: Dictionary = c.step(DT, 0.0, true)
	assert_true(r.let_go)
	assert_eq(c.phase_name(), "OFF")
	assert_lt((r.vel as Vector3).x, -1.0, "pushed back off the rungs")
	assert_gt((r.vel as Vector3).y, 0.0, "and a little up")


func test_the_registry_finds_near_ladders_and_drops_freed_ones() -> void:
	Ladders.clear()
	var anchor := Node3D.new()
	add_child(anchor)
	anchor.position = Vector3(100, 0, 0)
	Ladders.add(anchor, Ladders.spec(Vector3.ZERO, Vector3.RIGHT, 4.0))
	assert_eq(Ladders.near(Vector3(99.4, 0, 0), 2.0).size(), 1, "found by its foot")
	assert_eq(Ladders.near(Vector3(99.4, 3.5, 0), 2.0).size(), 1, "and up its length")
	assert_eq(Ladders.near(Vector3(0, 0, 0), 2.0).size(), 0, "not from far off")
	var w: Dictionary = Ladders.near(Vector3(99.4, 0, 0), 2.0)[0]
	assert_almost_eq((w.foot as Vector3).x, 100.0, 0.001, "in the world, through its anchor")
	anchor.free()
	assert_eq(Ladders.near(Vector3(99.4, 0, 0), 2.0).size(), 0, "gone with its anchor")
	assert_eq(Ladders.count(), 0)


func test_the_skimmer_outposts_roof_and_gantry_ladders_climb() -> void:
	var h := StationHull.for_id("skimmer_outpost")
	assert_eq(h.ladders.size(), 2, "the roof's and the gantry's")
	for s in h.ladders:
		var w := Ladders.world_of(s)
		var foot := Ladders.stand_at(w, 0.0)
		assert_true(_inside(h, foot - Vector3(0, 0.3, 0)), "a floor under its foot")
		var climb_path := true
		var u := 0.3
		while u < float(w.h) - 0.5:
			var at := Ladders.stand_at(w, u) + Vector3(0, 0.9, 0)
			if _inside(h, at):
				climb_path = false
			u += 0.5
		assert_true(climb_path, "nothing in the way up it")
		var out := Ladders.exit_at(w)
		assert_true(_inside(h, out - Vector3(0, 0.3, 0)), "a floor to climb out on")
		assert_false(_inside(h, out + Vector3(0, 0.9, 0)), "room to stand there")


func test_stacked_shacks_and_engine_rooms_note_their_ladders() -> void:
	var hull := StationHull.for_id("orbital_station")
	var fill = StationFill.new(TownBuildings.new(LookMaterials.new(), null), hull, func(_f: String) -> Material: return StandardMaterial3D.new())
	fill.solids_only = true
	var t: Dictionary = hull.towers[0]
	var by_floor := {}
	for i in (t.floors as Array).size():
		var fid := str(t.floors[i].id)
		if not (fid in ["engines", "homes"]) or fill.floor_cfg(fid).is_empty():
			continue
		var before: int = fill.ladders.size()
		var node := Node3D.new()
		add_child_autofree(node)
		if fill.begin(node, t, i):
			for k in 2000:
				if fill.step(50.0):
					break
		by_floor[fid] = fill.ladders.slice(before)
	assert_eq((by_floor.get("engines", []) as Array).size(), 8, "a catwalk ladder in each engine room")
	for s in by_floor.get("engines", []):
		assert_almost_eq(float(s.h), 6.0, 0.01, "up to the catwalk")
	assert_gt((by_floor.get("homes", []) as Array).size(), 20, "the favela's stacked shacks and containers")
	for s in by_floor.get("homes", []):
		assert_between(float(s.h), 2.0, 4.0, "up onto a lower roof")


func test_the_climb_pose_alternates_hands_and_feet() -> void:
	var a := BodyAnimator.climb_pose(0.0)
	var b := BodyAnimator.climb_pose(BodyAnimator.CLIMB_RUNG)       # half a cycle on
	assert_ne(a.joints.l_hip, a.joints.r_hip, "one foot higher than the other")
	assert_almost_eq((a.joints.l_hip as Vector3).x, (b.joints.r_hip as Vector3).x, 0.01, "the feet trade places each rung")
	assert_almost_eq((a.joints.l_shoulder as Vector3).x, (b.joints.r_shoulder as Vector3).x, 0.01, "and the hands")
	assert_lt((a.joints.l_shoulder as Vector3).x, -100.0, "arms up on the rungs")
	var anim := BodyAnimator.new()
	var o := {}
	for i in 30:
		o = anim.step(DT, { "grounded": false, "climb": 1.0, "climb_u": 0.0 })
	assert_eq(o.state, "CLIMB")
	assert_almost_eq((o.joints.l_shoulder as Vector3).x, (a.joints.l_shoulder as Vector3).x, 1.0, "posed as the climb says")


func test_walking_into_a_ladder_holding_w_gets_you_on() -> void:
	var p := CharBody.new()
	p.can_climb = true
	add_child_autofree(p)
	var w := _ladder()
	p.set_command(Vector2(0, 1), false, false, false)
	p.rotation.y = 0.0                                    # W walks along +Z: past it
	assert_false(PlayerClimber.walking_into(p, w), "walking along it, not into it")
	p.rotation.y = PI * 0.5                               # W walks along +X: at its rungs
	assert_true(PlayerClimber.walking_into(p, w), "walking at its rungs")
	p.set_command(Vector2(0, -1), false, false, false)
	assert_false(PlayerClimber.walking_into(p, w), "backing off it")


func test_the_body_climbs_and_climbs_out() -> void:
	var p := CharBody.new()
	p.can_climb = true
	add_child_autofree(p)
	var w := _ladder(3.0)
	p.global_position = Vector3(-0.6, 0, 0)
	assert_true(p.climb_on(w, false), "on it")
	assert_true(p.climbing)
	p.set_command(Vector2(0, 1), false, false, false)
	for i in 300:
		p._physics_process(DT)
		if not p.climbing:
			break
	assert_false(p.climbing, "climbed out")
	assert_almost_eq(p.global_position.distance_to(Ladders.exit_at(w)), 0.0, 0.05, "stood on the floor at the top")
	assert_eq(p.velocity, Vector3.ZERO, "no fall out of it")


static func _inside(h: StationHull, p: Vector3) -> bool:
	for part in h.parts:
		if not (str(part.kind) in ["solid", "floor"]):
			continue
		var l := (part.xf as Transform3D).affine_inverse() * p
		var e: Vector3 = (part.size as Vector3) * 0.5 + Vector3(0.05, 0.05, 0.05)
		if absf(l.x) <= e.x and absf(l.y) <= e.y and absf(l.z) <= e.z:
			return true
	return false
