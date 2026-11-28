extends RefCounted
## Climbing a ladder. Pure and headless-testable, like the character controller
## and the jetpack: it owns where you are on the ladder and hands the body a
## position each physics tick (the body skips its walk while it is on); the avatar
## reads anim() for the pose (BodyAnimator.climb_pose).
##
## How it plays (the ladders: src/systems/world/ladders.gd):
##   - Walk into a ladder's foot holding W: you step on (MOUNT) and W climbs,
##     rung over rung. Let go and you hang there.
##   - At the top you climb out onto the floor it leads to (TOP_OUT): up over the
##     lip, a knee on the edge, stood up past the rungs. No room to stand there and
##     you stop with your hands on the top rungs.
##   - On the floor at a ladder's top, [E] (PlayerClimber) swings you round onto it
##     (TOP_IN): back over the lip and down a few rungs, facing it.
##   - S slides you down, hands and boots on the rails, faster and faster; let go of
##     S and you grip and stop. At the foot you are off (a landing).
##   - Space lets go: a little push back off the ladder, and you fall (the jetpack
##     works from there as from any jump).
##
## Every number comes from content/core/flow/ladders.json "climb".

const Ladders := preload("res://src/systems/world/ladders.gd")
const PATH := "res://content/core/flow/ladders.json"

enum Phase { OFF, MOUNT, CLIMB, TOP_OUT, TOP_IN }

static var _cfg_cache: Dictionary = {}

var cfg: Dictionary = {}
var phase := Phase.OFF
var ladder: Dictionary = {}         ## the one you are on, in the world (Ladders.world_of)
var u := 0.0                        ## your feet, metres up it from its foot
var speed := 0.0                    ## m/s up it (- down)
var sliding := false
var t := 0.0                        ## seconds into a MOUNT, TOP_OUT or TOP_IN
var _from := Vector3.ZERO           ## where that move began (world)
var _face_from := Vector3.ZERO      ## the way you faced as it began (TOP_IN turns you round)
var _u_from := 0.0
## What happened this step, for sounds and the HUD: "mount", "top", "bottom",
## "let_go", "slide" (a slide began), "rung" (a rung climbed).
var events: Array = []
var climbs := 0                     ## ladders climbed out of at the top (traces, tests)
var slides := 0                     ## slides down to a foot (traces, tests)
var _rung_was := 0


func _init(c: Dictionary = {}) -> void:
	cfg = c if not c.is_empty() else load_cfg()


static func load_cfg() -> Dictionary:
	if _cfg_cache.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg_cache = (d as Dictionary).get("climb", {}) if d is Dictionary else {}
	return _cfg_cache


func n(key: String, def: float) -> float:
	return float(cfg.get(key, def))


func active() -> bool:
	return phase != Phase.OFF


## On the rungs proper (not stepping on, or climbing out or in at the top).
func on_rungs() -> bool:
	return phase == Phase.CLIMB


func phase_name() -> String:
	return ["OFF", "MOUNT", "CLIMB", "TOP_OUT", "TOP_IN"][phase]


## On from the foot, standing at `at`.
func start_bottom(w: Dictionary, at: Vector3) -> void:
	ladder = w
	phase = Phase.MOUNT
	t = 0.0
	_from = at
	_face_from = w.fwd
	u = clampf(Ladders.local(w, at).y, 0.0, float(w.h))
	_u_from = u
	speed = 0.0
	sliding = false
	_rung_was = _rung()
	events = ["mount"]


## On from the floor at the top, standing at `at` facing `facing` (world).
func start_top(w: Dictionary, at: Vector3, facing: Vector3) -> void:
	ladder = w
	phase = Phase.TOP_IN
	t = 0.0
	_from = at
	var up: Vector3 = w.up
	var f := facing - up * facing.dot(up)
	_face_from = f.normalized() if f.length() > 0.01 else -(w.fwd as Vector3)
	u = float(w.h)
	speed = 0.0
	sliding = false
	_rung_was = _rung()
	events = ["mount"]


## Off at once (downed, a teleport): nothing more happens.
func stop() -> void:
	phase = Phase.OFF
	speed = 0.0
	sliding = false


## The highest your feet go before you climb out (or, with no room up there, hang).
func top_u() -> float:
	return maxf(0.0, float(ladder.h) - n("top_out_below", 0.9))


## Near enough the top that the body should check there is room to climb out.
func near_top() -> bool:
	return phase == Phase.CLIMB and u >= top_u() - 0.5


