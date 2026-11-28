extends SceneTree
## Issue #877 trace (headless, real physics, the real town scene on the red
## desert world): the mountain towns. Every place stands on its peak (PLACES_*),
## the people are there (PEOPLE_*), the lift carries you from the sand to the top
## (LIFT_*), you can stand on its bridge and walk into the town (TOP_*), the road
## up Sootwell's peak is ground the whole way with nothing in a speeder's way
## (ROAD_*), and the town costs no more frame than the port's street (FRAME_*).
## Writes test_results/mountain_towns_trace.txt for tests/test_mountain_towns_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/mountain_towns_trace.gd

const OUT := "res://test_results/mountain_towns_trace.txt"

var demo
var lines := PackedStringArray()
var _last := 0
var _worst := 0.0
var _measuring := false


func _initialize() -> void:
	WorldState.reset()
	GameFlow.reset()
	GameFlow.dogfight_override = false
	GameFlow.change_scene = func(_p: String) -> void: pass
	_run()


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _measuring and _last > 0:
		_worst = maxf(_worst, (now - _last) / 1000.0)
	_last = now
	return false


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])
	print("  ", k, "=", v)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func worst_over(n: int, settle := 60) -> float:
	await frames(settle)
	_worst = 0.0
	_last = 0
	_measuring = true
	await frames(n)
	_measuring = false
	return snappedf(_worst, 0.01)


func place(p: Vector3) -> void:
	var pl = demo._player
	pl.global_position = p
	pl.velocity = Vector3.ZERO
	if "controller" in pl and pl.controller != null:
		pl.controller.velocity = Vector3.ZERO
		pl.controller.body_pos = p


func _run() -> void:
	await frames(2)
	WorldState.system = "red_reach"
	GameFlow.planet_id = "port_red"
	GameFlow.arrival = {}
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = true                       # each town's own folk (their Townsfolk)
	demo.use_look = false
	get_root().add_child(demo)
	await frames(40)
	var st = demo.settlements
	out("PLACE", str(demo.planet.get("id", "")))
	out("PLACES", st.places.size() if st != null else 0)
	if st == null:
		_write()
		return
	st.build()                                   # everything, as if every peak were in sight
	await frames(30)
	out("PLACES_BUILT", st.places.filter(func(s): return s.has("root")).size())
	out("PEOPLE", st.people.size())
	out("VENDORS", st.vendors.size())
	out("LIFTS", st.lifts.size())
	st.start_brains()                            # the places built after the town's brains step
	out("FOLKS", st.folks.size())
	var walkers := 0
	for f in st.folks.values():
		for g in f.brains:
			if (f.brains[g].patrol_points as Array).size() >= 2:
				walkers += 1
	out("FOLKS_WALKERS", walkers)
	var gear = demo.get("gear")
	out("VENDORS_GIVEN", gear.vendors.filter(func(v): return str(v.cfg.get("marker", "")).contains("/") and st.place_by_id(str(v.cfg.marker).get_slice("/", 0)).size() > 0).size() if gear != null else 0)
	var sp: PlanetSphere = PlanetSphere.current
	var pl = demo._player
	out("FRAME_STREET_MS", await worst_over(120))

	# The lift at the Pilgrims' Rest: on at the sand, off at the top.
	var s: Dictionary = st.place_by_id("pilgrims_rest")
	var lift: Lift = s.get("lift_node")
	var rock: Transform3D = s.rock
	var up := rock.basis.y.normalized()
	out("LIFT_CLIMB_M", snappedf(float(s.lift.top) - float(s.lift.bottom), 0.1))
	place(rock * Vector3(lift.at.x, float(s.lift.bottom) + 1.2, 0.0))
	var t := 0
	while t < 60 * 30 and not (lift.i == 1 and not lift.moving):
		await physics_frame
		t += 1
	await frames(20)
	var lp: Vector3 = rock.affine_inverse() * pl.global_position
	out("LIFT_SECONDS", snappedf(t / 60.0, 0.1))
	out("LIFT_AT_TOP", lift.i == 1)
	out("LIFT_RIDES", lift.rides)
	out("LIFT_PLAYER_DY", snappedf(lp.y - float(s.lift.top), 0.01))
	out("LIFT_ON_FLOOR", pl.is_on_floor())

	# Off onto the bridge, then in at the town's gate.
	var deck: Array = s.lift.deck
	place(rock * Vector3((float(deck[0]) + float(deck[1])) * 0.5, float(s.height) + 1.0, 0.0))
	await frames(60)
	lp = rock.affine_inverse() * pl.global_position
	out("TOP_BRIDGE_ON_FLOOR", pl.is_on_floor())
	out("TOP_BRIDGE_DY", snappedf(lp.y - float(s.height), 0.01))
	var gate: Vector3 = Settlements.marker_point(s, "gate")
	place(gate + up * 1.0)
	await frames(60)
	out("TOP_GATE_ON_FLOOR", pl.is_on_floor())
	out("TOP_GATE_HEIGHT", snappedf(demo.pilot.ground.height_above(pl.global_position), 0.01))
	out("FRAME_TOWN_MS", await worst_over(120))

	# The road up Sootwell's peak: ground all the way, nothing in a speeder's way.
	var so: Dictionary = st.place_by_id("sootwell")
	var road: Dictionary = so.get("ramp", {})
	var srock: Transform3D = so.rock
	var sup := srock.basis.y.normalized()
	var path: Array = road.get("path", [])
	var pts: Array = []
	for i in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var n := maxi(1, int(a.distance_to(b) / 2.0))
		for k in n:
			pts.append(a.lerp(b, float(k) / float(n)))
	pts.append(path[-1])
	var bad_h := 0
	var bad_hit := 0
	var bad_ray := 0
	var worst := 0.0
	var space: PhysicsDirectSpaceState3D = demo.get_world_3d().direct_space_state
	for q in pts:
		var w: Vector3 = srock * q
		var hover := w + sup * 1.5
		var h: float = demo.pilot.ground.height_above(hover)
		worst = maxf(worst, absf(h - 1.5))
		if absf(h - 1.5) > 0.6:
			bad_h += 1
		if demo.pilot.ground.hit(hover, 1.2) != "":
			bad_hit += 1
		var ray := PhysicsRayQueryParameters3D.create(w + sup * 3.0, w - sup * 3.0)
		var hit: Dictionary = space.intersect_ray(ray)
		if hit.is_empty() or absf((hit.position - w).dot(sup)) > 0.7:
			bad_ray += 1
	out("ROAD_POINTS", pts.size())
	out("ROAD_CLIMB_M", snappedf(float(so.height) - float(road.get("y0", 0.0)), 0.1))
	out("ROAD_LEN_M", snappedf(float(road.get("radius", 0.0)) * -float(road.get("start_angle", 0.0)), 1.0))
	out("ROAD_BAD_GROUND", bad_h)
	out("ROAD_WORST_DH", snappedf(worst, 0.01))
	out("ROAD_BLOCKED", bad_hit)
	out("ROAD_BAD_COLLIDER", bad_ray)
	# Its top end runs into the town's gate.
	var sg: Vector3 = srock.affine_inverse() * Settlements.marker_point(so, "gate")
	out("ROAD_END_TO_GATE_M", snappedf(Vector2(sg.x, sg.z).distance_to(Vector2((path[-1] as Vector3).x, (path[-1] as Vector3).z)), 0.1))
	out("ROAD_START_SAND_DY", snappedf(float(road.y0) - float(st._sand_y(so, path[0])), 0.01))
	_write()


func _write() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	demo.queue_free()
	demo = null
	await frames(3)
	GameFlow.reset()
	quit()
