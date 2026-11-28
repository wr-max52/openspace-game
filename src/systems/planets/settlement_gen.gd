class_name SettlementGen
extends RefCounted
## Issue #877: the mountain country's towns, as layouts. Pure: each place in a
## planet's `settlements` block (content/core/planets/port_red.json) becomes the
## same layout dictionary TownGen makes (boxes, markers, routes, zones), so
## TownLayout validates it rule for rule (V1 to V9) and Settlements builds,
## dresses and peoples it. Every layout is in the place's own frame: y 0 is the
## top of its peak, +x is its gate (where its lift or its ramp comes in).
##
## Three kinds, each a variation of something the game has:
##   town   TownGen at a small size with no landing bay (opts bay "none": nothing
##          lands on a peak), from the shared kit with the place's `kit` laid
##          over it: its houses, its proportions, its cantina's size. The gate's
##          apron is cut to `apron` m, so the town stops short of the cliff.
##   ring   a ranch ring: three or four houses round a yard inside one round wall
##          (RingWall, the round port's), a small cantina (TownGen's own, its
##          bar, owner, stage and patrons) on the far side, a stall and a fire.
##   ledge  a hamlet on a low shelf: two huts, a stall, a watch tower and a
##          shrine, the ranch villages' pieces.
##
## People: every marker's soldier goes through the place's `folk` (its own
## locals, in their own outfits, content/core/soldiers/<folk>_<role>.json):
## residents, merchants, patrons and the guards on TownGen's trooper posts (the
## locals guard their own towns: no Remnant up here). The cantina owner's spot is
## the barkeep's.

const KIT_PATH := "res://content/core/planets/town_kit.json"
## TownGen's soldiers -> the role a place's own folk fills.
const ROLES := { "local_resident": "resident", "local_merchant": "merchant", "local_patron": "patron",
	"gate_guard": "guard", "yard_trooper": "guard", "tower_sentry": "guard" }


## The place's layout, people and all. `cfg`: the planet's settlements block (its
## cantina sizes).
static func layout(place: Dictionary, cfg: Dictionary = {}) -> Dictionary:
	var out: Dictionary
	match str(place.get("kind", "town")):
		"ring":
			out = ring(place, cfg)
		"ledge":
			out = ledge(place)
		_:
			out = town(place, cfg)
	out["id"] = str(place.get("id", "settlement"))
	out["kind"] = "settlement"
	_folk(out, place)
	return out


## The shared town kit with the place's `kit` laid over it (a dictionary in it,
## like `counts`, is laid over key by key) and its cantina's size.
static func kit_for(place: Dictionary, cfg: Dictionary = {}) -> Dictionary:
	var kit: Dictionary = TownGen._read(KIT_PATH)
	var over: Dictionary = place.get("kit", {})
	for k in over:
		if k == "note":
			continue
		if kit.get(k) is Dictionary and over[k] is Dictionary:
			var d: Dictionary = (kit[k] as Dictionary).duplicate(true)
			for kk in over[k]:
				d[kk] = over[k][kk]
			kit[k] = d
		else:
			kit[k] = over[k]
	var dims: Dictionary = cfg.get("cantinas", {}).get(str(place.get("cantina", "small")), {})
	if not dims.is_empty():
		var c: Dictionary = (kit.get("cantina", {}) as Dictionary).duplicate(true)
		c["small"] = { "length": float(dims.get("length", 18.0)), "width": float(dims.get("width", 14.0)),
			"height": float(dims.get("height", 5.5)) }
		c["full_from_size"] = 1000                  # always "small": its size is the place's
		c["patrons_from_size"] = 1                  # every cantina up here has its drinkers
		var st: Dictionary = (c.get("stage", {}) as Dictionary).duplicate(true)
		st["small"] = float(dims.get("stage", st.get("small", 4.0)))
		c["stage"] = st
		kit["cantina"] = c
	return kit


