class_name FieldRocks
extends RefCounted
## Issue #880: an asteroid field's rocks, wrecks and the rock under each outpost,
## laid out from the "field" landmark of a planet on the field type (content/core/
## planets/types.json; the red system's field: content/core/planets/scatter_field.json).
##
## The same layout every time (the landmark's seed), and no look needed for it, so
## the colliders, the traces and the game agree:
##
##   - the home rock under the town's deck (the dock), level, its flat top a few
##     metres under the deck's keel slab
##   - one rock under each outpost (the field's "station" landmarks; their spots in
##     the station's own frame: outpost_rocks)
##   - chains ("paths") of rocks from the home rock to every outpost, every wreck's
##     pad and the stranded pilot's far rock, a jump apart (gap), so you can hop out
##     to each on foot
##   - scattered rocks round them (scatter), and hundreds of small ones that are
##     only seen (small: no collision, they tumble)
##   - the wrecked cruisers among them (wrecks: posed like the belt's, BeltWrecks;
##     "wreck" landmarks the ground adds, or leaves for later on a no-fade handoff)
##
## Every big rock is one of VARIANTS shared meshes (a lumpy ball, squashed, its
## top cut flat so you can stand and land on it), scaled and turned. In the world
## each is a WorldGround box of kind "roof" in its own frame (ships bump into it
## and set down on its top: height_above) carrying its hull's points ("convex": the
## feet's collider, WorldScenery), and a gravity body of the ball (PlanetSphere.
## add_gravity_body): near it, your feet stick to it.

const KIND := "field"
const VARIANTS := 6
const SQUASH := 0.72               ## a rock is this flat (y over x and z)
const TOP := 0.42                  ## its top is cut flat here (x its radius)
const LUMP := 0.55                 ## how lumpy (the noise's swing, x its radius)
const CORE := Vector3(0.6, 0.15, 0.6)   ## its gravity core box's half size (x its radius)
const SKIN := 0.27                 ## from that core out to its face (x its radius)

static var _units: Array = []      ## per variant: { tris, points, box }
static var _cache := {}            ## planet id -> layout


## The field landmark of a world's settings, or {}.
static func cfg_of(world: Dictionary) -> Dictionary:
	for lm in world.get("landmarks", []):
		if str((lm as Dictionary).get("kind", "")) == KIND:
			return lm
	return {}


# ------------------------------------------------------------------ the shared rocks

## Variant `v`'s rock at radius 1: { tris (every triangle's corners, in order),
## points (each corner once: the hull), box (its bounds) }.
static func unit(v: int) -> Dictionary:
	if _units.is_empty():
		for i in VARIANTS:
			_units.append(_make_unit(i))
	return _units[posmod(v, VARIANTS)]


static func _make_unit(v: int) -> Dictionary:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 8
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = 880 + v * 17
	noise.frequency = 0.9
	noise.fractal_octaves = 3
	var moved := PackedVector3Array()
	moved.resize(verts.size())
	var seen := {}
	var points := PackedVector3Array()
	var box := AABB()
	for i in verts.size():
		var d := verts[i].normalized()
		var k := 1.0 + noise.get_noise_3dv(d * 1.6) * LUMP
		var p := d * k
		p.y = minf(p.y * SQUASH, TOP)
		moved[i] = p
		var key := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
		if not seen.has(key):
			seen[key] = true
			points.append(p)
			box = AABB(p, Vector3.ZERO) if points.size() == 1 else box.expand(p)
	var tris := PackedVector3Array()
	for i in idx:
		tris.append(moved[i])
	return { "tris": tris, "points": points, "box": box }


