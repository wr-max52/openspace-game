extends GutTest
## Issue #611: the race. The yard crew hang out on foot with no speeders; the
## leader's buy-in has a floor and needs a speeder of yours; accepting builds their
## speeders and a crowd; [Z] lines you up and the countdown holds you; win and
## Dorrin holds the pot (and Skrugs's job is done); lose your speeder and you are
## out; from the shooting lap a racer with you in its nose fires; the tuned racers
## out-drive a stock speeder; after the race the speeders and the crowd go.

const TownDemo := preload("res://scenes/town_demo.gd")
const DT := 1.0 / 60.0


func before_each() -> void:
	WorldState.reset()
	Objective.race = {}
	Engine.time_scale = 1.0


func after_each() -> void:
	Engine.time_scale = 1.0
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
		if t.race_crews.size() >= 3:
			break
		await wait_physics_frames(1)
	return t


func _crew(t) -> RaceCrew:
	for c in t.race_crews:
		if c.id == "yard":
			return c
	return null


func _speeders_of(crew: RaceCrew) -> Array:
	return crew.get_children().filter(func(n): return n is SpeederNode)


## Your speeder, beside you, ridden, near `at`.
func _ride_near(t, at: Vector3, yaw: float) -> SpeederNode:
	var s: SpeederNode = t.speeder_post.speeders[0]
	s.place(at, yaw)
	t._player.global_position = at + Vector3(1.5, 0.5, 0)
	assert_true(s.mount(), "on your speeder")
	return s


## A short 1-lap loop beside Dorrin's yard so a whole race fits in a test.
func _short_course(t) -> RaceCourse:
	var c := { "id": "test_loop", "label": "Test Loop", "world": "port_desert", "laps": 1, "gate_width": 26.0,
		"antenna_height": 7.0, "grid": { "slots": 4, "back_m": 10.0, "row_m": 9.0, "side_m": 4.5 }, "gates": [], "line": [] }
	var centre := Vector2(-1100, -1000)
	for k in 24:
		var a := deg_to_rad(k * 15.0)
		c.line.append([centre.x + cos(a) * 110.0, centre.y + sin(a) * 110.0])
	for k in 4:
		var a := deg_to_rad(7.5 + k * 90.0)
		c.gates.append({ "id": "g%d" % k, "at": [centre.x + cos(a) * 110.0, centre.y + sin(a) * 110.0] })
	var rc := RaceCourse.new()
	rc.setup(t, t.pilot.ground, c)
	t.add_child(rc)
	t.race_courses.append(rc)
	return rc


# ---- hanging out, the menu ----------------------------------------------------------

func test_the_crew_hang_out_on_foot_and_the_buy_in_has_a_floor() -> void:
	var t = await _town()
	var crew := _crew(t)
	assert_not_null(crew, "the yard crew")
	assert_true(crew.found, "by Dorrin's yard")
	assert_eq(crew.racers.size(), 3, "three racers")
	assert_eq(_speeders_of(crew).size(), 0, "no speeders until you accept a race")
	assert_lt(crew.leader().global_position.distance_to(t.mechanic.world_point("customer")), 40.0, "they hang out by Dorrin's")
	assert_eq(str(crew.leader().profile.get("outfit", {}).get("head", "")), "guard:black", "the leader in black")
	WorldState.credits = 99
	assert_eq(crew.accept(100), "poor", "99 cr: refused")
	assert_eq(WorldState.credits, 99, "nothing taken")
	WorldState.credits = 500
	t._player.global_position = t.mechanic.world_point("customer") + Vector3(500, 0, 500)
	t.speeder_post.speeders[0].place(t._player.global_position + Vector3(400, 0, 0), 0.0)
	assert_eq(crew.accept(100), "speeder", "no speeder of yours near: refused")
	assert_eq(WorldState.credits, 500)
	var opts := crew.menu_options()
	assert_true(opts.any(func(o): return str(o.id) == "buy:100"), "the least buy-in")
	assert_false(opts.any(func(o): return str(o.id) == "buy:600"), "nothing above what you carry")
	assert_true(crew.menu_body().contains("10 times"), "the menu says what the winner takes")


