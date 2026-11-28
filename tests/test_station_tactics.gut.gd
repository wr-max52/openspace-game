extends GutTest
## How the station's Remnant fight aboard (src/systems/world/station_tactics.gd):
## every walk routed out of the room by its door and round the walkway (never
## through a wall into a corner), cover behind the furniture of their own room,
## and on the alarm: cover first, then out of the room to hunt.

const TownDemo := preload("res://scenes/town_demo.gd")
const StationRemnant := preload("res://src/systems/world/station_remnant.gd")
const HOST := "ringed_giant"
const CITY := "orbital_station"

var _sphere_before: PlanetSphere


func before_each() -> void:
	WorldState.reset()
	_sphere_before = PlanetSphere.current


func after_each() -> void:
	PlanetSphere.current = _sphere_before
	GameFlow.reset()
	WorldState.reset()


func _tactics() -> StationTactics:
	return StationTactics.new(null, StationHull.for_id(CITY))


func _top(who: String) -> Array:
	return StationRemnant.top_posts(StationHull.for_id(CITY)).filter(func(p): return str(p.soldier) == who)


## Follow route_local from `from` to `to`, a waypoint at a time: [the points walked
## through, whether it got there].
static func _walk(t: StationTactics, from: Vector3, to: Vector3, steps := 120) -> Array:
	var p := from
	var pts: Array = [p]
	for i in steps:
		var nxt := t.route_local(p, to)
		if nxt.distance_to(p) < 0.05:
			break
		p = nxt
		pts.append(p)
		if p.distance_to(to) < 0.05:
			return [pts, true]
	return [pts, p.distance_to(to) < 0.05]


## Every leg of `pts` crosses only open floor: the rooms in `rooms_ok` (keys), the
## walkway and nothing else (no other room, no wall, no locked room).
static func _legs_clear(t: StationTactics, pts: Array, rooms_ok: Array) -> String:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		for j in 21:
			var q := a.lerp(b, j / 20.0)
			var w := t.where(q)
			var k := str(w.kind)
			if k == "walk":
				continue
			if k == "room" and rooms_ok.has(StationTactics.area_key(w)):
				continue
			return "leg %d crosses %s at %s" % [i, StationTactics.area_key(w) if k == "room" else k, q]
	return ""


# ------------------------------------------------------------------ where

func test_it_knows_a_room_the_walkway_and_the_open_middle() -> void:
	var t := _tactics()
	var bar: Dictionary = _top("off_duty")[0]
	var w := t.where(bar.at)
	assert_eq(str(w.kind), "room")
	assert_eq(str(w.room.use), "barracks")
	var tw: Dictionary = StationHull.for_id(CITY).tower("main")
	var y := float((tw.floors as Array).back().y)
	assert_eq(str(t.where(Vector3(tw.c.x + t.ring_r(), y, tw.c.y)).kind), "walk")
	assert_eq(str(t.where(Vector3(tw.c.x, y, tw.c.y)).kind), "gap")
	assert_eq(str(t.where(Vector3(tw.c.x, y + 400.0, tw.c.y)).kind), "none")


# ------------------------------------------------------------------ route

func test_from_a_barracks_to_the_bridge_out_the_door_round_the_walkway_and_in() -> void:
	var t := _tactics()
	var from: Vector3 = _top("off_duty")[0].at
	var to: Vector3 = _top("general")[0].at
	to.y = from.y
	var r := _walk(t, from, to)
	assert_true(r[1], "gets there")
	var ok := [StationTactics.area_key(t.where(from)), StationTactics.area_key(t.where(to))]
	assert_eq(_legs_clear(t, r[0], ok), "", "never through a wall")
	var on_walk := (r[0] as Array).filter(func(p): return str(t.where(p).kind) == "walk")
	assert_gt(on_walk.size(), 2, "round the walkway")


