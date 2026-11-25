class_name BountyRunner
extends Node3D
## Issue #614: a bounty target who runs (WorldState.bounty "runner"; never the
## story's bounty). RemnantOutposts builds one beside the target at their outpost:
## a speeder parked by them. Numbers and words: content/core/story/main.json,
## bounty.runner.
##
##   waiting   the target stands by the speeder with the outpost's troopers.
##   flee      you come within trigger_m, or you hit them: they climb on and run
##             (SpeederBrain flee, its pace set here): full tilt for start_s, then
##             easing off to min_pace while you are more than ease_from_m behind,
##             and pushing again inside push_m. A chase you work at stays catchable.
##   caught    wreck the speeder (they are thrown clear, on foot, and fight) or
##             kill them: the bounty is theirs as ever (RemnantOutposts).
##   gone      the gap passes got_away_m: they and the speeder are removed and the
##             contract ends unpaid ("The bounty got away"; WorldState.on_bounty_got_away).

enum State { WAITING, FLEE, CAUGHT, GONE }

var demo
var ground: WorldGround
var target: NpcBody
var speeder: SpeederNode
var state := State.WAITING
var cfg: Dictionary = {}
var _t := 0.0


func setup(town_demo, world_ground: WorldGround, who: NpcBody, at: Vector3, yaw: float) -> void:
	demo = town_demo
	ground = world_ground
	target = who
	cfg = Story.bounty_cfg().get("runner", {})
	name = "BountyRunner"
	speeder = SpeederNode.new()
	speeder.setup(demo, ground, {}, true, str(cfg.get("paint", "remnant")))
	var side := Basis(Vector3.UP, yaw).x
	speeder.set_meta("bounty_runner", true)
	_spot = at + side * float(cfg.get("park_m", 4.0))
	_yaw = yaw


var _spot := Vector3.ZERO
var _yaw := 0.0


func _ready() -> void:
	add_child(speeder)
	speeder.place(_spot, _yaw)
	if target != null and is_instance_valid(target):
		target.hit_by.connect(_on_hit)


func n(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


func _player_pos() -> Vector3:
	var p = demo._player if demo != null else null
	if p == null or not is_instance_valid(p):
		return Vector3.INF
	if p.piloting and p.vehicle is SpeederNode:
		return (p.vehicle as SpeederNode).model.position
	return p.global_position


func _on_hit(_shooter: Node, _amount: float) -> void:
	if state == State.WAITING:
		run()


## They climb on and go.
func run() -> bool:
	if state != State.WAITING or target == null or not is_instance_valid(target) or target.dead:
		return false
	if speeder == null or not is_instance_valid(speeder) or not speeder.model.alive():
		return false
	var g = _garrison()
	if g != null:
		g.remove_member(target)          # off the outpost's brain while they ride
	if not speeder.seat_npc(target, "driver"):
		return false
	speeder.brain = SpeederBrain.new(speeder.model, str(cfg.get("skill", "runner")), 614)
	speeder.brain.flee()
	state = State.FLEE
	_t = 0.0
	return true


func _garrison():
	var rem = demo.get("outposts") if demo != null else null
	if rem == null:
		return null
	return rem.garrisons.get(str(target.get_meta("outpost", "")), demo.get("garrison"))


func _physics_process(dt: float) -> void:
	tick(dt)


func tick(dt: float) -> void:
	if state == State.GONE or state == State.CAUGHT:
		return
	if target == null or not is_instance_valid(target) or target.dead:
		state = State.CAUGHT
		return
	var you := _player_pos()
	if you == Vector3.INF:
		return
	match state:
		State.WAITING:
			if target.global_position.distance_to(you) <= n("trigger_m", 60.0):
				run()
		State.FLEE:
			if speeder == null or not is_instance_valid(speeder) or not speeder.npc_driven():
				state = State.CAUGHT         # wrecked: thrown clear, on foot
				return
			_t += dt
			var gap := speeder.model.position.distance_to(you)
			speeder.brain.target_pos = you
			speeder.brain.pace = pace_for(gap, _t)
			if gap > n("got_away_m", 500.0):
				_got_away()


## Full tilt at first; eased off while you are far behind; pushing when you close.
func pace_for(gap: float, t: float) -> float:
	if t < n("start_s", 6.0) or gap < n("push_m", 90.0):
		return 1.0
	if gap > n("ease_from_m", 150.0):
		return n("min_pace", 0.55)
	return lerpf(1.0, n("min_pace", 0.55), (gap - n("push_m", 90.0)) / maxf(n("ease_from_m", 150.0) - n("push_m", 90.0), 1.0))


func _got_away() -> void:
	state = State.GONE
	WorldState.on_bounty_got_away()
	var g = demo.get("gear") if demo != null else null
	if g != null and g.hud != null:
		g.hud.toast(str(cfg.get("toast", "The bounty got away.")), 4.0)
	if speeder != null and is_instance_valid(speeder):
		speeder.step_off()
		speeder.queue_free()
	if target != null and is_instance_valid(target):
		target.queue_free()
