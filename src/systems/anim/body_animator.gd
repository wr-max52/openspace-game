class_name BodyAnimator
extends RefCounted
## Procedural animation for the jointed CharacterKit body (M11). Pure math: given
## what the character is doing this frame it returns joint rotations, a pelvis
## height and (for weapons) chest-space hand/weapon targets. No nodes, so the state
## machine and the cycle are unit-tested headless (tests/test_body_animator.gut.gd).
##
## Why procedural and not imported clips: the characters are built from joints by
## CharacterKit (no skinned mesh), and the free CC0 clip libraries ship for a
## humanoid skeleton we do not have. Joint math keeps every character (player,
## cantina owner, troopers later) on one system, and every number is tunable here.
##
## Conventions (CharacterKit): the model faces +Z, its left is +X. Limbs hang along
## local -Y. Positive X rotation on a hip swings the leg BACK; positive on a knee
## bends the shin back; negative on an elbow bends the forearm forward.

enum State { LOCOMOTION, AIRBORNE, LAND }

## Upper body modes. FREE swings the arms; the rest are driven by weapons.
const UPPER_FREE := "free"
const UPPER_AIM := "aim"            ## a blaster: right hand forward, left hand supports
const UPPER_RIFLE := "rifle"
const UPPER_SWORD := "sword"        ## guard / swing / block come from SwordPoses
const UPPER_HOLSTER := "holster"    ## mid weapon swap: weapon_xf comes from the caller

const PELVIS_Y := 0.97
## Issue #133: three gaits. A walk, the run (W held, what used to be the Shift
## sprint) and the Shift sprint. The animation blends by speed, so guards and
## NPCs at their own speeds land somewhere on the same curve.
const WALK_SPEED := 4.0
const RUN_SPEED := 7.0
const SPRINT_SPEED := 10.0
## Metres per full cycle (two steps) at each gait's speed. The walk's step is long
## and unhurried (about 3.8 steps a second) so it no longer reads as a jog.
const WALK_STRIDE := 2.1
const RUN_STRIDE := 3.0
const SPRINT_STRIDE := 4.0
## Issue #632: below the walk the stride shortens with the pace (a slow amble takes
## short steps, a guard's walk longer ones), so the step rate and the step length
## both grow with speed: SLOW_STRIDE_BASE + SLOW_STRIDE_PER_MS * speed, up to the walk's
## (and shorter still under 1 m/s).
const SLOW_STRIDE_BASE := 0.85
const SLOW_STRIDE_PER_MS := 0.45

## Issue #632: planted feet. The legs are placed by where each foot is, not swung
## by an angle: a foot on the ground moves back under the hip at exactly the body's
## speed (so it stays put in the world) and rolls heel to toe; then it lifts and
## swings forward. Hip and knee come from two-bone IK on CharacterKit's leg.
const THIGH := 0.46
const SHIN := 0.43
const HIP_Y := -0.04                   ## the hip joints below the pelvis joint
const ANKLE_REST_Y := PELVIS_Y + HIP_Y - THIGH - SHIN   ## the ankle standing straight
const ANKLE_ABOVE_SOLE := 0.085        ## the boot: ankle over the sole
const HEEL_BACK := 0.075               ## heel behind the ankle
const BALL_AHEAD := 0.14               ## ball of the foot ahead of the ankle
const LEG_REACH := 0.993               ## of the full leg: a planted knee never quite locks
const MAX_DROP := 0.07                 ## the most the hips dip to keep both feet down
## Share of a cycle each foot is on the ground (duty factor) at walk, run and sprint:
## a walk always has a foot down, a run spends time in the air.
const DUTY_SLOW := 0.58
const DUTY_WALK := 0.5
const DUTY_RUN := 0.36
const DUTY_SPRINT := 0.27
## The swinging foot's lift over the straight line (m), and how early in the swing
## it peaks (a run kicks the heel up behind first).
const LIFT_WALK := 0.07
const LIFT_RUN := 0.24
const LIFT_SPRINT := 0.42
const STRIKE_DEG := 12.0               ## toes up as the heel lands (walk)
const PUSH_DEG := 26.0                 ## toes down as the foot leaves (walk; more on a run)
const STEADY_S := 0.25                 ## steady walking this long: the legs stop smoothing

var state := State.LOCOMOTION
var phase := 0.0               ## gait phase, radians
var time := 0.0
var dance_time := 0.0          ## continuous 10-second cantina loop
var perform_time := 0.0        ## issue #261: seconds into a performer's set (ClubMoves)
var land_left := 0.0
var land_time := 0.18
var smoothing := 14.0          ## per second; higher = snappier joints
var pelvis_y := PELVIS_Y
var pelvis_x := 0.0            ## issue #87: side-to-side hip shift (metres, + = model's left)
## Sprint slide (issue #65): 0 = not sliding, 1 = full slide pose. It ramps (on top
## of the joint smoothing) so sprint -> slide -> sprint never pops.
var slide_w := 0.0
var slide_blend_s := 0.14

var gait_speed := 0.0          ## issue #632: the speed the gait's shape follows (smoothed)
var steady := 0.0              ## issue #632: 0..1, how settled the walk is (1 = legs unsmoothed)
const GAIT_SPEED_SMOOTH := 6.0
const PELVIS_SMOOTH := 20.0    ## the walk's hip height, smoothed before the legs reach for the ground
const LEG_JOINTS := { "l_hip": true, "r_hip": true, "l_knee": true, "r_knee": true,
	"l_ankle": true, "r_ankle": true }
var _dt := 1.0 / 60.0
var _cur: Dictionary = {}      ## joint -> Vector3 degrees (smoothed)
var _last_state := State.LOCOMOTION
var states_seen := {}          ## for tests/traces: every state name entered


## Inputs:
##   speed:       horizontal speed, m/s
##   move_local:  Vector2(x = to the model's left, y = forward), length <= 1
##   grounded:    bool;   vy: vertical velocity
##   crouch / sprint: bool
##   upper:       one of the UPPER_* modes
##   ready:       0..1, how far a gun is raised (1 = aiming, the default; 0 = at rest)
##   aim_pitch:   radians, + is up (aim modes bend the chest toward it)
##   twist:       degrees of chest yaw the caller adds (sword swings)
##   perform:     issue #261: a performer's set ("dj", "drum", "bass"; ClubMoves), at `bpm`
## Returns { joints: {name: Vector3 deg}, pelvis_y: float, pelvis_x: float, state: String,
##   hands / reach: a performer's hands on their instrument (ClubMoves) }
## Issue #540: with `share_out` step returns the same dictionary every call and its
## `joints` is the animator's own (no copy of every joint per step): for a caller
## that reads them at once and changes nothing (NpcBody). Else new ones, as before.
var share_out := false
var _out := {}


