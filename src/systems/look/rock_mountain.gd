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
##   tunnel     (a version with `tunnel`) a wide arched way right through the
##              foot, a portal in the sheer cliff on one side and a cut through
##              the terraces on the other: big enough to race a speeder through
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
## its centre at an angle and height is wall(). A piece may also have `bots`, its
## bottom's height at each corner (a tunnel's arched ceiling). A version with
## `tunnel` { width, spring, crown } adds `tunnel` { a (the angle its cliff portal
## faces), half, spring, crown, path (its centre line, from the portal), gates
## (see _tunnel_gates), roofs (the roofed tiers' outlines) }. `opts` (a range's
## peak, range_plan): path (the tunnel's centre line instead of a straight one
## through the middle), cliff_toward (the angle the sheer side's portal faces),
## avoid (outlines the ways up and caves keep off: the neighbours' feet). Made
## once a session.
static func plan(v: Dictionary, cfg: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var key := "%s/%s/%s" % [hash(v), hash(cfg), hash(opts)]
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
	if opts.has("cliff_toward"):
		cliff = float(opts.cliff_toward) - PI
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
	var clear := float(cfg.get("clear", 1.5))
	# The tunnel: a slot along its centre line, straight through the middle with
	# its portal in the sheer side (where the shelves are narrowest, so the cliff
	# above it is tall), or a range's path. Nothing else may stand in it (a
	# keep-clear zone, and arcs like a way's where it passes the walls).
	var tun: Dictionary = v.get("tunnel", {})
	var t_path := PackedVector2Array()
	var t_slot := PackedVector2Array()
	var t_a := cliff + PI
	var t_half := float(tun.get("width", 36.0)) * 0.5
	var t_zone := {}
	if not tun.is_empty():
		if opts.has("path"):
			t_path = opts.path
		else:
			var reach: float = Array(tiers[0].table).max() + 20.0
			t_path = PackedVector2Array([Vector2.from_angle(t_a) * reach, -Vector2.from_angle(t_a) * reach])
		t_slot = _path_band(t_path, -t_half, t_half)
		t_zone = _zone(Geometry2D.offset_polygon(t_slot, clear)[0])
	# `ways`: the arcs they take, [centre angle, half width], kept clear of columns,
	# blocks and caves; each tier's wall is smooth (no jag) along its own, a little
	# past each end. `zones`: where nothing else may stand, every ramp and stair
	# column grown by `clear` m (a ramp's foot reaching on along the shelf, the way
	# onto it). A way that would cross one already placed tries further round.
	var ways: Array = []
	var zones: Array = []
	if not t_zone.is_empty():
		zones.append(t_zone)
		var r_lo := float(tiers[-1].radius) * 0.5
		var r_hi: float = Array(tiers[0].table).max() * 1.2
		for q in _resample(t_path, 4.0):
			var dq := (q as Vector2).length()
			if dq > r_lo and dq < r_hi:
				ways.append([(q as Vector2).angle(), atan2(t_half + clear * 2.0, dq)])
	for poly in opts.get("avoid", []):
		zones.append(_zone(poly))
	# The caves go first, clear of the tunnel and of each other, so the ways up,
	# the columns and the loose rock all keep out of them, mouth and all (a ramp
	# stands from the sand: over a cave it would fill it). From a random angle,
	# round in 2 degree steps to the first clean place.
	var cave: Dictionary = cfg.get("cave", {})
	var caves: Array = []
	var slots: Array = []
	for i in int(v.get("caves", 1)):
		var from := rng.randf() * TAU
		var cav := from
		var slot := _cave_slot(tiers[0], cav, cave)
		var tries := 0
		while (_in_arcs(ways, cav, 0.4) or _near(caves, cav, 1.2) or _blocks_way(zones, slot)) and tries < 180:
			tries += 1
			cav = from + TAU * float(tries) / 180.0
			slot = _cave_slot(tiers[0], cav, cave)
		if tries >= 180 and not caves.is_empty():
			break                  # no clean place for another: one fewer cave
		caves.append(cav)
		slots.append(slot)
		zones.append(_zone(Geometry2D.offset_polygon(slot, clear)[0]))
	var a := rng.randf() * TAU
	for k in tiers.size():
		var t: Dictionary = tiers[k]
		var below = tiers[k - 1] if k > 0 else null
		var h0 := 0.0 if below == null else float(below.top)
		# Every tier stands at least `margin` inside the one below at its shelf,
		# rounded stretches and all: the lobes are deep, and without this a tier
		# could swell out over the shelf under it (a fin of cliff where the shelf
		# should be, across a lower tier's ramp).
		var margin := jag
		if below != null:
			var tb: PackedFloat32Array = t.table
			for i in SAMPLES:
				tb[i] = minf(tb[i], _room(t, below, TAU * float(i) / float(SAMPLES), margin))
			t.table = tb
			t.radius = _mean(tb)
		# Twelve tries round the mountain toward its widest shelves, then a finer
		# sweep all the way round; with nowhere clean (the tunnel, a cave or a
		# neighbour's foot everywhere), this shelf has no ramp rather than one
		# standing in the way.
		var rp := {}
		var placed := false
		var slope := tan(deg_to_rad(float(ramp.get("slope_deg", 28.0))))
		var landing := float(ramp.get("landing", 3.0))
		for tries in 48:
			var ra := _widest(t, below, a + float(tries) * 0.5, 0.6, need) if tries < 12 \
				else _widest(t, below, a + TAU * float(tries - 12) / 36.0, 0.15, need)
			# The arc it will take round the wall, made round before it is built.
			# Sized by the round wall's own radius (it may sit inside the lobe there),
			# so the ramp never runs past the round stretch onto the lobes.
			var w := _lobed(t, ra)
			var arc := []
			for it in 3:
				var top_a := ra + landing / w
				var low_a := top_a - ((float(t.top) - h0) / slope + landing) / (w + 1.0)
				arc = [(top_a + low_a) * 0.5, (top_a - low_a) * 0.5 + 8.0 / w, 0.0]
				arc[2] = _most_inside(t, below, float(arc[0]), float(arc[1]) + 0.2, margin)
				w = float(arc[2])
			t.smooth.append(arc)
			rp = _ramp(t, ra, h0, ramp)
			rp["arc"] = arc
			if not _crosses(zones, _way_zones([rp], clear)):
				placed = true
				break
			t.smooth.pop_back()
		if placed:
			rp["way"] = "ramp"
			rp["tier"] = k
			pieces.append(rp)
			ways.append(rp.arc)
			zones.append_array(_way_zones([rp], clear))
		if below != null:
			var sc := {}
			var stair := false
			var size := float(step.get("size", 2.6))
			var n := int(ceil((float(t.top) - h0) / float(step.get("rise", 0.45)))) - 1
			for tries in 48:
				var sa := _widest(t, below, float(rp.arc[0]) + PI + float(tries) * 0.45, 0.6, 4.0) if tries < 12 \
					else _widest(t, below, float(rp.arc[0]) + PI + TAU * float(tries - 12) / 36.0, 0.15, 4.0)
				var w := _lobed(t, sa)
				var arc := []
				for it in 3:
					var span := float(n) * size * 0.8 / w
					arc = [sa + span * 0.5, span * 0.5 + 5.0 / w, 0.0]
					arc[2] = _most_inside(t, below, float(arc[0]), float(arc[1]) + 0.2, margin)
					w = float(arc[2])
				t.smooth.append(arc)
				sc = _scramble(t, sa, h0, step, rng)
				sc["arc"] = arc
				if not _crosses(zones, _way_zones(sc.blocks, clear)):
					stair = true
					break
				t.smooth.pop_back()
			if stair:
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
	var cave_h := float(cave.get("height", 6.0))
	var spring := float(tun.get("spring", 11.0))
	var crown := float(tun.get("crown", 24.0))
	var roofed: Array = []
	for t in tiers:
		var tl := { "c": t.centre, "k": float(t.shrink) / (float(t.top) + bury), "bury": bury }
		var parts: Array = [t.poly]
		if not t_slot.is_empty():
			# The tunnel cuts every tier; under shelves above its crown, an arched
			# ceiling: strips along it, narrower toward the walls, each one's
			# underside on the arch (a half ellipse from the spring line to the crown).
			var cut: Array = []
			for p in parts:
				cut.append_array(Geometry2D.clip_polygons(p, t_slot))
			parts = cut
			if float(t.top) > crown + 1.5:
				roofed.append(t)
				pieces.append_array(_arch(t, t_path, t_half, spring, crown, tl))
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
	if not t_slot.is_empty() and not roofed.is_empty():
		var roofs: Array = roofed.map(func(t): return t.poly)
		out["tunnel"] = { "a": t_a, "half": t_half, "spring": spring, "crown": crown,
			"path": t_path, "roofs": roofs, "gates": _tunnel_gates(t_path, roofs) }
	_plans[key] = out
	return out


## A range: several peaks in one frame (the middle's level ground), one tunnel
## along `path` through them all. `peaks`: [{ v (the version, its own seed), at
## (its centre), cliff_toward? }] in the range's frame. Each peak is a plan of its
## own cut by the whole path, its ways up and caves kept off its neighbours'
## feet; the rock overlaps where the peaks meet, so the tunnel runs on under it.
## The same as plan() (pieces, tiers with their own centres, radius from the
## range's centre, height, caves, tunnel with the range's path and gates) plus
## `peaks` [{ at, radius }] and `subplans` [{ at, plan }]. Made once a session.
static func range_plan(peaks: Array, path: PackedVector2Array, cfg: Dictionary) -> Dictionary:
	var key := "range/%s/%s/%s" % [hash(peaks), hash(path), hash(cfg)]
	if _plans.has(key):
		return _plans[key]
	var out := { "pieces": [], "tiers": [], "radius": 0.0, "height": 0.0, "caves": [], "range": true,
		"peaks": [], "subplans": [] }
	var feet: Array = []
	for pk in peaks:
		var v: Dictionary = pk.v
		var lob := 0.0
		for l in v.get("lobes", []):
			lob += float(l)
		feet.append(float(v.get("radius", 90.0)) * (1.0 + lob))
	var roofs: Array = []
	var tn := {}
	for i in peaks.size():
		var pk: Dictionary = peaks[i]
		var at: Vector2 = pk.at
		var local := PackedVector2Array()
		for q in path:
			local.append(q - at)
		var avoid: Array = []
		for j in peaks.size():
			if j != i:
				var ring := PackedVector2Array()
				for s in 24:
					ring.append((peaks[j].at as Vector2) - at + Vector2.from_angle(TAU * float(s) / 24.0) * float(feet[j]) * 0.9)
				avoid.append(ring)
		var opts := { "path": local, "avoid": avoid }
		if pk.has("cliff_toward"):
			opts["cliff_toward"] = float(pk.cliff_toward)
		var p := plan(pk.v, cfg, opts)
		out.subplans.append({ "at": at, "plan": p })
		out.peaks.append({ "at": at, "radius": float(p.radius) })
		for piece in p.pieces:
			out.pieces.append(_shifted(piece, at))
		for t in p.tiers:
			var tt: Dictionary = t.duplicate()
			tt["centre"] = at
			out.tiers.append(tt)
		out.caves.append_array(p.caves)
		out.radius = maxf(float(out.radius), at.length() + float(p.radius))
		out.height = maxf(float(out.height), float(p.height))
		if p.has("tunnel"):
			tn = p.tunnel
			for poly in p.tunnel.roofs:
				var moved := PackedVector2Array()
				for q in poly:
					moved.append(q + at)
				roofs.append(moved)
	if not tn.is_empty():
		out["tunnel"] = { "a": 0.0, "half": tn.half, "spring": tn.spring, "crown": tn.crown,
			"path": path, "roofs": roofs, "gates": _tunnel_gates(path, roofs) }
	_plans[key] = out
	return out


## A piece moved by `at` (a range's peak into the range's frame).
static func _shifted(piece: Dictionary, at: Vector2) -> Dictionary:
	var out: Dictionary = piece.duplicate()
	var poly := PackedVector2Array()
	for q in piece.poly:
		poly.append(q + at)
	out["poly"] = poly
	if piece.has("lean"):
		var ln: Dictionary = (piece.lean as Dictionary).duplicate()
		ln["c"] = (ln.c as Vector2) + at
		out["lean"] = ln
	if piece.has("strip"):
		var lift := Vector3(at.x, 0.0, at.y)
		var inner := PackedVector3Array()
		var outer := PackedVector3Array()
		for q in piece.strip.inner:
			inner.append(q + lift)
		for q in piece.strip.outer:
			outer.append(q + lift)
		out["strip"] = { "inner": inner, "outer": outer }
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




## How far tier t's foot may reach at angle a and still stand `margin` inside
## the wall of `below` at its shelf (t leans in by then). Where a ramp or a jump
## stair up `below` arrives on that shelf, 2.5 m more: room to step off it, past
## the jag of t's outline.
static func _room(t: Dictionary, below: Dictionary, a: float, margin: float) -> float:
	var b := float(t.bury)
	var f := 1.0 - float(t.shrink) * (float(below.top) + b) / (float(t.top) + b)
	var m := margin + (2.5 if _in_arcs(below.get("smooth", []), a, 0.15) else 0.0)
	return (wall(below, a, float(below.top)) - m) / f


## A rounded stretch's radius: as far out as the lobes reach across it, but never
## past _room() anywhere along it (no tier below: the lobes alone).
static func _most_inside(t: Dictionary, below, centre: float, half: float, margin: float) -> float:
	var m := _most(t, centre, half)
	if below == null:
		return m
	for i in 25:
		m = minf(m, _room(t, below, centre - half + half * 2.0 * float(i) / 24.0, margin))
	return m


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


## A tunnel's arched ceiling under tier t: bands along its centre line, narrower
## toward the walls, each corner's underside on the arch (a half ellipse from the
## spring line at the walls to the crown) by its distance off the line. Band
## edges against another band or the wall are hidden (no faces inside rock).
static func _arch(t: Dictionary, path: PackedVector2Array, half: float, spring: float,
		crown: float, tl: Dictionary) -> Array:
	var out: Array = []
	var n := 12
	for j in n:
		var l0 := -half * cos(PI * float(j) / float(n))
		var l1 := -half * cos(PI * float(j + 1) / float(n))
		for q in Geometry2D.intersect_polygons(t.poly, _path_band(path, l0, l1)):
			var bots: Array = []
			var on: Array = []          # which band edge a corner lies on (0 none, 1 l0, 2 l1)
			for c in q:
				var l := _path_lat(path, c)
				on.append(1 if absf(l - l0) < 0.05 else (2 if absf(l - l1) < 0.05 else 0))
				var u := clampf(l / half, -1.0, 1.0)
				bots.append(spring + (crown - spring) * sqrt(maxf(0.0, 1.0 - u * u)))
			var hide: Array = []
			for i in q.size():
				var a: int = on[i]
				hide.append(a != 0 and a == int(on[(i + 1) % q.size()]))
			out.append({ "poly": q, "y0": spring, "bots": bots, "tops": [float(t.top)], "lean": tl, "hide": hide })
	return out


## The band between l0 and l1 m off a centre line (left positive), mitred at its
## corners so every corner is exactly that far off both segments it joins.
static func _path_band(path: PackedVector2Array, l0: float, l1: float) -> PackedVector2Array:
	var n := path.size()
	var miters: Array = []
	for j in n:
		var na := Vector2.ZERO
		var nb := Vector2.ZERO
		if j > 0:
			var d := (path[j] - path[j - 1]).normalized()
			na = Vector2(-d.y, d.x)
		if j < n - 1:
			var d := (path[j + 1] - path[j]).normalized()
			nb = Vector2(-d.y, d.x)
		if j == 0:
			miters.append(nb)
		elif j == n - 1:
			miters.append(na)
		else:
			miters.append((na + nb) / (1.0 + na.dot(nb)))
	var out := PackedVector2Array()
	for j in n:
		out.append(path[j] + (miters[j] as Vector2) * l0)
	for j in range(n - 1, -1, -1):
		out.append(path[j] + (miters[j] as Vector2) * l1)
	return out


## How far q is off a centre line (left positive), to its nearest segment.
static func _path_lat(path: PackedVector2Array, q: Vector2) -> float:
	var best := INF
	var lat := 0.0
	for i in path.size() - 1:
		var a := path[i]
		var ab := path[i + 1] - a
		var tt := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := (q - a - ab * tt).length()
		if d < best:
			best = d
			lat = signf(ab.cross(q - a)) * d
	return lat


## A centre line's points every `step` m along it.
static func _resample(path: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([path[0]])
	var carry := 0.0
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var len := a.distance_to(b)
		var s := step - carry
		while s <= len:
			out.append(a.lerp(b, s / len))
			s += step
		carry = len - (s - step)
	if out[-1] != path[-1]:
		out.append(path[-1])
	return out


## Where a tunnel along `path` is roofed (under any of `roofs`, the roofed tiers'
## outlines): { entry, middle, exit } (points where the arch begins, halfway
## along it, where it ends) and { s_entry, s_exit } (m along the path).
static func _tunnel_gates(path: PackedVector2Array, roofs: Array) -> Dictionary:
	var pts := _resample(path, 1.0)
	var first := -1
	var last := -1
	for i in pts.size():
		for poly in roofs:
			if Geometry2D.is_point_in_polygon(pts[i], poly):
				if first < 0:
					first = i
				last = i
				break
	if first < 0:
		return {}
	return { "entry": pts[first], "exit": pts[last], "middle": pts[(first + last) / 2],
		"s_entry": float(first), "s_exit": float(last) }


## Where one goes on the ball: turned so its first cave faces downhill, and sunk to
## the lowest sand round its foot (at most `max_sink` m), so the cave is not full of
## sand and the foot never floats. { yaw (radians), sink (m) }. Pure maths on the
## sphere, so the ship's columns and the drawn rock agree.
static func placement(sp: PlanetSphere, map: Vector2, p: Dictionary, max_sink: float = 14.0) -> Dictionary:
	var base := sp.surface_at(map.x, map.y)
	var g := Transform3D(PlanetSphere.tilt_to(sp.up_at(base)), base)
	if p.has("range"):
		return { "yaw": 0.0, "sink": 0.0, "frame": g }     # its frame is the map's, on its own level sand
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
## mean radius, its top), along the ball's up, highest first, that a ship hits;
## then one (`<id>_top`, kind "mountain") carrying the rock's tops (top_surface)
## that is the ground under a ship. A tunnel version's
## columns carry `tunnel` { path (its centre line, world), half, spring, crown,
## roofed } so WorldGround leaves its way through open (WorldGround.in_tunnel).
static func columns(sp: PlanetSphere, map: Vector2, p: Dictionary, id: String) -> Array:
	var pl := placement(sp, map, p, 14.0)
	var g: Transform3D = pl.frame
	var turn := Basis(Vector3.UP, float(pl.yaw))
	var out: Array = []
	var tiers: Array = p.tiers
	var job := top_job(p)
	for k in range(tiers.size() - 1, -1, -1):
		var t: Dictionary = tiers[k]
		var c2: Vector2 = t.centre
		var at := g * (turn * Vector3(c2.x, -float(pl.sink), c2.y))
		var h := float(t.top)
		var col := { "id": "%s_%d" % [id, k], "kind": "mesa", "center": at,
			"radius": float(t.radius) * 0.95, "up": g.basis.y, "h": h, "top": at.y + h }
		if p.has("tunnel"):
			var tn: Dictionary = p.tunnel
			var wp := PackedVector3Array()
			for q in _resample(tn.path, 10.0):
				wp.append(g * (turn * Vector3(q.x, -float(pl.sink), q.y)))
			col["tunnel"] = { "path": wp, "half": float(tn.half) - 1.0, "spring": float(tn.spring),
				"crown": float(tn.crown), "roofed": h > float(tn.crown) + 1.5 }
		col["top_job"] = job         # once it is done the tops say where the rock is
		out.append(col)
	# A tier's column is round and its rock is lobed and jagged, with ramps,
	# stairs and blocks round it, so a ship set down on its column's top sank into
	# the rock or hung over a shelf. The ground under a ship is the rock's own tops
	# (the trimesh the player stands on); the columns above only stop a ship flying
	# into the walls. Sized from the plan (the tops are still being made): the
	# ramp up from the sand stands out past the foot, the crags up past the top.
	var xf := Transform3D(g.basis * turn, g.origin - g.basis.y * float(pl.sink))
	var reach := float(p.radius) + 30.0
	var height := float(p.height) + 20.0
	out.append({ "id": "%s_top" % id, "kind": "mountain", "center": xf.origin, "up": g.basis.y,
		"radius": reach, "h": height, "top": xf.origin.y + height,
		"top_job": job, "inv": xf.affine_inverse(), "no_hit": true })
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
		var bots: Array = piece.get("bots", [])
		var hide: Array = piece.get("hide", [])
		var bot_at := func(i: int) -> float: return float(bots[i]) if bots.size() == n else y0
		# The outline at height y: shrunk toward the lean's centre (leaning cliffs).
		var ln: Dictionary = piece.get("lean", {})
		var at_y := func(q: Vector2, yy: float) -> Vector2:
			if ln.is_empty():
				return q
			var lc: Vector2 = ln.c
			return lc + (q - lc) * (1.0 - float(ln.k) * (yy + float(ln.bury)))
		for i in n:
			if hide.size() == n and bool(hide[i]):
				continue           # against another band of a tunnel's ceiling, or the wall
			var j := (i + 1) % n
			var a := poly[i]
			var b := poly[j]
			var e := b - a
			var nrm := Vector2(e.y, -e.x).normalized()
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + nrm * 0.05, poly):
				nrm = -nrm
			var out := Vector3(nrm.x, 0.0, nrm.y)
			var ya: float = bot_at.call(i)
			var yb: float = bot_at.call(j)
			var ab: Vector2 = at_y.call(a, ya)
			var bb: Vector2 = at_y.call(b, yb)
			var at_: Vector2 = at_y.call(a, top_at.call(i))
			var bt: Vector2 = at_y.call(b, top_at.call(j))
			var a0 := Vector3(ab.x, ya, ab.y)
			var b0 := Vector3(bb.x, yb, bb.y)
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
			if y0 > -0.5:      # a roof over a cave or a tunnel: its underside is the ceiling
				var b3: Array = []
				for m in 3:
					var yb: float = bot_at.call(idx[k + m])
					var q: Vector2 = at_y.call(poly[idx[k + m]], yb)
					b3.append(Vector3(q.x, yb, q.y))
				tri.call(b3[0], b3[1], b3[2], Vector3.DOWN)
	st.generate_normals()
	return { "mesh": st.commit(), "faces": PackedVector3Array(faces) }


const TOP_CELL := 4.0         ## top_surface()'s grid, metres a cell

## The rock's tops (the triangles build() makes facing up: every shelf, ramp,
## stair and block, so exactly what the trimesh has to stand on, without its walls)
## binned on a TOP_CELL grid across the plan's frame, for the ship's ground:
## { verts (three a triangle), origin, w, h (the grid's corner and size in cells),
## start, items (cell c's triangles are items[start[c]] .. items[start[c + 1] - 1]),
## reach (how far from the frame's centre any top goes), height (the highest) }.
## Made once a plan on a worker thread (top_job), this waits for it.
static func top_surface(p: Dictionary) -> Dictionary:
	var job := top_job(p)
	job.done(true)
	return job.surface


## A plan's top_surface() being made on a worker thread: columns() starts one, so
## setting the ground up never waits on it (it costs about as much as the mesh).
## done() is true once `surface` is there; until then the tiers' columns stand in.
class TopJob extends RefCounted:
	var surface: Dictionary = {}
	var task := -1

	func done(wait: bool = false) -> bool:
		if task >= 0 and (wait or WorkerThreadPool.is_task_completed(task)):
			WorkerThreadPool.wait_for_task_completion(task)
			task = -1
		return task < 0


## The plan's TopJob, started the first time it is asked for (kept on the plan;
## plans are made once a session).
static func top_job(p: Dictionary) -> TopJob:
	if p.has("_top_job"):
		return p._top_job
	var job := TopJob.new()
	p["_top_job"] = job
	job.task = WorkerThreadPool.add_task(func() -> void: job.surface = _make_top_surface(p), false, "mountain tops")
	return job


static func _make_top_surface(p: Dictionary) -> Dictionary:
	var verts := _top_tris(p)
	var nt := verts.size() / 3
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var reach := 0.0
	var height := 0.0
	for q in verts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.z))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.z))
		reach = maxf(reach, q.x * q.x + q.z * q.z)
		height = maxf(height, q.y)
	if nt == 0:
		lo = Vector2.ZERO
		hi = Vector2.ZERO
	var w := floori((hi.x - lo.x) / TOP_CELL) + 1
	var h := floori((hi.y - lo.y) / TOP_CELL) + 1
	# The cells each triangle crosses, row by row (its span across each row's band,
	# not its bounding box: a shelf's top is long thin triangles corner to corner),
	# counted per cell, then the lists packed end to end.
	var spans := PackedInt32Array()           # per row crossed: triangle, row, first cell, last cell
	var start := PackedInt32Array()
	start.resize(w * h + 1)
	for t in nt:
		# Corners by z (v0 lowest), in cells from the grid's corner.
		var v0 := Vector2(verts[t * 3].x - lo.x, verts[t * 3].z - lo.y) / TOP_CELL
		var v1 := Vector2(verts[t * 3 + 1].x - lo.x, verts[t * 3 + 1].z - lo.y) / TOP_CELL
		var v2 := Vector2(verts[t * 3 + 2].x - lo.x, verts[t * 3 + 2].z - lo.y) / TOP_CELL
		if v1.y < v0.y:
			var sw := v0
			v0 = v1
			v1 = sw
		if v2.y < v1.y:
			var sw := v1
			v1 = v2
			v2 = sw
		if v1.y < v0.y:
			var sw := v0
			v0 = v1
			v1 = sw
		for cz in range(floori(v0.y), floori(v2.y) + 1):
			# The triangle's x across this row: the long edge v0-v2 and the short
			# ones (v0-v1 below v1, v1-v2 above) at the row's two edges, and v1.
			var za := maxf(float(cz), v0.y)
			var zb := minf(float(cz + 1), v2.y)
			var xa := _edge_x(v0, v2, za)
			var xb := _edge_x(v0, v2, zb)
			var sa := _edge_x(v0, v1, za) if za <= v1.y else _edge_x(v1, v2, za)
			var sb := _edge_x(v0, v1, zb) if zb <= v1.y else _edge_x(v1, v2, zb)
			var x_lo := minf(minf(xa, xb), minf(sa, sb))
			var x_hi := maxf(maxf(xa, xb), maxf(sa, sb))
			if v1.y >= za and v1.y <= zb:
				x_lo = minf(x_lo, v1.x)
				x_hi = maxf(x_hi, v1.x)
			var x0 := clampi(floori(x_lo - 0.001), 0, w - 1)
			var x1 := clampi(floori(x_hi + 0.001), 0, w - 1)
			spans.append_array([t, clampi(cz, 0, h - 1), x0, x1])
			for cx in range(x0, x1 + 1):
				start[clampi(cz, 0, h - 1) * w + cx + 1] += 1
	for i in w * h:
		start[i + 1] += start[i]
	var fill := start.duplicate()
	var items := PackedInt32Array()
	items.resize(start[w * h])
	for k in range(0, spans.size(), 4):
		var row := spans[k + 1] * w
		for cx in range(spans[k + 2], spans[k + 3] + 1):
			items[fill[row + cx]] = spans[k]
			fill[row + cx] += 1
	return { "verts": verts, "origin": lo, "w": w, "h": h, "start": start, "items": items,
		"reach": sqrt(reach), "height": height }


