extends SceneTree
## Issue #880 trace (headless, the real town scene in the asteroid field): the red
## system's field is its own place (FIELD_*: the field type, no ground, open space's
## sky, a few hundred rocks round a dock town on the biggest). On foot out there the
## gravity is low and the jetpack refuels in the air; step off a rock and you drift,
## slowly, onto the next one in reach (HOP_*). Drift clear of every rock and your ship
## reels you back in (REEL_*). A ship flown into a big rock is stopped by it, and can
## set down on one (SHIP_*). The four Remnant outposts on the biggest rocks are a
## Territory front, each one taken once its troopers are dead (OUTPOST_*). The bar
## board's field jobs come up in the field and pay: a salvage run carried from a wreck
## to your ship (JOB_*). Also the wrecks, the deck's rock and the board's other jobs.
## Writes test_results/field_trace.txt for tests/test_field_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/field_trace.gd

const OUT := "res://test_results/field_trace.txt"
const DT := 1.0 / 60.0

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
	player.align_to_ground(true)


func _run() -> void:
	await frames(2)
	WorldState.system = "red_reach"
	GameFlow.planet_id = "scatter_field"
	GameFlow.arrival = {}
	demo = load("res://scenes/town_demo.gd").new()
	demo.use_look = false
	get_root().add_child(demo)
	for i in 3000:
		if demo.terrain != null and demo.field_world != null and demo._player != null:
			break
		await physics_frame
	player = demo._player
	await frames(30)
	var fw: FieldWorld = demo.field_world
	out("FIELD_PLACE", str(demo.planet.get("id", "")))
	out("FIELD_TYPE", str(demo.planet.get("type", "")))
	out("FIELD_SYSTEM", PlanetGen.system_of("scatter_field"))
	out("FIELD_OWN_PLACE", fw != null and fw.L.size() > 0)
	if fw == null or fw.L.is_empty():
		_write()
		return
	var L: Dictionary = fw.L
	var ground: WorldGround = demo.pilot.ground
	var sp: PlanetSphere = ground.sphere()
	out("FIELD_SPHERE", sp.get_class() if sp == null else ("FieldSphere" if sp is FieldSphere else "other"))
	out("FIELD_NO_GROUND_MESH", (demo.terrain as PlanetTerrain).no_mesh)
	out("FIELD_ROCKS", (L.rocks as Array).size())
	out("FIELD_SMALL_ROCKS", (L.small as Array).size())
	var biggest := 0.0
	var smallest := INF
	var colliders := 0
	for rk in L.rocks:
		biggest = maxf(biggest, float(rk.r))
		smallest = minf(smallest, float(rk.r))
	for b in ground.boxes:
		if str(b.id).begins_with("field/"):
			colliders += 1
	var bad := []
	for b in ground.boxes:
		var size: Vector3 = (b.max as Vector3) - (b.min as Vector3)
		if size.x < 0.0 or size.y < 0.0 or size.z < 0.0:
			bad.append(str(b.id))
	out("FIELD_BAD_BOXES", ",".join(PackedStringArray(bad)))
	out("FIELD_ROCK_RADIUS_M", "%d..%d" % [int(smallest), int(biggest)])
	out("FIELD_ROCK_COLLIDERS", colliders)
	out("FIELD_GRAVITY_BODIES", sp.gravity_bodies.size())
	out("FIELD_WRECKS", (L.wrecks as Array).size())
	out("FIELD_GRAVITY", fw.gravity)
	var cantina := 0
	for b in ground.boxes:
		if str(b.id).contains("cantina"):
			cantina += 1
	out("FIELD_CANTINA_BOXES", cantina)
	var home: Dictionary = (L.rocks as Array).filter(func(r): return str(r.role) == "home")[0]
	out("FIELD_DECK_ON_ROCK", absf(FieldRocks.top_of(home).y - float(fw.cfg.home.face_y)) < 0.5)
	out("FIELD_SPAWN_HELD", fw.held(demo.town.spawn_pos()))
	var roles := {}
	for rk in L.rocks:
		roles[str(rk.role)] = int(roles.get(str(rk.role), 0)) + 1
	var rk_keys: Array = roles.keys()
	rk_keys.sort()
	out("FIELD_ROLES", ",".join(PackedStringArray(rk_keys.map(func(k): return "%s:%d" % [k, roles[k]]))))
	await _hop(fw, L, sp)
	await _reel(fw)
	await _wrecks(fw, L, ground)
	await _jobs_board()
	await _salvage(fw, L)
	await _outposts(fw)
	await _ship(L, ground)
	_write()


