class_name BeltWrecks
extends RefCounted
## Issue #317: the wrecked cruisers adrift in the belt under a station, laid out
## from the station's "belt" block (content/core/stations/<id>.json): stacked one
## under another, 50 to 100 m apart and never touching, each at its own heading,
## dive and list. The first hangs nose down under the engine deck's drop hatch
## like the home planet's nearest wreck in the sand (its bow sinks into the clouds).
## Every one is the desert's wreck (StarcruiserWreck) with "adrift": no sand, so
## no boarding plate, no salvage at its foot and no speeder kicker; posed by its
## own frame instead of a map point.
##
## Each is placed by its landing pad (the bridge platform, level whatever the
## pose: the same design every desert wreck has): the first pad drop_m under the
## hatch, each next one drop_m under the last and shift metres across. You go
## down on foot, from one to the next, with a jetpack burn to land softly
## (landing_speed works out the softest landing the jetpack item allows from a
## drop); you come back up by calling your ship down to a pad.
##
## Everything here is pure: the station's frame and its hull in, landmarks and
## numbers out. SpaceStation uses in_wreck() and lost() for the fall.

const FallDamage := preload("res://src/systems/combat/fall_damage.gd")
const GRAVITY := 20.0              ## character_controller.gd's gravity
const BOX_HALF := Vector3(47.0, 40.0, 302.0)   ## a wreck's hull, its plating and a little, in its own frame
const ENGINES_OUT := 32.0          ## how far the engine bells stand past the stern


## The station's belt block, or {} (no belt under this station).
static func cfg_of(hull: StationHull) -> Dictionary:
	return hull.cfg.get("belt", {}) if hull != null else {}


## Where a wreck's landing pad is, in its interior's design coordinates (the
## "level" frame: x, height v, stern-ward w): the bridge platform's open end, past
## the bridge house.
static func pad_design(hull: StationHull) -> Vector3:
	var p: Array = cfg_of(hull).get("pad", [0, StarcruiserWreck.BRIDGE_V, 138])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


## The wrecks of the belt as "wreck" landmarks in the world: { id, kind: wreck,
## frame (the hull's world transform), adrift, pitch_deg, roll_deg, variant }.
## `station_xf`: the station's frame.
static func landmarks(hull: StationHull, station_xf: Transform3D) -> Array:
	var out: Array = []
	for w in layout(hull):
		var lm: Dictionary = (w.spec as Dictionary).duplicate(true)
		lm.erase("note")
		lm["kind"] = "wreck"
		lm["adrift"] = true
		lm["frame"] = station_xf * (w.xf as Transform3D)
		out.append(lm)
	return out


## The belt laid out in the station's own frame: per wreck { id, spec, xf (its
## hull frame: x to starboard, y up, z to the stern, pitched and listed), level
## (its interior's frame: StarcruiserWreck.frame's "level"), pad (the middle of
## its landing pad), box_half, engines }.
## The hatch's frame (x out along its room, z across) carries the numbers: each
## wreck's yaw_deg turns its stern from straight out; shift is [out, across] from
## the pad (or hatch) before.
static func layout(hull: StationHull) -> Array:
	var bc := cfg_of(hull)
	var list: Array = bc.get("wrecks", [])
	var hatch := hull.drop_hatch() if hull != null else {}
	if list.is_empty() or hatch.is_empty():
		return []
	var hx: Transform3D = hatch.xf
	var out_dir := Vector3(hx.basis.x.x, 0, hx.basis.x.z).normalized()
	var across := Vector3(hx.basis.z.x, 0, hx.basis.z.z).normalized()
	var pad_d := pad_design(hull)
	var at: Vector3 = hatch.at
	var out: Array = []
	for i in list.size():
		var spec: Dictionary = list[i]
		var sh: Array = spec.get("shift", [0, 0])
		at += out_dir * float(sh[0]) + across * float(sh[1]) - Vector3.UP * float(spec.get("drop_m", 60.0))
		var dir := out_dir.rotated(Vector3.UP, deg_to_rad(float(spec.get("yaw_deg", 0.0))))
		var pitch := float(spec.get("pitch_deg", 0.0))
		var variant: Dictionary = spec.get("variant", {})
		var pose := StarcruiserWreck.Pose.new(pitch, float(variant.get("deck_drop", 0.0)))
		# The interior's level frame: heading, then the list; the hull is that pitched.
		var tangent := Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP, dir) \
			* Basis(Vector3.BACK, deg_to_rad(float(spec.get("roll_deg", 0.0))))
		var inside := pad_d + Vector3(0, pose.shift.x, pose.shift.y)
		var origin := at - tangent * inside
		var xf := Transform3D(tangent * Basis(Vector3.RIGHT, deg_to_rad(pitch)), origin)
		var skip: Array = variant.get("skip", [])
		var half := BOX_HALF
		if not skip.has("engine_"):
			half.z += ENGINES_OUT * 0.5
		out.append({ "id": str(spec.get("id", "belt_wreck_%d" % (i + 1))), "spec": spec, "xf": xf,
			"level": Transform3D(tangent, origin) * Transform3D(Basis.IDENTITY, Vector3(0, pose.shift.x, pose.shift.y)),
			"pad": at, "box_half": half, "engines": not skip.has("engine_") })
	return out


