class_name RoadNetwork
extends Node3D
## Issue #882: a planet's speeder roads (its `roads` block,
## content/core/planets/<planet>.json): lines of map points from the port city to
## each mountain town's way up (#877), through the mountains' tunnels, a packed
## dirt strip on the sand under each and a simple lamp every so many metres.
##
## A road is data: { id, from, to, via }. `from` and `to` are "port" or a place id
## from the planet's `settlements`; `via` is [latitude, longitude] points and
## "tunnel:<id>" (a `course_mountains` tunnel range: the road runs its whole
## centre line, in whichever direction it meets it first). The road is straight
## along the ground between its points (great circles, like a race course's legs).
##
## The road changes nothing about the ground: the strip is a ribbon a hand's
## breadth over the sand (drawn near only), and the lamps are glow, never real
## lights: one MultiMesh of heads per road, drawn far, so a far road is a dotted
## line of glows, and one of posts, drawn near (render rules). The mountains'
## clusters keep their peaks off every road (DesertLandforms.load_for), and the
## boulders and spires keep off its line (clear_circles).

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const LOOK_PATH := "res://content/look/roads.json"
const STEP_M := 10.0                   ## m of ground between a road's points

var demo                               ## town_demo.gd, may be null (tests)
var sp: PlanetSphere
var roads: Array = []                  ## plan(): { id, label, from, to, pts (map), lamps (map), tunnels }
var lamp_count := 0
var built := false
static var _look: Dictionary = {}
static var _mat_cache: Dictionary = {}


# ------------------------------------------------------------------ data

static func look() -> Dictionary:
	if _look.is_empty():
		_look = CoreContent.read_json(LOOK_PATH)
	return _look


static func cfg_of(planet: Dictionary) -> Dictionary:
	var c: Dictionary = planet.get("cfg", planet)
	return c.get("roads", {})


## Every road of the planet laid out: its points every STEP_M m of ground (map
## x, z), its lamps' spots and the tunnels it runs through.
static func plan(planet: Dictionary, sphere: PlanetSphere) -> Array:
	var rc := cfg_of(planet)
	if rc.is_empty():
		return []
	var ends := road_ends(planet, sphere)
	var tunnels := _tunnels(planet, sphere)
	var out: Array = []
	for r in rc.get("roads", []):
		var chain := _chain(r, ends, tunnels, sphere, float(rc.get("lead_m", 120.0)))
		if chain.size() < 2:
			continue
		var pts := _sample(chain.pts, sphere)
		out.append({ "id": str(r.id), "label": str(r.get("label", r.id)), "from": str(r.from), "to": str(r.to),
			"pts": pts, "tunnels": chain.tunnels, "length": _length(pts, sphere),
			"lamps": _lamp_spots(pts, rc, tunnels, chain.tunnels, sphere) })
	return out


## Where a road meets the port and each place: { id: { at (map), approach (map) } }.
## The port's end is out past its walls; a lift town's at its tube's door, a road
## town's at the foot of its road up, a ledge's at its foot on the gate side.
## `approach` is a point straight out from it, so the road comes in square.
static func road_ends(planet: Dictionary, sphere: PlanetSphere) -> Dictionary:
	var rc := cfg_of(planet)
	var out := {}
	out["port"] = { "at": Vector2.ZERO, "out_m": town_reach(planet) + float(rc.get("port_out_m", 60.0)) }
	var cfg: Dictionary = planet.get("cfg", planet)
	var st: Dictionary = cfg.get("settlements", {})
	if st.is_empty():
		return out
	var data := DesertLandforms.load_for(planet)
	var spots := {}
	for m in DesertLandforms.mountain_spots(data, sphere):
		spots[str(m.id)] = m
	var app := float(rc.get("approach_m", 60.0))
	for p in st.get("places", []):
		var m: Dictionary = spots.get("butte_" + str(p.id), {})
		if m.is_empty():
			continue
		var s := Settlements.site(p, st, sphere, m)
		var rock: Transform3D = s.rock
		var at := Vector3.ZERO
		var dir := Vector3.RIGHT
		if s.has("lift"):
			at = Vector3(float(s.lift.x) + float(st.get("lift", {}).get("car_radius", 2.6)) + 4.0, 0.0, 0.0)
		elif s.has("ramp"):
			var a0 := float(s.ramp.start_angle)
			var r := float(s.ramp.radius)
			at = Vector3(cos(a0) * r, 0.0, sin(a0) * r)
			dir = -Vector3(-sin(a0), 0.0, cos(a0))     # back along the road up
			at += dir * 4.0
		else:
			at = Vector3(RockMountain._lobed((s.plan.tiers as Array)[0], 0.0) + 8.0, 0.0, 0.0)
		out[str(p.id)] = { "at": sphere.world_to_map(rock * at), "approach": sphere.world_to_map(rock * (at + dir * app)),
			"centre": s.map, "foot": float(s.plan.radius) }
	return out


