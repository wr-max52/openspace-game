extends GutTest
## A wrap-up and a new job come one after the other: Oda closes the last chapter
## first ("wrap_up"), and Next brings the new job's line and its card. The line
## shrinks to fit the box and the card stands above the box, never on it. The
## droid merchant pays 200 cr for the cargo droid.


func before_each() -> void:
	WorldState.new_game(WorldState.STORY)


func _to_heist() -> void:
	Story.skip_to("droid_merchant")
	Story.on_droid_delivered()
	assert_eq(Story.chapter(), "heist")


func test_the_heist_beat_splits_the_wrap_up_from_the_job() -> void:
	_to_heist()
	var beat := Story.beat("cantina_owner")
	assert_true(str(beat.wrap_up).contains("weapon I promised"), "the droid chapter's wrap-up first")
	assert_false(str(beat.wrap_up).contains("job"), "with no word of the job")
	assert_true(str(beat.then).contains("Here's the job"), "then the job")
	assert_true(str(beat.say).begins_with(str(beat.wrap_up)), "say is still the whole of it")
	assert_eq(str(beat.job), "j_heist")
	var again := Story.beat("cantina_owner")
	assert_false(again.has("wrap_up"), "the wrap-up is said once")


func test_the_bounty_and_the_sparring_droid_too() -> void:
	Story.skip_to("remote")
	var beat := Story.beat("cantina_owner")
	assert_true(str(beat.wrap_up).contains("forty"))
	assert_true(str(beat.then).contains("five"))
	Story.skip_to("bounty")
	beat = Story.beat("cantina_owner")
	assert_true(str(beat.wrap_up).contains("flask"))
	assert_true(str(beat.then).contains("Skrugs"))
	assert_eq(str(beat.job), "j_bounty")


func test_the_panel_shows_one_then_the_next() -> void:
	var p := DialoguePanel.new()
	add_child_autofree(p)
	await wait_frames(1)
	var said: Array = []
	p.advanced.connect(func(t): said.append(t))
	p.open("Oda Vell", "My friend's happy.")
	p.queue_next("Here's the job.", { "id": "j_heist", "title": "A job", "text": "Rob it.", "pays": 10 })
	assert_true(p.has_next())
	assert_false(p.job_open(), "no card over the wrap-up")
	assert_false(p._field.editable, "the next line waits for Next")
	assert_true(p._next_row.visible)
	p.advance()
	assert_eq(p.line_text(), "Here's the job.")
	assert_true(p.history_text().contains("My friend's happy."), "the wrap-up goes up into the history")
	assert_true(p.job_open(), "the card comes with the job")
	assert_true(p._field.editable)
	assert_false(p._next_row.visible)
	assert_eq(said, ["Here's the job."])


func test_a_long_line_fits_the_box_and_the_card_sits_above_it() -> void:
	var p := DialoguePanel.new()
	add_child_autofree(p)
	await wait_frames(1)
	p.open("Oda Vell", "")
	var long_line := "My friend's happy, so here's the weapon I promised: somebody stashed an energy blade up on top of this cantina's tower, and it's still there. Climb up and take it. Here's the job, and you'll want that blade for it. The Remnant keep a stash of refined quantonium in the control room at the broken ridge outpost. Take one of my people and a droid, breach the vault with your welder, and bring the flasks to the fence. About 1080 cr after the crew's cut."
	p.set_line(long_line)
	p.show_job({ "id": "j", "title": "A job on a Remnant control room", "text": long_line, "pays": 1080 })
	await wait_frames(2)
	var vp := get_viewport().get_visible_rect().size
	var box: Rect2 = p._root.get_global_rect()
	assert_lte(box.end.y, vp.y + 1.0, "the box stays on the screen")
	assert_almost_eq(box.size.y, p.box_size().y, 2.0, "the line does not stretch the box")
	assert_lt(p.line_font_size(), RetroUI.size("dialogue_line", 34), "the long line's font shrinks to fit")
	var card: Rect2 = p._job.get_global_rect()
	assert_lte(card.end.y, box.position.y, "the card is above the box, not over it")


func test_the_droid_merchant_pays_200_for_your_trouble() -> void:
	Story.skip_to("droid_merchant")
	var c0 := WorldState.credits
	assert_eq(Story.on_droid_delivered(), 200)
	assert_eq(WorldState.credits, c0 + 200)
	assert_eq(Story.on_droid_delivered(), 0, "once")
	var line := str(JSON.parse_string(FileAccess.get_file_as_string("res://content/core/droids/droids.json")).labels.delivered_paid)
	assert_true(line.contains("I almost missed an order"))


func test_skipping_past_the_droid_merchant_pays_it_too() -> void:
	Story.skip_to("droid_merchant")
	var c0 := WorldState.credits
	Story.skip_to("heist")
	assert_eq(WorldState.credits, c0 + 200)
