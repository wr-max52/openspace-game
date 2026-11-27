class_name HoverModel
extends RefCounted
## A speeder's movement (issue #42). Pure and headless-testable, like AtmoFlight:
## the scene node reads input and draws, this decides.
##
## It rides `hover_height` above whatever WorldGround says is under it (the sand,
## a floor, the top of a ramp), easing toward that height at `follow_rate`. When
## the ground drops away faster than that in one step (more than `launch_gap`: the
## end of a ramp, a dune crest at speed) it leaves the ground with the vertical
## speed it had and flies ballistic until it comes down. There is no jump button:
## ramps and crests do the jumping, and low gravity makes it float like the light
## sled it is.
##
## Buildings stop it (WorldGround.hit) with a small bounce. Nothing it does to
## itself hurts it: no fall or crash damage. Only gunfire does, through
## apply_damage(), which the node's hull passes on from bolts.
##
## Numbers: content/core/vehicles/speeder.json.
##
## Issue #95: the Grav Lifter (a "hover" block in the config, from the mechanic's
## upgrades). Issue #100: it keeps the momentum you have. lift() hops it off the
## ground (or, already climbing, keeps that climb). While it is on (up to float_s
## seconds; lift() again drops it early) gravity is off and the climb eases toward
## what the nose asks for at hold_damp a second: level holds the height, nose up
## climbs at `climb` m/s, nose down sinks, so a hop rises about hop_vy / hold_damp
## and stops rather than running away. Nose down also gains speed (to max_speed)
## and nose up bleeds it, at `tilt_accel` of the speeder's accel. Meet a rising
## slope while it is on and the slope's climb is added: grav lift into a ramp or a
## dune face and you are launched up it and off the top. Sink onto flat ground and
## it lands. Then it falls as usual, and the lifter recharges for recharge_s times
## the share of float_s it was on (at least min_recharge_s).
##
## In the air, any speeder: W/S tilt the nose down/up (`air_pitch`, up to
## air_pitch_deg, back to level when let go) and boost still pushes it on toward
## boost_speed, at air_boost_scale of its accel, with no throttle needed (W is the
## tilt up there). Boosting under the lifter climbs or sinks boost_climb times as
## fast. Without the lifter the tilt is only for the eye: gravity has the height.
## On the ground W/S tip the nose a little too (`ground_pitch`, up to
## ground_pitch_deg at ground_pitch_rate_deg a second), for the eye only, so the
## tilt shows without a jump or the lifter.
##
## Issue #77: on the home planet's ball "up" turns with the ground. The heading is
## a direction slid along the ground as it drives (so straight stays straight round
## the curve), and heights are measured along up (`_level`: the distance from the
## planet's centre). On a flat world both are exactly the old yaw and y.
##
## Issue #627: Shift is the speeder's ability (`ability.kind`, the freighter's
## shape in flight_model.gd): "boost" (the default: the Sand-boxer, the racer) or
## "drift" (the box truck). A drift keeps it sliding the way it was going
## (`travel_dir`) at the speed it had while the nose turns `turn_scale` times as
## fast, the slide giving way to the nose at `settle` per second. Both run on the
## one meter (boost_time, boost_recharge).

var cfg: Dictionary = {}
var ground: WorldGround
var position := Vector3.ZERO
var yaw: float:                      ## radians about the ground's up; 0 faces -Z (on the plateau)
	get:
		var l := _tilt().inverse() * _fwd
		return atan2(-l.x, -l.z)
	set(v):
		_fwd = _tilt() * Vector3(-sin(v), 0.0, -cos(v))
var _fwd := Vector3.FORWARD          ## heading, along the ground
var speed := 0.0                     ## along the nose, m/s (negative = reversing)
var vy := 0.0                        ## vertical speed, m/s
var airborne := false
var boost_left := 0.0
var spent := false                   ## boost ran dry with the key held: off until it is let go
var hp := 0
var max_hp := 0
var events: Array = []               ## this step's: { type, ... }
var air_time := 0.0                  ## of the current (or last) jump
var top_height := 0.0                ## highest clearance over the ground on the last jump
var float_left := 0.0                ## issue #95: seconds the Grav Lifter has left this lift (gravity off)
var lift_cooldown := 0.0             ## issue #95: until the Grav Lifter can fire again
var air_pitch := 0.0                 ## radians, nose up +, in the air only (W/S tilt it); 0 on the ground
var ground_pitch := 0.0              ## radians, nose up +, the small W/S tip on the ground (for the eye only); eases to 0 in the air
var _float_used := 0.0               ## seconds the lifter has been on this lift (sets the recharge)
var tow := 0.0                       ## issue #618: 0..1, how far into another speeder's draft it is (its node sets it)
var drift_dir := Vector3.ZERO        ## issue #627: where a drift is carrying it (along the ground; ZERO = not drifting)

