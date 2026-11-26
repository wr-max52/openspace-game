class_name DesertLandforms
extends Node3D
## Mesas, spires (hoodoos) and boulders on the desert: the mesas and spires
## spread by latitude and longitude all round the home planet's ball, the boulders
## round the whole ball too (some in fields at the rocks' feet), so wherever you
## land there is something on the skyline. Spires are three variations of one
## reference-style sandstone spire, reused; beside them, the original hoodoos
## (column and cap stone) at half their old height, for a mix of short and tall. Same recipes as
## the beauty corner's `_build_landforms` (the beauty corner is the art reference
## and is not edited, so this is a copy driven by content/look/desert_landforms.json).
##
## Mesas and hoodoos are solid (the player can walk up to them). Boulders are one
## MultiMesh to draw, and (issue #93) each also has its own convex collider, so you
## can stand on them; `boulders` lists them for WorldGround, where the low ones are
## ramps for a speeder and the tall ones stop it.

const DATA_PATH := "res://content/look/desert_landforms.json"
const MESA_BURY := 2.0             ## sink the broad feet into the sand, not on top of it

var data: Dictionary = {}
var solid_count := 0          ## bodies added (read by tests)
var boulder_count := 0
var boulder_spots := PackedVector3Array()   ## where they went (the renderer may not say)
## { center: Vector3 (on the ground), up, radius, height } for WorldGround.add_boulders.
var boulders: Array = []
## The spires placed (spire_spots entries), for tests and the boulder fields.
var spires: Array = []
## The short hoodoos placed (short_spots entries).
var shorts: Array = []
## The ball's mesas where they went, { map: Vector2, radius, height } each, and
## on which planet, for the F11 map's ground (GlobeTerrain): kept after the scene
## goes, so the map can show that planet's ground from another one.
static var mesa_spots: Array = []
static var mesa_planet := ""

## Made once a session: the port is built again when you fly home from the moon,
## and its rocks never change (~110 ms of noise, meshes and colliders on that
## handoff's first frame). Rock meshes by recipe, their trimesh shapes by mesh, and
## the boulders' hulls by where they stand.
static var _meshes := {}
static var _shapes := {}
static var _boulder_hulls := {}


static func load_data(path: String = DATA_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DesertLandforms: cannot open %s" % path)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## Issue #64: more places to keep clear, [Vector2 centre, radius] each (the
## Remnant's desert outposts: the world's landmarks with a "clear" radius).
var clear_circles: Array = []
var _sp: PlanetSphere                ## the ball (null on a flat world), for the far circles
var _circle_dirs: Array = []         ## per clear circle: its direction when it is measured on the ground, else null


## `keep_out` = the town's floor area (xz); nothing is placed on or near it.
func build(terrain: DesertTerrain, mats: LookMaterials, keep_out: Rect2) -> void:
	name = "Landforms"
	data = load_data()
	if data.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.get("seed", 4242))
	var margin := float(data.get("keep_out_margin", 25.0))
	var clear := keep_out.grow(margin)
	var solid := bool(data.get("collision", true))
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.fractal_octaves = 3
	_prep_circles((terrain as PlanetTerrain).sphere if terrain is PlanetTerrain else null)

	# On the home ball, climbable mountains by latitude/longitude; flat worlds keep
	# the original nearby beauty-corner mesas.
	if terrain is PlanetTerrain and data.has("planet_mountains"):
		_build_planet_mountains(terrain as PlanetTerrain, mats, clear, solid)
	else:
		_build_local_mesas(terrain, mats, clear, noise, rng, solid)

	# Spires (the tall skinny rocks): three variations reused everywhere, the race
	# towers by the Hoodoo Run and, on a ball, more all round the planet.
	var sp: PlanetSphere = (terrain as PlanetTerrain).sphere if terrain is PlanetTerrain else null
	var strata := float(data.get("spire_strata", 0.35))
	spires = []
	for s in spire_spots(data, sp):
		var map: Vector2 = s.map
		if _hits(clear, map.x, map.y, s.radius) or _in_circles(map.x, map.y, s.radius):
			continue
		var made := _spire(data, int(s.variant))
		var g := _ground(terrain, map.x, map.y)
		var gy := snappedf(_ground_h(terrain, g, map.x, map.y), 1.0)
		var mi := _add(made.mesh, mats.rock(gy, strata), g, -_skirt_sink(terrain, g, map, float(s.radius)),
			Vector3(0, s.yaw, 0))
		if solid:
			_solid_shape(mi, made.shape)
		spires.append(s)

	# The original hoodoos, shorter: a fluted column under a cap stone, all round
	# the ball (the old recipe, beside the tall new spires).
	shorts = []
	for hd in short_spots(data, sp):
		var map: Vector2 = hd.map
		var r: float = hd.radius
		var h: float = hd.height
		if _hits(clear, map.x, map.y, r) or _in_circles(map.x, map.y, r):
			continue
		noise.frequency = 1.4 / r
		var base := _cyl(r * 0.55, r, h, 16)
		base.rings = 10
		var g := _ground(terrain, map.x, map.y)
		var gy := snappedf(_ground_h(terrain, g, map.x, map.y), 1.0)
		var mat := mats.rock(gy, 0.35)
		var col := _add(_cached("hoodoo/%s/%s/%s" % [r, h, hd.seed], func(): return LookMeshKit.rock(base, noise, 0.28, 3.0, float(hd.seed), 0.4)),
			mat, g, h * 0.45)
		var cap := SphereMesh.new()
		cap.radius = r * 0.9
		cap.height = r * 0.8
		cap.radial_segments = 12
		cap.rings = 6
		_add(_cached("hoodoo_cap/%s/%s" % [r, hd.seed], func(): return LookMeshKit.rock(cap, noise, 0.3, 0.0, float(hd.seed))), mat, g, h * 0.95,
			Vector3(0, 0, rng.randf_range(-12, 12)))
		if solid:
			_solid(col)
		shorts.append(hd)

	# Boulders, scattered with a MultiMesh: one draw call for hundreds.
	var b: Dictionary = data.get("boulders", {})
	var want := int(b.get("count", 0))
	if want <= 0:
		return
	var boulder_src := BoxMesh.new()
	boulder_src.size = Vector3(2.0, 1.6, 1.8)
	boulder_src.subdivide_width = 2
	boulder_src.subdivide_height = 2
	boulder_src.subdivide_depth = 2
	noise.frequency = 0.9
	var xforms: Array[Transform3D] = []
	var min_dist := float(b.get("min_dist", 165.0))
	var spread := float(b.get("spread", 1500.0))
	# On the ball: all round the planet, some in fields at the rocks' feet.
	var planet_wide := sp != null and bool(b.get("planet_wide", false))
	var anchors: Array = []          # [map, radius] of every mesa and spire placed
	if planet_wide:
		for m in mesa_spots:
			anchors.append([m.map, float(m.radius)])
		for s in spires:
			anchors.append([s.map, float(s.radius)])
		for hd in shorts:
			anchors.append([hd.map, float(hd.radius)])
	var near_share := float(b.get("near_rocks", 0.0))
	var reach := float(b.get("near_reach", 2.5))
	# Some of the count are moved onto race courses (`courses`), the rest go round
	# the planet as before.
	var on_courses: Array = b.get("courses", []) if planet_wide else []
	for cb in on_courses:
		want -= int(cb.get("count", 0))
	for i in want:
		var x: float
		var z: float
		if planet_wide:
			var at := _planet_spot(sp, rng, anchors, near_share, reach)
			x = at.x
			z = at.y
		else:
			var ang := rng.randf() * TAU
			var dist := min_dist + pow(rng.randf(), 1.6) * spread
			x = cos(ang) * dist
			z = sin(ang) * dist
		var s := rng.randf_range(0.5, 1.0) * (1.0 + pow(rng.randf(), 3.0) * 5.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s * rng.randf_range(0.8, 1.3)))
		basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4))
		if _hits(clear, x, z, s * 2.0) or _in_circles(x, z, s * 2.0):
			continue
		if planet_wide and (Vector2(x, z).length() < min_dist or _in_rock(sp, anchors, x, z, s * 2.0)):
			continue
		var g := _ground(terrain, x, z)
		xforms.append(Transform3D(g.basis * basis, g.origin + g.basis.y * (-s * 0.25)))
	for cb in on_courses:
		xforms.append_array(_course_boulders(terrain as PlanetTerrain, cb, anchors))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _cached("boulder", func(): return LookMeshKit.rock(boulder_src, noise, 0.4, 0.0, 3.0))
	if solid:
		_solid_boulders(mm.mesh, xforms)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	boulder_count = xforms.size()
	for x in xforms:
		boulder_spots.append(x.origin)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Boulders"
	mmi.multimesh = mm
	mmi.material_override = mats.rock(0.0, 1.2)
	add_child(mmi)
	if terrain is PlanetTerrain:
		_on_ball((terrain as PlanetTerrain).sphere)


