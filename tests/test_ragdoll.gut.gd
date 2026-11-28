extends GutTest
## Issue #25: bodies fall as ragdolls. A trooper dropped on a floor lands lying down,
## away from the shot, with every bone its own length, then sleeps; stop() stands it
## back up exactly as it was.

var kit: CharacterKit
var world: Node3D
var body: Node3D


func before_each() -> void:
	kit = CharacterKit.new(LookMaterials.new())
	world = Node3D.new()
	add_child_autofree(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	world.add_child(floor_body)
	body = kit.build("trooper")
	world.add_child(body)
	await wait_physics_frames(2)


func _drop(kick: Vector3, seconds := 4.0, up := Vector3.UP) -> Ragdoll:
	var r := Ragdoll.new(body.get_meta("joints"))
	r.start(Vector3.ZERO, kick, world.get_world_3d().direct_space_state, [], up)
	var dt := 1.0 / 60.0
	for i in int(seconds * 60.0):
		r.step(dt)
	return r


func test_falls_flat_and_rests_on_the_floor() -> void:
	var r := _drop(Vector3(0, 0, 3))
	var head := r.point("head")
	var pelvis := r.point("pelvis")
	assert_lt(head.y, 0.45, "the head ends near the ground (%s)" % head)
	assert_lt(pelvis.y, 0.4, "the pelvis ends near the ground (%s)" % pelvis)
	for p in ["head", "pelvis", "l_toe", "r_hand"]:
		assert_gt(r.point(p).y, -0.05, p + " stays above the floor")
	assert_true(r.asleep, "it goes to sleep once it stops")


## Flung off a landing in the cruiser's ramp shaft, a body was still falling when
## max_seconds ran out and hung in the air. It falls on until it lands (or, over
## nothing at all, until max_fall_seconds).
func test_a_body_still_in_the_air_does_not_hang_there() -> void:
	body.position = Vector3(0, 2000, 100)        # off the floor's edge, nothing below
	await wait_physics_frames(1)
	var cfg := Ragdoll.load_config()
	var r := _drop(Vector3(0, 0, 3), float(cfg.max_seconds) + 1.0)
	assert_false(r.asleep, "still falling past max_seconds: awake")
	assert_lt(r.point("pelvis").y, 2000.0 - 50.0, "and it has fallen a long way")
	var dt := 1.0 / 60.0
	for i in int((float(cfg.max_fall_seconds) - float(cfg.max_seconds)) * 60.0):
		r.step(dt)
	assert_true(r.asleep, "over nothing at all it gives up at max_fall_seconds")


func test_falls_away_from_the_shot() -> void:
	var start := (body.get_meta("joints").head as Node3D).global_position
	var r := _drop(Vector3(3, 0, 0))
	assert_gt(r.point("head").x - start.x, 0.4, "pushed toward +X, the head lands on that side")


func test_bones_keep_their_length() -> void:
	var j: Dictionary = body.get_meta("joints")
	var thigh := (j.l_hip as Node3D).global_position.distance_to((j.l_knee as Node3D).global_position)
	var arm := (j.r_shoulder as Node3D).global_position.distance_to((j.r_elbow as Node3D).global_position)
	var r := _drop(Vector3(0, 0, -3))
	assert_almost_eq(r.point("l_hip").distance_to(r.point("l_knee")), thigh, 0.03)
	assert_almost_eq(r.point("r_shoulder").distance_to(r.point("r_elbow")), arm, 0.03)
	# The joints follow the particles: the knee joint sits on the knee particle.
	assert_almost_eq((j.l_knee as Node3D).global_position.distance_to(r.point("l_knee")), 0.0, 0.08)


func test_stop_puts_the_pose_back() -> void:
	var j: Dictionary = body.get_meta("joints")
	var before := {}
	for jn in j:
		before[jn] = (j[jn] as Node3D).transform
	var r := _drop(Vector3(2, 0, 0), 1.0)
	assert_ne((j.pelvis as Node3D).transform, before.pelvis, "the body moved")
	r.stop()
	for jn in j:
		assert_eq((j[jn] as Node3D).transform, before[jn], jn + " is back")


## Far round the home planet's ball (the Blue Basin, ~32 degrees from town) the
## ground and the body are turned with the ball. Falling along world down, a body
## killed there slid off across the slope; falling along the ground's own down it
## lands and lies just as it does on flat ground in town.
func test_on_ground_turned_with_the_ball_it_lies_where_it_falls() -> void:
	var flat := _drop(Vector3(3, 0, 0), 6.0)
	var flat_pelvis := flat.point("pelvis")
	flat.stop()
	world.basis = Basis(Vector3.RIGHT, deg_to_rad(32.0))
	await wait_physics_frames(2)
	var up := world.global_basis.y
	var r := _drop(world.global_basis * Vector3(3, 0, 0), 6.0, up)
	var pelvis := world.global_transform.affine_inverse() * r.point("pelvis")
	assert_almost_eq(pelvis.y, flat_pelvis.y, 0.1, "it lies on the turned ground (%s)" % pelvis)
	assert_lt(Vector2(pelvis.x - flat_pelvis.x, pelvis.z - flat_pelvis.z).length(), 0.3,
		"and where it fell, not slid off down the slope (%s vs flat %s)" % [pelvis, flat_pelvis])
	assert_true(r.asleep, "and it goes to sleep")


func test_kick_runs_along_the_ground_it_stands_on() -> void:
	var cfg := Ragdoll.load_config()
	var up := Basis(Vector3.RIGHT, deg_to_rad(32.0)).y
	var k := Ragdoll.kick_for(Vector3(5, 0, 0), Vector3.ZERO, 20.0, cfg, up)
	assert_gt(k.x, 0.0, "away from the shooter")
	assert_gt(k.dot(up), 0.0, "lifted off the turned ground, not world up")
	assert_almost_eq(k.normalized().dot(up), float(cfg.kick_up) / Vector2(1.0, float(cfg.kick_up)).length(), 0.001)


func test_kick_points_away_from_the_shooter() -> void:
	var cfg := Ragdoll.load_config()
	var k := Ragdoll.kick_for(Vector3(5, 0, 0), Vector3.ZERO, 20.0, cfg)
	assert_gt(k.x, 0.0)
	assert_gt(k.y, 0.0, "a little lift")
	assert_between(k.length(), float(cfg.kick_min), float(cfg.kick_max) + 0.001)
	assert_eq(Ragdoll.kick_for(Vector3.ZERO, Vector3.INF, 20.0, cfg), Vector3.ZERO, "no shooter, no push")


## A dead man's gun (Ragdoll.drop: a RigidBody3D). On a floor turned with the ball
## (a skimmer outpost's deck over the ringed giant is turned 52 degrees, steeper
## than the gun's friction holds), falling along world down it slid away across the
## deck; along the ground's own down it lands where it was dropped and lies still.
func _gun(at: Vector3) -> Node3D:
	var item := Node3D.new()
	item.name = "Rifle"
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.12, 0.1)
	mi.mesh = bm
	item.add_child(mi)
	world.add_child(item)
	item.global_position = at
	return item


