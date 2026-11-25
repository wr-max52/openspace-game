class_name SpeederBrain
extends RefCounted
## Issue #609: an NPC driving a speeder. Pure and headless-testable, like the
## fighter brain: it reads its speeder's HoverModel (pose, speed, the ground it
## rides) and what it is after, and writes `command` ({ throttle, steer, boost,
## fire }) for SpeederNode to hand to the very same HoverModel the player drives.
## It never moves the speeder itself, so an NPC can not drive faster, turn harder
## or pass through anything the player can not.
##
## Whatever owns the speeder (a race, a garrison, a bounty) picks the mode and
## sets the situation each frame; SpeederNode runs update() while an NPC sits in
## its driver's seat (rule 7: a pure brain, run by an existing owner).
##
## Modes:
##   IDLE    -- stop and sit
##   FOLLOW  -- drive an ordered list of points, as a loop (laps) or a line (done)
##   PURSUE  -- close on a moving target, hold a range, fire when it is ahead
##   FLEE    -- drive away from a target at `pace` (the caller eases it off)
##   PARK    -- drive to a spot, stop facing a set way (done)
## Every mode steers round `avoid` (beasts, other speeders) and round whatever
## WorldGround.hit says is ahead, and backs off and tries again when stuck.
##
## How well it drives is a skill block: content/core/vehicles/speeder_drivers.json.

enum Mode { IDLE, FOLLOW, PURSUE, FLEE, PARK }

const CFG_PATH := "res://content/core/vehicles/speeder_drivers.json"
static var _cfg: Dictionary = {}

var model: HoverModel
var skill: Dictionary = {}
var mode := Mode.IDLE

## FOLLOW: the points (world positions), whether they loop, the next one, laps done.
var points: Array = []
var loop := true
var index := 0
var laps := 0
## PURSUE / FLEE: the target, set by the owner each frame.
var target_pos := Vector3.INF
var target_vel := Vector3.ZERO
## 0..1: the share of top speed it may use (FLEE eases off with it; any mode may).
var pace := 1.0
var may_boost := true
## PARK: where and which way (HoverModel yaw: 0 faces -Z, PI/2 faces -X).
var park_at := Vector3.INF
var park_yaw := 0.0
## [{ "pos": Vector3, "radius": float }]: things to steer round this frame.
var avoid: Array = []
var weapon_range := 140.0

## What the speeder does this frame.
var command := { "throttle": 0.0, "steer": 0.0, "boost": false, "fire": false }
var done := false                ## FOLLOW (a line) reached its end; PARK stopped on the spot
var stuck_events := 0
var shots_wanted := 0            ## frames it asked to fire (tests, traces)

var _rng := RandomNumberGenerator.new()
var _stuck_t := 0.0
var _backoff_t := 0.0
var _backoff_steer := 0.0
var _boost_on := false
var _boost_t := 0.0
var _wander := 0.0
var _wander_t := 0.0


