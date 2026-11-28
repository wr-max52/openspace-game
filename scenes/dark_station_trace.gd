extends SceneTree
## Issue #876 trace (headless, real physics, the real town scene): the red system's
## ring station and its cruiser over the red desert port. The station hangs over the
## port city in its own darker metal under its own name (STATION_*), Z docks you in
## its bay and you climb out aboard (DOCK_*), killing every Remnant soldier on its
## deck and top floor hands the deck to the locals and moves the map's owners
## (DECK_*, MAP_*), and killing the cruiser's general sets only that cruiser's flag
## and pays its own reward (CRUISER_*).
## Writes test_results/dark_station_trace.txt for tests/test_dark_station_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/dark_station_trace.gd

const OUT := "res://test_results/dark_station_trace.txt"
const PLACE := "station_dark_station"

var demo
var pilot
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


func _run() -> void:
	await frames(2)
	WorldState.system = "red_reach"
	GameFlow.planet_id = "port_red"
	GameFlow.arrival = {}
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false
	demo.use_look = false
	get_root().add_child(demo)
	var waited := 0
	while (demo.stations.is_empty() or demo.cruiser == null) and waited < 900:
		await physics_frame
		waited += 1
	pilot = demo.pilot
	player = demo._player
	var s = demo.stations[0] if not demo.stations.is_empty() else null
	out("STATIONS", demo.stations.size())
	if s == null:
		_finish()
		return
	_station(s)
	await _dock(s)
	await _deck(s)
	await _cruiser(demo.cruiser)
	_finish()


## Where it hangs, what it is called, what it is made of.
func _station(s) -> void:
	var sp: PlanetSphere = pilot.ground.sphere()
	out("STATION_ID", s.id)
	out("STATION_FILE", s.hull.id if s.hull != null else "")
	out("STATION_ALTITUDE", int(sp.altitude(s.frame.origin)))
	out("STATION_FROM_PORT_M", int(sp.ground_dist(sp.world_to_map(s.frame.origin), Vector2.ZERO)))
	out("STATION_NAME", s.vessel_name)
	var home := StationHull.for_id("orbital_station")
	out("HOME_STATION_NAME", NameHooks.vessel(home.cfg, "station:orbital_station"))
	out("STATION_FLOORS", s.hull.towers.map(func(t): return t.floors.size()))
	out("HOME_FLOORS", home.towers.map(func(t): return t.floors.size()))
	out("STATION_ROOMS", s.hull.rooms.values().reduce(func(n, a): return n + (a as Array).size(), 0))
	out("HOME_ROOMS", home.rooms.values().reduce(func(n, a): return n + (a as Array).size(), 0))
	var hull_mat: ShaderMaterial = s._mat("hull")
	var deck_mat: ShaderMaterial = s._mat("deck")
	out("HULL_COLOR", (hull_mat.get_shader_parameter("hull_color") as Color).to_html(false))
	out("DECK_COLOR", (deck_mat.get_shader_parameter("deck_color") as Color).to_html(false))
	out("HULL_LUMA", snappedf((hull_mat.get_shader_parameter("hull_color") as Color).get_luminance(), 0.001))
	out("OPEN_AIR", s.open_air)


