extends GutTest
## Issue #611: the race. The yard crew hang out on foot by their parked speeders;
## the leader's buy-in has a floor and needs a speeder of yours; accepting sends
## them one after another to their speeders and to the grid, and a crowd gathers;
## [Z] lines you up and the countdown holds you; win and Dorrin holds the pot (and
## Skrugs's job is done); lose your hull and you crash out, are patched up and race
## on; get off and you are out; from the shooting lap
## a racer with you in its nose fires; the tuned racers out-drive a stock speeder;
## after the race they park again and the crowd goes.

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
	t._player.global_position = t.mechanic.world_point("customer")
	await wait_physics_frames(5)
	assert_eq(_speeders_of(crew).size(), 3, "their speeders parked by them, built as you come near")
	for sp: SpeederNode in _speeders_of(crew):
		assert_false(sp.npc_driven(), "nobody aboard")
		assert_false(sp.can_mount(), "not yours to ride")
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
	assert_eq(theirs.size(), 3, "their three speeders")
	await wait_physics_frames(30)
	assert_true(crew.racers[0].speeder.npc_driven() or crew.racers[0].speeder._boarding.size() > 0, "the first heads off at once")
	assert_false(crew.racers[2].speeder.npc_driven(), "the last waits its turn")
	assert_eq(Objective.current_key(), "race", "the pointer is the race's")
	assert_true(crew.line_up(), "[Z] near the grid")
	var t0 := mine.model.position
	for i in 4000:
		if crew.phase == RaceCrew.Phase.COUNTDOWN:
			break
		await wait_physics_frames(1)
	assert_eq(crew.phase, RaceCrew.Phase.COUNTDOWN, "everyone on the grid: the countdown")
	for sp: SpeederNode in theirs:
		assert_true(sp.npc_driven(), "a racer drives each")
	assert_between(crew.crowd.size(), 5, 10, "a crowd at the line")
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
	for i in 5000:
		if crew.phase == RaceCrew.Phase.RACING:
			break
		await wait_physics_frames(1)
	assert_eq(crew.phase, RaceCrew.Phase.RACING, "GO")
	return mine


func test_win_pays_the_pot_at_once_and_skrugs_job_is_done() -> void:
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
	assert_eq(WorldState.credits, 400 + 1000, "10 x 100, paid into your credits at the finish")
	assert_eq(WorldState.count("race_winnings"), 0, "nothing left for Dorrin to hold")
	assert_eq(t.mechanic.collect_winnings(), 0, "nothing to collect")
	assert_true(WorldState.has_flag("race_won") and WorldState.has_flag("crew_beaten_yard"))
	assert_eq(WorldState.jobs_taken.get("j_speeder_race", ""), "done", "Skrugs's job is done")
	assert_eq(Quests.state(RaceCrew.quest_id("next", "basin")), "open", "next: the basin crew")
	assert_eq(Quests.state(RaceCrew.quest_id("slips", "yard")), "open", "a pink-slip rematch with the yard crew")
	Engine.time_scale = 4.0
	for i in 1500:
		if crew.phase == RaceCrew.Phase.IDLE:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_eq(crew.phase, RaceCrew.Phase.IDLE, "back to hanging out")
	await wait_physics_frames(2)
	assert_eq(_speeders_of(crew).size(), 3, "their speeders stay")
	for rc in crew.racers:
		if is_instance_valid(rc.speeder):
			assert_false(rc.speeder.npc_driven(), "parked, nobody aboard")
			assert_lt(rc.speeder.model.position.distance_to(crew._park_pos(rc)), 6.0, "back on its spot")
	assert_eq(crew.crowd.size(), 0, "the crowd has gone")


func test_lose_your_hull_and_you_crash_out_get_patched_up_and_race_on() -> void:
	var t = await _town()
	var crew := _crew(t)
	var mine := await _race_to_go(t, crew)
	assert_gt(mine.crash_repair_s, 0.0, "crash-outs on while the race runs")
	mine.apply_damage(1.0e6)
	assert_true(is_instance_valid(mine) and mine.model.alive(), "no burst: still there")
	assert_true(mine.riding, "still aboard")
	assert_eq(mine.crash_outs, 1, "crashed out")
	assert_gt(mine.repair_left, 0.0, "being patched up")
	assert_eq(mine.model.speed, 0.0, "stopped dead")
	var hp := mine.model.hp
	mine.apply_damage(50.0)
	assert_eq(mine.model.hp, hp, "no more hits while it is patched up")
	await wait_physics_frames(3)
	assert_eq(crew.player_out, "", "still in the race")
	assert_eq(crew.phase, RaceCrew.Phase.RACING, "the race runs on")
	Engine.time_scale = 4.0
	for i in 600:
		if mine.repair_left <= 0.0:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_eq(mine.repair_left, 0.0, "patched up")
	assert_eq(mine.model.hp, int(round(mine.model.max_hp * Welder.unwelded_hull())), "no welder: back at half hull (issue #722)")
	assert_eq(crew.player_out, "", "racing again")
	mine.dismount()
	for i in 30:
		if crew.phase != RaceCrew.Phase.RACING:
			break
		await wait_physics_frames(1)
	assert_eq(mine.crash_repair_s, 0.0, "crash-outs off once you are out")