var _pending: Array = []             ## events from between steps (lift), for the next step()
var _cmd := { "throttle": 0.0, "steer": 0.0, "boost": false }
var _last_ride := NAN                ## the ride height last step (NAN: none yet)
var _ground_rate := 0.0              ## how fast the ground under it was rising, m/s


func _init(config: Dictionary = {}, world_ground: WorldGround = null) -> void:
	cfg = config
	ground = world_ground
	max_hp = int(cfg.get("health", 120))
	hp = max_hp
	boost_left = p("boost_time", 3.5)


static func load_config(id: String = "speeder") -> Dictionary:
	var f := FileAccess.open("res://content/core/vehicles/%s.json" % id, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func p(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


# ---- queries ------------------------------------------------------------------------

func forward() -> Vector3:
	return _fwd


func up() -> Vector3:
	return ground.up_at(position) if ground != null else Vector3.UP


func _tilt() -> Basis:
	return PlanetSphere.tilt_to(up())


func transform() -> Transform3D:
	return Transform3D(Basis.looking_at(_fwd, up()), position)


## How high a point is, measured along up: y on a flat world, the distance from
## the centre on the ball.
func _level(at: Vector3) -> float:
	var sp: PlanetSphere = ground.sphere() if ground != null else null
	return (at - sp.center).length() if sp != null else at.y


## Move by `d` metres along up.
func _lift(d: float) -> void:
	position += up() * d


## The ground's level under the speeder (see _level).
func ground_height() -> float:
	if ground == null:
		return 0.0
	return _level(position) - ground.height_above(position)


## Clearance between the hover line and the ground below (0 when riding).
func height_over_ground() -> float:
	return _level(position) - p("hover_height", 1.05) - ground_height()


func alive() -> bool:
	return hp > 0


## Issue #627: what Shift does: "boost" or "drift" (the config's ability.kind).
func ability() -> String:
	return str(cfg.ability.get("kind", "boost")) if cfg.get("ability") is Dictionary else "boost"


## The ability is lit this step: the key held, meter left, not run dry since the
## key went down, and (boost) the throttle open or (drift) moving.
func ability_lit() -> bool:
	if not bool(_cmd.boost) or boost_left <= 0.0 or spent:
		return false
	if ability() == "drift":
		return absf(speed) > 2.0
	return airborne or float(_cmd.throttle) > 0.1     # in the air W is the tilt, not the throttle


## Boost is lit this step (the throttle open, the key held, boost left, and not
## run dry since the key went down). Never for a drifter.
func boosting() -> bool:
	return ability() == "boost" and ability_lit()


## Issue #627: drifting this step (the box truck's Shift).
func drifting() -> bool:
	return ability() == "drift" and ability_lit()


## Which way it is moving: the nose, or the slide while drifting.
func travel_dir() -> Vector3:
	return drift_dir if drift_dir != Vector3.ZERO else _fwd


func velocity() -> Vector3:
	return travel_dir() * speed + up() * vy


## Issue #95: a Grav Lifter is fitted.
func has_lifter() -> bool:
	return cfg.get("hover") is Dictionary


func lifter() -> Dictionary:
	return cfg.get("hover", {}) if has_lifter() else {}


func lift_ready() -> bool:
	return has_lifter() and lift_cooldown <= 0.0 and hp > 0 and not lifting()


## The Grav Lifter is holding it up now.
func lifting() -> bool:
	return float_left > 0.0


## The air tilt as a share of its limit: -1 nose full down .. 1 full up.
func tilt() -> float:
	return air_pitch / maxf(deg_to_rad(p("air_pitch_deg", 25.0)), 0.001)


# ---- control --------------------------------------------------------------------------

## Put it down at `at` (on the ground there), facing `yaw_rad`.
func place(at: Vector3, yaw_rad: float) -> void:
	position = at
	yaw = yaw_rad
	speed = 0.0
	vy = 0.0
	airborne = false
	drift_dir = Vector3.ZERO
	_lift(ground_height() + p("hover_height", 1.05) - _level(position))
	_last_ride = NAN
	_ground_rate = 0.0


## throttle -1..1 (back..forward), steer -1..1 (left..right).
func set_command(throttle: float, steer: float, boost: bool = false) -> void:
	_cmd = { "throttle": clampf(throttle, -1.0, 1.0), "steer": clampf(steer, -1.0, 1.0), "boost": boost }


## Issue #95: the Grav Lifter's button. On the ground it hops; in the air it
## starts the hold at once; already on, it drops it (falling from there). False
## if there is no lifter or it is recharging.
func lift() -> bool:
	if lifting():
		drop_lift()
		return true
	if not lift_ready():
		return false
	var h := lifter()
	if not airborne:
		airborne = true
		# Issue #100: climbing a slope already? Keep that climb if it beats the hop.
		vy = maxf(maxf(vy, _ground_rate), float(h.get("hop_vy", 5.0)))
		air_time = 0.0
		top_height = 0.0
	else:
		vy = maxf(vy, 0.0)
	float_left = float(h.get("float_s", 4.0))
	_float_used = 0.0
	_pending.append({ "type": "lift", "vy": vy })     # reported by the next step()
	return true


## Turn the lifter off (Space again, its time up, or touching down) and start
## its recharge: the longer it was on, the longer it takes. `now`: from inside
## step(), so the event goes out this step instead of the next.
func drop_lift(now: bool = false) -> void:
	if lifting():
		_end_lift(now)


func _end_lift(now: bool) -> void:
	var h := lifter()
	var share := clampf(_float_used / maxf(float(h.get("float_s", 4.0)), 0.01), 0.0, 1.0)
	float_left = 0.0
	lift_cooldown = maxf(float(h.get("min_recharge_s", 1.0)), float(h.get("recharge_s", 4.0)) * share)
	(events if now else _pending).append({ "type": "drop", "held": _float_used })


## Gunfire. Returns true if this shot destroyed it.
func apply_damage(amount: float) -> bool:
	if hp <= 0:
		return false
	hp = maxi(0, hp - int(ceil(amount)))
	events.append({ "type": "hit", "damage": amount, "hp": hp })
	if hp == 0:
		events.append({ "type": "destroyed", "at": position })
		return true
	return false


# ---- frame ------------------------------------------------------------------------------

## Advance one step. Returns this step's events.
func step(dt: float) -> Array:
	events = _pending
	_pending = []
	if hp <= 0:
		return events
	lift_cooldown = maxf(0.0, lift_cooldown - dt)
	_drive(dt)
	_move(dt)
	_hover(dt)
	return events


func _drive(dt: float) -> void:
	var throttle: float = _cmd.throttle
	# An empty meter ends the boost until the key is let go: held on, one step's
	# recharge would light it again the next, flickering at boost speed for ever.
	if not bool(_cmd.boost):
		spent = false
	var lit := ability_lit()
	if lit:
		boost_left = maxf(0.0, boost_left - dt)
		spent = boost_left <= 0.0
	else:
		boost_left = minf(p("boost_time", 3.5), boost_left + dt * p("boost_recharge", 0.45))
	var drift := lit and ability() == "drift"
	var boost := lit and ability() == "boost"
	var target := 0.0
	if throttle > 0.0:
		target = throttle * (p("boost_speed", 52.0) if boost else p("max_speed", 36.0)) * (1.0 + tow * p("tow_speed", 0.0))
	elif throttle < 0.0:
		target = throttle * p("reverse_speed", 9.0)
	var rate := p("accel", 16.0) * (1.0 + tow * p("tow_accel", 0.0))
	if throttle == 0.0:
		rate = p("coast_drag", 6.0)
	elif signf(target) != signf(speed) and absf(speed) > 0.5:
		rate = p("brake", 34.0)
	if not airborne and not drift:
		speed = move_toward(speed, target, rate * dt)    # issue #627: a drift holds the speed it had
	# The air: W/S tilt the nose (down/up), back to level when let go; boost still
	# pushes it on; under the lifter the tilt also trades height for speed.
	if airborne:
		air_pitch = move_toward(air_pitch, -throttle * deg_to_rad(p("air_pitch_deg", 25.0)), deg_to_rad(p("air_pitch_rate_deg", 110.0)) * dt)
		if boost:
			speed = move_toward(speed, p("boost_speed", 52.0), p("accel", 16.0) * p("air_boost_scale", 0.6) * dt)
		elif lifting() and not drift:
			var f := tilt()
			var push := p("accel", 16.0) * float(lifter().get("tilt_accel", 0.5)) * absf(f) * dt
			if f < 0.0 and speed < p("max_speed", 36.0):
				speed = minf(p("max_speed", 36.0), speed + push)     # nose down: on you go
			elif f > 0.0:
				speed = move_toward(speed, 0.0, push)                 # nose up: it bleeds off
	else:
		air_pitch = 0.0
	var gp := 0.0 if airborne else -throttle * deg_to_rad(p("ground_pitch_deg", 6.0))
	ground_pitch = move_toward(ground_pitch, gp, deg_to_rad(p("ground_pitch_rate_deg", 40.0)) * dt)
	# Turning: quicker when slow, a little in the air, faster in a drift.
	var k := clampf(absf(speed) / maxf(p("max_speed", 36.0), 1.0), 0.0, 1.0)
	var turn := deg_to_rad(lerpf(p("turn_rate_deg", 110.0), p("turn_rate_fast_deg", 62.0), k))
	if airborne:
		turn *= p("air_turn_scale", 0.35)
	if drift:
		turn *= float(cfg.ability.get("turn_scale", 2.0))
		if drift_dir == Vector3.ZERO:
			drift_dir = _fwd           # the line it was on when the drift began
	_fwd = _fwd.rotated(up(), -float(_cmd.steer) * turn * dt)
	if drift:
		# Keep sliding the way it was going; the slide slowly gives way to the nose,
		# so a long drift still comes round.
		drift_dir = drift_dir.slerp(_fwd, minf(1.0, dt * float(cfg.ability.get("settle", 0.8)))).normalized()
	else:
		drift_dir = Vector3.ZERO


func _move(dt: float) -> void:
	var to: Vector3 = position + travel_dir() * speed * dt
	if ground != null:
		var hit_id := ground.hit(to, p("body_radius", 1.3))
		if hit_id != "":
			events.append({ "type": "bump", "what": hit_id, "speed": speed })
			speed = -speed * p("bump_bounce", 0.25)        # bounced off: no damage
			return
	var lv := _level(position)
	position = to
	_lift(lv - _level(position))       # along the ground: the hover settles the height
	# Slide the heading along with it, so it stays flat to the ground here.
	var u := up()
	_fwd = (_fwd - u * _fwd.dot(u)).normalized()
	if drift_dir != Vector3.ZERO:
		drift_dir = (drift_dir - u * drift_dir.dot(u)).normalized()


func _hover(dt: float) -> void:
	var ride := ground_height() + p("hover_height", 1.05)
	var rate := 0.0 if is_nan(_last_ride) else (ride - _last_ride) / maxf(dt, 0.0001)
	_last_ride = ride
	if airborne:
		if lifting():
			# The Grav Lifter: no gravity; the climb eases toward what the nose asks
			# for (level holds, up climbs, down sinks), so nothing runs away.
			var h := lifter()
			float_left = maxf(0.0, float_left - dt)
			_float_used += dt
			var climb := float(h.get("climb", 3.0)) * (float(h.get("boost_climb", 1.6)) if boosting() else 1.0)
			vy = lerpf(vy, tilt() * climb, clampf(dt * float(h.get("hold_damp", 2.0)), 0.0, 1.0))
			if float_left <= 0.0:
				_end_lift(true)            # its time is up
		else:
			vy -= p("gravity", 9.0) * dt
		_lift(vy * dt)
		air_time += dt
		top_height = maxf(top_height, _level(position) - ride)
		if lifting() and _level(position) <= ride and rate > 0.5:
			# A rising slope under it while the lifter is on: ride up it, carrying
			# its climb, and off the top (a ramp launches you).
			_lift(ride - _level(position))
			vy = maxf(vy, rate)
			return
		if _level(position) <= ride:
			events.append({ "type": "landed", "fall_speed": -vy, "air_time": air_time, "top": top_height })
			_lift(ride - _level(position))
			vy = 0.0
			airborne = false
			air_pitch = 0.0
			drop_lift(true)                # sunk onto flat ground: the lifter lets go
		return
	var before := _level(position)
	if before - ride > p("launch_gap", 0.45):
		# The ground fell away faster than we can follow: off the edge, carrying
		# the climb the ground was giving it (up a ramp, that is the jump).
		airborne = true
		vy = maxf(vy, _ground_rate)
		air_time = 0.0
		top_height = before - ride
		events.append({ "type": "launch", "vy": vy, "speed": speed })
		vy -= p("gravity", 9.0) * dt
		_lift(vy * dt)
		return
	_ground_rate = rate
	var y := lerpf(before, ride, clampf(dt * p("follow_rate", 14.0), 0.0, 1.0))
	if ride > y:
		y = maxf(y, ride - 0.25)   # never sink into a rise
	_lift(y - before)
	vy = (y - before) / maxf(dt, 0.0001)
