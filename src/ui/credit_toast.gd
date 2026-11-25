class_name CreditToast
extends Control
## The credit toast: whenever money changes hands, a line under the banner's
## credits, top right, reads "+120 credits" in green or "-40 credits" in red,
## holds a few seconds and fades. Several in a row stack as a list, newest on
## top, each fading on its own clock.
##
## It watches WorldState.credits rather than being told: credits change in
## dozens of places (shops, jobs, bounties, races, the fence, the cantina tab),
## so every one of them shows with nothing to wire. Two changes in the same
## frame are one line, their sum. The last balance it saw is static, so money
## that moved during a scene change (a payout on arrival) shows on the next
## scene's HUD. A reset or a load is not news (WorldState.loads), nor is the
## F11 credits cheat (settle()).
##
## Timings and sizes: content/look/ui.json "credit_toast". It only reads, and
## never takes the mouse. Lives on RetroHud.

const LOOK_KEY := "credit_toast"
const TOP := 46.0                      ## just under RetroHud's 40 px banner
const RIGHT := 18.0                    ## the banner's own right margin: lines up under "CR ..."

static var _seen := -1                 ## the balance last seen, -1 = none yet
static var _seen_loads := -1           ## WorldState.loads when it was seen

var list: VBoxContainer
var rows: Array = []                   ## [Row], newest first
var _in := 0.15
var _hold := 3.0
var _out := 0.6
var _max := 6
var _font := 20


func _init() -> void:
	name = "CreditToast"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var cfg: Dictionary = RetroUI.ui().get(LOOK_KEY, {})
	_in = float(cfg.get("in", _in))
	_hold = float(cfg.get("hold", _hold))
	_out = float(cfg.get("out", _out))
	_max = int(cfg.get("max_rows", _max))
	_font = int(cfg.get("font_size", _font))
	list = VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 0)
	add_child(list)
	watch()                            # a fresh HUD takes the balance as it is


## Take the current balance as seen, with no line: the F11 credits cheat.
static func settle() -> void:
	_seen = WorldState.credits
	_seen_loads = WorldState.loads


func _process(dt: float) -> void:
	watch()
	for i in range(rows.size() - 1, -1, -1):
		var r: Row = rows[i]
		r.tick(dt)
		if r.done():
			rows.remove_at(i)
			list.remove_child(r)
			r.queue_free()
	_place()


## Compare the balance with the last one seen; a change goes up as a line.
func watch() -> void:
	if _seen < 0 or _seen_loads != WorldState.loads:
		settle()
		return
	var now := WorldState.credits
	if now != _seen:
		var delta := now - _seen
		_seen = now
		show_change(delta)


## Put a change of `delta` credits up now, on top of the list.
func show_change(delta: int) -> void:
	if delta == 0:
		return
	var r := Row.new(delta, _font, _in, _hold, _out)
	rows.push_front(r)
	list.add_child(r)
	list.move_child(r, 0)
	while rows.size() > _max:          # the oldest drops off the bottom
		var old: Row = rows.pop_back()
		list.remove_child(old)
		old.queue_free()


func _place() -> void:
	var view := get_viewport_rect().size
	list.reset_size()
	var sz := list.get_combined_minimum_size()
	list.size = sz
	list.position = Vector2(view.x - sz.x - RIGHT, TOP)


## One change: "+120 credits", green for in, red for out, fading on its own.
class Row extends Label:
	var delta: int
	var _in: float
	var _hold: float
	var _out: float
	var _t := 0.0                      ## seconds since it came up

	func _init(d: int, font_size: int, t_in: float, t_hold: float, t_out: float) -> void:
		delta = d
		_in = t_in
		_hold = t_hold
		_out = t_out
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		text = "%+d credits" % d
		add_theme_font_size_override("font_size", font_size)
		add_theme_color_override("font_color", StandingToast.GREEN if d > 0 else StandingToast.RED)
		add_theme_color_override("font_outline_color", Color.BLACK)
		add_theme_constant_override("outline_size", 5)
		modulate.a = 0.0

	func tick(dt: float) -> void:
		_t += dt
		var a := 1.0
		if _t < _in:
			a = _t / maxf(0.001, _in)
		elif _t > _in + _hold:
			a = 1.0 - (_t - _in - _hold) / maxf(0.001, _out)
		modulate.a = clampf(a, 0.0, 1.0)

	func done() -> bool:
		return _t >= _in + _hold + _out