## A shared rock mesh (flat faces) for the looks.
static func unit_mesh(v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for p in (unit(v).tris as PackedVector3Array):
		st.add_vertex(p)
	st.generate_normals()
	return st.commit()


## A rock's frame (its centre, turned; not scaled).
static func frame_of(rock: Dictionary) -> Transform3D:
	return Transform3D(rock.basis, rock.c)


## Its top's middle in the world (where you stand, where a ship sets down).
static func top_of(rock: Dictionary) -> Vector3:
	return frame_of(rock) * Vector3(0, TOP * float(rock.r), 0)


# ------------------------------------------------------------------ the layout

## The field laid out: { rocks: [{ id, c, r, basis, v, role, to? }], small: [{ c, r,
## basis, spin }], wrecks: [{ id, landmark, xf, level, pad }], deck: Rect2, home,
## sites: { pilot, crate } } (world points). `deck`: the town's floors (xz).
## The same for the same landmark and deck; kept per planet (cached()).
static func layout(world: Dictionary, sp: PlanetSphere, deck: Rect2) -> Dictionary:
	var lm := cfg_of(world)
	var out := { "rocks": [], "small": [], "wrecks": [], "deck": deck, "sites": {}, "cfg": lm }
	if lm.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lm.get("seed", 880))
	var rocks: Array = out.rocks
	# The dock: level under the deck, wide enough that the deck overhangs it a little.
	var hc: Dictionary = lm.get("home", {})
	var half := maxf(deck.size.x, deck.size.y) * 0.5
	var hr := maxf(30.0, half * float(hc.get("scale", 0.9)))
	var face := float(hc.get("face_y", -6.5))
	var dc := deck.get_center()
	var home := _rock("home", Vector3(dc.x, face - TOP * hr, dc.y), hr, Basis.IDENTITY, 0, "home")
	rocks.append(home)
	out["home"] = home
	# The outposts' rocks: each spot in its station's frame, the rock's top just under it.
	var targets: Array = []
	var spots: Array = lm.get("outpost_rocks", [])
	for slm in world.get("landmarks", []):
		if str((slm as Dictionary).get("kind", "")) != StationHull.LANDMARK_KIND or sp == null:
			continue
		var h := StationHull.for_id(str(slm.get("station", "")))
		if h == null:
			continue
		var sxf := h.frame_for(sp, slm, world)
		for j in spots.size():
			var s: Dictionary = spots[j]
			var r := float(s.get("radius", 40.0))
			var top := sxf * _v3(s.get("at", [0, -1.5, 0]))
			var rock := _rock("%s_rock_%d" % [str(slm.get("id", "")), j + 1], top - sxf.basis.y * TOP * r, r,
				sxf.basis, j + 1, "outpost")
			rock["outpost"] = str(slm.get("id", ""))
			rocks.append(rock)
			if j == 0:
				targets.append(rock)
	# The wrecks, posed like the belt's: `at` is the middle of the pad you come in on.
	for i in (lm.get("wrecks", []) as Array).size():
		var w := _wreck(lm.wrecks[i], i)
		out.wrecks.append(w)
		targets.append({ "c": w.pad, "r": 30.0, "id": w.id, "wreck": true })
	# The stranded pilot's far rock.
	var pc: Dictionary = (lm.get("sites", {}) as Dictionary).get("pilot", {})
	if not pc.is_empty():
		var pr := float(pc.get("radius", 18.0))
		var prock := _rock("pilot_rock", _v3(pc.get("at", [0, 0, 0])) - Vector3.UP * TOP * pr, pr,
			_tilt(rng, 12.0), 3, "pilot")
		rocks.append(prock)
		targets.append(prock)
		out.sites["pilot"] = top_of(prock) + Vector3(0, 1.0, 0)
	var cc: Dictionary = (lm.get("sites", {}) as Dictionary).get("crate", {})
	if not cc.is_empty():
		out.sites["crate"] = _v3(cc.get("at", [0, 0, 0]))
	# The paths: a hop at a time from the dock toward each.
	var path_r: Array = lm.get("path_radius", [12, 26])
	var gap: Array = lm.get("gap", [10, 26])
	var avoid: Array = out.wrecks
	for t in targets:
		_chain(rng, rocks, home, t, path_r, gap, avoid)
	# Scattered rocks round it all.
	var sc: Dictionary = lm.get("scatter", {})
	var sbox: Array = sc.get("box", [-1400, -250, -1400, 1400, 150, 1400])
	var srad: Array = sc.get("radius", [10, 34])
	var placed := 0
	var tries := 0
	while placed < int(sc.get("count", 40)) and tries < 4000:
		tries += 1
		var c := Vector3(rng.randf_range(sbox[0], sbox[3]), rng.randf_range(sbox[1], sbox[4]), rng.randf_range(sbox[2], sbox[5]))
		var r := rng.randf_range(srad[0], srad[1])
		if Vector2(c.x - dc.x, c.z - dc.y).length() < half + 120.0 or not _clear(rocks, avoid, c, r, 18.0):
			continue
		rocks.append(_rock("scatter_%d" % (placed + 1), c, r, _tilt(rng, 30.0), rng.randi_range(0, VARIANTS - 1), "scatter"))
		placed += 1
	# The small ones: only seen.
	var sm: Dictionary = lm.get("small", {})
	var mbox: Array = sm.get("box", sbox)
	var mrad: Array = sm.get("radius", [0.6, 3.5])
	for i in int(sm.get("count", 300)):
		var c := Vector3(rng.randf_range(mbox[0], mbox[3]), rng.randf_range(mbox[1], mbox[4]), rng.randf_range(mbox[2], mbox[5]))
		if Vector2(c.x - dc.x, c.z - dc.y).length() < half + 25.0:
			continue
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		out.small.append({ "c": c, "r": rng.randf_range(mrad[0], mrad[1]),
			"basis": Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)),
			"axis": axis.normalized() if axis.length() > 0.01 else Vector3.UP, "spin": rng.randf_range(0.05, 0.35),
			"v": rng.randi_range(0, VARIANTS - 1) })
	return out


