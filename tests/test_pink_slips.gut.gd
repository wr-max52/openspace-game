extends GutTest
## Issue #617: pink slips. Beat a crew for money and their leader will race you
## for speeders: win and theirs is yours, parked outside the back gate (and still
## there after a save); lose and yours is theirs, until you win it back. Parked
## speeders sleep while you are away. A full row means no pink slips.

const TownDemo := preload("res://scenes/town_demo.gd")


func before_each() -> void:
	WorldState.reset()
	Objective.race = {}


func after_each() -> void:
	WorldState.reset()
	Objective.race = {}
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town(owned: int = 1) -> Node:
	WorldState.counters["speeders_owned"] = owned
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	for i in 900:
		if t.race_crews.size() >= 3:
			break
		await wait_physics_frames(1)
	return t


func _yard(t) -> RaceCrew:
	for c in t.race_crews:
		if c.id == "yard":
			return c
	return null


func _ride_to_grid(t, crew: RaceCrew) -> SpeederNode:
	var s: SpeederNode = t.speeder_post.speeders[0]
	var s0: Dictionary = crew.course.grid_slot(0)
	s.place(s0.pos, float(s0.yaw))
	t._player.global_position = s.model.position + Vector3(1.5, 0.5, 0)
	s.mount()
	return s


## Settle the race now with `first` the winner.
func _finish(crew: RaceCrew, first: String, mine: SpeederNode) -> void:
	crew._player_speeder = mine
	crew.phase = RaceCrew.Phase.RACING
	crew.results = [first]
	crew._end_race()


func test_offered_only_once_you_have_beaten_them_for_money() -> void:
	var t = await _town()
	var crew := _yard(t)
	assert_false(crew.menu_options().any(func(o): return str(o.id) == "slips"), "not before you beat them")
	assert_eq(crew.accept_slips(), "beaten")
	WorldState.set_flag("crew_beaten_yard")
	assert_true(crew.menu_options().any(func(o): return str(o.id) == "slips"), "then pink slips are on the menu")


func test_win_and_their_speeder_waits_outside_the_back_gate_even_after_a_save() -> void:
	var t = await _town()
	var crew := _yard(t)
	WorldState.set_flag("crew_beaten_yard")
	var mine := _ride_to_grid(t, crew)
	var theirs := crew.leader_ride()
	assert_eq(crew.accept_slips(), "", "pink slips on")
	assert_eq(WorldState.credits, 60, "no money changes hands")
	_finish(crew, RaceCrew.YOU, mine)
	assert_eq(WorldState.count("speeders_owned"), 2, "two speeders")
	var won: SpeederNode = t.speeder_post.speeders[-1]
	assert_eq(won.paint, str(theirs.paint), "in their paint")
	for p in theirs.parts:
		assert_has(won.cfg.get("parts", []), p, "with their %s" % p)
	var row: Array = t.town.markers_with_role("speeder_spot")
	var near_row := row.any(func(m): return t.town.marker_pos(str(m.id)).distance_to(won.model.position) < 3.0)
	assert_true(near_row, "parked in the row outside the back gate")
	var saved := WorldState.to_save()
	WorldState.reset()
	WorldState.from_save(saved)
	var t2 = await _town(WorldState.count("speeders_owned"))
	assert_eq(t2.speeder_post.speeders.size(), 2, "after a boot: both")
	assert_true(t2.speeder_post.speeders.any(func(s): return s.paint == str(theirs.paint) and (s.cfg.get("parts", []) as Array).has(theirs.parts[0])), "theirs among them")


func test_lose_and_they_ride_yours_until_you_win_it_back() -> void:
	var t = await _town()
	var crew := _yard(t)
	WorldState.set_flag("crew_beaten_yard")
	WorldState.speeder_fits = [{ "paint": "tide", "parts": ["engine_1", "soft_top"], "spent": 0 }]
	t.speeder_post.refit(t.speeder_post.speeders[0])
	var mine := _ride_to_grid(t, crew)
	assert_eq(crew.accept_slips(), "")
	_finish(crew, "racer_0", mine)
	assert_eq(WorldState.count("speeders_owned"), 0, "your speeder is gone")
	assert_eq(str(crew.leader_ride().paint), "tide", "the leader rides it now")
	assert_has(crew.leader_ride().parts, "engine_1", "parts and all")
	crew._put_away()
	await wait_physics_frames(2)
	WorldState.credits = 500
	t.speeder_post.buy()
	var spare := _ride_to_grid(t, crew)
	assert_eq(crew.accept_slips(), "")
	var leader_speeder: SpeederNode = crew.racers[0].speeder
	assert_eq(leader_speeder.paint, "tide", "they race you on your old speeder")
	_finish(crew, RaceCrew.YOU, spare)
	assert_true(t.speeder_post.speeders.any(func(s): return s.paint == "tide" and (s.cfg.get("parts", []) as Array).has("engine_1")), "won back, parts and all")
	assert_true(WorldState.race_rides.is_empty(), "they are back on their own")


func test_parked_speeders_sleep_while_you_are_away() -> void:
	var t = await _town()
	for i in 4:
		t.speeder_post.add_owned(SpeederUpgrades.new_fit("steel"))
	assert_eq(t.speeder_post.speeders.size(), 5, "five in the row")
	t._player.global_position = t.speeder_post.speeders[0].model.position + Vector3(200, 0, 0)
	await wait_physics_frames(2)
	var before: Array = t.speeder_post.speeders.map(func(s): return s.parked_steps)
	await wait_physics_frames(30)
	var after: Array = t.speeder_post.speeders.map(func(s): return s.parked_steps)
	assert_eq(after, before, "200 m away: not one hover tick")
	var near: SpeederNode = t.speeder_post.speeders[2]
	t._player.global_position = near.model.position + Vector3(4, 0, 0)
	await wait_physics_frames(10)
	assert_gt(near.parked_steps, before[2], "walk up: it wakes")


func test_won_speeders_do_not_use_up_skrugss_one_of_each() -> void:
	var t = await _town(0)
	var post: SpeederPost = t.speeder_post
	post.add_owned(SpeederUpgrades.new_fit("crimson"))
	assert_eq(WorldState.count("speeders_owned"), 1, "a Sand-boxer won on pink slips")
	assert_eq(post.owned_of("speeder"), 0, "not one he sold")
	assert_false(post.at_limit("speeder"), "so he still sells you a Sand-boxer")
	WorldState.credits = 1000
	assert_true(post.buy(), "and you can buy it")
	assert_eq(post.owned_of("speeder"), 1, "that one counts")
	assert_true(post.at_limit("speeder"), "one of each")


func test_a_full_row_means_no_pink_slips() -> void:
	var t = await _town()
	var crew := _yard(t)
	WorldState.set_flag("crew_beaten_yard")
	while WorldState.count("speeders_owned") < t.speeder_post.owned_cap():
		t.speeder_post.add_owned(SpeederUpgrades.new_fit("steel"))
	_ride_to_grid(t, crew)
	assert_eq(crew.accept_slips(), "full", "where would you even park it")
	assert_null(t.speeder_post.add_owned(SpeederUpgrades.new_fit("steel")), "nor can you own more")
