extends GutTest
## Issue #314: the Remnant on the ring station's top floor (content/core/stations/
## orbital_station.json "remnant" "top"): the general and an honour guard either side
## of him on the bridge, troopers off duty in both barracks. They are the deck's
## place's people: the station falls only once they are dead too, and the locals'
## guards take their posts with the deck's.

const TownDemo := preload("res://scenes/town_demo.gd")
const StationRemnant := preload("res://src/systems/world/station_remnant.gd")
const HOST := "ringed_giant"
const CITY := "orbital_station"
const PLACE := "station_orbital_station"

var _sphere_before: PlanetSphere


func before_each() -> void:
	WorldState.reset()
	_sphere_before = PlanetSphere.current


func after_each() -> void:
	PlanetSphere.current = _sphere_before
	GameFlow.reset()
	WorldState.reset()


func _hull() -> StationHull:
	return StationHull.for_id(CITY)


func _host() -> Node:
	GameFlow.reset()
	GameFlow.resumed = true
	GameFlow.planet_id = HOST
	GameFlow.change_scene = func(_p: String) -> void: pass
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	return t


func _city(t):
	for i in 120:
		for s in t.stations:
			if str(s.id) == CITY:
				return s
		await wait_physics_frames(1)
	return null


func _woke(s) -> void:
	s.remnant._wake()
	for i in 240:
		await wait_physics_frames(1)
		if s.remnant._queue.is_empty():
			break


func _kill(list: Array) -> void:
	for g in list:
		if is_instance_valid(g) and not g.dead:
			g.apply_damage(100000.0)
	await wait_physics_frames(3)


## The top floor's people: [general, honour guards, off duty] counts.
static func _counts(posts: Array) -> Dictionary:
	var c := { "general": 0, "honour": 0, "off_duty": 0 }
	for p in posts:
		c[str(p.soldier)] = int(c.get(str(p.soldier), 0)) + 1
	return c


# ------------------------------------------------------------------ where they stand

func test_the_general_and_two_honour_guards_on_the_bridge_and_troopers_off_duty_in_both_barracks() -> void:
	var h := _hull()
	var top := StationRemnant.top_posts(h)
	var c := _counts(top)
	assert_eq(c.general, 1, "one general")
	assert_eq(c.honour, 2, "an honour guard either side of him")
	assert_eq(c.off_duty, 8, "four off duty in each of the two barracks")
	for p in top:
		assert_true(str(p.id).begins_with("top_bridge_") if str(p.soldier) != "off_duty" else str(p.id).begins_with("top_barracks_"),
			"%s stands in the right room" % p.id)
	var all := StationRemnant.posts(h)
	assert_eq(all.filter(func(p): return bool(p.get("top", false))).size(), top.size(), "the deck's posts include the top floor's")


func test_every_top_post_is_inside_its_room_on_the_top_floor() -> void:
	var h := _hull()
	var t := h.tower("main")
	var f: Dictionary = (t.floors as Array).back()
	assert_eq(str(f.id), "top")
	var c: Vector2 = t.c
	var r0 := h.gap_r + h.walk + 0.4
	var r1 := float(f.r) - StationHull.WALL
	for p in StationRemnant.top_posts(h):
		var at: Vector3 = p.at
		var r := Vector2(at.x, at.z).distance_to(c)
		assert_between(r, r0 + 1.0, r1 - 1.0, "%s is between the door and the window" % p.id)
		assert_between(at.y, float(f.y) - 0.01, float(f.y) + 0.5, "%s is on the top floor" % p.id)


func test_the_general_stands_on_the_dais_facing_the_door() -> void:
	var h := _hull()
	var g: Array = StationRemnant.top_posts(h).filter(func(p): return str(p.soldier) == "general")
	assert_eq(g.size(), 1)
	if g.is_empty():
		return
	var t := h.tower("main")
	var at: Vector3 = g[0].at
	var out := (Vector3(at.x, 0, at.z) - Vector3(t.c.x, 0, t.c.y)).normalized()
	assert_lt((g[0].face as Vector3).dot(out), -0.99, "facing back toward the door")
	var f: Dictionary = (t.floors as Array).back()
	assert_almost_eq(at.y - float(f.y), 0.45, 0.01, "up on the dais")


func test_a_skimmer_outpost_has_no_top_floor_people() -> void:
	assert_true(StationRemnant.top_posts(StationHull.for_id("skimmer_outpost")).is_empty())


# ------------------------------------------------------------------ in the scene

func test_they_take_their_posts_with_the_deck_and_the_station_falls_only_once_they_are_dead() -> void:
	var t = _host()
	var s = await _city(t)
	assert_not_null(s)
	if s == null or s.remnant == null:
		return
	WorldState.set_flag("belt_cruiser_taken")          # the deck is not locked
	await _woke(s)
	var profiles := {}
	for g in s.remnant.troopers:
		profiles[str(g.profile.get("id", ""))] = int(profiles.get(str(g.profile.get("id", "")), 0)) + 1
	assert_eq(int(profiles.get("cruiser_general", 0)), 1, "the general")
	assert_eq(int(profiles.get("cruiser_honour_guard", 0)), 3, "two honour guards on the bridge and the deck's commander")
	assert_eq(int(profiles.get("station_off_duty", 0)), 8, "eight off duty")
	var top_y: float = float((s.hull.tower("main").floors as Array).back().y)
	var up: Array = s.remnant.troopers.filter(func(g): return s.to_local_point(g.global_position).y > top_y - 1.0)
	assert_eq(up.size(), 11, "eleven of them up on the top floor")
	var below: Array = s.remnant.troopers.filter(func(g): return not up.has(g))
	await _kill(below)
	assert_eq(Territory.owner(PLACE), Territory.REMNANT, "the deck cleared, the top floor still stands")
	await _kill(up)
	assert_eq(Territory.owner(PLACE), Territory.LOCALS, "every one of them dead: the locals have the station")


func test_the_locals_guards_take_top_floor_posts_too() -> void:
	var t = _host()
	var s = await _city(t)
	assert_not_null(s)
	if s == null or s.remnant == null:
		return
	WorldState.control[PLACE] = { "owner": Territory.LOCALS }
	await _woke(s)
	for i in 600:
		await wait_physics_frames(1)
		if not s.remnant.guards.is_empty() and s.remnant._queue.is_empty():
			break
	assert_false(s.remnant.guards.is_empty(), "the locals' guards stand the posts")
	assert_true(s.remnant.troopers.is_empty(), "no Remnant")
	var top_y: float = float((s.hull.tower("main").floors as Array).back().y)
	var up: Array = s.remnant.guards.filter(func(g): return s.to_local_point(g.global_position).y > top_y - 1.0)
	assert_gt(up.size(), 0, "some on the top floor")
	assert_lt(up.size(), 11, "fewer than the Remnant had there")