func test_get_off_and_you_are_out_with_no_prize() -> void:
	var t = await _town()
	var crew := _crew(t)
	var mine := await _race_to_go(t, crew)
	assert_true(mine.dismount(), "off it")
	for i in 30:
		if crew.phase != RaceCrew.Phase.RACING:
			break
		await wait_physics_frames(1)
	assert_eq(crew.player_out, "why_off", "out: got off")
	assert_ne(crew.winner, RaceCrew.YOU, "no win")
	assert_eq(WorldState.count("race_winnings"), 0, "no prize")
	assert_eq(WorldState.credits, 400, "no refund")
	assert_eq(Quests.state(RaceCrew.quest_id("rematch", "yard")), "open", "lost: a rematch with them")
	assert_eq(Quests.state(RaceCrew.quest_id("slips", "yard")), "", "no pink slips offered")


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


# ---- the rematch -------------------------------------------------------------------

func test_rematch_at_once_for_the_same_stake_paid_from_dorrins_hold_too() -> void:
	var t = await _town()
	var crew := _crew(t)
	await _race_to_go(t, crew)
	assert_eq(WorldState.credits, 400, "100 cr paid")
	WorldState.credits = 50                     # short in hand, but Dorrin holds 1000 for you
	WorldState.counters["race_winnings"] = 1000
	crew._end_race()
	assert_eq(crew.phase, RaceCrew.Phase.RETURN, "they head home")
	assert_true(crew.rematch_on, "the rematch is open")
	assert_eq(crew.last_stake, 100, "for the same stake")
	await wait_physics_frames(20)
	assert_eq(crew.rematch(), "", "[Z]: on again")
	assert_eq(WorldState.credits, 0, "your 50 cr first")
	assert_eq(WorldState.count("race_winnings"), 950, "the other 50 out of what Dorrin holds")
	assert_eq(crew.stake, 100)
	assert_eq(crew.phase, RaceCrew.Phase.GRID, "back to the grid")
	assert_true(crew.lined_up, "already by the line: straight onto your slot")
	assert_false(crew.rematch_on, "once")
	assert_eq(crew.rematch(), "busy", "not twice")
	for i in 5000:
		if crew.phase == RaceCrew.Phase.COUNTDOWN:
			break
		await wait_physics_frames(1)
	assert_eq(crew.phase, RaceCrew.Phase.COUNTDOWN, "everyone back on the grid: the countdown")
	assert_between(crew.crowd.size(), 5, 10, "one crowd, not two")


## Bug: a rematch once they were home had you held on the grid while they walked
## back to their speeders one by one and drove over from the hangout. Now they are
## set down on their speeders just behind the grid and are there as you line up.
func test_rematch_once_they_are_home_sets_them_behind_the_line() -> void:
	var t = await _town()
	var crew := _crew(t)
	await _race_to_go(t, crew)
	crew._end_race()
	for rc in crew.racers:
		crew._settle_home(rc)                   # parked and off at the hangout, as if home
	assert_eq(crew.rematch(), "", "[Z]: on again")
	var g: Dictionary = crew.course.gates[0]
	var back := RaceCrew.rule("rematch_stage_m", 25.0)
	for rc in crew.racers:
		if bool(rc.out):
			continue
		assert_true(rc.speeder.npc_driven(), "%s is on their speeder at once" % rc.key)
		var s: Dictionary = crew.course.grid_slot(int(rc.slot))
		assert_lt(rc.speeder.model.position.distance_to(s.pos), back + 3.0, "%s just behind their slot" % rc.key)
		assert_lt(((rc.speeder.model.position - (g.pos as Vector3)).dot(g.fwd)), 0.0, "%s behind the line" % rc.key)
	var frames := 0
	for i in 5000:
		if crew.phase == RaceCrew.Phase.COUNTDOWN:
			break
		frames += 1
		await wait_physics_frames(1)
	assert_eq(crew.phase, RaceCrew.Phase.COUNTDOWN, "everyone on the grid: the countdown")
	assert_lt(frames * DT, 15.0, "in seconds, not a walk from the hangout (%.1f s)" % (frames * DT))


func test_short_for_a_rematch_they_go_home_and_the_menu_offers_it_later() -> void:
	var t = await _town()
	var crew := _crew(t)
	await _race_to_go(t, crew)
	WorldState.credits = 60
	crew._end_race()
	assert_false(crew.rematch_on, "60 cr: no rematch at 100")
	assert_eq(crew.last_stake, 100)
	assert_eq(crew.rematch(), "busy", "[Z] does nothing")
	assert_eq(WorldState.credits, 60, "nothing taken")
	Engine.time_scale = 4.0
	for i in 3000:
		if crew.phase == RaceCrew.Phase.IDLE:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_eq(crew.phase, RaceCrew.Phase.IDLE, "they went home")
	assert_false(crew.menu_options().any(func(o): return str(o.id) == "rematch"), "still short: no rematch row")
	WorldState.credits = 100
	var opts := crew.menu_options()
	assert_eq(str(opts[0].id), "rematch", "the same stake, first in the leader's menu")
	assert_true(str(opts[0].text).contains("100"), "at 100 cr")
	crew._on_pick("rematch")
	assert_eq(crew.phase, RaceCrew.Phase.GRID, "on again")
	assert_eq(WorldState.credits, 0, "100 cr paid")


func test_no_rematch_after_pink_slips() -> void:
	var t = await _town()
	var crew := _crew(t)
	await _race_to_go(t, crew)
	crew.pink = true
	crew._end_race()
	assert_false(crew.rematch_on, "pink slips: no rematch")


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
