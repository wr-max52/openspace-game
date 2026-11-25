extends GutTest
## Issue #627: the racer and the box truck. Skrugs sells them beside the
## Sand-boxer, one of each to a customer; speeder classes: the racer is light
## (quick off the line, glass), the truck heavy (the best top speed, always slow
## to get there, a tank whose Shift drifts); the bench sells all three the shared
## parts; they are stand-ins with a box hull until issue #628; parked speeders
## sleep while you are far off.

const TownDemo := preload("res://scenes/town_demo.gd")


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _flat() -> WorldGround:
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 4000.0 } })
	return g


func _model(id: String, cfg: Dictionary = {}) -> HoverModel:
	var m := HoverModel.new(cfg if not cfg.is_empty() else HoverModel.load_config(id), _flat())
	m.place(Vector3.ZERO, 0.0)
	return m


func _drive(m: HoverModel, seconds: float, throttle: float, steer: float = 0.0, shift: bool = false) -> void:
	for i in int(seconds * 60.0):
		m.set_command(throttle, steer, shift)
		m.step(1.0 / 60.0)


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	t._build_bar([ScriptedProvider.new("scripted_test")], "")
	t.speeder_post.attach_host(t.bar)
	return t


# ---- the two models ---------------------------------------------------------------------

func test_the_racer_is_light_quick_and_made_of_glass() -> void:
	var racer := HoverModel.load_config("racer")
	var sb := HoverModel.load_config("speeder")
	assert_gt(float(racer.accel), float(sb.accel), "quicker off the line than a Sand-boxer")
	assert_gt(float(racer.turn_rate_fast_deg), float(sb.turn_rate_fast_deg), "turns sharper at speed")
	assert_gt(float(racer.boost_speed), float(sb.boost_speed), "boosts harder")
	assert_eq(int(racer.health), int(sb.health) / 2, "half a Sand-boxer's health")
	var m := _model("racer")
	_drive(m, 5.0, 1.0)
	assert_almost_eq(m.speed, float(racer.max_speed), 1.0, "top speed")
	_drive(m, 1.5, 1.0, 0.0, true)
	assert_gt(m.speed, float(racer.max_speed) + 10.0, "Shift boosts it")


func test_the_truck_is_tough_fast_flat_out_and_cannot_boost() -> void:
	var cfg := HoverModel.load_config("hauler")
	var sb := HoverModel.load_config("speeder")
	assert_eq(int(cfg.health), 3 * int(sb.health), "three Sand-boxers")
	assert_gt(float(cfg.max_speed), float(HoverModel.load_config("racer").max_speed), "the best top speed of the three")
	var m := _model("hauler")
	assert_eq(m.ability(), "drift")
	_drive(m, 8.0, 1.0)
	assert_almost_eq(m.speed, float(cfg.max_speed), 1.0, "top speed")
	_drive(m, 1.0, 1.0, 0.0, true)
	assert_false(m.boosting(), "no boost on the truck")
	assert_lte(m.speed, float(cfg.max_speed) + 0.5, "Shift does not make it faster")


## Speeder classes: the truck has the top speed, but even fully tuned it gets
## there slowly; the racer is first off the line.
func test_the_truck_is_always_slow_off_the_line() -> void:
	var tuned_truck := SpeederUpgrades.apply(HoverModel.load_config("hauler"),
		{ "parts": ["engine_2", "thrusters_2"], "model": "hauler" })
	var sb := HoverModel.load_config("speeder")
	assert_lt(float(tuned_truck.accel), float(sb.accel), "Twin thrusters still leave it behind a stock Sand-boxer")
	assert_false(tuned_truck.has("boost_speed"), "an engine gives the truck no boost speed")
	var truck := _model("", tuned_truck)
	var boxer := _model("speeder")
	var racer := _model("racer")
	_drive(truck, 2.0, 1.0)
	_drive(boxer, 2.0, 1.0)
	_drive(racer, 2.0, 1.0)
	assert_gt(racer.speed, boxer.speed, "two seconds in: the racer leads")
	assert_gt(boxer.speed, truck.speed, "and the truck is last")
	_drive(truck, 6.0, 1.0)
	_drive(boxer, 6.0, 1.0)
	assert_gt(truck.speed, boxer.speed + 10.0, "flat out, the tuned truck is far faster")


