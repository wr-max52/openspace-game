class_name NpcLauncher
extends RefCounted
## A guard's seeker launcher against the ship or speeder you ride (a soldier
## profile with a "launcher" block; numbers in content/core/weapons/npc_seeker.json
## "vehicle"). On foot the launcher is just the guard's gun (NpcBody's weapon,
## slow unguided seekers); this is the other half.
##
## While the guard's side counts your vehicle hostile (NpcBody.hostile_vehicle, and
## either the Remnant garrison and a ship off the ground in town, or a guard who
## is already fighting you: anything you ride near an outpost)
## and it is within lock_range and in sight, the tube comes up and turns to it
## (`aim`; NpcBody faces and aims there instead of where its brain says) and
## MissileLock, the ship seekers' lock, builds over lock_time. Locked, and the
## tube up, one seeker goes at its hull (every `rate` s at most), then the lock
## starts over. Out of sight or range the lock bleeds off.
##
## threat_on(hull): a guard's lock or seeker on that hull now. ShipPilot sounds
## the cockpit's seeker warning on it (a speeder has no warning).

const MissileLock := preload("res://src/systems/flight/missile_lock.gd")
const BoltScene := preload("res://scenes/entities/bolt.tscn")
const GROUP := "npc_launchers"       ## NpcBody nodes that carry one

var body: Node3D                     ## the NpcBody
var cfg: Dictionary = {}             ## npc_seeker.json "vehicle"
var lock = MissileLock.new()
var aim := Vector3.INF               ## where the tube points while engaged; INF: the brain's aim
var hull: Node3D = null              ## what it is on (the vehicle's hull)
var fired := 0
var _cool := 0.0
var _look_left := 0.0
var _in_sight := false
var _seekers: Array = []             ## its seekers still flying


func _init(b: Node3D, c: Dictionary) -> void:
	body = b
	cfg = c
	lock.configure(c)


func engaged() -> bool:
	return aim != Vector3.INF


func locked_on(h: Node) -> bool:
	return h != null and hull == h and lock.is_locked()


## One physics frame.
func tick(dt: float) -> void:
	_cool = maxf(0.0, _cool - dt)
	var v: Node = body.hostile_vehicle() if body.has_method("hostile_vehicle") else null
	if v != null and not bool(body.get("hostile")):
		# Not fighting you yet: only the Remnant garrison opens up on a ship off the
		# ground in town (the troopers' rule); out of town, only once they fight you.
		var town_threat: bool = v.has_method("hostile_in_town") and v.hostile_in_town() \
			and str(body.get("faction")) == "imperial_remnant"
		if not town_threat:
			v = null
	if v != null and v.get("opening") == true:
		v = null                         # the free opening's landing is not a fight
	var h: Node3D = v.hull_body() as Node3D if v != null and v.has_method("hull_body") else null
	if h == null or not is_instance_valid(h) or not h.is_inside_tree() or h.get("dead") == true:
		_drop()
		return
	var eye: Vector3 = body.eye_position()
	var to := h.global_position - eye
	if to.length() > float(cfg.get("lock_range", 320.0)):
		_drop()
		return
	if h != hull:
		hull = h
		_look_left = 0.0
	_look_left -= dt
	if _look_left <= 0.0:
		_look_left = float(cfg.get("look_s", 0.25))
		_in_sight = body.sight_clear(h.global_position, h)
	aim = h.global_position
	if not _in_sight:
		lock.update(dt, h.get_instance_id(), Vector3.FORWARD, Vector3(0, 0, 1e9))    # out of range: bleeds off
		return
	lock.update(dt, h.get_instance_id(), to, to)
	var up: bool = body.carry.on_target() if body.get("carry") != null else true
	if lock.is_locked() and _cool <= 0.0 and up:
		fire(h)


func _drop() -> void:
	aim = Vector3.INF
	hull = null
	lock.reset()


## One seeker at `h` from the tube.
func fire(h: Node3D) -> Node:
	var host: Node = body.get_parent()
	if host == null:
		return null
	var origin: Vector3 = body.muzzle_position()
	var dir := (h.global_position - origin).normalized()
	var b = BoltScene.instantiate()
	b.direction = dir
	b.speed = float(cfg.get("bolt_speed", 60.0))
	b.damage = float(cfg.get("damage", 35.0))
	b.soft_damage = float(cfg.get("personnel_damage", 70.0))
	b.range_m = float(cfg.get("range", 500.0))
	b.shooter = body
	b.stylize = true
	b.sweep = true
	b.color = Color.html(str(cfg.get("color", "#ffd28a")))
	b.streak_length = float(cfg.get("length", 1.0))
	b.streak_radius = float(cfg.get("width", 0.2)) * 0.5
	b.seek = h
	b.turn_rate = float(cfg.get("turn_rate", 3.0))
	b.proximity = float(cfg.get("proximity", 4.0))
	b.blast_size = float(cfg.get("blast_size", 0.6))
	b.splash_radius = float(cfg.get("splash_radius", 6.0))
	b.splash_damage = float(cfg.get("splash_damage", 20.0))
	var sphere := PlanetSphere.current
	if sphere != null:
		b.over_ground = func(p: Vector3) -> float: return sphere.height_above_ground(p)
		b.ground_up = func(p: Vector3) -> Vector3: return sphere.up_at(p)
	host.add_child(b)
	b.global_position = origin
	_seekers.append(b)
	fired += 1
	_cool = float(cfg.get("rate", 6.0))
	lock.reset()                     # each seeker locks afresh, as the AI pilots' do
	Sound.play("ship_missile", origin)
	return b


## Its seekers still in the air turning after `h`.
func seekers_on(h: Node) -> int:
	_seekers = _seekers.filter(func(b): return is_instance_valid(b) and b.is_inside_tree())
	var n := 0
	for b in _seekers:
		if b.seek == h:
			n += 1
	return n


## A guard's lock or seeker on `h` now (the cockpit's seeker warning).
static func threat_on(h: Node, tree: SceneTree) -> bool:
	if h == null or tree == null:
		return false
	for n in tree.get_nodes_in_group(GROUP):
		var l = n.get("launcher")
		if l == null:
			continue
		if l.seekers_on(h) > 0 or (n.get("dead") != true and l.locked_on(h)):
			return true
	return false