## A rock and the next one along a hop path, the nearer pair; on foot from A's top,
## a run and a jump at B: the low gravity carries you over and B's pull lands you.
func _hop(fw: FieldWorld, L: Dictionary, sp: PlanetSphere) -> void:
	var rocks: Array = L.rocks
	var best := INF
	var pa := -1
	var pb := -1
	for i in rocks.size() - 1:
		var a: Dictionary = rocks[i]
		var b: Dictionary = rocks[i + 1]
		if str(a.role) != "path" or str(b.role) != "path" or str(a.get("to", "")) != str(b.get("to", "")):
			continue
		var gap: float = (a.c as Vector3).distance_to(b.c) - float(a.r) - float(b.r)
		var rise: float = FieldRocks.top_of(b).y - FieldRocks.top_of(a).y
		if absf(rise) < 6.0 and gap < best:
			best = gap
			pa = i
			pb = i + 1
	out("HOP_PAIR_FOUND", pa >= 0)
	if pa < 0:
		return
	var A: Dictionary = rocks[pa]
	var B: Dictionary = rocks[pb]
	out("HOP_GAP_M", snappedf(best, 0.1))
	var a_top := FieldRocks.top_of(A)
	var a_up: Vector3 = (A.basis as Basis).y
	var to_b: Vector3 = FieldRocks.top_of(B) - a_top
	to_b = (to_b - a_up * to_b.dot(a_up)).normalized()
	_put_player(a_top + to_b * float(A.r) * 0.25 + a_up * 0.4)
	player.rotation.y = 0.0
	await frames(40)
	out("HOP_STOOD_ON_A", player.is_on_floor() and int(sp.nearest_body(player.global_position).get("index", -1)) == pa)
	out("HOP_LOW_GRAVITY", snappedf(player.controller.gravity, 0.01))
	WorldState.inventory.add("jetpack")
	WorldState.inventory.attach("jetpack", demo.gear.content.get_item("jetpack"))
	demo.gear.sync_gear()
	out("HOP_HAS_JETPACK", player.jetpack != null)
	if player.jetpack != null:
		player.jetpack.refill()
	var hp0: float = float(player.health.hp)
	var left := false
	var air := 0
	var landed_on := -1
	var max_gap_air := 0.0
	var jet_ok := false
	for i in 60 * 20:
		var p: Vector3 = player.global_position
		var up := sp.up_at(p)
		var to: Vector3 = FieldRocks.top_of(B) - p
		to -= up * to.dot(up)
		var l: Vector3 = player.tilt.inverse() * to
		var go := Vector2(l.x, l.z).normalized() if to.length() > 2.0 and not left or air > 0 else Vector2.ZERO
		# Jump from the side of A that faces B (feet stick, so you walk round A's
		# curve toward B): up there points across the gap.
		var face_gap: float = p.distance_to(B.c) - float(B.r)
		var jump := not left and (face_gap <= best + 3.0 or up.dot(((B.c as Vector3) - p).normalized()) > 0.6)
		player.set_command(go, true, false, jump, false)
		await physics_frame
		if not player.is_on_floor():
			left = true
			air += 1
			if player.jetpack != null:
				if air == 2:
					player.jetpack.fuel = 0.0
				jet_ok = jet_ok or player.jetpack.fuel > 0.0
		elif left and air > 10:
			landed_on = int(sp.nearest_body(player.global_position).get("index", -1))
			break
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(30)
	out("HOP_LEFT_A", left)
	out("HOP_AIR_S", snappedf(air / 60.0, 0.01))
	out("HOP_LANDED_ON_B", landed_on == pb)
	out("HOP_LANDED_ON", "%d (A %d, B %d)" % [landed_on, pa, pb])
	out("HOP_STILL_ON_B", player.is_on_floor() and int(sp.nearest_body(player.global_position).get("index", -1)) == pb)
	var hp1: float = float(player.health.hp)
	out("HOP_UNHURT", hp1 >= hp0)
	out("HOP_JETPACK_REFUELS_IN_AIR", jet_ok)
	out("HOP_NOT_REELED", fw.pulls == 0)