## m from the port's middle to its farthest wall corner (its town's bounds).
static func town_reach(planet: Dictionary) -> float:
	var bd: Dictionary = (planet.get("town", {}) as Dictionary).get("bounds", {})
	if bd.is_empty():
		return 200.0
	var most := 0.0
	for x in [float(bd.min[0]), float(bd.max[0])]:
		for z in [float(bd.min[1]), float(bd.max[1])]:
			most = maxf(most, Vector2(x, z).length())
	return most


## The planet's tunnel ranges by id: { id: [map points along the centre line] }.
static func _tunnels(planet: Dictionary, sphere: PlanetSphere) -> Dictionary:
	var out := {}
	var data := DesertLandforms.load_for(planet)
	for e in data.get("course_mountains", []):
		if not e.has("path_ll"):
			continue
		var pts: Array = []
		for q in e.path_ll:
			pts.append(sphere.map_from_lat_lon(float(q[0]), float(q[1])))
		out[str(e.get("id", ""))] = pts
	return out


## A road's corner points in order (map) and the tunnels it takes.
static func _chain(r: Dictionary, ends: Dictionary, tunnels: Dictionary, sphere: PlanetSphere, cfg_lead := 120.0) -> Dictionary:
	var pts: Array = []
	var took: Array = []
	var mids: Array = []
	for v in r.get("via", []):
		if v is String and str(v).begins_with("tunnel:"):
			var tid := str(v).trim_prefix("tunnel:")
			if tunnels.has(tid):
				var t: Array = tunnels[tid]
				var lead := float(cfg_lead)
				var a: Vector2 = t[0]
				var b: Vector2 = t[-1]
				var len := maxf(sphere.ground_dist(a, b), 0.01)
				var past := [RaceCourse.ground_lerp(b, a, 1.0 + lead / len, sphere.radius), RaceCourse.ground_lerp(a, b, 1.0 + lead / len, sphere.radius)]
				mids.append({ "tunnel": tid, "pts": ([past[0]] + t + [past[1]]).duplicate() })
				took.append(tid)
		elif v is Array and (v as Array).size() >= 2:
			mids.append({ "pts": [sphere.map_from_lat_lon(float(v[0]), float(v[1]))] })
	var a: Dictionary = ends.get(str(r.get("from", "")), {})
	var b: Dictionary = ends.get(str(r.get("to", "")), {})
	if a.is_empty() or b.is_empty():
		return { "pts": [], "tunnels": [] }
	# Which way round each tunnel goes is judged from the place's middle (or the
	# last tunnel's far end), as cluster_avoid judges it.
	var from_c: Vector2 = a.get("centre", Vector2.ZERO)
	for i in mids.size():
		var seg: Array = mids[i].pts
		if seg.size() > 1 and sphere.ground_dist(from_c, seg[-1]) < sphere.ground_dist(from_c, seg[0]):
			seg.reverse()
		from_c = seg[-1]
	var head: Array = _end_pts(a, mids, true, sphere, b.get("approach", b.at))
	pts.append_array(head)
	for i in mids.size():
		pts.append_array(mids[i].pts)
	var tail: Array = _end_pts(b, mids, false, sphere, a.get("approach", a.at))
	tail.reverse()
	pts.append_array(tail)
	return { "pts": pts, "tunnels": took, "size": pts.size() }


## The points a road takes at one of its ends, outward first: the end and its
## approach (a place), or the port's middle pushed out past its walls toward
## the road's first corner (or, with none, toward the far end's approach).
static func _end_pts(e: Dictionary, mids: Array, first: bool, sphere: PlanetSphere, far: Vector2) -> Array:
	if e.has("approach"):
		return [e.at, e.approach]
	var toward := far
	if not mids.is_empty():
		var seg: Array = mids[0 if first else -1].pts
		toward = seg[0]
	var d := sphere.ground_dist(Vector2.ZERO, toward)
	if d < 1.0:
		return [Vector2.ZERO]
	return [RaceCourse.ground_lerp(Vector2.ZERO, toward, float(e.out_m) / d, sphere.radius)]