## Bug: a stolen gate speeder you rode over on got "Race us on what, your feet?"
## (GateChase only makes it yours once the chase is over). The one you got off
## counts for a buy-in race; only one you own can go up for pink slips.
func test_a_stolen_speeder_you_rode_over_on_counts() -> void:
	var t = await _town()
	var crew := _crew(t)
	WorldState.credits = 500
	var here: Vector3 = crew.leader().global_position + Vector3(6, 0, 6)
	t.speeder_post.speeders[0].place(here + Vector3(600, 0, 0), 0.0)   # your own is far off
	assert_false(t.gate_speeders.is_empty(), "a gate speeder to steal")
	var stolen: SpeederNode = t.gate_speeders[0]
	stolen.place(here, 0.0)
	t._player.global_position = here + Vector3(1.5, 0.5, 0)
	assert_true(stolen.mount(), "on the gate speeder")
	assert_true(stolen.dismount(), "off it, by the crew")
	assert_false(t.speeder_post.speeders.has(stolen), "not yours yet")
	assert_eq(crew.your_speeder(), stolen, "the crew count the speeder you rode over on")
	WorldState.set_flag("crew_beaten_yard")
	assert_eq(crew.accept_slips(), "not_yours", "no pink slips on a speeder that is not yours")
	assert_ne(crew.said, crew.line("no_speeder"), "and not the no-speeder line")
	assert_eq(crew.accept(100), "", "a buy-in race on it is on")
	assert_eq(WorldState.credits, 400, "100 cr paid")


func test_accepting_builds_their_speeders_and_a_crowd_and_z_lines_you_up() -> void:
	var t = await _town()
	var crew := _crew(t)
	WorldState.credits = 500
	var s0: Dictionary = crew.course.grid_slot(0)
	var g: Dictionary = crew.course.gates[0]
	var mine := _ride_near(t, (s0.pos as Vector3) - (g.fwd as Vector3) * 25.0, float(s0.yaw))
	assert_eq(crew.accept(100), "", "on")
	assert_eq(WorldState.credits, 400, "100 cr paid")
	var theirs := _speeders_of(crew)
	assert_eq(theirs.size(), 3, "three speeders built")
	for sp: SpeederNode in theirs:
		assert_true(sp.npc_driven(), "a racer drives each")
	assert_between(crew.crowd.size(), 5, 10, "a crowd at the line")
	assert_eq(Objective.current_key(), "race", "the pointer is the race's")
	assert_true(crew.line_up(), "[Z] near the grid")
	var t0 := mine.model.position
	for i in 900:
		if crew.phase == RaceCrew.Phase.COUNTDOWN:
			break
		await wait_physics_frames(1)
	assert_eq(crew.phase, RaceCrew.Phase.COUNTDOWN, "everyone on the grid: the countdown")
	assert_lt(mine.model.position.distance_to(s0.pos), 4.0, "you are on your slot (from %.0f m out)" % t0.distance_to(s0.pos))
	var held := mine.model.position
	await wait_physics_frames(60)
	assert_lt(mine.model.position.distance_to(held), 0.5, "held until GO")


# ---- a whole race ------------------------------------------------------------------

func _race_to_go(t, crew: RaceCrew) -> SpeederNode:
	crew.course = _short_course(t)
	WorldState.credits = 500
	var s0: Dictionary = crew.course.grid_slot(0)
	var mine := _ride_near(t, s0.pos, float(s0.yaw))
	crew.accept(100)
	crew.line_up()
	for i in 1200:
		if crew.phase == RaceCrew.Phase.RACING:
			break
		await wait_physics_frames(1)
	assert_eq(crew.phase, RaceCrew.Phase.RACING, "GO")
	return mine