# ------------------------------------------------------------------ town

static func town(place: Dictionary, cfg: Dictionary = {}) -> Dictionary:
	var opts := { "bay": "none" }
	if bool(place.get("dancer", false)):
		opts["stage_dancer"] = true
	var kit := kit_for(place, cfg)
	var out := TownGen.generate(str(place.get("id", "settlement")), int(place.get("size", 6)),
		int(place.get("seed", 1)), opts, kit)
	_pack_houses(out, kit, place)
	return out


## A peak has no room to spare: after TownGen's own lots, every gap big enough for
## a lot (clear of every building, the street, the gate's mouth and every walk by a
## lane) takes a house too, the place's huts or towers, and `residents` of them
## have someone strolling round. Same lots, same houses, same strolls as TownGen's.
static func _pack_houses(out: Dictionary, kit: Dictionary, place: Dictionary) -> void:
	var g := TownGen.new(kit)
	g._rng.seed = int(place.get("seed", 1)) * 31337
	g._boxes = out.boxes
	g._markers = out.markers
	g._routes = out.routes
	var lane := float(kit.get("lane", 4.0))
	var lot := float(kit.get("lot", 10.0))
	var sh := float(kit.get("street_half", 6.0))
	var wt := float(kit.get("wall", {}).get("thickness", 2.0))
	var b: Dictionary = out.bounds
	var xi0 := float(b.min[0]) + wt
	var zi0 := float(b.min[1]) + wt
	var xi1 := float(b.max[0]) - wt
	var zi1 := float(b.max[1]) - wt
	var taken: Array = [Rect2(xi0, -sh, xi1 - xi0, 2.0 * sh), Rect2(xi1 - 10.0, -8.0, 10.0, 16.0)]
	for bx in out.boxes:
		if str(bx.get("zone", "")) in ["ground", "perimeter"] or str(bx.kind) == "floor":
			continue
		taken.append(Rect2(float(bx.min[0]), float(bx.min[2]), float(bx.max[0]) - float(bx.min[0]),
			float(bx.max[2]) - float(bx.min[2])))
	for r in out.routes:
		var pts: Array = r.points
		for k in range(1, pts.size()):
			var a := Vector2(float(pts[k - 1][0]), float(pts[k - 1][1]))
			var c := Vector2(float(pts[k][0]), float(pts[k][1]))
			taken.append(Rect2(a, Vector2.ZERO).expand(c).grow(0.6))
	for m in out.markers:
		taken.append(Rect2(float(m.pos[0]) - 0.8, float(m.pos[2]) - 0.8, 1.6, 1.6))
	var lots: Array = []
	var z := zi0 + lane
	while z + lot <= zi1 - lane:
		var x := xi0 + lane
		while x + lot <= xi1 - lane:
			var r := Rect2(x, z, lot, lot)
			var grown := r.grow(lane - 0.01)
			var ok := true
			for t in taken:
				if grown.intersects(t):
					ok = false
					break
			if ok:
				lots.append(r)
				taken.append(r)
			x += 1.0
		z += 1.0
	var towers := kit.get("towers", []) as Array
	var share := float(kit.get("tower_share", 0.3))
	var have := 0
	for m in out.markers:
		if str(m.get("id", "")).begins_with("resident_"):
			have += 1
	var want := int(place.get("residents", 6))
	for i in lots.size():
		var r: Rect2 = lots[i]
		var north := r.get_center().y > 0.0
		var pool: Array = towers if north and not towers.is_empty() and g._rng.randf() < share else kit.get("huts", [])
		g._building("house_p_%02d" % (i + 1), r, g._weighted(pool), north)
		if have < want:
			have += 1
			var hb: Dictionary = out.boxes[-1]          # the house itself (it can stand a little past its lot)
			var rr := Rect2(float(hb.min[0]), float(hb.min[2]), float(hb.max[0]) - float(hb.min[0]),
				float(hb.max[2]) - float(hb.min[2])).merge(r).grow(lane * 0.5)
			var id := "resident_%d" % have
			out.routes.append({ "id": "stroll_" + id, "points": [[rr.position.x, rr.position.y], [rr.end.x, rr.position.y],
				[rr.end.x, rr.end.y], [rr.position.x, rr.end.y], [rr.position.x, rr.position.y]] })
			out.markers.append({ "id": id, "pos": [rr.position.x, 0, rr.position.y], "role": "ambient",
				"soldier": "local_resident", "patrol": "stroll_" + id })


