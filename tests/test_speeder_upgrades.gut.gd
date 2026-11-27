extends GutTest
## Issue #95: the mechanic's speeder upgrades. The parts' rules (tiers, slots,
## paint), what they do to the numbers, the Grav Lifter's hop, hold, tilt and drop, the yard out
## in the desert, buying and fitting at the bay, the save, and selling for scrap.

const TownDemo := preload("res://scenes/town_demo.gd")

var cfg: Dictionary


func before_each() -> void:
	WorldState.reset()
	cfg = HoverModel.load_config("speeder")


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---- the parts -----------------------------------------------------------------------

func test_every_part_is_complete() -> void:
	var groups := ["paint", "looks", "performance", "lifter", "race"]   # issue #616: race gear
	for p in SpeederUpgrades.parts():
		assert_gt(int(p.get("price", 0)), 0, str(p.id))
		assert_has(groups, str(p.get("group", "")), str(p.id))
		if p.has("requires"):
			assert_false(SpeederUpgrades.part(str(p.requires)).is_empty(), str(p.id) + " needs a real part")
		if str(p.slot) == "paint":       # issue #628: on its own model's look
			var look: Dictionary = HoverModel.load_config(str(p.get("model", "speeder"))).look
			assert_true(look.paints.has(str(p.paint)), str(p.id) + " is a real paint job")
	var lifter := SpeederUpgrades.part("grav_lifter")
	for p in SpeederUpgrades.parts():
		if str(p.id) != "grav_lifter":
			assert_gt(int(lifter.price), int(p.price), "the Grav Lifter costs the most")


func test_tier_two_needs_tier_one_and_replaces_it() -> void:
	var fit := SpeederUpgrades.new_fit()
	assert_eq(SpeederUpgrades.why_not(fit, "engine_2"), "needs:engine_1")
	assert_false(SpeederUpgrades.fit_part(fit, "engine_2"))
	assert_true(SpeederUpgrades.fit_part(fit, "engine_1"))
	assert_eq(SpeederUpgrades.why_not(fit, "engine_1"), "owned")
	assert_true(SpeederUpgrades.fit_part(fit, "engine_2"))
	assert_eq(fit.parts, ["engine_2"], "one engine at a time")
	assert_eq(SpeederUpgrades.why_not(fit, "engine_1"), "owned", "tier 1 counts as had")


func test_paint_can_change_again() -> void:
	var fit := SpeederUpgrades.new_fit("steel")
	assert_eq(SpeederUpgrades.why_not(fit, "paint_steel"), "owned", "already that colour")
	assert_true(SpeederUpgrades.fit_part(fit, "paint_tide"))
	assert_eq(fit.paint, "tide")
	assert_true(SpeederUpgrades.fit_part(fit, "paint_steel"))
	assert_eq(fit.paint, "steel")
	assert_eq(fit.parts, [], "paint is not a part")


func test_parts_change_the_numbers() -> void:
	var fit := SpeederUpgrades.new_fit()
	for id in ["engine_1", "engine_2", "thrusters_1", "cannons_1", "turbo_boosters"]:
		SpeederUpgrades.fit_part(fit, id)
	var up := SpeederUpgrades.apply(cfg, fit)
	assert_almost_eq(float(up.max_speed), float(cfg.max_speed) * 1.25, 0.01)
	assert_almost_eq(float(up.accel), float(cfg.accel) * 1.3, 0.01)
	assert_almost_eq(float(up.laser.damage), float(cfg.laser.damage) * float(SpeederUpgrades.part("cannons_1").mods["laser.damage"]), 0.01)
	assert_eq(float(up.turn_rate_deg), float(cfg.turn_rate_deg), "looks parts change nothing else")
	assert_eq(float(cfg.max_speed), 36.0, "the base config is untouched")
	assert_has(up.parts, "turbo_boosters")


func test_a_tuned_engine_is_faster_on_the_sand() -> void:
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 2000.0 } })
	var fit := SpeederUpgrades.new_fit()
	SpeederUpgrades.fit_part(fit, "engine_1")
	SpeederUpgrades.fit_part(fit, "thrusters_1")
	var stock := HoverModel.new(cfg, g)
	var tuned := HoverModel.new(SpeederUpgrades.apply(cfg, fit), g)
	for m in [stock, tuned]:
		m.place(Vector3(500, 0, 0), 0.0)
		for i in 180:
			m.set_command(1.0, 0.0)
			m.step(1.0 / 60.0)
	assert_gt(tuned.speed, stock.speed + 3.0, "quicker off the line and faster at the top")


