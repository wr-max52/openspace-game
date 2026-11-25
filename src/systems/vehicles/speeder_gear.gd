class_name SpeederGear
extends RefCounted
## Issue #616: a speeder's race gear: seekers, mines and a deflector (nitro is
## only numbers, boost_time and boost_recharge, through SpeederUpgrades.apply).
## Each is an ordinary part in content/core/vehicles/speeder_upgrades.json with a
## "gear" block; this reads the parts fitted (the speeder config's "parts") and
## keeps what is left. SpeederNode owns one; the player's keys or a racer's race
## (RaceCrew) ask it to fire.
##
##   seekers    a small homing missile, the ship missile's bolt scaled down: a few
##              a load, locking on to the speeder nearest the nose inside the cone
##              (none: it flies straight). Heavy damage; a hard turn or a jump can
##              shake it, and a deflector stops one.
##   mines      dropped behind; arms after a moment, bursts when a speeder rides
##              over it (Blast, the grenade's). Capped in the world (SpeederMine).
##   deflector  soaks the next hit (bolt, seeker, mine), then recharges.
##
## Counts come back one at a time every refill_s (data), and all at once when a
## race starts (refill()).

var seekers := 0
var mines := 0
var seekers_max := 0
var mines_max := 0
var deflector := false               ## fitted
var deflector_up := false
var seeker_cfg: Dictionary = {}
var mine_cfg: Dictionary = {}
var deflector_cfg: Dictionary = {}
var fired := 0                        ## seekers fired (tests, traces)
var dropped := 0
var soaked := 0                       ## hits the deflector took

var _seek_refill := 0.0
var _mine_refill := 0.0
var _deflect_left := 0.0
var _seek_cool := 0.0
var _grace := 0.0                     ## the deflector just took a hit: the rest of that impact (its splash) too
var _mine_cool := 0.0


func _init(speeder_cfg: Dictionary = {}) -> void:
	for id in speeder_cfg.get("parts", []):
		var g: Dictionary = SpeederUpgrades.part(str(id)).get("gear", {})
		match str(g.get("kind", "")):
			"seekers":
				seeker_cfg = g
				seekers_max = int(g.get("load", 4))
			"mines":
				mine_cfg = g
				mines_max = int(g.get("load", 3))
			"deflector":
				deflector_cfg = g
				deflector = true
	refill()


func has_any() -> bool:
	return seekers_max > 0 or mines_max > 0 or deflector


## Everything back: a full load and the deflector up.
func refill() -> void:
	seekers = seekers_max
	mines = mines_max
	deflector_up = deflector
	_deflect_left = 0.0


func step(dt: float) -> void:
	_seek_cool = maxf(0.0, _seek_cool - dt)
	_mine_cool = maxf(0.0, _mine_cool - dt)
	if seekers < seekers_max:
		_seek_refill += dt
		if _seek_refill >= float(seeker_cfg.get("refill_s", 30.0)):
			_seek_refill = 0.0
			seekers += 1
	if mines < mines_max:
		_mine_refill += dt
		if _mine_refill >= float(mine_cfg.get("refill_s", 30.0)):
			_mine_refill = 0.0
			mines += 1
	_grace = maxf(0.0, _grace - dt)
	if deflector and not deflector_up:
		_deflect_left -= dt
		if _deflect_left <= 0.0:
			deflector_up = true


## A hit is coming: true if the deflector took it (and is down now).
func absorb() -> bool:
	if _grace > 0.0:
		return true                       # the same impact's splash
	if not deflector_up:
		return false
	deflector_up = false
	_grace = float(deflector_cfg.get("grace_s", 0.3))
	_deflect_left = float(deflector_cfg.get("recharge_s", 12.0))
	soaked += 1
	return true


func can_seek() -> bool:
	return seekers > 0 and _seek_cool <= 0.0


func can_mine() -> bool:
	return mines > 0 and _mine_cool <= 0.0