func step(dt: float, inp: Dictionary) -> Dictionary:
	time += dt
	var dancing := bool(inp.get("dance", false))
	if dancing:
		dance_time = fposmod(dance_time + dt, DANCE_LOOP_S)
	var performing := str(inp.get("perform", ""))
	if performing != "":
		perform_time += dt
	var grounded: bool = inp.get("grounded", true)
	var vy: float = inp.get("vy", 0.0)
	var speed: float = inp.get("speed", 0.0)
	var crouch: bool = inp.get("crouch", false)

	# ---- state machine
	match state:
		State.LOCOMOTION:
			if not grounded:
				state = State.AIRBORNE
		State.AIRBORNE:
			if grounded:
				state = State.LAND
				land_left = land_time
		State.LAND:
			land_left -= dt
			if not grounded:
				state = State.AIRBORNE
			elif land_left <= 0.0:
				state = State.LOCOMOTION
	states_seen[state_name()] = true
	if state == State.AIRBORNE:
		states_seen["JUMP" if vy > 0.0 else "FALL"] = true

	# ---- gait phase: one full cycle per stride (two steps). Issue #632: the gait's
	# shape (stride, duty, lift) follows a smoothed speed so a change of pace never
	# jumps a planted foot; the phase runs on the real speed over that same stride,
	# so the planted foot moves back at exactly the body's speed.
	gait_speed = lerpf(gait_speed, speed, 1.0 - exp(-GAIT_SPEED_SMOOTH * dt))
	var stride := stride_for(gait_speed)
	if crouch:
		stride = 0.9
	if state == State.LOCOMOTION and speed > 0.05:
		phase = fmod(phase + TAU * speed / stride * dt, TAU)

	slide_w = move_toward(slide_w, 1.0 if bool(inp.get("slide", false)) and grounded else 0.0, dt / slide_blend_s)
	# On a ladder (LadderClimb.anim): how much the climb owns the body.
	var climb_w := clampf(float(inp.get("climb", 0.0)), 0.0, 1.0)
	if climb_w > 0.5:
		states_seen["CLIMB"] = true
	# Steady walking (on the ground, upright, no slide, dance or set): the legs and
	# hips are posed exactly, since the smoothing lagged and shrank every step. Any
	# other pose blends in through the smoothing as before.
	var plain := state == State.LOCOMOTION and not crouch and slide_w <= 0.0 \
		and not dancing and performing == "" and climb_w <= 0.0
	steady = move_toward(steady, 1.0, dt / STEADY_S) if plain else 0.0
	_dt = dt
	var target := _target(inp, speed, crouch, vy)
	var k := 1.0 - exp(-smoothing * dt)
	if climb_w > 0.0:
		var cp := climb_pose(float(inp.get("climb_u", 0.0)), float(inp.get("climb_slide", 0.0)),
			float(inp.get("climb_over", 0.0)))
		for jn in cp.joints:
			target.joints[jn] = (target.joints.get(jn, Vector3.ZERO) as Vector3).lerp(cp.joints[jn], climb_w)
		target.pelvis_y = lerpf(target.pelvis_y, cp.pelvis_y, climb_w)
		target.pelvis_x = lerpf(target.pelvis_x, cp.pelvis_x, climb_w)
		# The rung-over-rung cycle is quick (two and a half a second): the joints
		# follow it nearly as posed, or the smoothing would shrink every reach.
		k = lerpf(k, 1.0 - exp(-CLIMB_SMOOTH * dt), climb_w)
	var kl := lerpf(k, 1.0, steady)
	for j in target.joints:
		var v: Vector3 = target.joints[j]
		_cur[j] = (_cur.get(j, v) as Vector3).lerp(v, kl if LEG_JOINTS.has(j) else k)
	pelvis_y = lerpf(pelvis_y, target.pelvis_y, kl)
	pelvis_x = lerpf(pelvis_x, target.pelvis_x, k)
	var out := _out if share_out else {}
	out["joints"] = _cur if share_out else _cur.duplicate()
	out["pelvis_y"] = pelvis_y
	out["pelvis_x"] = pelvis_x
	out["state"] = "DANCE" if dancing else ("PERFORM" if performing != "" else ("CLIMB" if climb_w > 0.5 else state_name()))
	out["dance_yaw"] = float(target.get("yaw", 0.0))
	out["hands"] = target.get("hands", {})
	out["reach"] = target.get("reach", {})
	return out


