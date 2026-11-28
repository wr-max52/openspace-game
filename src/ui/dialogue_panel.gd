class_name DialoguePanel
extends CanvasLayer
## The conversation UI (M12): their name and mood, a streamed subtitle (driven
## by real deltas, not fake typing), the last few lines, a text field, credits and
## tab, and the job card. Enter speaks, Esc leaves.
##
## Issue #47: sized to be read. The box takes up to 1180 x 400 px (less on a small
## window), the text is larger, the background nearly opaque. Issue #29: a notice
## line at the top says this is an AI character, and post_notice() repeats it in
## the history when the player's words call for it. Issue #328: with AI
## characters off (or every model down) a row of topic buttons sits above the text
## field; a button says that topic's line for the player (topic_picked).
##
## A wrap-up and a new job come one after the other (queue_next): the wrap-up
## first, then [Enter] or Next brings the job's line and its card. The line
## shrinks its font to fit the box, and the card sits above the box, never on it.

signal submitted(text: String)
signal leave_requested
signal job_answered(job_id: String, accepted: bool)
signal sale_answered(item_id: String, accepted: bool)   ## issue #42: the speeder card
signal topic_picked(topic_id: String)                   ## issue #328: a topic button
signal advanced(text: String)                           ## Next pressed: the queued line is up

const WIDTH := 1180.0
const HEIGHT := 460.0
const MARGIN := 40.0                 ## kept clear at the window's edges
const MIN_SIZE := Vector2(640, 300)  ## never smaller than this, however small the window
const HISTORY_LINES := 10
const LINE_MIN := 74.0               ## the line's height when it is short
const HISTORY_MIN := 56.0            ## the history gives way to a long line, down to this
const JOB_WIDTH := 760.0
const JOB_GAP := 12.0                ## between the card and the box below it

var npc_name := "Cantina Owner"
var _root: PanelContainer
var _notice: Label
var _name: Label
var _mood: Label
var _history: RichTextLabel
var _line: RichTextLabel
var _field: LineEdit
var _money: Label
var _hint: Label
var _job: PanelContainer
var _job_title: Label
var _job_text: Label
var _job_id := ""
var _job_kind := "job"               ## "job" or "sale": which signal the card answers with
var _yes: Button
var _no: Button
var _lines: Array = []
var _topics: HFlowContainer         ## issue #328: the topic buttons ([] hides the row)
var _v: VBoxContainer
var _next_row: HBoxContainer
var _next: Button
var _queued := {}                    ## { text, job }: what Next brings up ({} = nothing)


func _ready() -> void:
	layer = 6
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.035, 0.94)
	sb.border_color = Color("#c9a35e")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_root.add_theme_stylebox_override("panel", sb)
	add_child(_root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_root.add_child(v)
	_v = v
	_notice = Label.new()
	_notice.add_theme_font_size_override("font_size", RetroUI.size("dialogue_hint", 20))
	_notice.add_theme_color_override("font_color", Color("#9fc7e8"))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	v.add_child(_notice)
	var head := HBoxContainer.new()
	v.add_child(head)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", RetroUI.size("dialogue_name", 32))
	_name.add_theme_color_override("font_color", Color("#e0a050"))
	head.add_child(_name)
	_mood = Label.new()
	_mood.add_theme_font_size_override("font_size", RetroUI.size("dialogue_small", 22))
	_mood.add_theme_color_override("font_color", Color(0.85, 0.8, 0.72))
	_mood.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_mood)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", RetroUI.size("dialogue_small", 22))
	_money.add_theme_color_override("font_color", Color(0.85, 0.8, 0.72))
	head.add_child(_money)
	_history = RichTextLabel.new()
	_history.bbcode_enabled = true
	_history.fit_content = false
	_history.scroll_following = true
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.custom_minimum_size = Vector2(0, 0)          # _history_room: room once it has lines
	_history.add_theme_font_size_override("normal_font_size", RetroUI.size("dialogue_history", 26))
	_history.add_theme_color_override("default_color", Color(0.86, 0.82, 0.76))
	v.add_child(_history)
	_line = RichTextLabel.new()
	_line.bbcode_enabled = true
	_line.fit_content = false                # _fit_line sizes it, so the box never runs off the screen
	_line.scroll_active = false
	_line.custom_minimum_size = Vector2(0, LINE_MIN)
	_line.add_theme_font_size_override("normal_font_size", RetroUI.size("dialogue_line", 34))
	_line.add_theme_font_size_override("italics_font_size", RetroUI.size("dialogue_line", 34))
	_line.add_theme_color_override("default_color", Color(1.0, 0.97, 0.9))
	v.add_child(_line)
	_next_row = HBoxContainer.new()
	_next_row.alignment = BoxContainer.ALIGNMENT_END
	_next_row.visible = false
	v.add_child(_next_row)
	_next = Button.new()
	_next.text = "Next  [Enter]"
	_next.focus_mode = Control.FOCUS_NONE
	_next.add_theme_font_size_override("font_size", RetroUI.size("job_button", 26))
	_next.pressed.connect(advance)
	_next_row.add_child(_next)
	_topics = HFlowContainer.new()
	_topics.add_theme_constant_override("h_separation", 10)
	_topics.add_theme_constant_override("v_separation", 6)
	_topics.visible = false
	v.add_child(_topics)
	_field = LineEdit.new()
	_field.placeholder_text = "Say something, then [Enter].  [Esc] leaves."
	_field.add_theme_font_size_override("font_size", RetroUI.size("dialogue_field", 28))
	_field.custom_minimum_size = Vector2(0, 44)
	_field.max_length = 300
	_field.text_submitted.connect(_on_submit)
	v.add_child(_field)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", RetroUI.size("dialogue_hint", 20))
	_hint.add_theme_color_override("font_color", Color(0.65, 0.62, 0.58))
	_hint.text = "[F3] debug   [F10] AI settings   [Shift]+[F10] cycle local / cloud / auto"
	v.add_child(_hint)
	_build_job_card()
	get_viewport().size_changed.connect(fit)
	fit()
	visible = false