## The chain sampled every STEP_M m of ground, straight along the ground between
## its corners.
static func _sample(chain: Array, sphere: PlanetSphere) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in chain.size() - 1:
		var a: Vector2 = chain[i]
		var b: Vector2 = chain[i + 1]
		var n := maxi(1, int(ceil(sphere.ground_dist(a, b) / STEP_M)))
		for k in n:
			out.append(RaceCourse.ground_lerp(a, b, float(k) / float(n), sphere.radius))
	out.append(chain[-1])
	return out


static func _length(pts: PackedVector2Array, sphere: PlanetSphere) -> float:
	var t := 0.0
	for i in pts.size() - 1:
		t += sphere.ground_dist(pts[i], pts[i + 1])
	return t


## A lamp every lamp_m of ground, sides taking turns, none inside a tunnel (the
## tunnel has its own runner lights): [{ at (map), side (+1/-1), along }].
static func _lamp_spots(pts: PackedVector2Array, rc: Dictionary, tunnels: Dictionary, took: Array, sphere: PlanetSphere) -> Array:
	var every := float(rc.get("lamp_m", 40.0))
	var keep := float(rc.get("tunnel_keep_m", 30.0))
	var out: Array = []
	var run := 0.0
	var next := every * 0.5
	var side := 1.0
	for i in pts.size() - 1:
		var seg := sphere.ground_dist(pts[i], pts[i + 1])
		while next <= run + seg:
			var at := RaceCourse.ground_lerp(pts[i], pts[i + 1], (next - run) / maxf(seg, 0.01), sphere.radius)
			if not _in_tunnel(at, tunnels, took, keep, sphere):
				out.append({ "at": at, "side": side, "seg": i })
				side = -side
			next += every
		run += seg
	return out


static func _in_tunnel(at: Vector2, tunnels: Dictionary, took: Array, keep: float, sphere: PlanetSphere) -> bool:
	for tid in took:
		var t: Array = tunnels[tid]
		for i in t.size() - 1:
			var a: Vector2 = t[i]
			var b: Vector2 = t[i + 1]
			var len := sphere.ground_dist(a, b)
			var n := maxi(1, int(len / 10.0))
			for k in n + 1:
				if sphere.ground_dist(at, RaceCourse.ground_lerp(a, b, float(k) / float(n), sphere.radius)) < keep:
					return true
	return false


## Where the boulders and spires keep off: every road point, `clear_m` round it
## ([Vector2 centre, radius, true]: the third element says the circle keeps only
## the small rocks off, never a mountain). Points close to a place's peak are
## left out (its foot is the road's end).
static func clear_circles(planet: Dictionary, sphere: PlanetSphere) -> Array:
	var rc := cfg_of(planet)
	var r := float(rc.get("clear_m", 12.0))
	var out: Array = []
	for road in plan(planet, sphere):
		var pts: PackedVector2Array = road.pts
		for i in range(0, pts.size(), 2):
			out.append([pts[i], r, true])
	return out