func test_a_dropped_gun_lies_where_it_falls_on_ground_turned_with_the_ball() -> void:
	body.visible = false
	world.basis = Basis(Vector3.RIGHT, deg_to_rad(52.0))
	await wait_physics_frames(2)
	var up := world.global_basis.y
	var cfg := Ragdoll.load_config()
	var item := _gun(world.global_transform * Vector3(0, 0.8, 0))
	var rb := Ragdoll.drop(item, world, Vector3.ZERO, cfg, up)
	assert_not_null(rb)
	if rb == null:
		return
	rb.angular_velocity = Vector3.ZERO
	await wait_seconds(3.0)
	var at := world.global_transform.affine_inverse() * rb.global_position
	assert_lt(at.y, 0.3, "it came down onto the turned floor (%s)" % at)
	assert_lt(Vector2(at.x, at.z).length(), 0.6, "and lies where it was dropped, not slid away (%s)" % at)
	assert_lt(rb.linear_velocity.length(), 0.05, "and lies still")


func test_a_dropped_gun_in_town_still_falls_straight_down() -> void:
	body.visible = false
	var cfg := Ragdoll.load_config()
	var item := _gun(Vector3(0, 0.8, 0))
	var rb := Ragdoll.drop(item, world, Vector3.ZERO, cfg)
	rb.angular_velocity = Vector3.ZERO
	await wait_seconds(2.0)
	assert_lt(rb.global_position.y, 0.3, "on the floor")
	assert_lt(Vector2(rb.global_position.x, rb.global_position.z).length(), 0.6, "where it fell")
	assert_eq(rb.gravity_scale, 1.0, "world gravity, unchanged")
