class_name PrimBatch
extends RefCounted
## Issue #693: boxes, cylinders and spheres merged into one mesh without reading
## anything back from the renderer. `SurfaceTool.append_from` on a primitive asks
## the GPU for its vertices and waits (render rule 5): the barge, the cruiser and
## the outposts' rooms spent most of their build doing it. Here each shape's
## triangles come from its own numbers, made once a session per size and kept,
## and each part is one native transform of those arrays.
##
## Boxes keep BoxMesh's UV layout (six faces on a 3 x 2 grid), which the
## cruiser_metal shader reads. No tangents: every material merged this way maps
## triplanar or has no normal map. Anything that is not a box, cylinder or
## sphere falls back to append_from, as before.
##
##     var b := PrimBatch.new()
##     b.add(box_mesh, xf)
##     b.add_box(Vector3(2, 1, 2), xf)
##     mi.mesh = b.commit()

static var _flats := {}                  ## shape key -> [vertices, normals, uvs], unindexed

var _v: Array = []                       ## PackedVector3Array per part
var _n: Array = []
var _uv: Array = []
var _st: SurfaceTool                     ## the fallback, for meshes it can not build


## Adds `mesh` turned by `xf`.
func add(mesh: Mesh, xf: Transform3D) -> void:
	var f := flat(mesh)
	if f.is_empty():
		if _st == null:
			_st = SurfaceTool.new()
			_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st.append_from(mesh, 0, xf)
		return
	_put(f, xf)


## Adds a box of `size` turned by `xf` (no BoxMesh made).
func add_box(size: Vector3, xf: Transform3D) -> void:
	_put(_box_flat(size), xf)


func is_empty() -> bool:
	return _v.is_empty() and _st == null


## Vertices so far (what the mesh will hold).
func vertex_count() -> int:
	var n := 0
	for a in _v:
		n += (a as PackedVector3Array).size()
	return n


