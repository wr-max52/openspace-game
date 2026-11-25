extends GutTest
## Issue #616: race gear. A seeker locks on to a speeder in your nose and hits it;
## with nobody in the cone there is no lock; a deflector soaks the first hit and
## not the second; a mine goes off under a speeder that drives over it; nitro
## lasts longer than stock; gear comes from the parts fitted and starts full.

const DT := 1.0 / 60.0


func after_each() -> void:
	SpeederMine.clear_all()


func _scene() -> Node3D:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 1, 600)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	floor_body.add_child(col)
	root.add_child(floor_body)
	return root


func _speeder(root: Node3D, parts: Array, at: Vector3, yaw: float = 0.0) -> SpeederNode:
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 3000.0 } })
	var cfg := SpeederUpgrades.apply(HoverModel.load_config("speeder"), { "paint": "", "parts": parts })
	var sp := SpeederNode.new()
	sp.setup(null, g, cfg)
	root.add_child(sp)
	sp.place(at, yaw)
	return sp


func test_gear_comes_from_the_parts_fitted_and_starts_full() -> void:
	var gear := SpeederGear.new(SpeederUpgrades.apply(HoverModel.load_config("speeder"),
		{ "parts": ["seekers", "mines", "deflector"] }))
	assert_eq(gear.seekers, 4, "a full rack")
	assert_eq(gear.mines, 3, "a full dropper")
	assert_true(gear.deflector_up, "the deflector up")
	assert_false(SpeederGear.new(HoverModel.load_config("speeder")).has_any(), "a stock speeder has none")
	for id in ["seekers", "mines", "deflector", "nitro_1", "nitro_2", "nitro_3"]:
		assert_eq(str(SpeederUpgrades.part(id).get("group", "")), "race", "%s is race gear in Dorrin's menu" % id)


func test_a_seeker_locks_on_and_hits() -> void:
	var root := _scene()
	var a := _speeder(root, ["seekers"], Vector3(0, 0, 0))
	var b := _speeder(root, [], Vector3(0, 0, -40))
	await wait_physics_frames(2)
	assert_eq(a.gear.pick_target(a), b.hull, "the speeder in the nose")
	var hp := b.model.hp
	assert_true(a.gear.fire_seeker(a, a.gear.pick_target(a)))
	await wait_physics_frames(60)
	assert_lt(b.model.hp, hp, "hit and damaged")
	assert_eq(a.gear.seekers, 3, "one fewer")


func test_no_lock_on_a_speeder_behind_you() -> void:
	var root := _scene()
	var a := _speeder(root, ["seekers"], Vector3(0, 0, 0))
	_speeder(root, [], Vector3(0, 0, 40))
	await wait_physics_frames(2)
	assert_null(a.gear.pick_target(a), "behind you: no lock")


func test_a_deflector_soaks_the_first_hit_not_the_second() -> void:
	var root := _scene()
	var a := _speeder(root, ["seekers"], Vector3(0, 0, 0))
	var b := _speeder(root, ["deflector"], Vector3(0, 0, -40))
	await wait_physics_frames(2)
	var hp := b.model.hp
	a.gear.fire_seeker(a, b.hull)
	await wait_physics_frames(60)
	assert_eq(b.model.hp, hp, "the first seeker: soaked")
	assert_eq(b.gear.soaked, 1)
	assert_false(b.gear.deflector_up, "and it is down")
	await wait_physics_frames(int(a.gear.seeker_cfg.get("rate", 0.6) / DT) + 2)
	a.gear.fire_seeker(a, b.hull)
	await wait_physics_frames(60)
	assert_lt(b.model.hp, hp, "the second hurts")


func test_a_mine_goes_off_under_a_speeder() -> void:
	var root := _scene()
	var a := _speeder(root, ["mines"], Vector3(0, 0, 0))
	var b := _speeder(root, [], Vector3(0, 0, 30))
	await wait_physics_frames(2)
	assert_true(a.gear.drop_mine(a))
	assert_eq(SpeederMine.live.size(), 1, "one mine down")
	var mine: SpeederMine = SpeederMine.live[0]
	await wait_physics_frames(2)
	assert_false(mine.armed, "not armed at once")
	var hp := b.model.hp
	b.place(mine.global_position, 0.0)       # sitting on it while it arms
	await wait_seconds(1.3)
	assert_true(not is_instance_valid(mine) or mine.armed, "armed after a moment")
	assert_lt(b.model.hp, hp, "it went off under the speeder")
	assert_eq(SpeederMine.live.size(), 0, "and is gone")


func test_mines_are_capped() -> void:
	var root := _scene()
	var a := _speeder(root, ["mines"], Vector3(0, 0, 0))
	await wait_physics_frames(2)
	var cap := int(a.gear.mine_cfg.get("cap", 6))
	for i in cap + 3:
		a.gear.mines = 3
		a.gear._mine_cool = 0.0
		a.place(Vector3(i * 10.0, 0, 0), 0.0)
		a.gear.drop_mine(a)
		await wait_physics_frames(1)
	await wait_physics_frames(2)
	assert_eq(SpeederMine.live.size(), cap, "no more than the cap in the world")


func test_nitro_lasts_longer_than_stock() -> void:
	var stock := HoverModel.load_config("speeder")
	var nitro := SpeederUpgrades.apply(stock, { "parts": ["nitro_2"] })
	var mods: Dictionary = SpeederUpgrades.part("nitro_2").mods
	assert_almost_eq(float(nitro.boost_time), float(stock.boost_time) * float(mods.boost_time), 0.01, "a bigger tank by the configured amount")
	assert_gt(float(nitro.boost_recharge), float(stock.boost_recharge), "and a faster refill")