func test_the_truck_drifts() -> void:
	var plain := _model("hauler")
	var drift := _model("hauler")
	_drive(plain, 4.0, 1.0)
	_drive(drift, 4.0, 1.0)
	var line := drift.forward()
	var meter := drift.boost_left
	_drive(plain, 0.5, 1.0, 1.0)
	_drive(drift, 0.5, 1.0, 1.0, true)
	assert_true(drift.drifting(), "Shift held at speed: drifting")
	assert_gt(drift.forward().angle_to(line), plain.forward().angle_to(line) * 1.5, "the nose turns faster")
	assert_lt(drift.travel_dir().angle_to(line), drift.forward().angle_to(line) * 0.8, "it keeps sliding along its old line")
	assert_lt(drift.boost_left, meter, "the meter drains")
	var speed := drift.speed
	_drive(drift, 0.1, 0.0)
	assert_false(drift.drifting())
	assert_true(drift.travel_dir().is_equal_approx(drift.forward()), "let go: it goes where it points")
	assert_almost_eq(drift.speed, speed, 1.5, "the drift held its speed")
	assert_eq(drift.drift_dir, Vector3.ZERO)


func test_the_sand_boxer_still_boosts() -> void:
	var m := _model("speeder")
	assert_eq(m.ability(), "boost")
	_drive(m, 4.0, 1.0)
	_drive(m, 0.5, 1.0, 1.0, true)
	assert_true(m.boosting())
	assert_false(m.drifting())
	assert_true(m.travel_dir().is_equal_approx(m.forward()))


# ---- buying and owning -------------------------------------------------------------------

func test_one_of_each_saved_with_its_model() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	WorldState.credits = 1000
	assert_true(post.buy("racer"))
	assert_eq(WorldState.credits, 600, "the racer is 400")
	assert_false(post.buy("racer"), "one racer to a customer")
	assert_eq(WorldState.credits, 600, "nothing charged")
	assert_true(post.buy("hauler"))
	assert_true(post.buy("speeder"))
	assert_eq(WorldState.credits, 200, "truck 300, Sand-boxer 100")
	assert_false(post.buy("hauler"))
	assert_true(post.at_limit())
	assert_eq(post.speeders.size(), 3)
	assert_eq(WorldState.count("speeders_owned"), 3)
	var models: Array = WorldState.speeder_fits.map(func(f): return SpeederUpgrades.model_of(f))
	assert_eq(models, ["racer", "hauler", "speeder"])
	var hp: Array = post.speeders.map(func(s): return s.model.max_hp)
	assert_eq(hp, [60, 360, 120])
	# Save and boot again: all three back, each its own model.
	var saved: Dictionary = WorldState.to_save()
	WorldState.reset()
	WorldState.from_save(saved)
	var t2 = _town()
	var again: Array = t2.speeder_post.speeders.map(func(s): return str(s.cfg.get("id", "")))
	assert_eq(again, ["racer", "hauler", "speeder"])


func test_a_fit_with_no_model_is_a_sand_boxer() -> void:
	WorldState.counters["speeders_owned"] = 1
	WorldState.speeder_fits = [{ "paint": "tide", "parts": [], "spent": 0 }]
	var t = _town()
	var s: SpeederNode = t.speeder_post.speeders[0]
	assert_eq(str(s.cfg.get("id", "")), "speeder")
	assert_eq(s.model.max_hp, 120)
	assert_eq(s.paint, "tide")


func test_skrugs_names_the_model_they_ask_for() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	var brain: NpcBrain = post.spot.brain
	var said := brain.canned_reply("How much for the racer?")
	assert_eq(str(said.actions[0].get("id", "")), "racer")
	assert_string_contains(str(said.say), "400")
	said = brain.canned_reply("I want to buy the box truck")
	assert_eq(str(said.actions[0].get("id", "")), "hauler")
	var labels: Array = post.shortcuts().map(func(s): return str(s.id))
	assert_eq(labels, ["go_speeder:speeder", "go_speeder:racer", "go_speeder:hauler"])
	WorldState.credits = 1000
	post.buy("racer")
	labels = post.shortcuts().map(func(s): return str(s.id))
	assert_false(labels.has("go_speeder:racer"), "no button for one they own")
	var b: Dictionary = brain.builder.briefing({ "sale_open": brain._sale_open(), "sale_models": brain._open_models() }, brain.rel, [], [])
	var v := ActionValidator.validate([{ "type": "offer_speeder", "id": "racer" }], b.ids, {})
	assert_true(v.kept.is_empty(), "an offer of the racer they own is dropped")
	v = ActionValidator.validate([{ "type": "offer_speeder", "id": "hauler", "price": 1 }], b.ids, {})
	assert_eq(int(v.kept[0].price), 300, "the game's price for the truck")
	said = brain.canned_reply("How much for the racer?")
	assert_true((said.actions as Array).is_empty(), "he does not offer the one they own")