## Off into the dark, clear of every rock's reach: a while later your ship reels
## you back in.
func _reel(fw: FieldWorld) -> void:
	var p0 := fw.pulls
	var ship := fw.ship_pos()
	_put_player(Vector3(0, 650, 0))
	var t := 0
	while fw.pulls == p0 and t < 60 * 15:
		await physics_frame
		t += 1
	out("REEL_PULLED_BACK", fw.pulls > p0)
	out("REEL_AFTER_S", snappedf(t / 60.0, 0.1))
	var by: float = player.global_position.distance_to(ship) if ship != Vector3.INF else player.global_position.distance_to(demo.town.spawn_pos())
	out("REEL_BY_SHIP_M", snappedf(by, 0.1))
	await frames(180)
	out("REEL_STANDING", player.is_on_floor())
	# Below the field, far down: the same.
	var p1 := fw.pulls
	_put_player(Vector3(40, -300, 40))
	await frames(10)
	out("REEL_FROM_BELOW", fw.pulls > p1)
	await frames(60)


## Each wreck: its pad stands in the dark among the rocks, its decks are walkable
## (the salvage cells are on a floor), and its own up holds round it.
func _wrecks(fw: FieldWorld, L: Dictionary, ground: WorldGround) -> void:
	var ok := 0
	var cells_on_floor := 0
	for w in L.wrecks:
		var pad: Vector3 = w.pad
		var h := ground.height_above(pad + (w.level as Transform3D).basis.y * 2.0)
		if h < 3.0 and fw.held(pad):
			ok += 1
		for c in fw.cfg.get("cells", []):
			var at: Vector3 = (w.level as Transform3D) * FieldRocks._v3(c) + (w.level as Transform3D).basis.y * 0.9
			if ground.height_above(at) < 2.5:
				cells_on_floor += 1
	out("WRECK_PADS_OK", ok)
	out("WRECK_CELLS_ON_FLOOR", cells_on_floor)
	# Walk into one: on its pad, then down its bridge ramp.
	var w0: Dictionary = L.wrecks[0]
	_put_player((w0.pad as Vector3) + (w0.level as Transform3D).basis.y * 1.0)
	await frames(150)
	out("WRECK_PAD_DROP_M", snappedf(ground.height_above((w0.pad as Vector3) + (w0.level as Transform3D).basis.y * 1.0), 0.01))
	out("WRECK_STOOD_ON_PAD", player.is_on_floor())


## The board's field jobs: up in the field, and not on another planet's board.
func _jobs_board() -> void:
	var here: Array = WorldState.open_jobs("").map(func(j): return str(j.id)).filter(func(id): return str(id).begins_with("j_field_"))
	here.sort()
	out("JOB_BOARD_HERE", ",".join(PackedStringArray(here)))
	var was := GameFlow.planet_id
	GameFlow.planet_id = "port_red"
	var there: Array = WorldState.open_jobs("").filter(func(j): return str(j.id).begins_with("j_field_"))
	GameFlow.planet_id = was
	out("JOB_BOARD_ELSEWHERE", there.size())
	await frames(1)