## Boulders moved onto a race course (a `boulders.courses` entry): { course, count,
## seed, on_line (the share dropped on the track, out to line_m either side of the
## racing line but clear of a lane lane_m wide down it, so the line itself stays
## open), band ([min, max] m either side of it for the rest), size ([min, max]
## scale: bigger than the planet's), tall ([min, max] stretch up: the planet's
## rock is a low slab; stood up, most of them are taller than a speeder can ride
## over), keep_gates_m (none this near a gate, the grid or a ramp) }. They skip
## the course's clear circles on purpose (they are there to be in the way) but
## keep off the rocks' feet and out of the tunnels. Measured on the ground, so
## they lie right on the far side of the ball too.
func _course_boulders(terrain: PlanetTerrain, cb: Dictionary, anchors: Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var c := RaceCourse.load_course(str(cb.get("course", "")))
	if c.is_empty() or terrain == null:
		return out
	var sp := terrain.sphere
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cb.get("seed", 77))
	# The line on the ground, and what to keep clear of.
	var pts: Array = []
	for q in c.get("line", []):
		pts.append(sp.center + sp.map_dir(float(q[0]), float(q[1])) * sp.radius)
	if pts.size() < 3:
		return out
	var keep: Array = []
	for g in c.get("gates", []):
		keep.append(sp.center + sp.map_dir(float(g.at[0]), float(g.at[1])) * sp.radius)
	for rp in c.get("ramps", []):
		keep.append(sp.center + sp.map_dir(float(rp.at[0]), float(rp.at[1])) * sp.radius)
	var keep_m := float(cb.get("keep_gates_m", 30.0))
	var grid_m := keep_m + 40.0           # the start's grid reaches back behind the line
	var total := 0.0
	var lens: Array = []
	for i in pts.size():
		var l := (pts[i] as Vector3).distance_to(pts[(i + 1) % pts.size()])
		lens.append(l)
		total += l
	var on_line := float(cb.get("on_line", 0.3))
	var line_m := float(cb.get("line_m", 10.0))
	var lane_m := float(cb.get("lane_m", 3.0))
	var band: Array = cb.get("band", [16.0, 60.0])
	var size: Array = cb.get("size", [1.2, 3.0])
	var tall: Array = cb.get("tall", [0.8, 1.2])
	var want := int(cb.get("count", 0))
	var tries := 0
	while out.size() < want and tries < want * 20:
		tries += 1
		var s_at := rng.randf() * total
		var k := 0
		while k < lens.size() - 1 and s_at > float(lens[k]):
			s_at -= float(lens[k])
			k += 1
		var a: Vector3 = pts[k]
		var bb: Vector3 = pts[(k + 1) % pts.size()]
		var at := a.lerp(bb, clampf(s_at / maxf(float(lens[k]), 0.001), 0.0, 1.0))
		var up := (at - sp.center).normalized()
		var fwd := bb - a
		fwd = (fwd - up * fwd.dot(up)).normalized()
		var side := up.cross(fwd).normalized()
		var s := rng.randf_range(float(size[0]), float(size[1]))
		# On the line: either side of a lane lane_m wide (a speeder's way through
		# stays open, the racing line itself clear), out to line_m.
		var lane := lane_m + s * 1.4
		var off := rng.randf_range(lane, maxf(line_m, lane + 0.5)) if rng.randf() < on_line \
			else rng.randf_range(float(band[0]), float(band[1]))
		off *= 1.0 if rng.randf() < 0.5 else -1.0
		var p := at + side * off
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(float(tall[0]), float(tall[1])), s * rng.randf_range(0.8, 1.3)))
		basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		var bad := false
		for gi in keep.size():
			if p.distance_to(keep[gi]) < (grid_m if gi == 0 else keep_m) + s * 2.0:
				bad = true
				break
		if bad:
			continue
		var m := sp.world_to_map(p)
		if _in_rock(sp, anchors, m.x, m.y, s * 2.0):
			continue
		var g := _ground(terrain, m.x, m.y)
		out.append(Transform3D(g.basis * basis, g.origin + g.basis.y * (-s * 0.25)))
	return out


