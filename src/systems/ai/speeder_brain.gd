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
##   FOLLOW  -- drive an ordered list of points, as a loop (laps) or a line (done);
##              follow_track() drives a race track (issue #853, RaceCourse.race_tracks)
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
## Issue #611: any mode may also shoot at this (a racer on lap 2 shooting the
## leader while it drives the line): fires when it is in the nose cone and in
## range. INF = nobody.
var shoot_at := Vector3.INF

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
## Issue #853: FOLLOW on a race track (follow_track): dense points cleared of rock,
## driven a look-ahead along them, braking for the turns ahead, no wander, and the
## rock swerve held back unless it is more than track_off_m past the track's room.
var on_track := false
var off_track_m := 0.0                 ## how far it is off its track, past the track's room there (tests, traces)
var room := PackedFloat32Array()       ## per track point: m it may stray and stay clear (RaceCourse.track_room)


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
	on_track = false


## Issue #853: drive a race track round and round (a loop of points a few metres
## apart, already clear of rock). `track_room` (RaceCourse.track_room) says how
## far it may stray at each point: on open sand it cuts corners, by rock it holds
## its lane. Without it, it holds its lane everywhere.
func follow_track(track: Array, track_room := PackedFloat32Array()) -> void:
	follow(track, true)
	on_track = track.size() >= 2
	off_track_m = 0.0
	room = track_room if track_room.size() == track.size() else PackedFloat32Array()


## How far it may stray from point `j` and stay clear: the track's room there, at
## least track_chord_m.
func _room(j: int) -> float:
	var r := float(room[j]) if room.size() == points.size() else 0.0
	return maxf(r, s("track_chord_m", 1.0))


func pursue() -> void:
	mode = Mode.PURSUE
	on_track = false
	done = false


func flee() -> void:
	mode = Mode.FLEE
	on_track = false
	done = false


func park(at: Vector3, yaw: float) -> void:
	park_at = at
	park_yaw = yaw
	mode = Mode.PARK
	on_track = false
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
	if shoot_at != Vector3.INF and _backoff_t <= 0.0:
		var to := _flat(shoot_at - model.position)
		if to.length() <= weapon_range and to.length() > 0.01 \
				and rad_to_deg(model.forward().angle_to(to)) <= s("fire_cone_deg", 7.0):
			command.fire = true
	if bool(command.fire):
		shots_wanted += 1
	return command


func _follow() -> void:
	if done or points.is_empty():
		return
	if on_track:
		_follow_track()
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


## Issue #853: on its track. Finds the stretch it is on (moving on as it passes
## each point, and on to a stretch further ahead when knocked nearer to that one,
## never back), aims track_look_s of speed along the track from there, and holds
## the most speed it can still brake from for every turn ahead.
func _follow_track() -> void:
	var n := points.size()
	for guard in n:
		var a: Vector3 = points[(index - 1 + n) % n]
		var seg := _flat((points[index] as Vector3) - a)
		var l2 := seg.length_squared()
		if l2 > 0.0001 and _flat(model.position - a).dot(seg) < l2:
			break
		_next_point()
	var here := _seg_dist(index)
	var skip := 0
	for k in range(1, int(s("track_rejoin", 8.0)) + 1):
		var d := _seg_dist((index + k) % n)
		if d < here - 1.0:
			here = d
			skip = k
	for k in skip:
		_next_point()
	# Off its track past the room it has there and over the next track_room_ahead_s
	# of driving (cutting a corner on open sand is not off; wide of a lane it is
	# about to enter between rocks is).
	off_track_m = maxf(0.0, here - _room_ahead())
	var look := maxf(s("point_reach", 12.0), maxf(model.speed, 0.0) * s("track_look_s", 0.45))
	var corner := _corner_speed()
	# Off its track: slower the further off, till it is back on its lane.
	var off_cap := _top() * clampf(1.0 - off_track_m / (2.0 * s("track_off_m", 4.0)), 0.35, 1.0)
	_drive_to(_along(look), minf(minf(_top() * pace, corner), off_cap), corner >= model.p("boost_speed", _top()) - 0.5 and off_track_m < 2.0)