func test_scrap_pays_base_plus_a_share_of_the_parts() -> void:
	var fit := SpeederUpgrades.new_fit()
	var base := SpeederUpgrades.scrap_value(fit)
	assert_gt(base, 0)
	SpeederUpgrades.fit_part(fit, "engine_1")    # 150
	assert_eq(SpeederUpgrades.scrap_value(fit), base + int(round(150 * 0.25)))


# ---- the Grav Lifter -----------------------------------------------------------------

func _lifter_model() -> HoverModel:
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 2000.0 } })
	var fit := SpeederUpgrades.new_fit()
	SpeederUpgrades.fit_part(fit, "grav_lifter")
	var m := HoverModel.new(SpeederUpgrades.apply(cfg, fit), g)
	m.place(Vector3(500, 0, 0), 0.0)
	return m


func test_no_lifter_no_lift() -> void:
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 2000.0 } })
	var m := HoverModel.new(cfg, g)
	m.place(Vector3.ZERO, 0.0)
	assert_false(m.lift())
	assert_false(m.airborne)


func test_the_lifter_hops_holds_then_falls() -> void:
	var m := _lifter_model()
	var hover := float(cfg.hover_height)
	assert_true(m.lift())
	var ev: Array = m.step(1.0 / 60.0)
	assert_eq(str(ev[0].type), "lift")
	assert_true(m.airborne, "off the ground")
	assert_true(m.lifting())
	# Up, then the hold: level, it keeps its height.
	var peak := 0.0
	for i in 90:
		m.step(1.0 / 60.0)
		peak = maxf(peak, m.position.y)
	assert_gt(peak - hover, 1.5, "a real hop")
	var hold_start := m.position.y
	for i in 60:
		m.step(1.0 / 60.0)
	assert_almost_eq(m.position.y, hold_start, 0.5, "holds: gravity is off")
	var landed := false
	for i in 600:
		for e in m.step(1.0 / 60.0):
			landed = landed or str(e.type) == "landed"
	assert_true(landed, "and comes down when its time is up")
	assert_true(m.lift_ready(), "recharged by now")


func test_the_lifter_is_not_a_rocket() -> void:
	# Hands off, the hop rises a few metres and stops: no runaway climb.
	var m := _lifter_model()
	var hover := float(cfg.hover_height)
	m.lift()
	var peak := 0.0
	while m.lifting():
		m.step(1.0 / 60.0)
		peak = maxf(peak, m.position.y - hover)
	assert_lt(peak, 4.0, "a hop and a hold, not a launch")
	assert_almost_eq(m.lift_cooldown, float(m.lifter().recharge_s), 0.05, "held to the end: the full recharge")


func test_space_again_drops_the_lifter() -> void:
	var m := _lifter_model()
	m.lift()
	for i in 30:
		m.step(1.0 / 60.0)
	assert_true(m.lifting())
	assert_true(m.lift(), "Space again turns it off")
	assert_false(m.lifting())
	var vy_was := m.vy
	var ev: Array = m.step(1.0 / 60.0)
	assert_true(ev.any(func(e): return str(e.type) == "drop"), "it says so")
	assert_almost_eq(m.vy, vy_was - float(cfg.gravity) / 60.0, 0.01, "and gravity has it again")
	var full := float(m.lifter().recharge_s)
	assert_lt(m.lift_cooldown, full, "a short lift recharges quicker")
	assert_false(m.lift(), "but it still recharges")


func test_the_lifter_keeps_the_climb_issue_100() -> void:
	var m := _lifter_model()
	m.airborne = true
	m.vy = 5.0
	m.position.y = 20.0
	assert_true(m.lift())
	m.step(1.0 / 60.0)
	assert_gt(m.vy, 4.5, "the climb it had carries on")
	for i in 180:
		m.step(1.0 / 60.0)
	assert_lt(m.vy, 1.0, "then eases off, hands off: no runaway")
	var m2 := _lifter_model()
	m2.airborne = true
	m2.vy = -6.0
	m2.position.y = 20.0
	m2.lift()
	m2.step(1.0 / 60.0)
	assert_gte(m2.vy, 0.0, "and no downward momentum")


