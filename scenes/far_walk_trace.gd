extends SceneTree
## Issue #802: walking on the far side of the ball (headless, real physics). The
## player sprints 60 m in a straight line in five places: open sand by the port
## (the trace's own control), across Saltpan's yard and out of its gate (3.5 km
## round), the same line through Cragfall's yard (12.7 km round) and Farleap's
## (13.9 km round), and over open far-side sand with no village. Counts the ticks
## off the floor, the ticks they barely moved (a snag), the speed actually made
## against the sprint asked for, and how often the floor under them changed
## collider; then where the Cragfall troopers stand. Writes
## test_results/far_walk_trace.txt (key=value) for tests/test_far_walk.gut.gd.
##
## Before the fix the far walks snagged nearly every tick (0.4 to 3 m/s of the 7
## asked): Godot's own physics loses its contacts that far from the world origin.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/far_walk_trace.gd

const OUT := "res://test_results/far_walk_trace.txt"
const WALK_M := 60.0
## The yard line, in a ranch village's own frame (+x out of the gate): from the
## stalls, between the gate posts and 40 m out onto the sand. All the ranch
## villages share the yard layout.
const YARD_FROM := Vector3(12, 0, -2)
const YARD_TO := Vector3(72, 0, -2)
## Open sand as far round as Cragfall, half way between it and Farleap.
const OPEN_SAND := Vector2(-12700.0, 0.0)

var demo
var player
var terrain: PlanetTerrain
var sp: PlanetSphere
var lines := PackedStringArray()


func _initialize() -> void:
	WorldState.reset()
	GameFlow.resumed = true
	GameFlow.planet_id = ""       # the home planet, whatever a save says
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false       # everyone holds still
	demo.with_npcs = true         # the outposts (and their ground) come with the NPCs
	demo.use_look = false         # greybox: the colliders are the same
	get_root().add_child(demo)
	_run()


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	await frames(10)
	player = demo._player
	terrain = demo.terrain as PlanetTerrain
	out("TERRAIN", terrain != null)
	if terrain == null or terrain.sphere == null:
		_write()
		return
	sp = terrain.sphere
	var wait := 0
	while demo.outposts == null and wait < 1800:   # the build plan makes them a while in
		await physics_frame
		wait += 1
	demo.settle_now()              # every outpost and its ground, not only the ones in sight
	await frames(5)
	out("OUTPOSTS", demo.outposts.outposts.size() if demo.outposts != null else -1)
	await open_sand("NEAR", Vector2(0.0, -600.0))
	await yard("SALTPAN", "remnant_outpost_saltpan")
	await yard("CRAGFALL", "remnant_outpost_cragfall")
	out("CRAGFALL_GUARDS_OFF_GROUND", snappedf(_guards_off_ground("remnant_outpost_cragfall"), 0.01))
	out("CRAGFALL_GUARDS_ON_FLOOR", _guards_on_floor("remnant_outpost_cragfall"))
	await yard("FARLEAP", "remnant_outpost_farleap")
	await open_sand("OPEN", OPEN_SAND)
	_write()


func yard(key: String, id: String) -> void:
	var o: Dictionary = demo.outposts.outpost(id) if demo.outposts != null else {}
	out(key + "_FOUND", not o.is_empty())
	if o.is_empty():
		return
	out(key + "_OUTPOST_GROUND", demo.outposts.get_node_or_null("Ground_" + id) != null)
	var xf: Transform3D = o.xf
	await walk(key, _on_ground(xf * YARD_FROM), _on_ground(xf * YARD_TO))


## 60 m over open sand from map point `m`, along the ground's own x there.
func open_sand(key: String, m: Vector2) -> void:
	var a := sp.surface_at(m.x, m.y)
	await walk(key, a, _on_ground(a + sp.tilt_at(a).x * WALK_M))


func _on_ground(p: Vector3) -> Vector3:
	var m := sp.world_to_map(p)
	return sp.surface_at(m.x, m.y)