## Every spire this world stands up, { id, map, variant, yaw, radius (the skirt's
## at the foot), column (a ship's column), height }: the race towers (plateau x,
## z, `hoodoos`) and, on a ball, the planet-wide ones (latitude, longitude,
## `planet_hoodoos`). WorldGround reads the same list, so its columns are the
## rocks on screen.
static func spire_spots(data: Dictionary, sp: PlanetSphere = null) -> Array:
	var variants: Array = data.get("spire_variants", [])
	var out: Array = []
	if variants.is_empty():
		return out
	var col := float(data.get("spire_column", 0.56))
	var entries: Array = []
	for e in data.get("hoodoos", []):
		entries.append([Vector2(float(e[0]), float(e[1])), e])
	if sp != null:
		for e in data.get("planet_hoodoos", []):
			entries.append([sp.map_from_lat_lon(float(e[0]), float(e[1])), e])
	for pair in entries:
		var map: Vector2 = pair[0]
		var e: Array = pair[1]
		var k := int(e[2]) % variants.size()
		var v: Dictionary = variants[k]
		out.append({ "id": "hoodoo_%d_%d" % [int(map.x), int(map.y)], "map": map, "variant": k,
			"yaw": float(e[3]) if e.size() > 3 else 0.0, "radius": float(v.radius),
			"column": float(v.radius) * col, "height": float(v.height) })
	return out


## The short (original-recipe) hoodoos on a ball, { id, map, radius, height, seed }
## from `short_hoodoos` [latitude, longitude, radius, height]. None on a flat world.
static func short_spots(data: Dictionary, sp: PlanetSphere = null) -> Array:
	var out: Array = []
	if sp == null:
		return out
	for e in data.get("short_hoodoos", []):
		var map := sp.map_from_lat_lon(float(e[0]), float(e[1]))
		out.append({ "id": "hoodoo_%d_%d" % [int(map.x), int(map.y)], "map": map,
			"radius": float(e[2]), "height": float(e[3]), "seed": float(e[0]) + float(e[1]) * 0.1 })
	return out


## A boulder's map spot on the ball: `share` of them near a rock (a little past its
## foot, out to `reach` of its radius), the rest anywhere on the planet (uniform on
## the sphere). Offsets go round the ball, not across the map, so a field stays
## round however far from the port its rock is.
static func _planet_spot(sp: PlanetSphere, rng: RandomNumberGenerator, anchors: Array,
		share: float, reach: float) -> Vector2:
	if not anchors.is_empty() and rng.randf() < share:
		var a: Array = anchors[rng.randi() % anchors.size()]
		var ang := rng.randf() * TAU
		var d := float(a[1]) * (1.15 + pow(rng.randf(), 1.5) * reach)
		var up := sp.map_dir((a[0] as Vector2).x, (a[0] as Vector2).y)
		var t1 := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.BACK).normalized()
		var t2 := up.cross(t1)
		var th := d / sp.radius
		return sp.dir_map(up * cos(th) + (t1 * cos(ang) + t2 * sin(ang)) * sin(th))
	var y := rng.randf_range(-1.0, 1.0)
	var phi := rng.randf() * TAU
	var r := sqrt(maxf(0.0, 1.0 - y * y))
	return sp.dir_map(Vector3(r * cos(phi), y, r * sin(phi)))


## Inside (or touching) a mesa or spire's foot, measured round the ball.
static func _in_rock(sp: PlanetSphere, anchors: Array, x: float, z: float, pad: float) -> bool:
	var d := sp.map_dir(x, z)
	for a in anchors:
		var ad := sp.map_dir((a[0] as Vector2).x, (a[0] as Vector2).y)
		if d.angle_to(ad) * sp.radius < float(a[1]) * 1.05 + pad:
			return true
	return false


