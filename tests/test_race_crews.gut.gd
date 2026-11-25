extends GutTest
## Issue #615: three race crews at their own spots, a ladder, and parts you unlock
## by beating them (story mode only; free roam sells everything). Every crew and
## course is a file on clear sand; the story never needs a locked part; the map
## shows the races you have heard of.

const TownDemo := preload("res://scenes/town_demo.gd")


func before_each() -> void:
	WorldState.reset()
	WorldState.mode = WorldState.FREEPLAY
	Objective.race = {}


func after_each() -> void:
	WorldState.reset()
	WorldState.mode = WorldState.FREEPLAY
	Objective.race = {}
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	for i in 900:
		if t.race_crews.size() >= 3:
			break
		await wait_physics_frames(1)
	return t


func _crew(t, id: String) -> RaceCrew:
	for c in t.race_crews:
		if c.id == id:
			return c
	return null


func test_three_crews_three_spots_three_courses() -> void:
	var t = await _town()
	assert_eq(t.race_crews.size(), 3, "the yard, basin and salt crews")
	assert_eq(t.race_courses.size(), 3, "a course each")
	var ground: WorldGround = t.pilot.ground
	for crew: RaceCrew in t.race_crews:
		assert_true(crew.found, "%s found its hangout" % crew.id)
		assert_eq(crew.racers.size(), 3, "%s: three racers" % crew.id)
		assert_eq(crew.racers.filter(func(r): return bool(r.cfg.get("leader", false))).size(), 1, "%s: one leader" % crew.id)
		for rc in crew.racers:
			var at: Vector3 = rc.body.global_position
			assert_eq(ground.hit(at + ground.up_at(at) * 1.0, 0.5), "", "%s stands clear of buildings" % rc.key)
		assert_lt(crew.leader().global_position.distance_to(crew.course.gate_pos(0)), 350.0, "%s: their start line is near their spot" % crew.id)
		var bad := 0
		for p in crew.course.line:
			if ground.hit(p + ground.up_at(p) * 1.0, 1.3) != "":
				bad += 1
		assert_eq(bad, 0, "%s: the racing line is clear sand" % crew.course.id)
	assert_ne(_crew(t, "basin").course, _crew(t, "yard").course, "each crew on its own course")


func test_the_ladder_rung_by_rung() -> void:
	var t = await _town()
	WorldState.credits = 2000
	var basin := _crew(t, "basin")
	var salt := _crew(t, "salt")
	assert_true(_crew(t, "yard").ladder_open(), "the yard crew races anyone")
	assert_eq(basin.accept(250), "ladder", "the basin crew wants the yard crew beaten first")
	assert_eq(basin.said, basin.line("not_yet"), "and says so")
	assert_eq(salt.accept(500), "ladder", "the salt crew too")
	WorldState.set_flag("crew_beaten_yard")
	assert_ne(basin.accept(250), "ladder", "yard beaten: the basin crew will race")
	assert_eq(salt.accept(500), "ladder", "the salt crew still wants the basin crew")
	assert_eq(WorldState.credits, 2000, "nothing paid on a refusal")


func test_parts_unlock_by_beating_crews_in_story_mode_only() -> void:
	var t = await _town()
	WorldState.mode = WorldState.STORY
	assert_eq(SpeederUpgrades.locked_by("engine_2"), "yard", "story: Engine II waits on the yard crew")
	assert_eq(SpeederUpgrades.locked_by("engine_1"), "", "Engine I is for sale")
	WorldState.credits = 2000
	var s: SpeederNode
	t.speeder_post.buy()
	s = t.speeder_post.speeders[-1]
	s.place(t.mechanic.world_point("bay"), 0.0)
	t.mechanic.buy("engine_1")
	t.mechanic.talk()
	t.mechanic.menu.choose("group:performance")
	var ids: Array = t.mechanic.menu.options.map(func(o): return str(o.id))
	var row: String = t.mechanic.menu.options[ids.find("buy:engine_2")].text
	var leader := _crew(t, "yard").leader_name()
	assert_string_contains(row, leader, "the menu names who to beat")
	assert_string_contains(row, "yard crew")
	assert_eq(t.mechanic.buy("engine_2"), "crew:yard", "and will not sell it")
	WorldState.set_flag("crew_beaten_yard")
	assert_eq(SpeederUpgrades.locked_by("engine_2"), "", "yard crew beaten: on sale")
	assert_eq(t.mechanic.buy("engine_2"), "bought")
	WorldState.mode = WorldState.FREEPLAY
	for p in SpeederUpgrades.parts():
		assert_eq(SpeederUpgrades.locked_by(str(p.id)), "", "free roam: %s is for sale" % p.id)


func test_the_story_never_needs_a_locked_part() -> void:
	var locked: Array = SpeederUpgrades.parts().filter(func(p): return str(p.get("unlocked_by", "")) != "").map(func(p): return str(p.id))
	assert_gt(locked.size(), 0, "some parts are held back")
	var texts: Array = []
	for d in ["res://content/core/story/", "res://content/core/board/"]:
		var dir := DirAccess.open(d)
		for f in dir.get_files():
			if f.ends_with(".json"):
				texts.append(FileAccess.get_file_as_string(d + f))
	for id: String in locked:
		for txt: String in texts:
			assert_false(txt.contains('"%s"' % id), "the story and board never ask for %s" % id)


func test_the_map_shows_the_races_you_have_heard_of() -> void:
	var ids := func(): return GlobeMap.race_pins("port_desert").map(func(p): return str(p.id))
	assert_eq(ids.call().size(), 0, "no speeder, no races heard of")
	WorldState.counters["speeders_owned"] = 1
	assert_eq(ids.call(), ["race_yard"], "own a speeder: Skrugs tells you of the yard crew")
	WorldState.set_flag("crew_beaten_yard")
	assert_true(ids.call().has("race_basin"), "beat them: they tell you of the basin crew")
	assert_false(ids.call().has("race_salt"))
