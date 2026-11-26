class_name WelderLook
extends RefCounted
## Issue #722: the plasma welder from simple shapes, shaped like a real welding
## gun, in the energy blade's own space so it sits in the same grip: the handle
## where the hilt is (along +Y, the top at y = 0), a head on top with the trigger
## in front, then a long rod that leans forward up to about face height and hooks
## over to point straight ahead (+Z, the way you face in the guard pose), the
## nozzle at its end about half a metre in front of the face, like a bow. A hose
## stub leaves the bottom of the handle. A "Nozzle" node at the tip (its +Y along
## the nozzle) is where WelderFx goes. Colours: hand_weapons.json "plasma_welder"
## "tint". Materials are shared between builds.

const NECK_DEG := -15.0             ## the neck, degrees off the handle (in the grip it leans about 20 degrees forward)
const TIP_DEG := 55.0               ## the bent end, degrees off the handle: level and straight ahead in the grip
const NECK_LEN := 0.42              ## long enough to bring the tip up to the face...
const TIP_LEN := 0.08               ## ...and about 0.45 m in front of it, where the sparks fly

static var _mats: Dictionary = {}


static func build(tint: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "PlasmaWelder"
	var body := _mat(str(tint.get("body", "#5a5650")), 0.5, 0.55)
	var trim := _mat(str(tint.get("trim", "#c9a26a")), 0.7, 0.4)
	var accent := _mat(str(tint.get("tank", "#8a3a22")), 0.3, 0.6)
	var grip := _mat("#2a2826", 0.0, 0.85)
	var glow := _glow(str(tint.get("glow", "#7fd8ff")))
	# The handle, where the blade's hilt is, and the hose out of its foot.
	_mi(root, _cyl(0.021, 0.023, 0.22), grip, Vector3(0, -0.12, 0))
	_mi(root, _cyl(0.026, 0.026, 0.02), trim, Vector3(0, -0.235, 0))
	_seg(root, Vector3(0, -0.245, 0), Vector3(0, -0.33, -0.06), 0.014, 0.014, grip)
	# The head on top, and the trigger under its front.
	_mi(root, _box(Vector3(0.05, 0.06, 0.07)), body, Vector3(0, 0.025, 0.01))
	_mi(root, _box(Vector3(0.054, 0.01, 0.074)), trim, Vector3(0, 0.0, 0.01))
	_mi(root, _box(Vector3(0.016, 0.045, 0.014)), accent, Vector3(0, -0.03, 0.035))
	# The neck: up at an angle, a joint, then straight ahead to the nozzle.
	var a := Vector3(0, 0.05, 0.02)
	var d1 := Vector3(0, cos(deg_to_rad(NECK_DEG)), sin(deg_to_rad(NECK_DEG)))
	var b := a + d1 * NECK_LEN
	_seg(root, a, b, 0.011, 0.013, body)
	var joint := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.013
	sm.height = 0.026
	sm.radial_segments = 10
	sm.rings = 5
	joint.mesh = sm
	joint.material_override = body
	joint.position = b
	root.add_child(joint)
	var d2 := Vector3(0, cos(deg_to_rad(TIP_DEG)), sin(deg_to_rad(TIP_DEG)))
	var c := b + d2 * TIP_LEN
	_seg(root, b, c, 0.0105, 0.011, body)
	# The nozzle: a wider trim cup with a glowing ring at the tip.
	var e := c + d2 * 0.045
	_seg(root, c, e, 0.014, 0.017, trim)
	var ring := _mi(root, _cyl(0.0085, 0.0085, 0.004), glow, e)
	ring.basis = _along(d2)
	var nozzle := Node3D.new()
	nozzle.name = "Nozzle"
	nozzle.transform = Transform3D(_along(d2), e + d2 * 0.004)
	root.add_child(nozzle)
	root.set_meta("grips", { "r": Vector3(0, -0.05, 0), "l": Vector3(0, -0.18, 0) })
	return root


## A cylinder from `from` to `to` (radii at each end).
static func _seg(parent: Node3D, from: Vector3, to: Vector3, r_from: float, r_to: float, mat: Material) -> MeshInstance3D:
	var d := to - from
	var m := _mi(parent, _cyl(r_to, r_from, d.length()), mat, (from + to) * 0.5)
	m.basis = _along(d.normalized())
	return m


## A basis whose +Y runs along `d`.
static func _along(d: Vector3) -> Basis:
	var y := d.normalized()
	var hint := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.BACK
	var z := hint.cross(y).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


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
