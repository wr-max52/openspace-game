extends GutTest
## Your droids' safety. E beside an assassin or floating droid of yours turns its
## safety on (it shoots nobody, its eyes go blue) or off (red); it is saved with
## the droid. The weapon wheel's slot 9 (and key 9) toggles every armed droid at
## once: on if any is off, else all off. Cargo droids have no gun and no safety.

const PlayerBody := preload("res://src/systems/player/character_body.gd")
const CameraRigNode := preload("res://src/systems/camera/camera_rig_node.gd")


class FakePlayer extends CharacterBody3D:
	var piloting := false
	var locked := false
	var vehicle: Node


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()


func _scene() -> Array:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	floor_body.add_child(col)
	root.add_child(floor_body)
	var p := FakePlayer.new()
	root.add_child(p)
	var ctl := DroidController.new()
	ctl.setup(null, p, null)
	root.add_child(ctl)
	ctl.vendor_sites.append({ "id": "port_market", "pos": Vector3(-60, 0, 0), "face": Vector3(0, 0, 1), "label": "Droid Merchant" })
	ctl._select_vendor(0)
	WorldState.credits = 100000
	return [ctl, p]


func _eye(u) -> Color:
	return ((DroidKit.eyes(u.look)[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color


func test_e_toggles_one_droids_safety_its_eyes_and_the_save() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	var p: FakePlayer = s[1]
	assert_eq(ctl.buy("assassin"), "bought")
	var uid := int(WorldState.droids.owned[0].uid)
	await wait_physics_frames(3)
	var u = ctl.companions[uid]
	var sc: Dictionary = DroidRoster.config().safety
	assert_false(DroidRoster.safety_on(WorldState.droids.find(uid)), "a new droid's safety is off")
	assert_eq(_eye(u), Color(str(sc.eye_armed)), "red eyes: armed")
	ctl.vendor_sites.clear()                              # nothing else in reach for E
	p.global_position = u.global_position + Vector3(0.8, 0, 0)
	ctl.focus = ctl._find_focus()
	assert_eq(str(ctl.focus.get("kind", "")), "safety", "E beside it is its safety")
	assert_string_contains(ctl.prompt_text(), "Safety ON")
	assert_eq(ctl.interact(), "safety_on")
	assert_true(DroidRoster.safety_on(WorldState.droids.find(uid)))
	assert_eq(_eye(u), Color(str(sc.eye_safe)), "blue eyes: safe")
	# Safe: it lets go of whoever it was after and does not pick anyone new.
	u.target = p
	ctl._companion_guns(0.1)
	assert_null(u.target, "it shoots nobody")
	var loaded := DroidRoster.new()
	loaded.from_save(JSON.parse_string(JSON.stringify(WorldState.droids.to_save())))
	assert_true(DroidRoster.safety_on(loaded.find(uid)), "on survives a save")
	ctl.focus = {}
	assert_eq(ctl.interact(), "safety_off")
	assert_eq(_eye(u), Color(str(sc.eye_armed)), "red again")
	loaded.from_save(JSON.parse_string(JSON.stringify(WorldState.droids.to_save())))
	assert_false(DroidRoster.safety_on(loaded.find(uid)), "and so does off")


func test_toggle_all_turns_every_armed_droid_on_then_off_and_skips_cargo() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	assert_false(ctl.toggle_all_safety(), "no droids: nothing to toggle")
	assert_eq(ctl.buy("assassin"), "bought")
	assert_eq(ctl.buy("floating"), "bought")
	assert_eq(ctl.buy("cargo"), "bought")
	var r := WorldState.droids
	r.set_safety(int(r.owned[0].uid), true)              # one already on: mixed
	assert_false(ctl.all_safe())
	assert_true(ctl.toggle_all_safety(), "any off: all on")
	assert_true(ctl.all_safe())
	for d in r.owned:
		assert_eq(DroidRoster.safety_on(d), str(d.kind) != "cargo", "%s" % d.kind)
	assert_false(ctl.toggle_all_safety(), "all on: all off")
	for d in r.owned:
		assert_false(DroidRoster.safety_on(d))
	assert_false(r.set_safety(int(r.owned[2].uid), true), "a cargo droid has no safety")


func _kit() -> PlayerWeapons:
	var p := PlayerBody.new()
	add_child_autofree(p)
	var bolts := Node3D.new()
	add_child_autofree(bolts)
	var rig := CameraRigNode.new()
	add_child_autofree(rig)
	return PlayerKit.attach(p, rig, bolts, LookMaterials.new()).weapons


func test_wheel_slot_9_and_key_9_toggle_and_draw_nothing() -> void:
	var pw := _kit()
	var runs := [0]
	var armed := [false]
	assert_false(pw.wheel.selectable(8), "dim with no droids to toggle")
	pw.add_action("droid_safety", func(): runs[0] += 1, func() -> bool: return armed[0],
		func() -> Dictionary: return { "name": "Droids", "detail": "SAFETY OFF", "verb": "Toggle" })
	assert_false(pw.wheel.selectable(8), "still dim with none armed")
	armed[0] = true
	assert_true(pw.wheel.selectable(8))
	assert_eq(str(pw._wheel_info("droid_safety").name), "Droids")
	var tab := InputEventAction.new()
	tab.action = "weapon_cycle"
	tab.pressed = true
	pw._unhandled_input(tab)
	for i in 20:
		pw._physics_process(1.0 / 60.0)
	assert_true(pw.wheel.is_open)
	var mm := InputEventMouseMotion.new()
	mm.relative = WeaponWheel.slot_dir(8) * pw.wheel.mouse_pixels
	pw._unhandled_input(mm)
	assert_eq(pw.wheel.choice(), "droid_safety")
	tab = InputEventAction.new()
	tab.action = "weapon_cycle"
	tab.pressed = false
	pw._unhandled_input(tab)
	assert_eq(runs[0], 1, "letting go on slot 9 toggles")
	assert_eq(pw.holder.current, "", "and draws nothing")
	var nine := InputEventAction.new()
	nine.action = "weapon_9"
	nine.pressed = true
	pw._unhandled_input(nine)
	assert_eq(runs[0], 2, "key 9 toggles too")
	assert_eq(pw.holder.current, "")
