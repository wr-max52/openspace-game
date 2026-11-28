extends GutTest
## Issue #883: heists get a partner who rides with you and calls the waves, a
## third wave on a speeder near the end of the breach (with a grenade thrown at
## it), and a getaway chase on the ride home. Also the story's first heist stays
## near, never the dry wash, and every speeder has room for a rider.

const TownDemo := preload("res://scenes/town_demo.gd")
const DT := 1.0 / 60.0


func before_each() -> void:
	WorldState.reset()
	WorldState.mode = WorldState.FREEPLAY
	WorldState.story = { "chapter": "free", "told": true }
	GameFlow.planet_id = ""
	Heist._cfg = {}


func after_each() -> void:
	WorldState.reset()
	Heist._cfg = {}
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---- data and pure ------------------------------------------------------------

func test_every_speeder_has_room_for_a_rider() -> void:
	assert_eq(HoverModel.load_config("speeder").get("seats", {}).size(), 4, "the Sand-boxer seats four")
	for id in ["racer", "hauler"]:
		var seats: Dictionary = HoverModel.load_config(id).get("seats", {})
		assert_eq(seats.size(), 2, "%s: a driver and a rider" % id)
	var racer: Dictionary = HoverModel.load_config("racer").seats
	assert_almost_eq(float(racer.rider[2]) - float(racer.driver[2]), 1.0, 0.001, "the racer's rider sits 1 m behind the driver")


func test_story_first_heist_stays_near_and_never_the_dry_wash() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("droid_merchant")
	for i in 3:
		Story.on_droid_delivered()
	assert_eq(Story.chapter(), "heist")
	var never := str(Heist.cfg().get("story_never", ""))
	assert_eq(never, Story.OUTPOSTS[0], "the dry wash: the first bounty and the general's assassination")
	assert_true(str(WorldState.job(Heist.LOCALS_JOB).get("target", "")).ends_with(Heist.STORY_FIRST), "the broken ridge while the Remnant hold it")
	# The locals took the broken ridge: the next nearest the Remnant hold, not a random one.
	WorldState.control[Heist.STORY_FIRST] = { "owner": Territory.LOCALS, "hold": 900.0 }
	Heist._offers.clear()
	var want := ""
	var t := Heist.targets(WorldState.job(Heist.LOCALS_JOB))
	for id in Heist.cfg().story_first:
		if t.has(str(id)):
			want = str(id)
			break
	assert_ne(want, "", "somewhere on the list is still the Remnant's")
	assert_eq(Heist.story_pick(t), want, "the first of the list they hold")
	assert_true(str(WorldState.job(Heist.LOCALS_JOB).get("target", "")).ends_with(want), "offered there")
	# Only the dry wash and one far outpost left: the far one, never the dry wash.
	assert_eq(Heist.story_pick([never, "remnant_outpost_farleap"]), "remnant_outpost_farleap", "not the dry wash")
	assert_eq(Heist.story_pick([never]), never, "unless it is the only one")


func test_once_a_heist_each() -> void:
	assert_true(WorldState.accept_job(Heist.LOCALS_JOB))
	assert_true(Heist.take_once("speeder_waved"), "the first time: send it")
	assert_false(Heist.take_once("speeder_waved"), "once a heist")
	assert_true(Heist.take_once("chased"), "the chase is its own")
	assert_false(Heist.take_once("chased"))
	assert_eq(Heist.wave_paint(Territory.REMNANT), "remnant")
	assert_eq(Heist.wave_paint(Territory.LOCALS), "tide")


## The harass loop on flat sand against a target cruising at 15 m/s: it rams,
## tails and shoots, passes and drops back. Against one boosting away it never
## catches up.
func test_the_getaway_driver_rams_tails_and_passes() -> void:
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 6000.0 } })
	var m := HoverModel.new(HoverModel.load_config("speeder"), g)
	m.place(Vector3(0, 0, 200), 0.0)
	var b := SpeederBrain.new(m, "heist_chaser", 7)
	b.harass = true
	b.pursue()
	var target := Vector3(0, 0, 0)
	var vel := Vector3(0, 0, -15.0)
	var shots := 0
	var t := 0.0
	while t < 90.0 and not (b.rams >= 1 and b.passes >= 1 and shots > 0):
		target += vel * DT
		b.target_pos = target
		b.target_vel = vel
		var c := b.update(DT)
		shots += int(bool(c.fire))
		m.set_command(float(c.throttle), float(c.steer), bool(c.boost))
		m.step(DT)
		t += DT
	assert_gte(b.rams, 1, "it rammed you")
	assert_gt(shots, 0, "it shot from your tail")
	assert_gte(b.passes, 1, "it passed you")
	# Boosting away from 300 m: it never closes.
	m.place(Vector3(0, 0, 300), 0.0)
	b = SpeederBrain.new(m, "heist_chaser", 8)
	b.harass = true
	b.pursue()
	target = Vector3.ZERO
	vel = Vector3(0, 0, -52.0)
	for i in 600:
		target += vel * DT
		b.target_pos = target
		b.target_vel = vel
		var c := b.update(DT)
		m.set_command(float(c.throttle), float(c.steer), bool(c.boost))
		m.step(DT)
	assert_eq(b.rams, 0, "never rammed a boosting speeder")
	assert_gt(m.position.distance_to(target), 300.0, "and the gap opened")


