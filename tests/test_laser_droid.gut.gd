extends GutTest
## Issue #392: the moon rave's droid merchant sells a floating droid and the laser
## rig, sold nowhere else. A rig is dark and quiet until its two buttons in the
## Ledger (I) turn the lasers on and step the music cantina -> rave -> off; the two
## are separate and saved with the droid, and buying the rig says where they are.
## E beside it is its safety, as for any armed droid. Knocked out it goes dark and
## quiet, and it comes back with the droid when it reboots.


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


func test_the_ledger_turns_the_lasers_on_and_off_and_it_is_saved_and_reboots() -> void:
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
	assert_eq(DroidRoster.laser_music(d), "", "a new rig is quiet")
	await wait_physics_frames(3)
	var u = ctl.companions[uid]
	assert_not_null(u.rig, "the rig is on the droid")
	assert_false(u.lasers.visible, "a new rig is dark")
	assert_true(ctl.toggle_lasers(uid))
	assert_true(u.lasers.visible, "lasers on")
	assert_true(DroidRoster.lasers_on(d))
	assert_false(ctl.toggle_lasers(uid))
	assert_false(u.lasers.visible, "and off")
	ctl.toggle_lasers(uid)
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


func test_e_beside_a_laser_droid_is_its_safety() -> void:
	var r = await _rigged()
	var ctl: DroidController = r[0]
	var uid: int = r[2]
	var u = r[3]
	ctl.focus = ctl._find_focus()
	assert_eq(ctl.focus, { "kind": "safety", "uid": uid }, "E beside it: its safety")
	assert_string_contains(ctl.prompt_text(), "Safety ON")
	ctl.focus = {}
	assert_eq(ctl.interact(), "safety_on")
	assert_true(DroidRoster.safety_on(WorldState.droids.find(uid)))
	assert_false(u.lasers.visible, "the lasers are not E's any more")
	ctl.focus = {}
	assert_eq(ctl.interact(), "safety_off")


func test_buying_the_rig_says_where_its_settings_are() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	_sites(ctl)
	ctl._select_vendor(1)
	WorldState.credits = 1000
	ctl.buy("floating")
	var uid := int(WorldState.droids.owned[0].uid)
	var g := GearController.new()
	var hud := GearHud.new()
	hud.toast_label = Label.new()
	g.hud = hud
	ctl.gear = g
	ctl.upgrade(uid, "lasers")
	ctl.gear = null
	var tips: Array = hud._queued.map(func(q): return str(q.text))
	assert_eq(tips, ["Press [I] to change laser droid settings"], "the tip follows the fitted toast")
	hud.toast_label.free()
	hud.free()
	g.free()


func test_the_ledger_shows_a_laser_droids_two_buttons() -> void:
	var r = await _rigged()
	var ctl: DroidController = r[0]
	var uid: int = r[2]
	var u = r[3]
	var page := InventoryPanel.new()
	page.toggle_lasers = ctl.toggle_lasers
	page.cycle_station = ctl.cycle_station
	add_child_autofree(page)
	page.refresh()
	assert_true(page.laser_buttons.has(uid), "the laser droid's row has its buttons")
	var b: Array = page.laser_buttons[uid]
	assert_eq(b[0].text, "Lasers: OFF")
	assert_eq(b[1].text, "Music: Off")
	b[0].pressed.emit()
	assert_true(u.lasers.visible, "Lasers: on")
	b = page.laser_buttons[uid]
	assert_eq(b[0].text, "Lasers: ON")
	b[1].pressed.emit()
	b = page.laser_buttons[uid]
	assert_eq(b[1].text, "Music: Cantina")
	b[1].pressed.emit()
	assert_eq(page.laser_buttons[uid][1].text, "Music: Rave")
	page.laser_buttons[uid][1].pressed.emit()
	assert_eq(page.laser_buttons[uid][1].text, "Music: Off", "round to off")


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


func test_the_music_steps_cantina_rave_off_on_its_own() -> void:
	var r = await _rigged()
	var ctl: DroidController = r[0]
	var uid: int = r[2]
	var u = r[3]
	var modes := DroidRoster.laser_modes()
	assert_eq(modes.map(func(m): return str(m.id)), ["cantina", "rave", "quiet"], "the stations, from data")
	assert_eq(str(modes[0].music), "dust_lounge", "cantina: the desert cantina mix")
	assert_eq(str(modes[1].music), "salvage_rave", "rave: the moon rave mix")
	assert_eq(str(modes[2].music), "", "off: no music")
	for w in [["cantina", "dust_lounge"], ["rave", "salvage_rave"], ["quiet", ""]]:
		assert_eq(ctl.cycle_station(uid), w[0])
		assert_false(u.lasers.visible, "the music does not light the lasers")
		await wait_physics_frames(2)
		assert_eq(Sound.lib().droid, w[1], "the music for %s, lasers off" % w[0])
		if w[1] != "":
			assert_almost_eq(Sound.lib().droid_near, 1.0, 0.001, "beside you: all of it")
	ctl.toggle_lasers(uid)
	await wait_physics_frames(2)
	assert_eq(Sound.lib().droid, "", "and the lasers do not start the music")


func test_the_station_is_saved_and_old_saves_keep_their_music() -> void:
	var r = await _rigged()
	var ctl: DroidController = r[0]
	var uid: int = r[2]
	ctl.cycle_station(uid)
	ctl.cycle_station(uid)
	var loaded := DroidRoster.new()
	loaded.from_save(JSON.parse_string(JSON.stringify(WorldState.droids.to_save())))
	assert_eq(DroidRoster.laser_station(loaded.find(uid)), "rave", "the station survives a save")
	var on := { "uid": 7, "kind": "floating", "variant": "rave", "cargo": {}, "up": { "lasers": 1 }, "lasers_on": true, "laser_mode": "rave" }
	var off := { "uid": 8, "kind": "floating", "variant": "rave", "cargo": {}, "up": { "lasers": 1 }, "lasers_on": false, "laser_mode": "rave" }
	loaded.from_save({ "owned": [on, off] })
	assert_eq(DroidRoster.laser_music(loaded.find(7)), "salvage_rave", "an old save with the lasers on keeps its music")
	assert_eq(DroidRoster.laser_music(loaded.find(8)), "", "an old one with them off stays quiet")


func test_knocked_out_or_walked_off_the_music_stops_or_fades() -> void:
	var r = await _rigged()
	var ctl: DroidController = r[0]
	var p: FakePlayer = r[1]
	var u = r[3]
	ctl.cycle_station(r[2])
	ctl.cycle_station(r[2])
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
