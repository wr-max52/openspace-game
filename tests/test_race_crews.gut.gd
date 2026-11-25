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


# ---- speeder classes: who rides what, rung by rung ----------------------------

func _crew_file(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://content/core/racing/crews/%s.json" % id))


func _models(crew: Dictionary) -> Array:
	return (crew.racers as Array).map(func(r): return SpeederUpgrades.model_of(r))


func _tier_two(parts: Array) -> bool:
	return parts.any(func(p): return str(SpeederUpgrades.part(str(p)).get("requires", "")) != "")


func test_the_yard_crew_ride_basic_sand_boxers_with_lasers_only() -> void:
	var yard := _crew_file("yard")
	assert_eq(_models(yard), ["speeder", "speeder", "speeder"], "all Sand-boxers")
	assert_true((yard.rules.get("gear", []) as Array).is_empty(), "no race gear: lasers only")
	for r in yard.racers:
		assert_false(_tier_two(r.parts), "first-tier parts at most")
		assert_lte((r.parts as Array).filter(func(p): return str(SpeederUpgrades.part(str(p)).group) == "performance").size(), 1,
			"one performance part at most")


func test_the_basin_crew_bring_a_fast_truck_seekers_and_mines() -> void:
	var basin := _crew_file("basin")
	assert_eq(_models(basin).count("hauler"), 1, "one box truck")
	assert_eq(_models(basin).count("speeder"), 2, "and two Sand-boxers")
	assert_eq(basin.rules.gear, ["seekers", "mines"])
	var yard_perf := 0
	for r in _crew_file("yard").racers:
		yard_perf += (r.parts as Array).filter(func(p): return str(SpeederUpgrades.part(str(p)).group) == "performance").size()
	var basin_perf := 0
	for r in basin.racers:
		basin_perf += (r.parts as Array).filter(func(p): return str(SpeederUpgrades.part(str(p)).group) == "performance").size()
		if SpeederUpgrades.model_of(r) == "hauler":
			assert_has(r.parts, "engine_2", "the truck is a fast one")
	assert_gt(basin_perf, yard_perf, "more tuned than the yard crew")


func test_the_salt_crew_stack_their_sand_boxer_and_truck() -> void:
	var salt := _crew_file("salt")
	assert_eq(_models(salt).count("racer"), 1, "a racer")
	assert_eq(_models(salt).count("hauler"), 1, "a box truck")
	assert_eq(_models(salt).count("speeder"), 1, "a Sand-boxer")
	assert_eq(salt.rules.gear, ["seekers", "mines", "deflector", "nitro"], "every piece of race gear")
	for r in salt.racers:
		var parts: Array = r.parts
		if SpeederUpgrades.model_of(r) == "racer":
			assert_false(_tier_two(parts), "the racer: some upgrades")
			assert_false(parts.is_empty())
		else:
			for top in ["engine_2", "thrusters_2", "cannons_2"]:
				assert_has(parts, top, "%s: fully stacked" % SpeederUpgrades.model_of(r))


func test_a_crew_racer_keeps_its_model_on_pink_slips() -> void:
	var fit := RaceCrew._own_fit({ "model": "hauler", "paint": "", "parts": ["engine_2"] })
	assert_eq(fit.model, "hauler")
	assert_eq(RaceCrew.ride_label(fit), "the Boxcar (racing engine)")
	assert_eq(RaceCrew.ride_label({ "paint": "steel", "parts": [] }), "the steel Sand-boxer", "no model: a Sand-boxer")


## Health and weapons: a bolt is 15% of a Sand-boxer, a seeker (hit and splash)
## or a mine a third; the racer takes half that, the truck three times.
func test_hits_to_wreck_each_class() -> void:
	var seeker: Dictionary = SpeederUpgrades.part("seekers").gear
	var mine: Dictionary = SpeederUpgrades.part("mines").gear
	var laser := float(HoverModel.load_config("speeder").laser.damage)
	var hits := func(hp: float, dmg: float) -> int: return int(ceil(hp / dmg))
	var want := { "racer": [4, 2, 2], "speeder": [7, 3, 3], "hauler": [20, 9, 9] }
	for model in want:
		var hp := float(HoverModel.load_config(model).health)
		var got := [hits.call(hp, laser), hits.call(hp, float(seeker.damage) + float(seeker.splash_damage)), hits.call(hp, float(mine.vehicle_damage))]
		assert_eq(got, want[model], "%s: laser bolts, seekers, mines to wreck" % model)


func test_the_map_shows_the_races_you_have_heard_of() -> void:
	var ids := func(): return GlobeMap.race_pins("port_desert").map(func(p): return str(p.id))
	assert_eq(ids.call().size(), 0, "no speeder, no races heard of")
	WorldState.counters["speeders_owned"] = 1
	assert_eq(ids.call(), ["race_yard"], "own a speeder: Skrugs tells you of the yard crew")
	WorldState.set_flag("crew_beaten_yard")
	assert_true(ids.call().has("race_basin"), "beat them: they tell you of the basin crew")
	assert_false(ids.call().has("race_salt"))


## Bug: the race pin sat on the empty start line, 100-300 m from the crew you
## have to talk to. It sits where the leader stands now.
func test_the_race_pin_is_where_the_crew_stand() -> void:
	WorldState.counters["speeders_owned"] = 1
	WorldState.set_flag("crew_beaten_yard")
	WorldState.set_flag("crew_beaten_basin")
	var world = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/worlds/port_desert.json"))
	var pins := GlobeMap.race_pins("port_desert", world)
	assert_eq(pins.size(), 3, "all three races heard of")
	for p in pins:
		var c := RaceCrew.load_crew(str(p.id).trim_prefix("race_"))
		var near := str(c.hangout.near)
		var lm: Dictionary = (world.landmarks as Array).filter(func(l): return str(l.get("location", l.id)) == near)[0]
		var hang := Vector2(float(lm.at[0]), float(lm.at[2]))
		var gate: Array = RaceCourse.load_course(str(c.course)).gates[0].at
		var stand: Array = (c.racers as Array).filter(func(r): return bool(r.get("leader", false)))[0].stand
		assert_almost_eq((p.map as Vector2).distance_to(hang), Vector2(float(stand[0]), float(stand[1])).length(), 0.5,
			"%s: the pin is on the leader's spot by their hangout" % p.id)
		assert_gt((p.map as Vector2).distance_to(Vector2(float(gate[0]), float(gate[1]))), 60.0, "%s: not out on the start line" % p.id)
