extends SceneTree
## Issue #879 trace (headless, the real town scene on the tide world): the round
## sea. The tide world is the water type made a ball (SEA_*: an OceanSphere, the
## sea a smooth ball a little under the deck, no glass, nothing lethal to a ship);
## its speeder pad stands out of the sea in front of the gate at the deck's level
## with a ramp down to the water (PAD_*), and the town's loaner waits on it; the
## five Remnant outposts stand on pontoons out on the sea, a Territory front
## (OUTPOST_*). A speeder leaves the pad, crosses a kilometre of open sea to the
## nearest outpost, its rider steps off onto the pontoon and back on, and it rides
## home without sinking, lifting and settling on the swell (RIDE_*). A person on foot
## in the water drowns and wakes by the landing bay, whether dropped out on the sea
## or stepping off the deck's side (DROWN_*).
## Writes test_results/sea_trace.txt for tests/test_sea_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/sea_trace.gd

const OUT := "res://test_results/sea_trace.txt"
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


func _run() -> void:
	await frames(2)
	WorldState.system = "red_reach"
	GameFlow.planet_id = "port_tide"
	GameFlow.arrival = {}
	demo = load("res://scenes/town_demo.gd").new()
	demo.use_look = false
	get_root().add_child(demo)
	for i in 3000:
		if demo.terrain != null and demo.platform != null and demo.sea_loaner != null:
			break
		await physics_frame
	player = demo._player
	await frames(10)
	out("PLACE", str(demo.planet.get("id", "")))
	out("TYPE", str(demo.planet.get("type", "")))
	out("SYSTEM", PlanetGen.system_of("port_tide"))

	# ---------------------------------------------------------------- the sea
	var terrain: PlanetTerrain = demo.terrain
	var sp: OceanSphere = terrain.sphere as OceanSphere
	out("SEA_IS_BALL", sp != null)
	if sp == null:
		_write()
		return
	out("SEA_RADIUS_M", int(sp.radius))
	out("SEA_LEVEL_M", snappedf(sp.sea_level(), 0.01))
	var far := sp.elevation(sp.map_dir(2000.0, -2600.0))
	var far2 := sp.elevation(sp.map_dir(-4000.0, 9000.0))
	out("SEA_SMOOTH", absf(far - sp.sea_level()) < 0.001 and absf(far2 - sp.sea_level()) < 0.001)
	out("SEA_SHADER", str((terrain.material as ShaderMaterial).shader.resource_path))
	out("SEA_NO_SAND", demo.landforms == null and not demo._desert_dressed)
	out("SEA_NO_GLASS", demo.platform.glass_boxes.size())
	out("SEA_NOT_LETHAL", not demo.planet.world.has("lethal_below"))
	out("SEA_STYLE", str(demo.planet.get("style", "")))

	# ---------------------------------------------------------------- the speeder pad
	var pad: Dictionary = demo.planet.town.get("speeder_pad", {})
	out("PAD_BUILT", not pad.is_empty())
	var rect: Rect2 = pad.get("rect", Rect2())
	var c := rect.get_center()
	out("PAD_OUT_FRONT", rect.position.x >= demo.platform.deck.end.x - 2.0 and absf(c.y) < 10.0)
	out("PAD_LEVEL_M", snappedf(terrain.height_at(c.x, c.y), 0.01))
	out("PAD_RAMP_TO_SEA", absf(sp.elevation(sp.map_dir(rect.end.x + float(pad.ramp) + 1.0, c.y)) - sp.sea_level()) < 0.01)
	var spots: Array = demo.town.markers_with_role("speeder_spot")
	var on_pad := 0
	for m in spots:
		var q: Vector3 = demo.town.marker_pos(str(m.id))
		if rect.has_point(Vector2(q.x, q.z)):
			on_pad += 1
	out("PAD_SPOTS", spots.size())
	out("PAD_SPOTS_ON_PAD", on_pad)
	var loaner: SpeederNode = demo.sea_loaner
	var lp: Vector3 = loaner.model.position
	out("PAD_LOANER_ON_PAD", rect.has_point(Vector2(lp.x, lp.z)))
	out("PAD_LOANER_HEIGHT_M", snappedf(lp.y - terrain.height_at(lp.x, lp.z), 0.01))

	# ---------------------------------------------------------------- the outposts
	var ids: Array = Territory.front("tide").get("outposts", [])
	out("OUTPOST_FRONT", ",".join(PackedStringArray(ids)))
	var lifted := 0
	var ramped := 0
	var dists := []
	for lm in demo.planet.world.landmarks:
		if not ids.has(str(lm.get("location", ""))):
			continue
		var at := Vector2(float(lm.at[0]), float(lm.at[2]))
		dists.append(int(sp.ground_dist(Vector2.ZERO, at)))
		if absf(sp.elevation(sp.map_dir(at.x, at.y)) - (sp.sea_level() + PlanetTerrain.SEA_PAD_LIFT)) < 0.05:
			lifted += 1
		var past := at + Vector2(PlanetTerrain.SEA_PAD_HALF + PlanetTerrain.SEA_PAD_BLEND + 2.0, 0.0)
		if absf(sp.elevation(sp.map_dir(past.x, past.y)) - sp.sea_level()) < 0.01:
			ramped += 1
	out("OUTPOST_COUNT", dists.size())
	out("OUTPOST_ON_PONTOONS", lifted)
	out("OUTPOST_IN_OPEN_SEA", ramped)
	dists.sort()
	out("OUTPOST_DIST_M", ",".join(PackedStringArray(dists.map(func(d): return str(d)))))

	# ---------------------------------------------------------------- the ride
	var ground: WorldGround = demo.pilot.ground
	_put_player(lp + Vector3(-2.0, 0.6, 1.5))
	await frames(5)
	out("RIDE_MOUNTED", loaner.mount())
	var spit := Vector2.ZERO
	for lm in demo.planet.world.landmarks:
		if str(lm.get("location", "")) == "remnant_outpost_tide_spit":
			spit = Vector2(float(lm.at[0]), float(lm.at[2]))
	var stop_x := spit.x - PlanetTerrain.SEA_PAD_HALF + 4.0     # on the pontoon, short of its troopers
	var leg_out := await _ride(loaner, sp, ground, lp.x, stop_x, spit.y)
	out("RIDE_OUT_ARRIVED", leg_out.arrived)
	out("RIDE_OUT_SECONDS", snappedf(leg_out.t, 0.1))
	out("RIDE_OUT_SEA_M", int(leg_out.sea_m))
	out("RIDE_OUT_LOW_M", snappedf(leg_out.low, 0.01))
	out("RIDE_SWELL_RANGE_M", snappedf(leg_out.hi_sea - leg_out.lo_sea, 0.01))
	# Off onto the pontoon: a person standing there is not in the sea.
	out("RIDE_DISMOUNT", loaner.dismount())
	var d0: int = demo.platform.drowned
	await frames(90)
	out("RIDE_STOOD_ON_PONTOON", demo.platform.drowned == d0 and not demo.platform.is_falling())
	var at_pontoon := sp.world_to_map(player.global_position)
	out("RIDE_ON_PONTOON_M", int(sp.ground_dist(at_pontoon, spit)))
	_put_player(loaner.model.position + ground.up_at(loaner.model.position) * 0.6)
	await frames(5)
	out("RIDE_REMOUNTED", loaner.mount())
	var leg_back := await _ride(loaner, sp, ground, loaner.model.position.x, c.x + 4.0, c.y)
	out("RIDE_BACK_ARRIVED", leg_back.arrived)
	out("RIDE_BACK_SECONDS", snappedf(leg_back.t, 0.1))
	out("RIDE_BACK_LOW_M", snappedf(leg_back.low, 0.01))
	out("RIDE_ALIVE", loaner.model.alive())
	out("RIDE_NOT_DROWNED", demo.platform.drowned == d0)
	loaner.dismount()
	await frames(30)

	# ---------------------------------------------------------------- drowning
	var spawn: Vector3 = demo.town.spawn_pos()
	var falls0: int = demo.platform.falls
	var dir := sp.map_dir(420.0, 310.0)
	_put_player(sp.center + dir * (sp.radius + sp.sea_level() + 0.3))
	var went := false
	for i in 60 * 5:
		await physics_frame
		if demo.platform.falls > falls0:
			went = true
			break
	out("DROWN_OUT_AT_SEA", went and demo.platform.drowned > d0)
	out("DROWN_WOKE_BY_BAY_M", snappedf(player.global_position.distance_to(spawn), 0.1))
	await frames(60)
	# Stepping off the deck's side into the water.
	var d1: int = demo.platform.drowned
	var deck: Rect2 = demo.platform.deck
	_put_player(Vector3(deck.get_center().x, 0.6, deck.position.y - 3.0))
	went = false
	for i in 60 * 6:
		await physics_frame
		if demo.platform.drowned > d1:
			went = true
			break
	await frames(200)
	out("DROWN_OFF_THE_DECK", went)
	out("DROWN_WOKE_AGAIN_M", snappedf(player.global_position.distance_to(spawn), 0.1))
	out("DROWN_LINE", str(demo.planet.type_cfg.get("fall_text", "")))
	# And standing on the deck by the gate, nobody drowns.
	var d2: int = demo.platform.drowned
	_put_player(Vector3(deck.end.x - 6.0, 0.3, 0.0))
	await frames(120)
	out("DROWN_NOT_ON_DECK", demo.platform.drowned == d2)
	_write()


