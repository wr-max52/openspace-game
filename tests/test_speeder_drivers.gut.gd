extends GutTest
## Issue #609: NPCs who drive a speeder. SpeederBrain drives the player's own
## HoverModel (lap a loop without touching a building, close on and fire at a
## moving target, flee, park, back off when stuck), and NPC bodies climb on, ride,
## get off and are thrown clear alive when it bursts.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const DT := 1.0 / 60.0

var cfg: Dictionary
var content


func before_each() -> void:
	cfg = HoverModel.load_config("speeder")
	content = CoreScript.new()
	content.load_from()


## Flat sand with a block of buildings in the middle of the loop.
func _ground() -> WorldGround:
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 3000.0 } })
	g.add_box("block", "solid", Vector3(-40, 0, -40), Vector3(40, 8, 40))
	return g


func _model(at: Vector3, yaw: float = 0.0, g: WorldGround = null) -> HoverModel:
	var m := HoverModel.new(cfg, g if g != null else _ground())
	m.place(at, yaw)
	return m


func _step(m: HoverModel, b: SpeederBrain) -> Array:
	var c := b.update(DT)
	m.set_command(float(c.throttle), float(c.steer), bool(c.boost))
	return m.step(DT)


# ---- driving ------------------------------------------------------------------

func test_a_driver_laps_a_loop_round_the_buildings_without_touching_them() -> void:
	var m := _model(Vector3(-90, 0, 90), 0.0)
	var b := SpeederBrain.new(m, "racer")
	b.follow([Vector3(-90, 0, -90), Vector3(90, 0, -90), Vector3(90, 0, 90), Vector3(-90, 0, 90)], true)
	var bumps := 0
	var t := 0.0
	while b.laps < 3 and t < 120.0:
		for e in _step(m, b):
			bumps += int(e.type == "bump")
		t += DT
	assert_eq(b.laps, 3, "three laps")
	assert_lt(t, 75.0, "inside the time (720 m a lap)")
	assert_eq(bumps, 0, "never touched the buildings")


func test_a_line_ends_and_says_so() -> void:
	var m := _model(Vector3(-200, 0, 0), 0.0)
	var b := SpeederBrain.new(m)
	b.follow([Vector3(-200, 0, -150)], false)
	var t := 0.0
	while not b.done and t < 30.0:
		_step(m, b)
		t += DT
	assert_true(b.done, "reached the end of the line")


func test_a_pursuer_closes_on_a_moving_target_and_fires() -> void:
	var m := _model(Vector3(-300, 0, 300), 0.0)
	var b := SpeederBrain.new(m, "chaser")
	b.pursue()
	var target := Vector3(-300, 0, 150)
	var vel := Vector3(0, 0, -20)
	var fired := 0
	var t := 0.0
	while t < 20.0:
		target += vel * DT
		b.target_pos = target
		b.target_vel = vel
		_step(m, b)
		fired += int(b.command.fire)
		t += DT
	var gap := Vector2(m.position.x - target.x, m.position.z - target.z).length()
	assert_lt(gap, b.s("hold_range", 30.0) + 20.0, "closed to its range (gap %.0f m)" % gap)
	assert_gt(fired, 0, "and fired")


func test_a_fleer_opens_the_gap_on_a_slower_target() -> void:
	var m := _model(Vector3(300, 0, 0), 0.0)
	var b := SpeederBrain.new(m, "runner")
	b.flee()
	var chaser := Vector3(300, 0, 40)
	var start := 40.0
	var t := 0.0
	while t < 12.0:
		var to := (m.position - chaser)
		to.y = 0.0
		chaser += to.normalized() * 22.0 * DT      # slower than a speeder's top speed
		b.target_pos = chaser
		_step(m, b)
		t += DT
	var gap := Vector2(m.position.x - chaser.x, m.position.z - chaser.z).length()
	assert_gt(gap, start + 40.0, "ran away from it (gap %.0f m)" % gap)


func test_pace_eases_a_fleer_off() -> void:
	var fast := _model(Vector3(300, 0, 300), 0.0)
	var slow := _model(Vector3(300, 0, 300), 0.0)
	var bf := SpeederBrain.new(fast, "runner")
	var bs := SpeederBrain.new(slow, "runner")
	bf.flee()
	bs.flee()
	bs.pace = 0.5
	for i in 300:
		bf.target_pos = Vector3(300, 0, 340)
		bs.target_pos = Vector3(300, 0, 340)
		_step(fast, bf)
		_step(slow, bs)
	assert_lt(slow.speed, fast.speed - 8.0, "half pace drives slower")


func test_a_driver_parks_on_the_spot_facing_the_way() -> void:
	var m := _model(Vector3(-200, 0, -200), 0.0)
	var b := SpeederBrain.new(m)
	b.park(Vector3(-200, 0, -260), PI * 0.5)
	var t := 0.0
	while not b.done and t < 20.0:
		_step(m, b)
		t += DT
	assert_true(b.done, "parked")
	assert_lt(Vector2(m.position.x + 200.0, m.position.z + 260.0).length(), 4.0, "on the spot")
	assert_lt(absf(wrapf(m.yaw - PI * 0.5, -PI, PI)), deg_to_rad(10.0), "facing the way")