## Where the station's up holds round wreck `w` (PlanetSphere.add_gravity_zone): a
## level frame at its middle, turned with its heading but not its dive or list, so
## a wreck lying over still has the station's up, not its own.
static func zone_frame(w: Dictionary) -> Transform3D:
	var xf: Transform3D = w.xf
	var z := xf.basis.z
	z = Vector3(z.x, 0.0, z.z).normalized()
	return Transform3D(Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z), xf.origin)


## The box of that zone: the hull's box as it lies, and a margin all round.
static func zone_box(w: Dictionary, margin: float = 30.0) -> AABB:
	var inv := zone_frame(w).affine_inverse() * (w.xf as Transform3D)
	var h: Vector3 = w.box_half
	var box := AABB()
	for k in 8:
		var c := inv * Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z)
		box = AABB(c, Vector3.ZERO) if k == 0 else box.expand(c)
	return box.grow(margin)


# ------------------------------------------------------------------ going down

## The softest landing (m/s straight down) a jump off an edge `drop` metres over
## a floor can make with a full tank: falling, then the whole tank burned at the
## last moment it still helps. Stepped like the game (60 a second), from the
## jetpack item's "jetpack" block and falls.json's terminal_speed.
static func landing_speed(drop: float, jet_cfg: Dictionary, terminal: float = 45.0, dt: float = 1.0 / 60.0) -> float:
	return best_burn(drop, jet_cfg, terminal, dt).y


## The softest landing from `drop`: Vector2(how high over the floor to start
## holding jump, the landing speed then).
static func best_burn(drop: float, jet_cfg: Dictionary, terminal: float = 45.0, dt: float = 1.0 / 60.0) -> Vector2:
	var best := Vector2(0.0, INF)
	var h := 0.0
	while h <= drop:
		var v := _land_lighting_at(drop, h, jet_cfg, terminal, dt)
		if v < best.y:
			best = Vector2(h, v)
		h += 1.0
	return best


## One try: fall from `drop` over the floor, holding jump once `light_at` metres
## over it (the pack lights after its kick-in); the speed as it touches down.
static func _land_lighting_at(drop: float, light_at: float, jet_cfg: Dictionary, terminal: float, dt: float) -> float:
	var jet = load("res://src/systems/player/jetpack.gd").new(jet_cfg)
	var y := drop
	var v := 0.0
	for i in 6000:
		var held := y <= light_at
		var lift: float = jet.step(dt, held, false)
		v += (lift - GRAVITY) * dt
		if lift > 0.0:
			v = minf(v, float(jet.max_rise()))
		if terminal > 0.0:
			v = maxf(v, -terminal)
		y += v * dt
		if y <= 0.0:
			return maxf(0.0, -v)
	return 0.0


## Every drop the belt asks of you, { what, drop }: from the hatch down to the
## first pad, then from each pad down to the next.
static func drops(hull: StationHull) -> Array:
	var ws := layout(hull)
	var out: Array = []
	var from: Vector3 = hull.drop_hatch().get("at", Vector3.ZERO)
	var what := "the hatch"
	for w in ws:
		out.append({ "what": "%s down to %s" % [what, w.id], "drop": from.y - (w.pad as Vector3).y })
		from = w.pad
		what = str(w.id)
	return out