# ------------------------------------------------------------------ ring

## A ranch ring on a peak. `ring_r` (the wall's outer radius), `houses` (3 or 4).
static func ring(place: Dictionary, cfg: Dictionary = {}) -> Dictionary:
	var g := TownGen.new(kit_for(place, cfg))
	g._rng.seed = int(place.get("seed", 1)) * 7919
	var r := float(place.get("ring_r", 24.0))
	var t := float(place.get("ring_thickness", 1.2))
	var h := float(place.get("ring_height", 3.6))
	var gate := float(place.get("gate_half", 3.5))
	var apron := float(place.get("apron", 6.0))
	var inner := r - t
	g._layout_box("ground", "ground", "floor", [-r - 3.0, -0.5, -r - 3.0], [r + apron, 0, r + 3.0])
	g._layout_box("ring_wall", "perimeter", "ring", [-r, 0, -r], [r, h, r],
		{ "thickness": t, "hollow": true, "piece": 4.0, "gaps": [{ "deg": 0, "half": gate }], "look": "ring_wall" })
	g._marker("gate", [r - t * 0.5, 0, 0], "waypoint")
	g._marker("desert_exit", [r + apron * 0.5, 0, 0], "waypoint")
	g._zones.append({ "id": "yard", "min": [-inner, -inner], "max": [inner, inner] })
	# The cantina on the far side of the yard, its door toward the gate.
	var ccfg: Dictionary = g.kit.get("cantina", {})
	var cd: Dictionary = ccfg.get("small", {})
	var cl := float(cd.get("length", 14.0))
	var cw := float(cd.get("width", 12.0))
	var x0 := -sqrt(maxf(pow(inner - 1.0, 2.0) - pow(cw * 0.5, 2.0), 0.0)) + 0.5
	x0 = ceilf(x0)
	var cantina: Dictionary = g._cantina(x0, cl, cw, float(cd.get("height", 5.5)), float(ccfg.get("door_half", 2.0)),
		{}, true)
	# Houses round the yard, doors toward the fire.
	var fire := Vector2(float(cantina.end) + (r - float(cantina.end)) * 0.4, 0.0)
	var n := clampi(int(place.get("houses", 4)), 3, 4)
	var angles: Array = [62.0, 118.0, 242.0, 298.0] if n == 4 else [70.0, 180.0 + 110.0, 125.0]
	var pool: Array = g.kit.get("huts", [])
	var hr := inner - 8.0
	for i in n:
		var a := deg_to_rad(float(angles[i]))
		var c := Vector2(cos(a), sin(a)) * hr
		var look := g._weighted(pool)
		var wr: Array = look.get("w", [5, 7])
		var bw := float(g._rng.randi_range(int(wr[0]), int(wr[1])))
		var round := bool(look.get("round", false))
		var dr: Array = look.get("d", wr)
		var bd := bw if round else float(g._rng.randi_range(int(dr[0]), int(dr[1])))
		var hh: Array = look.get("h", [4.0, 5.0])
		var bh := snappedf(g._rng.randf_range(float(hh[0]), float(hh[1])), 0.5)
		c = Vector2(snappedf(c.x, 0.5), snappedf(c.y, 0.5))
		var north := c.y > 0.0
		var extra := { "look": str(look.look), "face": "-z" if north else "+z" }
		if round:
			extra["shape"] = "round"
		var id := "house_%d" % (i + 1)
		g._layout_box(id, "yard", "solid", [c.x - bw * 0.5, 0, c.y - bd * 0.5], [c.x + bw * 0.5, bh, c.y + bd * 0.5], extra)
		var door := c + Vector2(0.0, -1.0 if north else 1.0) * (bd * 0.5 + 1.4)
		g._markers.append({ "id": "resident_%d" % (i + 1), "pos": [snappedf(door.x, 0.1), 0, snappedf(door.y, 0.1)],
			"role": "ambient", "soldier": "local_resident", "face": [fire.x, 0, fire.y] })
	# A stall east of the fire, its keeper behind it, facing the fire.
	var sx := snappedf(fire.x + 6.0, 0.5)
	g._layout_box("stall_1", "yard", "cover", [sx, 0, -2.0], [sx + 1.0, 1.1, 2.0], { "look": "stall", "face": "-x" })
	g._layout_box("stall_1_back", "yard", "solid", [sx + 3.6, 0, -2.0], [sx + 4.0, 2.6, 2.0], { "look": "stall_back" })
	g._markers.append({ "id": "vendor_1", "pos": [sx + 2.3, 0, 0], "role": "ambient", "soldier": "local_merchant",
		"face": [fire.x, 0, 0] })
	g._markers.append({ "id": "fire", "pos": [snappedf(fire.x, 0.1), 0, 0], "role": "waypoint" })
	# Two guards inside the gate, looking out, and a pair walking the yard.
	for s in [-1.0, 1.0]:
		g._markers.append({ "id": "guard_%s" % ("n" if s > 0 else "s"), "pos": [snappedf(inner - 3.0, 0.1), 0, 5.0 * s],
			"role": "trooper_post", "soldier": "gate_guard", "face": [r + 20.0, 0, 5.0 * s] })
	var loop: Array = []
	var lr := 5.0
	for k in 9:
		var a := TAU * float(k) / 8.0
		loop.append([snappedf(fire.x + cos(a) * lr, 0.1), snappedf(sin(a) * lr * 0.9, 0.1)])
	g._routes.append({ "id": "yard_loop", "points": loop })
	for k in 2:
		var p: Array = loop[k * 4]
		g._markers.append({ "id": "roamer_%d" % (k + 1), "pos": [p[0], 0, p[1]], "role": "ambient",
			"soldier": "local_resident", "patrol": "yard_loop" })
	return _finish(g, place, Rect2(-r - 3.0, -r - 3.0, 2.0 * r + 3.0 + apron, 2.0 * r + 6.0))


