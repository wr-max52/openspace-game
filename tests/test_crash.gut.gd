extends GutTest
## Issue #404: crashes. The fall is pure maths (CrashPath): the same start gives the
## same poses, it ends exactly on the sand and never goes under it. The wreck
## (CrashWreck) moves through spiral, sink, burn and cold in order and frees itself
## once it is out of sight and far enough away.

const DT := 1.0 / 60.0


## Flat sand at y = 0.
func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


## Rolling dunes: the path must still stop on them.
func _dunes(p: Vector3) -> Vector3:
	return Vector3(p.x, 1.5 * sin(p.x * 0.07) + 0.8 * cos(p.z * 0.11), p.z)


func _start(h := 12.0) -> Dictionary:
	return { "pos": Vector3(0, h, 0), "basis": Basis.IDENTITY, "up": Vector3.UP, "vel": Vector3(0, -2, -40) }


func test_same_start_same_path() -> void:
	var cfg := CrashPath.for_kind("speeder")
	var g := Callable(self, "_dunes")
	var ti := CrashPath.impact_time(_start(), cfg, g)
	for t in [0.0, 0.3, 0.9, ti, ti + 2.0]:
		var a: Dictionary = CrashPath.pose(_start(), t, cfg, g)
		var b: Dictionary = CrashPath.pose(_start(), t, cfg, g)
		assert_eq(a.xf, b.xf, "pose at %.2f s repeats" % t)


func test_ends_on_the_sand_never_under_it() -> void:
	for kind in ["speeder", "ship", "barge"]:
		var cfg := CrashPath.for_kind(kind)
		for g in [Callable(self, "_flat"), Callable(self, "_dunes")]:
			var ti := CrashPath.impact_time(_start(), cfg, g)
			assert_gt(ti, 0.0, "%s falls for a while" % kind)
			assert_lt(ti, float(cfg.max_fall_s), "%s lands before the limit" % kind)
			var t := 0.0
			while t < ti + 1.0:
				var p: Dictionary = CrashPath.pose(_start(), t, cfg, g, ti)
				var h := CrashPath.height(p.xf.origin, Vector3.UP, g)
				assert_true(h >= -0.0001, "%s never under the sand (t %.2f, h %.4f)" % [kind, t, h])
				t += DT
			var end: Dictionary = CrashPath.pose(_start(), ti + 5.0, cfg, g, ti)
			assert_true(end.landed, "%s has landed" % kind)
			assert_almost_eq(CrashPath.height(end.xf.origin, Vector3.UP, g), 0.0, 0.0001, "%s ends exactly on the sand" % kind)


func test_it_spins_and_moves_on() -> void:
	var cfg := CrashPath.for_kind("speeder")
	var a := CrashPath.free_pose(_start(), 0.0, cfg)
	var b := CrashPath.free_pose(_start(), 0.5, cfg)
	assert_lt(b.origin.z, a.origin.z - 5.0, "it keeps going the way it was")
	assert_gt(rad_to_deg(a.basis.x.angle_to(b.basis.x)), 45.0, "and rolls round its nose")


func test_wreck_timeline_and_despawn() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var cam := Camera3D.new()
	parent.add_child(cam)
	cam.global_position = Vector3(0, 5, 20)
	var look := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 0.6, 3.0)
	mi.mesh = box
	look.add_child(mi)
	parent.add_child(look)
	var w := CrashWreck.spawn(parent, "speeder", look, _start(4.0), Callable(self, "_flat"))
	assert_not_null(w, "a wreck")
	w.camera_fn = func(): return cam
	var seen: Array = [w.phase]
	w.phase_changed.connect(func(p): seen.append(p))
	var cfg: Dictionary = w.cfg
	var total := w.t_impact + float(cfg.smoke_s) + 1.0
	var t := 0.0
	while t < total:
		w._process(0.1)
		t += 0.1
	assert_eq(seen, [CrashWreck.SPIRAL, CrashWreck.SINK, CrashWreck.BURN, CrashWreck.COLD], "spiral, sink, burn, cold in order")
	assert_eq(w.halves.size(), 2, "split in two")
	assert_true(not is_instance_valid(look) or look.is_queued_for_deletion(), "the whole model is gone, the halves stand for it")
	for h in w.halves:
		assert_gt((h as Node3D).get_child_count(), 0, "each half has its pieces")
	assert_false(w.is_queued_for_deletion(), "still here while the camera is close")
	cam.global_position = Vector3(0, 5, 2000)
	cam.look_at(Vector3(0, 5, 4000))
	w._process(1.1)
	assert_true(w.is_queued_for_deletion(), "frees itself out of sight and far away")
