class_name LauncherLook
extends RefCounted
## The seeker launcher from simple shapes: a tube carried on the right shoulder,
## flared at both ends, a pistol grip under it for the right hand, a front grip
## for the left, a pad where it sits on the shoulder and a band of trim. The scope
## is not built here: PlayerAvatar adds GunSights' own (the rifle's) from the same
## look's "scope" block, so it aims in like the sniper's.
##
## Model space (hand_weapons.json "seeker_launcher"): the tube's axis along +Z
## (the muzzle end), +Y up, +X the shooter's left; the origin on the axis where
## it sits on the shoulder. "tube" { radius, back, front, bell, bell_len } and
## "grips" { r, l } place it; "tint" { tube, trim, grip } colours it. Materials
## are shared between builds.
## `viewmodel` (the player's own): its parts are weapon_solid instead, so aimed in
## the scope keeps the tube past its "barrel_from" in view, pinned to the eye
## (GunSights). Those materials are the build's own; the guards' stay plain and
## shared (no shader instance uniforms on every guard).

const SOLID := preload("res://src/systems/look/shaders/weapon_solid.gdshader")

static var _mats: Dictionary = {}
static var _own: Dictionary = {}       ## this build's weapon_solid materials, while building


static func build(spec: Dictionary, viewmodel := false) -> Node3D:
	_own = {}
	var solid := viewmodel
	var root := Node3D.new()
	root.name = "SeekerLauncher"
	var t: Dictionary = spec.get("tube", {})
	var tint: Dictionary = spec.get("tint", {})
	var r := float(t.get("radius", 0.062))
	var back := float(t.get("back", -0.42))
	var front := float(t.get("front", 0.62))
	var bell := float(t.get("bell", r * 1.2))
	var bell_len := float(t.get("bell_len", 0.07))
	# The tube and its trim in the station favela's painted metal (chipped, grimy,
	# seamed); "tex_scale" tiles a metre.
	var ts := float(spec.get("tex_scale", 3.0))
	var tube := _mat(str(tint.get("tube", "#4f5a48")), 0.25, 0.6, solid, ts)
	var trim := _mat(str(tint.get("trim", "#2a2c2e")), 0.6, 0.45, solid, ts)
	var grip := _mat(str(tint.get("grip", "#1d1e20")), 0.0, 0.85, solid)
	var bore := _mat("#0a0a0b", 0.0, 1.0, solid)
	# The tube between the bells, the bells flaring out to both ends, and the dark
	# bore inside each end.
	var mid_from := back + bell_len
	var mid_to := front - bell_len
	_along_z(root, LookMeshKit.cyl(r, r, mid_to - mid_from, 20, 1), tube, (mid_from + mid_to) * 0.5)
	_along_z(root, LookMeshKit.cyl(bell, r, bell_len, 20, 1), trim, front - bell_len * 0.5)
	_along_z(root, LookMeshKit.cyl(r, bell, bell_len, 20, 1), trim, back + bell_len * 0.5)
	_along_z(root, LookMeshKit.cyl(bell - 0.008, bell - 0.008, 0.004, 20, 1), bore, front + 0.001)
	_along_z(root, LookMeshKit.cyl(bell - 0.008, bell - 0.008, 0.004, 20, 1), bore, back - 0.001)
	# Trim bands round the tube: behind the front bell, ahead of the grip.
	for z: float in [front - bell_len - 0.05, 0.3]:
		_along_z(root, LookMeshKit.cyl(r + 0.004, r + 0.004, 0.024, 20, 1), trim, z)
	# The shoulder pad under the tube where it rests on the shoulder.
	_mi(root, LookMeshKit.box(Vector3(r * 1.3, 0.02, 0.22)), grip, Vector3(0, -r - 0.006, 0.0))
	# The right hand's pistol grip, raked back, and its trigger guard.
	var g: Dictionary = spec.get("grips", {})
	var gr := _v3(g.get("r", [0.0, -0.135, 0.2]))
	var gl := _v3(g.get("l", [0.0, -0.125, 0.42]))
	_mi(root, LookMeshKit.box(Vector3(0.05, 0.03, 0.12)), trim, Vector3(0, -r - 0.012, gr.z + 0.02))
	var pg := _mi(root, LookMeshKit.box(Vector3(0.034, 0.12, 0.045)), grip, Vector3(gr.x, gr.y + 0.005, gr.z - 0.008))
	pg.rotation_degrees = Vector3(-17, 0, 0)
	_mi(root, LookMeshKit.box(Vector3(0.008, 0.006, 0.06)), trim, Vector3(0, -r - 0.058, gr.z + 0.055))
	_mi(root, LookMeshKit.box(Vector3(0.008, 0.04, 0.006)), trim, Vector3(0, -r - 0.04, gr.z + 0.085))
	# The left hand's front grip: a short post on a clamp.
	_along_z(root, LookMeshKit.cyl(r + 0.006, r + 0.006, 0.04, 20, 1), trim, gl.z)
	var post := _mi(root, LookMeshKit.cyl(0.017, 0.019, 0.1, 20, 1), grip, Vector3(gl.x, gl.y + 0.01, gl.z))
	post.rotation_degrees = Vector3(-10, 0, 0)
	return root


static func _along_z(parent: Node3D, mesh: Mesh, mat: Material, z: float) -> MeshInstance3D:
	var mi := _mi(parent, mesh, mat, Vector3(0, 0, z))
	mi.rotation_degrees = Vector3(90, 0, 0)
	return mi


static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## `tex` > 0: the favela's painted metal at that many tiles a metre.
static func _mat(hex: String, metal: float, rough: float, solid := false, tex := 0.0) -> Material:
	var key := "%s/%s/%s/%s" % [hex, metal, rough, tex]
	var t: Array = StallTextures._metal_tex() if tex > 0.0 else []
	if solid:
		if not _own.has(key):
			var sm := ShaderMaterial.new()
			sm.shader = SOLID
			sm.set_shader_parameter("albedo", Color.html(hex))
			sm.set_shader_parameter("metallic", metal)
			sm.set_shader_parameter("roughness", rough)
			if tex > 0.0:
				sm.set_shader_parameter("use_tex", true)
				sm.set_shader_parameter("tex_scale", tex)
				sm.set_shader_parameter("albedo_tex", t[0])
				sm.set_shader_parameter("normal_tex", t[1])
			_own[key] = sm
		return _own[key]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.html(hex)
	m.metallic = metal
	m.roughness = rough
	if tex > 0.0:
		m.albedo_texture = t[0]
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * tex
		if t[1] != null:
			m.normal_enabled = true
			m.normal_texture = t[1]
			m.normal_scale = 0.7
	_mats[key] = m
	return m


static func _v3(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