## Where the mountain clusters keep their peaks off, before any sphere is built:
## points along each road's corners, its tunnels' lines and a straight run to
## each place's peak (load_for widens each place's own clearing by approach_m)
## ([[unit dir (DesertLandforms._dir_of), keep m]], as load_for's `avoid`).
static func cluster_avoid(cfg: Dictionary, data: Dictionary) -> Array:
	var rc: Dictionary = cfg.get("roads", {})
	if rc.is_empty():
		return []
	var radius := float(cfg.get("sphere_radius", 4000.0))
	var keep := float(rc.get("width_m", 8.0)) * 0.5 + float(rc.get("peak_keep_m", 30.0))
	var places := {}
	for p in cfg.get("settlements", {}).get("places", []):
		places[str(p.id)] = [float(p.lat), float(p.lon)]
	var tunnels := {}
	for e in data.get("course_mountains", []):
		if e.has("path_ll"):
			tunnels[str(e.get("id", ""))] = e.path_ll
	var out: Array = []
	for r in rc.get("roads", []):
		var ll: Array = [places.get(str(r.from), [90.0, 0.0])]
		for v in r.get("via", []):
			if v is String and str(v).begins_with("tunnel:"):
				var t: Array = (tunnels.get(str(v).trim_prefix("tunnel:"), []) as Array).duplicate()
				if t.size() >= 2:
					if _ll_dist(ll[-1], t[-1]) < _ll_dist(ll[-1], t[0]):
						t.reverse()
					ll.append_array(t)
					# the lead past the far portal (the near one lies on the leg in)
					var ta := DesertLandforms._dir_of(float(t[-2][0]), float(t[-2][1]))
					var tb := DesertLandforms._dir_of(float(t[-1][0]), float(t[-1][1]))
					var ang := ta.angle_to(tb)
					if ang > 0.0:
						var past := ta.slerp(tb, 1.0 + float(rc.get("lead_m", 120.0)) / radius / ang)
						ll.append([rad_to_deg(asin(clampf(past.y, -1.0, 1.0))), rad_to_deg(atan2(past.z, past.x))])
			elif v is Array:
				ll.append(v)
		ll.append(places.get(str(r.to), [90.0, 0.0]))
		for i in ll.size() - 1:
			var a := DesertLandforms._dir_of(float(ll[i][0]), float(ll[i][1]))
			var b := DesertLandforms._dir_of(float(ll[i + 1][0]), float(ll[i + 1][1]))
			var n := maxi(1, int(ceil(a.angle_to(b) * radius / (keep * 0.8))))
			for k in n + 1:
				out.append([a.slerp(b, float(k) / float(n)), keep])
	return out


static func _ll_dist(a: Array, b: Array) -> float:
	return DesertLandforms._dir_of(float(a[0]), float(a[1])).angle_to(DesertLandforms._dir_of(float(b[0]), float(b[1])))


# ------------------------------------------------------------------ the look

func setup(town_demo, sphere: PlanetSphere, planet: Dictionary) -> void:
	name = "Roads"
	demo = town_demo
	sp = sphere
	roads = plan(planet, sphere)


## The strips and lamps: one node per road, built a road a call (StagedBuild).
func build(st: StagedBuild = null) -> void:
	if built:
		return
	built = true
	var lk := look()
	for road in roads:
		var node := Node3D.new()
		node.name = "Road_" + str(road.id)
		add_child(node)
		_strip(node, road, lk)
		_lamps(node, road, lk)
		await StagedBuild.slice_of(st)


## The packed-dirt strip: quads every half STEP_M m, the width of the road, each
## edge lifted `lift_m` over the real ground under it (so a dune's side slope
## neither buries one edge nor floats the other); one mesh per `chunk_m` of road
## so each is culled and drawn by distance on its own.
func _strip(node: Node3D, road: Dictionary, lk: Dictionary) -> void:
	var sc: Dictionary = lk.get("strip", {})
	var half := float(cfg_half(lk))
	var lift := float(sc.get("lift_m", 0.08))
	var per := maxi(2, int(float(sc.get("chunk_m", 200.0)) / STEP_M))
	var mat := _strip_mat(Color(str(sc.get("colour", "#7a3e26"))), float(sc.get("alpha", 0.55)))
	var pts: PackedVector2Array = road.pts
	var i := 0
	while i < pts.size() - 1:
		var j := mini(i + per, pts.size() - 1)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var mid := sp.surface_at(pts[(i + j) / 2].x, pts[(i + j) / 2].y)
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var first := true
		for k in range(i, j + 1):
			var halves := 1 if k == j else 2
			for hk in halves:
				var q := pts[k] if hk == 0 else pts[k].lerp(pts[k + 1], 0.5)
				var p := sp.surface_at(q.x, q.y)
				var up := sp.up_at(p)
				var f := _fwd(pts, k)
				var right := f.cross(up).normalized()
				var gl := _ground(p - right * half)
				var gr := _ground(p + right * half)
				var l := gl + sp.up_at(gl) * lift - mid
				var r := gr + sp.up_at(gr) * lift - mid
				if not first:
					st.set_normal(up)
					st.add_vertex(prev_l)
					st.add_vertex(r)
					st.add_vertex(prev_r)
					st.add_vertex(prev_l)
					st.add_vertex(l)
					st.add_vertex(r)
				first = false
				prev_l = l
				prev_r = r
		var mi := MeshInstance3D.new()
		mi.name = "Strip"
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = float(sc.get("draw_m", 600.0))
		mi.visibility_range_end_margin = 60.0
		mi.position = mid
		node.add_child(mi)
		i = j