## Issue #133: stride length (one full cycle, metres) for a ground speed.
static func stride_for(speed: float) -> float:
	if speed < WALK_SPEED:
		# Under 1 m/s the steps shrink to nothing, so a body coming to a stop ends
		# with both feet under it.
		return minf(SLOW_STRIDE_BASE + SLOW_STRIDE_PER_MS * speed, WALK_STRIDE) * clampf(speed, 0.05, 1.0)
	if speed <= RUN_SPEED:
		return lerpf(WALK_STRIDE, RUN_STRIDE, clampf((speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0))
	return lerpf(RUN_STRIDE, SPRINT_STRIDE, clampf((speed - RUN_SPEED) / (SPRINT_SPEED - RUN_SPEED), 0.0, 1.0))


## Issue #632: share of a cycle each foot is on the ground at a speed.
static func gait_duty(speed: float) -> float:
	if speed <= 2.0:
		return DUTY_SLOW
	if speed <= WALK_SPEED:
		return lerpf(DUTY_SLOW, DUTY_WALK, (speed - 2.5) / (WALK_SPEED - 2.5))
	if speed <= RUN_SPEED:
		return lerpf(DUTY_WALK, DUTY_RUN, (speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED))
	return lerpf(DUTY_RUN, DUTY_SPRINT, clampf((speed - RUN_SPEED) / (SPRINT_SPEED - RUN_SPEED), 0.0, 1.0))


## Issue #632: the legs for gait `phase` (radians; the left heel lands at 0, the
## right half a cycle later) at `speed`, moving along (fwd, side) in the body frame.
## `prev_pelvis_y` and `dt` smooth the hips' height before the legs reach the
## ground from it, so the planted feet stay exactly on it. Writes the hips, knees
## and ankles (degrees) into `into` and returns
## { joints: into, pelvis_y, feet: { l, r: { z, x, y, pitch, planted } } },
## feet in metres from under the hip (z along the body's forward, x to its left,
## y the ankle's height over its standing height).
static func gait_legs(phase_r: float, speed: float, fwd: float, side: float,
		prev_pelvis_y: float, dt: float, into: Dictionary = {}) -> Dictionary:
	var stride := stride_for(speed)
	var duty := gait_duty(speed)
	var sweep := duty * stride
	var g := clampf(speed / 1.0, 0.0, 1.0)
	var walk01 := clampf(speed / WALK_SPEED, 0.0, 1.0)
	var run01 := clampf((speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	var dash01 := clampf((speed - RUN_SPEED) / (SPRINT_SPEED - RUN_SPEED), 0.0, 1.0)
	# A heel strike and a push off only walking forwards; backwards and sideways
	# the foot stays flat. roll = (strike deg, push deg, heel off at).
	var ahead := clampf(fwd * 2.0, 0.0, 1.0)
	var roll := Vector3(STRIKE_DEG * (1.0 - run01) * ahead * g, (PUSH_DEG + 14.0 * run01) * ahead * g,
		lerpf(0.55, 0.3, run01))
	var lift := g * (LIFT_WALK + 0.03 * walk01) + LIFT_RUN * run01 + (LIFT_SPRINT - LIFT_RUN) * dash01
	var peak_exp := log(0.5) / log(lerpf(0.45, 0.3, run01))
	# Where the foot lands and leaves (centred under the hip, a touch forward: the
	# heel lands ahead).
	var on := _stance_ankle(0.0, sweep, roll)
	var off := _stance_ankle(1.0, sweep, roll)
	var centre := -0.5 * (on.x + off.x) + 0.03 * g
	on.x += centre
	off.x += centre
	var feet := {}
	var hip_max := INF        # how high the hips may ride with every planted foot still down
	var r := LEG_REACH * (THIGH + SHIN)
	var down_any := false
	for leg in ["l", "r"]:
		var p := fposmod(phase_r / TAU + (0.0 if leg == "l" else 0.5), 1.0)
		var planted := p < duty
		var f: Vector3
		if planted:
			f = _stance_ankle(p / duty, sweep, roll)
			f.x += centre
		else:
			var u := (p - duty) / maxf(1.0 - duty, 0.001)
			var e := 0.5 - 0.5 * cos(PI * u)
			f = Vector3(lerpf(off.x, on.x, e), lerpf(off.y, on.y, e) + lift * sin(PI * pow(u, peak_exp)),
				lerpf(off.z, on.z, _smooth01(u)))
		var z := f.x * fwd
		var x := f.x * side
		feet[leg] = { "z": z, "x": x, "y": f.y, "pitch": f.z * ahead, "planted": planted }
		if planted:
			down_any = true
			hip_max = minf(hip_max, ANKLE_REST_Y + f.y + sqrt(r * r - minf(z * z + x * x, r * r * 0.98)))
	# The hips: as high as the planted feet allow (so a walk rises over the foot and
	# dips between steps), never more than MAX_DROP down; a run sits lower (knees
	# taking the load) and bounces up into the flight.
	var base := PELVIS_Y - 0.008 * g - 0.02 * run01 - 0.03 * dash01
	if not down_any:
		base += 0.03 * run01
	var want := clampf(hip_max - HIP_Y, base - MAX_DROP - 0.03 * run01, base) if down_any else base
	var py := lerpf(prev_pelvis_y, want, 1.0 - exp(-PELVIS_SMOOTH * dt))
	var hip_y := py + HIP_Y
	for leg in ["l", "r"]:
		var ft: Dictionary = feet[leg]
		var ay: float = ANKLE_REST_Y + float(ft.y) - hip_y      # the ankle, from the hip (negative)
		var lat := float(ft.x)
		var down := sqrt(ay * ay + lat * lat)
		var ik := leg_ik(float(ft.z), -down)
		into[leg + "_hip"] = Vector3(ik.x, 0, rad_to_deg(atan2(lat, down)) + (2.0 if leg == "l" else -2.0))
		into[leg + "_knee"] = Vector3(ik.y, 0, 0)
		# Foot pitch in the world (toes up +) = -(hip + knee + ankle) about X.
		into[leg + "_ankle"] = Vector3(-float(ft.pitch) - ik.x - ik.y, 0, 0)
	return { "joints": into, "pelvis_y": py, "feet": feet }


## Two-bone IK in the leg's plane: the ankle at `z` ahead of the hip and `y` above
## it (negative). Returns Vector2(hip X, knee X) in degrees (+hip swings the leg
## back, +knee bends the shin back), the knee always forward.
static func leg_ik(z: float, y: float) -> Vector2:
	var reach := THIGH + SHIN
	var d := clampf(sqrt(z * z + y * y), absf(THIGH - SHIN) + 0.01, reach * 0.9995)
	var knee := PI - acos(clampf((THIGH * THIGH + SHIN * SHIN - d * d) / (2.0 * THIGH * SHIN), -1.0, 1.0))
	var a := atan2(z, -y)                   # the hip-to-ankle line, forward of straight down
	var b := acos(clampf((THIGH * THIGH + d * d - SHIN * SHIN) / (2.0 * THIGH * d), -1.0, 1.0))
	return Vector2(-rad_to_deg(a + b), rad_to_deg(knee))


## The planted foot's ankle at `u` (0..1 through its stance), with no centring: a
## point on the ground under it moves from +sweep/2 to -sweep/2 (back at the body's
## speed, so it stays put in the world). The heel lands toes up (roll.x degrees)
## and rocks flat, the foot stays flat, then from roll.z the heel lifts and it rolls
## over the ball to roll.y degrees toes down. Returns Vector3(forward m, height m
## over the standing ankle, foot pitch degrees, toes up +).
static func _stance_ankle(u: float, sweep: float, roll: Vector3) -> Vector3:
	var ground := sweep * (0.5 - u)          # the heel's spot, moving back with the ground
	var pitch := 0.0
	var pivot := ground
	var arm_z := HEEL_BACK                   # pivot -> ankle, foot flat
	if u < 0.15:
		pitch = roll.x * (1.0 - _smooth01(u / 0.15))
	elif u > roll.z:
		pitch = -roll.y * _smooth01((u - roll.z) / maxf(1.0 - roll.z, 0.001))
		pivot = ground + HEEL_BACK + BALL_AHEAD
		arm_z = -BALL_AHEAD
	if pitch == 0.0:
		return Vector3(pivot + arm_z, 0.0, 0.0)
	var rad := deg_to_rad(pitch)
	var c := cos(rad)
	var sn := sin(rad)
	return Vector3(pivot + arm_z * c - ANKLE_ABOVE_SOLE * sn, arm_z * sn + ANKLE_ABOVE_SOLE * c - ANKLE_ABOVE_SOLE, pitch)


func state_name() -> String:
	return ["LOCOMOTION", "AIRBORNE", "LAND"][state]


## Every joint the animator owns, so leftovers from a previous pose never stick.
const JOINTS := ["pelvis", "spine", "chest", "neck", "head",
	"l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist",
	"l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle"]

## Five playful stage moves of DANCE_SEG_S each, crossfaded over DANCE_BLEND_S, so the
## loop is DANCE_LOOP_S long and closes on its own first pose: hip swirl, a twirl,
## a shimmy and blown kiss, a turn-around bend with a hip shake, and a back-facing
## body roll that spins round to face the audience again.
const DANCE_SEG_S := 4.0
const DANCE_BLEND_S := 0.8
const DANCE_MOVES := 5
const DANCE_LOOP_S := DANCE_SEG_S * DANCE_MOVES


## Move i runs on its own clock: it starts DANCE_BLEND_S before its segment so the
## crossfade out of the previous move already shows it, and every move is tuned to
## begin near upright, facing the audience (or the wall, for the one after the bend).
static var _cower: Dictionary = {}


## Issue #605: crouched still (down on one knee, the crouch the player and the
## guards use), sampled once and shared: { joints, pelvis_y }. Puppets and the
## talk-only NPCs take it while they hide from a fight.
static func cower_pose() -> Dictionary:
	if _cower.is_empty():
		var a = load("res://src/systems/anim/body_animator.gd").new()
		var inp := { "speed": 0.0, "move_local": Vector2.ZERO, "grounded": true, "crouch": true, "upper": UPPER_FREE }
		var o: Dictionary = {}
		for i in 120:
			o = a.step(1.0 / 60.0, inp)
		_cower = { "joints": o.joints, "pelvis_y": float(o.pelvis_y) }
	return _cower


## Sat at the controls of an open-cockpit speeder (the racer, show_driver): leaning
## back a little, thighs out ahead, shins down and forward, feet flat, hands out on
## the bars. { joints, pelvis_y }: the soles rest at the body's origin, ahead of
## the hips, so pelvis_y is the hips' height over the floor the feet are on.
const SIT_HIP := 78.0           ## thighs forward of straight down (deg)
const SIT_KNEE := 60.0          ## shins bent back from the thighs (deg)

static func sit_pose() -> Dictionary:
	var j := {}
	for n in JOINTS:
		j[n] = Vector3.ZERO
	j.l_hip = Vector3(-SIT_HIP, 0.0, 7.0)
	j.r_hip = Vector3(-SIT_HIP, 0.0, -7.0)
	j.l_knee = Vector3(SIT_KNEE, 0.0, 0.0)
	j.r_knee = Vector3(SIT_KNEE, 0.0, 0.0)
	j.l_ankle = Vector3(SIT_HIP - SIT_KNEE, 0.0, 0.0)     # foot pitch = -(hip + knee + ankle): flat
	j.r_ankle = Vector3(SIT_HIP - SIT_KNEE, 0.0, 0.0)
	j.spine = Vector3(-8.0, 0.0, 0.0)                    # sat back into the seat
	j.head = Vector3(8.0, 0.0, 0.0)                      # eyes up the track again
	j.l_shoulder = Vector3(-24.0, -5.0, 0.0)            # upper arms down by the sides, forearms turned in
	j.r_shoulder = Vector3(-24.0, 5.0, 0.0)
	j.l_elbow = Vector3(-62.0, 0.0, 0.0)                  # forearms out, low, to the grips
	j.r_elbow = Vector3(-62.0, 0.0, 0.0)
	var h := deg_to_rad(SIT_HIP)
	var shin := deg_to_rad(SIT_HIP - SIT_KNEE)
	return { "joints": j, "pelvis_y": ANKLE_ABOVE_SOLE + THIGH * cos(h) + SHIN * cos(shin) - HIP_Y }


static func dance_pose(seconds: float) -> Dictionary:
	var t := fposmod(seconds, DANCE_LOOP_S)
	var i := int(t / DANCE_SEG_S) % DANCE_MOVES
	var u := t - float(i) * DANCE_SEG_S
	var cur := _dance_move(i, u + DANCE_BLEND_S)
	var into := u - (DANCE_SEG_S - DANCE_BLEND_S)
	if into <= 0.0:
		return cur
	var nxt := _dance_move((i + 1) % DANCE_MOVES, into)
	var w := _smooth01(into / DANCE_BLEND_S)
	var joints := {}
	for n in JOINTS:
		joints[n] = (cur.joints[n] as Vector3).lerp(nxt.joints[n], w)
	return {
		"joints": joints,
		"pelvis_y": lerpf(cur.pelvis_y, nxt.pelvis_y, w),
		"pelvis_x": lerpf(cur.pelvis_x, nxt.pelvis_x, w),
		"yaw": lerp_angle(cur.yaw, nxt.yaw, w),
	}


static func _dance_move(i: int, s: float) -> Dictionary:
	var j := {}
	for n in JOINTS:
		j[n] = Vector3.ZERO
	var py := PELVIS_Y
	var px := 0.0
	var yaw := 0.0
	match i:
		0:  # hip swirl: slow circles, arms overhead, a cheeky head tilt
			var w := TAU * s / 2.0
			j.pelvis = Vector3(6.0 * cos(w), 12.0 * sin(w + 0.8), 9.0 * sin(w))
			j.spine = Vector3(-3.0 * cos(w), -6.0 * sin(w + 0.8), -5.0 * sin(w))
			j.chest = Vector3(2.0, -8.0 * sin(w + 0.8), -6.0 * sin(w))
			j.head = Vector3(-4.0, 6.0 * sin(w - 0.6), 9.0 * sin(w + 0.9))
			j.l_shoulder = Vector3(-18.0, 0.0, 142.0 + 12.0 * sin(w))
			j.r_shoulder = Vector3(-18.0, 0.0, -142.0 - 12.0 * sin(w + 1.1))
			j.l_elbow = Vector3(-26.0 - 10.0 * sin(w), 0.0, 0.0)
			j.r_elbow = Vector3(-26.0 - 10.0 * sin(w + 1.1), 0.0, 0.0)
			j.l_wrist = Vector3(0.0, 0.0, 14.0 * sin(w * 2.0))
			j.r_wrist = Vector3(0.0, 0.0, -14.0 * sin(w * 2.0))
			j.l_hip = Vector3(-3.0, 0.0, 3.0 + 3.0 * sin(w))
			j.r_hip = Vector3(-3.0, 0.0, -3.0 + 3.0 * sin(w))
			j.l_knee = Vector3(9.0 + 9.0 * maxf(0.0, sin(w)), 0.0, 0.0)
			j.r_knee = Vector3(9.0 + 9.0 * maxf(0.0, -sin(w)), 0.0, 0.0)
			px = 0.05 * sin(w)
			py = PELVIS_Y - 0.02 + 0.015 * cos(w * 2.0)
		1:  # twirl: one hand high, the other on the hip, a full spin and a flourish
			var spin := _smooth01((s - 0.5) / 2.4)
			yaw = TAU * spin
			var bob := sin(TAU * s * 2.0)
			j.pelvis = Vector3(0.0, 5.0 * bob, 4.0 * bob)
			j.chest = Vector3(-3.0, -4.0 * bob, -2.0 * bob)
			j.head = Vector3(-6.0, 0.0, 7.0 * sin(TAU * s / 1.6))
			j.l_shoulder = Vector3(-10.0, 0.0, 155.0 + 8.0 * sin(TAU * s * 1.5))
			j.l_elbow = Vector3(-22.0, 0.0, 0.0)
			j.l_wrist = Vector3(0.0, 0.0, 18.0 * sin(TAU * s * 3.0))
			j.r_shoulder = Vector3(8.0, 0.0, -34.0)
			j.r_elbow = Vector3(-105.0, 0.0, 0.0)
			j.l_hip = Vector3(-4.0, 0.0, 2.0)
			j.r_hip = Vector3(6.0, 0.0, -2.0)
			j.l_knee = Vector3(8.0 + 6.0 * absf(bob), 0.0, 0.0)
			j.r_knee = Vector3(14.0 + 6.0 * absf(bob), 0.0, 0.0)
			j.l_ankle = Vector3(-6.0, 0.0, 0.0)
			j.r_ankle = Vector3(-6.0, 0.0, 0.0)
			py = PELVIS_Y + 0.02 + 0.012 * absf(bob)
		2:  # shimmy: fast shoulders, a beckoning hand and a blown kiss
			var shim := sin(TAU * s * 3.5)
			var kiss := _smooth01((s - 2.2) / 0.5) * (1.0 - _smooth01((s - 3.3) / 0.6))
			var dip := sin(TAU * s * 1.75)
			j.pelvis = Vector3(0.0, -6.0 * dip, 6.0 * dip)
			j.spine = Vector3(2.0, 4.0 * shim * 0.5, 0.0)
			j.chest = Vector3(-2.0, 14.0 * shim, 5.0 * shim)
			j.neck = Vector3(0.0, -4.0 * shim, 0.0)
			j.head = Vector3(-2.0 - 6.0 * kiss, 8.0 * sin(TAU * s / 2.0), -10.0 * kiss + 4.0 * dip)
			j.l_shoulder = Vector3(-38.0 + 6.0 * shim, 0.0, 38.0)
			j.l_elbow = Vector3(-62.0 - 22.0 * sin(TAU * s * 1.5), 0.0, 0.0)
			j.l_wrist = Vector3(0.0, 0.0, 16.0 * sin(TAU * s * 3.0))
			j.r_shoulder = Vector3(-22.0 - 62.0 * kiss, 0.0, -48.0 + 34.0 * kiss - 6.0 * shim)
			j.r_elbow = Vector3(-40.0 - 90.0 * kiss, 0.0, 0.0)
			j.r_wrist = Vector3(0.0, 0.0, -10.0 * kiss)
			j.l_hip = Vector3(-4.0, 0.0, 4.0 + 3.0 * dip)
			j.r_hip = Vector3(-4.0, 0.0, -4.0 + 3.0 * dip)
			j.l_knee = Vector3(12.0 + 10.0 * maxf(0.0, dip), 0.0, 0.0)
			j.r_knee = Vector3(12.0 + 10.0 * maxf(0.0, -dip), 0.0, 0.0)
			px = 0.03 * dip
			py = PELVIS_Y - 0.03 - 0.012 * absf(dip)
		3:  # turn around, bend over and shake it, glancing back at the crowd
			var turn := _smooth01((s - 0.2) / 1.2)
			var fold := _smooth01((s - 1.3) / 0.9)
			var shake := sin(TAU * s * 3.0) * fold
			yaw = PI * turn
			j.pelvis = Vector3(fold * 40.0, 16.0 * shake, 11.0 * shake)
			j.spine = Vector3(fold * 20.0, -8.0 * shake, -4.0 * shake)
			j.chest = Vector3(fold * 24.0, -6.0 * shake, 0.0)
			j.neck = Vector3(-fold * 20.0, 0.0, 0.0)
			j.head = Vector3(-fold * 38.0, 34.0 * fold * sin(TAU * s / 3.2), 6.0 * shake)
			j.l_shoulder = Vector3(-fold * 12.0 - 8.0, 0.0, 14.0 + fold * 6.0)
			j.r_shoulder = Vector3(-fold * 12.0 - 8.0, 0.0, -14.0 - fold * 6.0)
			j.l_elbow = Vector3(-12.0 - fold * 10.0, 0.0, 0.0)
			j.r_elbow = Vector3(-12.0 - fold * 10.0, 0.0, 0.0)
			j.l_hip = Vector3(-fold * 38.0 - 2.0, 0.0, 4.0 + 4.0 * shake)
			j.r_hip = Vector3(-fold * 38.0 - 2.0, 0.0, -4.0 + 4.0 * shake)
			j.l_knee = Vector3(8.0 + fold * 14.0, 0.0, 0.0)
			j.r_knee = Vector3(8.0 + fold * 14.0, 0.0, 0.0)
			j.l_ankle = Vector3(-fold * 6.0, 0.0, 0.0)
			j.r_ankle = Vector3(-fold * 6.0, 0.0, 0.0)
			px = 0.035 * shake
			py = PELVIS_Y - 0.1 * fold
		_:  # back-facing body roll, a hand trailing down a thigh, then round to the front
			var w := TAU * s / 1.6
			var round_up := _smooth01((s - 2.5) / 1.4)
			var open := _smooth01((s - 2.7) / 1.0)
			yaw = PI * (1.0 - round_up)
			j.pelvis = Vector3(16.0 * sin(w + 1.0), 14.0 * sin(w), 5.0 * sin(w + 0.5))
			j.spine = Vector3(14.0 * sin(w + 0.2), -5.0 * sin(w), 0.0)
			j.chest = Vector3(14.0 * sin(w - 0.6), -7.0 * sin(w), 3.0 * sin(w))
			j.neck = Vector3(-8.0 * sin(w - 1.0), 0.0, 0.0)
			j.head = Vector3(-4.0, 46.0 * (1.0 - open) + 6.0 * sin(w), 8.0 * sin(w - 0.8))
			j.l_shoulder = Vector3(lerpf(8.0, -20.0, open), 0.0, lerpf(24.0, 75.0, open))
			j.l_elbow = Vector3(lerpf(-24.0, -20.0, open), 0.0, 0.0)
			j.r_shoulder = Vector3(-14.0, 0.0, lerpf(-150.0, -75.0, open) - 8.0 * sin(w))
			j.r_elbow = Vector3(-28.0, 0.0, 0.0)
			j.r_wrist = Vector3(0.0, 0.0, -12.0 * sin(w * 2.0))
			j.l_hip = Vector3(-6.0 - 8.0 * maxf(0.0, sin(w + 1.0)), 0.0, 4.0)
			j.r_hip = Vector3(-6.0 - 8.0 * maxf(0.0, -sin(w + 1.0)), 0.0, -4.0)
			j.l_knee = Vector3(12.0 + 8.0 * maxf(0.0, sin(w + 1.0)), 0.0, 0.0)
			j.r_knee = Vector3(12.0 + 8.0 * maxf(0.0, -sin(w + 1.0)), 0.0, 0.0)
			px = 0.04 * sin(w)
			py = PELVIS_Y - 0.04 + 0.02 * cos(w * 2.0)
	return { "joints": j, "pelvis_y": py, "pelvis_x": px, "yaw": yaw }


static func _smooth01(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _target(inp: Dictionary, speed: float, crouch: bool, vy: float) -> Dictionary:
	if bool(inp.get("dance", false)):
		return dance_pose(dance_time)
	if str(inp.get("perform", "")) != "":
		return ClubMoves.pose(str(inp.perform), perform_time, float(inp.get("bpm", 110.0)))
	var j := {}
	for n in JOINTS:
		j[n] = Vector3.ZERO
	var py := PELVIS_Y
	var px := 0.0
	var s := sin(phase)
	var c := cos(phase)
	var walk01 := clampf(speed / WALK_SPEED, 0.0, 1.0)
	var run01 := clampf((speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	var dash01 := clampf((speed - RUN_SPEED) / (SPRINT_SPEED - RUN_SPEED), 0.0, 1.0)
	var move: Vector2 = inp.get("move_local", Vector2(0, 1))
	if move.length() < 0.01:
		move = Vector2(0, 1)
	move = move.normalized()
	var fwd := move.y          # cos of the move angle in the body frame
	var side := move.x         # + = toward the model's left

	match state:
		State.LOCOMOTION:
			# Issue #133: three gaits on one curve.
			#   walk:   long easy steps, heel first, knees nearly straight, a little
			#           hip sway (issue #87's swagger, toned down) and loose arms.
			#   run:    a light jog; slight lean, the body bounces up between steps
			#           and the arms bend to about 80 degrees.
			#   sprint: a hard forward lean, high knee drive in front, a high kick
			#           behind and arms pumping with the elbows locked near 90.
			# Issue #632: `g` is how much the body is walking at all (full by 1 m/s, so a
			# slow amble still swings its arms and shifts its weight); walk01 is how far
			# up the walk's pace it is.
			var g := clampf(speed / 1.0, 0.0, 1.0)
			var strut := g * (1.0 - run01)
			var gait := gait_legs(phase, gait_speed, fwd, side, pelvis_y, _dt, j)
			py = gait.pelvis_y
			# Leg forwardness: + while the left leg is ahead (its heel lands at phase 0
			# and it leaves the ground at the duty), so the hips, chest and arms turn
			# with the steps the feet actually take.
			var sw := cos(phase - PI * (gait_duty(gait_speed) - 0.5))
			var stance_mid := cos(phase - PI * gait_duty(gait_speed))   # + over the left foot
			px = 0.026 * strut * stance_mid
			j.pelvis = Vector3(0, -g * (4.0 + 4.0 * walk01) * sw, 3.0 * strut * stance_mid)
			j.spine = Vector3(8.0 * run01 + 12.0 * dash01, 0, -1.5 * strut * stance_mid)
			j.chest = Vector3(3.0 * walk01 + 4.0 * run01 + 6.0 * dash01, g * (6.0 + 5.0 * walk01) * sw,
				-1.0 * strut * stance_mid)
			j.head = Vector3(-3.0 * walk01 - 6.0 * run01 - 12.0 * dash01, -g * (2.0 + walk01) * sw,
				-1.5 * strut * stance_mid)
			# Arms counter-swing the legs: loose from the shoulder on a walk (the
			# forearm swings up a touch on the way forward), bent on the run, pumping
			# hard on the sprint.
			var arm_a := g * (12.0 + 12.0 * walk01) + 18.0 * run01 + 30.0 * dash01
			var bend := 18.0 * strut
			var elbow := -14.0 - 8.0 * walk01 - 55.0 * run01 - 20.0 * dash01
			var arm_out := 9.0 + 3.0 * strut - 3.0 * dash01
			j.l_shoulder = Vector3(arm_a * sw, 4.0 * strut * sw, arm_out)
			j.r_shoulder = Vector3(-arm_a * sw, 4.0 * strut * sw, -arm_out)
			j.l_elbow = Vector3(elbow - bend * maxf(0.0, -sw), 0, 0)
			j.r_elbow = Vector3(elbow - bend * maxf(0.0, sw), 0, 0)
			j.l_wrist = Vector3(-6.0 * walk01, 0, 0)
			j.r_wrist = Vector3(-6.0 * walk01, 0, 0)
			# Idle: breathe, shift the weight from foot to foot and glance around.
			var idle := 1.0 - g
			var sway := sin(time * 0.55)
			j.chest.x += idle * 1.5 * sin(time * 1.7)
			j.l_shoulder.z += idle * 0.8 * sin(time * 1.7)
			j.r_shoulder.z -= idle * 0.8 * sin(time * 1.7)
			px += idle * 0.018 * sway
			j.pelvis.z += idle * 2.5 * sway
			j.chest.z -= idle * 2.0 * sway
			j.l_knee.x += idle * 5.0 * maxf(0.0, -sway)
			j.r_knee.x += idle * 5.0 * maxf(0.0, sway)
			j.head.y += idle * 14.0 * sin(time * 0.31) * sin(time * 0.17)
			j.head.x += idle * 3.0 * sin(time * 0.23)
			if crouch:
				var pose := _crouch(inp, speed, s, c, fwd)
				for n in pose.joints:
					j[n] = pose.joints[n]
				py = pose.pelvis_y
				px = 0.0
		State.AIRBORNE:
			# Tucked on the way up, legs reaching for the ground and arms out on the
			# way down; a running jump splits the legs into a leap.
			var up01 := clampf(vy / 5.0, 0.0, 1.0)
			var down01 := clampf(-vy / 6.0, 0.0, 1.0)
			var leap := clampf(speed / WALK_SPEED, 0.0, 1.0)
			j.l_hip = Vector3(-30.0 - 25.0 * up01 - 25.0 * leap, 0, 5)
			j.r_hip = Vector3(-5.0 - 15.0 * up01 + 30.0 * leap - 10.0 * down01, 0, -5)
			j.l_knee = Vector3(30.0 + 50.0 * up01 - 15.0 * down01, 0, 0)
			j.r_knee = Vector3(25.0 + 30.0 * up01 + 35.0 * leap - 10.0 * down01, 0, 0)
			j.l_ankle = Vector3(-15.0 + 10.0 * down01, 0, 0)
			j.r_ankle = Vector3(10.0 * leap, 0, 0)
			j.l_shoulder = Vector3(-35.0 * up01 + 20.0 * leap, 0, 25.0 + 30.0 * down01)
			j.r_shoulder = Vector3(-35.0 * up01 - 30.0 * leap, 0, -25.0 - 30.0 * down01)
			j.l_elbow = Vector3(-40.0 + 15.0 * down01, 0, 0)
			j.r_elbow = Vector3(-50.0 + 15.0 * down01, 0, 0)
			j.spine = Vector3(6.0 * leap, 0, 0)
			j.chest = Vector3(10.0 * up01 - 4.0 * down01, 0, 0)
			j.head = Vector3(-6.0 + 10.0 * down01, 0, 0)
		State.LAND:
			var dip := clampf(land_left / land_time, 0.0, 1.0)
			j.l_hip = Vector3(-35.0 * dip, 0, 3)
			j.r_hip = Vector3(-30.0 * dip, 0, -3)
			j.l_knee = Vector3(60.0 * dip, 0, 0)
			j.r_knee = Vector3(55.0 * dip, 0, 0)
			j.l_ankle = Vector3(-25.0 * dip, 0, 0)
			j.r_ankle = Vector3(-25.0 * dip, 0, 0)
			j.chest = Vector3(12.0 * dip, 0, 0)
			j.l_shoulder = Vector3(0, 0, 20.0 * dip + 6.0)
			j.r_shoulder = Vector3(0, 0, -20.0 * dip - 6.0)
			py = PELVIS_Y - 0.18 * dip

	# ---- sprint slide: lead leg out straight, the other tucked under, torso leaning
	# back, pelvis near the ground, one arm out for balance.
	if slide_w > 0.0 and state == State.LOCOMOTION:
		var sl := {
			"pelvis": Vector3(0, 0, 0), "spine": Vector3(0, 0, 0),
			"chest": Vector3(-22.0, 0, 0), "neck": Vector3(0, 0, 0), "head": Vector3(14.0, 0, 0),
			"l_hip": Vector3(-82.0, 0, 3), "l_knee": Vector3(6.0, 0, 0), "l_ankle": Vector3(-20.0, 0, 0),
			"r_hip": Vector3(-30.0, 0, -6), "r_knee": Vector3(115.0, 0, 0), "r_ankle": Vector3(-25.0, 0, 0),
			"l_shoulder": Vector3(-30.0, 0, 20.0), "l_elbow": Vector3(-35.0, 0, 0), "l_wrist": Vector3.ZERO,
			"r_shoulder": Vector3(-10.0, 0, -75.0), "r_elbow": Vector3(-10.0, 0, 0), "r_wrist": Vector3.ZERO,
		}
		for n in sl:
			j[n] = (j[n] as Vector3).lerp(sl[n], slide_w)
		py = lerpf(py, PELVIS_Y - 0.5, slide_w)
		px = lerpf(px, 0.0, slide_w)

	# ---- upper body overrides for weapons. Arms are placed by IK afterwards
	# (player_avatar.gd, npc_body.gd), so here we only shape the torso. Issue #87:
	# "ready" is how far the weapon is up (1 = aimed, 0 = resting low), so a body
	# at rest keeps its walk's swagger and only squares up to aim.
	var upper: String = inp.get("upper", UPPER_FREE)
	var ready := clampf(float(inp.get("ready", 1.0)), 0.0, 1.0)
	var pitch_deg := rad_to_deg(float(inp.get("aim_pitch", 0.0)))
	if upper != UPPER_FREE:
		# Stop the walk's shoulder twist so the weapon stays on the aim line.
		# At rest a two-handed carry still damps the twist, or the gun swings about.
		j.pelvis.y *= lerpf(0.7, 0.3, ready)
		j.chest.y *= lerpf(0.35, 0.0, ready)
		j.head.y *= 1.0 - ready
	match upper:
		UPPER_AIM, UPPER_RIFLE:
			j.chest.x = lerpf(j.chest.x * 0.6 + 2.0, -pitch_deg * 0.55 + 4.0, ready)
			j.head.x = lerpf(j.head.x, -pitch_deg * 0.35, ready)
			j.spine.y = (-8.0 if upper == UPPER_AIM else -14.0) * ready
		UPPER_SWORD, UPPER_HOLSTER:
			j.chest.x = j.chest.x * 0.5 - pitch_deg * 0.3 + 6.0
			j.head.x = -pitch_deg * 0.3
	j.chest.y += float(inp.get("twist", 0.0))
	if slide_w > 0.0 and upper != UPPER_FREE:
		j.chest.x -= 14.0 * slide_w  # weapon up: still lean back, the aim pass keeps the hands
	return { "joints": j, "pelvis_y": py, "pelvis_x": px }


# ------------------------------------------------------------------ ladders

## Climbing (LadderClimb): the body hangs Ladders.STAND back from the rungs, its
## feet `u` metres up from the ladder's foot. One cycle is two rungs: each foot
## stands on a rung while the body rises past it, then lifts off and steps up two;
## the opposite hand reaches up as that foot does (left hand with right foot), and
## pulls down past the shoulder while it holds. The feet are placed by the same leg
## IK as the walk (leg_ik), so their boots sit on the rungs; the arms are angles.
const CLIMB_RUNG := 0.35            ## rung spacing (m): a cycle is two
const CLIMB_REACH := 0.4            ## ankle ahead of the hips: the ball of the boot on the rung
const CLIMB_PELVIS := 0.86          ## hips over the lower foot's rung (knees bent)
const CLIMB_SMOOTH := 40.0          ## joint smoothing per second while on a ladder
const CLIMB_FOOT_LO := 0.05         ## a foot's rung, over the body's feet: as it leaves it
const CLIMB_FOOT_HI := 0.4          ## and as it lands on the next but one

## { joints, pelvis_y, pelvis_x } for feet `u` m up the ladder, `slide` (0..1: hands
## and boots on the rails, legs out round them) and `over` (0..1: climbing out over
## the top, a knee on the lip and both hands pushing on the floor).
static func climb_pose(u: float, slide: float = 0.0, over: float = 0.0) -> Dictionary:
	var j := {}
	for jn in JOINTS:
		j[jn] = Vector3.ZERO
	var p := fposmod(u / (2.0 * CLIMB_RUNG), 1.0)
	var py := CLIMB_PELVIS
	var hip_y := py + HIP_Y
	for leg in ["l", "r"]:
		var q := fposmod(p + (0.0 if leg == "l" else 0.5), 1.0)
		var rel: float
		var back := 0.0
		if q < 0.5:
			rel = CLIMB_FOOT_HI - q * 2.0 * CLIMB_RUNG             # stood on: the body rises past it
		else:
			var e := _smooth01((q - 0.5) / 0.5)
			rel = lerpf(CLIMB_FOOT_LO, CLIMB_FOOT_HI, e)
			back = 0.12 * sin(PI * e)                                # off the rung and up
		var ik := leg_ik(CLIMB_REACH - back, rel + ANKLE_ABOVE_SOLE - hip_y)
		j[leg + "_hip"] = Vector3(ik.x, 0, 3.0 if leg == "l" else -3.0)
		j[leg + "_knee"] = Vector3(ik.y, 0, 0)
		j[leg + "_ankle"] = Vector3(-ik.x - ik.y, 0, 0)            # boots flat on the rungs
	for arm in ["l", "r"]:
		var q := fposmod(p + (0.5 if arm == "l" else 0.0), 1.0)   # the left hand goes with the right foot
		var reach: float
		var out := 0.0
		if q < 0.5:
			reach = 1.0 - q * 2.0                                    # holding: pulled down toward the shoulder
		else:
			var e := _smooth01((q - 0.5) / 0.5)
			reach = e
			out = 8.0 * sin(PI * e)                                  # a little out round the rung on the way up
		var sgn := 1.0 if arm == "l" else -1.0
		j[arm + "_shoulder"] = Vector3(lerpf(-108.0, -160.0, reach), 0, sgn * (11.0 + out))
		j[arm + "_elbow"] = Vector3(lerpf(-78.0, -12.0, reach), 0, 0)
	var sw := sin(TAU * p)
	j.pelvis = Vector3(0, 4.0 * sw, 0)
	j.spine = Vector3(3.0, 0, 0)
	j.chest = Vector3(2.0, -3.0 * sw, 0)
	j.head = Vector3(-14.0, 0, 0)                                    # eyes up the ladder
	var px := 0.015 * sw
	if slide > 0.0:
		var s := {}
		var ik := leg_ik(0.3, 0.12 + ANKLE_ABOVE_SOLE - hip_y)
		s.l_hip = Vector3(ik.x, 0, 16.0)
		s.r_hip = Vector3(ik.x, 0, -16.0)                            # legs out round the rails
		s.l_knee = Vector3(ik.y, 0, 0)
		s.r_knee = Vector3(ik.y, 0, 0)
		s.l_ankle = Vector3(-ik.x - ik.y - 20.0, 0, 0)
		s.r_ankle = Vector3(-ik.x - ik.y - 20.0, 0, 0)
		s.l_shoulder = Vector3(-128.0, 0, 15.0)                       # hands loose on the rails
		s.r_shoulder = Vector3(-128.0, 0, -15.0)
		s.l_elbow = Vector3(-36.0, 0, 0)
		s.r_elbow = Vector3(-36.0, 0, 0)
		s.pelvis = Vector3.ZERO
		s.spine = Vector3(-4.0, 0, 0)
		s.chest = Vector3(-6.0, 0, 0)
		s.head = Vector3(18.0, 0, 0)                                 # looking down where you are going
		for jn in s:
			j[jn] = (j[jn] as Vector3).lerp(s[jn], slide)
		px = lerpf(px, 0.0, slide)
	if over > 0.0:
		var o := {
			"pelvis": Vector3.ZERO, "spine": Vector3(14.0, 0, 0), "chest": Vector3(32.0, 0, 0), "head": Vector3(-20.0, 0, 0),
			"l_hip": Vector3(-100.0, 0, 6.0), "l_knee": Vector3(115.0, 0, 0), "l_ankle": Vector3(-15.0, 0, 0),
			"r_hip": Vector3(-12.0, 0, -4.0), "r_knee": Vector3(40.0, 0, 0), "r_ankle": Vector3(-25.0, 0, 0),
			"l_shoulder": Vector3(-40.0, 0, 12.0), "l_elbow": Vector3(-30.0, 0, 0),
			"r_shoulder": Vector3(-40.0, 0, -12.0), "r_elbow": Vector3(-30.0, 0, 0),
		}
		for jn in o:
			j[jn] = (j[jn] as Vector3).lerp(o[jn], over)
		py = lerpf(py, 0.8, over)
		px = lerpf(px, 0.0, over)
	return { "joints": j, "pelvis_y": py, "pelvis_x": px }


## Issue #87: crouched. Still, down on the right knee with the left foot planted
## ahead; moving, a low duck walk (deep knees, short steps, torso forward). Leg
## angles are set so the feet and the knee land on the ground for CharacterKit's
## 0.46 / 0.43 m thigh and shin.
func _crouch(_inp: Dictionary, speed: float, s: float, c: float, fwd: float) -> Dictionary:
	var kneel := {
		"pelvis": Vector3(0, 6, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(6, -4, 0), "head": Vector3(-6, 0, 0),
		"l_hip": Vector3(-86, 0, 8), "l_knee": Vector3(88, 0, 0), "l_ankle": Vector3(-2, 0, 0),
		"r_hip": Vector3(2, 0, -6), "r_knee": Vector3(92, 0, 0), "r_ankle": Vector3(-25, 0, 0),
		"l_shoulder": Vector3(-14, 0, 6), "l_elbow": Vector3(-55, 0, 0), "l_wrist": Vector3.ZERO,
		"r_shoulder": Vector3(4, 0, -10), "r_elbow": Vector3(-20, 0, 0), "r_wrist": Vector3.ZERO,
	}
	var step_a := 18.0 * fwd
	var duck := {
		"pelvis": Vector3(0, -5.0 * s, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(16, 5.0 * s, 0), "head": Vector3(-18, 0, 0),
		"l_hip": Vector3(-58.0 - step_a * s, 0, 8), "l_knee": Vector3(92.0 + 14.0 * maxf(0.0, c), 0, 0),
		"l_ankle": Vector3(-34.0, 0, 0),
		"r_hip": Vector3(-58.0 + step_a * s, 0, -8), "r_knee": Vector3(92.0 + 14.0 * maxf(0.0, -c), 0, 0),
		"r_ankle": Vector3(-34.0, 0, 0),
		"l_shoulder": Vector3(14.0 * s - 10.0, 0, 14), "l_elbow": Vector3(-40, 0, 0), "l_wrist": Vector3.ZERO,
		"r_shoulder": Vector3(-14.0 * s - 10.0, 0, -14), "r_elbow": Vector3(-40, 0, 0), "r_wrist": Vector3.ZERO,
	}
	var m := clampf(speed / 1.2, 0.0, 1.0)
	var j := {}
	for n in kneel:
		j[n] = (kneel[n] as Vector3).lerp(duck[n], m)
	var py := lerpf(PELVIS_Y - 0.44, PELVIS_Y - 0.31 - 0.02 * s * s, m)
	return { "joints": j, "pelvis_y": py }
