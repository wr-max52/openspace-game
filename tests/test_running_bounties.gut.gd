extends GutTest
## Issue #614: running bounties. The story's bounty never runs; repeat contracts
## sometimes do, and say so. A runner keeps a speeder at their outpost and flees
## when you close in; they ease off when you fall behind and push when you close;
## past the got-away distance they are gone and the contract ends unpaid. A runner
## contract saved and loaded is still a runner at the same outpost.

const TownDemo := preload("res://scenes/town_demo.gd")


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _runners(rolls: int) -> int:
	var n := 0
	for i in rolls:
		WorldState.bounty = { "run": i, "state": "" }
		WorldState._roll_bounty()
		n += int(bool(WorldState.bounty.get("runner", false)))
	return n


func test_the_story_bounty_never_runs() -> void:
	WorldState.mode = WorldState.STORY
	WorldState.story = { "chapter": "bounty" }
	assert_eq(_runners(200), 0, "the story's first contract never runs")
	WorldState.counters["bounties_paid"] = 1
	assert_eq(_runners(200), 0, "nor any while the story is on its bounty chapter")
	WorldState.bounty = { "run": 1, "general": true, "state": "rolled" }
	assert_false(WorldState.runner_allowed(), "nor the general")


func test_repeat_contracts_sometimes_run_and_say_so() -> void:
	WorldState.mode = WorldState.FREEPLAY
	WorldState.story = { "chapter": "free", "told": true }
	WorldState.counters["bounties_paid"] = 1
	var n := _runners(300)
	assert_between(n, 50, 160, "about a third run (%d of 300)" % n)
	WorldState.bounty = { "run": 9, "key": "npc:bounty/9", "name": "Vel Ankor", "crime": "x", "outpost": Story.OUTPOSTS[1], "pay": 2000, "state": "rolled", "runner": true }
	var job := WorldState._bounty_job({ "id": "j_bounty", "kind": "bounty" })
	assert_string_contains(str(job.text), str(Story.bounty_cfg().runner.hint), "the contract hints at it")


func test_ease_off_when_you_fall_behind_push_when_you_close() -> void:
	var r := BountyRunner.new()
	r.cfg = Story.bounty_cfg().runner
	assert_eq(r.pace_for(400.0, 1.0), 1.0, "full tilt at first")
	assert_eq(r.pace_for(400.0, 30.0), float(r.cfg.min_pace), "far behind: eased off")
	assert_eq(r.pace_for(40.0, 30.0), 1.0, "closing: pushing again")
	r.free()


func _town_with_runner() -> Node:
	WorldState.mode = WorldState.FREEPLAY
	WorldState.story = { "chapter": "free", "told": true }
	WorldState.counters["bounties_paid"] = 1
	WorldState.bounty = { "run": 7, "key": "npc:bounty/7", "name": "Vel Ankor", "crime": "x",
		"outpost": Story.OUTPOSTS[1], "pay": 2000, "state": "out", "runner": true }
	var t = TownDemo.new()
	t.use_look = false
	add_child_autofree(t)
	for i in 1500:
		if t.outposts != null and t.outposts.runner != null:
			break
		await wait_physics_frames(1)
	return t


func test_a_runner_flees_and_gets_away() -> void:
	var t = await _town_with_runner()
	var rem = t.outposts
	assert_not_null(rem.runner, "a runner, with a speeder at the outpost")
	var r: BountyRunner = rem.runner
	var target: NpcBody = rem.target
	var target_ref: WeakRef = weakref(target)
	assert_lt(r.speeder.model.position.distance_to(target.global_position), 8.0, "parked by them")
	t._player.global_position = target.global_position + Vector3(40, 1, 0)
	for i in 30:
		if r.state == BountyRunner.State.FLEE:
			break
		await wait_physics_frames(1)
	assert_eq(r.state, BountyRunner.State.FLEE, "you came close: they run")
	assert_true(r.speeder.npc_driven(), "on the speeder")
	var gone := r.speeder.model.position + Vector3(0, 0, 900)
	t._player.global_position = gone
	var ref: WeakRef = weakref(r)
	var away := false
	for i in 30:
		var rr = ref.get_ref()
		away = rr == null or rr.state == BountyRunner.State.GONE
		if away:
			break
		await wait_physics_frames(1)
	assert_true(away, "too far behind: they got away (and the runner is put away)")
	assert_eq(str(WorldState.bounty.get("state", "x")), "", "the contract ends; a fresh one next time")
	assert_false(WorldState.bounty_collectable(), "and nothing to collect")
	await wait_physics_frames(2)
	assert_null(target_ref.get_ref(), "they are gone")


func test_a_runner_contract_survives_a_save() -> void:
	WorldState.mode = WorldState.FREEPLAY
	WorldState.story = { "chapter": "free", "told": true }
	WorldState.counters["bounties_paid"] = 1
	WorldState.bounty = { "run": 3, "key": "npc:bounty/3", "name": "Vel Ankor", "crime": "x",
		"outpost": Story.OUTPOSTS[2], "pay": 2000, "state": "rolled", "runner": true }
	var saved := WorldState.to_save()
	WorldState.reset()
	WorldState.from_save(saved)
	assert_true(bool(WorldState.bounty.get("runner", false)), "still a runner")
	assert_eq(str(WorldState.bounty.outpost), Story.OUTPOSTS[2], "at the same outpost")
