extends GutTest
## Issue #697: an NPC's capsule (its hitbox, and what walks) takes the body's
## size: height with the look's height, radius with its width, crouching too.
## The player's stays 1.8 m by 0.4 m. Set before the body is in the tree, so it
## is the same with the look on or off.

const CharacterBodyT := preload("res://src/systems/player/character_body.gd")


func _npc(soldier: Dictionary) -> NpcBody:
	var npc := NpcBody.new()
	npc.setup(soldier, Vector3.ZERO, 0.0, null)
	add_child_autofree(npc)
	return npc


func _cap(body: CharacterBody3D) -> CapsuleShape3D:
	for c in body.get_children():
		if c is CollisionShape3D and c.shape is CapsuleShape3D:
			return c.shape
	return null


func test_a_trooper_is_taller_and_wider_than_a_local() -> void:
	var trooper := _cap(_npc({ "archetype": "remnant_trooper" }))
	var local := _cap(_npc({ "archetype": "local" }))
	assert_gt(trooper.height, local.height, "the trooper's hitbox is taller")
	assert_gt(trooper.radius, local.radius, "and wider")
	var s := CharacterKit.size_of("remnant_trooper")
	assert_almost_eq(trooper.height, 1.8 * s.y, 0.001, "height with the look's height")
	assert_almost_eq(trooper.radius, 0.4 * s.x, 0.001, "radius with the look's width")


func test_a_pack_child_is_sixty_percent_of_an_adult() -> void:
	var adult := _cap(_npc({ "archetype": "desert_nomad" }))
	var child := _cap(_npc({ "archetype": "desert_nomad", "look_scale": 0.6 }))
	assert_almost_eq(child.height / adult.height, 0.6, 0.001)
	assert_almost_eq(child.radius / adult.radius, 0.6, 0.001)


func test_a_variant_takes_its_base_bulk() -> void:
	var s := CharacterKit.size_of("dark_master")
	assert_almost_eq(s.y, 2.16 / 1.8, 0.001, "its own height")
	assert_almost_eq(s.x, s.y * 1.1, 0.001, "its own bulk")
	var dancer := CharacterKit.size_of("cantina_dancer")
	assert_almost_eq(dancer.x, dancer.y, 0.001, "no bulk of its own: the base's 1.0")


func test_crouching_scales_the_same_way() -> void:
	var npc := _npc({ "archetype": "remnant_trooper" })
	var s := CharacterKit.size_of("remnant_trooper")
	assert_almost_eq(npc.controller.crouch_height, 1.0 * s.y, 0.001)
	npc._set_crouch_shape(true)
	assert_almost_eq(_cap(npc).height, 1.0 * s.y + 0.05, 0.001, "the crouched capsule is his size too")


func test_the_player_capsule_is_unchanged() -> void:
	var p := CharacterBodyT.new()
	add_child_autofree(p)
	assert_almost_eq(_cap(p).height, 1.8, 0.001)
	assert_almost_eq(_cap(p).radius, 0.4, 0.001)
	assert_almost_eq(p.controller.crouch_height, 1.0, 0.001)


func test_the_tallest_body_fits_the_barracks_doors() -> void:
	var tallest := 0.0
	var widest := 0.0
	for a in ["remnant_trooper", "remnant_commander", "remnant_marked", "dark_master"]:
		var s := CharacterKit.size_of(a)
		tallest = maxf(tallest, 1.8 * s.y)
		widest = maxf(widest, 0.8 * s.x)
	var inner := BarracksHall.gap(BarracksHall.n("inner_door_scale", 1.4))
	assert_lt(tallest, inner.y, "under the office and bunk room doors")
	assert_lt(widest, inner.x, "and through them")
