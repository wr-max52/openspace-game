class_name WarpDrive
extends Node
## Issue #874: the warp drive, T-89's 10,000 cr upgrade (t89.json "warp", an
## "unlock" upgrade: ShipUpgrades.unlocked). How you leave a star system.
##
## Only in open space (no planet's bubble round you), seated and flying: hold the
## warp key (flight_warp, K) for space.warp.hold_s and the picker opens with every
## other system (types.json space.systems). Pick one and the warp runs on its own,
## no key held: the boosters' flames lengthen, the sky's stars rush out from dead
## ahead and the camera's field of view kicks wide (render rule 13: nothing new
## is drawn, only what is already there, pushed). It lasts at least min_s and for
## as long as the next system's main planet takes to get ready (PlanetGen.build,
## its models started on workers), then a short flash and you are in that
## system's open space (GameFlow.travel with a handoff), outside its main planet's
## bubble on the side facing its sun, nose on the planet.
##
## Anywhere else the key does nothing but say why. Child of the ShipPilot.

enum Phase { IDLE, HOLDING, PICKING, WARPING, LEAVING, ARRIVING }

var pilot = null                     ## the ShipPilot
var phase := Phase.IDLE
var held := 0.0                      ## seconds the key has been held
var target := ""                     ## the system the warp is taking you to
var elapsed := 0.0                   ## seconds into the warp
var level := 0.0                     ## 0..1, how far the warp has spun up (the look)
var change := true                   ## false: decide but do not change scene (tests)
var last_travel: Dictionary = {}     ## what the last warp carried (tests, with change = false)
var _ready_for := ""                 ## the system whose main planet is built
var _said := false                   ## the "why not" line, once per press
var _layer: CanvasLayer
var _panel: PanelContainer
var _rows: VBoxContainer


static func cfg() -> Dictionary:
	return PlanetGen.space_cfg().get("warp", {})


static func setting(key: String, fallback: float) -> float:
	return float(cfg().get(key, fallback))


func _ready() -> void:
	name = "WarpDrive"


## Why the drive will not spin up here, "" when it will.
func blocked_reason() -> String:
	if pilot == null:
		return "warp_not_here"
	if not ShipUpgrades.unlocked(str(pilot.ship_id), "warp"):
		return "warp_no_drive"
	if pilot.travel == null or not pilot.travel.open:
		return "warp_not_here"
	if pilot.fight != null:
		return "warp_in_fight"
	return ""


## The systems you can warp to from here: every system but the one you are in.
static func destinations() -> Array:
	var here := PlanetGen.current_system()
	var out: Array = []
	for sys in PlanetGen.system_ids():
		if str(sys) != here and PlanetGen.main_planet(str(sys)) != "":
			out.append(str(sys))
	return out


func busy() -> bool:
	return phase in [Phase.WARPING, Phase.LEAVING]


func _physics_process(dt: float) -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	match phase:
		Phase.WARPING, Phase.LEAVING:
			_warp_step(dt)
			return
		Phase.ARRIVING:
			_settle_step(dt)
			return
		Phase.PICKING:
			if not _flying():
				close_picker()
			return
	var down := _flying() and InputMap.has_action("flight_warp") and Input.is_action_pressed("flight_warp")
	if not down:
		held = 0.0
		_said = false
		phase = Phase.IDLE
		return
	press(dt)


func _flying() -> bool:
	return bool(pilot.piloting) and pilot.atmo != null and pilot.atmo.state == AtmoFlight.State.FLYING


## The key held for `dt` more seconds (the keyboard, or a test).
func press(dt: float) -> void:
	var why := blocked_reason()
	if why != "":
		if not _said:
			pilot.hud.toast(GameFlow.label(why), 3.0)
			_said = true
		return
	if held == 0.0:
		pilot.hud.toast(GameFlow.label("warp_hold"), setting("hold_s", 1.0) + 0.2)
	phase = Phase.HOLDING
	held += dt
	if held >= setting("hold_s", 1.0):
		open_picker()


