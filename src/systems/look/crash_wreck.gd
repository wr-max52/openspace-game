class_name CrashWreck
extends Node3D
## Issue #404: a destroyed vehicle's crash, played on its own model. It falls along
## CrashPath (spiral), blows up where it meets the sand (impact), splits into two
## halves cut across its middle that tilt apart and settle into the sand (sink),
## burns with jet flames and light smoke for about a minute (burn), and then lies
## there dark and cold (cold). Once it is out of sight and far enough away it frees
## itself; it is not saved. The halves are solid like any scenery and can not be
## boarded. Thin: the maths is CrashPath, the numbers content/look/crash.json.

signal phase_changed(phase: String)

const SPIRAL := "spiral"
const SINK := "sink"
const BURN := "burn"
const COLD := "cold"

var kind := "speeder"
var cfg: Dictionary = {}
var phase := SPIRAL
var t := 0.0                          ## seconds since the crash began
var t_impact := 0.0
var t_landed := 0.0                   ## seconds since impact
var halves: Array = []                ## [front, back] Node3D, after impact
var camera_fn: Callable               ## -> Camera3D, for the out-of-sight check (default: the viewport's)

var _start: Dictionary = {}
var _ground: Callable
var _look: Node3D                     ## the vehicle's own model while it falls
var _look_xf := Transform3D.IDENTITY  ## the model's transform in the wreck's frame
var _up := Vector3.UP
var _rest: Transform3D                ## the impact pose
var _flames: Array = []
var _smokes: Array = []
var _trail: CPUParticles3D
var _burnt: StandardMaterial3D
var _check := 0.0
var _boom_size := 1.0
var _boom := true                     ## the impact's own blast (off: the caller has its own)
var _parked := false                  ## blown up where it stands: no fall
var _box := AABB()                    ## the model's bounds in the wreck's frame
var _cut := 0.0                       ## where it breaks (z in the wreck's frame)
var _glow: OmniLight3D                ## the fire's light while the flames last

static var _halves_cache: Dictionary = {}   ## "mesh id|xf|side" -> ArrayMesh


## A crash for `look` (the vehicle's model, any node: it is taken over and moved
## here) starting from `start` (CrashPath's). `ground` gives the sand point under a
## point. Added to `parent`. Returns null (and leaves `look` alone) when it can not.
## opts: parked (true: no fall, straight to the blast and the split, as a ship shot
## to pieces on the ground), boom (false: the caller has its own blasts).
static func spawn(parent: Node, crash_kind: String, look: Node3D, start: Dictionary, ground: Callable, opts: Dictionary = {}) -> CrashWreck:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree() or look == null or not ground.is_valid():
		return null
	var w := CrashWreck.new()
	w.setup(crash_kind, look, start, ground, opts)
	parent.add_child(w)
	w._take(look)
	return w


## A copy of a model for a wreck, without its scripts, signals or groups: for a
## vehicle that keeps its own model (a parked ship's berth, a fighter that comes
## back, the barge that is rebuilt). Placed where the model is.
static func model_copy(model: Node3D) -> Node3D:
	var c := model.duplicate(0) as Node3D
	c.visible = true
	return c


func setup(crash_kind: String, look: Node3D, start: Dictionary, ground: Callable, opts: Dictionary = {}) -> void:
	kind = crash_kind
	cfg = CrashPath.for_kind(kind)
	_parked = bool(opts.get("parked", false))
	if _parked:
		# Where it stands (often a pad, not sand): no fall, and it settles only a little.
		cfg = cfg.duplicate()
		for k in ["hop_m_s", "spin_deg_s", "pitch_deg_s"]:
			cfg[k] = 0.0
		cfg["sink_m"] = float(cfg.get("sink_m", 0.5)) * float(cfg.get("parked_sink", 0.3))
		start = start.duplicate()
		start["vel"] = Vector3.ZERO
	_boom = bool(opts.get("boom", true))
	_start = start
	_ground = ground
	_look = look
	_up = (start.get("up", Vector3.UP) as Vector3).normalized()
	t_impact = 0.0 if _parked else CrashPath.impact_time(start, cfg, ground)
	_boom_size = float(cfg.get("impact_size", 1.0))
	name = "Crash_" + kind


func _take(look: Node3D) -> void:
	var start_xf := Transform3D((_start.get("basis", Basis.IDENTITY) as Basis).orthonormalized(), _start.get("pos", Vector3.ZERO))
	global_transform = start_xf
	var gx := look.global_transform if look.is_inside_tree() else start_xf
	_look_xf = start_xf.affine_inverse() * gx
	if look.get_parent() != null:
		look.get_parent().remove_child(look)
	add_child(look)
	look.transform = _look_xf
	_strip(look)
	_trail = ExplosionFx.smoke_trail(self, Vector3.ZERO, float(cfg.get("smoke_size", 1.0)))


