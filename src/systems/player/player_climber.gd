extends Node
## Ladders on foot: what gets you onto one, and what is shown while you are on it.
## The climb itself is the body's (CharacterBody.climb_on, LadderClimb); the
## ladders are Ladders' registry (src/systems/world/ladders.gd), so the near ones
## are a lookup, not a tree scan.
##   at a foot   walking into it holding W gets you on ("[W] Climb the ladder" while
##               you stand there)
##   at a top    "[E] Climb down the ladder": E swings you round onto it (unless E
##               is someone else's here: a gear pickup, a weld)
##   on it       the keys on the gear HUD; the weapon in hand goes away (both hands
##               on the rungs) and comes back out when you are off
## Riding, flying or downed, it does nothing. Words: content/core/flow/ladders.json.

const Ladders := preload("res://src/systems/world/ladders.gd")
const LadderClimb := preload("res://src/systems/player/ladder_climb.gd")

var demo                            ## the town scene
var mounts := 0                     ## times you got on a ladder (tests, traces)
var _words: Dictionary = {}
var _prompt_was := ""
var _back_to := "?"                 ## the weapon in hand as you got on ("?" = none put away)
var _was_on := false


func setup(p_demo) -> void:
	demo = p_demo
	name = "PlayerClimber"


func _player() -> CharacterBody3D:
	return demo.get("_player") if demo != null else null


func _weapons() -> PlayerWeapons:
	var kit = demo.get("player_kit") if demo != null else null
	return kit.weapons if kit != null and is_instance_valid(kit) else null


func _hud():
	var g = demo.get("gear") if demo != null else null
	return g.hud if g != null and is_instance_valid(g) else null


func line(key: String) -> String:
	if _words.is_empty():
		var f := FileAccess.open(LadderClimb.PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_words = (d as Dictionary).get("words", {}) if d is Dictionary else {}
	return str(_words.get(key, key))


func _physics_process(dt: float) -> void:
	tick(dt)


## One tick. Returns "mount" the tick it put you on a ladder, else "".
func tick(_dt: float) -> String:
	var p := _player()
	if p == null or not is_instance_valid(p) or not p.is_inside_tree() or p.get("climb") == null:
		_prompt("")
		return ""
	var on: bool = p.get("climbing") == true
	if on != _was_on:
		_hands(on)
		_was_on = on
	if on:
		_sounds(p.get("climb"))
		_prompt(line("on_ladder"))
		return ""
	if p.get("piloting") == true or p.get("is_downed") == true or p.get("locked") == true:
		_prompt("")
		return ""
	var pos := p.global_position
	var near := Ladders.near(pos, 2.5)
	if near.is_empty():
		_prompt("")
		return ""
	var foot := {}
	var top := {}
	for w in near:
		if foot.is_empty() and Ladders.at_foot(w, pos):
			foot = w
		if top.is_empty() and Ladders.at_top(w, pos):
			top = w
	if not foot.is_empty():
		if p.is_on_floor() and walking_into(p, foot) and p.climb_on(foot, false):
			mounts += 1
			_prompt(line("on_ladder"))
			return "mount"
		_prompt(line("at_foot"))
		return ""
	if not top.is_empty() and not _e_taken():
		_prompt(line("at_top"))
		if InputMap.has_action("interact") and Input.is_action_just_pressed("interact") and p.is_on_floor() \
				and p.climb_on(top, true, _facing(p)):
			mounts += 1
			return "mount"
		return ""
	_prompt("")
	return ""


## The move keys push you into ladder `w` (Ladders.world_of): W held and the way
## you walk heads at its rungs.
static func walking_into(p: CharacterBody3D, w: Dictionary) -> bool:
	var ctl = p.get("controller")
	if ctl == null:
		return false
	var dir: Vector2 = ctl.command.dir
	if dir.y < 0.5:
		return false
	var yaw := -p.rotation.y
	var local := Vector3(dir.x * cos(yaw) - dir.y * sin(yaw), 0.0, dir.x * sin(yaw) + dir.y * cos(yaw))
	var t = p.get("tilt")
	var world: Vector3 = (t as Basis) * local if t is Basis else local
	return world.normalized().dot(w.fwd) > 0.55


## The way the body faces now (the avatar's, else the way it walks).
func _facing(p: CharacterBody3D) -> Vector3:
	var kit = demo.get("player_kit") if demo != null else null
	if kit != null and is_instance_valid(kit) and kit.avatar != null:
		return (kit.avatar as Node3D).global_basis.z
	return -p.global_basis.z


## E belongs to someone else here (a gear pickup or a weld in front of you).
func _e_taken() -> bool:
	if Welder.claims_e:
		return true
	var g = demo.get("gear") if demo != null else null
	return g != null and is_instance_valid(g) and g.get("focus") is Dictionary and not (g.focus as Dictionary).is_empty()


## Both hands on the rungs: the weapon in hand goes back in its holster (and the
## trigger, the aim and the wheel are off); off the ladder it comes back out.
func _hands(on: bool) -> void:
	var w := _weapons()
	if w == null:
		return
	if on:
		_back_to = w.holder.current
		if _back_to != "":
			w.holder.request("")
		w.set_enabled(false)
	else:
		w.set_enabled(true)
		if _back_to != "?" and _back_to != "":
			w.holder.request(_back_to)
		_back_to = "?"


func _sounds(cl) -> void:
	if cl == null:
		return
	for ev in cl.events:
		if str(ev) == "slide":
			Sound.play("slide_scuff")


## The gear HUD's prompt is set every tick by GearController (often to nothing), so
## a prompt of ours is set every tick too, after it (town_demo adds this node after
## the gear and the welder); ours gone, it is cleared once.
func _prompt(text: String) -> void:
	var hud = _hud()
	if hud == null:
		return
	if text != "":
		hud.set_prompt(text)
	elif _prompt_was != "":
		hud.set_prompt("")
	_prompt_was = text