func open_picker() -> void:
	phase = Phase.PICKING
	held = 0.0
	if not pilot.is_inside_tree():
		return
	if _layer == null:
		_build_picker()
	for c in _rows.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = GameFlow.label("warp_pick_title")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#9fe8ff"))
	_rows.add_child(title)
	var dests := destinations()
	if dests.is_empty():
		var none := Label.new()
		none.text = GameFlow.label("warp_pick_none")
		_rows.add_child(none)
	for i in dests.size():
		var sys := str(dests[i])
		var b := Button.new()
		b.text = "  %d   ●  %s" % [i + 1, PlanetGen.system_label(sys)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var star := Color(str(PlanetGen.systems().get(sys, {}).get("star", {}).get("color", "#ffffff")))
		b.add_theme_color_override("font_color", star)
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(func(): pick(sys))
		_rows.add_child(b)
		if i == 0:
			b.grab_focus.call_deferred()
	var hint := Label.new()
	hint.text = GameFlow.label("warp_pick_hint")
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_rows.add_child(hint)
	_layer.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_picker() -> void:
	if phase == Phase.PICKING:
		phase = Phase.IDLE
	if _layer != null:
		_layer.visible = false
	if pilot != null and bool(pilot.piloting):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.PICKING or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var dests := destinations()
	var k: int = (event as InputEventKey).keycode
	if k == KEY_ESCAPE:
		close_picker()
		get_viewport().set_input_as_handled()
	elif k in [KEY_ENTER, KEY_KP_ENTER] and not dests.is_empty():
		pick(str(dests[0]))
		get_viewport().set_input_as_handled()
	elif k >= KEY_1 and k <= KEY_9 and k - KEY_1 < dests.size():
		pick(str(dests[k - KEY_1]))
		get_viewport().set_input_as_handled()


## Start the warp to system `sys` (from the picker, or a test).
func pick(sys: String) -> bool:
	if blocked_reason() != "" or not PlanetGen.systems().has(sys) or sys == PlanetGen.current_system():
		return false
	close_picker()
	target = sys
	elapsed = 0.0
	level = 0.0
	_ready_for = ""
	phase = Phase.WARPING
	pilot.hud.toast(GameFlow.label("warp_going") % PlanetGen.system_label(sys), 3.0)
	if pilot.travel != null:
		pilot.travel.traveling = "warp:" + sys      # no planet's bubble takes over mid-warp
	_get_ready.call_deferred(sys)
	return true


## The next system's main planet built and its models loading (once per warp):
## what its open space will draw first.
func _get_ready(sys: String) -> void:
	var main := PlanetGen.main_planet(sys)
	if main != "":
		var planet := PlanetGen.build(main)
		PlanetGen.reserve_names(planet)
		if pilot != null and is_instance_valid(pilot) and bool(pilot.demo.get("use_look")):
			ModelCache.prefetch_planet(main)
	_ready_for = sys


func _warp_step(dt: float) -> void:
	elapsed += dt
	var min_s := setting("min_s", 5.0)
	var fade_s := setting("fade_s", 0.35)
	# Spin up over the first 60% of the warp, held at full until the drop.
	level = clampf(elapsed / maxf(min_s * 0.6, 0.01), 0.0, 1.0)
	var e := level * level * (3.0 - 2.0 * level)
	pilot.fov_kick = setting("fov_kick", 38.0) * e
	pilot.flame_stretch = 1.0 + (setting("flame_stretch", 2.6) - 1.0) * e
	pilot._throttle = 1.0
	if pilot.sky != null:
		_rush(e)
	var ready := _ready_for == target
	var left := min_s - elapsed
	if left <= fade_s and pilot.hud != null:
		pilot.hud.set_fade(clampf(1.0 - left / maxf(fade_s, 0.01), 0.0, 1.0))
	if phase == Phase.WARPING and elapsed >= min_s and ready:
		phase = Phase.LEAVING
		_leave()


## Into the target system's open space, outside its main planet's bubble.
func _leave() -> void:
	var sys := target
	var hand := arrival(sys)
	var extra := { "handoff": hand, "warp": sys }
	last_travel = { "to": PlanetGen.open_space_id(), "system": sys, "extra": extra }
	if not change:
		return
	WorldState.system = sys
	GameFlow.flown_key = pilot.berth_key()
	GameFlow.travel(get_tree() if is_inside_tree() else null, PlanetGen.open_space_id(), pilot.ship_id, "", extra)


## Where a warp into system `sys` drops you, in its open space's frame: outside
## the main planet's bubble by arrive_m, on the side facing the sun, nose on it.
static func arrival(sys: String) -> Dictionary:
	var main := PlanetGen.main_planet(sys)
	var s: Dictionary = PlanetGen.systems().get(sys, {})
	var sun := PlanetGen.system_sun(null, sys)
	var origin := sun if sun.is_finite() else Vector3.ZERO     # open space's origin is its sun
	var centre = PlanetGen.system_centre(main)
	if centre == null:
		centre = origin + Vector3(0, 0, 30000)
	var c: Vector3 = centre - origin
	var to_sun: Vector3 = sun - origin - c
	var out_dir := to_sun.normalized() if to_sun.length() > 1.0 else Vector3.BACK
	var dist := PlanetGen.bubble_radius(main, true) + float(s.get("arrive_m", 6000.0))
	if dist <= 0.0:
		dist = PlanetGen.ball_radius({ "type": "sand" }) + float(s.get("arrive_m", 6000.0))
	var at := c + out_dir * dist
	var up := Vector3.UP if absf(out_dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	# Nose on the planet, a little off its middle: in over its shoulder, never
	# straight down at it (its "up" out here points away from it).
	var side := out_dir.cross(up).normalized()
	var cc = PlanetGen._content()
	var aim := c + side * PlanetGen.ball_radius(cc.planets.get(main, {}), cc) * 0.5
	return { "position": at, "basis": Basis.looking_at((aim - at).normalized(), out_dir),
		"speed": setting("speed_after", 300.0), "throttle": 0.6 }


## Issue #874: just out of a warp into system `sys` (this scene's first frame):
## the flash fades, the stars and the field of view settle, and a line names the
## system and its main planet ahead.
func arrived(sys: String) -> void:
	phase = Phase.ARRIVING
	target = sys
	elapsed = 0.0
	level = 1.0
	pilot.fov_kick = setting("fov_kick", 38.0)
	pilot.hud.set_fade(1.0)
	var main := PlanetGen.main_planet(sys)
	var pname := PlanetGen.display_name(PlanetGen.build(main)) if main != "" else ""
	pilot.hud.toast(GameFlow.label("warp_arrived") % [PlanetGen.system_label(sys), pname], 4.0)


## The stars stream past in waves: each wave pulls the field out from the nose
## and fades it, then the next starts (space.warp.rush_s a wave), `e` how hard.
func _rush(e: float) -> void:
	var wave := fposmod(elapsed / maxf(setting("rush_s", 0.45), 0.05), 1.0)
	var pull := e * setting("star_stretch", 5.0) * wave
	pilot.sky.warp_stretch(pull, -pilot.atmo.flight.basis.z, 1.0 + e * setting("star_swell", 2.5) * wave,
		e * sin(PI * wave))


func _settle_step(dt: float) -> void:
	elapsed += dt
	var settle := maxf(setting("settle_s", 1.2), 0.05)
	level = clampf(1.0 - elapsed / settle, 0.0, 1.0)
	var e := level * level * (3.0 - 2.0 * level)
	pilot.fov_kick = setting("fov_kick", 38.0) * e
	pilot.flame_stretch = 1.0 + (setting("flame_stretch", 2.6) - 1.0) * e
	if pilot.sky != null:
		_rush(e)
	pilot.hud.set_fade(clampf(1.0 - elapsed / maxf(setting("fade_s", 0.35), 0.01), 0.0, 1.0))
	if level <= 0.0:
		phase = Phase.IDLE
		pilot.fov_kick = 0.0
		pilot.flame_stretch = 1.0
		pilot.hud.set_fade(0.0)


func _exit_tree() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()


func _build_picker() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6
	_layer.name = "WarpPicker"
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.35
	_panel.anchor_bottom = 0.35
	_panel.offset_left = -190
	_panel.offset_right = 190
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.08, 0.85)
	sb.border_color = Color("#9fe8ff")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	_panel.add_child(_rows)
	_layer.add_child(_panel)
	add_child(_layer)