## The least room on the track from here to track_room_ahead_s of speed on (0
## with no room list: the track is a lane everywhere).
func _room_ahead() -> float:
	var n := points.size()
	if room.size() != n:
		return 0.0
	var reach := maxf(model.speed, 0.0) * s("track_room_ahead_s", 1.5)
	var r := float(room[index])
	var dist := 0.0
	var j := index
	for guard in n:
		var nj := (j + 1) % n
		dist += _flat((points[nj] as Vector3) - (points[j] as Vector3)).length()
		if dist > reach:
			break
		r = minf(r, float(room[nj]))
		j = nj
	return r


func _next_point() -> void:
	index += 1
	if index >= points.size():
		index = 0
		laps += 1


## Ground distance from the speeder to the stretch ending at point `j`.
func _seg_dist(j: int) -> float:
	var n := points.size()
	var a: Vector3 = points[(j - 1 + n) % n]
	var seg := _flat((points[j] as Vector3) - a)
	var rel := _flat(model.position - a)
	var t := clampf(rel.dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
	return (rel - seg * t).length()


## The point `dist` m along the track from where the speeder is on it, brought
## in where it would cut too close to rock: the farthest point whose straight
## line from the speeder passes every track point before it within that point's
## room (_room: wide on open sand, so it cuts corners; a metre by rock, so it
## never cuts across a weave), but never nearer than point_reach.
func _along(dist: float) -> Vector3:
	var n := points.size()
	var a: Vector3 = points[(index - 1 + n) % n]
	var b: Vector3 = points[index]
	var seg := b - a
	var t := clampf(_flat(model.position - a).dot(_flat(seg)) / maxf(_flat(seg).length_squared(), 0.0001), 0.0, 1.0)
	var at := a + seg * t
	var cands: Array[Vector3] = []           # track points between the speeder and the goal, then the goal
	var tols: Array[float] = []
	var goal := at
	var j := index
	for guard in n:
		var to: Vector3 = points[j]
		var d := _flat(to - at).length()
		if d >= dist:
			goal = at.lerp(to, dist / maxf(d, 0.0001))
			break
		dist -= d
		at = to
		cands.append(to)
		tols.append(_room(j))
		goal = to
		j = (j + 1) % n
	if cands.is_empty() or cands[-1] != goal:
		cands.append(goal)
		tols.append(_room(j))
	var near := s("point_reach", 12.0)     # never nearer than this: inside its turning circle it would circle
	var best := goal
	for k in cands.size():
		var c: Vector3 = cands[k]
		var chord := _flat(c - model.position)
		var ok := true
		if chord.length() >= near:
			for q in k:
				var rel := _flat(cands[q] - model.position)
				var u := clampf(rel.dot(chord) / maxf(chord.length_squared(), 0.0001), 0.0, 1.0)
				if (rel - chord * u).length() > tols[q]:
					ok = false
					break
		if not ok:
			break
		best = c
	return best


## The most speed it may hold now and still slow in time for every turn ahead,
## out to as far as it would need to stop from boost speed (so it never boosts
## into a turn it can not brake for): at each point the turn is the angle between
## the track track_turn_pts points before and after it, taken at _turn_speed, and
## braked for at track_brake_use of the speeder's brake (less than all of it: at
## speed it flies off crests, and in the air it can not brake).
func _corner_speed() -> float:
	var n := points.size()
	var w := maxi(1, int(s("track_turn_pts", 2.0)))
	var decel := model.p("brake", 34.0) * s("track_brake_use", 0.5)
	var v := maxf(maxf(model.speed, 0.0), model.p("boost_speed", _top()))
	var horizon := v * v / (2.0 * maxf(decel, 0.1)) + 30.0
	var best := INF
	# From w points back (a turn it is still in counts in full) to the horizon.
	var dist := 0.0
	var ahead := false
	var j := (index - w + n) % n
	for guard in n:
		var p: Vector3 = points[j]
		if j == index:
			ahead = true
			dist = _flat(p - model.position).length()
		if dist > horizon:
			break
		var into := _flat(p - (points[(j - w + n) % n] as Vector3))
		var out := _flat((points[(j + w) % n] as Vector3) - p)
		if into.length() > 0.01 and out.length() > 0.01:
			# Slow by where the turn begins, not the corner: the arc starts its
			# tangent length before it, and it steers for it a look-ahead sooner.
			var turn := into.angle_to(out)
			var bend := _corner_room(j)
			var v_turn := _turn_speed(turn, bend)
			if v_turn < INF:
				var lead := minf(v_turn * s("track_look_s", 0.45) + _turn_radius(turn, bend) * tan(minf(turn, 2.8) * 0.5), s("track_lead_m", 25.0))
				best = minf(best, sqrt(v_turn * v_turn + 2.0 * decel * maxf(0.0, dist - lead)))
		var nj := (j + 1) % n
		if ahead:
			dist += _flat((points[nj] as Vector3) - p).length()
		j = nj
	return best


## How far a turn at point `j` may bend out from the corner: the least room on
## the track from two points before it to track_corner_pts after it (where it
## comes out of the turn), from track_corner_m (tight by rock) up to
## track_corner_max_m (open sand: the turn is taken wide and fast).
func _corner_room(j: int) -> float:
	var n := points.size()
	var r := INF
	for k in range(-2, int(s("track_corner_pts", 10.0)) + 1):
		r = minf(r, _room((j + k + n) % n))
	return clampf(r, s("track_corner_m", 4.0), s("track_corner_max_m", 14.0))


## The radius of the arc round a turn of `turn` radians that bends out no more
## than `bend_m` from the corner (INF: no turn).
func _turn_radius(turn: float, bend_m: float) -> float:
	var bend := 1.0 / maxf(cos(turn * 0.5), 0.05) - 1.0
	return bend_m / bend if bend > 0.0001 else INF


## The fastest it can take a turn of `turn` radians and stay within `bend_m` of
## the corner: the arc that bends no further than that, at the speeder's own turn
## rate for that speed (HoverModel: quicker when slow).
func _turn_speed(turn: float, bend_m: float) -> float:
	var r := _turn_radius(turn, bend_m)
	if r == INF:
		return INF
	var top := maxf(_top(), 1.0)
	var slow := deg_to_rad(model.p("turn_rate_deg", 110.0))
	var fast := deg_to_rad(model.p("turn_rate_fast_deg", 62.0))
	var v := r * slow / (1.0 + r * (slow - fast) / top)
	if v > top:
		v = maxf(top, r * fast)
	return maxf(v, s("track_min_speed", 6.0))


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
## for a sharp angle, boost only nearly straight on and far enough out. Speeder
## classes: never on the box truck, whose Shift is a drift that would hold its
## speed instead of building it.
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
		and want > model.p("max_speed", 36.0) - 0.5 and model.ability() == "boost"


## Steer round what is ahead: the owner's `avoid` list, then buildings and rocks.
func _avoid() -> void:
	var fwd := model.forward()
	var right := _right()
	var look := s("look_min", 8.0) + maxf(model.speed, 0.0) * s("look_ahead_s", 0.6)
	var margin := s("avoid_margin", 3.0) + model.p("body_radius", 1.3)
	# On its track (issue #853): other speeders pushed past more gently (the
	# track's lane is narrow), and no rock swerve: the track is clear already.
	var held := on_track and off_track_m <= s("track_off_m", 4.0)
	var push_scale: float = s("track_avoid", 0.5) if on_track else 1.0
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
			var push := (1.0 - absf(side) / r) * 1.6 * push_scale
			command.steer = clampf(float(command.steer) + (-push if side >= 0.0 else push), -1.0, 1.0)
	var g := model.ground
	if g == null or held:
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
	if float(command.throttle) >= 0.3 and absf(model.speed) < 1.5 and not model.airborne:
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