## The salvage run: take it, walk to each power cell in the wreck, carry them to
## your ship; it pays and goes back on the board.
func _salvage(fw: FieldWorld, L: Dictionary) -> void:
	var c0 := WorldState.credits
	out("JOB_SALVAGE_TAKEN", WorldState.accept_job("j_field_salvage"))
	await frames(5)
	var st: Dictionary = fw.jobs.get("j_field_salvage", {})
	out("JOB_SALVAGE_STARTED", not st.is_empty())
	if st.is_empty():
		return
	out("JOB_SALVAGE_WRECK", str(st.wreck))
	out("JOB_SALVAGE_GOAL", str(FieldWorld.goal.get("text", "")))
	out("JOB_SALVAGE_POINTER", FieldWorld.goal.get("at", Vector3.INF) != Vector3.INF)
	for c in st.cells:
		_put_player((c.at as Vector3) + Vector3(0.5, 0.2, 0.0))
		await frames(20)
	out("JOB_SALVAGE_CARRIED", int(st.carried))
	var ship := fw.ship_pos()
	out("JOB_SHIP_PARKED", ship != Vector3.INF)
	_put_player(ship + Vector3(6.0, 0.5, 0.0) if ship != Vector3.INF else demo.town.spawn_pos())
	await frames(20)
	out("JOB_SALVAGE_PAID", WorldState.credits - c0)
	out("JOB_SALVAGE_BACK_ON_BOARD", not WorldState.jobs_taken.has("j_field_salvage"))
	out("JOB_SALVAGE_RUNS", WorldState.count("field_salvage_runs"))


## Your ship flown at a big rock's side is stopped by it (a bump at low speed);
## over a rock's top C sets her down on it.
func _ship(L: Dictionary, ground: WorldGround) -> void:
	var pilot: ShipPilot = demo.pilot
	var big: Dictionary = {}
	for rk in L.rocks:
		if str(rk.role) in ["path", "scatter"] and (big.is_empty() or float(rk.r) > float(big.r)):
			if absf((rk.basis as Basis).y.dot(Vector3.UP)) > 0.95:
				big = rk
	out("SHIP_ROCK_RADIUS_M", int(big.get("r", 0)))
	var c: Vector3 = big.c
	var r := float(big.r)
	# Over its top: C sets her down on the rock.
	var top := FieldRocks.top_of(big)
	pilot._seat_arriving()
	pilot.atmo.reached_space = true
	pilot.atmo.place_flying(top + Vector3(0, 30.0, 0), Vector3.FORWARD, 4.0, 0.0)
	out("SHIP_CAN_LAND", pilot.atmo.can_land())
	out("SHIP_LAND", pilot.land())
	var waited := 0
	while pilot.atmo.state != AtmoFlight.State.PARKED and waited < 60 * 20:
		pilot.set_external_command({ "throttle": 0.0 })
		await physics_frame
		waited += 1
	pilot.set_external_command({})
	out("SHIP_LAND_STATE", pilot.atmo.state_label())
	out("SHIP_ON_ROCK_M", snappedf(pilot.atmo.position().distance_to(top), 0.1))
	await frames(10)
	# At its side, slowly: a bump, and she stops against it.
	var start := c + Vector3(r + 18.0, 0.0, 0.0)
	pilot._seat_arriving()
	pilot.atmo.place_flying(c + Vector3(r + 18.0, 0.0, 0.0), Vector3.LEFT, 14.0, 0.0)
	var bumped := false
	var top_speed := 0.0
	var frames_flown := 0
	for f in 60 * 10:
		# Cruise in at about 14 m/s, well under a crash.
		pilot.set_external_command({ "throttle": 0.25 if float(pilot.atmo.flight.speed) < 14.0 else 0.0 })
		top_speed = maxf(top_speed, float(pilot.atmo.flight.speed))
		await physics_frame
		frames_flown += 1
		top_speed = maxf(top_speed, float(pilot.atmo.flight.speed))
		if pilot.atmo.last_hit.begins_with("field/") or pilot.atmo.state != AtmoFlight.State.FLYING:
			bumped = pilot.atmo.last_hit.begins_with("field/")
			break
	out("SHIP_BUMPED_ROCK", bumped)
	out("SHIP_HIT", pilot.atmo.last_hit)
	out("SHIP_BUMP_SPEED", snappedf(top_speed, 0.1))
	out("SHIP_BUMP_AFTER_S", snappedf(frames_flown / 60.0, 0.01))
	out("SHIP_STATE_AFTER_BUMP", pilot.atmo.state_label())
	var q: Vector3 = FieldRocks.frame_of(big).affine_inverse() * pilot.atmo.position()
	out("SHIP_OUTSIDE_ROCK", Vector2(q.x, q.z).length() > r * 0.9 or q.y > FieldRocks.TOP * r)
	# A fast run into it: she crashes.
	pilot.atmo.last_hit = ""
	pilot.atmo.place_flying(start, Vector3.LEFT, 120.0, 1.0)
	for f in 60 * 4:
		pilot.set_external_command({ "throttle": 1.0 })
		await physics_frame
		if pilot.atmo.state != AtmoFlight.State.FLYING:
			break
	out("SHIP_CRASH_STATE", pilot.atmo.state_label())
	out("SHIP_CRASH_HIT", pilot.atmo.last_hit)
	pilot.set_external_command({})
	pilot.crash_left = -1.0
	await frames(10)