## Off the station's far side (away from the cruiser), Z: round the towers, in, down
## on the dock pad; then out of the ship onto the bay's deck.
func _dock(s) -> void:
	pilot._seat_arriving()
	var c = demo.cruiser
	var away: Vector3 = (s.frame.origin - c.frame.origin).normalized() if c != null else Vector3.RIGHT
	away -= pilot.ground.up_at(s.frame.origin) * away.dot(pilot.ground.up_at(s.frame.origin))
	var start: Vector3 = s.frame.origin + away.normalized() * 600.0 + pilot.ground.up_at(s.frame.origin) * 40.0
	pilot.atmo.place_flying(start, -away.normalized(), 0.0, 0.5)
	pilot._set_hull(true)
	await frames(2)
	var target = pilot.dock_target()
	out("DOCK_TARGET", target.id if target != null and "id" in target else "")
	out("DOCK_STARTED", pilot.dock())
	var waited := 0
	while pilot.atmo.state != AtmoFlight.State.PARKED and waited < 60 * 90:
		await physics_frame
		waited += 1
	out("DOCK_S", snappedf(waited / 60.0, 0.1))
	out("DOCK_STATE", pilot.atmo.state_label())
	var pad: Vector3 = s.frame * (s.hull.dock_pad().at as Vector3)
	out("DOCK_PAD_ERR_M", snappedf((pilot.atmo.position() - pad).length(), 0.1))
	out("EXITED", pilot.exit_ship())
	await frames(30)
	out("PLAYER_ABOARD", s.aboard(player.global_position))
	out("PLAYER_ON_FLOOR", player.is_on_floor())


## The Remnant deck: who holds it on the map before and after its soldiers die.
func _owners(s) -> Dictionary:
	var count := { "remnant": 0, "locals": 0, "smugglers": 0 }
	for t in s.hull.towers:
		for i in t.floors.size():
			for rm in GlobeMap.room_pins({ "id": s.id }, s.hull, t, i):
				var who := str(rm.owner)
				count[who] = int(count.get(who, 0)) + 1
	return count


func _deck(s) -> void:
	out("DECK_OWNER_BEFORE", Territory.owner(PLACE))
	out("MAP_BEFORE", _owners(s))
	var r = s.remnant
	out("REMNANT", r != null)
	if r == null:
		return
	var waited := 0
	while (not r.woke or not r._queue.is_empty()) and waited < 600:
		await physics_frame
		waited += 1
	out("DECK_SOLDIERS", r.troopers.size())
	out("DECK_LOCKED", Territory.station_locked(PLACE))
	for g in r.troopers.duplicate():
		if is_instance_valid(g) and not g.dead:
			g.apply_damage_from(10000.0, player)
	await frames(10)
	out("DECK_OWNER_AFTER", Territory.owner(PLACE))
	out("MAP_AFTER", _owners(s))
	out("STATIONS_TAKEN", WorldState.count("stations_taken"))


## The cruiser over the port: its own file, its own flag, its own reward.
func _cruiser(c) -> void:
	out("CRUISER", c != null)
	if c == null:
		return
	var sp: PlanetSphere = pilot.ground.sphere()
	out("CRUISER_CFG", c.cfg_id)
	out("CRUISER_FLAG", c.flag())
	out("CRUISER_ALTITUDE", int(sp.altitude(c.frame.origin)))
	out("CRUISER_TO_STATION_M", int(c.frame.origin.distance_to(demo.stations[0].frame.origin)))
	# Aboard its bay: the crew wake and the general takes the bridge.
	player.global_position = c.frame * ((CruiserHull.dock_pad().at as Vector3) + Vector3(-16, 0.1, 0))
	var waited := 0
	while (c.general == null or not is_instance_valid(c.general)) and waited < 900:
		await physics_frame
		waited += 1
	out("GENERAL", c.general != null and is_instance_valid(c.general))
	if c.general == null:
		return
	var credits: int = WorldState.credits
	c.general.apply_damage_from(10000.0, player)
	await frames(5)
	out("CRUISER_TAKEN", c.taken())
	out("RED_FLAG", WorldState.has_flag("red_cruiser_taken"))
	out("BELT_FLAG", WorldState.has_flag("belt_cruiser_taken"))
	out("STORY_CRUISER", Story.cruiser_taken())
	out("PAID", WorldState.credits - credits)
	out("HOLDER", RemnantCruiser.holder_of("red_cruiser"))
	out("BELT_HOLDER", RemnantCruiser.holder_of("belt_cruiser"))


func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	if demo != null:
		demo.queue_free()
		demo = null
	await frames(3)
	GameFlow.reset()
	quit()