## The layout for the ground's world, made once per planet.
static func for_ground(ground: WorldGround) -> Dictionary:
	var pid := str(ground.world.get("planet", ""))
	if _cache.has(pid):
		return _cache[pid]
	var L := layout(ground.world, ground.sphere(), deck_of(ground))
	_cache[pid] = L
	return L


## The layout already made for a planet ({} before the ground was set up).
static func cached(planet_id: String) -> Dictionary:
	return _cache.get(planet_id, {})


## The town's floors (xz) from the ground's own boxes (no "/": not a landmark's).
static func deck_of(ground: WorldGround) -> Rect2:
	var r := Rect2()
	var any := false
	for b in ground.boxes:
		if str(b.kind) != "floor" or str(b.id).contains("/"):
			continue
		var br := Rect2(Vector2(b.min.x, b.min.z), Vector2(b.max.x - b.min.x, b.max.z - b.min.z))
		r = br if not any else r.merge(br)
		any = true
	return r if any else Rect2(-40, -40, 80, 80)


static func _rock(id: String, c: Vector3, r: float, basis: Basis, v: int, role: String) -> Dictionary:
	return { "id": id, "c": c, "r": r, "basis": basis, "v": posmod(v, VARIANTS), "role": role }


## A turn of up to `deg` off level, any heading.
static func _tilt(rng: RandomNumberGenerator, deg: float) -> Basis:
	var yaw := rng.randf() * TAU
	var lean := deg_to_rad(rng.randf_range(0.0, deg))
	var axis := Vector3(cos(yaw), 0, sin(yaw))
	return Basis(axis, lean) * Basis(Vector3.UP, rng.randf() * TAU)


## Is a rock at c (radius r) clear of the rocks and wrecks so far, by `margin`?
static func _clear(rocks: Array, wrecks: Array, c: Vector3, r: float, margin: float) -> bool:
	for o in rocks:
		if c.distance_to(o.c) < r + float(o.r) + margin:
			return false
	for w in wrecks:
		if in_wreck(w, c, r + margin):
			return false
	return true


## Is world point p within `grow` metres of wreck w's hull box?
static func in_wreck(w: Dictionary, p: Vector3, grow: float = 0.0) -> bool:
	var q := (w.xf as Transform3D).affine_inverse() * p
	var h: Vector3 = BeltWrecks.BOX_HALF + Vector3(grow, grow, grow + BeltWrecks.ENGINES_OUT * 0.5)
	return absf(q.x) <= h.x and absf(q.y) <= h.y and absf(q.z) <= h.z