func _init(hover: HoverModel = null, skill_id: String = "default", rng_seed: int = 1) -> void:
	model = hover
	skill = skill_block(skill_id)
	_rng.seed = rng_seed
	if model != null:
		weapon_range = float(model.cfg.get("laser", {}).get("range", 140.0))


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(CFG_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg = d if d is Dictionary else {}
	return _cfg


## A rule shared by every driver (boarding, stuck, thrown clear).
static func rule(key: String, fallback: float) -> float:
	return float(cfg().get("rules", {}).get(key, fallback))


## The "default" skill with the named one's numbers over it.
static func skill_block(id: String) -> Dictionary:
	var skills: Dictionary = cfg().get("skills", {})
	var out: Dictionary = (skills.get("default", {}) as Dictionary).duplicate()
	if id != "default":
		out.merge(skills.get(id, {}), true)
	return out


func s(key: String, fallback: float) -> float:
	return float(skill.get(key, fallback))


# ---------------------------------------------------------------- modes

func idle() -> void:
	mode = Mode.IDLE
	done = false


func follow(route: Array, as_loop: bool = true) -> void:
	points = route.duplicate()
	loop = as_loop
	index = 0
	laps = 0
	done = points.is_empty()
	mode = Mode.FOLLOW


func pursue() -> void:
	mode = Mode.PURSUE
	done = false


func flee() -> void:
	mode = Mode.FLEE
	done = false


func park(at: Vector3, yaw: float) -> void:
	park_at = at
	park_yaw = yaw
	mode = Mode.PARK
	done = false


# ---------------------------------------------------------------- frame

func update(dt: float) -> Dictionary:
	command = { "throttle": 0.0, "steer": 0.0, "boost": false, "fire": false }
	if model == null or not model.alive():
		return command
	_tick_wander(dt)
	match mode:
		Mode.FOLLOW:
			_follow()
		Mode.PURSUE:
			_pursue()
		Mode.FLEE:
			_flee()
		Mode.PARK:
			_park()
	if mode != Mode.IDLE and not (mode == Mode.PARK and done):
		_avoid()
		_unstick(dt)
	_tick_boost(dt)
	if bool(command.fire):
		shots_wanted += 1
	return command


func _follow() -> void:
	if done or points.is_empty():
		return
	var goal: Vector3 = points[index]
	var reach := s("point_reach", 12.0)
	if _flat(goal - model.position).length() <= reach:
		index += 1
		if index >= points.size():
			if loop:
				index = 0
				laps += 1
			else:
				done = true
				index = points.size() - 1
				return
		goal = points[index]
	# Slow for the turn after this point when it is near enough to matter.
	var want := _top() * pace
	var after: Vector3 = points[(index + 1) % points.size()] if (loop or index + 1 < points.size()) else goal
	var dist := _flat(goal - model.position).length()
	if after != goal and dist < maxf(model.speed, 0.0) * s("brake_time", 1.2) + reach:
		var turn := _flat(goal - model.position).angle_to(_flat(after - goal))
		want *= clampf(1.0 - turn / PI * s("corner_slow", 0.8), s("min_corner", 0.35), 1.0)
	_drive_to(goal + _side() * _wander, want, dist > s("boost_dist", 50.0))


func _pursue() -> void:
	if target_pos == Vector3.INF:
		return
	var to := _flat(target_pos - model.position)
	var dist := to.length()
	var lead := clampf(dist / maxf(absf(model.speed), 10.0), 0.0, s("lead_s", 1.0))
	var goal := target_pos + target_vel * lead
	var hold := s("hold_range", 30.0)
	var want := _top() * pace
	if dist < hold * 1.5:
		want = clampf(target_vel.length() + (dist - hold) * 0.8, 0.0, _top() * pace)
	_drive_to(goal, want, dist > s("boost_dist", 50.0))
	var ahead := rad_to_deg(model.forward().angle_to(to)) if dist > 0.01 else 0.0
	command.fire = dist <= weapon_range and ahead <= s("fire_cone_deg", 7.0)


func _flee() -> void:
	if target_pos == Vector3.INF:
		return
	var away := _flat(model.position - target_pos)
	away = away.normalized() if away.length() > 0.01 else model.forward()
	# Keep a heading it can hold: away from the target, bent toward where it faces.
	var dir := (away * 2.0 + model.forward()).normalized()
	_drive_to(model.position + dir * 80.0 + _side() * _wander, _top() * pace, pace >= 0.99)


func _park() -> void:
	if park_at == Vector3.INF:
		return
	var dist := _flat(park_at - model.position).length()
	if dist > s("park_reach", 2.5):
		var want := minf(_top(), sqrt(2.0 * model.p("brake", 34.0) * dist) * 0.5)
		_drive_to(park_at, want, false)
		return
	# On the spot: let it coast to a stop and turn to face the way.
	var diff := wrapf(park_yaw - model.yaw, -PI, PI)
	command.throttle = -0.4 if model.speed > 1.0 else 0.0
	command.steer = clampf(-diff * 2.0, -1.0, 1.0)
	if absf(rad_to_deg(diff)) <= s("park_face_deg", 8.0) and absf(model.speed) < 0.8:
		command.steer = 0.0
		command.throttle = 0.0
		done = true


# ---------------------------------------------------------------- steering

## Steer at `goal` and hold `want` m/s: brake hard when going too fast, ease off
## for a sharp angle, boost only nearly straight on and far enough out.
func _drive_to(goal: Vector3, want: float, far: bool) -> void:
	var to := _flat(goal - model.position)
	if to.length() < 0.01:
		return
	var angle := _signed_angle(to)
	command.steer = clampf(-angle * s("steer_gain", 2.4), -1.0, 1.0)
	var a := absf(angle)
	want *= clampf(1.0 - maxf(0.0, a - deg_to_rad(20.0)) / PI * 1.4, 0.25, 1.0)
	if model.speed > want + 4.0:
		command.throttle = -1.0                       # brake (HoverModel's brake rate)
	else:
		command.throttle = clampf(want / maxf(model.p("max_speed", 36.0), 1.0), 0.0, 1.0)
		if a > deg_to_rad(100.0) and to.length() < 20.0:
			command.throttle = minf(command.throttle, 0.35)   # behind and close: turn tight
	command.boost = far and may_boost and _boost_on and a < deg_to_rad(s("boost_angle_deg", 12.0)) \
		and want > model.p("max_speed", 36.0) - 0.5


## Steer round what is ahead: the owner's `avoid` list, then buildings and rocks.
func _avoid() -> void:
	var fwd := model.forward()
	var right := _right()
	var look := s("look_min", 8.0) + maxf(model.speed, 0.0) * s("look_ahead_s", 0.6)
	var margin := s("avoid_margin", 3.0) + model.p("body_radius", 1.3)
	for a: Dictionary in avoid:
		var at = a.get("pos", null)
		if not (at is Vector3):
			continue
		var rel := _flat((at as Vector3) - model.position)
		var along := rel.dot(fwd)
		var side := rel.dot(right)
		var r := float(a.get("radius", 2.0)) + margin
		if along > 0.0 and along < look + r and absf(side) < r:
			# Away from it: if it is right of the nose, steer left.
			var push := (1.0 - absf(side) / r) * 1.6
			command.steer = clampf(float(command.steer) + (-push if side >= 0.0 else push), -1.0, 1.0)
	var g := model.ground
	if g == null:
		return
	var r0 := model.p("body_radius", 1.3)
	if g.hit(model.position + fwd * look, r0) == "":
		return
	var left := g.hit(model.position + fwd.rotated(model.up(), deg_to_rad(35.0)) * look, r0) == ""
	var rite := g.hit(model.position + fwd.rotated(model.up(), deg_to_rad(-35.0)) * look, r0) == ""
	if rite and not left:
		command.steer = 1.0
	elif left and not rite:
		command.steer = -1.0
	elif left and rite:
		command.steer = 1.0 if float(command.steer) >= 0.0 else -1.0
	else:
		command.steer = 1.0 if float(command.steer) >= 0.0 else -1.0
		command.throttle = minf(float(command.throttle), 0.3)
	command.boost = false


## Pressing on and not moving for stuck_s: back off, turning the other way, then
## try again.
func _unstick(dt: float) -> void:
	if _backoff_t > 0.0:
		_backoff_t -= dt
		command.throttle = -1.0
		command.steer = _backoff_steer
		command.boost = false
		command.fire = false
		return
	if float(command.throttle) > 0.3 and absf(model.speed) < 1.5 and not model.airborne:
		_stuck_t += dt
		if _stuck_t >= rule("stuck_s", 1.6):
			_stuck_t = 0.0
			stuck_events += 1
			_backoff_t = rule("backoff_s", 1.2)
			_backoff_steer = -1.0 if float(command.steer) >= 0.0 else 1.0
	else:
		_stuck_t = 0.0


func _tick_boost(dt: float) -> void:
	_boost_t -= dt
	if _boost_t <= 0.0:
		_boost_t = 0.5
		_boost_on = _rng.randf() < s("boost", 0.6)


func _tick_wander(dt: float) -> void:
	_wander_t -= dt
	if _wander_t <= 0.0:
		_wander_t = 1.5
		_wander = _rng.randf_range(-1.0, 1.0) * s("wander_m", 1.5)


# ---------------------------------------------------------------- helpers

func _top() -> float:
	return model.p("max_speed", 36.0)


## `v` with the part along up removed (flat to the ground here).
func _flat(v: Vector3) -> Vector3:
	var u := model.up()
	return v - u * v.dot(u)


func _right() -> Vector3:
	return model.forward().cross(model.up()).normalized()


func _side() -> Vector3:
	return _right()


## Radians from the nose to `to`: positive is to the left (HoverModel's steer is
## positive to the right, so the brain steers -angle).
func _signed_angle(to: Vector3) -> float:
	var fwd := model.forward()
	return atan2(-to.dot(_right()), to.dot(fwd))
