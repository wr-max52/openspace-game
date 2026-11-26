extends GutTest
## Issue #695: two NPC bodies of the same look (each NPC has its own CharacterKit,
## on the town's one LookMaterials) share their materials and Skins: what every
## body of a look makes the same way is made once.

const LOOKS := ["remnant_trooper", "remnant_marked", "local", "desert_nomad", "cantina_owner_station"]


func _surfaces(root: Node) -> Array:
	var out: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			out.append([str(root.get_path_to(m)) + ":%d" % i, m.get_active_material(i), m.skin])
	return out


func test_two_bodies_of_one_look_share_materials_and_skins() -> void:
	var mats := LookMaterials.new()
	for look in LOOKS:
		var a: Node3D = CharacterKit.new(mats, -1000.0).build(look)
		var b: Node3D = CharacterKit.new(mats, -1000.0).build(look, "", a.get_meta("outfit", {}))
		var sa := _surfaces(a)
		var sb := _surfaces(b)
		assert_eq(sa.size(), sb.size(), "%s: the same surfaces" % look)
		var own_mats: Array = []
		var own_skins: Array = []
		for i in mini(sa.size(), sb.size()):
			if sa[i][1] != null and not is_same(sa[i][1], sb[i][1]):
				own_mats.append(sa[i][0])
			if sa[i][2] != null and not is_same(sa[i][2], sb[i][2]):
				own_skins.append(sa[i][0])
		assert_eq(own_mats.size(), 0, "%s: every material shared (%d of %d each its own: %s)" % [look, own_mats.size(), sa.size(), str(own_mats.slice(0, 3))])
		assert_eq(own_skins.size(), 0, "%s: every Skin shared (%d each its own: %s)" % [look, own_skins.size(), str(own_skins.slice(0, 3))])
		a.free()
		b.free()