## Size the box to the window: WIDTH x HEIGHT, smaller if the window is.
func fit() -> void:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var w := clampf(vp.x - MARGIN * 2.0, MIN_SIZE.x, WIDTH)
	var h := clampf(vp.y * 0.5, MIN_SIZE.y, HEIGHT)
	_root.offset_left = -w * 0.5
	_root.offset_right = w * 0.5
	_root.offset_top = -h - 20.0
	_root.offset_bottom = -20.0
	# The card stands on the box's top edge and grows up from it.
	var jw := minf(JOB_WIDTH, w)
	_job.offset_left = -jw * 0.5
	_job.offset_right = jw * 0.5
	_job.offset_bottom = _root.offset_top - JOB_GAP
	_job.offset_top = _job.offset_bottom - 10.0
	_job_text.custom_minimum_size.x = jw - 40.0
	_fit_line()
	_fit_job()


func box_size() -> Vector2:
	return Vector2(_root.offset_right - _root.offset_left, _root.offset_bottom - _root.offset_top)


## Issue #29: the notice pinned at the top of the box ("" hides it).
func set_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = text != ""
	_fit_line()


func notice() -> String:
	return _notice.text if _notice.visible else ""


## Issue #29: the notice again, highlighted, in the history.
func post_notice(text: String) -> void:
	_add_history("[color=#9fc7e8][b]%s[/b][/color]" % text.replace("[", "("))


func history_text() -> String:
	return _history.text


func _build_job_card() -> void:
	_job = PanelContainer.new()
	_job.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_job.grow_vertical = Control.GROW_DIRECTION_BEGIN     # fit() puts its bottom on the box's top
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.07, 0.95)
	sb.border_color = Color("#e0a050")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_job.add_theme_stylebox_override("panel", sb)
	add_child(_job)
	var v := VBoxContainer.new()
	_job.add_child(v)
	_job_title = Label.new()
	_job_title.add_theme_font_size_override("font_size", RetroUI.size("job_title", 32))
	_job_title.add_theme_color_override("font_color", Color("#e0a050"))
	v.add_child(_job_title)
	_job_text = Label.new()
	_job_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_job_text.custom_minimum_size = Vector2(JOB_WIDTH - 40.0, 0)
	_job_text.add_theme_font_size_override("font_size", RetroUI.size("job_text", 26))
	v.add_child(_job_text)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(h)
	_no = Button.new()
	_no.text = "Not now"
	_no.add_theme_font_size_override("font_size", RetroUI.size("job_button", 26))
	_no.pressed.connect(func(): _answer(false))
	h.add_child(_no)
	_yes = Button.new()
	_yes.text = "Take the job"
	_yes.add_theme_font_size_override("font_size", RetroUI.size("job_button", 26))
	_yes.pressed.connect(func(): _answer(true))
	h.add_child(_yes)
	_job.visible = false


func open(name_text: String, greeting: String) -> void:
	npc_name = name_text
	_name.text = name_text.to_upper()
	_lines.clear()
	_history.text = ""
	_history_room()
	visible = true
	set_line(greeting)
	focus()


func close() -> void:
	visible = false
	_job.visible = false
	_set_queued({})


func focus() -> void:
	if _field != null and visible:
		_field.grab_focus()


func set_mood(m: String) -> void:
	_mood.text = "   " + m


func set_money(credits: int, tab: int) -> void:
	_money.text = "credits %d   tab %d" % [credits, tab]