func test_a_corner_of_a_room_walks_to_its_door_first() -> void:
	var t := _tactics()
	var bar: Dictionary = _top("off_duty")[0]
	var w := t.where(bar.at)
	var room: Dictionary = w.room
	# A back corner, by the window (the glass is round), against a side wall.
	var ang := float(room.half) * 0.93
	var rc := float(room.r1) - 1.5
	var corner := StationTactics.area_frame(w) * Vector3(rc * cos(ang), 0, rc * sin(ang))
	assert_eq(StationTactics.area_key(t.where(corner)), StationTactics.area_key(w), "the corner is in the room")
	var outside: Vector3 = StationTactics.polar(w, float(room.a) + PI * 0.5, t.ring_r())
	var first := t.route_local(corner, outside)
	var fw := t.where(first)
	assert_eq(StationTactics.area_key(fw), StationTactics.area_key(w), "still in the room")
	assert_lt(absf(wrapf(float(fw.a) - float(room.a), -PI, PI)) * float(fw.r), 0.1, "on its middle line")
	assert_almost_eq(float(fw.r), float(room.r0) + t.n("door_in_m", 0.8), 0.05, "just inside the door")
	var r := _walk(t, corner, outside)
	assert_true(r[1])
	assert_eq(_legs_clear(t, r[0], [StationTactics.area_key(w)]), "")


func test_another_floor_is_as_far_as_the_walkway_facing_it() -> void:
	var t := _tactics()
	var from: Vector3 = _top("off_duty")[0].at
	var deck: Array = StationRemnant.posts(StationHull.for_id(CITY)).filter(func(p): return str(p.soldier) == "commander")
	assert_eq(deck.size(), 1)
	var r := _walk(t, from, deck[0].at)
	assert_false(r[1], "no stairs or elevator for them")
	var last: Vector3 = (r[0] as Array).back()
	var w := t.where(last)
	assert_eq(str(w.kind), "walk", "waiting on the walkway")
	assert_eq(str(w.tower.id), "main")
	assert_eq(int(w.fi), (StationHull.for_id(CITY).tower("main").floors as Array).size() - 1, "on his own floor")
	assert_eq(_legs_clear(t, r[0], [StationTactics.area_key(t.where(from))]), "")


func test_the_walkway_route_clears_the_decks_barricade_and_checkpoint() -> void:
	var t := _tactics()
	var h := StationHull.for_id(CITY)
	var rooms := StationRemnant.rooms(h)
	assert_gt(rooms.size(), 4)
	var a: Dictionary = rooms[0]
	var b: Dictionary = rooms[rooms.size() / 2]
	var from: Vector3 = (a.frame as Transform3D) * Vector3(float(a.r0) + 6.0, 0, 0)
	var to: Vector3 = (b.frame as Transform3D) * Vector3(float(b.r0) + 6.0, 0, 0)
	var r := _walk(t, from, to)
	assert_true(r[1])
	# Barricades: 0.7 m deep at gap_r + walk - 3.5; checkpoint posts at gap_r + walk - 1.2.
	var rr := h.gap_r + h.walk
	for p in r[0]:
		var w := t.where(p)
		if str(w.kind) == "walk":
			assert_between(float(w.r), rr - 3.5 + 0.35 + 0.4, rr - 1.2 - 0.18 - 0.4, "a walkway point clear of both")


# ------------------------------------------------------------------ in the scene

func _host(brains := false) -> Node:
	GameFlow.reset()
	GameFlow.resumed = true
	GameFlow.planet_id = HOST
	GameFlow.change_scene = func(_p: String) -> void: pass
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = brains
	add_child_autofree(t)
	return t


func _city(t):
	for i in 120:
		for s in t.stations:
			if str(s.id) == CITY:
				return s
		await wait_physics_frames(1)
	return null


func _fill(s) -> void:
	for i in 400:
		for k in 300:
			s._step_fill()
		var done := true
		for ff in s.fill_floors:
			if not bool(ff.built):
				done = false
		if done:
			break
		await wait_physics_frames(1)
	await wait_physics_frames(2)