# ---- in the town --------------------------------------------------------------

func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	add_child_autofree(t)
	for i in 1500:
		if t.heist_raid != null and t.heist_crew != null and t.outposts != null and not t.outposts.outposts.is_empty():
			break
		await wait_physics_frames(1)
	assert_not_null(t.heist_raid, "the town builds the heist's speeders")
	return t


func _wait_for(cond: Callable, frames: int) -> bool:
	for i in frames:
		if cond.call():
			return true
		await wait_physics_frames(1)
	return cond.call()


## A heist on: returns its outpost.
func _heist(t) -> Dictionary:
	assert_true(WorldState.accept_job(Heist.LOCALS_JOB), "took the heist")
	var o: Dictionary = t.outposts.outpost(Heist.target())
	assert_false(o.is_empty(), "its outpost is here")
	return o


func _speeder(t, at: Vector3) -> SpeederNode:
	var s := SpeederNode.new()
	s.setup(t, t.pilot.ground, {}, true, "steel")
	t.add_child(s)
	s.place(at, 0.0)
	return s


## Stand the player at `at` with the crew member out beside them.
func _crew_at(t, at: Vector3) -> NpcBody:
	t._player.global_position = at
	assert_true(await _wait_for(func(): return t.heist_crew.body != null, 120), "the crew member is out")
	var body: NpcBody = t.heist_crew.body
	body.global_position = at + Vector3(-2.0, 0.0, 0.0)
	return body


func test_the_crew_rides_along_and_gets_off_across_from_you() -> void:
	var t = await _town()
	var o := _heist(t)
	var out: Vector3 = t.outposts.world_point(o, (o.room.stand as Vector3) + Vector3(80, 0, 0))
	var body := await _crew_at(t, out + Vector3(0, 1.0, 0))
	var s := _speeder(t, out + Vector3(1.5, 1.0, 0))
	await wait_physics_frames(2)
	t._player.global_position = s.model.position + Vector3(1.5, -1.0, 0)
	assert_true(s.mount(), "aboard")
	assert_true(await _wait_for(func(): return s.npc_seats.values().has(body), 30), "the crew hops on behind you")
	assert_eq(t.heist_crew.seat_in, s)
	assert_eq(body.speaking(), "Nice ride, comrade.", "and says so")
	assert_ne(s.npc_seats.find_key(body), "driver", "a rider's seat: the driver's is yours")
	s.dismount()
	assert_true(await _wait_for(func(): return not s.npc_seats.values().has(body), 30), "you got off: so do they")
	var right := s.model.transform().basis.x
	var me: float = (t._player.global_position - s.model.position).dot(right)
	var them: float = (body.global_position - s.model.position).dot(right)
	assert_lt(me * them, 0.0, "across from you (you %.1f, them %.1f along its right)" % [me, them])
	assert_true(body.is_physics_processing(), "on their feet")


func test_the_speeder_wave_comes_at_thirty_seconds_and_they_get_off() -> void:
	var t = await _town()
	var o := _heist(t)
	var ro = t.outposts
	var console: Vector3 = ro.console_point(o)
	t._player.global_position = console
	ro.running_at = str(o.id)
	ro.running = 31.0
	await wait_physics_frames(5)
	assert_null(t.heist_raid.raid, "not before 30 s left")
	ro.running = 29.0
	assert_true(await _wait_for(func(): return t.heist_raid.raid != null, 30), "the speeder wave is sent")
	var s: SpeederNode = t.heist_raid.raid
	assert_eq(s.paint, "remnant", "the robbed side's speeder (the Remnant's, on the locals' heist)")
	assert_eq(s.npc_seats.size(), 4, "four aboard")
	assert_true(s.npc_driven(), "with a driver")
	for b in t.heist_raid.raid_riders:
		assert_eq((b as NpcBody).faction, "imperial_remnant", "the Remnant's troopers")
		assert_true(ro.wave.has(b), "the outpost's wave")
	assert_almost_eq(s.model.position.distance_to(console), 500.0, 60.0, "500 m out")
	assert_false(Heist.take_once("speeder_waved"), "once a heist: a rebuilt town sends no second")
	# Bring it in close and let it pull up.
	var near: Vector3 = ro.world_point(o, (o.room.stand as Vector3) + Vector3(60, 0, 0))
	s.place(near + Vector3(0, 1.0, 0), t.heist_raid._raid_yaw)
	assert_true(await _wait_for(func(): return t.heist_raid.raid_state == "off", 900), "it pulled up by the door")
	assert_true(s.npc_seats.is_empty(), "everyone off")
	for b in t.heist_raid.raid_riders:
		assert_true((b as NpcBody).is_physics_processing(), "%s on foot to fight" % b.name)
	assert_lt(s.model.position.distance_to(t.heist_raid._raid_park), 25.0, "close to the door")