## Ride `s` straight along the map's z = `z` line from x0 to x1 at a rider's pace
## (SpeederBrain), real frames. { arrived, t, sea_m (metres of open sea crossed),
## low (lowest height over the water or pad), lo_sea / hi_sea (height over the
## still sea on open water: the swell) }.
func _ride(s: SpeederNode, sp: OceanSphere, ground: WorldGround, x0: float, x1: float, z: float) -> Dictionary:
	var route: Array = []
	var step := 20.0 * signf(x1 - x0)
	var x := x0
	while (x1 - x) * signf(step) > 0.0:
		route.append(sp.surface_at(x, z) + ground.up_at(sp.surface_at(x, z)) * 1.0)
		x += step
	route.append(sp.surface_at(x1, z) + ground.up_at(sp.surface_at(x1, z)) * 1.0)
	var end: Vector3 = route[-1]
	var b := SpeederBrain.new(s.model, "default", 7)
	b.follow(route, false)
	b.pace = 0.8
	var r := { "arrived": false, "t": 0.0, "sea_m": 0.0, "low": INF, "lo_sea": INF, "hi_sea": -INF }
	var last := s.model.position
	while r.t < 240.0 and s.model.alive():
		if s.model.position.distance_to(end) < 8.0:
			r.arrived = true
			break
		var cmd := b.update(DT)
		if s.model.position.distance_to(end) < 40.0:
			cmd["throttle"] = minf(float(cmd.get("throttle", 0.0)), 0.35)
		s.set_external_command(cmd)
		await physics_frame
		r.t += DT
		var p := s.model.position
		var h := sp.height_above_ground(p)
		r.low = minf(r.low, h)
		var dir := (p - sp.center).normalized()
		if sp.elevation(dir) <= sp.sea_level() + 0.01:
			r.sea_m += p.distance_to(last)
			var over := (p - sp.center).length() - sp.radius - sp.sea_level()
			r.lo_sea = minf(r.lo_sea, over)
			r.hi_sea = maxf(r.hi_sea, over)
		last = p
	s.set_external_command({ "throttle": 0.0, "steer": 0.0, "boost": false })
	for i in 60:
		await physics_frame
	return r


func _write() -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("SEATRACE wrote ", OUT, " (", lines.size(), " lines)")
	quit()
