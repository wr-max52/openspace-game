extends GutTest
## Jobs done for Oda and runs for the fence raise the locals' standing: each
## job's board entry names how much ("standing"; WorldState.job_standing).

const CoreContent := preload("res://src/systems/dataload/core_content.gd")

var content


func before_each() -> void:
	GameFlow.reset()
	WorldState.reset()
	content = CoreContent.new()
	content.load_from()


func after_all() -> void:
	WorldState.reset()


func _locals() -> int:
	return int(WorldState.standing.get("locals", 0))


func _entry(id: String) -> Dictionary:
	for j in WorldState.board():
		if str(j.id) == id:
			return j
	return {}


func _gain(id: String) -> int:
	return int(_entry(id).get("standing", {}).get("locals", 0))


## Pick up the drop of `job` and sell it all to the port's fence, as GearController does.
func _run_for_fence(job: String) -> void:
	WorldState.open_jobs("confidant")             # rolls the offer
	assert_true(WorldState.accept_job(job), "the run can be taken")
	var drop := WorldState.smuggle_drop()
	assert_true(WorldState.inventory.pick_up(drop))
	var fence: Dictionary = content.get_vendor("fence")
	var item: Dictionary = content.get_item(str(drop.item))
	for i in int(drop.count):
		WorldState.credits += WorldState.inventory.sell(str(drop.item), item, fence)
	WorldState.on_contraband_sold()


func test_every_oda_job_and_fence_run_raises_the_locals() -> void:
	for j in WorldState.board():
		var giver = j.get("giver", "cantina_owner")
		var odas: bool = giver is Array and (giver as Array).has("cantina_owner") or str(giver) == "cantina_owner"
		var fence_run: bool = str(j.get("kind", "")) == "smuggle" and str(j.get("deliver_to", "fence")) == "fence"
		if not (odas or fence_run) or str(j.get("kind", "")) in ["heist", "supply"]:
			continue                               # those two raise it their own way
		assert_gt(_gain(str(j.id)), 0, "%s raises the locals' standing" % j.id)
		assert_ne(str(j.get("standing", {}).get("line", "")), "", "%s says why" % j.id)


func test_the_general_jobs_do_not() -> void:
	for id in ["j_general_droids", "j_general_repossess", "j_general_heist"]:
		assert_eq(_gain(id), 0, id)


func test_a_finished_oda_job_raises_the_locals() -> void:
	var before := _locals()
	assert_true(WorldState.accept_job("j_range_bet"))
	WorldState.on_range_record(12.0)
	assert_eq(_locals(), before + _gain("j_range_bet"))
	assert_true(WorldState.events.any(func(e): return str(e.text) == str(_entry("j_range_bet").standing.line)),
			"the gossip hears why")
	WorldState.on_range_record(10.0)
	assert_eq(_locals(), before + _gain("j_range_bet"), "once per job")


func test_a_job_not_taken_raises_nothing() -> void:
	var before := _locals()
	WorldState.on_range_record(12.0)
	assert_eq(_locals(), before)


func test_a_drop_sold_to_the_fence_raises_the_locals_once() -> void:
	Story.skip_to("smuggle_1")
	var before := _locals()
	_run_for_fence("j_smuggle_run")
	assert_eq(_locals(), before + _gain("j_smuggle_run"))
	WorldState.on_contraband_sold()
	assert_eq(_locals(), before + _gain("j_smuggle_run"), "the same drop twice is not two runs")


func test_the_generals_run_raises_only_the_remnant() -> void:
	Story.skip_to("smuggle_1")
	WorldState.open_jobs("confidant")
	assert_true(WorldState.accept_job("j_general_repossess"))
	assert_true(WorldState.inventory.pick_up(WorldState.smuggle_drop()))
	var before := _locals()
	assert_gt(WorldState.hand_over_contraband(5), 0)
	assert_eq(_locals(), before, "the locals do not thank you for that")


func test_a_bounty_paid_raises_the_locals() -> void:
	WorldState.bounty = { "run": 1, "key": "npc:bounty/1", "name": "Vel Doran", "crime": "x", "outpost": Story.OUTPOSTS[0], "pay": 1500, "state": "out" }
	WorldState.on_bounty_killed()
	var before := _locals()
	assert_eq(WorldState.collect_bounty(), 1500)
	assert_eq(_locals(), before + _gain("j_bounty"))
	WorldState.collect_bounty()
	assert_eq(_locals(), before + _gain("j_bounty"), "paid once")
