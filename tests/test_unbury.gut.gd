extends GutTest
## Stuck inside a floor after a hard move (a save from under the pit's half metre
## floor, out of a ship that had sunk through it): the next tick stands you on top
## of that floor. Standing on a floor, or under a roof with room, nothing moves.

const CharacterBody := preload("res://src/systems/player/character_body.gd")


## A half metre slab with its top at y 0, and sand two metres under it.
func _slab_and_sand() -> void:
	for spec in [[Vector3(0, -0.25, 0), 0.5], [Vector3(0, -2.5, 0), 1.0]]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(40, spec[1], 40)
		cs.shape = box
		body.add_child(cs)
		body.position = spec[0]
		add_child_autofree(body)


func _player(at: Vector3) -> CharacterBody3D:
	var p := CharacterBody.new()
	p.position = at
	add_child_autofree(p)
	p.set_command(Vector2.ZERO, false, false, false)
	return p


func test_a_hard_move_under_a_floor_stands_you_on_it() -> void:
	_slab_and_sand()
	var p := _player(Vector3(0, 5, 0))
	await wait_physics_frames(3)
	p.global_position = Vector3(3, -2.0, 3)      # on the sand, the slab through your chest
	p.align_to_ground(true)
	await wait_physics_frames(6)
	assert_almost_eq(p.global_position.y, 0.0, 0.05, "on top of the floor")
	assert_true(p.is_on_floor())


func test_standing_on_the_floor_nothing_moves() -> void:
	_slab_and_sand()
	var p := _player(Vector3(0, 0.05, 0))
	await wait_physics_frames(6)
	assert_false(p.unbury(), "standing on it is not inside it")
	assert_almost_eq(p.global_position.y, 0.0, 0.05)


func test_under_a_roof_with_room_nothing_moves() -> void:
	_slab_and_sand()
	var roof := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 0.3, 10)
	cs.shape = box
	roof.add_child(cs)
	roof.position = Vector3(0, 2.2, 0)              # a low roof, room under it
	add_child_autofree(roof)
	var p := _player(Vector3(0, 0.05, 0))
	await wait_physics_frames(3)
	p.align_to_ground(true)
	await wait_physics_frames(3)
	assert_almost_eq(p.global_position.y, 0.0, 0.05, "not onto the roof")