## The four outposts: each one's troopers dead, and once you are well away and the
## clock has run, the locals have it; Clear the rock pays on the first.
func _outposts(fw: FieldWorld) -> void:
	var ids: Array = Territory.front("field").get("outposts", [])
	out("OUTPOST_FRONT", ",".join(PackedStringArray(ids)))
	out("OUTPOST_FRONT_PLANET", Territory.front_for_planet("scatter_field"))
	var c0 := WorldState.credits
	out("JOB_CLEAR_TAKEN", WorldState.accept_job("j_field_clear"))
	await frames(5)
	var keep_hp: int = player.health.max_hp
	player.health.max_hp = 1000000      # the troopers shoot back; this is about the outposts
	player.health.hp = 1000000
	var built := 0
	var troopers := 0
	var taken := 0
	var on_rock := 0
	for s in demo.stations:
		if s.remnant == null or not ids.has(s.remnant.place):
			continue
		built += 1
		var rm = s.remnant
		var foot: Vector3 = s.to_world(Vector3.ZERO)
		_put_player(foot + Vector3(0, 60.0, 0))      # in sight of it: its troopers take their posts
		for i in 600:
			if rm.woke and rm._queue.is_empty() and not rm.troopers.is_empty():
				break
			await physics_frame
		troopers += rm.troopers.size()
		var below: float = demo.pilot.ground.height_above(foot + Vector3.UP * 2.0)
		if below < 4.0:
			on_rock += 1
		for g in rm.troopers:
			if is_instance_valid(g) and not g.dead:
				g.apply_damage(100000.0)
		await frames(5)
		WorldState.clock += Territory.n("move_in_s", 45.0) + 1.0
		var far: Vector3 = foot + Vector3(3000, 0, 0)
		for i in 31:
			rm._tick_front_rules(far)
		await frames(2)
		if Territory.owner(rm.place) == Territory.LOCALS:
			taken += 1
	_put_player(demo.town.spawn_pos())
	player.health.max_hp = keep_hp
	player.health.hp = keep_hp
	out("OUTPOST_BUILT", built)
	out("OUTPOST_TROOPERS", troopers)
	out("OUTPOST_ON_ROCKS", on_rock)
	out("OUTPOST_TAKEN", taken)
	out("OUTPOST_HELD", Territory.held("field").size())
	await frames(10)
	out("JOB_CLEAR_PAID", WorldState.credits - c0)
	out("JOB_CLEAR_DONE", WorldState.has_flag("job_done_j_field_clear"))


func _write() -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("FIELDTRACE wrote ", OUT, " (", lines.size(), " lines)")
	quit()