## One physics tick. `climb_in`: -1..1, W up, S down (a slide). `jump`: Space
## pressed this tick (let go). `exit_clear`: there is room to stand at the top
## (Ladders.exit_at). Returns { pos (world), done (off the ladder at its foot or
## top), let_go (fell off: vel is the push), vel }.
func step(dt: float, climb_in: float, jump: bool, exit_clear: bool = true) -> Dictionary:
	events = []
	var out := { "pos": Vector3.ZERO, "done": false, "let_go": false, "vel": Vector3.ZERO }
	match phase:
		Phase.OFF:
			return out
		Phase.MOUNT:
			t += dt
			var d := n("mount_s", 0.35)
			var e := _smooth(t / d)
			u = lerpf(_u_from, maxf(_u_from, n("first_step", 0.3)), e)
			out.pos = _from.lerp(Ladders.stand_at(ladder, u), e)
			if t >= d:
				phase = Phase.CLIMB
			return out
		Phase.TOP_IN:
			t += dt
			var d := n("top_in_s", 0.9)
			var k := clampf(t / d, 0.0, 1.0)
			var h := float(ladder.h)
			var lip := Ladders.stand_at(ladder, h + 0.05)
			var turn := n("top_turn", 0.45)       # the share spent back over the lip
			if k < turn:
				var e := _smooth(k / turn)
				out.pos = _from.lerp(lip, e) + (ladder.up as Vector3) * 0.12 * sin(PI * e)
				u = h
			else:
				var e := _smooth((k - turn) / (1.0 - turn))
				u = lerpf(h + 0.05, top_u(), e)
				out.pos = Ladders.stand_at(ladder, u)
			if t >= d:
				phase = Phase.CLIMB
				u = top_u()
				_rung_was = _rung()
			return out
		Phase.TOP_OUT:
			t += dt
			var d := n("top_out_s", 0.85)
			var k := clampf(t / d, 0.0, 1.0)
			var h := float(ladder.h)
			var rise := n("top_rise", 0.55)       # the share spent pulling up over the lip
			if k < rise:
				var e := _smooth(k / rise)
				u = lerpf(_u_from, h + 0.05, e)
				out.pos = Ladders.stand_at(ladder, u)
			else:
				var e := _smooth((k - rise) / (1.0 - rise))
				u = h
				out.pos = Ladders.stand_at(ladder, h + 0.05).lerp(Ladders.exit_at(ladder), e) \
					+ (ladder.up as Vector3) * 0.1 * sin(PI * e)
			if t >= d:
				phase = Phase.OFF
				out.pos = Ladders.exit_at(ladder)
				out.done = true
				climbs += 1
				events.append("top")
			return out
	# CLIMB
	if jump:
		phase = Phase.OFF
		sliding = false
		out.pos = Ladders.stand_at(ladder, u)
		out.let_go = true
		# A push back off it, and whatever speed you had along it (a slide keeps falling).
		out.vel = -(ladder.fwd as Vector3) * n("let_go_push", 2.5) + (ladder.up as Vector3) * (n("let_go_up", 1.5) + speed)
		speed = 0.0
		events.append("let_go")
		return out
	if climb_in > 0.1:
		sliding = false
		speed = move_toward(speed, n("climb_speed", 1.8) * clampf(climb_in, 0.0, 1.0), n("climb_accel", 10.0) * dt)
	elif climb_in < -0.1:
		if not sliding:
			events.append("slide")
		sliding = true
		speed = move_toward(speed, -n("slide_speed", 6.0), n("slide_accel", 9.0) * dt)
	else:
		var brake := n("slide_brake", 14.0) if sliding else n("climb_accel", 10.0)
		speed = move_toward(speed, 0.0, brake * dt)
		if speed == 0.0:
			sliding = false
	u += speed * dt
	if speed > 0.0 and u >= top_u():
		if exit_clear:
			u = top_u()
			phase = Phase.TOP_OUT
			t = 0.0
			_u_from = u
			speed = 0.0
			out.pos = Ladders.stand_at(ladder, u)
			return out
		u = top_u()
		speed = 0.0
	if u <= 0.0:
		u = 0.0
		phase = Phase.OFF
		out.pos = Ladders.stand_at(ladder, 0.0)
		out.done = true
		out.vel = (ladder.up as Vector3) * speed      # how hard you hit the foot (a slide's speed)
		if sliding:
			slides += 1
		sliding = false
		speed = 0.0
		events.append("bottom")
		return out
	var r := _rung()
	if r != _rung_was and not sliding:
		events.append("rung")
	_rung_was = r
	out.pos = Ladders.stand_at(ladder, u)
	return out


## The way to face (world): the ladder, or turning round onto it from the top.
func facing() -> Vector3:
	if phase == Phase.TOP_IN:
		var turn := n("top_turn", 0.45)
		var e := _smooth(clampf(t / n("top_in_s", 0.9) / turn, 0.0, 1.0))
		var up: Vector3 = ladder.up
		var ang := _face_from.signed_angle_to(ladder.fwd, up)
		return _face_from.rotated(up, ang * e)
	return ladder.fwd


## For BodyAnimator.climb_pose: { w (0..1, how much the climb owns the body), u
## (feet up the ladder, drives the rung-over-rung cycle), slide (0..1), over (0..1:
## the knee-on-the-lip pose of climbing out, or in from the top) }.
func anim() -> Dictionary:
	var a := { "w": 0.0, "u": u, "slide": 0.0, "over": 0.0 }
	match phase:
		Phase.MOUNT:
			a.w = _smooth(t / n("mount_s", 0.35))
		Phase.CLIMB:
			a.w = 1.0
			a.slide = clampf(-speed / 1.5, 0.0, 1.0) if sliding else 0.0
		Phase.TOP_OUT:
			var k := clampf(t / n("top_out_s", 0.85), 0.0, 1.0)
			a.w = 1.0 - _smooth((k - 0.5) / 0.5) if k > 0.5 else 1.0
			a.over = sin(PI * k)
		Phase.TOP_IN:
			var k := clampf(t / n("top_in_s", 0.9), 0.0, 1.0)
			a.w = _smooth(k / 0.5) if k < 0.5 else 1.0
			a.over = sin(PI * k)
	return a


func _rung() -> int:
	return int(floor(u / n("rung", 0.35)))


static func _smooth(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)
