extends GutTest
## Issue #392: the moon rave's droid merchant sells a floating droid and the laser
## rig, sold nowhere else. A rig is dark until E beside the droid turns it on.
## Lasers on means music on: E steps off -> lasers with rave music -> with cantina
## music -> no music -> off. The mode is saved with the droid. Knocked out it goes
## dark and quiet, and it comes back with the droid when it reboots.


class FakePlayer extends CharacterBody3D:
	var piloting := false
	var locked := false
	var vehicle: Node


func before_each() -> void:
	WorldState.reset()
	_quiet()


func after_each() -> void:
	_quiet()


## No droid music left over from another test (without making the library just for that).
func _quiet() -> void:
	if is_instance_valid(Sound._lib):
		Sound.set_droid("", 0.0)


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
	return [ctl, p]


## The merchants: the market's (as at the port) and the moon rave's, far apart.
func _sites(ctl: DroidController) -> void:
	var cv: Dictionary = DroidRoster.config().club_vendor
	ctl.vendor_sites.append({ "id": "port_market", "pos": Vector3(-60, 0, 0), "face": Vector3(0, 0, 1), "label": "Droid Merchant" })
	ctl.vendor_sites.append({ "id": str(cv.id), "pos": Vector3(60, 0, 0), "face": Vector3(0, 0, 1), "label": str(cv.label),
		"stock": cv.stock, "sells": str(cv.sells) })


func test_the_rig_is_sold_only_at_the_rave_and_fits_only_floating_droids() -> void:
	assert_eq(DroidRoster.upgrades_for("floating"), ["health", "damage"], "the other merchants' list is as it was")
	assert_eq(DroidRoster.upgrades_for("floating", "rave"), ["lasers"], "the rave's merchant sells the rig")
	assert_eq(DroidRoster.upgrades_for("assassin", "rave"), [], "for floating droids only")
	assert_eq(DroidRoster.upgrades_for("cargo", "rave"), [])
	var s := _scene()
	var ctl: DroidController = s[0]
	_sites(ctl)
	ctl._select_vendor(1)
	assert_eq(ctl.trade_options().map(func(o): return o.id), ["buy:floating"], "floating droids only")
	WorldState.credits = 1000
	assert_eq(ctl.buy("floating"), "bought")
	var uid := int(WorldState.droids.owned[0].uid)
	assert_eq(ctl.upgrade_options().map(func(o): return o.id), ["up:%d:lasers" % uid], "the laser rig, nothing else")
	ctl._select_vendor(0)
	assert_false(ctl.upgrade_options().any(func(o): return str(o.id).ends_with(":lasers")), "not at the market")


func test_e_turns_the_lasers_on_and_off_and_it_is_saved_and_reboots() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	var p: FakePlayer = s[1]
	_sites(ctl)
	ctl._select_vendor(1)
	WorldState.credits = 1000
	assert_eq(ctl.buy("floating"), "bought")
	var uid := int(WorldState.droids.owned[0].uid)
	assert_eq(ctl.upgrade(uid, "lasers"), "upgraded")
	assert_eq(WorldState.credits, 1000 - 50 - int(DroidRoster.upgrade_cfg("lasers").prices[0]), "the rig's price, from data")
	var d: Dictionary = WorldState.droids.find(uid)
	assert_eq(str(d.variant), "rave", "it wears the rave droid's colours")
	await wait_physics_frames(3)
	var u = ctl.companions[uid]
	assert_not_null(u.rig, "the rig is on the droid")
	assert_false(u.lasers.visible, "a new rig is dark")
	# Stand beside it, away from both merchants.
	p.global_position = u.global_position + Vector3(0.8, 0, 0)
	ctl.focus = {}
	assert_eq(ctl.interact(), "lasers_rave")
	assert_true(u.lasers.visible, "E: lasers on")
	assert_true(DroidRoster.lasers_on(d))
	for i in 3:
		ctl.focus = {}
		ctl.interact()
	assert_false(u.lasers.visible, "round to off")
	ctl.focus = {}
	assert_eq(ctl.interact(), "lasers_rave")
	# Saved with the droid.
	var loaded := DroidRoster.new()
	loaded.from_save(JSON.parse_string(JSON.stringify(WorldState.droids.to_save())))
	assert_true(DroidRoster.lasers_on(loaded.find(uid)), "on survives a save")
	WorldState.droids.set_lasers(uid, false)
	loaded.from_save(JSON.parse_string(JSON.stringify(WorldState.droids.to_save())))
	assert_false(DroidRoster.lasers_on(loaded.find(uid)), "and so does off")
	assert_true(DroidRoster.has_lasers(loaded.find(uid)), "the rig too")
	WorldState.droids.set_lasers(uid, true)
	u.lasers.visible = true
	# Knocked out: dark. Rebooted: on again.
	ctl._hurt_companion(u, 99999.0)
	assert_true(u.dead)
	assert_false(u.rig.visible, "dark while it is knocked out")
	u.down_left = 0.01
	await wait_physics_frames(3)
	var back = ctl.companions[uid]
	assert_ne(back, u, "a new body")
	assert_false(back.dead)
	assert_true(back.rig.visible and back.lasers.visible, "lasers back on when it reboots")



