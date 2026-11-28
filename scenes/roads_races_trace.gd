extends SceneTree
## Issue #882 trace (headless, the real town scene on the red desert world): the
## roads and the races. Every town is on a road and the roads join them all to
## the port (ROADS_*); a road's lamps are two batched draws, heads and posts
## (LAMP_*); every road point is open ground with no rock on it, tunnels included
## (GROUND_*); a speeder drives every road end to end and never leaves it
## (DRIVE_*); and the first red crew's race runs to the finish with its NPC
## racers (RACE_*). Writes test_results/roads_races_trace.txt for
## tests/test_roads_races_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/roads_races_trace.gd

const OUT := "res://test_results/roads_races_trace.txt"
const DT := 1.0 / 60.0

var demo
var lines := PackedStringArray()


func _initialize() -> void:
	WorldState.reset()
	GameFlow.reset()
	GameFlow.dogfight_override = false
	GameFlow.change_scene = func(_p: String) -> void: pass
	_run()


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])
	print("  ", k, "=", v)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	await frames(2)
	WorldState.system = "red_reach"
	WorldState.counters["speeders_owned"] = 1
	WorldState.credits = 5000
	GameFlow.planet_id = "port_red"
	GameFlow.arrival = {}
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false
	demo.use_look = false
	get_root().add_child(demo)
	for i in 3000:
		if demo.race_crews.size() >= 3 and demo.roads != null:
			break
		await physics_frame
	var roads: RoadNetwork = demo.roads
	out("PLACE", str(demo.planet.get("id", "")))
	out("ROADS", roads.roads.size() if roads != null else 0)
	if roads == null:
		_write()
		return
	var sp: PlanetSphere = roads.sp
	var ground: WorldGround = demo.pilot.ground

	# Every town on a road, and every road joined up to the port.
	var places: Array = (demo.planet.cfg.settlements.places as Array).map(func(p): return str(p.id))
	var on_road := {}
	var links := {}
	var km := 0.0
	var tunnels := {}
	for r in roads.roads:
		on_road[r.from] = true
		on_road[r.to] = true
		links[r.from] = (links.get(r.from, []) as Array) + [r.to]
		links[r.to] = (links.get(r.to, []) as Array) + [r.from]
		km += float(r.length) / 1000.0
		for t in r.tunnels:
			tunnels[t] = true
	var seen := { "port": true }
	var todo := ["port"]
	while not todo.is_empty():
		var at: String = todo.pop_back()
		for n in links.get(at, []):
			if not seen.has(n):
				seen[n] = true
				todo.append(n)
	out("ROADS_TOWNS", places.filter(func(p): return on_road.has(p)).size())
	out("ROADS_JOINED", places.filter(func(p): return seen.has(p)).size())
	out("ROADS_KM", snappedf(km, 0.1))
	out("ROADS_TUNNELS", tunnels.size())

	# The lamps: two MultiMeshes a road, nothing else drawn for them.
	var heads := 0
	var posts := 0
	var lamp_draws_worst := 0
	for node in roads.get_children():
		var mm := node.get_children().filter(func(n): return n is MultiMeshInstance3D)
		lamp_draws_worst = maxi(lamp_draws_worst, mm.size())
		for n in mm:
			if n.name == "LampHeads":
				heads += (n as MultiMeshInstance3D).multimesh.instance_count
			elif n.name == "LampPosts":
				posts += (n as MultiMeshInstance3D).multimesh.instance_count
	out("LAMPS", roads.lamp_count)
	out("LAMP_HEADS", heads)
	out("LAMP_POSTS", posts)
	out("LAMP_DRAWS_PER_ROAD", lamp_draws_worst)
	var lights := 0
	for n in roads.find_children("*", "Light3D", true, false):
		lights += 1
	out("LAMP_REAL_LIGHTS", lights)
	var mats := {}
	for node in roads.get_children():
		for n in node.get_children():
			if n is MultiMeshInstance3D and n.name == "LampHeads":
				mats[(n as MultiMeshInstance3D).material_override.get_instance_id()] = true
	out("LAMP_HEAD_MATERIALS", mats.size())

	# Every road point: ground under a speeder's hover, nothing solid on it.
	var pts_n := 0
	var bad_h := 0
	var blocked := 0
	var worst_dh := 0.0
	for r in roads.roads:
		var rp: PackedVector2Array = r.pts
		for i in rp.size():
			var q := rp[i]
			var w := sp.surface_at(q.x, q.y)
			var up := ground.up_at(w)
			var hover := w + up * 1.5
			var h: float = ground.height_above(hover)
			pts_n += 1
			worst_dh = maxf(worst_dh, absf(h - 1.5))
			if absf(h - 1.5) > 1.0:
				bad_h += 1
			var what: String = ground.hit(hover, 1.2)
			if what != "":
				blocked += 1
				print("    blocked: %s point %d of %d, by %s" % [r.id, i, rp.size(), what])
	out("GROUND_POINTS", pts_n)
	out("GROUND_BAD", bad_h)
	out("GROUND_WORST_DH", snappedf(worst_dh, 0.01))
	out("GROUND_BLOCKED", blocked)

	# A speeder drives every road end to end and never leaves it.
	var cfg := HoverModel.load_config("speeder")
	var done := 0
	var worst_off := 0.0
	var reached := {}
	var drive_s := 0.0
	var wrecked := 0
	for r in roads.roads:
		var pts: PackedVector2Array = r.pts
		var route: Array = []
		var room := PackedFloat32Array()
		var half := float(demo.planet.cfg.roads.width_m) * 0.5
		for q in pts:
			route.append(sp.surface_at(q.x, q.y) + ground.up_at(sp.surface_at(q.x, q.y)) * 1.0)
			room.append(half - 1.0)
		var end: Vector3 = route[-1]
		# A track loops: carry the line a little past the road's end so its aim ahead
		# never turns back to the start as it arrives.
		var last := (pts[-1] - pts[-2]).normalized()
		for k in range(1, 5):
			var q := pts[-1] + last * 5.0 * k
			route.append(sp.surface_at(q.x, q.y) + ground.up_at(sp.surface_at(q.x, q.y)) * 1.0)
			room.append(half - 1.0)
		var m := HoverModel.new(cfg, ground)
		var f: Vector3 = route[1] - route[0]
		m.place(route[0], atan2(-f.x, -f.z))
		# Held to the road as a racer holds a track (room: the road's half width),
		# at a rider's pace, not a race's.
		var b := SpeederBrain.new(m, "racer", 3)
		b.follow_track(route, room)
		b.pace = 0.6
		var yard := false
		var t := 0.0
		var idx := 0
		var off := 0.0
		var off_at := 0
		var arrived := false
		while not arrived and t < 600.0 and m.alive():
			# The last stretch, into the town's door yard: slowed, to stop at the end.
			if not yard and idx >= pts.size() - 16:
				yard = true
				b.pace = 0.35
			if idx >= pts.size() - 2 and (m.position - end).length() < 6.0:
				arrived = true
				break
			var c := b.update(DT)
			m.set_command(float(c.throttle), float(c.steer), bool(c.boost))
			m.step(DT)
			t += DT
			var here := sp.world_to_map(m.position)
			var best := INF
			var best_k := idx
			for k in range(maxi(0, idx - 6), mini(pts.size(), idx + 40)):
				var dd := sp.ground_dist(here, pts[k])
				if dd < best:
					best = dd
					best_k = k
			idx = best_k
			# how far from the road's centre line, measured square to it (not to its points)
			var lat := best
			if best_k + 1 < pts.size():
				var seg := sp.ground_dist(pts[best_k], pts[best_k + 1])
				if seg > 0.01:
					var along := clampf(((here - pts[best_k]).dot(pts[best_k + 1] - pts[best_k])) / (pts[best_k + 1] - pts[best_k]).length_squared(), 0.0, 1.0)
					lat = sp.ground_dist(here, pts[best_k].lerp(pts[best_k + 1], along))
			if lat > off:
				off = lat
				off_at = best_k
		drive_s += t
		worst_off = maxf(worst_off, off)
		if not m.alive():
			wrecked += 1
		if arrived:
			done += 1
			reached[r.to] = true
			reached[r.from] = true
		print("    road %s: %s in %.0f s, %.1f m off at worst near point %d (got to point %d of %d)" % [r.id, "done" if arrived else "NOT done", t, off, off_at, idx, pts.size()])
	out("DRIVE_ROADS_DONE", done)
	out("DRIVE_TOWNS_REACHED", places.filter(func(p): return reached.has(p)).size())
	out("DRIVE_WORST_OFF_M", snappedf(worst_off, 0.1))
	out("DRIVE_WRECKED", wrecked)
	out("DRIVE_MIN", snappedf(drive_s / 60.0, 0.1))

	# The red crews, and the first one's race run to the finish.
	out("RACE_CREWS", demo.race_crews.size())
	out("RACE_COURSES", demo.race_courses.size())
	var crew: RaceCrew = null
	for c in demo.race_crews:
		if c.id == "scorch":
			crew = c
	out("RACE_CREW_FOUND", crew != null and crew.found)
	if crew == null:
		_write()
		return
	var tunnel_on_line := 0
	for c in demo.race_courses:
		if _tunnel_on_line(c, sp):
			tunnel_on_line += 1
	out("RACE_TUNNELS_ON_LINE", tunnel_on_line)
	var s0: Dictionary = crew.course.grid_slot(0)
	var mine := SpeederNode.new()
	mine.setup(demo, ground, {}, true, "")
	demo.add_child(mine)
	mine.place(s0.pos, float(s0.yaw))
	demo._player.global_position = (s0.pos as Vector3) + ground.up_at(s0.pos) * 0.5 + Vector3(1.5, 0, 0)
	await frames(5)
	out("RACE_MOUNTED", mine.mount())
	out("RACE_ACCEPT", crew.accept(300))
	crew.line_up()
	for i in 6000:
		if crew.phase == RaceCrew.Phase.RACING:
			break
		await physics_frame
	out("RACE_GO", crew.phase == RaceCrew.Phase.RACING)
	var me := SpeederBrain.new(mine.model, "ace")
	me.follow(crew.course.race_route(), true)
	var t0 := Time.get_ticks_msec()
	var ticks := 0
	while crew.phase == RaceCrew.Phase.RACING and ticks < 60 * 400:
		mine.set_external_command(me.update(DT))
		await physics_frame
		ticks += 1
	out("RACE_SECONDS", snappedf(ticks / 60.0, 0.1))
	out("RACE_WINNER", crew.winner)
	# The others carry on to the line after the winner: wait for them.
	for i in 60 * 120:
		if crew.results.size() >= 1 + crew.racers.size() or crew.phase == RaceCrew.Phase.IDLE:
			break
		mine.set_external_command(me.update(DT))
		await physics_frame
	out("RACE_FINISHERS", crew.results.size())
	out("RACE_NPC_FINISHERS", crew.results.filter(func(k): return str(k) != RaceCrew.YOU).size())
	out("RACE_OUT", crew.player_out)
	out("RACE_WALL_S", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1))
	_write()


## The course's tunnel leg: two of its gates lie on a tunnel range's centre line,
## carried on past its portals (the leg between them is the tunnel).
func _tunnel_on_line(c: RaceCourse, sp: PlanetSphere) -> bool:
	var data := DesertLandforms.load_for(demo.planet)
	for e in data.get("course_mountains", []):
		if not e.has("path_ll"):
			continue
		var a := sp.map_from_lat_lon(float(e.path_ll[0][0]), float(e.path_ll[0][1]))
		var b := sp.map_from_lat_lon(float(e.path_ll[-1][0]), float(e.path_ll[-1][1]))
		var hits := 0
		for g in c.course.gates:
			var q := Vector2(float(g.at[0]), float(g.at[1]))
			var s := (q - a).dot(b - a) / (b - a).length_squared()
			if s < -0.3 or s > 1.3:
				continue
			var on := RaceCourse.ground_lerp(a, b, RaceCourse.ground_dist(a, q, sp.radius) / RaceCourse.ground_dist(a, b, sp.radius) * (1.0 if s >= 0.0 else -1.0), sp.radius)
			if sp.ground_dist(q, on) < 3.0:
				hits += 1
		if hits >= 2:
			return true
	return false


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