func _build_local_mesas(terrain: DesertTerrain, mats: LookMaterials, clear: Rect2,
		noise: FastNoiseLite, rng: RandomNumberGenerator, solid: bool) -> void:
	# [x, z, radius, height] entries remain for flat-world beauty corners.
	for m in data.get("mesas", []):
		var r: float = m[2]
		var h: float = m[3]
		if _hits(clear, m[0], m[1], r) or _in_circles(m[0], m[1], r):
			continue
		var so := float(m[0]) * 0.01 + float(m[1]) * 0.003
		var mesh := _cached("mesa/%s/%s/%s" % [r, h, so], func(): return _mesa_mesh(r, h, noise, so))
		var g := _ground(terrain, m[0], m[1])
		var gy := _ground_h(terrain, g, m[0], m[1])
		var mi := _add(mesh, mats.rock(gy, 0.11), g, h * 0.46 - MESA_BURY,
			Vector3(0, rng.randf_range(0, 360), 0))
		if solid:
			_solid(mi)


func _build_planet_mountains(terrain: PlanetTerrain, mats: LookMaterials, clear: Rect2, solid: bool) -> void:
	var sp := terrain.sphere
	mesa_spots = []
	mesa_planet = GameFlow.current_planet_id()
	var strata := float(data.get("mountain", {}).get("strata", 0.2))
	for m in mountain_spots(data, sp):
		var map: Vector2 = m.map
		var p: Dictionary = m.plan
		var radius := float(p.radius)
		# A range on a race course stands over its line on purpose (its tunnel).
		if _hits(clear, map.x, map.y, radius) or (not m.has("course") and _in_circles(map.x, map.y, radius)):
			continue
		var made := _mountain(p, int(m.variant))
		var pl := RockMountain.placement(sp, map, p)
		var g: Transform3D = pl.frame
		var gy := snappedf(sp.altitude(g.origin) - float(pl.sink), 1.0)
		var mi := MeshInstance3D.new()
		mi.mesh = made.mesh
		mi.material_override = mats.rock(gy, strata)
		mi.transform = Transform3D(g.basis * Basis(Vector3.UP, float(pl.yaw)), g.origin - g.basis.y * float(pl.sink))
		add_child(mi)
		if solid:
			_solid_shape(mi, made.shape)
		if p.has("tunnel") and not (m.get("lights", {}) as Dictionary).is_empty():
			mi.add_child(_runner_lights(p.tunnel, m.lights))
		mesa_spots.append({ "map": map, "radius": radius, "height": float(p.height) })


