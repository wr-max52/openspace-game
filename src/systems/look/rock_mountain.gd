class_name RockMountain
extends RefCounted
## The big rocks on the home ball: climbable mountains of stacked rock shelves,
## a few versions reused round the planet (content/look/desert_landforms.json,
## `mountain_variants`). Each is a pile of extruded rock blocks:
##
##   tiers      jagged slabs, each smaller than the one below, so their tops are
##              shelves you can stand on (a rise of rise[0]..rise[1] m between)
##   ramps      a walkable rock ramp (no steeper than the floor limit) up the
##              wall to every shelf, the ramps spiralling round the mountain
##   scrambles  a stair of rock columns 0.45 m apart (one jump each) up to
##              every shelf on the far side from its ramp
##   blocks     loose columns on the shelves (columnar rock, and things to hop on)
##   crags      tall pinnacles on the top shelf (a jetpack climb)
##   caves      a slot cut into the foot that runs under the shelves above into
##              a round room
##
## The plan is only numbers, so WorldGround's ship columns and the drawn rock
## come from the same place; the collider is a trimesh of the very triangles
## drawn. Every block stands from `bury` m under the sand, so nothing floats.

static var _plans := {}
const SAMPLES := 144          ## a tier's radius table: one value every 2.5 degrees


## The plan of one version: { pieces, tiers, radius (the foot's), height, caves
## (angles) }. A piece is a prism: `poly` (x, z), its bottom `y0`, the top's
## height at each corner `tops` (one value for a flat top, a ramp's slope
## otherwise) and an optional `lean` { c, k, bury }: the outline shrinks toward c
## by k per metre up (from the buried foot), so cliffs lean in a little. A tier
## is { centre, radius (mean), top, table (foot radius by angle), shrink, bury, smooth, poly }; its wall's distance from
## its centre at an angle and height is wall(). Made once a session.
static func plan(v: Dictionary, cfg: Dictionary) -> Dictionary:
	var key := "%s/%s" % [hash(v), hash(cfg)]
	if _plans.has(key):
		return _plans[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(v.get("seed", 1))
	var bury := float(cfg.get("bury", 3.0))
	var r := float(v.get("radius", 90.0))
	var rise: Array = v.get("rise", [4.5, 7.0])
	var shelf: Array = v.get("shelf", [10.0, 15.0])
	var asym := float(v.get("asym", 0.9))
	var jag := float(v.get("jag", 2.0))
	var points := int(v.get("points", 36))
	var min_top := float(v.get("top_radius", 12.0))
	var lean: Array = v.get("lean", [0.03, 0.07])
	var lobe_amp: Array = v.get("lobes", [0.12, 0.14, 0.07])
	var y := float(v.get("first_rise", 3.5))
	# All tiers share one centre; each is a table of its foot's radius by angle.
	# The foot: broad lobes (1, 2 and 3 a turn). Each tier above is the top edge
	# of the one below less a shelf whose width goes round the mountain, widest on
	# one side and almost nothing on the other (the cliff), so it always stands
	# inside the tier below and the ways up never meet a cliff from the sand.
	var cliff := rng.randf() * TAU
	var table := PackedFloat32Array()
	table.resize(SAMPLES)
	var phases: Array = []
	for f in lobe_amp.size():
		phases.append(rng.randf() * TAU)
	for i in SAMPLES:
		var a := TAU * float(i) / float(SAMPLES)
		var rr := r
		for f in lobe_amp.size():
			rr += r * float(lobe_amp[f]) * cos(float(f + 1) * a + float(phases[f]))
		table[i] = rr
	var tiers: Array = []
	var pieces: Array = []
	for k in int(v.get("tiers", 8)):
		var t := { "centre": Vector2.ZERO, "radius": _mean(table), "top": y, "table": table,
			"shrink": rng.randf_range(float(lean[0]), float(lean[1])), "bury": bury, "smooth": [] }
		tiers.append(t)
		var s_k := rng.randf_range(float(shelf[0]), float(shelf[1]))
		var wob := rng.randf_range(-0.5, 0.5)
		var b2 := rng.randf_range(0.1, 0.35)
		var ph2 := rng.randf() * TAU
		var next := PackedFloat32Array()
		next.resize(SAMPLES)
		var least := INF
		for i in SAMPLES:
			var a := TAU * float(i) / float(SAMPLES)
			var f := maxf(0.05, 1.0 + asym * cos(a - cliff - wob) + b2 * cos(2.0 * a + ph2))
			next[i] = table[i] * (1.0 - float(t.shrink)) - s_k * f - jag * 0.6 - 0.3
			least = minf(least, next[i])
		if least < min_top:
			break
		table = next
		y += rng.randf_range(float(rise[0]), float(rise[1]))

	# Ways up: a ramp to every shelf and a jump stair round the other side, each
	# where there is shelf below to stand on, the ramps turning round the mountain.
	var ramp: Dictionary = cfg.get("ramp", {})
	var step: Dictionary = cfg.get("step", {})
	var need := float(ramp.get("width", 6.0)) + 2.0
	# `ways`: the arcs they take, [centre angle, half width], kept clear of columns,
	# blocks and caves; each tier's wall is smooth (no jag) along its own, a little
	# past each end. `zones`: where nothing else may stand, every ramp and stair
	# column grown by `clear` m (a ramp's foot reaching on along the shelf, the way
	# onto it). A way that would cross one already placed tries further round.
	var clear := float(cfg.get("clear", 1.5))
	var ways: Array = []
	var zones: Array = []
	var a := rng.randf() * TAU
	for k in tiers.size():
		var t: Dictionary = tiers[k]
		var below = tiers[k - 1] if k > 0 else null
		var h0 := 0.0 if below == null else float(below.top)
		var rp := {}
		var slope := tan(deg_to_rad(float(ramp.get("slope_deg", 28.0))))
		var landing := float(ramp.get("landing", 3.0))
		for tries in 12:
			var ra := _widest(t, below, a + float(tries) * 0.5, 0.6, need)
			# The arc it will take round the wall, made round before it is built.
			var w := _lobed(t, ra)
			var top_a := ra + landing / w
			var low_a := top_a - ((float(t.top) - h0) / slope + landing) / (w + 1.0)
			var arc := [(top_a + low_a) * 0.5, (top_a - low_a) * 0.5 + 8.0 / w, 0.0]
			arc[2] = _most(t, float(arc[0]), float(arc[1]) + 0.2)
			t.smooth.append(arc)
			rp = _ramp(t, ra, h0, ramp)
			rp["arc"] = arc
			if not _crosses(zones, _way_zones([rp], clear)) or tries == 11:
				break
			t.smooth.pop_back()
		rp["way"] = "ramp"
		rp["tier"] = k
		pieces.append(rp)
		ways.append(rp.arc)
		zones.append_array(_way_zones([rp], clear))
		if below != null:
			var sc := {}
			var size := float(step.get("size", 2.6))
			var n := int(ceil((float(t.top) - h0) / float(step.get("rise", 0.45)))) - 1
			for tries in 12:
				var sa := _widest(t, below, float(rp.arc[0]) + PI + float(tries) * 0.45, 0.6, 4.0)
				var w := _lobed(t, sa)
				var span := float(n) * size * 0.8 / w
				var arc := [sa + span * 0.5, span * 0.5 + 5.0 / w, 0.0]
				arc[2] = _most(t, float(arc[0]), float(arc[1]) + 0.2)
				t.smooth.append(arc)
				sc = _scramble(t, sa, h0, step, rng)
				sc["arc"] = arc
				if not _crosses(zones, _way_zones(sc.blocks, clear)) or tries == 11:
					break
				t.smooth.pop_back()
			for sp in sc.blocks:
				sp["way"] = "step"
				sp["tier"] = k
				pieces.append(sp)
			ways.append(sc.arc)
			zones.append_array(_way_zones(sc.blocks, clear))
		a = float(rp.arc[0]) + deg_to_rad(rng.randf_range(80.0, 130.0))
	for t in tiers:
		t["poly"] = _outline(t, points, jag, rng)

	# Rock columns against every wall: some stand proud of the shelf edge (the
	# skyline's teeth), some stop short (buttresses and footholds).
	for k in tiers.size():
		var t: Dictionary = tiers[k]
		for i in int(v.get("columns", 8)):
			var ca := rng.randf() * TAU
			if _in_arcs(ways, ca, 0.25):
				continue
			var cr := rng.randf_range(1.8, 4.2)
			var h := float(t.top) + rng.randf_range(-5.0, 3.5)
			var at: Vector2 = (t.centre as Vector2) + Vector2.from_angle(ca) * (wall(t, ca, h) + cr * 0.25)
			var poly := _jagged(at, cr, 6, cr * 0.25, rng)
			if not _blocks_way(zones, poly):
				pieces.append({ "poly": poly, "y0": -bury, "tops": [h] })

	# Loose blocks on each shelf, between the wall above and the shelf's edge.
	for k in range(0, tiers.size() - 1):
		var below: Dictionary = tiers[k]
		var above: Dictionary = tiers[k + 1]
		for i in int(v.get("blocks", 4)):
			var ba := rng.randf() * TAU
			if _in_arcs(ways, ba, 0.25):
				continue
			var wall_at: Vector2 = (above.centre as Vector2) + Vector2.from_angle(ba) * wall(above, ba, float(below.top))
			var rel: Vector2 = wall_at - (below.centre as Vector2)
			var room := wall(below, rel.angle(), float(below.top)) - rel.length()
			if room < 5.0:
				continue
			var at: Vector2 = wall_at + Vector2.from_angle(ba) * room * 0.5
			var h: float = float(below.top) + [0.45, 0.9, 1.35, 2.6, 4.0][rng.randi() % 5]
			var poly := _jagged(at, rng.randf_range(1.4, 2.6), 6, 0.4, rng)
			if not _blocks_way(zones, poly):
				pieces.append({ "poly": poly, "y0": -bury, "tops": [h] })

	# Pinnacles on the top shelf.
	var top: Dictionary = tiers[-1]
	for i in int(v.get("crags", 3)):
		var ca := rng.randf() * TAU
		var at: Vector2 = (top.centre as Vector2) + Vector2.from_angle(ca) * float(top.radius) * rng.randf_range(0.1, 0.5)
		var h := float(top.top) + rng.randf_range(6.0, 16.0)
		var poly := _jagged(at, rng.randf_range(2.5, 4.5), 7, 0.8, rng)
		if not _blocks_way(zones, poly):
			pieces.append({ "poly": poly, "y0": -bury, "tops": [h] })

	# The tiers themselves, with the caves cut in.
	var cave: Dictionary = cfg.get("cave", {})
	var caves: Array = []
	for i in int(v.get("caves", 1)):
		var cav := rng.randf() * TAU
		var tries := 0
		while (_in_arcs(ways, cav, 0.4) or _near(caves, cav, 1.2)) and tries < 24:
			cav = rng.randf() * TAU
			tries += 1
		caves.append(cav)
	var slots: Array = []
	for cav in caves:
		slots.append(_cave_slot(tiers[0], cav, cave))
	var cave_h := float(cave.get("height", 6.0))
	for t in tiers:
		var tl := { "c": t.centre, "k": float(t.shrink) / (float(t.top) + bury), "bury": bury }
		var parts: Array = [t.poly]
		for slot in slots:
			var cut: Array = []
			# The slot starts outside the foot, so a cut never leaves a hole.
			for p in parts:
				cut.append_array(Geometry2D.clip_polygons(p, slot))
			parts = cut
			# Under shelves higher than the cave, a roof over it from cave_h up.
			if float(t.top) > cave_h + 1.5:
				for q in Geometry2D.intersect_polygons(t.poly, slot):
					pieces.append({ "poly": q, "y0": cave_h, "tops": [float(t.top)], "lean": tl })
		for p in parts:
			pieces.append({ "poly": p, "y0": -bury, "tops": [float(t.top)], "lean": tl })

	var out := { "pieces": pieces, "tiers": tiers, "radius": Array(tiers[0].table).max(),
		"height": float(top.top), "caves": caves }
	_plans[key] = out
	return out


## A tier's wall: its distance from the tier's centre at angle a and height h
## (the lobes, less the lean in by h; the outline's jag is left out).
## Along a way up (a `smooth` arc [centre, half width, radius]) the wall is
## round, easing back into the lobes over 0.2 rad past each end, so a ramp is a
## clean spiral and a stair a clean arc (a lobed wall would fold them).
static func wall(t: Dictionary, a: float, h: float) -> float:
	var r := _lobed(t, a)
	for arc in t.get("smooth", []):
		var d := absf(wrapf(a - float(arc[0]), -PI, PI))
		var half := float(arc[1])
		if d < half + 0.2:
			r = lerpf(r, float(arc[2]), 1.0 - smoothstep(half, half + 0.2, d))
	var b := float(t.bury)
	return r * (1.0 - float(t.shrink) * (h + b) / (float(t.top) + b))


## A tier's foot radius at angle a, from its table.
static func _lobed(t: Dictionary, a: float) -> float:
	var tb: PackedFloat32Array = t.table
	var x := wrapf(a, 0.0, TAU) / TAU * float(SAMPLES)
	var i := int(x) % SAMPLES
	return lerpf(tb[i], tb[(i + 1) % SAMPLES], x - floorf(x))


## The most a tier's foot reaches across an arc (so a round stretch of wall only
## ever stands out, never in toward the tier above).
static func _most(t: Dictionary, centre: float, half: float) -> float:
	var m := 0.0
	for i in 25:
		m = maxf(m, _lobed(t, centre - half + half * 2.0 * float(i) / 24.0))
	return m


static func _mean(tb: PackedFloat32Array) -> float:
	var m := 0.0
	for v in tb:
		m += v
	return m / float(tb.size())




## The angle near `a` (within `spread` radians) where the shelf of `below` under
## tier t's wall is widest.
static func _widest(t: Dictionary, below, a: float, spread: float, need: float) -> float:
	if below == null:
		return a
	var best := a
	var best_w := -INF
	for i in 25:
		var ca := a + spread * (float(i) / 12.0 - 1.0)
		var at: Vector2 = (t.centre as Vector2) + Vector2.from_angle(ca) * wall(t, ca, float(below.top))
		var rel: Vector2 = at - (below.centre as Vector2)
		var w := wall(below, rel.angle(), float(below.top)) - rel.length()
		# Prefer the target angle once the shelf is wide enough.
		var score := minf(w, need) - absf(ca - a) * 0.01
		if score > best_w:
			best_w = score
			best = ca
	return best


## Where one goes on the ball: turned so its first cave faces downhill, and sunk to
## the lowest sand round its foot (at most `max_sink` m), so the cave is not full of
## sand and the foot never floats. { yaw (radians), sink (m) }. Pure maths on the
## sphere, so the ship's columns and the drawn rock agree.
static func placement(sp: PlanetSphere, map: Vector2, p: Dictionary, max_sink: float = 14.0) -> Dictionary:
	var base := sp.surface_at(map.x, map.y)
	var g := Transform3D(PlanetSphere.tilt_to(sp.up_at(base)), base)
	var r := float(p.radius)
	var low_a := 0.0
	var low := INF
	for i in 16:
		var a := TAU * float(i) / 16.0
		var w := g * Vector3(cos(a) * r, 0.0, sin(a) * r)
		var m := sp.world_to_map(w)
		var h := (sp.surface_at(m.x, m.y) - base).dot(g.basis.y)
		if h < low:
			low = h
			low_a = a
	# Basis(UP, yaw) turns angle atan2(z, x) down by yaw.
	var caves: Array = p.caves
	var yaw := (float(caves[0]) - low_a) if not caves.is_empty() else 0.0
	return { "yaw": yaw, "sink": clampf(-low, 0.0, max_sink), "frame": g }


## The ship's columns for one placed mountain: one per tier (its centre, its
## mean radius, its top), along the ball's up. Highest first.
static func columns(sp: PlanetSphere, map: Vector2, p: Dictionary, id: String) -> Array:
	var pl := placement(sp, map, p)
	var g: Transform3D = pl.frame
	var turn := Basis(Vector3.UP, float(pl.yaw))
	var out: Array = []
	var tiers: Array = p.tiers
	for k in range(tiers.size() - 1, -1, -1):
		var t: Dictionary = tiers[k]
		var c2: Vector2 = t.centre
		var at := g * (turn * Vector3(c2.x, -float(pl.sink), c2.y))
		var h := float(t.top)
		out.append({ "id": "%s_%d" % [id, k], "kind": "mesa", "center": at,
			"radius": float(t.radius) * 0.95, "up": g.basis.y, "h": h, "top": at.y + h })
	return out


## The mesh and the collider's faces for a plan: { mesh, faces }. Faceted (hard
## edges), as the mesas and boulders: broken rock, not wind-polished.
static func build(p: Dictionary) -> Dictionary:
	var faces: Array = []
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var tri := func(p0: Vector3, p1: Vector3, p2: Vector3, out: Vector3) -> void:
		if (p1 - p0).cross(p2 - p0).dot(out) > 0.0:
			var tmp := p1
			p1 = p2
			p2 = tmp
		for q in [p0, p1, p2]:
			st.add_vertex(q)
			faces.append(q)
	for piece in p.pieces:
		if piece.has("strip"):
			_build_strip(piece, tri)
			continue
		var poly: PackedVector2Array = piece.poly
		var n := poly.size()
		if n < 3:
			continue
		var y0 := float(piece.y0)
		var tops: Array = piece.tops
		var top_at := func(i: int) -> float: return float(tops[i] if tops.size() == n else tops[0])
		# The outline at height y: shrunk toward the lean's centre (leaning cliffs).
		var ln: Dictionary = piece.get("lean", {})
		var at_y := func(q: Vector2, yy: float) -> Vector2:
			if ln.is_empty():
				return q
			var lc: Vector2 = ln.c
			return lc + (q - lc) * (1.0 - float(ln.k) * (yy + float(ln.bury)))
		for i in n:
			var j := (i + 1) % n
			var a := poly[i]
			var b := poly[j]
			var e := b - a
			var nrm := Vector2(e.y, -e.x).normalized()
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + nrm * 0.05, poly):
				nrm = -nrm
			var out := Vector3(nrm.x, 0.0, nrm.y)
			var ab: Vector2 = at_y.call(a, y0)
			var bb: Vector2 = at_y.call(b, y0)
			var at_: Vector2 = at_y.call(a, top_at.call(i))
			var bt: Vector2 = at_y.call(b, top_at.call(j))
			var a0 := Vector3(ab.x, y0, ab.y)
			var b0 := Vector3(bb.x, y0, bb.y)
			var a1 := Vector3(at_.x, top_at.call(i), at_.y)
			var b1 := Vector3(bt.x, top_at.call(j), bt.y)
			tri.call(a0, b0, b1, out)
			tri.call(a0, b1, a1, out)
		var idx := Geometry2D.triangulate_polygon(poly)
		for k in range(0, idx.size(), 3):
			var t3: Array = []
			for m in 3:
				var yy: float = top_at.call(idx[k + m])
				var q: Vector2 = at_y.call(poly[idx[k + m]], yy)
				t3.append(Vector3(q.x, yy, q.y))
			tri.call(t3[0], t3[1], t3[2], Vector3.UP)
			if y0 > -0.5:      # a roof over a cave: its underside is the ceiling
				var b3: Array = []
				for m in 3:
					var q: Vector2 = at_y.call(poly[idx[k + m]], y0)
					b3.append(Vector3(q.x, y0, q.y))
				tri.call(b3[0], b3[1], b3[2], Vector3.DOWN)
	st.generate_normals()
	return { "mesh": st.commit(), "faces": PackedVector3Array(faces) }


