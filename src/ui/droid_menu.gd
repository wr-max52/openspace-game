class_name DroidMenu
extends CanvasLayer
## A pick list (issue #51): the droid merchant, a cargo droid's hold, and "you
## already run three droids: sell one?". No game logic: the caller hands it the
## options and a callback. Issue #58: an optional body (what T-89 is saying) sits
## between the title and the options.
##
## Keys: W/S or the arrows move the cursor, Enter picks the row under it, Esc
## walks away. A shop that reopens the menu from its pick
## callback (open with keep_cursor) stays where it was, so you can buy or sell
## again without starting over. Long lists scroll.
##
## A row marked "job" (what you are delivering for a job you have open) is green,
## and a fresh menu opens with the cursor on the first one.
##
## A row can also carry "alt" (the id Shift+Enter picks instead, e.g. stash the whole
## stack; "alt_hint" names it in the key hint) and "buttons" ([{ id, text }], small
## buttons at the row's end that pick their id when clicked; the mouse is freed while
## a menu with buttons is open). A cargo droid's hold: Stash one / Stash all, and
## Take one / Take all for what it holds. The cursor lands on a button too: A/D (or
## the left/right arrows) move between a row's buttons, the one under the cursor is
## lit, and Enter presses it. Buttons sit in a fixed-width column, so a row that
## gains or loses its second button does not change the menu's size, and a menu
## reopened with keep_cursor keeps its height.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const AMBER := Color("#e0a050")
const JOB_GREEN := Color("#6ee07a")   ## coloured, so RetroSkin leaves it be
const PANEL_W := 600.0             ## narrower on a small screen (or a big text size)
const LIST_MAX_H := 330.0          ## rows past this scroll (less on a short screen)
const MARK_W := 20.0               ## the cursor mark's column (not KEY_W: in here that would hide the W key)
const BTN_W := 100.0               ## one button; a row's buttons always take two of these
const BTN_GAP := 4.0
const BTN_COL := BTN_W * 2.0 + BTN_GAP
const LINE_GAP := 6.0
const HINT := "[W/S]  Move    [Enter]  Choose    [Esc]  Walk away"
const HINT_ALT := "[W/S]  Move    [Enter]  Choose    [Shift+Enter]  %s    [Esc]  Walk away"
const HINT_BUTTONS := "[W/S]  Move    [A/D]  Button    [Enter]  Choose    [Esc]  Walk away"

var panel: PanelContainer
var title_label: Label
var body_label: Label
var scroll: ScrollContainer
var list: VBoxContainer
var hint: Label
var options: Array = []           ## [{ id, text }]
var on_pick: Callable             ## (id: String) -> void; "" = walked away
var rows: Array = []              ## the text of each row, for tests
var selected := 0                 ## the row under the cursor
var button := 0                   ## the button under the cursor in that row (kept when moving rows)
var _rows: Array = []             ## [{ box: PanelContainer, key: Label, text: Label, buttons: [Button] }]
var _keep_h := 0.0                ## reopened with keep_cursor: the list keeps this height
var _cursor_box: StyleBoxFlat
var _row_box: StyleBoxEmpty
var _freed_mouse := false         ## we showed the mouse for the buttons
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _counted := false             ## this menu is in open_count
static var open_count := 0        ## menus up right now: the player does not walk while any is
signal option_selected(id: String)


func _init() -> void:
	name = "DroidMenu"
	layer = 8


func _ready() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	title_label = Label.new()
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", AMBER)
	box.add_child(title_label)
	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 17)
	body_label.add_theme_color_override("font_color", INK)
	box.add_child(body_label)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	hint = Label.new()
	hint.text = HINT
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(INK, 0.6))
	box.add_child(hint)
	_cursor_box = StyleBoxFlat.new()
	_cursor_box.border_width_left = 3
	_cursor_box.set_content_margin_all(2)
	_row_box = StyleBoxEmpty.new()
	_row_box.set_content_margin_all(2)
	panel.visible = false


func is_open() -> bool:
	return panel != null and panel.visible


## Some menu is up. W/S move its cursor, so the player's body stands still
## (CharacterBody checks this), whether or not the shop locked the player itself.
static func any_open() -> bool:
	return open_count > 0


func _count(on: bool) -> void:
	if on != _counted:
		_counted = on
		open_count = maxi(open_count + (1 if on else -1), 0)


func _exit_tree() -> void:
	_count(false)