func test_a_driver_steers_round_what_it_is_told_to_avoid() -> void:
	var m := _model(Vector3(-300, 0, -300), 0.0)
	var b := SpeederBrain.new(m)
	b.follow([Vector3(-300, 0, -500)], false)
	var rock := Vector3(-300, 0, -380)
	var closest := INF
	var t := 0.0
	while not b.done and t < 20.0:
		b.avoid = [{ "pos": rock, "radius": 4.0 }]
		_step(m, b)
		closest = minf(closest, Vector2(m.position.x - rock.x, m.position.z - rock.z).length())
		t += DT
	assert_true(b.done, "still got there")
	assert_gt(closest, 4.0 + float(cfg.body_radius), "and never touched it (closest %.1f m)" % closest)


func test_a_stuck_driver_backs_off_and_tries_again() -> void:
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 3000.0 } })
	g.add_box("wall", "solid", Vector3(-60, 0, -12), Vector3(60, 8, -10))
	var m := _model(Vector3(0, 0, -6), 0.0, g)
	var b := SpeederBrain.new(m)
	b.skill["look_min"] = 0.0          # blind to the wall: drives straight into it
	b.skill["look_ahead_s"] = 0.0
	b.follow([Vector3(0, 0, -200)], false)
	var reversed := false
	for i in 600:
		_step(m, b)
		reversed = reversed or m.speed < -1.0
	assert_gt(b.stuck_events, 0, "it noticed it was stuck")
	assert_true(reversed, "and backed off")


func test_skills_are_data() -> void:
	var d := SpeederBrain.skill_block("default")
	var ace := SpeederBrain.skill_block("ace")
	assert_true(d.has("steer_gain") and d.has("hold_range"), "the default skill block")
	assert_ne(float(ace.boost), float(d.boost), "a named skill overrides the default")
	assert_eq(float(ace.hold_range), float(d.hold_range), "and keeps what it does not name")
	assert_gt(SpeederBrain.rule("stuck_s", 0.0), 0.0, "rules come from the file")


# ---- getting on and off -----------------------------------------------------------

func _scene() -> Node3D:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	floor_body.add_child(col)
	root.add_child(floor_body)
	return root


func _speeder(root: Node3D) -> SpeederNode:
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 3000.0 } })
	var sp := SpeederNode.new()
	sp.setup(null, g, cfg)
	root.add_child(sp)
	sp.place(Vector3.ZERO, 0.0)
	return sp


func _local(root: Node3D, at: Vector3) -> NpcBody:
	var n := NpcBody.new()
	n.setup(content.get_soldier("gate_guard"), at, 0.0, null)
	root.add_child(n)
	return n


func test_a_body_boards_rides_fifty_metres_and_gets_off_on_its_feet() -> void:
	var root := _scene()
	var sp := _speeder(root)
	var n := _local(root, Vector3(-8, 0, 0))
	await wait_physics_frames(2)
	assert_true(sp.board(n, "driver"), "sent to the driver's seat")
	var t := 0
	while not sp.npc_driven() and t < 900:
		await wait_physics_frames(1)
		t += 1
	assert_true(sp.npc_driven(), "walked up and climbed on")
	assert_false(sp.can_mount(), "not yours to climb on while they ride it")
	sp.brain = SpeederBrain.new(sp.model)
	sp.brain.follow([Vector3(0, 0, -50)], false)
	t = 0
	while not sp.brain.done and t < 900:
		await wait_physics_frames(1)
		t += 1
	assert_true(sp.brain.done, "drove there")
	assert_lt(n.global_position.distance_to(sp.model.position), 2.5, "the driver went with it")
	sp.brain.park(sp.model.position, sp.model.yaw)
	await wait_physics_frames(60)
	assert_true(sp.step_off(), "got off")
	await wait_physics_frames(30)
	assert_false(sp.npc_driven(), "nobody drives it")
	assert_true(n.is_physics_processing(), "walking again")
	assert_lt(absf(n.global_position.y), 0.6, "on the sand")
	assert_gt(Vector2(n.global_position.x - sp.model.position.x, n.global_position.z - sp.model.position.z).length(), 1.5, "beside it")
	assert_lt(n.global_position.z, -30.0, "fifty metres on from where it got on")


func test_a_second_rider_sits_behind_the_driver() -> void:
	var root := _scene()
	var sp := _speeder(root)
	var a := _local(root, Vector3(1, 0, 0))
	var b := _local(root, Vector3(-1, 0, 0))
	await wait_physics_frames(2)
	assert_true(sp.seat_npc(a, "driver"))
	assert_true(sp.seat_npc(b, "rider"))
	assert_false(sp.board(_local(root, Vector3(0, 0, 2)), "rider"), "the seat is taken")
	await wait_physics_frames(2)
	var back := sp.model.transform().basis.z
	assert_gt((b.global_position - a.global_position).dot(back), 0.5, "the rider sits behind the driver")


func test_a_burst_throws_both_riders_clear_alive() -> void:
	var root := _scene()
	var sp := _speeder(root)
	var a := _local(root, Vector3(1, 0, 0))
	var b := _local(root, Vector3(-1, 0, 0))
	await wait_physics_frames(2)
	sp.seat_npc(a, "driver")
	sp.seat_npc(b, "rider")
	var hp: int = a.health.hp
	sp.apply_damage(1.0e6)
	await wait_physics_frames(20)
	for n: NpcBody in [a, b]:
		assert_false(n.dead, "%s is alive" % n.name)
		assert_true(n.is_physics_processing(), "%s is back on its feet" % n.name)
		assert_lt(absf(n.global_position.y), 0.6, "%s is on the sand" % n.name)
	assert_lt(int(a.health.hp), hp, "a little hurt")
	assert_ne(a.global_position.distance_to(b.global_position), 0.0, "not on top of each other")