func _process(dt: float) -> void:
	t += dt
	match phase:
		SPIRAL:
			if _parked:
				_impact(Transform3D((_start.get("basis", Basis.IDENTITY) as Basis).orthonormalized(), _start.get("pos", Vector3.ZERO)))
				return
			var p := CrashPath.pose(_start, t, cfg, _ground, t_impact)
			global_transform = p.xf
			if p.landed:
				_impact(p.xf)
		SINK, BURN:
			t_landed += dt
			_settle()
			_burn(dt)
		COLD:
			t_landed += dt
	if phase != SPIRAL:
		_check -= dt
		if _check <= 0.0:
			_check = float(cfg.get("despawn_check_s", 1.0))
			if out_of_sight():
				queue_free()


## Away from the player's eye and further than despawn_m (no camera: away).
func out_of_sight() -> bool:
	var cam: Camera3D = camera_fn.call() if camera_fn.is_valid() else (get_viewport().get_camera_3d() if is_inside_tree() else null)
	if cam == null or not is_instance_valid(cam):
		return true
	var at := global_position
	if cam.global_position.distance_to(at) < float(cfg.get("despawn_m", 160.0)):
		return false
	return not cam.is_position_in_frustum(at)


func _set_phase(p: String) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(p)


# ------------------------------------------------------------------ impact and split

func _impact(xf: Transform3D) -> void:
	_rest = xf
	if _boom:
		ExplosionFx.big(get_parent(), xf.origin + _up * 0.5, _boom_size)
		Sound.play("vehicle_boom", xf.origin)
	if _trail != null:
		_trail.emitting = false
		_trail.queue_free()
		_trail = null
	# Settle level along the ground's up, keeping the heading: the halves lie in the
	# sand, not standing on a wingtip.
	var fwd := -xf.basis.z
	fwd = (fwd - _up * fwd.dot(_up))
	fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else _up.cross(Vector3.RIGHT).normalized()
	_rest = Transform3D(Basis.looking_at(fwd, _up), xf.origin)
	global_transform = _rest
	_split()
	_set_phase(SINK)


## The model as two halves cut across its middle (the plane through its centre,
## square to its nose), each its own node, the original freed.
func _split() -> void:
	_burnt = StandardMaterial3D.new()
	_burnt.albedo_color = Color(0.05, 0.04, 0.035, 0.0)
	_burnt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_burnt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var parts: Array = []
	var engines: Array = []
	if _look != null and is_instance_valid(_look):
		_collect(_look, _look_xf, parts, engines)  # each mesh in the wreck's frame, the engine flames apart
	var centre := Vector3.ZERO
	var box := AABB()
	var first := true
	for pr in parts:
		var a: AABB = pr.xf * (pr.mi as MeshInstance3D).get_aabb()
		box = a if first else box.merge(a)
		first = false
	if not first:
		centre = box.get_center()
	_box = box
	_cut = centre.z
	for side in [0, 1]:
		var h := Node3D.new()
		h.name = "Front" if side == 0 else "Back"
		add_child(h)
		for pr in parts:
			var mesh := _half_mesh((pr.mi as MeshInstance3D).mesh, pr.xf, centre.z, side == 0)
			if mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.transform = pr.xf
			mi.material_override = (pr.mi as MeshInstance3D).material_override
			_char(mi)
			h.add_child(mi)
		_add_collider(h, box, centre.z, side == 0)
		halves.append(h)
	# The engines that were lit as it came down keep burning on their half, whole
	# (not cut, not charred), and die with the fire's flames below.
	for e in engines:
		var en: Node3D = e.node
		var side := 0 if (e.xf as Transform3D).origin.z < centre.z else 1
		en.get_parent().remove_child(en)
		halves[side].add_child(en)
		en.transform = e.xf
		en.set_meta("base_scale", (e.xf as Transform3D).basis.get_scale())
		_flames.append(en)
	if _look != null and is_instance_valid(_look):
		_look.queue_free()
	_look = null
	var r := float(cfg.get("flame_radius", 0.4))
	var fl := float(cfg.get("flame_length", 2.0))
	for i in halves.size():
		var h: Node3D = halves[i]
		# Out of the top of the broken end, pointing up (a flame's -y is its exhaust).
		# flame_y: how far up the model the break burns (the barge's masts are not its deck).
		var top := box.position.y + box.size.y * clampf(float(cfg.get("flame_y", 1.0)), 0.0, 1.0)
		var at := Vector3(centre.x, top if not first else 0.3, centre.z + (-0.15 if i == 0 else 0.15) * box.size.z * 0.5)
		var flame := EngineFlame.build(h, Transform3D(Basis(Vector3.RIGHT, PI), at), r, fl, EngineFlame.JET, 12)
		_flames.append(flame)
		var sm := ExplosionFx.smoke_trail(h, at, float(cfg.get("smoke_size", 1.0)), int(cfg.get("smoke_amount", 14)),
			float(cfg.get("smoke_life_s", 4.5)))
		if sm != null:
			_smokes.append(sm)
	_glow = OmniLight3D.new()
	_glow.light_color = Color("#ff9a4a")
	_glow.omni_range = maxf(4.0, box.size.length() * 1.5)
	_glow.shadow_enabled = false
	_glow.position = Vector3(centre.x, box.position.y + box.size.y * clampf(float(cfg.get("flame_y", 1.0)), 0.0, 1.0) + 0.5, centre.z)
	add_child(_glow)
	_settle()


