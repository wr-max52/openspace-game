extends GutTest
## Issue #612: race day's second beast. On the course only while a race runs,
## inside its leash; gone after; killed, it stays dead under its own flag while the
## planet's beast lives on untouched; racers steer round it and die on it.

const TownDemo := preload("res://scenes/town_demo.gd")


func before_each() -> void:
	WorldState.reset()
	Objective.race = {}


func after_each() -> void:
	Objective.race = {}
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	WorldState.counters["speeders_owned"] = 1
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	for i in 900:
		if not t.race_crews.is_empty() and t.beast != null:
			break
		await wait_physics_frames(1)
	return t


func _accept(t, crew: RaceCrew) -> void:
	WorldState.credits = 500
	var s: SpeederNode = t.speeder_post.speeders[0]
	var s0: Dictionary = crew.course.grid_slot(0)
	s.place(s0.pos, float(s0.yaw))
	t._player.global_position = s.model.position + Vector3(1.5, 0.5, 0)
	s.mount()
	assert_eq(crew.accept(100), "", "race on")


func test_the_track_beast_is_there_only_while_a_race_runs() -> void:
	var t = await _town()
	var crew: RaceCrew = t.race_crews[0]
	assert_null(crew.track_beast, "no track beast between races")
	var brief_before := PlanetBeast.brief(t.planet)
	_accept(t, crew)
	assert_not_null(crew.track_beast, "a race starts: the track beast")
	assert_ne(crew.track_beast, t.beast, "a second beast, not the planet's")
	await wait_physics_frames(5)
	var b := crew.track_beast
	assert_lt(b.global_position.distance_to(b.home), float(b.cfg.get("leash_m", 0.0)) + 50.0, "inside its leash")
	assert_lt(b.home.distance_to(crew.course.center), 200.0, "its home is the course")
	assert_eq(PlanetBeast.brief(t.planet), brief_before, "the planet's beast's brief is unchanged")
	crew._end_race()
	crew._put_away()
	await wait_physics_frames(2)
	assert_null(crew.track_beast, "the race is over: gone")
	assert_true(is_instance_valid(t.beast) and not t.beast.dead, "the planet's beast is still about")


func test_killed_it_stays_dead_and_the_planets_beast_lives_on() -> void:
	var t = await _town()
	var crew: RaceCrew = t.race_crews[0]
	_accept(t, crew)
	crew.track_beast._die()
	var pid := str(t.planet.get("id", ""))
	assert_true(WorldState.has_flag("beast_slain_%s_track" % pid), "its own flag")
	assert_false(PlanetBeast.is_slain(pid), "the planet's beast is not slain")
	assert_true(PlanetBeast.lives_on(t.planet), "and still lives")
	crew._end_race()
	crew._put_away()
	await wait_physics_frames(2)
	_accept(t, crew)
	assert_null(crew.track_beast, "the next race: no track beast")


func test_racers_steer_round_it_and_die_on_it() -> void:
	var t = await _town()
	var crew: RaceCrew = t.race_crews[0]
	_accept(t, crew)
	await wait_physics_frames(5)
	var head := crew.track_beast.global_position
	assert_false(crew._beast_avoid(head).is_empty(), "its body is on a racer's avoid list")
	crew.phase = RaceCrew.Phase.RACING
	var rc: Dictionary = crew.racers[1]
	var b: NpcBody = rc.body
	rc.speeder.place(head, 0.0)
	await wait_physics_frames(3)
	assert_true(bool(rc.out), "into it: out of the race")
	assert_true(b.dead, "and dead, as you would be")
