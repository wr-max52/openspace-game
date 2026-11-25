extends GutTest
## Issue #613: the gate chase. The gate speeder can be ridden and stealing it sets
## off the alarm; two guards ride after you on the chase speeder; get off and they
## get off; get away and they give up and park, and the stolen speeder is yours
## (kept across a save, sold to Skrugs); burst the chase speeder and both riders
## live; the locals do the same once they hold the town.

const TownDemo := preload("res://scenes/town_demo.gd")


func before_each() -> void:
	WorldState.reset()
	GateChase._cfg = {}


func after_each() -> void:
	WorldState.reset()
	GateChase._cfg = {}
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	add_child_autofree(t)
	for i in 1200:
		if t.gate_chase != null and t.gate_chase.chaser != null and t.gate_chase.garrison() != null and t.gate_chase._joined:
			break
		await wait_physics_frames(1)
	return t


func _gate(t) -> SpeederNode:
	return t.gate_speeders[0]


func _steal(t) -> SpeederNode:
	var s := _gate(t)
	t._player.global_position = s.model.position + Vector3(1.5, 0.5, 0)
	await wait_physics_frames(2)
	assert_true(s.can_mount(), "the gate speeder can be ridden")
	s.mount()
	return s


func _wait_for(cond: Callable, frames: int) -> bool:
	for i in frames:
		if cond.call():
			return true
		await wait_physics_frames(1)
	return cond.call()


func test_steal_it_and_two_guards_ride_after_you() -> void:
	var t = await _town()
	var gc: GateChase = t.gate_chase
	assert_not_null(gc, "the chase is set up")
	assert_eq(gc.riders.size(), 2, "two guards by the chase speeder")
	var s := await _steal(t)
	assert_true(gc.alarm_up(), "climbing on sets off the alarm")
	s.place(s.model.position + Vector3(60, 0, 0), s.model.yaw)
	assert_true(await _wait_for(func(): return gc.state == GateChase.State.CHASE, 240), "they set off")
	assert_true(gc.chaser.npc_driven(), "a driver")
	assert_not_null(gc.chaser.npc_in("rider"), "and a gunner behind")
	s.dismount()
	assert_true(await _wait_for(func(): return gc.chaser.npc_seats.is_empty(), 900), "you got off: they get off")
	for b in gc.riders:
		assert_true(b.is_physics_processing(), "%s on foot" % b.name)


func test_get_away_and_the_speeder_is_yours_and_skrugs_buys_it() -> void:
	var t = await _town()
	var gc: GateChase = t.gate_chase
	GateChase.cfg()["give_up_s"] = 1.0
	var s := await _steal(t)
	s.place(s.model.position + Vector3(60, 0, 0), s.model.yaw)
	assert_true(await _wait_for(func(): return gc.state == GateChase.State.CHASE, 240), "they set off")
	s.place(s.model.position + Vector3(1200, 0, 0), s.model.yaw)
	t._player.global_position = s.model.position
	assert_true(await _wait_for(func(): return gc.escapes > 0, 300), "they gave up")
	assert_eq(gc.kept, 1, "the stolen speeder is yours")
	assert_eq(WorldState.count("speeders_owned"), 1)
	assert_true(bool(WorldState.speeder_fits[0].get("stolen", false)), "marked stolen")
	assert_eq(str(WorldState.speeder_fits[0].paint), "remnant", "in the Remnant's paint")
	assert_true(await _wait_for(func(): return gc.state == GateChase.State.IDLE, 2400), "they drove home")
	assert_lt(gc.chaser.model.position.distance_to(gc.home.origin), 6.0, "and parked on the marker")
	var saved := WorldState.to_save()
	WorldState.reset()
	WorldState.from_save(saved)
	var t2 = await _town()
	var post: SpeederPost = t2.speeder_post
	assert_eq(post.speeders.size(), 1, "after a boot it is in the row")
	assert_eq(post.speeders[0].paint, "remnant")
	var before := WorldState.credits
	assert_eq(t2.gate_chase.sell(post.speeders[0]), int(GateChase.n("sell_price", 350)), "Skrugs buys it")
	assert_eq(WorldState.credits, before + int(GateChase.n("sell_price", 350)))
	assert_eq(post.speeders.size(), 0, "gone for good")
	assert_eq(WorldState.count("speeders_owned"), 0)


func test_burst_the_chase_speeder_and_both_riders_fight_on() -> void:
	var t = await _town()
	var gc: GateChase = t.gate_chase
	GateChase.cfg()["respawn_s"] = 1.0
	var s := await _steal(t)
	s.place(s.model.position + Vector3(60, 0, 0), s.model.yaw)
	assert_true(await _wait_for(func(): return gc.state == GateChase.State.CHASE, 240), "they set off")
	gc.chaser.apply_damage(1.0e6)
	await wait_physics_frames(10)
	for b in gc.riders:
		assert_false(b.dead, "%s alive" % b.name)
		assert_true(b.is_physics_processing(), "%s on their feet" % b.name)
	assert_true(await _wait_for(func(): return gc.chaser != null and is_instance_valid(gc.chaser), 240), "a new chase speeder later")


func test_the_locals_do_the_same_once_they_hold_the_town() -> void:
	WorldState.set_flag(str(Territory.front(Territory.HOME).driven_off))
	var t = await _town()
	var gc: GateChase = t.gate_chase
	assert_eq(gc.holder_now, "locals")
	assert_eq(_gate(t).paint, GateChase.paint_for("locals"), "the locals' gate speeder")
	assert_eq(gc.chaser.paint, GateChase.paint_for("locals"), "and chase speeder")
	for b in gc.riders:
		assert_eq(str(b.profile.get("faction", "")), "locals", "locals ride it")
	if gc.garrison() == null:
		pending("no locals' gate garrison in this town save")
		return
	var s := await _steal(t)
	assert_true(gc.alarm_up(), "their alarm")
	s.place(s.model.position + Vector3(60, 0, 0), s.model.yaw)
	assert_true(await _wait_for(func(): return gc.state == GateChase.State.CHASE, 240), "they ride after you")
