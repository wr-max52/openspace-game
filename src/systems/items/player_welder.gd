class_name PlayerWelder
extends Node
## Issue #722: welding on foot. Each tick it finds the nearest WeldSpot in reach
## that wants welding (WeldSpot.all: no tree scan) and says so on the gear HUD:
##   no welder:  "You need a plasma welder to fix <it>"
##   blocked:    the spot's reason ("needs 10 flasks of refined quantonium")
##   else:       "[Hold E] Weld <it>", or for a spot whose E is taken (a parked
##               speeder: E mounts it) "[Hold fire] Weld <it>" with the welder out.
## Hold E (or fire, welder drawn) for Welder.weld_s and the spot is welded. While
## you hold it the welder is in your hand, sparks flying off its tip
## (PlayerWeapons.welding) and off the thing being welded (spark_target), and a
## bar fills; let go or walk off and it stops. When it is done the hand goes back
## to what it held before. Riding or flying, it does nothing: the speeder's seat
## has its own weld (SpeederNode), and nothing else is welded from a seat.
## Words: content/core/flow/gear.json "welder".

var demo                            ## the town scene
var focus: WeldSpot                 ## what a hold would weld now (null: nothing)
var progress := 0.0                 ## seconds held so far
var welds := 0                      ## spots welded (tests)
var _was_prompt := false
var _back_to := "?"                 ## the weapon in hand before welding ("?" = untouched)
var _wait_release := false          ## done: let go of the key before the next weld
var _words: Dictionary = {}
var _target_fx: WelderFx            ## the sparks on what is being welded (built on first use)


func setup(p_demo) -> void:
	demo = p_demo
	name = "PlayerWelder"


func _player() -> Node3D:
	return demo.get("_player") if demo != null else null


func _weapons() -> PlayerWeapons:
	var kit = demo.get("player_kit") if demo != null else null
	return kit.weapons if kit != null and is_instance_valid(kit) else null


func _hud():
	var g = demo.get("gear") if demo != null else null
	return g.hud if g != null and is_instance_valid(g) else null


func line(key: String) -> String:
	if _words.is_empty():
		var f := FileAccess.open("res://content/core/flow/gear.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_words = (d as Dictionary).get("welder", {}) if d is Dictionary else {}
	return str(_words.get(key, key))


func _physics_process(dt: float) -> void:
	tick(dt)


## One tick: focus, prompt, the hold. Returns "welded" the tick a weld finishes.
func tick(dt: float) -> String:
	var p := _player()
	if p == null or not is_instance_valid(p) or not p.is_inside_tree() or _seated(p):
		_drop()
		return ""
	focus = find_focus(p.global_position)
	Welder.claims_e = focus != null and focus.use_e and Welder.owned() and focus.blocked() == ""
	_prompt()
	var held := _held()
	if _wait_release:
		_wait_release = held
		held = false
	if focus == null or not held or not Welder.owned() or focus.blocked() != "":
		_stop()
		return ""
	progress += dt
	_hand(true)
	spark_target(_spark_point(p.global_position, focus), true)
	var hud = _hud()
	if hud != null:
		hud.set_progress(progress / maxf(Welder.weld_s(), 0.01))
	if progress < Welder.weld_s():
		return ""
	var what := focus.what()
	focus.weld()
	welds += 1
	_wait_release = true
	_stop()
	Sound.play("droid_fix", p.global_position)
	if hud != null:
		hud.toast(line("welded") % what)
	return "welded"


## The nearest WeldSpot in reach (flat distance, and no more than 2.5 m above or
## below) that wants welding.
func find_focus(at: Vector3) -> WeldSpot:
	var best: WeldSpot = null
	var best_d := INF
	for s in WeldSpot.all:
		var spot := s as WeldSpot
		if spot == null or not is_instance_valid(spot) or not spot.is_inside_tree() or not spot.is_visible_in_tree():
			continue
		var d3 := spot.global_position - at
		if absf(d3.y) > 2.5:
			continue
		var d := Vector2(d3.x, d3.z).length()
		if d <= spot.range_m() and d < best_d and spot.needs():
			best = spot
			best_d = d
	return best


## The hold that welds: E for a spot that takes it, or fire with the welder drawn.
func _held() -> bool:
	if focus == null:
		return false
	var w := _weapons()
	var fire: bool = w != null and w.holder.current == Welder.ITEM and w.get("_fire_held") == true
	return fire or (focus.use_e and Welder.e_held())


func prompt_text() -> String:
	if focus == null:
		return ""
	var what := focus.what()
	if not Welder.owned():
		return line("need_welder") % what
	var why := focus.blocked()
	if why != "":
		return line("blocked") % [what, why]
	if progress > 0.0:
		return line("welding") % what
	return (line("hold_e") if focus.use_e else line("hold_fire")) % [what, Welder.weld_s()]


func _prompt() -> void:
	var hud = _hud()
	if hud == null:
		return
	var text := prompt_text()
	if text != "":
		hud.set_prompt(text)
		_was_prompt = true
	elif _was_prompt:
		hud.set_prompt("")
		_was_prompt = false


## Welding: the welder comes out (and sparks); done or let go: back to what you had.
func _hand(on: bool) -> void:
	var w := _weapons()
	if w == null:
		return
	w.welding = on
	if on and _back_to == "?":
		_back_to = w.holder.current
		if w.holder.current != Welder.ITEM:
			w.holder.request(Welder.ITEM)
	elif not on and _back_to != "?":
		if _back_to != Welder.ITEM and w.holder.current == Welder.ITEM:
			w.holder.request(_back_to)
		_back_to = "?"


## Sparks on what is being welded, at `at` (world), or off. Also the heist's vault
## (RemnantOutposts) while you burn it open.
func spark_target(at: Vector3, on: bool) -> void:
	if on and _target_fx == null and demo is Node3D and (demo as Node3D).is_inside_tree():
		_target_fx = WelderFx.make(Color("#a8e4ff"), 1.4)
		(demo as Node3D).add_child(_target_fx)
	if _target_fx == null or not is_instance_valid(_target_fx):
		return
	if on:
		_target_fx.global_position = at
	if _target_fx.on != on:
		_target_fx.set_on(on)


## Where the sparks land on spot `s`: its own spark height, and no further from
## you than an arm and a welder (a ship's spot is in her middle; her skin is nearer).
static func _spark_point(from: Vector3, s: WeldSpot) -> Vector3:
	var at := s.global_position
	var flat := Vector3(at.x - from.x, 0.0, at.z - from.z)
	var d := flat.length()
	if d > 1.1:
		at = Vector3(from.x, at.y, from.z) + flat / d * 1.1
	return at + Vector3.UP * s.spark_height


func _stop() -> void:
	spark_target(Vector3.ZERO, false)
	if progress > 0.0:
		var hud = _hud()
		if hud != null:
			hud.set_progress(-1.0)
	progress = 0.0
	_hand(false)


func _drop() -> void:
	_stop()
	focus = null
	Welder.claims_e = false
	if _was_prompt:
		var hud = _hud()
		if hud != null:
			hud.set_prompt("")
		_was_prompt = false


## Riding a speeder or in a ship's seat: no welding on foot.
static func _seated(p: Node) -> bool:
	return p.get("locked") == true or not (p as Node3D).is_visible_in_tree()