## Rocks from `from` toward target t ({ c, r }), each a jump past the one before,
## until the last is a jump from t. A rock that would hit another (or a wreck)
## swings aside; the path gives up after a few tries rather than overlap.
static func _chain(rng: RandomNumberGenerator, rocks: Array, from: Dictionary, t: Dictionary, path_r: Array,
		gap: Array, wrecks: Array) -> void:
	var cur := from
	var tid := str(t.get("id", "target"))
	var n := 0
	while n < 40:
		var to: Vector3 = t.c
		var rem: float = (cur.c as Vector3).distance_to(to) - float(cur.r) - float(t.r)
		if rem <= float(gap[1]):
			return
		var r := rng.randf_range(path_r[0], path_r[1])
		var g := rng.randf_range(gap[0], gap[1])
		var placed := false
		for tryi in 8:
			var dir: Vector3 = (to - (cur.c as Vector3)).normalized()
			var yaw := deg_to_rad(rng.randf_range(-18.0, 18.0) * (1.0 + tryi * 0.5))
			dir = dir.rotated(Vector3.UP, yaw)
			dir.y = clampf(dir.y + rng.randf_range(-0.08, 0.08), -0.35, 0.35)
			dir = dir.normalized()
			var c: Vector3 = cur.c + dir * (float(cur.r) + g + r)
			if t.get("wreck", false) and c.distance_to(to) < r + 20.0:
				break                       # the wreck's pad is the last hop
			var others := rocks.filter(func(o): return o != cur)
			if not _clear(others, wrecks, c, r, 6.0):
				continue
			var rock := _rock("path_%s_%d" % [tid, n + 1], c, r, _tilt(rng, 22.0), rng.randi_range(0, VARIANTS - 1), "path")
			rock["to"] = tid
			rocks.append(rock)
			cur = rock
			placed = true
			break
		if not placed:
			return
		n += 1


## A wreck from its spec: { id, landmark, xf, level, pad }, posed like the belt's
## (BeltWrecks.layout) with its pad's middle at `at`, heading yaw_deg (its stern's
## way, from +z), pitched and listed.
static func _wreck(spec: Dictionary, i: int) -> Dictionary:
	var at := _v3(spec.get("at", [0, 0, 0]))
	var dir := Vector3.BACK.rotated(Vector3.UP, deg_to_rad(float(spec.get("yaw_deg", 0.0))))
	var pitch := float(spec.get("pitch_deg", 0.0))
	var variant: Dictionary = spec.get("variant", {})
	var pose := StarcruiserWreck.Pose.new(pitch, float(variant.get("deck_drop", 0.0)))
	var tangent := Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP, dir) \
		* Basis(Vector3.BACK, deg_to_rad(float(spec.get("roll_deg", 0.0))))
	var pad_d := _v3(spec.get("pad_design", [0, 146, 138]))
	var inside := pad_d + Vector3(0, pose.shift.x, pose.shift.y)
	var origin := at - tangent * inside
	var xf := Transform3D(tangent * Basis(Vector3.RIGHT, deg_to_rad(pitch)), origin)
	var id := str(spec.get("id", "field_wreck_%d" % (i + 1)))
	var lm: Dictionary = spec.duplicate(true)
	lm.erase("at")
	lm.erase("note")
	lm["id"] = id
	lm["kind"] = "wreck"
	lm["adrift"] = true
	lm["frame"] = xf
	return { "id": id, "landmark": lm, "xf": xf,
		"level": Transform3D(tangent, origin) * Transform3D(Basis.IDENTITY, Vector3(0, pose.shift.x, pose.shift.y)),
		"pad": at, "box_half": BeltWrecks.BOX_HALF + Vector3(0, 0, BeltWrecks.ENGINES_OUT * 0.5) }


## Where the field's own up holds round wreck w: level at its middle, turned with
## its heading only (as BeltWrecks.zone_frame), so you walk its decks as built.
static func wreck_zone(w: Dictionary) -> Array:
	return [BeltWrecks.zone_frame(w), BeltWrecks.zone_box(w, 24.0)]


