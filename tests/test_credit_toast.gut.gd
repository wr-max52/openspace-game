extends GutTest
## The credit toast (CreditToast): money in or out shows "+120 credits" green or
## "-40 credits" red under the banner's credits, newest on top, then fades. A
## load or the F11 cheat is not news.


func before_each() -> void:
	WorldState.reset()


func _toast() -> CreditToast:
	var t := CreditToast.new()
	add_child_autofree(t)
	return t


func test_a_fresh_hud_shows_nothing() -> void:
	WorldState.credits = 500
	var t := _toast()
	t.watch()
	assert_eq(t.rows.size(), 0, "the balance it starts with is not a change")


func test_money_in_and_out_each_show_a_line() -> void:
	var t := _toast()
	WorldState.credits += 120
	t.watch()
	WorldState.credits -= 40
	t.watch()
	assert_eq(t.rows.size(), 2)
	assert_eq(t.rows[0].text, "-40 credits", "newest on top")
	assert_eq(t.rows[1].text, "+120 credits")
	assert_eq(t.rows[0].get_theme_color("font_color"), StandingToast.RED)
	assert_eq(t.rows[1].get_theme_color("font_color"), StandingToast.GREEN)
	assert_eq(t.list.get_child(0), t.rows[0], "the list draws newest first")


func test_real_payments_show_with_no_wiring() -> void:
	WorldState.credits = 100
	var t := _toast()
	WorldState.on_guard_reward(25)             # a bounty in
	t.watch()
	WorldState.on_gate_bribe(30)               # a bribe out
	t.watch()
	assert_eq(t.rows.size(), 2)
	assert_eq(t.rows[0].text, "-30 credits")
	assert_eq(t.rows[1].text, "+25 credits")


func test_lines_fade_and_go() -> void:
	var t := _toast()
	WorldState.credits += 10
	t._process(0.0)
	assert_eq(t.rows.size(), 1)
	var r = t.rows[0]
	t._process(t._in + t._hold * 0.5)
	assert_almost_eq(r.modulate.a, 1.0, 0.01, "fully up while it holds")
	t._process(t._hold * 0.5 + t._out * 0.5)
	assert_lt(r.modulate.a, 1.0, "fading")
	t._process(t._out)
	assert_eq(t.rows.size(), 0, "gone after the fade")


func test_the_list_is_capped() -> void:
	var t := _toast()
	for i in t._max + 3:
		WorldState.credits += 1
		t.watch()
	assert_eq(t.rows.size(), t._max, "the oldest drop off")


func test_a_load_is_not_news() -> void:
	var t := _toast()
	WorldState.from_save({ "credits": 9000 })
	t.watch()
	assert_eq(t.rows.size(), 0)
	WorldState.credits += 5
	t.watch()
	assert_eq(t.rows.size(), 1, "after the load, money moving is news again")


func test_the_cheat_is_not_news() -> void:
	var t := _toast()
	WorldState.credits = 4000
	CreditToast.settle()
	t.watch()
	assert_eq(t.rows.size(), 0)


func test_money_moved_between_scenes_shows_on_the_next_hud() -> void:
	var a := _toast()
	a.watch()
	a.queue_free()
	WorldState.credits += 75                   # a payout on arrival, no HUD up
	var b := _toast()
	b.watch()
	assert_eq(b.rows.size(), 1)
	assert_eq(b.rows[0].text, "+75 credits")


func test_the_hud_carries_it() -> void:
	var hud := RetroHud.new()
	add_child_autofree(hud)
	assert_not_null(hud.credit_toast)
	assert_eq(hud.credit_toast.get_parent(), hud)


func test_look_numbers_come_from_ui_json() -> void:
	var cfg: Dictionary = RetroUI.ui().get(CreditToast.LOOK_KEY, {})
	assert_false(cfg.is_empty(), "content/look/ui.json has a credit_toast block")
	var t := _toast()
	assert_eq(t._hold, float(cfg.hold))
	assert_eq(t._max, int(cfg.max_rows))


func test_lines_move_under_a_space_fights_readout() -> void:
	var t := _toast()
	assert_eq(t.top(), CreditToast.TOP, "no fight: just under the banner")
	var layer := CanvasLayer.new()             # as SpaceFight._build_hud puts it
	add_child_autofree(layer)
	var r := Label.new()
	r.position = Vector2(100, 54)
	r.size = Vector2(400, 170)
	layer.add_child(r)
	SpaceFight.readout = r
	assert_eq(t.top(), 54.0 + 170.0 + t._fight_gap, "under the read-out, with the gap")
	r.visible = false
	assert_eq(t.top(), CreditToast.TOP, "a hidden read-out does not push it down")
	r.visible = true
	r.free()                                   # the fight is over
	assert_eq(t.top(), CreditToast.TOP, "back under the banner")
	SpaceFight.readout = null
