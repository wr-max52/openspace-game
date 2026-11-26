extends GutTest
## Issue #698: getting out of a ship puts you on the ground beside it, never up on
## something next to it. In the round pit (greybox: the colliders are the same),
## out of the pit's ship where the flight trace lands it (6 m off the pad, where
## the first exit spot used to be 1.3 m up), and out of every ship T-89 sells on
## the spare pad.

const TownDemo := preload("res://scenes/town_demo.gd")
const PIT_FLOOR := -6.0

var t


func before_each() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")
	ShipSalesman.greeted = false
	t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	t.with_npcs = false
	add_child_autofree(t)
	await wait_physics_frames(10)


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Board berth i from beside it, get out, and return the player's height.
func _out_of(i: int) -> float:
	var pilot: ShipPilot = t.pilot
	var v: Node3D = pilot.berths[i].visual
	var c: float = pilot.berths[i].clearance
	t._player.global_position = Vector3(v.global_position.x + 3.0, v.global_position.y - c, v.global_position.z)
	t._player.controller.body_pos = t._player.global_position
	await wait_physics_frames(3)
	assert_eq(pilot.nearest_berth(), i)
	assert_true(pilot.board())
	await wait_physics_frames(2)
	return await _exit()


func _exit() -> float:
	assert_true(t.pilot.exit_ship())
	await wait_physics_frames(30)
	assert_true(t._player.is_on_floor())
	return t._player.global_position.y


func test_out_of_the_pit_ship_landed_off_the_pad() -> void:
	var pilot: ShipPilot = t.pilot
	t._player.global_position = t.town.spawn_pos()
	await wait_physics_frames(2)
	assert_true(pilot.board())
	await wait_physics_frames(2)
	# Where the m14 flight trace sets her down, nose to the north-east.
	pilot.atmo.park(Vector3(19.16366, -5.0, 7.602868), -0.988895)
	await wait_physics_frames(2)
	var y := await _exit()
	assert_almost_eq(y, PIT_FLOOR, 0.3, "on the pit floor, not up beside the ship")


func test_out_of_every_ship_on_its_pad() -> void:
	var y := await _out_of(0)
	assert_almost_eq(y, PIT_FLOOR, 0.3, "the pit's own ship")
	var s: ShipSalesman = t.salesman
	WorldState.credits = 1000000
	for id in s.stock():
		assert_eq(s.buy(id), "bought")
		await wait_physics_frames(3)
		y = await _out_of(t.pilot.berths.size() - 1)
		assert_almost_eq(y, PIT_FLOOR, 0.3, "%s on the spare pad" % id)
		s.sell()
		await wait_physics_frames(3)