func test_tilt_steers_the_lift() -> void:
	# S tilts the nose up: it climbs and slows. W tilts it down: it sinks, speeds
	# up and lands, and landing ends the lift.
	var up := _lifter_model()
	up.speed = 20.0
	up.lift()
	up.set_command(-1.0, 0.0)
	var y0 := up.position.y
	for i in 120:
		up.step(1.0 / 60.0)
	assert_gt(up.air_pitch, 0.2, "nose up")
	assert_gt(up.position.y - y0, 4.0, "climbs")
	assert_lt(up.speed, 20.0, "and slows")
	var down := _lifter_model()
	down.speed = 20.0
	down.airborne = true
	down.position.y += 3.0
	down.lift()
	down.set_command(1.0, 0.0)
	var landed := false
	for i in 300:
		for e in down.step(1.0 / 60.0):
			landed = landed or str(e.type) == "landed"
		if landed:
			break
	assert_true(landed, "nose down sinks it to the ground")
	assert_gt(down.speed, 20.0, "picking up speed on the way")
	assert_false(down.lifting(), "and the lifter lets go on touching down")
	assert_eq(down.air_pitch, 0.0, "level on the ground")


func test_boost_works_in_the_air() -> void:
	var m := _lifter_model()
	m.speed = 20.0
	m.lift()
	m.set_command(0.0, 0.0, true)      # boost, no throttle (W is the tilt up there)
	for i in 30:
		m.step(1.0 / 60.0)
	assert_gt(m.speed, 22.0, "boost pushes it on while lifted")
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 2000.0 } })
	var plain := HoverModel.new(cfg, g)
	plain.place(Vector3(500, 0, 0), 0.0)
	plain.airborne = true
	plain.position.y = 30.0
	plain.speed = 20.0
	plain.set_command(0.0, 0.0, true)
	for i in 30:
		plain.step(1.0 / 60.0)
	assert_gt(plain.speed, 22.0, "and off a ramp without the lifter")


func test_off_a_cliff_the_lifter_keeps_it_up_longer() -> void:
	var a := _lifter_model()
	var b := _lifter_model()
	for m in [a, b]:
		m.airborne = true
		m.vy = 0.0
		m.position.y = 40.0
	a.lift()       # in the air already: the hold starts at once
	var ta := 0.0
	var tb := 0.0
	while a.airborne and ta < 20.0:
		a.step(1.0 / 60.0)
		ta += 1.0 / 60.0
	while b.airborne and tb < 20.0:
		b.step(1.0 / 60.0)
		tb += 1.0 / 60.0
	assert_gt(ta, tb + 0.8, "longer in the air")


# ---- the yard ------------------------------------------------------------------------

func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	return t


func _speeder_in_bay(t) -> SpeederNode:
	WorldState.credits += 100
	t.speeder_post.buy()
	var s: SpeederNode = t.speeder_post.speeders[-1]
	s.place(t.mechanic.world_point("bay"), 0.0)
	return s


func test_the_yard_is_a_drive_out_of_town() -> void:
	var t = _town()
	var y: MechanicYard = t.mechanic
	assert_not_null(y)
	assert_true(y.found, "the world has the yard")
	var stall: Vector3 = t.speeder_post.world_point("customer")
	var d := y.world_point("bay").distance_to(stall)
	var secs := d / float(cfg.max_speed)
	assert_between(secs, 22.0, 40.0, "about a 30 second drive at full speed (%.0f s)" % secs)
	assert_not_null(y.mechanic, "Dorrin is there")


func test_no_speeder_in_the_bay_no_shop() -> void:
	var t = _town()
	var y: MechanicYard = t.mechanic
	WorldState.credits = 1000
	t.speeder_post.buy()            # parked at Skrugs's, not at the yard
	assert_null(y.speeder_in_bay())
	assert_eq(y.buy("engine_1"), "no_speeder")
	assert_eq(WorldState.credits, 900, "nothing charged")


