class_name BeltWrecks
extends RefCounted
## Issue #317: the wrecked cruisers adrift in the belt under a station, laid out
## from the station's "belt" block (content/core/stations/<id>.json) like stairs:
## the first one's spine 12 m under the engine deck's drop hatch, each next one
## lower again across a small gap, end to end. Every one is the desert's wreck
## (StarcruiserWreck) with "adrift": no sand, so no boarding plate, no salvage at
## its foot and no speeder kicker; posed by its own frame instead of a map point.
##
## The joints are the point: the jetpack has to carry you up every one of them, so
## the step and the gap are data, and reach() works out how high a jump with a full
## tank climbs from the jetpack item's own numbers (content/core/items/jetpack.json):
## a jetpack change that makes one joint too tall fails tests/test_belt_wrecks.
##
## Everything here is pure: the station's frame and its hull in, landmarks and
## numbers out. SpaceStation uses in_wreck() and below_belt() for the fall.

const JUMP_HEIGHT := 0.6           ## character_controller.gd: a jump is sqrt(2 g 0.6)
const GRAVITY := 20.0              ## character_controller.gd's gravity
const BOX_HALF := Vector3(47.0, 40.0, 302.0)   ## a wreck's hull, its plating and a little, in its own frame
const ENGINES_OUT := 32.0          ## how far the engine bells stand past the stern


## The station's belt block, or {} (no belt under this station).
static func cfg_of(hull: StationHull) -> Dictionary:
	return hull.cfg.get("belt", {}) if hull != null else {}


## The wrecks of the belt as "wreck" landmarks in the world: { id, kind, frame
## (the hull's world transform), adrift, variant, top (station frame: the highest
## point you can stand on, near and far end) }. `station_xf`: the station's frame.
static func landmarks(hull: StationHull, station_xf: Transform3D) -> Array:
	var out: Array = []
	for w in layout(hull):
		var lm: Dictionary = (w.spec as Dictionary).duplicate(true)
		lm.erase("note")
		lm["kind"] = "wreck"
		lm["adrift"] = true
		lm["pitch_deg"] = 0.0
		lm["frame"] = station_xf * (w.xf as Transform3D)
		lm["planks"] = cfg_of(hull).get("planks", [])
		out.append(lm)
	return out


## The belt laid out in the station's own frame: per wreck { id, spec, xf (its
## hull frame: x to starboard, y up, z to the stern), near (the top of its spine
## at the end toward the station), far (at the other end), box_half }. Its bow
## points back at the station, so the far end is its stern.
static func layout(hull: StationHull) -> Array:
	var bc := cfg_of(hull)
	var list: Array = bc.get("wrecks", [])
	var hatch := hull.drop_hatch() if hull != null else {}
	if list.is_empty() or hatch.is_empty():
		return []
	var out: Array = []
	var a := float(hatch.a) + deg_to_rad(float(bc.get("heading_deg", 0.0)))
	var dir := Vector3(cos(a), 0, sin(a))
	var prev: Dictionary = {}
	for i in list.size():
		var spec: Dictionary = list[i]
		if i > 0:
			dir = dir.rotated(Vector3.UP, deg_to_rad(float(spec.get("turn_deg", 0.0))))
		var basis := _basis(dir, float(spec.get("roll_deg", 0.0)))
		var variant: Dictionary = spec.get("variant", {})
		var near_local := spine_top(variant, float(spec.get("roll_deg", 0.0)), -1)
		var far_local := spine_top(variant, float(spec.get("roll_deg", 0.0)), 1)
		var origin: Vector3
		if i == 0:
			# The spine under the hatch, `behind_m` in from the bow toward the stern.
			var behind := float(bc.get("behind_m", 20.0))
			var z := -StarcruiserWreck.HALF_LENGTH + behind
			var under := spine_top(variant, float(spec.get("roll_deg", 0.0)), 0, z)
			var at: Vector3 = hatch.at
			var want := Vector3(at.x, at.y - float(bc.get("drop_m", 12.0)), at.z)
			origin = want - basis * Vector3(under.x, under.y, z)
		else:
			var from: Vector3 = prev.far
			var want := from + dir * float(bc.get("gap_m", 4.0)) - Vector3.UP * float(bc.get("step_m", 12.0))
			origin = want - basis * near_local
		var xf := Transform3D(basis, origin)
		var half := BOX_HALF
		var skip: Array = variant.get("skip", [])
		if not skip.has("engine_"):
			half.z += ENGINES_OUT * 0.5
		var w := { "id": str(spec.get("id", "belt_wreck_%d" % (i + 1))), "spec": spec, "xf": xf,
			"near": xf * near_local, "far": xf * far_local, "box_half": half,
			"engines": not skip.has("engine_") }
		out.append(w)
		prev = w
	return out


## The hull's turn: its stern (+z) along `dir`, level, then `roll_deg` about its keel.
static func _basis(dir: Vector3, roll_deg: float) -> Basis:
	var z := dir.normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x, Vector3.UP, z) * Basis(Vector3.BACK, deg_to_rad(roll_deg))


