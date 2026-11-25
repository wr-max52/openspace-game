extends GutTest
## The pick list's cursor keys: W and Up go up, S and Down go down, both wrap.
## (W once did nothing: a layout constant named KEY_W hid the W key inside the menu.)


func _menu() -> DroidMenu:
	var m := DroidMenu.new()
	add_child_autofree(m)
	m.open("t", [{ "id": "a", "text": "A" }, { "id": "b", "text": "B" }, { "id": "c", "text": "C" }], func(_id): pass)
	return m


func _press(m: DroidMenu, keycode: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	m._input(e)


func test_s_and_down_go_down_and_w_and_up_go_up() -> void:
	var m := _menu()
	_press(m, KEY_S)
	assert_eq(m.selected, 1, "S goes down")
	_press(m, KEY_DOWN)
	assert_eq(m.selected, 2, "Down goes down")
	_press(m, KEY_W)
	assert_eq(m.selected, 1, "W goes back up")
	_press(m, KEY_UP)
	assert_eq(m.selected, 0, "Up goes up")


func test_the_cursor_wraps_round() -> void:
	var m := _menu()
	_press(m, KEY_W)
	assert_eq(m.selected, 2, "up from the top lands on the last row")
	_press(m, KEY_S)
	assert_eq(m.selected, 0, "down from the last row lands on the first")


## W/S move the cursor, not the player: while any menu is up the player's body
## stands still, even when the shop that opened it (the race crew) did not lock them.
func test_an_open_menu_holds_the_player_still() -> void:
	var before := DroidMenu.open_count
	var m := _menu()
	assert_true(DroidMenu.any_open(), "open: the player does not walk")
	m.choose("")
	assert_eq(DroidMenu.open_count, before, "closed: they walk again")
	m.open("t", [{ "id": "a", "text": "A" }], func(_id): pass)
	m.free()
	assert_eq(DroidMenu.open_count, before, "a menu freed while open lets go too")