# ------------------------------------------------------------------ ledge

## A hamlet on a low shelf: `half` m each way from its middle.
static func ledge(place: Dictionary) -> Dictionary:
	var g := TownGen.new(TownGen._read(KIT_PATH))
	g._rng.seed = int(place.get("seed", 1)) * 104729
	var l := float(place.get("half", 13.0))
	g._layout_box("ground", "ground", "floor", [-l, -0.5, -l], [l, 0, l])
	var pool: Array = g.kit.get("huts", [])
	var houses := [Vector2(-7.0, -6.0), Vector2(-7.0, 6.0)]
	for i in houses.size():
		var c: Vector2 = houses[i]
		var look := g._weighted(pool)
		var round := bool(look.get("round", false))
		var bw := 6.0
		var bd := 6.0 if round else 5.0
		var hh: Array = look.get("h", [4.0, 5.0])
		var extra := { "look": str(look.look), "face": "+x" }
		if round:
			extra["shape"] = "round"
		g._layout_box("house_%d" % (i + 1), "ground", "solid", [c.x - bw * 0.5, 0, c.y - bd * 0.5],
			[c.x + bw * 0.5, snappedf(g._rng.randf_range(float(hh[0]), float(hh[1])), 0.5), c.y + bd * 0.5], extra)
		g._markers.append({ "id": "resident_%d" % (i + 1), "pos": [c.x + bw * 0.5 + 1.5, 0, c.y], "role": "ambient",
			"soldier": "local_resident", "face": [l, 0, c.y] })
	g._layout_box("watch", "ground", "solid", [6.0, 0, -11.0], [10.0, float(place.get("watch_h", 9.0)), -7.0],
		{ "look": "watchtower", "face": "-x" })
	g._layout_box("shrine", "ground", "cover", [6.0, 0, 6.0], [8.0, 1.0, 8.0], { "look": "shrine" })
	g._markers.append({ "id": "pilgrim", "pos": [4.6, 0, 7.0], "role": "ambient", "soldier": "local_patron",
		"face": [7.0, 0, 7.0] })
	g._layout_box("stall_1", "ground", "cover", [-1.0, 0, -10.0], [3.0, 1.1, -9.0], { "look": "stall", "face": "+z" })
	g._layout_box("stall_1_back", "ground", "solid", [-1.0, 0, -12.6], [3.0, 2.6, -12.2], { "look": "stall_back" })
	g._markers.append({ "id": "vendor_1", "pos": [1.0, 0, -11.3], "role": "ambient", "soldier": "local_merchant",
		"face": [1.0, 0, 0] })
	g._marker("gate", [l - 1.0, 0, 0], "waypoint")
	return _finish(g, place, Rect2(-l, -l, 2.0 * l, 2.0 * l))