## x where the edge p0-p1 (x, z) is at z (clamped onto it).
static func _edge_x(p0: Vector2, p1: Vector2, z: float) -> float:
	var dz := p1.y - p0.y
	if dz < 1e-9:
		return p0.x
	return p0.x + (p1.x - p0.x) * clampf((z - p0.y) / dz, 0.0, 1.0)


## build()'s up-facing triangles alone: each piece's top (its outline drawn in by
## the lean at its top's height) and each ramp strip's top.
static func _top_tris(p: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	for piece in p.pieces:
		if piece.has("strip"):
			var inner: PackedVector3Array = piece.strip.inner
			var outer: PackedVector3Array = piece.strip.outer
			for i in inner.size() - 1:
				out.append_array([outer[i], outer[i + 1], inner[i + 1], outer[i], inner[i + 1], inner[i]])
			continue
		var poly: PackedVector2Array = piece.poly
		var n := poly.size()
		if n < 3:
			continue
		var tops: Array = piece.tops
		var ln: Dictionary = piece.get("lean", {})
		var lc := Vector2.ZERO
		var lk := 0.0
		var lb := 0.0
		if not ln.is_empty():
			lc = ln.c
			lk = float(ln.k)
			lb = float(ln.bury)
		for i in Geometry2D.triangulate_polygon(poly):
			var yy := float(tops[i] if tops.size() == n else tops[0])
			var q := lc + (poly[i] - lc) * (1.0 - lk * (yy + lb))
			out.append(Vector3(q.x, yy, q.y))
	return out


## The highest rock top straight under (x, z) in the plan's frame no higher than
## `below` (a roof over a cave or the tunnel is not the floor), or -INF.
static func top_at(s: Dictionary, x: float, z: float, below: float) -> float:
	var o: Vector2 = s.origin
	var cx := floori((x - o.x) / TOP_CELL)
	var cz := floori((z - o.y) / TOP_CELL)
	var w: int = s.w
	if cx < 0 or cz < 0 or cx >= w or cz >= int(s.h):
		return -INF
	var start: PackedInt32Array = s.start
	var items: PackedInt32Array = s.items
	var verts: PackedVector3Array = s.verts
	var ci := cz * w + cx
	var best := -INF
	for k in range(start[ci], start[ci + 1]):
		var t := items[k]
		var a := verts[t * 3]
		var b := verts[t * 3 + 1]
		var c := verts[t * 3 + 2]
		var e0x := b.x - a.x
		var e0z := b.z - a.z
		var e1x := c.x - a.x
		var e1z := c.z - a.z
		var den := e0x * e1z - e1x * e0z
		if absf(den) < 1e-9:
			continue
		var px := x - a.x
		var pz := z - a.z
		var u := (px * e1z - e1x * pz) / den
		var v := (e0x * pz - px * e0z) / den
		if u < -1e-5 or v < -1e-5 or u + v > 1.00001:
			continue
		var y := a.y + u * (b.y - a.y) + v * (c.y - a.y)
		if y <= below and y > best:
			best = y
	return best


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
	var far: float = Array(t.table).max()
	var radial := Vector2.from_angle(a)
	var side := Vector2.from_angle(a + PI * 0.5) * mouth * 0.5
	var outer: Vector2 = c + radial * (far + 8.0)    # past the furthest lobe
	var inner := c + radial * (_lobed(t, a) - depth)
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
