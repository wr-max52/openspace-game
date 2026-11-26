extends GutTest
## Issue #700: the planet's beast walks the sand, never onto a rock, turns away from
## what is ahead of it (WorldGround.hit, a few times a second), and a chase gives up
## at the town wall.

const TownDemo := preload("res://scenes/town_demo.gd")
const DT := 0.1


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	for i in 900:
		if t.beast != null:
			break
		await wait_physics_frames(1)
	return t


## Two game hours of wandering, stepped by hand: its head is never up on a rock,
## and neither its head nor its body ever ends up inside a box, boulder or column.
func test_two_hours_of_wandering_stay_on_the_sand_and_out_of_things() -> void:
	var t = await _town()
	var b: PlanetBeast = t.beast
	assert_not_null(b, "the planet has its beast")
	if b == null:
		return
	b.set_physics_process(false)
	var g: WorldGround = b.ground
	var sp := g.sphere()
	var onto := 0
	var into := {}
	var worst := 0.0
	for i in int(7200.0 / DT):
		b._wander(DT)
		var up := b._up(b._head_ground)
		var over := sp.height_above_ground(b._head_ground + up * 2.0) - 2.0 if sp != null else b._head_ground.y
		worst = maxf(worst, over)
		if over > 0.3:
			onto += 1
		if i % 5 == 0:
			b._pose()
			var hit := g.hit(b.global_position, b.radius * 0.8)
			if hit != "":
				into[hit] = int(into.get(hit, 0)) + 1
			for s in b.segments:
				var sh := g.hit((s.node as Node3D).global_position, float(s.r) * 0.8)
				if sh != "":
					into[sh] = int(into.get(sh, 0)) + 1
	assert_gt(b.travelled, 2000.0, "it wandered")
	assert_gt(int(b.get("avoids") if b.get("avoids") != null else 0), 0, "it turned away from something ahead")
	assert_eq(onto, 0, "its head never stood up on a rock (worst %.2f m over the sand)" % worst)
	assert_eq(into.size(), 0, "never inside a box, boulder or column: %s" % [into])


## Hurt it and run home: it chases you to the town wall and gives up there.
func test_a_chase_toward_town_ends_outside_the_wall() -> void:
	var t = await _town()
	var b: PlanetBeast = t.beast
	if b == null:
		return
	b.set_physics_process(false)
	var sp := b.ground.sphere()
	assert_not_null(sp, "the home planet is a ball")
	var walls: Rect2 = sp.under_rect
	assert_true(walls.has_area(), "the town has its walls")
	var mid := walls.get_center()
	var start := Vector2(walls.end.x + 160.0, mid.y)
	b.home = b._ground_at(sp.surface_at(start.x, start.y))
	b.heading = b._flat(sp.surface_at(mid.x, mid.y) - b.home, b.home).normalized()
	b._seed_trail()
	b._place(b.home)
	var p: Node3D = t._player
	p.global_position = sp.surface_at(mid.x, mid.y) + b._up(b.home) * 1.0
	b.chasing = true
	var inside := 0
	var closest := INF
	for i in int(90.0 / DT):
		p.global_position = sp.surface_at(mid.x, mid.y) + b._up(b.home) * 1.0
		b._wander(DT)
		var m := sp.world_to_map(b._head_ground)
		if walls.has_point(m):
			inside += 1
		closest = minf(closest, absf(m.x - walls.end.x))
	assert_false(b.chasing, "it gave up")
	assert_eq(inside, 0, "it never got inside the walls (closest %.0f m from the wall)" % closest)
