class_name CrashPath
extends RefCounted
## Issue #404: where a destroyed vehicle is while it falls, as pure maths (the
## wreck node, CrashWreck, only plays it). From a start pose it keeps its speed
## along the ground (bleeding off with `drag`), pops up by `hop_m_s` and falls
## with `gravity`, rolls round its nose at `spin_deg_s` and drops its nose at
## `pitch_deg_s` (to 60 degrees). It stops where it meets the sand: the pose at
## and after impact sits exactly on the ground, and no pose is ever below it.
##
## start: { pos: Vector3, basis: Basis, vel: Vector3, up: Vector3 }
## ground: Callable(p: Vector3) -> Vector3, the sand point under p (along up).
## cfg: the crash numbers (content/look/crash.json, `for_kind`).

const CFG_PATH := "res://content/look/crash.json"
const STEP := 1.0 / 60.0
const MAX_PITCH := 1.0471975512     ## 60 degrees

static var _cfg: Dictionary = {}


## The numbers for one kind ("speeder", "ship", "barge"): its block over "default".
static func for_kind(kind: String) -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(CFG_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg = d if d is Dictionary else { "default": {} }
	var out: Dictionary = (_cfg.get("default", {}) as Dictionary).duplicate()
	var own: Dictionary = _cfg.get(kind, {})
	for k in own:
		out[k] = own[k]
	return out


## Where it would be at `t` seconds if the ground were not there.
static func free_pose(start: Dictionary, t: float, cfg: Dictionary) -> Transform3D:
	var up: Vector3 = (start.get("up", Vector3.UP) as Vector3).normalized()
	var vel: Vector3 = start.get("vel", Vector3.ZERO)
	var v_up := vel.dot(up)
	var v_flat := vel - up * v_up
	var drag := maxf(0.001, float(cfg.get("drag", 0.35)))
	var along := v_flat * (1.0 - exp(-drag * t)) / drag
	var rise := (v_up + float(cfg.get("hop_m_s", 0.0))) * t - 0.5 * float(cfg.get("gravity", 14.0)) * t * t
	var pos: Vector3 = (start.get("pos", Vector3.ZERO) as Vector3) + along + up * rise
	var b: Basis = (start.get("basis", Basis.IDENTITY) as Basis).orthonormalized()
	var nose := -b.z
	var roll := deg_to_rad(float(cfg.get("spin_deg_s", 0.0))) * t
	var pitch := minf(MAX_PITCH, deg_to_rad(float(cfg.get("pitch_deg_s", 0.0))) * t)
	b = Basis(b.x.normalized(), -pitch) * b
	b = Basis(nose.normalized(), roll) * b
	return Transform3D(b, pos)


## Height over the sand of a point (negative = under it).
static func height(p: Vector3, up: Vector3, ground: Callable) -> float:
	var g: Vector3 = ground.call(p)
	return (p - g).dot(up)


## When it meets the sand (seconds), at most cfg.max_fall_s.
static func impact_time(start: Dictionary, cfg: Dictionary, ground: Callable) -> float:
	var up: Vector3 = (start.get("up", Vector3.UP) as Vector3).normalized()
	var limit := float(cfg.get("max_fall_s", 12.0))
	var t := 0.0
	if height(free_pose(start, 0.0, cfg).origin, up, ground) <= 0.0:
		return 0.0
	while t < limit:
		var nt := minf(limit, t + STEP)
		if height(free_pose(start, nt, cfg).origin, up, ground) <= 0.0:
			var lo := t
			var hi := nt
			for i in 10:
				var mid := (lo + hi) * 0.5
				if height(free_pose(start, mid, cfg).origin, up, ground) <= 0.0:
					hi = mid
				else:
					lo = mid
			return hi
		t = nt
	return limit


## The pose at `t`: { xf: Transform3D, landed: bool }. From `t_impact` on it is the
## impact pose, its origin on the sand.
static func pose(start: Dictionary, t: float, cfg: Dictionary, ground: Callable, t_impact := -1.0) -> Dictionary:
	var ti := t_impact if t_impact >= 0.0 else impact_time(start, cfg, ground)
	var landed := t >= ti
	var xf := free_pose(start, minf(t, ti), cfg)
	var up: Vector3 = (start.get("up", Vector3.UP) as Vector3).normalized()
	if landed or height(xf.origin, up, ground) < 0.0:
		xf.origin = ground.call(xf.origin)
	return { "xf": xf, "landed": landed }