## The hull of the speeder nearest `from`'s nose inside the lock cone and range,
## or null.
func pick_target(from: SpeederNode) -> Node3D:
	if from == null or not from.is_inside_tree():
		return null
	var cone := deg_to_rad(float(seeker_cfg.get("lock_cone_deg", 25.0)))
	var reach := float(seeker_cfg.get("lock_range", 160.0))
	var best: Node3D = null
	var best_d := INF
	for n in from.get_tree().get_nodes_in_group(SpeederNode.GROUP):
		var s := n as SpeederNode
		if s == null or s == from or not is_instance_valid(s) or not s.model.alive() or s.hull == null:
			continue
		var to: Vector3 = s.model.position - from.model.position
		var d := to.length()
		if d > reach or d < 2.0 or from.model.forward().angle_to(to) > cone:
			continue
		if d < best_d:
			best_d = d
			best = s.hull
	return best


## Fire one seeker off `from`'s nose, homing on `target` (a hull, or null:
## straight). False if none is left or it is between shots.
func fire_seeker(from: SpeederNode, target: Node3D = null) -> bool:
	if not can_seek() or from == null or not from.is_inside_tree():
		return false
	seekers -= 1
	_seek_cool = float(seeker_cfg.get("rate", 0.6))
	var speed := float(seeker_cfg.get("speed", 95.0))
	var b := from.model.transform().basis
	var origin: Vector3 = from.model.position + b * Vector3(0.0, 0.4, -3.2)
	var shot := { "velocity": from.model.forward() * (speed + maxf(from.model.speed, 0.0)),
		"damage": float(seeker_cfg.get("damage", 70.0)), "personnel_damage": float(seeker_cfg.get("personnel_damage", 120.0)),
		"range": float(seeker_cfg.get("range", 400.0)), "weapon_id": "" }
	var content = from.demo._content() if from.demo != null and from.demo.has_method("_content") else _empty_content()
	var bolt := ShipPilot.ship_bolt(shot, from.hull, content, from.model.ground, Color(str(seeker_cfg.get("color", "#ffd28a"))))
	bolt.streak_length = float(seeker_cfg.get("length", 1.1))
	bolt.streak_radius = float(seeker_cfg.get("width", 0.22)) * 0.5
	bolt.seek = target
	bolt.turn_rate = float(seeker_cfg.get("turn_rate", 2.2))
	bolt.blast_size = float(seeker_cfg.get("blast_size", 0.5))
	bolt.splash_radius = float(seeker_cfg.get("splash_radius", 4.0))
	bolt.splash_damage = float(seeker_cfg.get("splash_damage", 30.0))
	var host: Node = from.demo if from.demo is Node3D else from.get_parent()
	host.add_child(bolt)
	bolt.global_position = origin
	fired += 1
	Sound.play("ship_missile", origin)
	return true


## Drop a mine behind `from`. False if none is left.
func drop_mine(from: SpeederNode) -> bool:
	if not can_mine() or from == null or not from.is_inside_tree():
		return false
	mines -= 1
	_mine_cool = float(mine_cfg.get("rate", 0.8))
	var at: Vector3 = from.model.position - from.model.forward() * float(from.cfg.get("look", {}).get("length", 5.0))
	if from.model.ground != null:
		at = from.model.ground.surface_below(at + from.model.up() * 3.0)
	var m := SpeederMine.new()
	m.setup(mine_cfg, from)
	var host: Node = from.demo if from.demo is Node3D else from.get_parent()
	host.add_child(m)
	m.global_position = at
	dropped += 1
	return true


## The speeder HUD's lines for what is fitted.
func hud_text() -> String:
	var out := ""
	if seekers_max > 0:
		out += "\nSEEKERS %d/%d [RMB]" % [seekers, seekers_max]
	if mines_max > 0:
		out += "\nMINES   %d/%d [G]" % [mines, mines_max]
	if deflector:
		out += "\nDEFLECT %s" % ("UP" if deflector_up else "%.0fs" % maxf(_deflect_left, 0.0))
	return out


static func _empty_content():
	return { "weapons": {} }