## A tunnel's runner lights: small glowing blocks low on both walls every
## `spacing_m` along its roofed stretch, `inset_m` in from the walls, one
## MultiMesh and one cached glow (no real lights: the render rules' lamps).
static var _runner_mat: StandardMaterial3D
static func _runner_lights(tn: Dictionary, cfg: Dictionary) -> MultiMeshInstance3D:
	var path: PackedVector2Array = tn.path
	var gates: Dictionary = tn.gates
	var spacing := float(cfg.get("spacing_m", 9.0))
	var off := float(tn.half) - float(cfg.get("inset_m", 1.0))
	var size: Array = cfg.get("size", [0.3, 0.22, 1.6])
	var pts := RockMountain._resample(path, 1.0)
	var spots: Array = []         # [point, along]
	var s := float(gates.get("s_entry", 0.0)) - spacing * 2.0
	while s <= float(gates.get("s_exit", pts.size() - 1)) + spacing * 2.0:
		var i := clampi(int(s), 0, pts.size() - 2)
		spots.append([pts[i], (pts[i + 1] - pts[i]).normalized()])
		s += spacing
	var box := BoxMesh.new()
	box.size = Vector3(float(size[0]), float(size[1]), float(size[2]))
	if _runner_mat == null:
		_runner_mat = StandardMaterial3D.new()
		var c := Color(str(cfg.get("colour", "#ffb04a")))
		_runner_mat.albedo_color = c
		_runner_mat.emission_enabled = true
		_runner_mat.emission = c
		_runner_mat.emission_energy_multiplier = float(cfg.get("energy", 3.0))
	box.material = _runner_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = spots.size() * 2
	for k in spots.size():
		var at: Vector2 = spots[k][0]
		var d: Vector2 = spots[k][1]
		var side := Vector2(-d.y, d.x)
		var basis := Basis.looking_at(Vector3(d.x, 0.0, d.y), Vector3.UP)
		for j in 2:
			var q: Vector2 = at + side * off * (1.0 if j == 0 else -1.0)
			mm.set_instance_transform(k * 2 + j, Transform3D(basis, Vector3(q.x, float(size[1]) * 0.5 + 0.15, q.y)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "RunnerLights"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Every mountain on a ball: { id, map, variant, plan } from `planet_mountains`
## [latitude, longitude, version], and the ranges of `course_mountains` (see
## _course_range: a few tunnel peaks over a race course's line, one tunnel
## through them all; these add `course` and `lights`). WorldGround reads the
## same list.
static func mountain_spots(data: Dictionary, sp: PlanetSphere) -> Array:
	var variants: Array = data.get("mountain_variants", [])
	var out: Array = []
	if variants.is_empty() or sp == null:
		return out
	var cfg: Dictionary = data.get("mountain", {})
	for e in data.get("planet_mountains", []):
		var k := int(e[2]) % variants.size()
		out.append({ "id": "mesa_%d_%d" % [int(e[0]), int(e[1])], "map": sp.map_from_lat_lon(float(e[0]), float(e[1])),
			"variant": k, "plan": RockMountain.plan(variants[k], cfg) })
	for e in data.get("course_mountains", []):
		out.append(_course_range(e, variants, cfg, sp))
	return out


## A range over a race course: { course, path: map [[x, z], ...] (the tunnel's
## centre line, the racing line's way through, smoothed), peaks: [{ along (m from
## the path's start), variant, seed, portal ("start" or "end": its sheer side's
## portal faces that end of the path) }], lights }. Its frame is the map's at the
## path's middle, on the ball's own level there (directions only, so it is the
## same with or without the flat sites made): every peak and the path in it.
static func _course_range(e: Dictionary, variants: Array, cfg: Dictionary, sp: PlanetSphere) -> Dictionary:
	# A point every 20 m of ground: far round the ball the map is stretched
	# across, so the step on the map grows with it (else a far tunnel's path
	# would carry several times the points every ground query walks).
	var step := 20.0
	var p0 := Vector2(float(e.path[0][0]), float(e.path[0][1])) if not (e.path as Array).is_empty() else Vector2.ZERO
	if sp.map_stretch(p0) > RaceCourse.FAR_STRETCH:
		step *= sp.map_stretch(p0)
	var mpath := smooth_path(e.path, step)
	var total := 0.0
	for i in mpath.size() - 1:
		total += mpath[i].distance_to(mpath[i + 1])
	var mid := along_path(mpath, total * 0.5)
	var dir := sp.map_dir(mid.x, mid.y)
	var g := Transform3D(PlanetSphere.tilt_to(sp.up_at(sp.center + dir * sp.radius)), sp.center + dir * sp.radius)
	var inv := g.affine_inverse()
	var local := func(m: Vector2) -> Vector2:
		var l: Vector3 = inv * (sp.center + sp.map_dir(m.x, m.y) * sp.radius)
		return Vector2(l.x, l.z)
	var path := PackedVector2Array()
	for q in mpath:
		path.append(local.call(q))
	var peaks: Array = []
	var k := 0
	for pk in e.get("peaks", []):
		k = int(pk.get("variant", 0)) % variants.size()
		var v: Dictionary = (variants[k] as Dictionary).duplicate(true)
		v["seed"] = int(pk.get("seed", v.get("seed", 1)))
		var at: Vector2 = local.call(along_path(mpath, float(pk.get("along", 0.0))))
		var peak := { "v": v, "at": at }
		match str(pk.get("portal", "")):
			"start":
				peak["cliff_toward"] = (path[0] - at).angle()
			"end":
				peak["cliff_toward"] = (path[-1] - at).angle()
		peaks.append(peak)
	return { "id": "mesa_%s" % str(e.get("id", e.get("course", "course"))), "map": mid, "variant": k,
		"plan": RockMountain.range_plan(peaks, path, cfg), "course": str(e.get("course", "")),
		"lights": e.get("lights", {}), "map_path": mpath }


## A course's line through map points, smoothed (Catmull-Rom through them, a
## point every `step` m or so).
static func smooth_path(points: Array, step: float) -> PackedVector2Array:
	var p: Array = []
	for q in points:
		p.append(Vector2(float(q[0]), float(q[1])))
	var out := PackedVector2Array()
	for i in p.size() - 1:
		var p0: Vector2 = p[maxi(i - 1, 0)]
		var p1: Vector2 = p[i]
		var p2: Vector2 = p[i + 1]
		var p3: Vector2 = p[mini(i + 2, p.size() - 1)]
		var n := maxi(1, int(ceil(p1.distance_to(p2) / step)))
		for j in n:
			var t := float(j) / float(n)
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	out.append(p[-1])
	return out


## The point `s` m along a path (its ends past either end).
static func along_path(path: PackedVector2Array, s: float) -> Vector2:
	for i in path.size() - 1:
		var len := path[i].distance_to(path[i + 1])
		if s <= len:
			return path[i].lerp(path[i + 1], clampf(s / len, 0.0, 1.0))
		s -= len
	return path[-1]


## Level sand under each mountain on the home ball (a playa, as round real
## yardangs), so dunes do not bury its lower shelves or pile against its caves:
## the plane square to "up" there through the mean height of the sand round it
## before levelling, out to the mountain's reach plus the pad's margin, easing
## back into the dunes over its blend. Boxes on the map, like the camps' and the
## race gates'; far round the ball the map stretches across (the blend with it).
static func mountain_flat_sites(planet: Dictionary, sp: PlanetSphere) -> Array:
	var sites: Array = []
	if sp == null or str(planet.get("id", "")) != PlanetGen.home_id():
		return sites
	var data := load_data()
	var pad: Dictionary = data.get("mountain", {}).get("pad", {})
	var margin := float(pad.get("margin_m", 30.0))
	var blend := float(pad.get("blend_m", 50.0))
	for m in mountain_spots(data, sp):
		var map: Vector2 = m.map
		var base := sp.surface_at(map.x, map.y)
		var g := Transform3D(PlanetSphere.tilt_to(sp.up_at(base)), base)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var sum := 0.0
		var n := 0
		# Round each peak of a range (one level plane for them all), else round it.
		var rounds: Array = []
		for pk in m.plan.get("peaks", [{ "at": Vector2.ZERO, "radius": float(m.plan.radius) }]):
			rounds.append([pk.at, float(pk.radius) + margin])
		for rd in rounds:
			for ring in [float(rd[1]), float(rd[1]) * 0.5]:
				for i in 24:
					var a := TAU * float(i) / 24.0
					var c2: Vector2 = rd[0]
					var q := sp.world_to_map(g * Vector3(c2.x + cos(a) * float(ring), 0.0, c2.y + sin(a) * float(ring)))
					lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
					hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
					sum += sp.elevation(sp.map_dir(q.x, q.y))
					n += 1
		var mean := sum / float(n)
		var th := map.length() / sp.radius
		var stretch := clampf(th / sin(th), 1.0, 6.0) if th > 0.01 and th < PI - 0.01 else 1.0
		var mid := sp.center + sp.map_dir(map.x, map.y) * (sp.radius + mean)
		if m.has("course") and sp.map_stretch(map) > RaceCourse.FAR_STRETCH:
			# A course range far round the ball: its playa is a box on the ground
			# round its peaks, in the range's own frame (the map is stretched there).
			var llo := Vector2(INF, INF)
			var lhi := -llo
			for rd in rounds:
				var c2: Vector2 = rd[0]
				llo = Vector2(minf(llo.x, c2.x - float(rd[1])), minf(llo.y, c2.y - float(rd[1])))
				lhi = Vector2(maxf(lhi.x, c2.x + float(rd[1])), maxf(lhi.y, c2.y + float(rd[1])))
			var centre := g * Vector3((llo.x + lhi.x) * 0.5, 0.0, (llo.y + lhi.y) * 0.5)
			sites.append(sp.framed_site(centre, g.basis.x, (lhi - llo) * 0.5, blend,
				{ "y": mean, "plane_c": mid, "plane_u": sp.up_at(mid) }))
			continue
		sites.append({ "rect": Rect2(lo, hi - lo), "y": mean, "plane_c": mid,
			"plane_u": sp.up_at(mid), "blend": blend * stretch })
	return sites


## One mountain version's mesh and trimesh, built once a session.
static func _mountain(p: Dictionary, k: int) -> Dictionary:
	var key := "mountain/%d/%s" % [k, hash(p.height) + hash(p.radius)]
	if not _meshes.has(key):
		var built := RockMountain.build(p)
		_meshes[key] = built.mesh
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(built.faces)
		_shapes[built.mesh] = shape
	var mesh: Mesh = _meshes[key]
	return { "mesh": mesh, "shape": _shapes[mesh] }


## How far the sand dips under a spire's skirt below its centre (6 samples round
## the foot, at most 8 m), so on a dune's slope the skirt's edge stays buried.
static func _skirt_sink(terrain: DesertTerrain, g: Transform3D, map: Vector2, radius: float) -> float:
	var sink := 0.0
	for i in 6:
		var a := TAU * float(i) / 6.0
		var p := map + Vector2(cos(a), sin(a)) * radius
		var gp := _ground(terrain, p.x, p.y)
		sink = maxf(sink, (g.origin - gp.origin).dot(g.basis.y))
	return minf(sink, 8.0)


## The rock shader's ground height on the ball is metres above the bare ball.
static func _ground_h(terrain: DesertTerrain, g: Transform3D, x: float, z: float) -> float:
	if terrain is PlanetTerrain:
		return (terrain as PlanetTerrain).sphere.altitude(g.origin)
	return terrain.height_at(x, z)


## Every rock material here: strata and dusk follow the ball (issue #77).
func rock_materials() -> Array:
	var out: Array = []
	for n in find_children("*", "GeometryInstance3D", true, false):
		var m = (n as GeometryInstance3D).material_override
		if m is ShaderMaterial and not out.has(m):
			out.append(m)
	return out


func _on_ball(sp: PlanetSphere) -> void:
	for m in rock_materials():
		m.set_shader_parameter("planet_center", sp.center)
		m.set_shader_parameter("planet_radius", sp.radius)
		m.set_shader_parameter("dusk_strength", 0.35)


static func _hits(r: Rect2, x: float, z: float, radius: float) -> bool:
	return r.grow(radius).has_point(Vector2(x, z))


## Far round the ball (the far side's race courses and ranches) the map stretches
## across several times over, so a clear circle there is measured on the ground;
## near the port (stretch under RaceCourse.FAR_STRETCH) on the map, as always.
func _prep_circles(sp: PlanetSphere) -> void:
	_sp = sp
	_circle_dirs = []
	for c in clear_circles:
		var m: Vector2 = c[0]
		_circle_dirs.append(sp.map_dir(m.x, m.y) if sp != null and sp.map_stretch(m) > RaceCourse.FAR_STRETCH else null)


func _in_circles(x: float, z: float, radius: float) -> bool:
	var p := Vector2(x, z)
	var d := Vector3.ZERO
	var have := false
	for i in clear_circles.size():
		var c: Array = clear_circles[i]
		var reach := float(c[1]) + radius
		var md := (c[0] as Vector2).distance_to(p)
		if md < reach:
			return true                   # the map never shrinks a distance
		var cd = _circle_dirs[i] if i < _circle_dirs.size() else null
		if cd == null or md > reach * 12.0:
			continue
		if not have:
			d = _sp.map_dir(x, z)
			have = true
		if d.angle_to(cd) * _sp.radius < reach:
			return true
	return false


func _cyl(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## One spire variation, built once a session: { mesh, shape }. The shape is a
## trimesh of the very triangles drawn, so what you climb is what you see.
static func _spire(d: Dictionary, k: int) -> Dictionary:
	var key := "spire/%d/%s" % [k, hash(d.get("spire_variants", [])[k])]
	if not _meshes.has(key):
		var built := spire_mesh(d.get("spire_variants", [])[k], d.get("spire_profile", []),
			int(d.get("spire_segments", 40)), int(d.get("spire_rings", 46)), float(d.get("spire_bury", 3.0)))
		_meshes[key] = built.mesh
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(built.faces)
		_shapes[built.mesh] = shape
	var mesh: Mesh = _meshes[key]
	return { "mesh": mesh, "shape": _shapes[mesh] }


## A wind-cut sandstone spire: a broad flared skirt, a lumpy lower body of stacked
## bulges (bands that ride up and down round the column, like melted wax), a long
## tapering finger split by vertical cracks, a rounded top and a slight lean. The
## foot is `bury` m under the ground. Returns { mesh, faces } (faces: the triangles,
## for the collider). Smooth normals: the stone is wind-polished, not faceted.
static func spire_mesh(v: Dictionary, profile: Array, seg: int, rings: int, bury: float) -> Dictionary:
	var h := float(v.height)
	var r0 := float(v.radius)
	var lean_xz: Array = v.get("lean", [0.0, 0.0])
	var lean := Vector3(float(lean_xz[0]), 0.0, float(lean_xz[1]))
	var bands := float(v.get("bands", 4.0))
	var bulge := float(v.get("bulge", 0.06))
	var cracks := int(v.get("cracks", 2))
	var crack_depth := float(v.get("crack_depth", 0.15))
	var twist := float(v.get("twist", 1.0))
	var noise := FastNoiseLite.new()
	noise.seed = int(v.get("seed", 1))
	noise.frequency = 1.0
	noise.fractal_octaves = 3
	var ph := float(int(v.get("seed", 1)) % 97) * 0.37         # this variation's phases
	var crack_at: Array[float] = []
	for c in cracks:
		crack_at.append(TAU * (float(c) + 0.3 * noise.get_noise_1d(c * 7.1)) / float(cracks) + ph)

	var rows: Array[PackedVector3Array] = []
	# The foot: a ring `bury` m straight under the skirt's edge.
	var foot := PackedVector3Array()
	for i in seg:
		var a := TAU * float(i) / float(seg)
		foot.append(Vector3(cos(a) * r0, -bury, sin(a) * r0))
	rows.append(foot)
	for j in rings:
		# More rings near the foot, where the skirt turns fast.
		var t := pow(float(j) / float(rings - 1), 1.25)
		var base := _profile_at(profile, t) * r0
		var body := smoothstep(0.08, 0.24, t)             # the skirt stays smooth
		var split := smoothstep(0.2, 0.6, t)              # cracks deepen up the finger
		var centre := lean * pow(t, 1.8)
		var row := PackedVector3Array()
		for i in seg:
			var a := TAU * float(i) / float(seg)
			var ca := cos(a)
			var sa := sin(a)
			var wobble := noise.get_noise_3d(ca * 1.3 + ph, t * 2.0, sa * 1.3)
			# Stacked bulges, offset round the column so they read as lobes, not rings.
			# Bulbous peaks with narrow grooves between (cubed), not an even ripple.
			var wave := 0.5 + 0.5 * sin((t * bands + wobble * 1.1 + a / TAU * 0.6) * TAU)
			var bump := (pow(wave, 2.0) * 2.0 - 0.6) * bulge * body * (1.0 - 0.45 * t)
			# Two or three broad lobes in plan that turn slowly with height.
			var lobe := (cos(3.0 * a + twist * t + ph) * 0.06 + cos(2.0 * a - twist * 0.6 * t + ph * 1.7) * 0.05) * body
			var crack := 0.0
			for c in crack_at:
				var dd := wrapf(a - c - 0.25 * sin(t * 5.0 + ph), -PI, PI)
				crack += exp(-pow(dd / 0.2, 2.0)) * crack_depth * split
			var fine := noise.get_noise_3d(ca * 3.0 + ph, t * h * 0.08, sa * 3.0) * 0.06
			var rr := base * maxf(0.15, 1.0 + bump + lobe + fine - crack)
			var y := t * h
			row.append(centre + Vector3(ca * rr, y, sa * rr))
		rows.append(row)
	var top := lean + Vector3(0.0, h + r0 * 0.04, 0.0)

	var faces: Array = []       # an Array: the lambda below appends to it (a packed array would be copied)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var tri := func(p0: Vector3, p1: Vector3, p2: Vector3, out: Vector3) -> void:
		# Clockwise from outside (Godot's front face), as LookMeshKit.add_tri.
		if (p1 - p0).cross(p2 - p0).dot(out) > 0.0:
			var tmp := p1
			p1 = p2
			p2 = tmp
		for q in [p0, p1, p2]:
			st.add_vertex(q)
			faces.append(q)
	for j in rows.size() - 1:
		for i in seg:
			var n := (i + 1) % seg
			var a := TAU * (float(i) + 0.5) / float(seg)
			var out := Vector3(cos(a), 0.0, sin(a))
			tri.call(rows[j][i], rows[j][n], rows[j + 1][n], out)
			tri.call(rows[j][i], rows[j + 1][n], rows[j + 1][i], out)
	for i in seg:
		tri.call(top, rows[-1][i], rows[-1][(i + 1) % seg], Vector3.UP)
	st.index()
	st.generate_normals()
	return { "mesh": st.commit(), "faces": PackedVector3Array(faces) }


## The spire's radius (fraction of the skirt's) at height fraction t.
static func _profile_at(profile: Array, t: float) -> float:
	if profile.is_empty():
		return 1.0 - t
	for k in range(1, profile.size()):
		var b: Array = profile[k]
		if t <= float(b[0]):
			var a: Array = profile[k - 1]
			var f := inverse_lerp(float(a[0]), float(b[0]), t)
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, f))
	return float(profile[-1][1])


## A broad, weathered plateau with broken shelves and cliff-cut gullies. The
## outline stays inside WorldGround's existing mesa column, so the improved
## silhouette does not change the ship's conservative landmark collision.
static func _mesa_mesh(radius: float, height: float, noise: FastNoiseLite, seed_offset: float) -> ArrayMesh:
	const SEGMENTS := 64
	const PROFILE := [
		Vector2(0.00, 0.76), Vector2(0.10, 0.84), Vector2(0.22, 0.82),
		Vector2(0.31, 0.78), Vector2(0.35, 0.73), Vector2(0.49, 0.72),
		Vector2(0.54, 0.67), Vector2(0.67, 0.66), Vector2(0.71, 0.61),
		Vector2(0.84, 0.60), Vector2(0.88, 0.56), Vector2(0.98, 0.55),
		Vector2(1.00, 0.52)
	]
	noise.frequency = 1.0
	var rings: Array[PackedVector3Array] = []
	for ring in PROFILE:
		var row := PackedVector3Array()
		var t := float(ring.x)
		var base_radius := float(ring.y)
		for i in SEGMENTS:
			var angle := TAU * float(i) / SEGMENTS
			var ca := cos(angle)
			var sa := sin(angle)
			var broad := noise.get_noise_2d(ca * 2.0 + seed_offset, sa * 2.0 + seed_offset)
			var fine := noise.get_noise_3d(ca * 5.0 + seed_offset, t * 3.0, sa * 5.0 + seed_offset)
			# Vertical flutes are strongest on the cliff face, not the broad cap.
			var cliff_band := smoothstep(0.12, 0.30, t) * (1.0 - smoothstep(0.72, 0.92, t))
			var gully := pow(maxf(0.0, cos(angle * 6.0 + broad * 0.55)), 8.0) * 0.045 * cliff_band
			var radial := base_radius + broad * 0.026 + fine * 0.009 - gully
			var cap_wave := 1.0 - smoothstep(0.92, 1.0, t)
			var y_noise := (broad * 0.012 + fine * 0.006) * cap_wave
			row.append(Vector3(
				ca * radius * radial,
				(t - 0.5) * height * 0.92 + y_noise * height,
				sa * radius * radial
			))
		rings.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for j in rings.size() - 1:
		for i in SEGMENTS:
			var next := (i + 1) % SEGMENTS
			var radial := Vector3(
				cos(TAU * (float(i) + 0.5) / SEGMENTS), 0.0,
				sin(TAU * (float(i) + 0.5) / SEGMENTS)
			)
			LookMeshKit.add_quad(st, rings[j][i], rings[j][next],
				rings[j + 1][next], rings[j + 1][i], radial)
	var cap_center := Vector3.ZERO
	for point in rings[-1]:
		cap_center += point
	cap_center /= SEGMENTS
	for i in SEGMENTS:
		var next := (i + 1) % SEGMENTS
		LookMeshKit.add_tri(st, cap_center, rings[-1][i], rings[-1][next], Vector3.UP)
	var base_center := Vector3.ZERO
	for point in rings[0]:
		base_center += point
	base_center /= float(SEGMENTS)
	for i in SEGMENTS:
		var next := (i + 1) % SEGMENTS
		LookMeshKit.add_tri(st, base_center, rings[0][next], rings[0][i], Vector3.DOWN)
	return st.commit()


## Where a landform at map (x, z) stands: the ground there, y along its up. On the
## home planet's ball (issue #77) that leans with the ground; on a flat desert it is
## just the height at x, z.
static func _ground(terrain: DesertTerrain, x: float, z: float) -> Transform3D:
	if terrain is PlanetTerrain:
		var sp: PlanetSphere = (terrain as PlanetTerrain).sphere
		var at := sp.surface_at(x, z)
		return Transform3D(PlanetSphere.tilt_to(sp.up_at(at)), at)
	return Transform3D(Basis.IDENTITY, Vector3(x, terrain.height_at(x, z), z))


## `up` metres above the ground frame g, turned by rot_deg within it.
func _add(mesh: Mesh, mat: Material, g: Transform3D, up: float, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(g.basis * Basis.from_euler(rot_deg * PI / 180.0), g.origin + g.basis.y * up)
	add_child(mi)
	return mi


## One static body per boulder: a convex hull of the very rock mesh drawn there (its
## points put through that boulder's transform), so what you stand on is what you see.
func _solid_boulders(mesh: Mesh, xforms: Array[Transform3D]) -> void:
	var key := "%d/%s/%s" % [xforms.size(), xforms[0], xforms[-1]] if not xforms.is_empty() else ""
	var made: Array = _boulder_hulls.get(key, [])      # [shape, top, rad] per rock
	if made.size() != xforms.size():
		made = _boulder_shapes(mesh, xforms)
		_boulder_hulls[key] = made
	var root := StaticBody3D.new()
	root.name = "BoulderColliders"
	add_child(root)
	for k in xforms.size():
		var xf := xforms[k]
		var shape: Shape3D = made[k][0]
		var top: float = made[k][1]
		var rad: float = made[k][2]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = xf.origin
		root.add_child(cs)
		# Up: the ground's (the transform also leans and turns the rock a little).
		var up := Vector3.UP
		if PlanetSphere.current != null:
			up = PlanetSphere.current.up_at(xf.origin)
		# Measured from the rock's origin, a little under the sand; the ground under
		# it counts wherever it is higher.
		boulders.append({ "center": xf.origin, "up": up, "radius": rad * 0.85, "height": top })


## One convex hull per boulder: the very rock mesh drawn there (its points put
## through that boulder's transform), with its height and reach along its up.
static func _boulder_shapes(mesh: Mesh, xforms: Array[Transform3D]) -> Array:
	var pts := PackedVector3Array()
	var seen := {}
	for v in (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		var key := v.snapped(Vector3.ONE * 0.01)
		if not seen.has(key):
			seen[key] = true
			pts.append(v)
	var out: Array = []
	for xf in xforms:
		var hull := PackedVector3Array()
		hull.resize(pts.size())
		var top := 0.0
		var rad := 0.0
		for i in pts.size():
			var w: Vector3 = xf.basis * pts[i]
			hull[i] = w
			top = maxf(top, w.dot(xf.basis.y.normalized()))
			rad = maxf(rad, (w - xf.basis.y.normalized() * w.dot(xf.basis.y.normalized())).length())
		var shape := ConvexPolygonShape3D.new()
		shape.points = hull
		out.append([shape, top, rad])
	return out


## A static body with a shape made beforehand (a spire's, from its own triangles).
func _solid_shape(mi: MeshInstance3D, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)
	solid_count += 1


## The same as mi.create_trimesh_collision(), with the shape made once a session.
func _solid(mi: MeshInstance3D) -> void:
	var shape: Shape3D = _shapes.get(mi.mesh)
	if shape == null:
		shape = mi.mesh.create_trimesh_shape()
		_shapes[mi.mesh] = shape
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)
	solid_count += 1


static func _cached(key: String, make: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = make.call()
	return _meshes[key]