static func _v3(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


# ------------------------------------------------------------------ in the world

## Register the field with the ground (WorldGround, for the "field" landmark): each
## big rock a box in its own frame with its hull's points, the ball's pull round
## it, a level zone over the town's deck, the wrecks (now, or left for later) with
## their zones.
static func add_to_ground(ground: WorldGround, _lm: Dictionary) -> void:
	var sp := ground.sphere()
	if sp == null:
		return
	_cache.erase(str(ground.world.get("planet", "")))
	var L := for_ground(ground)
	var reach := float((L.cfg as Dictionary).get("reach", 32.0))
	for rock in L.rocks:
		var r := float(rock.r)
		var u := unit(int(rock.v))
		var box: AABB = u.box
		var pts := PackedVector3Array()
		for p in (u.points as PackedVector3Array):
			pts.append(p * r)
		ground.add_box("field/" + str(rock.id), "roof", box.position * r, box.end * r, "", false, frame_of(rock))
		ground.boxes[-1]["convex"] = pts
		ground.boxes[-1]["field_rock"] = true
		sp.add_gravity_body(frame_of(rock), CORE * r, SKIN * r, reach + 0.4 * r)
	# The deck: the town's own up, whatever rock is under it.
	var deck: Rect2 = L.deck
	sp.add_gravity_zone(Transform3D.IDENTITY, AABB(Vector3(deck.position.x - 4.0, -9.0, deck.position.y - 4.0),
		Vector3(deck.size.x + 8.0, 70.0, deck.size.y + 8.0)))
	for w in L.wrecks:
		var z := wreck_zone(w)
		sp.add_gravity_zone(z[0], z[1])
		if ground.defer_kinds.has("wreck"):
			ground.deferred.append(w.landmark)
		else:
			StarcruiserWreck.add_to_ground(ground, w.landmark)


## The big rocks and the small ones, drawn: a MultiMesh a variant for each, in the
## field's rock colours. `small_out` gets the small ones' MultiMesh instances (so
## FieldWorld can tumble them).
static func build_look(parent: Node3D, L: Dictionary, mats: LookMaterials, small_out: Array = []) -> void:
	var look: Dictionary = (L.cfg as Dictionary).get("look", {})
	var mat := mats.rock(-400.0, 0.05)
	var a := Color(str(look.get("rock", "#6e5a50")))
	mat.set_shader_parameter("rock_a", a)
	mat.set_shader_parameter("rock_b", a.lightened(0.15))
	mat.set_shader_parameter("rock_dark", Color(str(look.get("rock_dark", "#2a2220"))))
	mat.set_shader_parameter("dust", Color(str(look.get("dust", "#a27c64"))))
	var root := Node3D.new()
	root.name = "FieldRocks"
	parent.add_child(root)
	for v in VARIANTS:
		var mesh := unit_mesh(v)
		var big: Array = (L.rocks as Array).filter(func(r): return int(r.v) == v)
		if not big.is_empty():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = big.size()
			for i in big.size():
				var rk: Dictionary = big[i]
				mm.set_instance_transform(i, Transform3D(rk.basis * Basis.from_scale(Vector3.ONE * float(rk.r)), rk.c))
			var mi := MultiMeshInstance3D.new()
			mi.name = "Big%d" % v
			mi.multimesh = mm
			mi.material_override = mat
			root.add_child(mi)
		var small: Array = (L.small as Array).filter(func(r): return int(r.v) == v)
		if not small.is_empty():
			var sm := MultiMesh.new()
			sm.transform_format = MultiMesh.TRANSFORM_3D
			sm.mesh = mesh
			sm.instance_count = small.size()
			for i in small.size():
				var s: Dictionary = small[i]
				sm.set_instance_transform(i, Transform3D(s.basis * Basis.from_scale(Vector3.ONE * float(s.r)), s.c))
			var smi := MultiMeshInstance3D.new()
			smi.name = "Small%d" % v
			smi.multimesh = sm
			smi.material_override = mat
			root.add_child(smi)
			small_out.append({ "mm": sm, "list": small })