func test_the_crew_grenade_wrecks_it_on_a_hit_and_says_nothing_on_a_miss() -> void:
	var t = await _town()
	var o := _heist(t)
	var out: Vector3 = t.outposts.world_point(o, (o.room.stand as Vector3) + Vector3(90, 0, 0))
	var body := await _crew_at(t, out + Vector3(0, 1.0, 0))
	var crew: HeistCrew = t.heist_crew
	var s := _speeder(t, body.global_position + Vector3(0, 0, -30.0))
	await wait_physics_frames(2)
	crew.force_grenade_hit = 1
	crew.throw_at(s)
	assert_eq(body.speaking(), "Grenade out!", "he calls it")
	assert_true(await _wait_for(func(): return crew.grenade_hits == 1, 240), "a hit")
	assert_false(is_instance_valid(s) and s.model.alive(), "the speeder is wrecked")
	assert_eq(body.speaking(), "Got that one taken care of.", "and says so")
	var s2 := _speeder(t, body.global_position + Vector3(0, 0, -30.0))
	await wait_physics_frames(2)
	crew.force_grenade_hit = 0
	body.say("")
	crew.throw_at(s2)
	await wait_physics_frames(240)
	assert_true(is_instance_valid(s2) and s2.model.alive(), "a miss: still whole")
	assert_eq(crew.grenade_hits, 1, "no hit counted")
	assert_ne(body.speaking(), "Got that one taken care of.", "silent on a miss")


func test_the_getaway_chase_rams_and_you_lose_it_by_getting_away() -> void:
	var t = await _town()
	var o := _heist(t)
	assert_true(Heist.on_hacked(str(o.id), str(o.label)), "the vault is breached")
	Heist.cfg()["getaway"]["give_up_s"] = 0.5
	var at: Vector3 = t.outposts.world_point(o, (o.room.stand as Vector3) + Vector3(200, 0, 0))
	var s := _speeder(t, at + Vector3(0, 1.0, 0))
	await wait_physics_frames(2)
	t._player.global_position = s.model.position + Vector3(1.5, -1.0, 0)
	assert_true(s.mount(), "aboard, 200 m out")
	var hr: HeistRaid = t.heist_raid
	assert_true(await _wait_for(func(): return hr.chaser != null, 30), "a speeder comes after you")
	assert_eq(hr.chase.state, SpeederChase.State.CHASE, "chasing")
	assert_true(hr.chaser.brain.harass, "on the ram-and-pass loop")
	assert_eq(hr.chaser.npc_seats.size(), 2, "a driver and a gunner")
	assert_almost_eq(hr.chaser.model.position.distance_to(s.model.position), 450.0, 60.0, "about 450 m away")
	# A ram: your speeder jolts, slows and takes a dent.
	s.model.speed = 30.0
	var hp := s.model.hp
	hr.chaser.brain.rams += 1
	await wait_physics_frames(2)
	assert_eq(hr.rams, 1, "rammed")
	assert_lt(s.model.speed, 30.0, "slowed")
	assert_lt(s.model.hp, hp, "dented")
	# Get away: far past escape_m, and they give up and are gone.
	s.model.place(s.model.position + (s.model.position - hr.chaser.model.position).normalized() * 1500.0, 0.0)
	assert_true(await _wait_for(func(): return hr.escapes == 1, 300), "they gave up")
	assert_null(hr.chaser, "and are gone")
	assert_false(Heist.take_once("chased"), "once a heist")


func test_get_off_and_they_pull_up_and_leave_their_speeder_to_take() -> void:
	var t = await _town()
	var o := _heist(t)
	assert_true(Heist.on_hacked(str(o.id), str(o.label)))
	var at: Vector3 = t.outposts.world_point(o, (o.room.stand as Vector3) + Vector3(200, 0, 0))
	var s := _speeder(t, at + Vector3(0, 1.0, 0))
	await wait_physics_frames(2)
	t._player.global_position = s.model.position + Vector3(1.5, -1.0, 0)
	assert_true(s.mount())
	var hr: HeistRaid = t.heist_raid
	assert_true(await _wait_for(func(): return hr.chaser != null, 30))
	var c: SpeederNode = hr.chaser
	c.place(s.model.position + Vector3(0, 0, 80.0), c.model.yaw)
	s.dismount()
	assert_true(await _wait_for(func(): return c.npc_seats.is_empty(), 900), "you got off: they pulled up and got off")
	for b in hr.chase_riders:
		assert_true((b as NpcBody).is_physics_processing(), "%s on foot" % b.name)
	assert_true(c.rideable and c.model.alive(), "their speeder sits there for the taking")