## Burnt: every material a dark copy (shared, made once per material; the glow
## goes out). A material that is not a BaseMaterial3D gets the dark overlay instead.
func _char(mi: MeshInstance3D) -> void:
	var k := float(cfg.get("burnt_alpha", 0.7))
	var all_base := true
	if mi.material_override != null:
		if mi.material_override is BaseMaterial3D:
			mi.material_override = _dark(mi.material_override, k)
		else:
			all_base = false
	else:
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m is BaseMaterial3D:
				mi.set_surface_override_material(si, _dark(m, k))
			elif m != null:
				all_base = false
	if not all_base:
		mi.material_overlay = _burnt


static var _dark_cache: Dictionary = {}

static func _dark(m: BaseMaterial3D, k: float) -> BaseMaterial3D:
	var key := "%d|%.2f" % [m.get_instance_id(), k]
	if not _dark_cache.has(key):
		var d := m.duplicate() as BaseMaterial3D
		d.albedo_color = Color(m.albedo_color.r * (1.0 - k), m.albedo_color.g * (1.0 - k) * 0.95, m.albedo_color.b * (1.0 - k) * 0.9, m.albedo_color.a)
		d.emission_enabled = false
		d.metallic = minf(d.metallic, 0.2)
		d.roughness = 1.0
		_dark_cache[key] = d
	return _dark_cache[key]


## Every MeshInstance3D under `n` with its transform in the wreck's frame (`xf` is n's).
## Engine flames (a ship's "Flames", a speeder's boosters) go in `engines` instead,
## one per nozzle, and only if they were lit: they are fire, not hull, so they are
## never cut into the halves (they would glow there for good).
func _collect(n: Node, xf: Transform3D, out: Array, engines: Array = []) -> void:
	for c in n.get_children():
		var cxf := xf
		if c is Node3D:
			cxf = xf * (c as Node3D).transform
		if c is Node3D and c.has_meta("no_bounds") and String(c.name) == "Flames":
			if (c as Node3D).visible:
				for fl in c.get_children():
					if fl is Node3D and (fl as Node3D).visible:
						engines.append({ "node": fl, "xf": cxf * (fl as Node3D).transform })
			continue
		if c is MeshInstance3D and String(c.name).begins_with("BoosterFlame"):
			if (c as MeshInstance3D).visible:
				engines.append({ "node": c, "xf": cxf })
			continue
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and (c as MeshInstance3D).visible:
			out.append({ "mi": c, "xf": cxf })
		_collect(c, cxf, out, engines)


## Off for a wreck: lights, particles, sounds and any script ticking under it.
func _strip(n: Node) -> void:
	for c in n.get_children():
		if c is Light3D or c is GPUParticles3D or c is CPUParticles3D or c is AudioStreamPlayer3D:
			c.queue_free()
			continue
		c.process_mode = Node.PROCESS_MODE_DISABLED
		_strip(c)