## The streamed subtitle (replaced as more words arrive).
func set_line(text: String, thinking: bool = false) -> void:
	_line.text = ("[i]" + text + "[/i]") if thinking else text
	_fit_line()


func line_text() -> String:
	return _line.get_parsed_text()


func line_font_size() -> int:
	return _line.get_theme_font_size("normal_font_size")


## The line's font, largest first, down until the words fit the room the box has
## left for them; the line then takes just that height. Past the smallest size it
## scrolls rather than push the box off the screen.
func _fit_line() -> void:
	if _line == null or _v == null:
		return
	var full := RetroUI.size("dialogue_line", 34)
	var smallest := maxi(16, int(full * 0.55))
	var text := _line.get_parsed_text()
	var w := box_size().x - 52.0
	if w <= 0.0:
		return                               # not sized yet: fit() calls again
	var room := maxf(_line_room(), 30.0)
	var font := _line.get_theme_font("normal_font")
	var size := full
	var h := 0.0
	while true:
		h = _text_height(font, text, w, size)
		if h <= room or size <= smallest:
			break
		size -= 2
	_line.add_theme_font_size_override("normal_font_size", size)
	_line.add_theme_font_size_override("italics_font_size", size)
	_line.scroll_active = h > room
	_line.custom_minimum_size.y = minf(maxf(h, LINE_MIN), room) if room >= LINE_MIN else room
	_refit_in = 2                            # again once the box has laid itself out


var _refit_in := 0
var _laid_out := false


func _process(_dt: float) -> void:
	if _refit_in <= 0 or not visible:
		return
	_refit_in -= 1
	if _refit_in == 0:
		_laid_out = true
		_fit_line()
		_refit_in = 0                        # measured: no need to go round again


static func _text_height(font: Font, text: String, w: float, size: int) -> float:
	if font == null or text == "":
		return 0.0
	# A little over the font's own measure: the label adds line spacing.
	return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w, size).y * 1.12 + 4.0


## The height the box has for the line. Laid out, it is what the line and the
## history have between them now (less the history's smallest, and any overflow);
## before that (and a frame after anything changes: _refit) an estimate from the
## box's inside less everything else shown in it.
func _line_room() -> float:
	if _laid_out and _line.size.y > 0.0:
		var over := maxf(0.0, _root.size.y - box_size().y)
		return _line.size.y + _history.size.y - _history.custom_minimum_size.y - over
	var inner := box_size().y - 32.0
	var sep := float(_v.get_theme_constant("separation"))
	var used := 0.0
	var shown := 0
	for c in _v.get_children():
		var ctl := c as Control
		if ctl == null or not ctl.visible:
			continue
		shown += 1
		if ctl == _line:
			continue
		used += _history.custom_minimum_size.y if ctl == _history else ctl.get_combined_minimum_size().y
	return inner - used - sep * maxf(0.0, shown - 1)


## The card's text shrinks too when the card would not fit above the box.
func _fit_job() -> void:
	if _job_text == null or _job_title == null:
		return
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var full := RetroUI.size("job_text", 26)
	var smallest := maxi(14, int(full * 0.6))
	# Above the box: less the gap, a margin at the top, the card's own padding,
	# the title and the buttons.
	var room := vp.y + _job.offset_bottom - 20.0 - 24.0 \
		- _job_title.get_combined_minimum_size().y - _yes.get_combined_minimum_size().y - 8.0
	var font := _job_text.get_theme_font("font")
	var w := _job_text.custom_minimum_size.x
	var size := full
	while size > smallest and _text_height(font, _job_text.text, w, size) > room:
		size -= 2
	_job_text.add_theme_font_size_override("font_size", size)


func job_box() -> Rect2:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var h := _job.get_combined_minimum_size().y
	return Rect2(vp.x * 0.5 + _job.offset_left, vp.y + _job.offset_bottom - h, _job.offset_right - _job.offset_left, h)


func panel_box() -> Rect2:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	return Rect2(vp.x * 0.5 + _root.offset_left, vp.y + _root.offset_top, box_size().x, box_size().y)


# ------------------------------------------------------------------ one line, then the next

## Put `text` (and `job`'s card, if any) behind a Next button: the current line
## stays up until the player has read it. Input waits meanwhile.
func queue_next(text: String, job: Dictionary = {}) -> void:
	_set_queued({ "text": text, "job": job })


func has_next() -> bool:
	return not _queued.is_empty()


## The queued line up (the one before into the history), then its card.
func advance() -> void:
	if _queued.is_empty():
		return
	var q := _queued
	_set_queued({})
	commit_line()
	set_line(str(q.text))
	if not (q.job as Dictionary).is_empty():
		show_job(q.job)
	advanced.emit(str(q.text))