func test_buying_a_part_fits_it_and_saves_it() -> void:
	var t = _town()
	var y: MechanicYard = t.mechanic
	var s := _speeder_in_bay(t)
	WorldState.credits = 200
	assert_eq(y.buy("engine_1"), "bought")
	assert_eq(WorldState.credits, 50)
	var now: SpeederNode = y.speeder_in_bay()
	assert_not_null(now, "rebuilt where it stood")
	assert_ne(now, s, "a new node with the part")
	assert_almost_eq(float(now.cfg.max_speed), float(cfg.max_speed) * 1.12, 0.01)
	assert_eq(WorldState.speeder_fits[0].parts, ["engine_1"])
	# Saved and loaded: the part is still on it.
	var save := WorldState.to_save()
	WorldState.from_save(save)
	assert_eq(WorldState.speeder_fits[0].parts, ["engine_1"])


func test_too_poor_buys_nothing() -> void:
	var t = _town()
	var y: MechanicYard = t.mechanic
	_speeder_in_bay(t)
	WorldState.credits = 100
	assert_eq(y.buy("grav_lifter"), "cant_afford")
	assert_eq(WorldState.credits, 100)
	assert_eq(WorldState.speeder_fits[0].parts, [])


func test_looks_parts_show_on_the_speeder() -> void:
	var t = _town()
	var y: MechanicYard = t.mechanic
	_speeder_in_bay(t)
	WorldState.credits = 1000
	assert_eq(y.buy("turbo_boosters"), "bought")
	assert_eq(y.buy("soft_top"), "bought")
	assert_eq(y.buy("paint_remnant"), "bought")
	var s: SpeederNode = y.speeder_in_bay()
	await wait_frames(1)
	assert_not_null(s.visual.find_child("Booster", true, false), "boosters on the back")
	assert_not_null(s.visual.find_child("SoftTop", true, false), "a roof")
	assert_eq(s.paint, "remnant")


func test_the_menu_lists_the_groups_and_scrap() -> void:
	var t = _town()
	var y: MechanicYard = t.mechanic
	_speeder_in_bay(t)
	y.talk()
	var ids: Array = y.menu.options.map(func(o): return str(o.id))
	for want in ["group:paint", "group:looks", "group:performance", "buy:grav_lifter", "scrap"]:
		assert_has(ids, want)
	y.menu.choose("group:performance")
	var perf: Array = y.menu.options.map(func(o): return str(o.id))
	assert_has(perf, "buy:engine_2")
	var row: String = y.menu.options[perf.find("buy:engine_2")].text
	assert_string_contains(row, "needs")


func test_sell_it_for_scrap() -> void:
	var t = _town()
	var y: MechanicYard = t.mechanic
	_speeder_in_bay(t)
	WorldState.credits = 200
	y.buy("engine_1")
	var before := WorldState.credits
	var pay := y.scrap()
	assert_eq(pay, 35 + int(round(150 * 0.25)))
	assert_eq(WorldState.credits, before + pay)
	assert_eq(t.speeder_post.speeders.size(), 0, "gone")
	assert_eq(WorldState.count("speeders_owned"), 0)
	assert_eq(WorldState.speeder_fits.size(), 0, "its parts went with it")


func test_space_lifts_and_mouse_fires_with_a_lifter() -> void:
	var t = _town()
	var y: MechanicYard = t.mechanic
	_speeder_in_bay(t)
	WorldState.credits = 1000
	y.buy("grav_lifter")
	var s: SpeederNode = y.speeder_in_bay()
	await wait_frames(1)
	t._player.global_position = s.model.position + Vector3(1.5, -1.0, 0)
	assert_true(s.mount())
	s.set_external_command({ "lift": true })
	s._physics_process(1.0 / 60.0)
	assert_true(s.model.airborne, "it hops")
	s._physics_process(1.0 / 60.0)
	assert_true(s.model.lifting(), "a held lift is one press, not one a frame")
	var glow := s.visual.get_node_or_null("LiftGlow") as Node3D
	assert_not_null(glow, "the lifter lights the underside")
	for i in 10:
		s._physics_process(1.0 / 60.0)
	assert_true(glow.visible, "lit while it holds you up")
	s.set_external_command({})
	s._physics_process(1.0 / 60.0)
	s.set_external_command({ "lift": true })
	s._physics_process(1.0 / 60.0)
	assert_false(s.model.lifting(), "pressed again, it drops")
	for i in 20:
		s._physics_process(1.0 / 60.0)
	assert_false(glow.visible, "and the glow goes out")
	s.set_external_command({})
	s.dismount()
