class_name SpeederChase
extends RefCounted
## Issue #883: one speeder chasing you, the loop the gate chase (#613, GateChase)
## and the heist's getaway (HeistRaid) share. Its owner spawns the speeder, seats
## the riders, sets up the driver's SpeederBrain and decides what happens after;
## this says what the chaser does each frame and tells the owner when something
## changes:
##
##   CHASE    you ride a speeder: the driver pursues you (its brain's PURSUE, with
##            whatever the owner switched on, such as the getaway's harass).
##   PULL_UP  you got off (or were thrown off): it pulls up pull_up_m from you,
##            and once there everyone aboard steps off to fight you on foot.
##   IDLE     nothing to do: not started, pulled up, gave up, or ended.
##
## tick() returns what happened this frame:
##   ""             nothing new
##   "pull_up"      you got off: they are pulling up near you
##   "stepped_off"  pulled up: they are off it, on foot
##   "back_on"      you climbed back on while they pulled up: after you again
##   "lost"         you were past escape_m for give_up_s: they give up
##   "ended"        no chaser, no driver or no brain any more (wrecked, shot)
##
## Pure enough for the headless tests: it reads the player node's piloting and
## vehicle and the chaser's model, and only calls the speeder's own calls.

enum State { IDLE, CHASE, PULL_UP }

var chaser: SpeederNode
var state := State.IDLE
var pull_up_m := 18.0
var escape_m := 800.0
var give_up_s := 6.0
var far_t := 0.0                  ## seconds past escape_m so far


func _init(p_chaser: SpeederNode = null, p_pull_up_m := 18.0, p_escape_m := 800.0, p_give_up_s := 6.0) -> void:
	chaser = p_chaser
	pull_up_m = p_pull_up_m
	escape_m = p_escape_m
	give_up_s = p_give_up_s


## The driver is aboard: after you.
func start() -> void:
	if not _ok():
		return
	chaser.brain.pursue()
	state = State.CHASE
	far_t = 0.0


func _ok() -> bool:
	return chaser != null and is_instance_valid(chaser) and chaser.brain != null


## You (`p`, the player node) ride a speeder.
static func riding(p) -> bool:
	return p != null and is_instance_valid(p) and bool(p.get("piloting")) and p.get("vehicle") is SpeederNode


## Where you are and how fast you go: [position, velocity].
static func target_of(p) -> Array:
	if riding(p):
		var v: SpeederNode = p.vehicle
		return [v.model.position, v.model.forward() * v.model.speed]
	return [(p as Node3D).global_position, Vector3.ZERO]


## How far the chaser is from you (INF with no chaser).
func dist_to(p) -> float:
	if chaser == null or not is_instance_valid(chaser) or p == null:
		return INF
	return chaser.model.position.distance_to(target_of(p)[0])


func tick(dt: float, p) -> String:
	if state == State.IDLE:
		return ""
	if not _ok() or p == null or not is_instance_valid(p):
		state = State.IDLE
		return "ended"
	var on := riding(p)
	match state:
		State.CHASE:
			if not chaser.npc_driven():
				state = State.IDLE
				return "ended"
			var t := target_of(p)
			var target: Vector3 = t[0]
			chaser.brain.target_pos = target
			chaser.brain.target_vel = t[1]
			if not on:
				# You got off: pull up near you, then they get off and fight on foot.
				var away: Vector3 = chaser.model.position - target
				away.y = 0.0
				var stop := target + (away.normalized() if away.length() > 0.1 else Vector3.RIGHT) * pull_up_m
				chaser.brain.park(stop, chaser.model.yaw)
				state = State.PULL_UP
				return "pull_up"
			if chaser.model.position.distance_to(target) > escape_m:
				far_t += dt
				if far_t >= give_up_s:
					state = State.IDLE
					return "lost"
			else:
				far_t = 0.0
		State.PULL_UP:
			if on:
				state = State.CHASE        # back on: after you again
				chaser.brain.pursue()
				return "back_on"
			if chaser.brain.done or chaser.model.position.distance_to((p as Node3D).global_position) <= pull_up_m + 4.0:
				chaser.step_off()
				state = State.IDLE
				return "stepped_off"
	return ""