## The real ground under a world point (the ball's surface there, dunes and all).
func _ground(p: Vector3) -> Vector3:
	var m := sp.world_to_map(p)
	return sp.surface_at(m.x, m.y)


func cfg_half(lk: Dictionary) -> float:
	return float(lk.get("strip", {}).get("width_m", 8.0)) * 0.5


## The road's way at point k (world, along the ground).
func _fwd(pts: PackedVector2Array, k: int) -> Vector3:
	var a := sp.surface_at(pts[maxi(k - 1, 0)].x, pts[maxi(k - 1, 0)].y)
	var b := sp.surface_at(pts[mini(k + 1, pts.size() - 1)].x, pts[mini(k + 1, pts.size() - 1)].y)
	var up := sp.up_at(a)
	var f := b - a
	f -= up * f.dot(up)
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


## The lamps: a post and a glowing head at each spot, in two MultiMeshes for the
## whole road (the heads drawn far, the posts near).
func _lamps(node: Node3D, road: Dictionary, lk: Dictionary) -> void:
	var lc: Dictionary = lk.get("lamp", {})
	var spots: Array = road.lamps
	if spots.is_empty():
		return
	var h := float(lc.get("height_m", 3.2))
	var side_m := cfg_half(lk) + float(lc.get("out_m", 1.2))
	var xfs: Array = []
	var origin := sp.surface_at(spots[spots.size() / 2].at.x, spots[spots.size() / 2].at.y)
	for s in spots:
		var p := sp.surface_at(s.at.x, s.at.y)
		var up := sp.up_at(p)
		var f := _fwd(road.pts, int(s.seg))
		var right := f.cross(up).normalized()
		var g := _ground(p + right * side_m * float(s.side))
		xfs.append(Transform3D(PlanetSphere.tilt_to(sp.up_at(g)), g - origin))
	var post := LookMeshKit.cyl(float(lc.get("post_r", 0.07)), float(lc.get("post_r", 0.07)), h, 6, 1)
	var head := LookMeshKit.ball(float(lc.get("head_r", 0.22)), 8, 4)
	var mats: LookMaterials = demo._flat_mats() if demo != null and demo.has_method("_flat_mats") else null
	node.add_child(_multi("LampPosts", post, _post_mat(mats, Color(str(lc.get("post", "#3b3631")))), xfs, Vector3(0, h * 0.5, 0),
		float(lc.get("post_draw_m", 450.0)), origin))
	node.add_child(_multi("LampHeads", head, _head_mat(mats, Color(str(lc.get("glow", "#ffc46a"))), float(lc.get("energy", 3.0))),
		xfs, Vector3(0, h + float(lc.get("head_r", 0.22)) * 0.6, 0), float(lc.get("glow_draw_m", 4000.0)), origin))
	lamp_count += spots.size()


func _multi(nm: String, mesh: Mesh, mat: Material, xfs: Array, lift: Vector3, draw: float, origin: Vector3) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		var xf: Transform3D = xfs[i]
		mm.set_instance_transform(i, Transform3D(xf.basis, xf.origin + xf.basis * lift))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = draw
	mmi.visibility_range_end_margin = draw * 0.1
	mmi.position = origin
	return mmi


static func _strip_mat(c: Color, alpha: float) -> StandardMaterial3D:
	var key := "strip/%s/%s" % [c.to_html(), alpha]
	if not _mat_cache.has(key) or not is_instance_valid(_mat_cache[key]):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(c.r, c.g, c.b, alpha)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 1.0
		m.render_priority = -1
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_cache[key] = m
	return _mat_cache[key]


static func _post_mat(mats: LookMaterials, c: Color) -> Material:
	if mats != null:
		return mats.flat(c, 0.7, 0.3)
	var key := "post/%s" % c.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		_mat_cache[key] = m
	return _mat_cache[key]


static func _head_mat(mats: LookMaterials, c: Color, energy: float) -> Material:
	var key := "head/%s/%s" % [c.to_html(), energy]
	if not _mat_cache.has(key) or not is_instance_valid(_mat_cache[key]):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		_mat_cache[key] = m
	return _mat_cache[key]