## The drops a full tank cannot land from without more than the belt's
## landing.max_damage (falls.json's sums, FallDamage). Empty when every one is fine.
static func too_hard(hull: StationHull, jet_cfg: Dictionary, falls: Dictionary) -> Array:
	var cap := int(cfg_of(hull).get("landing", {}).get("max_damage", 30))
	var out: Array = []
	for d in drops(hull):
		var v := landing_speed(float(d.drop), jet_cfg, float(falls.get("terminal_speed", 45.0)))
		var dmg := FallDamage.damage(v, falls)
		if dmg > cap:
			out.append("%s: %.0f m, lands at %.1f m/s at best (%d damage, %d allowed)" % [d.what, d.drop, v, dmg, cap])
	return out


# ------------------------------------------------------------------ the fall

## Inside (or on) one of the wrecks: its hull's box in the station's frame.
static func in_wreck(ws: Array, local: Vector3, grow: float = 0.0) -> bool:
	for w in ws:
		var l := (w.xf as Transform3D).affine_inverse() * local
		var h: Vector3 = (w.box_half as Vector3) + Vector3.ONE * grow
		if absf(l.x) <= h.x and absf(l.y) <= h.y and absf(l.z) <= h.z:
			return true
	return false


## Over the belt: within `margin` metres, across, of a wreck as it lies (its box
## seen from above, in the station's frame).
static func over_belt(ws: Array, local: Vector3, margin: float) -> bool:
	for w in ws:
		var l := zone_frame(w).affine_inverse() * local
		var b := zone_box(w, margin)
		if l.x >= b.position.x and l.x <= b.end.x and l.z >= b.position.z and l.z <= b.end.z:
			return true
	return false


## Lost to the belt at station point `local`: down in the clouds (under clouds_y,
## inside a hull or not), or out of every hull and fall_m under the lowest pad.
static func lost(ws: Array, bc: Dictionary, local: Vector3) -> bool:
	if local.y < float(bc.get("clouds_y", -300.0)):
		return true
	return local.y < lost_below(ws, float(bc.get("fall_m", 25.0))) and not in_wreck(ws, local)


## The height (station frame) under which a body out of every hull is lost:
## fall_m under the lowest pad.
static func lost_below(ws: Array, fall_m: float) -> float:
	var y := INF
	for w in ws:
		y = minf(y, (w.pad as Vector3).y)
	return y - fall_m


## Whether a ship can come straight down onto wreck `i`'s pad: nothing of another
## wreck in a column `radius` wide over it, up to the station's top, and not under
## the station (StationHull.under).
static func pad_open(hull: StationHull, ws: Array, i: int, radius: float = 14.0) -> bool:
	var p: Vector3 = ws[i].pad
	var others := ws.filter(func(w): return w != ws[i])
	var y := p.y + 12.0
	while y < hull.top_y() + 40.0:
		for off in [Vector3.ZERO, Vector3(radius, 0, 0), Vector3(-radius, 0, 0), Vector3(0, 0, radius), Vector3(0, 0, -radius)]:
			var q: Vector3 = Vector3(p.x, y, p.z) + off
			if in_wreck(others, q, 4.0) or hull.under(q, 10.0):
				return false
		y += 6.0
	return true


## How close two wrecks come: the least distance from a corner of one hull's box
## to the other's box, both ways (0 when they touch). Boxes, so it errs short.
static func gap_between(a: Dictionary, b: Dictionary) -> float:
	return minf(_corner_gap(a, b), _corner_gap(b, a))


static func _corner_gap(a: Dictionary, b: Dictionary) -> float:
	var to_b := (b.xf as Transform3D).affine_inverse() * (a.xf as Transform3D)
	var ha: Vector3 = a.box_half
	var hb: Vector3 = b.box_half
	var best := INF
	# A grid over a's box (5 across, 5 up, 31 along), against b's box.
	for i in 5:
		for j in 5:
			for k in 31:
				var p := to_b * Vector3(ha.x * (i / 2.0 - 1.0), ha.y * (j / 2.0 - 1.0), ha.z * (k / 15.0 - 1.0))
				var d := Vector3(maxf(absf(p.x) - hb.x, 0.0), maxf(absf(p.y) - hb.y, 0.0), maxf(absf(p.z) - hb.z, 0.0))
				best = minf(best, d.length())
	return best
