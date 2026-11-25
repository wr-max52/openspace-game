extends GutTest
## Speeder race quests: a win pays the pot into your credits at once and offers
## two optional quests (the next crew up the ladder, a pink-slip rematch with the
## crew you beat); a loss offers one (a rematch with the crew who beat you). The
## quests are data (racing/rules.json "quests") and point at the crew's hangout.


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
	assert_eq(Quests.cfg(RaceCrew.quest_id("slips", "basin")).get("title", ""), "Pink slip rematch - Basin crew")


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
	assert_eq(Quests.state(RaceCrew.quest_id("rematch", "basin")), "done", "won it back")
	assert_eq(Quests.state(RaceCrew.quest_id("next", "salt")), "open")


func test_beating_the_next_crew_finishes_their_quest() -> void:
	WorldState.on_race_won("yard", 100)
	RaceCrew.settle_quests("yard", true, false)
	WorldState.on_race_won("basin", 100)
	RaceCrew.settle_quests("basin", true, false)
	assert_eq(Quests.state(RaceCrew.quest_id("next", "basin")), "done")


func test_top_crew_offers_no_next_and_a_beaten_crew_is_not_offered_again() -> void:
	WorldState.on_race_won("salt", 100)
	RaceCrew.settle_quests("salt", true, false)
	for q in Quests.entries():
		assert_false(str(q.id).begins_with("race_next_"), "nobody above the salt crew")
	WorldState.set_flag("crew_beaten_basin")
	RaceCrew.settle_quests("yard", true, false)
	assert_eq(Quests.state(RaceCrew.quest_id("next", "basin")), "", "already beaten: no quest")


func test_a_pink_slip_race_does_the_slips_quest_and_a_loss_offers_a_rematch() -> void:
	WorldState.on_race_won("yard", 100)
	RaceCrew.settle_quests("yard", true, false)
	RaceCrew.settle_quests("yard", false, true)
	assert_eq(Quests.state(RaceCrew.quest_id("slips", "yard")), "done", "raced for slips")
	assert_eq(Quests.state(RaceCrew.quest_id("rematch", "yard")), "open")