## The highest point of a level wreck's plating you can stand on once it is turned
## `roll_deg` about its keel, in its hull frame (parts() coordinates): at one end (`end` -1 the bow, 1 the
## stern: the last section of plates there) or across the section at hull z `at_z`
## (`end` 0). From the parts' own boxes (StarcruiserWreck.parts), so a variant
## that tears plates away moves it.
static func spine_top(variant: Dictionary, roll_deg: float, end: int, at_z: float = 0.0) -> Vector3:
	var roll := Basis(Vector3.BACK, deg_to_rad(roll_deg))
	var best := Vector3.ZERO
	var best_up := -INF
	var hl := StarcruiserWreck.HALF_LENGTH
	for p in _plates(variant):
		var xf: Transform3D = p.xf
		var cz := xf.origin.z
		if end == 0:
			if absf(cz - at_z) > 15.0:
				continue
		elif cz * end < hl - 30.0:
			continue
		var h: Vector3 = (p.size as Vector3) * 0.5
		# The plate's outer face (its +y or -y, by which way the facet turns): the
		# highest of its corners, a hair in from the ends the facets overlap at.
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var q := xf * Vector3(h.x * sx * 0.98, h.y * sy, h.z * sz)
					var up := (roll * q).y
					if up > best_up:
						best_up = up
						best = q
	best.z = float(end) * hl if end != 0 else at_z
	return best


static var _plates_kept := {}

static func _plates(variant: Dictionary) -> Array:
	var key := hash(variant)
	if not _plates_kept.has(key):
		_plates_kept[key] = StarcruiserWreck.parts(0.0, variant).filter(func(p): return str(p.id).begins_with("plate_"))
	return _plates_kept[key]


## Where the station's up holds round wreck `w` (PlanetSphere.add_gravity_zone): a
## level frame at its middle, turned with its heading but not its roll, so a wreck
## that lies over on its side still has the station's up, not its own.
static func zone_frame(w: Dictionary) -> Transform3D:
	var xf: Transform3D = w.xf
	var z := xf.basis.z
	z = Vector3(z.x, 0.0, z.z).normalized()
	return Transform3D(Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z), xf.origin)


## The box of that zone: the hull's, its roll's lean and a margin all round (the
## joints' gaps and the climb over a wreck's spine stay inside one zone or the next).
static func zone_box(w: Dictionary, margin: float = 30.0) -> AABB:
	var h: Vector3 = w.box_half
	var lean := h.x * absf(sin(deg_to_rad(float((w.spec as Dictionary).get("roll_deg", 0.0)))))
	var e := Vector3(h.x + margin, h.y + lean + margin, h.z + margin)
	return AABB(-e, e * 2.0)


# ------------------------------------------------------------------ the jetpack's reach

## How high a jump with a full tank climbs over the spot it left: the jump, the
## pack lighting after its kick-in and burning to empty, then the coast to the top.
## Stepped like the game (60 a second, CharacterController.step's order), from the
## jetpack item's "jetpack" block.
static func reach(jet_cfg: Dictionary, gravity: float = GRAVITY, jump_h: float = JUMP_HEIGHT, dt: float = 1.0 / 60.0) -> float:
	var jet = load("res://src/systems/player/jetpack.gd").new(jet_cfg)
	var max_rise := float(jet.max_rise())
	var v := sqrt(2.0 * gravity * jump_h)
	var y := 0.0
	var top := 0.0
	var on_ground := true
	for i in 600:
		var lift: float = jet.step(dt, true, on_ground)
		if on_ground:
			on_ground = false                # the jump frame: off the ground with v already
		else:
			v += (lift - gravity) * dt
			if lift > 0.0 and max_rise > 0.0:
				v = minf(v, max_rise)
		y += v * dt
		top = maxf(top, y)
		if v < 0.0 and not jet.thrusting and jet.fuel <= 0.0001:
			break
	return top


## Every climb the belt asks of you, { what, rise, gap }: the hatch over the first
## wreck, then each joint (from the lower wreck up to the one before it). Laid out
## from the data, so a step or a gap changed in the station's file shows here.
static func climbs(hull: StationHull) -> Array:
	var bc := cfg_of(hull)
	var ws := layout(hull)
	var out: Array = []
	if ws.is_empty():
		return out
	out.append({ "what": "the hatch over %s" % ws[0].id, "rise": float(bc.get("drop_m", 12.0)), "gap": 0.0 })
	for i in range(1, ws.size()):
		var a: Vector3 = ws[i - 1].far
		var b: Vector3 = ws[i].near
		out.append({ "what": "%s up to %s" % [ws[i].id, ws[i - 1].id], "rise": a.y - b.y,
			"gap": Vector2(a.x - b.x, a.z - b.z).length() })
	return out


## The climbs the jetpack cannot make: rise plus the belt's spare_m over what
## reach() gives. Empty when every one is in reach.
static func out_of_reach(hull: StationHull, jet_cfg: Dictionary) -> Array:
	var spare := float(cfg_of(hull).get("spare_m", 2.0))
	var top := reach(jet_cfg)
	var out: Array = []
	for c in climbs(hull):
		if float(c.rise) + spare > top:
			out.append("%s: %.1f m up (and %.1f m spare) but the jetpack climbs %.1f m" % [c.what, c.rise, spare, top])
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


## Over the belt: within `margin` metres (across, in the station's frame) of a wreck.
static func over_belt(ws: Array, local: Vector3, margin: float) -> bool:
	for w in ws:
		var l := (w.xf as Transform3D).affine_inverse() * local
		var h: Vector3 = w.box_half
		if absf(l.x) <= h.x + margin and absf(l.z) <= h.z + margin:
			return true
	return false


## The height (station frame) under which a body outside every wreck is lost to
## the belt: fall_m under the lowest wreck's spine.
static func lost_below(ws: Array, fall_m: float) -> float:
	var y := INF
	for w in ws:
		y = minf(y, minf((w.near as Vector3).y, (w.far as Vector3).y))
	return y - fall_m