func test_only_skrugs_sells_them() -> void:
	var t = _town()
	for s in t.gate_speeders:
		assert_eq(str(s.cfg.get("id", "speeder")), "speeder", "the gate speeder is a Sand-boxer")
	assert_eq(str(t.speeder_post.display.cfg.get("id", "")), "speeder", "the display is a Sand-boxer")


# ---- the bench -------------------------------------------------------------------------

func test_the_bench_sells_every_model_the_shared_parts() -> void:
	for model in ["racer", "hauler"]:
		var fit := SpeederUpgrades.new_fit("", model)
		for g in ["performance", "race", "lifter"]:
			assert_eq(SpeederUpgrades.in_group_for(g, model).size(), SpeederUpgrades.in_group(g).size(), "%s: every %s part" % [model, g])
		for g in ["paint", "looks"]:
			assert_true(SpeederUpgrades.in_group_for(g, model).is_empty(), "%s: no %s parts (the Sand-boxer's)" % [model, g])
		assert_eq(SpeederUpgrades.why_not(fit, "engine_1"), "")
		assert_eq(SpeederUpgrades.why_not(fit, "paint_tide"), "wrong_model", "the Sand-boxer's paints are not hers")
		assert_true(SpeederUpgrades.fit_part(fit, "engine_1"))
		assert_eq(SpeederUpgrades.why_not(fit, "engine_2"), "", "tier two after tier one")
		var cfg := SpeederUpgrades.apply(HoverModel.load_config(model), fit)
		assert_almost_eq(float(cfg.max_speed), float(HoverModel.load_config(model).max_speed) * 1.12, 0.01, "%s: the engine works" % model)
		assert_gt(SpeederUpgrades.scrap_value(fit), 35, "her own scrap price")
	var sb := SpeederUpgrades.new_fit("steel")
	assert_eq(SpeederUpgrades.why_not(sb, "engine_1"), "", "the Sand-boxer is unchanged")
	assert_eq(SpeederUpgrades.in_group_for("performance", "speeder").size(), SpeederUpgrades.in_group("performance").size())


# ---- stand-ins and their hull --------------------------------------------------------------

func test_each_stand_in_has_a_box_hull_round_it() -> void:
	var t = _town()
	for id in ["racer", "hauler"]:
		var cfg := HoverModel.load_config(id)
		var s := SpeederNode.new()
		s.setup(t, t.speeder_post.ground, cfg, true)
		t.add_child(s)
		s.place(Vector3(300, 0, 300), 0.0)
		assert_null(s.visual.get_node_or_null("Model"), "%s: a stand-in until #628" % id)
		var cs := s.hull.get_node("Shape") as CollisionShape3D
		assert_true(cs.shape is BoxShape3D, "%s: a box hull" % id)
		var box := AABB(cs.position - (cs.shape as BoxShape3D).size * 0.5, (cs.shape as BoxShape3D).size)
		assert_almost_eq(box.size.z, float(cfg.look.length), 0.5, "%s: as long as its look" % id)
		assert_true(box.has_point(Vector3.ZERO), "%s: a bolt at its middle hits the hull" % id)
		assert_lte(box.size.x * 0.5, float(cfg.body_radius) + 0.3, "%s: bumps about where its sides are" % id)
		s.queue_free()


func test_every_model_fits_his_parking() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	for id in ["speeder", "racer", "hauler"]:
		var r := float(HoverModel.load_config(id).body_radius)
		for i in post.parking.size():
			var at: Vector3 = post.parking_spot(i)[0]
			assert_eq(post.ground.hit(at + Vector3.UP * 1.0, r), "", "%s fits parking spot %d" % [id, i])


# ---- parked speeders sleep ----------------------------------------------------------------

func test_parked_speeders_sleep_while_you_are_far_off() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	WorldState.credits = 1000
	for id in ["speeder", "racer", "hauler"]:
		post.buy(id)
	var p: Node3D = t._player
	p.global_position = post.speeders[0].model.position + Vector3(200, 0, 0)
	for s in post.speeders:
		s._physics_process(1.0 / 60.0)          # settle, then sleep
	var steps: Array = post.speeders.map(func(s): return s.parked_steps)
	for k in 30:
		for s in post.speeders:
			s._physics_process(1.0 / 60.0)
	assert_eq(post.speeders.map(func(s): return s.parked_steps), steps, "200 m away: no hover steps")
	assert_true(post.speeders.all(func(s): return s.asleep))
	p.global_position = post.speeders[0].model.position + Vector3(3, 0, 0)
	for s in post.speeders:
		s._physics_process(1.0 / 60.0)
	assert_false(post.speeders[0].asleep, "walk up: it wakes")
	assert_gt(post.speeders[0].parked_steps, steps[0])