## Show the menu. keep_cursor: the same menu again (after a buy or a sale), so the
## cursor stays on the row it was on, or the row that took its place.
func open(title: String, opts: Array, pick: Callable, body: String = "", keep_cursor: bool = false) -> void:
	var was := str(options[selected].id) if keep_cursor and selected < options.size() else ""
	options = opts.duplicate()
	on_pick = pick
	rows.clear()
	var at := -1
	if was != "":
		for i in options.size():
			if str(options[i].id) == was:
				at = i
				break
	selected = at if at >= 0 else (clampi(selected, 0, maxi(options.size() - 1, 0)) if keep_cursor else first_job())
	if not keep_cursor:
		button = 0
	_keep_h = scroll.custom_minimum_size.y if keep_cursor and scroll != null else 0.0
	for i in options.size():
		rows.append(str(options[i].text))
	if panel == null:
		return
	title_label.text = title
	hint.text = _hint_text()
	body_label.text = body
	body_label.visible = body != ""
	for c in list.get_children():
		c.free()
	_rows.clear()
	for i in options.size():
		var box := PanelContainer.new()
		box.set_meta("retro_off", true)     # the cursor bar is ours, not RetroSkin's glass
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", int(LINE_GAP))
		box.add_child(line)
		var key := _row_label("")
		key.custom_minimum_size.x = MARK_W
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN     # level with the first line
		line.add_child(key)
		var text := _row_label(str(options[i].text))
		if bool(options[i].get("job", false)):
			text.add_theme_color_override("font_color", JOB_GREEN)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART     # long offers wrap under the text, not the cursor
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		var btns: Array = []
		var defs: Array = options[i].get("buttons", [])
		if not defs.is_empty():
			var col := HBoxContainer.new()     # the same width whether it holds one button or two
			col.add_theme_constant_override("separation", int(BTN_GAP))
			col.custom_minimum_size.x = BTN_COL
			col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			line.add_child(col)
			for j in defs.size():
				var btn := Button.new()
				btn.set_meta("retro_off", true)     # lit by _show_cursor, not RetroSkin
				btn.text = str(defs[j].text)
				btn.clip_text = true
				btn.custom_minimum_size.x = BTN_COL if defs.size() == 1 else BTN_W
				btn.focus_mode = Control.FOCUS_NONE     # the keys stay the menu's
				btn.add_theme_font_size_override("font_size", 14)
				btn.add_theme_font_override("font", RetroUI.font("Bold"))
				btn.pressed.connect(choose.bind(str(defs[j].id)))
				btn.mouse_entered.connect(_point.bind(i, j))
				col.add_child(btn)
				btns.append(btn)
		list.add_child(box)
		_rows.append({ "box": box, "key": key, "text": text, "buttons": btns })
	_fit()
	_show_cursor()
	panel.visible = true
	_count(true)
	if has_buttons() and not _freed_mouse:
		_mouse_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_freed_mouse = true
	_fit.call_deferred()     # again once RetroSkin has swapped the font in


## Some row has a Shift+Enter choice.
func has_alt() -> bool:
	for o in options:
		if str(o.get("alt", "")) != "":
			return true
	return false


## What Shift+Enter does, for the key hint: the row under the cursor's "alt_hint",
## else the first row's (a hold mixes Stash all and Take all rows).
func alt_hint() -> String:
	if selected < options.size() and str(options[selected].get("alt_hint", "")) != "":
		return str(options[selected].alt_hint)
	for o in options:
		if str(o.get("alt_hint", "")) != "":
			return str(o.alt_hint)
	return "All"


func has_buttons() -> bool:
	for o in options:
		if not (o.get("buttons", []) as Array).is_empty():
			return true
	return false


func _hint_text() -> String:
	if has_buttons():
		return HINT_BUTTONS     # one line whatever row the cursor is on, so the box keeps its size
	return HINT_ALT % alt_hint() if has_alt() else HINT


## The buttons of row `i` (from its options, so it works before the panel is built).
func _buttons_of(i: int) -> Array:
	return options[i].get("buttons", []) if i >= 0 and i < options.size() else []


## The button under the cursor in the selected row, or -1 when that row has none.
func button_at() -> int:
	var n := _buttons_of(selected).size()
	return -1 if n == 0 else mini(button, n - 1)


## The id Enter picks: the lit button, else the row's own id.
func picked_id() -> String:
	if selected >= options.size():
		return ""
	var b := button_at()
	return str(_buttons_of(selected)[b].id) if b >= 0 else str(options[selected].id)


## The first row marked "job", or 0 when there is none.
func first_job() -> int:
	for i in options.size():
		if bool(options[i].get("job", false)):
			return i
	return 0


func _row_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", INK)
	return l


