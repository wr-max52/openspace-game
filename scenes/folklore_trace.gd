extends SceneTree
## Issue #878 trace (headless, the real town scene on the red desert world): the
## red world's folklore and its worm. Dool'rey Kah is built from the planet's
## data as a worm (WORM_*: about twice the beetle's segments, no legs, rings of
## teeth, the same eyes), out on the open dunes far from the mountain country and
## its roads; it rolls along with its body following and rolling in and out of
## the sand, and touching it kills (TOUCH_*). The Pilgrims' Rest's storyteller
## sits in its cantina as an AI character, and asked about the worm, even with no
## model, names it (TELLER_*); each town's locals mutter their own lines
## (LOCALS_*); every AI character is briefed on it (BRIEF_*).
## Writes test_results/folklore_trace.txt for tests/test_folklore_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/folklore_trace.gd

const OUT := "res://test_results/folklore_trace.txt"

var demo
var player
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


func _put_player(at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	if "controller" in player and player.controller != null:
		player.controller.velocity = Vector3.ZERO
		player.controller.body_pos = at


func _run() -> void:
	await frames(2)
	WorldState.system = "red_reach"
	GameFlow.planet_id = "port_red"
	GameFlow.arrival = {}
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = true                     # each town's own folk (their Townsfolk)
	demo.use_look = false
	get_root().add_child(demo)
	for i in 3000:
		if demo.beast != null and demo.settlements != null:
			break
		await physics_frame
	player = demo._player
	var beast = demo.beast
	out("PLACE", str(demo.planet.get("id", "")))
	out("WORM_BUILT", beast != null)
	if beast == null:
		_write()
		return
	var sp: PlanetSphere = PlanetSphere.current

	# ---------------------------------------------------------------- the worm
	out("WORM_NAME", beast.beast_name)
	out("WORM_KIND", str(beast.cfg.get("kind", "")))
	out("WORM_IS_WORM", beast.is_worm())
	out("WORM_SEGMENTS", beast.segments.size())
	out("WORM_BEETLE_SEGMENTS", int(PlanetBeast.defaults().get("segments", 14)))
	out("WORM_LEGS", beast.leg_count())
	out("WORM_MANDIBLES", beast._mandibles.size())
	out("WORM_ANTENNAE", beast._antennae.size())
	out("WORM_TEETH", beast.tooth_count())
	var eyes := 0
	for n in beast._ball.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).material_override == beast._eye_mat:
			eyes += 1
	out("WORM_EYES", eyes)
	var balls := 0
	for s in beast.segments:
		for n in (s.node as Node3D).get_children():
			if n is MeshInstance3D and not ((n as MeshInstance3D).mesh is CylinderMesh):
				balls += 1
	out("WORM_BODY_BALLS", balls)
	# Out on the open dunes: the far side from the mountain country (longitude
	# past 90 either way), far from every town, every road and every pocket.
	var hm := Vector2(float(beast.cfg.home[0]), float(beast.cfg.home[1]))
	var hd: Vector3 = sp.map_dir(hm.x, hm.y)
	out("WORM_HOME_LON_DEG", snappedf(rad_to_deg(atan2(hd.x, -hd.z)), 0.1))
	out("WORM_HOME_FROM_PORT_M", int(sp.ground_dist(Vector2.ZERO, hm)))
	var near_peak := INF
	for c in demo.planet.cfg.landforms.mountain_clusters:
		near_peak = minf(near_peak, sp.ground_dist(hm, sp.map_from_lat_lon(float(c.lat), float(c.lon))))
	for c in demo.planet.cfg.landforms.get("course_mountains", []):
		if c.has("lat"):
			near_peak = minf(near_peak, sp.ground_dist(hm, sp.map_from_lat_lon(float(c.lat), float(c.lon))))
	out("WORM_HOME_TO_MOUNTAINS_M", int(near_peak))
	var near_town := INF
	for p in demo.planet.cfg.settlements.places:
		near_town = minf(near_town, sp.ground_dist(hm, sp.map_from_lat_lon(float(p.lat), float(p.lon))))
	out("WORM_HOME_TO_TOWN_M", int(near_town))
	var near_road := INF
	if demo.roads != null:
		for r in demo.roads.roads:
			for q in r.pts:
				near_road = minf(near_road, sp.ground_dist(hm, q))
	out("WORM_HOME_TO_ROAD_M", int(near_road))
	out("WORM_LEASH_M", float(beast.cfg.get("leash_m", 0.0)))

	# It rolls along, its body following, rolling in and out of the sand.
	var p0: Vector3 = beast.global_position
	var tail0: Vector3 = beast.segments[-1].node.global_position
	var lift_lo := INF
	var lift_hi := -INF
	for i in 60 * 6:
		await physics_frame
		var s = beast.segments[beast.segments.size() / 2]
		var g: Vector3 = beast._ground_at(s.node.global_position)
		var h: float = s.node.global_position.distance_to(g) - float(s.r)
		lift_lo = minf(lift_lo, h)
		lift_hi = maxf(lift_hi, h)
	out("WORM_ROLLED_M", snappedf(beast.travelled, 0.1))
	out("WORM_MOVED", beast.global_position.distance_to(p0) > 2.0)
	out("WORM_BODY_FOLLOWS", beast.segments[-1].node.global_position.distance_to(tail0) > 2.0)
	out("WORM_ROLL_M", snappedf(lift_hi - lift_lo, 0.01))
	var lo := PlanetSphere.current.world_to_map(beast.global_position)
	out("WORM_ON_DUNES", sp.ground_dist(lo, hm) < float(beast.cfg.get("leash_m", 1200.0)) + 200.0)

	# ---------------------------------------------------------------- touch = death
	var up: Vector3 = beast._up(beast.global_position)
	var side: Vector3 = up.cross(beast.heading).normalized()
	var mid = beast.segments[beast.segments.size() / 2]
	var k0: int = beast.kills
	_put_player(beast._ground_at(mid.node.global_position + side * float(mid.r) * 0.6))
	var died := false
	for i in 30:
		await physics_frame
		if player.is_downed:
			died = true
			break
	out("TOUCH_KILLS", died and beast.kills > k0)
	out("TOUCH_LINE", beast.line("killed"))
	_put_player(demo.town.spawn_pos())
	player.revive(0.0)
	await frames(10)

	# ---------------------------------------------------------------- briefed on it
	var brief: String = PlanetBeast.brief(demo.planet)
	out("BRIEF_NAMES_IT", brief.contains("Dool'rey Kah"))
	out("BRIEF_A_WORM", brief.contains("worm") and not brief.contains("beetle"))

	# ---------------------------------------------------------------- the storyteller
	var st = demo.settlements
	if demo.bar == null:
		demo._build_bar()                        # the talk host (built with the look; headless here)
		await frames(2)
	st.build()
	await frames(30)
	st.start_brains()
	await frames(5)
	out("TELLER_COUNT", st.storytellers.size())
	var spot: TalkSpot = st.storytellers[0] if not st.storytellers.is_empty() else null
	if spot != null:
		var body: NpcBody = spot.body
		var s: Dictionary = st.place_by_id("pilgrims_rest")
		out("TELLER_NAME", spot.display_name())
		out("TELLER_BODY_NAME", body.display_name)
		out("TELLER_PLACE", str(body.get_meta("ranch", "")))
		out("TELLER_POST", body.post_id)
		out("TELLER_SOLDIER", str(body.profile.get("id", "")))
		var zone := {}
		for z in s.lay.zones:
			if str(z.id) == "cantina":
				zone = z
		var local: Vector3 = (s.xf as Transform3D).affine_inverse() * body.global_position
		out("TELLER_IN_CANTINA", not zone.is_empty() and local.x >= float(zone.min[0]) and local.x <= float(zone.max[0])
			and local.z >= float(zone.min[1]) and local.z <= float(zone.max[1]))
		out("TELLER_ON_HOST", demo.bar != null and demo.bar.spots.has(spot))
		var gear = demo.get("gear")
		var clear := true
		if gear != null:
			for v in gear.vendors:
				if (v.pos as Vector3).distance_to(body.global_position) <= float(v.cfg.get("reach", 3.5)) + spot.radius:
					clear = false
		out("TELLER_CLEAR_OF_TRADE", clear)
		_put_player(body.global_position + body.global_basis.z * 1.2)
		await frames(3)
		out("TELLER_IN_RANGE", spot.in_range(player))
		var b: NpcBrain = spot.brain
		out("TELLER_TOPICS", ",".join(PackedStringArray(b.topics().map(func(t): return str(t.id)))))
		var r: Dictionary = b.canned_reply("What do you know about the worm?")
		out("TELLER_WORM_REPLY", str(r.get("say", "")))
		out("TELLER_WORM_NAMES_IT", str(r.get("say", "")).contains("Dool'rey Kah"))
		out("TELLER_GHOST_REPLY", str(b.canned_reply("Any ghosts round here?").get("say", "")))
		out("TELLER_CURSE_REPLY", str(b.canned_reply("Is the mine cursed?").get("say", "")))
		# A whole turn with no model: say it, and hear the canned answer.
		var heard := [""]
		b.line_done.connect(func(turn): heard[0] = str(turn.get("say", "")))
		b.say("Tell me about the beast in the sand.")
		for i in 30:
			if heard[0] != "":
				break
			await physics_frame
		out("TELLER_SAID", heard[0])
		out("TELLER_SAID_NAMES_IT", heard[0].contains("Dool'rey Kah"))

	# ---------------------------------------------------------------- each town's own lines
	var keys := {}
	var own_said := 0
	var towns := 0
	for id in ["pilgrims_rest", "sootwell", "highfold"]:
		var f = st.folks.get(id, null)
		if f == null:
			continue
		towns += 1
		keys[id] = f.lore_key
		var own: Array = demo.planet.cfg.beast.locals_say.get(f.lore_key, [])
		var alive: Array = f.members.filter(func(g): return is_instance_valid(g) and not g.dead)
		if alive.is_empty():
			continue
		var heard_own := false
		for attempt in 40:
			f._beast_next = 0.0
			f.beast_said.clear()
			var g = alive[attempt % alive.size()]
			_put_player(g.global_position + g.global_basis.z * 1.5)
			await frames(2)
			if not f.beast_said.is_empty() and own.has(f.beast_said[0]):
				heard_own = true
				break
		if heard_own:
			own_said += 1
	out("LOCALS_TOWNS", towns)
	out("LOCALS_KEYS", ",".join(PackedStringArray(keys.values())))
	out("LOCALS_OWN_LINES_HEARD", own_said)
	var a: Array = PlanetBeast.lore(demo.planet, "pilgrim")
	var c: Array = PlanetBeast.lore(demo.planet, "soot")
	out("LOCALS_TOWNS_DIFFER", a != c and a.size() > 0 and c.size() > 0)
	out("LOCALS_PORT_LINES", PlanetBeast.lore(demo.planet, "port").size())
	_write()


func _write() -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("FOLKLORETRACE wrote ", OUT, " (", lines.size(), " lines)")
	quit()