## A ramp's faces: its top in quads along the strip, its outer and inner sides
## down to y0, and both ends.
static func _build_strip(piece: Dictionary, tri: Callable) -> void:
	var inner: PackedVector3Array = piece.strip.inner
	var outer: PackedVector3Array = piece.strip.outer
	var y0 := float(piece.y0)
	var down := func(q: Vector3) -> Vector3: return Vector3(q.x, y0, q.z)
	var n := inner.size()
	for i in n - 1:
		var i0 := inner[i]
		var i1 := inner[i + 1]
		var o0 := outer[i]
		var o1 := outer[i + 1]
		tri.call(o0, o1, i1, Vector3.UP)
		tri.call(o0, i1, i0, Vector3.UP)
		var out := Vector3(o0.x - i0.x, 0.0, o0.z - i0.z).normalized()
		tri.call(down.call(o0), down.call(o1), o1, out)
		tri.call(down.call(o0), o1, o0, out)
		tri.call(down.call(i0), down.call(i1), i1, -out)
		tri.call(down.call(i0), i1, i0, -out)
	for e in [[0, 1], [n - 1, n - 2]]:
		var i0 := inner[e[0]]
		var o0 := outer[e[0]]
		var back := (inner[e[0]] - inner[e[1]])
		back.y = 0.0
		back = back.normalized()
		tri.call(down.call(i0), down.call(o0), o0, back)
		tri.call(down.call(i0), o0, i0, back)