static func _finish(g: TownGen, place: Dictionary, bounds: Rect2) -> Dictionary:
	return {
		"id": str(place.get("id", "settlement")),
		"units": "meters",
		"generated": { "by": "SettlementGen", "seed": int(place.get("seed", 1)) },
		"bounds": { "min": [bounds.position.x, bounds.position.y], "max": [bounds.end.x, bounds.end.y] },
		"player_clearance": 0.6,
		"blocking_kinds": ["wall", "solid", "cover", "counter", "ship"],
		"zones": g._zones,
		"boxes": g._boxes,
		"markers": g._markers,
		"routes": g._routes,
		"locals": { "alarm": g.kit.get("alarms", {}).get("locals", {}) },
	}


# ------------------------------------------------------------------ people

## Every soldier through the place's folk; the cantina owner's spot to its barkeep.
static func _folk(out: Dictionary, place: Dictionary) -> void:
	var folk := str(place.get("folk", ""))
	if folk == "":
		return
	for m in out.get("markers", []):
		var s := str(m.get("soldier", ""))
		if ROLES.has(s):
			m["soldier"] = "%s_%s" % [folk, ROLES[s]]
			if str(m.get("role", "")) == "trooper_post":
				m["role"] = "ambient"
		elif str(m.get("id", "")) == "cantina_owner":
			m["role"] = "ambient"
			m["soldier"] = "%s_barkeep" % folk
			m.erase("npc")


## How far the layout reaches from its middle: the half-diagonal of its floors
## (the town, its walls and the apron at its gate), about `centre(out)`.
static func fit(out: Dictionary) -> float:
	var r := _floors(out)
	return (r.size * 0.5).length()


## The middle of its floors, [x, z]: the point that sits on the middle of its peak.
static func centre(out: Dictionary) -> Vector2:
	return _floors(out).get_center()


static func _floors(out: Dictionary) -> Rect2:
	var r := Rect2()
	var first := true
	for b in out.get("boxes", []):
		if str(b.kind) != "floor":
			continue
		var q := Rect2(float(b.min[0]), float(b.min[2]), float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2]))
		r = q if first else r.merge(q)
		first = false
	return r


## The places' soldier ids (each `<folk>_<role>`), for tests and the content check.
static func soldiers(out: Dictionary) -> Array:
	var ids: Array = []
	for m in out.get("markers", []):
		if m.has("soldier") and not ids.has(str(m.soldier)):
			ids.append(str(m.soldier))
	return ids
