extends GutTest
## Issue #618: race feel. Drafting lifts a speeder's top speed by the configured
## share; a speeder behind another builds a tow; a checkpoint taken dead centre
## tops up the boost and one taken at the edge does not; a faster lap is a record,
## saved and shown on the start line; the finish cam slows time, takes the view
## and puts the filter on, then gives it all back.

const TownDemo := preload("res://scenes/town_demo.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const DT := 1.0 / 60.0


func before_each() -> void:
	WorldState.reset()
	Objective.race = {}
	Engine.time_scale = 1.0


func after_each() -> void:
	Engine.time_scale = 1.0
	WorldState.reset()
	Objective.race = {}
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_a_full_tow_lifts_top_speed_by_the_configured_share() -> void:
	var cfg := HoverModel.load_config("speeder")
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 3000.0 } })
	var alone := HoverModel.new(cfg, g)
	var towed := HoverModel.new(cfg, g)
	alone.place(Vector3(0, 0, 0), 0.0)
	towed.place(Vector3(50, 0, 0), 0.0)
	towed.tow = 1.0
	for i in 600:
		alone.set_command(1.0, 0.0)
		towed.set_command(1.0, 0.0)
		alone.step(DT)
		towed.step(DT)
	assert_almost_eq(towed.speed, alone.speed * (1.0 + float(cfg.tow_speed)), 0.6, "top speed up by tow_speed")


func test_a_speeder_behind_another_builds_a_tow() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 3000.0 } })
	var content = CoreScript.new()
	content.load_from()
	var speeders: Array = []
	for z: float in [-15.0, 0.0]:
		var sp := SpeederNode.new()
		sp.setup(null, g, HoverModel.load_config("speeder"))
		root.add_child(sp)
		sp.place(Vector3(0, 0, z), 0.0)
		var n := NpcBody.new()
		n.setup(content.get_soldier("gate_guard"), Vector3(1, 0, z), 0.0, null)
		root.add_child(n)
		await wait_physics_frames(1)
		sp.seat_npc(n, "driver")
		sp.brain = SpeederBrain.new(sp.model)
		sp.brain.may_boost = false
		sp.brain.follow([Vector3(0, 0, z - 2000.0)], false)
		speeders.append(sp)
	var lead: SpeederNode = speeders[0]
	var back: SpeederNode = speeders[1]
	lead.brain.pace = 0.8                  # a little slower: the one behind closes into its tow
	var back_tow := 0.0
	var lead_tow := 0.0
	for i in 300:
		await wait_physics_frames(1)
		if back.model.position.z > lead.model.position.z + 3.0:     # still behind it (forward is -z)
			back_tow = maxf(back_tow, back.model.tow)
			lead_tow = maxf(lead_tow, lead.model.tow)
	assert_gt(back_tow, 0.9, "right behind it: in the tow")
	assert_lt(lead_tow, 0.1, "the one in front has none")


# ---- in a race -----------------------------------------------------------------------

func _town() -> Node:
	WorldState.counters["speeders_owned"] = 1
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	for i in 900:
		if t.race_crews.size() >= 3:
			break
		await wait_physics_frames(1)
	return t


func _racing(t) -> RaceCrew:
	var crew: RaceCrew = null
	for c in t.race_crews:
		if c.id == "yard":
			crew = c
	WorldState.credits = 500
	var s: SpeederNode = t.speeder_post.speeders[0]
	var s0: Dictionary = crew.course.grid_slot(0)
	s.place(s0.pos, float(s0.yaw))
	t._player.global_position = s.model.position + Vector3(1.5, 0.5, 0)
	s.mount()
	crew.accept(100)
	crew.line_up()
	for i in 5000:
		if crew.phase == RaceCrew.Phase.RACING:
			break
		await wait_physics_frames(1)
	return crew


func test_clean_gates_boost_and_faster_laps_are_records() -> void:
	var t = await _town()
	var crew := await _racing(t)
	assert_eq(crew.phase, RaceCrew.Phase.RACING)
	var m: HoverModel = crew._player_speeder.model
	m.boost_left = 0.0
	crew._you_event({ "type": "gate", "gate": 1, "off": 0.9 })
	assert_eq(m.boost_left, 0.0, "through the edge: nothing")
	crew._you_event({ "type": "gate", "gate": 1, "off": 0.05 })
	assert_almost_eq(m.boost_left, m.p("boost_time", 3.5) * RaceCrew.rule("gate_boost", 0.35), 0.01, "dead centre: boost back")
	assert_eq(crew.clean_gates, 1)
	var key := "race_best_" + crew.course.id
	crew.race_t = 0.0
	crew._you_event({ "type": "start", "gate": 0, "off": 0.0 })
	crew.race_t = 70.5
	crew._you_event({ "type": "lap", "gate": 0, "off": 0.0, "lap": 1 })
	assert_eq(int(WorldState.counters.get(key, 0)), 70500, "the first lap is the record")
	crew.race_t += 80.0
	crew._you_event({ "type": "lap", "gate": 0, "off": 0.0, "lap": 2 })
	assert_eq(int(WorldState.counters.get(key, 0)), 70500, "a slower lap is not")
	crew.race_t += 60.0
	crew._you_event({ "type": "lap", "gate": 0, "off": 0.0, "lap": 3 })
	assert_eq(int(WorldState.counters.get(key, 0)), 60000, "a faster one is")
	assert_almost_eq(crew.best_lap(), 60.0, 0.01, "the race menu reads it")
	assert_not_null(crew.course.record_label, "the start line shows it")
	assert_string_contains(crew.course.record_label.text, "1:00.0")
	var saved := WorldState.to_save()
	assert_eq(int(saved.counters.get(key, 0)), 60000, "saved with the world")


func test_the_finish_cam_slows_time_takes_the_view_and_gives_it_back() -> void:
	var t = await _town()
	var crew := await _racing(t)
	var mine: SpeederNode = crew._player_speeder
	crew.start_finish_cam()
	assert_true(crew.finish_cam_on)
	assert_almost_eq(Engine.time_scale, RaceCrew.rule("finish_slow", 0.33), 0.001, "time slows")
	assert_true(mine.cam_override_on, "the finish cam has the view")
	assert_true(crew._fc_layer != null and crew._fc_layer.visible, "the filter is on")
	for i in 900:
		if not crew.finish_cam_on:
			break
		await wait_physics_frames(1)
	assert_false(crew.finish_cam_on, "over")
	assert_eq(Engine.time_scale, 1.0, "time back to normal")
	assert_false(mine.cam_override_on, "the view is yours again")
	assert_false(crew._fc_layer.visible, "the filter is off")
