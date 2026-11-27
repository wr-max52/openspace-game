class_name GraphicsChoiceOverlay
extends CanvasLayer
## The first launch's first question, before the AI notice (DisclaimerOverlay) and
## New Game: Low graphics or Full graphics. Asked only on the first start (SavePrefs.
## ask_graphics), never in a headless run. The game is paused behind it. Full is the lit
## answer (Enter or Space picks the focused button; the arrows move between them).
## The answer is saved (GraphicsPrefs.choose), every save file gets it, and the
## town redraws at once. Text from time_of_day.json low_graphics.ask.

signal accepted
signal chosen(low: bool)

var _low_button: Button
var _full_button: Button
var _was_paused := false


## Show it on the first start only. Returns the overlay, or null.
static func show_if_unasked(parent: Node) -> GraphicsChoiceOverlay:
	if DisplayServer.get_name() == "headless" or not SavePrefs.ask_graphics():
		return null
	var o := GraphicsChoiceOverlay.new()
	parent.add_child(o)
	return o


func _ready() -> void:
	name = "GraphicsChoice"
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ask: Dictionary = LookEnvironment.low_cfg().get("ask", {})
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.01, 0.9)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -200
	panel.offset_bottom = 200
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.05, 0.98)
	sb.border_color = Color("#c9a35e")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		sb.set_content_margin(side, 28)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	var title := Label.new()
	title.text = str(ask.get("title", "Graphics"))
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#e0a050"))
	v.add_child(title)
	var body := Label.new()
	body.text = str(ask.get("text", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(700, 0)
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", Color(0.95, 0.92, 0.86))
	v.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	_low_button = _button(str(ask.get("low", "Low graphics")), true)
	_full_button = _button(str(ask.get("full", "Full graphics")), false)
	row.add_child(_low_button)
	row.add_child(_full_button)
	_was_paused = get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_full_button.grab_focus()


func _button(text: String, low: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(200, 48)
	b.pressed.connect(choose.bind(low))
	return b


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		choose(_low_button != null and _low_button.has_focus())


## The answer: saved on this machine and in every save file, then the next
## question (or the game).
func choose(low: bool) -> void:
	if not is_inside_tree():
		return
	GraphicsPrefs.choose(low)
	SavePrefs.write_saves()
	chosen.emit(low)
	get_tree().paused = _was_paused
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	accepted.emit()
	queue_free()
