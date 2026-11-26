class_name WelderLook
extends RefCounted
## Issue #722: the plasma welder from simple shapes, in the energy blade's own
## space so it sits in the same grip: the handle where the hilt is (along +Y,
## the top at y = 0), the welder's head above it and the nozzle pointing up the
## blade's way. A "Nozzle" node is where WelderFx goes. Colours: hand_weapons.json
## "plasma_welder" "tint". Materials are shared between builds.

static var _mats: Dictionary = {}


static func build(tint: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "PlasmaWelder"
	var body := _mat(str(tint.get("body", "#5a5650")), 0.5, 0.55)
	var trim := _mat(str(tint.get("trim", "#c9a26a")), 0.7, 0.4)
	var tank := _mat(str(tint.get("tank", "#8a3a22")), 0.3, 0.6)
	var grip := _mat("#2a2826", 0.0, 0.85)
	var glow := _glow(str(tint.get("glow", "#7fd8ff")))
	# The handle, where the blade's hilt is.
	_mi(root, _cyl(0.02, 0.022, 0.22), grip, Vector3(0, -0.12, 0))
	_mi(root, _cyl(0.026, 0.026, 0.02), trim, Vector3(0, -0.235, 0))
	# The head: a block with a trim band and a small gas tank on its side.
	_mi(root, _box(Vector3(0.06, 0.08, 0.07)), body, Vector3(0, 0.035, 0))
	_mi(root, _box(Vector3(0.064, 0.012, 0.074)), trim, Vector3(0, 0.0, 0))
	_mi(root, _cyl(0.018, 0.018, 0.09), tank, Vector3(0.045, 0.03, -0.01))
	_mi(root, _cyl(0.008, 0.008, 0.012), trim, Vector3(0.045, 0.081, -0.01))
	# The barrel and the nozzle, with a glowing ring at the tip.
	_mi(root, _cyl(0.011, 0.014, 0.12), body, Vector3(0, 0.135, 0))
	_mi(root, _cyl(0.006, 0.011, 0.03), trim, Vector3(0, 0.21, 0))
	_mi(root, _cyl(0.0075, 0.0075, 0.004), glow, Vector3(0, 0.226, 0))
	var nozzle := Node3D.new()
	nozzle.name = "Nozzle"
	nozzle.position = Vector3(0, 0.232, 0)
	root.add_child(nozzle)
	root.set_meta("grips", { "r": Vector3(0, -0.05, 0), "l": Vector3(0, -0.18, 0) })
	return root


static func _mi(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = at
	parent.add_child(m)
	return m


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 10
	c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _mat(hex: String, metal: float, rough: float) -> StandardMaterial3D:
	var k := "%s/%s/%s" % [hex, metal, rough]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(hex)
		m.metallic = metal
		m.roughness = rough
		_mats[k] = m
	return _mats[k]


static func _glow(hex: String) -> StandardMaterial3D:
	var k := "glow/" + hex
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(hex)
		m.emission_enabled = true
		m.emission = Color(hex)
		m.emission_energy_multiplier = 2.5
		_mats[k] = m
	return _mats[k]
