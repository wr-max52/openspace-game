extends GutTest
## Issue #699: a trooper finds a silent-kill body only if it can see it: inside
## the distance and the view cone, and with no wall between its eyes and the body.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")


func _npc(at: Vector3, yaw: float) -> NpcBody:
	var cc = CoreScript.new()
	cc.load_from()
	var n := NpcBody.new()
	n.setup(cc.get_soldier("gate_guard"), at, yaw, null)
	add_child_autofree(n)
	return n


## The yaw that faces a body from `from` toward `to` (flat).
func _facing(guard: NpcBody, to: Vector3) -> NpcBody:
	var d := (to - guard.global_position)
	d.y = 0.0
	if d.length() > 0.01 and not guard.forward().normalized().is_equal_approx(d.normalized()):
		guard.rotate_y(guard.forward().signed_angle_to(d, Vector3.UP))
	return guard


func _wall(at: Vector3) -> StaticBody3D:
	var w := StaticBody3D.new()
	var c := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 4.0, 6.0)
	c.shape = box
	w.add_child(c)
	add_child_autofree(w)
	w.global_position = at
	return w


func test_a_body_in_the_open_is_found() -> void:
	var guard := _facing(_npc(Vector3.ZERO, 0.0), Vector3(8, 0, 0))
	var body := _npc(Vector3(8, 0, 0), 0.0)
	body.apply_damage_from(9999.0, null)
	await wait_physics_frames(2)
	assert_true(SilentKill.sees(guard, body.global_position, body), "8 m, in the cone, nothing between")
	assert_eq(SilentKill.finder([guard], [body]), [guard, body])


func test_a_body_behind_a_wall_is_not_found() -> void:
	var guard := _facing(_npc(Vector3.ZERO, 0.0), Vector3(8, 0, 0))
	var body := _npc(Vector3(8, 0, 0), 0.0)
	body.apply_damage_from(9999.0, null)
	_wall(Vector3(4, 2, 0))
	await wait_physics_frames(2)
	assert_true(guard.perception.cone_check(guard.global_position, guard.forward(), body.global_position, false),
		"still inside the cone and the distance")
	assert_false(SilentKill.sees(guard, body.global_position, body), "but the wall hides it")
	assert_eq(SilentKill.finder([guard], [body]), [])