## A droid of yours with the rig, bought at the rave and standing beside you.
func _rigged() -> Array:
	var s := _scene()
	var ctl: DroidController = s[0]
	var p: FakePlayer = s[1]
	_sites(ctl)
	ctl._select_vendor(1)
	WorldState.credits = 1000
	ctl.buy("floating")
	var uid := int(WorldState.droids.owned[0].uid)
	ctl.upgrade(uid, "lasers")
	await wait_physics_frames(3)
	var u = ctl.companions[uid]
	p.global_position = u.global_position + Vector3(0.8, 0, 0)
	return [ctl, p, uid, u]


func test_e_steps_rave_cantina_quiet_off_and_the_music_follows() -> void:
	var r = await _rigged()
	var ctl: DroidController = r[0]
	var uid: int = r[2]
	var u = r[3]
	var modes := DroidRoster.laser_modes()
	assert_eq(modes.map(func(m): return str(m.id)), ["rave", "cantina", "quiet"], "the modes, from data")
	assert_eq(str(modes[0].music), "salvage_rave", "rave: the moon rave mix")
	assert_eq(str(modes[1].music), "dust_lounge", "cantina: the desert cantina mix")
	assert_eq(str(modes[2].music), "", "quiet: lasers, no music")
	var want := [["lasers_rave", "salvage_rave", true], ["lasers_cantina", "dust_lounge", true],
		["lasers_quiet", "", true], ["lasers_off", "", false]]
	for w in want:
		ctl.focus = {}
		assert_eq(ctl.interact(), w[0])
		assert_eq(u.lasers.visible, w[2], "lasers lit for %s" % w[0])
		await wait_physics_frames(2)
		assert_eq(Sound.lib().droid, w[1], "the music for %s" % w[0])
		if w[1] != "":
			assert_almost_eq(Sound.lib().droid_near, 1.0, 0.001, "beside you: all of it")
	# The prompt says what the next E does.
	ctl.focus = { "kind": "lasers", "uid": uid }
	assert_string_contains(ctl.prompt_text(), "rave music")


func test_the_mode_is_saved_and_an_old_save_with_lasers_on_plays_music() -> void:
	var r = await _rigged()
	var ctl: DroidController = r[0]
	var uid: int = r[2]
	for i in 2:
		ctl.focus = {}
		ctl.interact()
	var loaded := DroidRoster.new()
	loaded.from_save(JSON.parse_string(JSON.stringify(WorldState.droids.to_save())))
	assert_eq(DroidRoster.laser_mode(loaded.find(uid)), "cantina", "the mode survives a save")
	var old := { "uid": 7, "kind": "floating", "variant": "rave", "cargo": {}, "up": { "lasers": 1 }, "lasers_on": true }
	loaded.from_save({ "owned": [old] })
	assert_eq(DroidRoster.laser_music(loaded.find(7)), "salvage_rave", "lasers on means music on")


func test_knocked_out_or_walked_off_the_music_stops_or_fades() -> void:
	var r = await _rigged()
	var ctl: DroidController = r[0]
	var p: FakePlayer = r[1]
	var u = r[3]
	ctl.focus = {}
	ctl.interact()
	await wait_physics_frames(2)
	assert_eq(Sound.lib().droid, "salvage_rave")
	var mc: Dictionary = DroidRoster.upgrade_cfg("lasers").music
	ctl.set_physics_process(false)        # hold it where it is
	p.global_position = u.global_position + Vector3((float(mc.full_m) + float(mc.hear_m)) / 2.0, 0, 0)
	ctl._droid_music()
	assert_between(Sound.lib().droid_near, 0.05, 0.95, "further off: quieter")
	p.global_position = u.global_position + Vector3(float(mc.hear_m) + 5.0, 0, 0)
	ctl._droid_music()
	assert_eq(Sound.lib().droid, "", "out of earshot")
	p.global_position = u.global_position + Vector3(0.8, 0, 0)
	ctl._droid_music()
	ctl._hurt_companion(u, 99999.0)
	ctl._droid_music()
	assert_eq(Sound.lib().droid, "", "knocked out: quiet")


func test_the_droid_plays_on_the_club_layer_under_a_cantina_and_the_radio() -> void:
	var s := Sound.lib()
	var keep := [s.club, s.club_near, s.club_inside, s.radio, s.in_space]
	s.club = ""
	s.club_inside = false
	s.in_space = false
	s.set_radio("")
	Sound.set_droid("salvage_rave", 1.0)
	assert_true(s.droid_plays())
	assert_eq(s.club_playlist(), "salvage_rave", "the droid's music on the club layer")
	assert_eq(s.club_target(), 1.0, "all of it beside you, the score ducked")
	s.club = "dust_lounge"
	s.club_near = 1.0
	assert_eq(s.club_playlist(), "salvage_rave", "louder than a cantina through its wall")
	s.club_inside = true
	assert_eq(s.club_playlist(), "dust_lounge", "inside a cantina its band plays")
	s.club_inside = false
	s.set_radio("dust_lounge")
	assert_false(s.droid_plays(), "the ship's radio plays over it")
	s.set_radio("")
	Sound.set_droid("", 0.0)
	assert_false(s.droid_plays())
	s.club = keep[0]
	s.club_near = keep[1]
	s.club_inside = keep[2]
	s.set_radio(keep[3])
	s.in_space = keep[4]