func _set_queued(q: Dictionary) -> void:
	_queued = q
	if _next_row == null:
		return
	_next_row.visible = not q.is_empty()
	set_input_enabled(q.is_empty())
	_fit_line()


## Move the current line into the history scroll.
func commit_line() -> void:
	var t := _line.text
	if t != "":
		_add_history("[color=#e0a050]%s:[/color] %s" % [npc_name, t])


func add_player_line(text: String) -> void:
	_add_history("[color=#9ad0c8]You:[/color] " + text.replace("[", "("))


func _add_history(bb: String) -> void:
	_lines.append(bb)
	while _lines.size() > HISTORY_LINES:
		_lines.pop_front()
	_history.text = "\n".join(_lines)
	_history_room()


## An empty history takes no room from the line; one with lines keeps a little.
func _history_room() -> void:
	_history.custom_minimum_size.y = HISTORY_MIN if not _lines.is_empty() else 0.0
	_fit_line()


func set_input_enabled(on: bool) -> void:
	_field.editable = on
	for b in _topics.get_children():
		(b as Button).disabled = not on
	if on:
		focus()


## Issue #328: the topic buttons, [{ id, label }] ([] hides the row).
func set_topics(list: Array) -> void:
	for b in _topics.get_children():
		_topics.remove_child(b)
		b.queue_free()
	for t in list:
		var b := Button.new()
		b.name = str(t.id)
		b.text = str(t.label)
		b.focus_mode = Control.FOCUS_NONE       # Enter stays the text field's
		b.disabled = not _field.editable        # a menu put up mid-answer waits for it
		b.add_theme_font_size_override("font_size", RetroUI.size("dialogue_topic", 22))
		b.pressed.connect(func(): topic_picked.emit(str(t.id)))
		_topics.add_child(b)
	_topics.visible = not list.is_empty()
	_fit_line()
	_field.placeholder_text = "Pick a topic or type, then [Enter].  [Esc] leaves." if not list.is_empty() \
		else "Say something, then [Enter].  [Esc] leaves."


func topic_ids() -> Array:
	return _topics.get_children().map(func(b): return str(b.name))


## Tests and bots press a topic button through here.
func press_topic(id: String) -> bool:
	for b in _topics.get_children():
		if str(b.name) == id and not (b as Button).disabled:
			topic_picked.emit(id)
			return true
	return false


func show_job(job: Dictionary) -> void:
	_job_id = str(job.get("id", ""))
	_job_kind = "job"
	_job_title.text = str(job.get("title", "A job"))
	var pay := int(job.get("pays", 0))
	_job_text.text = str(job.get("text", "")) + ("\n\nPays %d credits." % pay if pay > 0 else "")   # 0: the text says the pay
	_yes.text = "Take the job"
	_yes.disabled = false
	_job.visible = true
	_fit_job()


## Issue #42: something for sale. `item`: { id, name, price, text }. The Buy
## button is off when the player cannot afford it; only a click buys. Issue #295:
## with "selling", the other way round: they pay the player, and Sell is the button.
func show_sale(item: Dictionary, credits: int) -> void:
	_job_id = str(item.get("id", ""))
	_job_kind = "sale"
	var price := int(item.get("price", 0))
	if bool(item.get("selling", false)):
		_job_title.text = "%s  ·  +%d credits" % [str(item.get("name", "Your ship")), price]
		_job_text.text = "%s\n\nYou have %d credits." % [str(item.get("text", "")), credits]
		_yes.text = "Sell"
		_yes.disabled = false
		_job.visible = true
		_fit_job()
		return
	_job_title.text = "%s  ·  %d credits" % [str(item.get("name", "For sale")).capitalize(), price]
	var afford := credits >= price
	_job_text.text = "%s\n\nYou have %d credits.%s" % [str(item.get("text", "")), credits,
		"" if afford else "  Not enough."]
	_yes.text = "Buy" if afford else "Can't afford"
	_yes.disabled = not afford
	_job.visible = true
	_fit_job()


func job_open() -> bool:
	return _job.visible


func _answer(yes: bool) -> void:
	_job.visible = false
	if _job_kind == "sale":
		sale_answered.emit(_job_id, yes)
	else:
		job_answered.emit(_job_id, yes)
	focus()


## Tests and bots press the card's buttons through here.
func answer_card(yes: bool) -> void:
	if _job.visible and not (yes and _yes.disabled):
		_answer(yes)


func _on_submit(text: String) -> void:
	if text.strip_edges() == "":
		return
	_field.text = ""
	submitted.emit(text)


func _input_event_esc(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE


func _input(event: InputEvent) -> void:
	if visible and _input_event_esc(event):
		get_viewport().set_input_as_handled()
		leave_requested.emit()
	elif visible and has_next() and event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE):
		get_viewport().set_input_as_handled()
		advance()
