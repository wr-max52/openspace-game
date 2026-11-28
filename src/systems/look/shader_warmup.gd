class_name ShaderWarmup
extends Node
## Issue #714: the first time a session draws a kind of material (a shader with
## its features, on a mesh of its vertex format) Godot compiles it and its
## pipelines on that frame: 40-85 ms for the club's booths, the barge's decks,
## the rock or the wreck plates, ~450 ms frames on a fresh install. Flying home
## from the gas giant, home's scene loads fresh, so all of them landed on the way
## down.
##
## content/look/warm_kinds.json lists, per planet, every kind its scene drew
## (recorded by the descent trace: DESCENT_KINDS=1). From prepare_m out in open
## space (SpaceTravel._prepare) this node makes one kind's material a frame (its
## shader compiles then, on the main thread) and draws it DRAW_AFTER frames later
## (its pipelines), far in front of the camera and too small to see, for
## SHOW_FRAMES frames. The materials stay alive for the session (_mats), so a kind
## is compiled once and never freed with the last scene that used it. Making
## them all at once was one ~0.8 s frame; one a frame, home's 71 take ~76 frames
## at up to ~50 ms each (a warm disk cache), out in open space.
##
## A kind is { "mat": {...}, "fmt": [...], "mm": "" }: the material (a
## StandardMaterial3D's shader-changing settings, or a ShaderMaterial's shader
## path), the mesh's vertex attributes, and for a MultiMesh its per-instance data.
## Headless there is nothing to compile, so it does nothing.

const CoreContentScript := preload("res://src/systems/dataload/core_content.gd")
const KINDS_PATH := "res://content/look/warm_kinds.json"
const PER_FRAME := 2       ## kinds drawn a frame
const SHOW_FRAMES := 2     ## frames each stays on screen
const AHEAD := 60.0        ## metres in front of the camera
const DRAW_AFTER := 3      ## frames between making a material (its shader compiles) and drawing it (its pipelines)
const SIZE := 0.02         ## metres across: under a pixel

static var _mats := {}            ## kind key -> its material, kept for the session
static var _meshes := {}          ## vertex format -> a one-triangle mesh of it
static var _done := {}            ## planet id -> true: warmed (or warming) this session
static var _tex: ImageTexture
static var _list := {}
static var last := {}             ## the last warm-up's { id, kinds, frames, worst_ms, slow } (the descent trace reads it)

var _queue: Array = []
var _shown: Array = []            ## [node, frames left]
var worst_ms := 0.0               ## the slowest frame it drew on (for the trace)
var _t := 0
var _id := ""
var _frames := 0
var _drawn: Array = []            ## the keys shown last frame (their compile lands on the next)
var slowest: Array = []           ## [ms, keys] of the slowest frames (the trace reads them)


## Starts warming planet `id`'s kinds under `parent`, once a session.
static func start(parent: Node, id: String) -> ShaderWarmup:
	if parent == null or _done.has(id) or DisplayServer.get_name() == "headless":
		return null
	var kinds: Array = kinds_for(id)
	if kinds.is_empty():
		return null
	_done[id] = true
	var w := ShaderWarmup.new()
	w.name = "ShaderWarmup"
	w._id = id
	for k in kinds:
		if not _mats.has(key_of(k)):
			w._queue.append(k)
	parent.add_child(w)
	return w


static func kinds_for(id: String) -> Array:
	if _list.is_empty() and FileAccess.file_exists(KINDS_PATH):
		_list = CoreContentScript.read_json(KINDS_PATH)
	return _list.get(id, [])


static func key_of(k: Dictionary) -> String:
	return JSON.stringify([k.get("mat", {}), k.get("fmt", []), k.get("mm", "")], "", true)


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if _t > 0:
		var ms := (now - _t) / 1000.0
		worst_ms = maxf(worst_ms, ms)
		if ms > 30.0:
			slowest.append([snappedf(ms, 0.1), _drawn])
	_drawn = []
	_t = now
	_frames += 1
	for i in range(_shown.size() - 1, -1, -1):
		_shown[i][1] -= 1
		if _shown[i][1] <= 0:
			_shown[i][0].queue_free()
			_shown.remove_at(i)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_make_next()
	var at := cam.global_position - cam.global_transform.basis.z * minf(AHEAD, cam.far * 0.5)
	for n in PER_FRAME:
		if _queue.is_empty() or _made_at.is_empty() or _frames - int(_made_at[0]) < DRAW_AFTER:
			break
		_made -= 1
		_made_at.pop_front()
		var k: Dictionary = _queue.pop_front()
		_drawn.append(key_of(k))
		var node := _show(k)
		if node != null:
			add_child(node)
			node.global_position = at
			_shown.append([node, SHOW_FRAMES])
	if _queue.is_empty() and _shown.is_empty():
		last = { "id": _id, "kinds": _mats.size(), "frames": _frames, "worst_ms": snappedf(worst_ms, 0.1), "slow": slowest }
		queue_free()


## The next queued kind's material. Godot compiles a new kind's shader on the
## main thread when the material is made, so one a frame; it is drawn (its
## pipelines) DRAW_AFTER frames later.
var _made := 0
var _made_at: Array = []          ## per queued kind, the frame its material was made
func _make_next() -> void:
	while _made < _queue.size():
		var k: Dictionary = _queue[_made]
		_made += 1
		_made_at.append(_frames)
		var key := key_of(k)
		if _mats.has(key):
			continue
		var mat := material_of(k.get("mat", {}))
		if mat != null:
			_mats[key] = mat
			mat.get_rid()
			_drawn.append("make:" + key)
			return