## Stand at `a` (on the ground), let the near ground build round them, then sprint
## straight for `b`.
func walk(key: String, a: Vector3, b: Vector3) -> void:
	out(key + "_KM_FROM_ORIGIN", snappedf(a.length() / 1000.0, 0.01))
	out(key + "_KM_ROUND", snappedf(sp.ground_dist(Vector2.ZERO, sp.world_to_map(a)) / 1000.0, 0.01))
	player.set_command(Vector2.ZERO, false, false, false)
	player.global_position = a + sp.up_at(a) * 0.05
	player.align_to_ground()
	terrain.snap_to(player.global_position)
	var wait := 0
	while (terrain.is_rebuilding() or not player.is_on_floor()) and wait < 900:
		await physics_frame
		wait += 1
	await frames(20)
	out(key + "_SETTLED", player.is_on_floor())
	var dt := 1.0 / Engine.physics_ticks_per_second
	var asked: float = player.controller.sprint_speed
	var air := 0
	var stalls := 0               # ticks on the floor that made under half the sprint
	var floor_swaps := 0          # the floor's collider changed under them
	var last_floor: Object = null
	var moved := 0.0
	var ticks := 0
	var reached := false
	var prev: Vector3 = player.global_position
	for i in 1200:
		var p: Vector3 = player.global_position
		var up := sp.up_at(p)
		var to := b - p
		to -= up * to.dot(up)
		if to.length() <= 1.0:
			reached = true
			break
		player.rotation.y = 0.0
		var l: Vector3 = player.tilt.inverse() * to
		player.set_command(Vector2(l.x, l.z).normalized(), true, false, false)
		await physics_frame
		ticks += 1
		var q: Vector3 = player.global_position
		var step := q - prev
		step -= up * step.dot(up)
		prev = q
		moved += step.length()
		if not player.is_on_floor():
			air += 1
			continue
		if ticks > 15 and step.length() < asked * dt * 0.5:
			stalls += 1
		var f := _floor_collider()
		if f != null:
			if last_floor != null and f != last_floor:
				floor_swaps += 1
			last_floor = f
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(2)
	out(key + "_REACHED", reached)
	out(key + "_TICKS", ticks)
	out(key + "_AIR_FRAMES", air)
	out(key + "_STALLS", stalls)
	out(key + "_FLOOR_SWAPS", floor_swaps)
	out(key + "_SPEED", snappedf(moved / maxf(ticks * dt, 0.001), 0.01))
	out(key + "_ASKED", asked)
	var pe: Vector3 = player.global_position
	out(key + "_RISE", snappedf((pe - sp.center).length() - (a - sp.center).length(), 0.01))


## The collider under the player's feet this tick (null if none reported).
func _floor_collider() -> Object:
	for i in player.get_slide_collision_count():
		var c: KinematicCollision3D = player.get_slide_collision(i)
		if c.get_normal().dot(player.up_direction) > 0.7:
			return c.get_collider()
	return null


## The furthest any of outpost `id`'s troopers stands off the sand (either way).
func _guards_off_ground(id: String) -> float:
	var worst := -1.0
	for g in demo.outposts.guards + demo.outposts.held_by:
		if is_instance_valid(g) and str(g.get_meta("outpost", "")) == id:
			worst = maxf(worst, absf(sp.height_above_ground(g.global_position)))
	return worst


## "n/m": how many of outpost `id`'s troopers stand on a floor, of how many.
func _guards_on_floor(id: String) -> String:
	var n := 0
	var m := 0
	for g in demo.outposts.guards + demo.outposts.held_by:
		if is_instance_valid(g) and str(g.get_meta("outpost", "")) == id:
			m += 1
			if g.is_on_floor():
				n += 1
	return "%d/%d" % [n, m]


func _write() -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("FARWALK wrote ", OUT, " (", lines.size(), " lines)")
	quit()
