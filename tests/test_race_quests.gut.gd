extends GutTest
## Speeder race quests: a win pays the pot into your credits at once and offers
## two optional quests (the next crew up the ladder, a pink-slip rematch with the
## crew you beat); a loss offers one (a rematch with the crew who beat you). The
## quests are data (racing/rules.json "quests") and point at the crew's hangout.
## One line per crew: its name, difficulty and where you stand (Race, Rematch,
## Pink slip); offering one clears that crew's others.


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()


func test_a_win_pays_your_credits_not_dorrin() -> void:
	WorldState.credits = 100
	WorldState.on_race_won("yard", 1000)
	assert_eq(WorldState.credits, 1100, "paid at the finish")
	assert_eq(WorldState.count("race_winnings"), 0, "Dorrin holds nothing")
	assert_true(WorldState.has_flag("crew_beaten_yard"))


func test_every_crew_has_slips_and_rematch_and_all_but_the_first_a_next() -> void:
	var ids: Array = []
	for q in RaceCrew.quests():
		ids.append(str(q.id))
		assert_eq(str(q.target), "crew:" + str(q.id).get_slice("_", 2), "points at its crew")
		assert_false(str(q.title).contains("{"), "title filled in: " + str(q.title))
		assert_false(str(q.text).contains("{"), "text filled in: " + str(q.text))
	for cid in RaceCrew.ids():
		assert_has(ids, RaceCrew.quest_id("slips", cid))
		assert_has(ids, RaceCrew.quest_id("rematch", cid))
	assert_does_not_have(ids, RaceCrew.quest_id("next", "yard"), "the first rung has no crew below it")
	assert_has(ids, RaceCrew.quest_id("next", "basin"))
	assert_has(ids, RaceCrew.quest_id("next", "salt"))
	assert_eq(Quests.cfg(RaceCrew.quest_id("slips", "basin")).get("title", ""), "Basin crew (Easy) - Pink slip")
	assert_eq(Quests.cfg(RaceCrew.quest_id("next", "salt")).get("title", ""), "Salt crew (Medium) - Race")
	assert_eq(Quests.cfg(RaceCrew.quest_id("rematch", "leap")).get("title", ""), "Leap crew (Hard) - Rematch")


func test_win_offers_next_crew_and_pink_slips() -> void:
	WorldState.on_race_won("yard", 100)
	RaceCrew.settle_quests("yard", true, false)
	assert_eq(Quests.state(RaceCrew.quest_id("next", "basin")), "open")
	assert_eq(Quests.state(RaceCrew.quest_id("slips", "yard")), "open")
	assert_eq(Quests.state(RaceCrew.quest_id("rematch", "yard")), "", "no rematch after a win")
	assert_true(Quests.can_point(RaceCrew.quest_id("next", "basin")), "it has somewhere to point")


func test_loss_offers_only_a_rematch_and_a_win_finishes_it() -> void:
	RaceCrew.settle_quests("basin", false, false)
	assert_eq(Quests.state(RaceCrew.quest_id("rematch", "basin")), "open")
	assert_eq(Quests.state(RaceCrew.quest_id("next", "salt")), "")
	assert_eq(Quests.state(RaceCrew.quest_id("slips", "basin")), "")
	WorldState.on_race_won("basin", 100)
	RaceCrew.settle_quests("basin", true, false)
	assert_eq(Quests.state(RaceCrew.quest_id("rematch", "basin")), "", "won it back: the line moves on to pink slips")
	assert_eq(Quests.state(RaceCrew.quest_id("slips", "basin")), "open")
	assert_eq(Quests.state(RaceCrew.quest_id("next", "salt")), "open")


func test_beating_the_next_crew_finishes_their_quest() -> void:
	WorldState.on_race_won("yard", 100)
	RaceCrew.settle_quests("yard", true, false)
	WorldState.on_race_won("basin", 100)
	RaceCrew.settle_quests("basin", true, false)
	assert_eq(Quests.state(RaceCrew.quest_id("next", "basin")), "", "beaten: their line is pink slips now")
	assert_eq(Quests.state(RaceCrew.quest_id("slips", "basin")), "open")


func test_top_crew_offers_no_next_and_a_beaten_crew_is_not_offered_again() -> void:
	WorldState.on_race_won("leap", 100)
	RaceCrew.settle_quests("leap", true, false)
	for q in Quests.entries():
		assert_false(str(q.id).begins_with("race_next_"), "nobody above the leap crew")
	WorldState.set_flag("crew_beaten_basin")
	RaceCrew.settle_quests("yard", true, false)
	assert_eq(Quests.state(RaceCrew.quest_id("next", "basin")), "", "already beaten: no quest")


func test_a_pink_slip_race_does_the_slips_quest_and_a_loss_offers_a_rematch() -> void:
	WorldState.on_race_won("yard", 100)
	RaceCrew.settle_quests("yard", true, false)
	RaceCrew.settle_quests("yard", false, true)
	assert_eq(Quests.state(RaceCrew.quest_id("slips", "yard")), "", "raced for slips: the line is the rematch now")
	assert_eq(Quests.state(RaceCrew.quest_id("rematch", "yard")), "open")


func _lines(crew_id: String) -> Array:
	return Quests.entries().filter(func(e): return str(e.id).ends_with("_" + crew_id))


func test_one_line_per_crew_lose_after_the_race_was_offered() -> void:
	WorldState.on_race_won("basin", 100)
	RaceCrew.settle_quests("basin", true, false)
	assert_eq(Quests.state(RaceCrew.quest_id("next", "salt")), "open")
	Quests.toggle_waypoint(RaceCrew.quest_id("next", "salt"))
	RaceCrew.settle_quests("salt", false, false)
	var lines := _lines("salt")
	assert_eq(lines.size(), 1, "one line for the salt crew")
	assert_eq(str(lines[0].id), RaceCrew.quest_id("rematch", "salt"))
	assert_true(bool(lines[0].waypoint), "the waypoint moved to the rematch")


func test_a_pink_slip_line_and_the_next_crew_line_together() -> void:
	WorldState.on_race_won("yard", 100)
	RaceCrew.settle_quests("yard", true, false)
	assert_eq(_lines("yard").size(), 1)
	assert_eq(str(_lines("yard")[0].id), RaceCrew.quest_id("slips", "yard"))
	assert_eq(str(_lines("basin")[0].id), RaceCrew.quest_id("next", "basin"))


func test_no_fresh_race_line_over_a_rematch() -> void:
	WorldState.on_race_won("yard", 100)
	RaceCrew.settle_quests("yard", true, false)
	RaceCrew.settle_quests("basin", false, false)       # lost to the basin crew
	RaceCrew.settle_quests("yard", true, true)          # won pinks off the yard crew
	assert_eq(_lines("basin").size(), 1)
	assert_eq(str(_lines("basin")[0].id), RaceCrew.quest_id("rematch", "basin"), "still the rematch")


func test_an_old_save_with_three_lines_keeps_one() -> void:
	for kind in ["next", "slips", "rematch"]:
		WorldState.quests[RaceCrew.quest_id(kind, "salt")] = { "state": "open", "waypoint": kind == "next" }
	RaceCrew.tidy_quests()
	var lines := _lines("salt")
	assert_eq(lines.size(), 1)
	assert_eq(str(lines[0].id), RaceCrew.quest_id("rematch", "salt"))
	assert_true(bool(lines[0].waypoint), "kept the waypoint")
