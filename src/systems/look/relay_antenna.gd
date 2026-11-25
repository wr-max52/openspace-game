class_name RelayAntenna
extends RefCounted
## The droid relays' antenna array (issue #355), pulled out (issue #610) so the
## race gates stand on the same mast: a guyed mast, three cross tiers with lamp
## boxes, two wing masts, a beacon and a small dish. Primitives only; meshes are
## shared by size, so every array in the world draws the same few meshes.
##
## build() returns the lamps it made (the tier-2 lamp boxes and the beacon), so
## a gate can swap their material when a racer goes through.

static var _meshes: Dictionary = {}


## `mats`: steel, dark, trim, glow (the tier-2 lamps), beacon. `base`: the foot of
## the mast in `root`'s frame.
static func build(root: Node3D, height: float, style: String, mats: Dictionary, base: Vector3,
		with_dish: bool = true) -> Array:
	var steel: Material = mats.steel
	var dark: Material = mats.dark
	var trim: Material = mats.trim
	var glow: Material = mats.glow
	var beacon: Material = mats.beacon
	var lamps: Array = []
	part(root, box(Vector3(1.3, 0.24, 1.3)), dark, base + Vector3(0, 0.12, 0))
	rod(root, 0.09, height, steel, base + Vector3(0, height * 0.5, 0), Vector3.UP)
	for side: float in [-1.0, 1.0]:
		rod(root, 0.045, height * 0.83, trim,
			base + Vector3(side * 0.35, height * 0.415, 0), Vector3(side * 0.04, 1, 0).normalized())
	var span := 3.4 if style == "wide" else 2.7
	for tier in 3:
		var y := height * (0.3 + tier * 0.25)
		var tier_span := span if tier == 1 or style == "wide" else span * 0.68
		rod(root, 0.055 if tier == 1 else 0.04, tier_span, steel, base + Vector3(0, y, 0), Vector3.RIGHT)
		rod(root, 0.04, 0.95, dark, base + Vector3(0, y + 0.28, 0), Vector3.FORWARD)
		for side: float in [-1.0, 1.0]:
			rod(root, 0.027, 0.8, trim, base + Vector3(side * tier_span * 0.31, y - 0.22, 0),
				Vector3(side * 0.45, 1, 0).normalized())
			var lamp := part(root, box(Vector3(0.13, 0.22, 0.13)), glow if tier == 2 else dark,
				base + Vector3(side * tier_span * 0.5, y, 0))
			if tier == 2:
				lamps.append(lamp)
	for side: float in [-1.0, 1.0]:
		var wing := base + Vector3(side * 1.35, height * 0.15, 0.2)
		rod(root, 0.035, height * 0.48, steel, wing + Vector3(0, height * 0.24, 0), Vector3.UP)
		rod(root, 0.025, 1.0, trim, wing + Vector3(0, height * 0.48, 0), Vector3.FORWARD)
		rod(root, 0.022, Vector3(0.9, height * 0.35, 0).length(), dark,
			base + Vector3(side * 0.32, height * 0.12, 0), Vector3(side * 0.9, height * 0.35, 0).normalized())
	part(root, box(Vector3(0.32, 0.38, 0.32)), trim, base + Vector3(0, height + 0.18, 0))
	lamps.append(part(root, box(Vector3(0.24, 0.24, 0.24)), beacon, base + Vector3(0, height + 0.48, 0)))
	if with_dish:
		# The dish is a small directional receiver below the top array.
		var key := "dish"
		if not _meshes.has(key):
			var dish := CylinderMesh.new()
			dish.top_radius = 0.08
			dish.bottom_radius = 0.72
			dish.height = 0.22
			dish.radial_segments = 12
			_meshes[key] = dish
		part(root, _meshes[key], steel, base + Vector3(0, height * 0.72, -0.28), Basis(Vector3.RIGHT, deg_to_rad(68.0)))
		part(root, box(Vector3(0.11, 1.1, 0.11)), trim, base + Vector3(0, height * 0.72 + 0.52, -0.28))
	return lamps


static func rod(root: Node3D, radius: float, length: float, mat: Material, at: Vector3, direction: Vector3) -> MeshInstance3D:
	var key := "rod/%.3f/%.3f" % [radius, length]
	if not _meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = length
		mesh.radial_segments = 6
		_meshes[key] = mesh
	return part(root, _meshes[key], mat, at, Basis(Quaternion(Vector3.UP, direction.normalized())))


static func box(size: Vector3) -> BoxMesh:
	var key := "box/%.3f/%.3f/%.3f" % [size.x, size.y, size.z]
	if not _meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	return _meshes[key]


static func part(root: Node3D, mesh: Mesh, mat: Material, at: Vector3, basis: Basis = Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	mi.position = at
	mi.basis = basis
	return mi