## One kind on a node, its material kept for the session. Null if it cannot be made.
func _show(k: Dictionary) -> GeometryInstance3D:
	var key := key_of(k)
	var mat: Material = _mats.get(key)
	if mat == null:
		mat = material_of(k.get("mat", {}))
		if mat == null:
			return null
		_mats[key] = mat
	var mesh := _mesh_of(k.get("fmt", []))
	var g: GeometryInstance3D
	var mm := str(k.get("mm", ""))
	if mm == "":
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		g = mi
	else:
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_colors = mm.contains("c")
		m.use_custom_data = mm.contains("d")
		m.mesh = mesh
		m.instance_count = 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = m
		g = mmi
	g.material_override = mat
	g.scale = Vector3.ONE * SIZE
	return g


static func material_of(d: Dictionary) -> Material:
	if d.has("shader"):
		var sh = load(str(d.shader)) if ResourceLoader.exists(str(d.shader)) else null
		if not sh is Shader:
			return null
		var sm := ShaderMaterial.new()
		sm.shader = sh
		return sm
	var m: BaseMaterial3D = ORMMaterial3D.new() if str(d.get("type", "")) == "orm" else StandardMaterial3D.new()
	for p in d.get("props", {}):
		var v = d.props[p]
		m.set(p, _texture() if v is String and v == "tex" else int(v) if v is float else v)
	return m


static func _texture() -> ImageTexture:
	if _tex == null:
		_tex = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	return _tex


const _ATTRS := { "normal": Mesh.ARRAY_FORMAT_NORMAL, "tangent": Mesh.ARRAY_FORMAT_TANGENT,
	"color": Mesh.ARRAY_FORMAT_COLOR, "uv": Mesh.ARRAY_FORMAT_TEX_UV, "uv2": Mesh.ARRAY_FORMAT_TEX_UV2 }


static func _mesh_of(fmt: Array) -> ArrayMesh:
	var key := ",".join(fmt)
	if _meshes.has(key):
		return _meshes[key]
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 0)])
	if fmt.has("normal"):
		a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	if fmt.has("tangent"):
		a[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1])
	if fmt.has("color"):
		a[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	if fmt.has("uv"):
		a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN])
	if fmt.has("uv2"):
		a[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	_meshes[key] = mesh
	return mesh


# ------------------------------------------------------------- recording

## Every kind drawn under `root` (see the top): what warm_kinds.json lists.
static func record(root: Node) -> Array:
	var seen := {}
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var g := n as GeometryInstance3D
		if g == null or not g.is_visible_in_tree():
			continue
		var mesh: Mesh = null
		var mm := ""
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var m := (g as MultiMeshInstance3D).multimesh
			mesh = m.mesh
			mm = "i" + ("c" if m.use_colors else "") + ("d" if m.use_custom_data else "")
		if mesh == null:
			continue
		var fmt_all: Array = []
		if mesh is PrimitiveMesh:
			fmt_all = ["normal", "tangent", "uv"] + (["uv2"] if (mesh as PrimitiveMesh).add_uv2 else [])
		elif not mesh is ArrayMesh:
			continue
		for s in mesh.get_surface_count():
			var fmt := fmt_all
			if mesh is ArrayMesh:
				if (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
					continue
				fmt = _format((mesh as ArrayMesh).surface_get_format(s))
			var mat: Material = g.material_override
			if mat == null and g is MeshInstance3D:
				mat = (g as MeshInstance3D).get_surface_override_material(s)
			if mat == null:
				mat = mesh.surface_get_material(s)
			var md := describe(mat)
			if md.is_empty():
				continue
			var k := { "mat": md, "fmt": fmt, "mm": mm }
			var key := key_of(k)
			if not seen.has(key):
				seen[key] = true
				out.append(k)
	return out


static func _format(f: int) -> Array:
	var out: Array = []
	for name in _ATTRS:
		if f & int(_ATTRS[name]):
			out.append(name)
	return out


## A material's shader-changing settings ({} for none, or one that cannot be remade).
static func describe(mat: Material) -> Dictionary:
	if mat is ShaderMaterial:
		var sh := (mat as ShaderMaterial).shader
		if sh == null or not sh.resource_path.begins_with("res://"):
			return {}
		return { "shader": sh.resource_path }
	if not mat is BaseMaterial3D:
		return {}
	var fresh: BaseMaterial3D = ORMMaterial3D.new() if mat is ORMMaterial3D else StandardMaterial3D.new()
	var props := {}
	for p in mat.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_STORAGE) or str(p.name).begins_with("metadata/"):
			continue
		var v = mat.get(p.name)
		if int(p.type) in [TYPE_BOOL, TYPE_INT]:
			if v != fresh.get(p.name) and str(p.name) != "render_priority":
				props[p.name] = v
		elif v is Texture2D and fresh.get(p.name) == null:
			props[p.name] = "tex"
	var d := { "props": props }
	if mat is ORMMaterial3D:
		d["type"] = "orm"
	return d