## The parts as one ArrayMesh (null when there are none).
func commit() -> ArrayMesh:
	if _st != null:
		var arr := _st.commit_to_arrays()
		var fv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var fn = arr[Mesh.ARRAY_NORMAL]
		var fu = arr[Mesh.ARRAY_TEX_UV]
		_v.append(fv)
		_n.append(fn if fn is PackedVector3Array and (fn as PackedVector3Array).size() == fv.size() else _filled3(fv.size(), Vector3.UP))
		_uv.append(fu if fu is PackedVector2Array and (fu as PackedVector2Array).size() == fv.size() else _filled2(fv.size()))
		_st = null
	if _v.is_empty():
		return null
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	for i in _v.size():
		v.append_array(_v[i])
		n.append_array(_n[i])
		uv.append_array(_uv[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _put(f: Array, xf: Transform3D) -> void:
	_v.append(xf * (f[0] as PackedVector3Array))
	var b := xf.basis                     # a stretched part: normals stay square to its faces
	var nb := b.orthonormalized() if b.is_conformal() else b.inverse().transposed()
	_n.append(Transform3D(nb, Vector3.ZERO) * (f[1] as PackedVector3Array))
	_uv.append(f[2])


static func _filled3(count: int, v: Vector3) -> PackedVector3Array:
	var a := PackedVector3Array()
	a.resize(count)
	a.fill(v)
	return a


static func _filled2(count: int) -> PackedVector2Array:
	var a := PackedVector2Array()
	a.resize(count)
	return a


## Whether flat() can build `mesh` from its numbers.
static func can_flat(mesh: Mesh) -> bool:
	return mesh is BoxMesh or mesh is CylinderMesh or mesh is SphereMesh or mesh is TorusMesh


## A box's, cylinder's or sphere's triangles as [vertices, normals, uvs], made once
## a session per shape; [] for anything else.
static func flat(mesh: Mesh) -> Array:
	if mesh is BoxMesh:
		return _box_flat((mesh as BoxMesh).size)
	if mesh is CylinderMesh:
		var c := mesh as CylinderMesh
		var key := "c|%s|%s|%s|%d|%s|%s" % [c.top_radius, c.bottom_radius, c.height, c.radial_segments, c.cap_top, c.cap_bottom]
		if not _flats.has(key):
			var out := [[], [], []]
			_cyl_tris(out, c.top_radius, c.bottom_radius, c.height, c.radial_segments, c.cap_top, c.cap_bottom)
			_flats[key] = _packed(out)
		return _flats[key]
	if mesh is SphereMesh:
		var s := mesh as SphereMesh
		var key := "s|%s|%s|%d|%d|%s" % [s.radius, s.height, s.radial_segments, s.rings, s.is_hemisphere]
		if not _flats.has(key):
			var out := [[], [], []]
			_sphere_tris(out, s.radius, s.height, s.radial_segments, s.rings, s.is_hemisphere)
			_flats[key] = _packed(out)
		return _flats[key]
	if mesh is TorusMesh:
		var t := mesh as TorusMesh
		var key := "t|%s|%s|%d|%d" % [t.inner_radius, t.outer_radius, t.rings, t.ring_segments]
		if not _flats.has(key):
			var out := [[], [], []]
			_torus_tris(out, t.inner_radius, t.outer_radius, t.rings, t.ring_segments)
			_flats[key] = _packed(out)
		return _flats[key]
	return []


## The unit box, scaled per part: one set of arrays for every box size.
static func _box_flat(size: Vector3) -> Array:
	if not _flats.has("box"):
		var out := [[], [], []]
		_box_tris(out, Vector3(0.5, 0.5, 0.5))
		_flats["box"] = _packed(out)
	var unit: Array = _flats["box"]
	if size == Vector3.ONE:
		return unit
	var key := "b|%s" % size
	if not _flats.has(key):
		if _flats.size() > 4096:
			_flats.clear()                 # never grows without end (a size per part is rare)
			return _box_flat(size)
		var sc := Transform3D(Basis.from_scale(size), Vector3.ZERO)
		_flats[key] = [sc * (unit[0] as PackedVector3Array), unit[1], unit[2]]     # a box's normals do not change with its size
	return _flats[key]


static func _packed(out: Array) -> Array:
	return [PackedVector3Array(out[0]), PackedVector3Array(out[1]), PackedVector2Array(out[2])]


## A triangle, clockwise seen from `n`'s side (Godot's front faces).
static func _tri(out: Array, a: Vector3, b: Vector3, c: Vector3, n: Array, uv: Array) -> void:
	var swap := (b - a).cross(c - a).dot((n[0] as Vector3) + (n[1] as Vector3) + (n[2] as Vector3)) > 0.0
	var order := [0, 2, 1] if swap else [0, 1, 2]
	var pts := [a, b, c]
	for i in order:
		(out[0] as Array).append(pts[i])
		(out[1] as Array).append(n[i])
		(out[2] as Array).append(uv[i])


static func _quad(out: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Array, uv: Array) -> void:
	_tri(out, a, b, c, [n[0], n[1], n[2]], [uv[0], uv[1], uv[2]])
	_tri(out, a, c, d, [n[0], n[2], n[3]], [uv[0], uv[2], uv[3]])


static func _box_tris(out: Array, h: Vector3) -> void:
	# face: normal, its two axes across, its cell on BoxMesh's 3 x 2 UV grid
	var faces := [[Vector3.BACK, Vector3.RIGHT, Vector3.UP, Vector2(0, 0)], [Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, Vector2(1, 0)],
		[Vector3.FORWARD, Vector3.LEFT, Vector3.UP, Vector2(2, 0)], [Vector3.LEFT, Vector3.BACK, Vector3.UP, Vector2(0, 1)],
		[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD, Vector2(1, 1)], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK, Vector2(2, 1)]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var du := u * h
		var dv := v * h
		var cell: Vector2 = f[3]
		var uv := func(x: float, y: float) -> Vector2: return Vector2((cell.x + x) / 3.0, (cell.y + 1.0 - y) / 2.0)
		_quad(out, c - du - dv, c + du - dv, c + du + dv, c - du + dv, [n, n, n, n],
			[uv.call(0, 0), uv.call(1, 0), uv.call(1, 1), uv.call(0, 1)])


static func _cyl_tris(out: Array, rt: float, rb: float, h: float, seg: int, cap_top: bool, cap_bottom: bool) -> void:
	var hy := h * 0.5
	var slope := (rb - rt) / maxf(h, 0.001)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		var u0 := float(i) / seg
		var u1 := float(i + 1) / seg
		_quad(out, d0 * rb - Vector3(0, hy, 0), d1 * rb - Vector3(0, hy, 0), d1 * rt + Vector3(0, hy, 0), d0 * rt + Vector3(0, hy, 0),
			[n0, n1, n1, n0], [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)])
		if cap_top and rt > 0.0:
			_tri(out, Vector3(0, hy, 0), d0 * rt + Vector3(0, hy, 0), d1 * rt + Vector3(0, hy, 0), [Vector3.UP, Vector3.UP, Vector3.UP],
				[Vector2(0.5, 0.5), Vector2(0.5 + d0.x * 0.5, 0.5 + d0.z * 0.5), Vector2(0.5 + d1.x * 0.5, 0.5 + d1.z * 0.5)])
		if cap_bottom and rb > 0.0:
			_tri(out, Vector3(0, -hy, 0), d0 * rb - Vector3(0, hy, 0), d1 * rb - Vector3(0, hy, 0), [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN],
				[Vector2(0.5, 0.5), Vector2(0.5 + d0.x * 0.5, 0.5 + d0.z * 0.5), Vector2(0.5 + d1.x * 0.5, 0.5 + d1.z * 0.5)])


static func _sphere_tris(out: Array, r: float, h: float, seg: int, rings: int, hemi: bool) -> void:
	var sy := h / (2.0 * r) if r > 0.0 else 1.0           # SphereMesh squashes to its height
	var top := PI * 0.5
	var bot := 0.0 if hemi else -PI * 0.5
	var p := func(i: int, j: int) -> Vector3:
		var lat := lerpf(top, bot, float(j) / rings)
		var lon := TAU * i / seg
		return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
	for i in seg:
		for j in rings:
			var a: Vector3 = p.call(i, j)
			var b: Vector3 = p.call(i + 1, j)
			var c: Vector3 = p.call(i + 1, j + 1)
			var d: Vector3 = p.call(i, j + 1)
			var sc := Vector3(r, r * sy, r)
			var uv := [Vector2(float(i) / seg, float(j) / rings), Vector2(float(i + 1) / seg, float(j) / rings),
				Vector2(float(i + 1) / seg, float(j + 1) / rings), Vector2(float(i) / seg, float(j + 1) / rings)]
			_quad(out, a * sc, b * sc, c * sc, d * sc, [a, b, c, d], uv)


static func _torus_tris(out: Array, r_in: float, r_out: float, rings: int, segs: int) -> void:
	var mid := (r_in + r_out) * 0.5
	var tube := (r_out - r_in) * 0.5
	var p := func(i: int, j: int) -> Array:
		var a := TAU * i / rings
		var b := TAU * j / segs
		var ring := Vector3(cos(a), 0, sin(a))
		var n := ring * cos(b) + Vector3(0, sin(b), 0)
		return [ring * mid + n * tube, n, Vector2(float(i) / rings, float(j) / segs)]
	for i in rings:
		for j in segs:
			var a: Array = p.call(i, j)
			var b: Array = p.call(i + 1, j)
			var c: Array = p.call(i + 1, j + 1)
			var d: Array = p.call(i, j + 1)
			_quad(out, a[0], b[0], c[0], d[0], [a[1], b[1], c[1], d[1]], [a[2], b[2], c[2], d[2]])