## A jagged outline round c: `points` corners at radius r +- jag, a little uneven
## in angle, so the walls read as broken columns.
static func _jagged(c: Vector2, r: float, points: int, jag: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(points)
		out.append(c + Vector2.from_angle(a) * (r + rng.randf_range(-jag, jag)))
	return out


## A tier's outline at its foot: its lobed wall, broken by jag, with every third
## corner set in further so the cliff reads as columns (the flutes between them).
## Along the tier's ways up (`smooth` arcs) the wall is exact and closely sampled,
## so a ramp or a jump stair meets it with no gap and is never swallowed by it.
static func _outline(t: Dictionary, points: int, jag: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var c: Vector2 = t.centre
	var b := float(t.bury)
	var corners: Array = []       # [angle, radius]
	for i in points:
		var a := TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / float(points)
		var r := wall(t, a, -b) + rng.randf_range(-jag, jag) * 0.6
		if i % 3 == 0:
			r -= jag * rng.randf_range(0.6, 1.4)
		if not _in_arcs(t.smooth, a, 0.06):
			corners.append([wrapf(a, 0.0, TAU), r])
	for arc in t.smooth:
		var half := float(arc[1]) + 0.06
		var n := int(ceil(half * 2.0 / 0.04))
		for i in n + 1:
			var a := float(arc[0]) - half + half * 2.0 * float(i) / float(n)
			corners.append([wrapf(a, 0.0, TAU), wall(t, a, -b)])
	corners.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
	var out := PackedVector2Array()
	for cr in corners:
		out.append(c + Vector2.from_angle(float(cr[0])) * float(cr[1]))
	return out


## A ramp against tier t's wall ending at angle a, from h0 at its foot up to the
## shelf. It follows the wall round (the lobes bulge in and out, so a straight
## ramp would run into the cliff): sampled every metre and a half, its inner edge
## 4 m into the wall at that height and its outer edge `width` out, rising at
## `slope_deg` with a flat `landing` at the top. A buttress from the sand up, so
## it never floats over a lower shelf's edge. { strip: { inner, outer } (low end
## first), poly (its outline, for keep-clear zones), y0, arc }.
static func _ramp(t: Dictionary, a: float, h0: float, cfg: Dictionary) -> Dictionary:
	var h1 := float(t.top)
	var width := float(cfg.get("width", 6.0))
	var slope := tan(deg_to_rad(float(cfg.get("slope_deg", 28.0))))
	var landing := float(cfg.get("landing", 3.0))
	var c: Vector2 = t.centre
	var hi := h1 - 0.04          # 4 cm under the shelf where they meet, so faces never fight
	var ds := 1.5
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	var phi := a + landing / wall(t, a, h1)
	var s := 0.0
	var h := hi
	var phi_top := phi
	while true:
		var w := wall(t, phi, h)
		var dir := Vector2.from_angle(phi)
		var pi_ := c + dir * (w - 4.0)
		var po := c + dir * (w + width)
		inner.append(Vector3(pi_.x, h, pi_.y))
		outer.append(Vector3(po.x, h, po.y))
		if h <= h0:
			break
		s += ds
		h = maxf(h0, hi - maxf(0.0, s - landing) * slope)
		phi -= ds / (w + (width - 4.0) * 0.5)
	inner.reverse()
	outer.reverse()
	var poly := PackedVector2Array()
	for q in inner:
		poly.append(Vector2(q.x, q.z))
	for i in range(outer.size() - 1, -1, -1):
		poly.append(Vector2(outer[i].x, outer[i].z))
	# The wall stays smooth past both ends (the way onto its foot, off its top).
	var wr := wall(t, a, h1)
	var arc := [(phi + phi_top) * 0.5, (phi_top - phi) * 0.5 + 7.0 / wr]
	return { "strip": { "inner": inner, "outer": outer }, "poly": poly, "y0": -float(t.bury), "tops": [h0], "arc": arc }


## A stair of rock columns up tier t's wall from angle a, one jump (0.45 m)
## apart, round the wall from one jump under its shelf (at a) down to h0. Spaced
## along the wall itself (its lobes too), each column standing into the wall at
## its own height (the wall leans in): no gap to jump. { blocks, arc }.
static func _scramble(t: Dictionary, a: float, h0: float, cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var h1 := float(t.top)
	var rise := float(cfg.get("rise", 0.45))
	var size := float(cfg.get("size", 2.6))
	var blocks: Array = []
	var n := int(ceil((h1 - h0) / rise)) - 1
	if n <= 0:
		return { "blocks": blocks, "arc": [a, 0.0] }
	var c: Vector2 = t.centre
	var ca := a
	for j in range(n - 1, -1, -1):          # the highest first, nearest a
		var h := h0 + rise * float(j + 1)
		var w := wall(t, ca, h)
		var at := c + Vector2.from_angle(ca) * (w + size * 0.3)
		var poly := PackedVector2Array()
		var spin := rng.randf_range(-0.3, 0.3)
		for k in 4:
			var pa := ca + spin + TAU * (float(k) + 0.5) / 4.0
			poly.append(at + Vector2.from_angle(pa) * size * 0.62 * rng.randf_range(0.95, 1.05))
		blocks.append({ "poly": poly, "y0": -float(t.bury), "tops": [h] })
		ca += size * 0.8 / w
	return { "blocks": blocks, "arc": [(a + ca) * 0.5, (ca - a) * 0.5 + 5.0 / float(t.radius)] }


## The keep-clear zones of a way's pieces: each grown by `clear`, a ramp's foot
## reaching 5 m further along (the way onto it).
static func _way_zones(way_pieces: Array, clear: float) -> Array:
	var out: Array = []
	for piece in way_pieces:
		var poly: PackedVector2Array = piece.poly
		var grown := Geometry2D.offset_polygon(poly, clear)
		if piece.has("strip"):
			# The way onto its foot: a pad 5 m on along the wall from the low end.
			var inner: PackedVector3Array = piece.strip.inner
			var outer: PackedVector3Array = piece.strip.outer
			var i0 := Vector2(inner[0].x, inner[0].z)
			var o0 := Vector2(outer[0].x, outer[0].z)
			var back := (i0 - Vector2(inner[1].x, inner[1].z)).normalized() * 5.0
			var pad := Geometry2D.offset_polygon(PackedVector2Array([i0, o0, o0 + back, i0 + back]), clear)
			if not pad.is_empty():
				out.append(_zone(pad[0]))
		if not grown.is_empty():
			out.append(_zone(grown[0]))
	return out


static func _crosses(zones: Array, new_zones: Array) -> bool:
	for z in new_zones:
		if _blocks_way(zones, z.poly):
			return true
	return false


## A way's keep-clear zone: its outline, centre and reach (for a quick test first).
static func _zone(poly: PackedVector2Array) -> Dictionary:
	var c := Vector2.ZERO
	for q in poly:
		c += q
	c /= float(poly.size())
	var r := 0.0
	for q in poly:
		r = maxf(r, c.distance_to(q))
	return { "poly": poly, "c": c, "r": r }


## True when `poly` would stand on a ramp, a stair or the way onto one.
static func _blocks_way(zones: Array, poly: PackedVector2Array) -> bool:
	var z := _zone(poly)
	for zone in zones:
		if (zone.c as Vector2).distance_to(z.c) > float(zone.r) + float(z.r):
			continue
		if not Geometry2D.intersect_polygons(poly, zone.poly).is_empty():
			return true
	return false


static func _in_arcs(arcs: Array, a: float, margin: float) -> bool:
	for arc in arcs:
		if absf(wrapf(a - float(arc[0]), -PI, PI)) < float(arc[1]) + margin:
			return true
	return false


## The cave's floor plan: a slot from outside the foot inward, ending in a round
## room, at angle a of the first tier.
static func _cave_slot(t: Dictionary, a: float, cfg: Dictionary) -> PackedVector2Array:
	var mouth := float(cfg.get("mouth", 6.0))
	var depth := float(cfg.get("depth", 28.0))
	var room := float(cfg.get("room", 7.0))
	var c: Vector2 = t.centre
	var r := float(t.radius)
	var radial := Vector2.from_angle(a)
	var side := Vector2.from_angle(a + PI * 0.5) * mouth * 0.5
	var outer := c + radial * (r + 8.0)
	var inner := c + radial * (r - depth)
	var slot := PackedVector2Array([outer - side, outer + side, inner + side, inner - side])
	var ring := PackedVector2Array()
	for i in 10:
		ring.append(inner + Vector2.from_angle(TAU * float(i) / 10.0) * room)
	var merged := Geometry2D.merge_polygons(slot, ring)
	return merged[0] if merged.size() == 1 else slot


static func _near(angles: Array, a: float, within: float) -> bool:
	for b in angles:
		if absf(wrapf(a - float(b), -PI, PI)) < within:
			return true
	return false