func test_cover_in_a_barracks_is_behind_its_furniture_from_the_door() -> void:
	var t = _host()
	var s = await _city(t)
	assert_not_null(s)
	if s == null:
		return
	await _fill(s)
	var tac := StationTactics.new(s)
	var taken: Array = []
	for p in _top("off_duty"):
		var body := Node3D.new()
		add_child_autofree(body)
		body.global_position = s.to_world(p.at)
		var w := tac.where(p.at)
		var door: Vector3 = s.to_world(StationTactics.polar(w, float(w.room.a), tac.ring_r()))
		var spot := tac.cover(body, door, taken)
		assert_ne(spot, Vector3.INF, "%s finds cover" % p.id)
		if spot == Vector3.INF:
			continue
		var sw := tac.where(s.to_local_point(spot))
		assert_eq(StationTactics.area_key(sw), StationTactics.area_key(w), "%s's cover is in his own room" % p.id)
		# Something solid between the spot and the door, at crouching height.
		var space: PhysicsDirectSpaceState3D = s.get_world_3d().direct_space_state
		var up: Vector3 = s.frame.basis.y
		var q := PhysicsRayQueryParameters3D.create(spot + up * 0.6, door + up * 0.6)
		assert_false(space.intersect_ray(q).is_empty(), "%s's cover hides him from the door" % p.id)
		for o in taken:
			assert_gt((o as Vector3).distance_to(spot), 1.0, "two never share a spot")
		taken.append(spot)


func test_on_the_alarm_they_take_cover_in_the_barracks_then_leave_it_to_hunt() -> void:
	var t = _host(true)
	var s = await _city(t)
	assert_not_null(s)
	if s == null or s.remnant == null:
		return
	await _fill(s)
	if not s.remnant.woke:
		s.remnant._wake()
	for i in 240:
		await wait_physics_frames(1)
		if s.remnant._queue.is_empty():
			break
	var gar: Garrison = s.remnant.top_garrison
	assert_not_null(gar, "the top floor's garrison")
	if gar == null:
		return
	assert_not_null(gar.tactics, "with the station's tactics")
	var tac: StationTactics = gar.tactics
	var off: Array = s.remnant.troopers.filter(func(g): return str(g.profile.get("id", "")) == "station_off_duty")
	assert_eq(off.size(), 8)
	# The alarm: someone saw you on the walkway outside the first barracks. You are
	# then a floor below it, near (the alarm holds) and out of sight (so they hunt),
	# held there; a camera at the barracks door keeps them awake (StationRemnant._sleep).
	var w0 := tac.where(s.to_local_point(off[0].global_position))
	var seen: Vector3 = s.to_world(StationTactics.polar(w0, float(w0.room.a) + 0.6, tac.ring_r()))
	var cam := Camera3D.new()
	add_child_autofree(cam)
	cam.global_position = s.to_world(StationTactics.polar(w0, float(w0.room.a), float(w0.room.r0)) + Vector3(0, 2.0, 0))
	cam.make_current()
	var p = t.get("_player")
	if p != null:
		p.process_mode = Node.PROCESS_MODE_DISABLED
		var below := StationTactics.polar(w0, float(w0.room.a), float(w0.room.r0) + 10.0)
		below.y -= StationHull.for_id(CITY).floor_h
		p.global_position = s.to_world(below + Vector3(0, 0.1, 0))
	gar.join_alarm(seen, "test")
	var covered := {}
	var out_of_room := {}
	var homes := {}
	for g in off:
		homes[g] = StationTactics.area_key(tac.where(s.to_local_point(g.global_position)))
	for i in 60 * 30:
		await wait_physics_frames(1)
		for g in off:
			if not is_instance_valid(g) or g.dead or not gar.brains.has(g):
				continue
			var b: GuardBrain = gar.brains[g]
			if b.cover != Vector3.INF and g.global_position.distance_to(b.cover) < 1.2 and not b.hunting():
				covered[g] = true
			var w := tac.where(s.to_local_point(g.global_position))
			if covered.has(g) and StationTactics.area_key(w) != homes[g] and b.hunting():
				out_of_room[g] = true
		if out_of_room.size() >= 2:
			break
	assert_gte(covered.size(), 4, "at least half of them reached cover in their own room (got %d)" % covered.size())
	assert_gte(out_of_room.size(), 2, "and after a while they leave it to hunt (got %d)" % out_of_room.size())
	var stuck := 0
	for g in off:
		stuck += int(g.stuck_events)
	assert_lt(stuck, 8 * 4, "nobody pinned in a corner over and over (stuck events %d)" % stuck)
	gut.p("station tactics: %d of 8 reached cover, %d left the room to hunt, %d stuck events" % [covered.size(), out_of_room.size(), stuck])