## Size the box to the screen: at a big text size the screen is small in UI units,
## so the box narrows, rows wrap, and the list scrolls rather than run off it.
func _fit() -> void:
	if panel == null:
		return
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var w := minf(PANEL_W, vp.x - 32.0)
	panel.offset_left = -w * 0.5
	panel.offset_right = w * 0.5
	var inner := w - 28.0
	var wraps := [title_label, body_label, hint]
	var widths := [inner, inner, inner]
	for r in _rows:
		wraps.append(r.text)
		var tw := inner - 16.0 - MARK_W - LINE_GAP     # less the scroll bar, the cursor mark, the gap
		if not (r.buttons as Array).is_empty():
			tw -= BTN_COL + LINE_GAP                   # and the button column
		widths.append(tw)
	for i in wraps.size():
		var l: Label = wraps[i]
		l.custom_minimum_size.x = widths[i]
		l.size.x = widths[i]     # wrap at this width now, not after the next layout pass
	var h := 0.0
	for r in _rows:
		h += r.box.get_combined_minimum_size().y + 2.0
	var rest := title_label.get_combined_minimum_size().y + hint.get_combined_minimum_size().y + 60.0
	if body_label.visible:
		rest += body_label.get_combined_minimum_size().y
	var room := clampf(vp.y * 0.92 - rest, 60.0, LIST_MAX_H)
	scroll.custom_minimum_size = Vector2(inner, minf(maxf(h, _keep_h), room))
	var ph := panel.get_combined_minimum_size().y
	panel.offset_top = -ph * 0.5
	panel.offset_bottom = ph * 0.5


## Move the cursor by `step` rows (wraps round).
func move(step: int) -> void:
	if options.is_empty():
		return
	selected = posmod(selected + step, options.size())
	_show_cursor()


## Move the cursor between the selected row's buttons (stops at the ends).
func move_button(step: int) -> void:
	var n := _buttons_of(selected).size()
	if n < 2:
		return
	button = clampi(button_at() + step, 0, n - 1)
	_show_cursor()


## The mouse is over button `j` of row `i`: the cursor follows it.
func _point(i: int, j: int) -> void:
	if i == selected and j == button_at():
		return
	selected = i
	button = j
	_show_cursor()


## The row under the cursor: a lit bar behind it in the HUD colour (RetroSkin
## owns the text colours) and a ">" in front of it.
func _show_cursor() -> void:
	_cursor_box.bg_color = Color(RetroUI.accent, 0.28)
	_cursor_box.border_color = RetroUI.accent
	var lit := button_at()
	for i in _rows.size():
		var on := i == selected
		_rows[i].box.add_theme_stylebox_override("panel", _cursor_box if on else _row_box)
		_rows[i].key.text = ">" if on else ""
		var btns: Array = _rows[i].buttons
		for j in btns.size():
			_style_button(btns[j], on and j == lit)
	hint.text = _hint_text()
	_scroll_to_cursor()


## A row button: filled in the HUD colour with dark text under the cursor, dark
## glass with a thin rim otherwise.
func _style_button(b: Button, on: bool) -> void:
	var a := RetroUI.accent
	var sb: StyleBoxFlat
	if on:
		sb = StyleBoxFlat.new()
		sb.bg_color = a
		sb.set_content_margin_all(6.0)
	else:
		sb = RetroUI.box(0.85, 1, 6.0)
		sb.shadow_size = 0
	for k in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(k, sb)
	var ink := Color.BLACK if on else a
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, ink)


## Once the list has been laid out (the rows' places are known), bring the cursor
## row into view.
func _scroll_to_cursor() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if scroll != null and selected < _rows.size() and is_instance_valid(_rows[selected].box):
		scroll.ensure_control_visible(_rows[selected].box)


## Pick an option by id ("" = walk away). The same path the keys use.
func choose(id: String) -> void:
	for i in options.size():
		if str(options[i].id) == id:
			selected = i
			break
	if panel != null:
		panel.visible = false
	_count(false)
	if _freed_mouse:
		_freed_mouse = false
		Input.mouse_mode = _mouse_before
	var cb := on_pick
	on_pick = Callable()
	option_selected.emit(id)
	if cb.is_valid():
		cb.call(id)


## _input, not _unhandled_input: the menu is modal, and a focused Control would
## otherwise take the arrow keys for focus moves first.
func _input(event: InputEvent) -> void:
	if not is_open() or not (event is InputEventKey) or not event.pressed:
		return
	var k := (event as InputEventKey).keycode
	if k in [KEY_UP, KEY_W, KEY_DOWN, KEY_S]:     # held: keeps moving
		move(-1 if k in [KEY_UP, KEY_W] else 1)
		get_viewport().set_input_as_handled()
		return
	if k in [KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D]:
		move_button(-1 if k in [KEY_LEFT, KEY_A] else 1)
		get_viewport().set_input_as_handled()
		return
	if event.echo:
		return
	if k == KEY_ESCAPE:
		choose("")
		get_viewport().set_input_as_handled()
	elif k in [KEY_ENTER, KEY_KP_ENTER] and selected < options.size():
		var alt := str(options[selected].get("alt", ""))
		choose(alt if event.shift_pressed and alt != "" else picked_id())
		get_viewport().set_input_as_handled()