## One half of `mesh`: the triangles whose middle lies in front of (`front`) or
## behind the plane z = `cut` of the model's frame (`xf` puts the mesh in it). The
## vertices are kept as they are, only the index list is cut, so every surface
## keeps its material and attributes. Cached: parked ships of one model share it.
static func _half_mesh(mesh: Mesh, xf: Transform3D, cut: float, front: bool) -> ArrayMesh:
	if mesh == null:
		return null
	var key := "%d|%s|%.3f|%s" % [mesh.get_rid().get_id(), str(xf), cut, front]
	if _halves_cache.has(key):
		return _halves_cache[key]
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			continue                   # a PrimitiveMesh (box, cylinder) is always triangles
		var arr: Array = mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var keep := PackedInt32Array()
		var i := 0
		while i + 2 < idx.size():
			var m := (verts[idx[i]] + verts[idx[i + 1]] + verts[idx[i + 2]]) / 3.0
			var z := (xf * m).z
			if (z < cut) == front:     # the nose is -z
				keep.append(idx[i])
				keep.append(idx[i + 1])
				keep.append(idx[i + 2])
			i += 3
		if keep.is_empty():
			continue
		arr[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(si))
	if out.get_surface_count() == 0:
		out = null
	_halves_cache[key] = out
	return out


## A box the size of the half, solid like scenery (it can not be boarded).
func _add_collider(h: Node3D, box: AABB, cut: float, front: bool) -> void:
	if box.size == Vector3.ZERO:
		return
	var z0 := box.position.z if front else cut
	var z1 := cut if front else box.end.z
	if z1 - z0 < 0.05:
		return
	var body := StaticBody3D.new()
	body.name = "Solid"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(box.size.x, box.size.y * 0.8, z1 - z0)
	cs.shape = shape
	cs.position = Vector3(box.get_center().x, box.get_center().y, (z0 + z1) * 0.5)
	body.add_child(cs)
	h.add_child(body)


# ------------------------------------------------------------------ settle and burn

## The halves pull apart and tip over their own middles, broken ends down into
## the sand and outer ends up, and sink over sink_s.
func _settle() -> void:
	var k := clampf(t_landed / maxf(0.01, float(cfg.get("sink_s", 3.0))), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var snap := 1.0 - pow(1.0 - minf(1.0, k * 3.0), 2.0)      # the break opens fast, then it settles
	var depth := float(cfg.get("sink_m", 0.5)) * e
	var tilt := deg_to_rad(float(cfg.get("split_deg", 12.0))) * snap
	var gap := float(cfg.get("split_gap_m", 0.5)) * 0.5 * snap
	for i in halves.size():
		var h: Node3D = halves[i]
		var s := -1.0 if i == 0 else 1.0                 # front half is -z (the nose)
		var mid := Vector3(0, _box.get_center().y, (_cut + (_box.position.z if i == 0 else _box.end.z)) * 0.5)
		var rot := Basis(Vector3.RIGHT, -s * tilt)
		h.transform = Transform3D(rot, mid - rot * mid + Vector3(0, -depth, s * gap))
	if _glow != null:
		_glow.light_energy = 1.4 * clampf(1.0 - t_landed / maxf(0.01, float(cfg.get("flame_s", 25.0))), 0.0, 1.0) \
			* (0.8 + 0.3 * sin(t * 17.0))


## The flames shrink away over flame_s, the smoke thins over smoke_s; then cold.
func _burn(_dt: float) -> void:
	var flame_k := clampf(1.0 - t_landed / maxf(0.01, float(cfg.get("flame_s", 25.0))), 0.0, 1.0)
	for f in _flames:
		if is_instance_valid(f):
			var flick := 0.85 + 0.25 * absf(sin(t * 23.0 + float(f.get_instance_id() % 7)))
			var b: Vector3 = (f as Node3D).get_meta("base_scale", Vector3.ONE)    # an engine's: its width and length when it hit
			(f as Node3D).scale = Vector3(b.x, maxf(0.001, b.y * flame_k * flick), b.z)
			(f as Node3D).visible = flame_k > 0.01
	var smoke_s := maxf(0.01, float(cfg.get("smoke_s", 60.0)))
	var smoke_k := clampf(1.0 - t_landed / smoke_s, 0.0, 1.0)
	for s in _smokes:
		if is_instance_valid(s):
			(s as CPUParticles3D).color = Color(1, 1, 1, smoke_k)     # thins out (the ramp is multiplied by it)
	if _burnt != null:
		_burnt.albedo_color.a = float(cfg.get("burnt_alpha", 0.6)) * clampf(t_landed / 3.0, 0.0, 1.0)
	if phase == SINK and t_landed >= float(cfg.get("sink_s", 3.0)):
		_set_phase(BURN)
	if t_landed >= smoke_s:
		for f in _flames:
			if is_instance_valid(f):
				f.queue_free()
		if _glow != null:
			_glow.queue_free()
			_glow = null
		for s in _smokes:
			if is_instance_valid(s):
				(s as CPUParticles3D).emitting = false
		_flames.clear()
		_set_phase(COLD)
