extends GutTest
## Issue #544: one mesh kit and one JSON reader. Boxes, cylinders and balls come from
## LookMeshKit.box / cyl / ball (placed with LookMeshKit.mi), and JSON from
## CoreContent.read_json, so a builder never starts from a fresh copy and the render
## rules ("batch everything, share materials") have one place to live. This scan fails
## on any new local copy; a helper that is not a mesh at all wants a name that says
## what it is (_layout_box, _zone_box, _add_column).

const SCAN_DIRS := ["res://src/", "res://scenes/"]
const BANNED := ["func _box(", "func _cyl(", "func _read_json("]
const LookMeshKitScript := preload("res://src/systems/look/mesh_kit.gd")
const CoreContentScript := preload("res://src/systems/dataload/core_content.gd")

var _files := PackedStringArray()


func before_all() -> void:
	_files.clear()
	for d in SCAN_DIRS:
		_walk(d, _files)


func _walk(dir: String, out: PackedStringArray) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := dir + name
			if da.current_is_dir():
				_walk(full + "/", out)
			elif name.ends_with(".gd"):
				out.append(full)
		name = da.get_next()
	da.list_dir_end()


func test_the_scan_sees_the_kits() -> void:
	assert_true(_files.has("res://src/systems/look/mesh_kit.gd"), "src/ is scanned")
	assert_true(_files.has("res://scenes/lookdev/beauty_corner.gd"), "scenes/ is scanned")
	assert_gt(_files.size(), 100, "the whole tree, not one folder")


func test_no_local_copies_of_box_cyl_or_read_json() -> void:
	var hits := PackedStringArray()
	for path in _files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			for b in BANNED:
				if lines[i].contains(b):
					hits.append("%s:%d %s" % [path, i + 1, lines[i].strip_edges()])
	assert_eq(hits.size(), 0, "primitives come from LookMeshKit and JSON from CoreContent:\n" + "\n".join(hits))


func test_primitives_are_shared_by_their_exact_numbers() -> void:
	var a: BoxMesh = LookMeshKitScript.box(Vector3(0.3, 0.2, 0.1))
	assert_same(a, LookMeshKitScript.box(Vector3(0.3, 0.2, 0.1)), "the same box is one mesh")
	assert_ne(a, LookMeshKitScript.box(Vector3(0.3, 0.2, 0.1001)), "a size never rounds onto another")
	assert_eq(a.size, Vector3(0.3, 0.2, 0.1))
	var c: CylinderMesh = LookMeshKitScript.cyl(0.1, 0.2, 0.5, 12, 1, false)
	assert_same(c, LookMeshKitScript.cyl(0.1, 0.2, 0.5, 12, 1, false))
	assert_ne(c, LookMeshKitScript.cyl(0.1, 0.2, 0.5, 12, 1, true), "caps are part of the key")
	assert_almost_eq(c.top_radius, 0.1, 0.0001)
	assert_almost_eq(c.bottom_radius, 0.2, 0.0001)
	assert_almost_eq(c.height, 0.5, 0.0001)
	assert_eq([c.radial_segments, c.rings, c.cap_top, c.cap_bottom], [12, 1, false, false])
	var plain: CylinderMesh = LookMeshKitScript.cyl(0.1, 0.1, 0.5)
	var godot := CylinderMesh.new()
	assert_eq([plain.radial_segments, plain.rings], [godot.radial_segments, godot.rings],
		"left out, segments and rings are Godot's own")
	var s: SphereMesh = LookMeshKitScript.ball(0.2, 16, 8)
	assert_almost_eq(s.height, 0.4, 0.0001, "a ball is round unless given a height")
	assert_eq([s.radial_segments, s.rings, s.is_hemisphere], [16, 8, false])
	assert_almost_eq(LookMeshKitScript.ball(0.2, 16, 8, 0.3).height, 0.3, 0.0001)


func test_mi_places_and_parents() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var m: MeshInstance3D = LookMeshKitScript.mi(root, LookMeshKitScript.box(Vector3.ONE), null,
		Vector3(1, 2, 3), Basis.from_scale(Vector3(2, 2, 2)))
	assert_eq(m.get_parent(), root)
	assert_eq(m.position, Vector3(1, 2, 3))
	assert_eq(m.scale, Vector3(2, 2, 2))
	var lone: MeshInstance3D = LookMeshKitScript.mi(null, null, null)
	assert_null(lone.get_parent(), "no parent: the caller adds it")
	lone.free()


func test_read_json_is_quiet_and_always_a_dictionary() -> void:
	assert_false(CoreContentScript.read_json("res://content/core/manifest.json").is_empty())
	assert_eq(CoreContentScript.read_json("res://content/core/no_such_file.json"), {})
	assert_null(CoreContentScript.parse_json("res://content/core/no_such_file.json"))
