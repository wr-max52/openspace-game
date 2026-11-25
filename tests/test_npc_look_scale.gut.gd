extends GutTest
## An NPC body keeps its kit size (the archetype's height and bulk, a pack
## child's look_scale) once _stand_on_ground stands it along the ground's tilt.
## Since issue #77 the tilt replaced the look's basis every tick and dropped it.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var cc


func before_all() -> void:
	cc = CoreScript.new()
	cc.load_from()


func _body(soldier: Dictionary) -> NpcBody:
	var n := NpcBody.new()
	n.setup(soldier, Vector3.ZERO, 0.0, LookMaterials.new())
	add_child_autofree(n)
	return n


func _height_scale(n: NpcBody) -> float:
	return n.look_body.basis.get_scale().y


func test_archetype_size_survives_standing_on_the_ground() -> void:
	var n := _body(cc.get_soldier("gate_guard"))
	var built := n.look_body.scale
	assert_ne(built, Vector3.ONE, "a trooper is not the reference size")
	n._stand_on_ground()
	assert_almost_eq(n.look_body.basis.get_scale(), built, Vector3.ONE * 0.001, "flat ground: same size")
	n.tilt = Basis(Vector3.RIGHT, 0.4)   # far round the home planet's curve
	n._stand_on_ground()
	assert_almost_eq(n.look_body.basis.get_scale(), built, Vector3.ONE * 0.001, "tilted: same size")
	assert_almost_eq(n.look_body.basis.y.normalized().dot(Vector3.UP), cos(0.4), 0.001, "and stood along the tilt")


func test_pack_child_stays_small() -> void:
	var adult := _body(cc.get_soldier("gate_guard"))
	var soldier: Dictionary = cc.get_soldier("gate_guard").duplicate(true)
	soldier["look_scale"] = 0.6
	var child := _body(soldier)
	adult._stand_on_ground()
	child._stand_on_ground()
	assert_almost_eq(_height_scale(child), _height_scale(adult) * 0.6, 0.001, "a child is 60% of the same body")


func test_stall_keeper_size_still_wins() -> void:
	var n := _body(cc.get_soldier("local_merchant"))
	n.set_look_scale(Vector3(0.9, 1.1, 0.9))
	n._stand_on_ground()
	assert_almost_eq(n.look_body.basis.get_scale(), Vector3(0.9, 1.1, 0.9), Vector3.ONE * 0.001)