func test_win_and_dorrin_holds_the_pot_and_skrugs_job_is_done() -> void:
	var t = await _town()
	var crew := _crew(t)
	WorldState.jobs_taken["j_speeder_race"] = "active"
	var mine := await _race_to_go(t, crew)
	for rc in crew.racers:
		rc.brain.pace = 0.2              # let them dawdle: this test is about winning
	var me := SpeederBrain.new(mine.model, "ace")
	var start := crew._line_start()
	var route: Array = []
	for k in crew.course.line.size():
		route.append(crew.course.line[(start + k) % crew.course.line.size()])
	me.follow(route, true)
	Engine.time_scale = 3.0
	for i in 2400:
		if crew.phase != RaceCrew.Phase.RACING:
			break
		mine.set_external_command(me.update(DT))
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_eq(crew.winner, RaceCrew.YOU, "you won")
	assert_eq(WorldState.count("race_winnings"), 1000, "10 x 100, held by Dorrin")
	assert_true(WorldState.has_flag("race_won") and WorldState.has_flag("crew_beaten_yard"))
	assert_eq(WorldState.jobs_taken.get("j_speeder_race", ""), "done", "Skrugs's job is done")
	var before := WorldState.credits
	assert_eq(t.mechanic.collect_winnings(), 1000, "Dorrin pays out")
	assert_eq(WorldState.credits, before + 1000)
	assert_eq(t.mechanic.collect_winnings(), 0, "once")
	Engine.time_scale = 4.0
	for i in 1500:
		if crew.phase == RaceCrew.Phase.IDLE:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_eq(crew.phase, RaceCrew.Phase.IDLE, "back to hanging out")
	await wait_physics_frames(2)
	assert_eq(_speeders_of(crew).size(), 0, "their speeders are put away")
	assert_eq(crew.crowd.size(), 0, "the crowd has gone")


func test_lose_your_speeder_and_you_are_out_with_no_prize() -> void:
	var t = await _town()
	var crew := _crew(t)
	var mine := await _race_to_go(t, crew)
	mine.apply_damage(1.0e6)
	for i in 30:
		if crew.phase != RaceCrew.Phase.RACING:
			break
		await wait_physics_frames(1)
	assert_eq(crew.player_out, "why_wrecked", "out: wrecked")
	assert_ne(crew.winner, RaceCrew.YOU, "no win")
	assert_eq(WorldState.count("race_winnings"), 0, "no prize")
	assert_eq(WorldState.credits, 400, "no refund")


func test_from_the_shooting_lap_a_racer_with_you_in_its_nose_fires() -> void:
	var t = await _town()
	var crew := _crew(t)
	var mine := await _race_to_go(t, crew)
	var rc: Dictionary = crew.racers[0]
	var sp: SpeederNode = rc.speeder
	rc.brain.pace = 0.0
	mine.place(sp.model.position + sp.model.forward() * 30.0, sp.model.yaw)
	await wait_physics_frames(3)
	assert_eq(rc.brain.shoot_at, Vector3.INF, "lap 1: nobody shoots")
	crew.laps.racers[rc.key].lap = 1        # on lap 2 now
	var fired := false
	for i in 20:
		mine.place(sp.model.position + sp.model.forward() * 30.0, sp.model.yaw)
		await wait_physics_frames(1)
		fired = fired or bool(rc.brain.command.get("fire", false))
	assert_ne(rc.brain.shoot_at, Vector3.INF, "lap 2: you are the target")
	assert_true(fired, "and it fires")


# ---- hard to win -------------------------------------------------------------------

func test_the_tuned_racers_out_drive_a_stock_speeder() -> void:
	var ground := WorldGround.new()
	ground.setup({ "terrain": { "extent": 6000.0 } })
	var course := RaceCourse.load_course("hoodoo_run")
	var crew := RaceCrew.load_crew("yard")
	var route: Array = []
	for p in course.line:
		route.append(Vector3(float(p[0]), 0.0, float(p[1])))
	var base := HoverModel.load_config("speeder")
	var lead: Dictionary = crew.racers[0]
	var tuned := SpeederUpgrades.apply(base, { "paint": lead.paint, "parts": lead.parts })
	var times: Array = []
	for cfg: Dictionary in [base, tuned]:
		var m := HoverModel.new(cfg, ground)
		m.place(route[0], 0.0)
		var b := SpeederBrain.new(m, str(lead.skill))
		b.follow(route.slice(1) + [route[0]], false)
		var tt := 0.0
		while not b.done and tt < 200.0:
			var c := b.update(DT)
			m.set_command(float(c.throttle), float(c.steer), bool(c.boost))
			m.step(DT)
			tt += DT
		times.append(tt)
	assert_lt(float(times[1]), float(times[0]) - 4.0, "the leader's speeder laps faster than stock (%.1f s v %.1f s)" % [times[1], times[0]])
