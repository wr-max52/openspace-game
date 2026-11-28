extends SceneTree
## Issue #874 trace (headless, real physics, the real town scene): the warp drive.
## Start in the home system's open space, flying. Without the drive the warp key
## only says why (NO_DRIVE_*). T-89 fits it: hold the key, the picker opens, pick
## the red system and the warp runs on its own for at least space.warp.min_s,
## then open space again in the red system (RED_*): only its planets hang there,
## none of home's. A save made out there loads at the red world (SAVE_*). Then
## warp home the same way (HOME_*).
## Writes test_results/warp_trace.txt for tests/test_warp_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/warp_trace.gd

const OUT := "res://test_results/warp_trace.txt"
const SaveSystem := preload("res://src/systems/save/save_system.gd")

var demo
var went: Array = []
var lines := PackedStringArray()


func _initialize() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")
	GameFlow.reset()
	GameFlow.dogfight_override = false
	GameFlow.change_scene = func(path: String) -> void:
		went.append(path)
		if OS.get_environment("WARP_STACK") != "": print_stack()
	_run()


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])
	print("  ", k, "=", v)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


## The scene GameFlow asked for (the place in GameFlow.planet_id, arriving as
## GameFlow.arrival says), built the way the game builds it.
func make_town() -> void:
	if demo != null:
		demo.queue_free()
		await frames(2)
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false
	demo.use_look = false
	get_root().add_child(demo)
	await frames(10)


## Straight into system `sys`'s open space, where a warp drops you.
func start_in_open_space(sys: String) -> void:
	WorldState.system = sys
	GameFlow.planet_id = PlanetGen.open_space_id()
	GameFlow.arrival = { "mode": "handoff", "from": "", "to": GameFlow.planet_id, "ship": "", "name": "",
		"handoff": WarpDrive.arrival(sys) }
	await make_town()


func bodies() -> Array:
	return demo.pilot.travel.bodies.map(func(b): return str(b.id))


## Hold the warp key for `secs` (the drive's own press, as the keyboard does).
func hold(secs: float) -> void:
	var w: WarpDrive = demo.pilot.warp
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	Input.action_press("flight_warp")
	for i in int(secs / dt):
		await physics_frame
		if w.phase == WarpDrive.Phase.PICKING:
			break
	Input.action_release("flight_warp")


## Warp to `sys` from here; the seconds the warp ran, or -1 when it never left.
func warp_to(sys: String, tag: String) -> float:
	var w: WarpDrive = demo.pilot.warp
	await hold(2.0)
	out(tag + "PICKER_OPEN", w.phase == WarpDrive.Phase.PICKING)
	out(tag + "DESTINATIONS", ",".join(WarpDrive.destinations()))
	out(tag + "PICKED", w.pick(sys))
	went.clear()
	var n := 0
	var max_fov := 0.0
	var max_flames := 0.0
	while went.is_empty() and n < 60 * 30:
		await physics_frame
		n += 1
		max_fov = maxf(max_fov, demo.pilot.fov_kick)
		max_flames = maxf(max_flames, demo.pilot.flame_stretch)
	var secs := n / float(Engine.physics_ticks_per_second)
	out(tag + "WARP_S", snappedf(secs, 0.01))
	out(tag + "FOV_KICK_MAX", snappedf(max_fov, 0.1))
	out(tag + "FLAMES_MAX", snappedf(max_flames, 0.01))
	out(tag + "LEFT", not went.is_empty())
	out(tag + "SCENE", went[0] if not went.is_empty() else "")
	out(tag + "TO", GameFlow.planet_id)
	out(tag + "WARP_ARRIVAL", str(GameFlow.arrival.get("warp", "")))
	return secs if not went.is_empty() else -1.0


func _run() -> void:
	await frames(2)
	# 1. Home system's open space, no drive.
	await start_in_open_space("home")
	var p: ShipPilot = demo.pilot
	out("START_PLACE", str(demo.planet.get("id", "")))
	out("START_SYSTEM", PlanetGen.current_system())
	out("START_BODIES", ",".join(bodies()))
	out("START_FLYING", p.piloting and p.atmo.state == AtmoFlight.State.FLYING)
	out("NO_DRIVE_REASON", p.warp.blocked_reason())
	await hold(2.0)
	out("NO_DRIVE_PICKER", p.warp.phase == WarpDrive.Phase.PICKING)
	out("NO_DRIVE_TOAST", p.hud.toast_label.text if p.hud.toast_label != null else "")
	out("NO_DRIVE_PICK", p.warp.pick("red_reach"))
	# 2. T-89 fits the drive; warp to the red system.
	out("FITTED", ShipUpgrades.fit(p.ship_id, "warp"))
	out("UNLOCKED", ShipUpgrades.unlocked(p.ship_id, "warp"))
	out("DRIVE_REASON", p.warp.blocked_reason())
	await warp_to("red_reach", "RED_")
	out("RED_SYSTEM_SET", str(WorldState.system))
	var hand: Dictionary = GameFlow.arrival.get("handoff", {})
	await make_town()
	went.clear()
	p = demo.pilot
	out("RED_PLACE", str(demo.planet.get("id", "")))
	out("RED_SYSTEM", PlanetGen.current_system())
	out("RED_BODIES", ",".join(bodies()))
	out("RED_POS_ERR_M", snappedf(p.atmo.position().distance_to(hand.get("position", Vector3.INF)), 0.01))
	var red_main: Dictionary = p.travel.bodies.filter(func(b): return b.id == "port_red")[0] if bodies().has("port_red") else {}
	if not red_main.is_empty():
		var to_planet: Vector3 = ((red_main.at as Vector3) - p.atmo.position()).normalized()
		out("RED_FACING_DOT", snappedf((-p.atmo.flight.basis.z).dot(to_planet), 0.001))
		out("RED_GAP_KM", snappedf(((red_main.at as Vector3).distance_to(p.atmo.position()) - float(red_main.radius) - float(red_main.handoff)) / 1000.0, 0.1))
	out("RED_SETTLING", p.warp.phase == WarpDrive.Phase.ARRIVING)
	out("RED_TOAST", p.hud.toast_label.text if p.hud.toast_label != null else "")
	out("RED_FLYING", p.piloting and p.atmo.state == AtmoFlight.State.FLYING)
	await frames(120)
	out("RED_SETTLED", p.warp.phase == WarpDrive.Phase.IDLE and p.fov_kick == 0.0)
	out("RED_STILL_HERE", str(demo.planet.get("id", "")) == PlanetGen.open_space_id() and went.is_empty())
	out("RED_WENT", ",".join(went) + " to=" + GameFlow.planet_id)
	# 3. A save made out here loads at the red world.
	var save := SaveSystem.new()
	save.new_game()
	save.set_where(PlanetGen.home_id(), Vector3.ZERO, false)
	save.set_where(PlanetGen.open_space_id(), Vector3.ZERO, false)
	out("SAVE_WHERE", str(save.get_where().get("planet", "")))
	var ws := WorldState.to_save()
	out("SAVE_SYSTEM", str(ws.get("system", "")))
	WorldState.reset()
	out("RESET_SYSTEM", str(WorldState.system))
	WorldState.from_save(ws)
	out("LOAD_SYSTEM", str(WorldState.system))
	out("LOAD_FITTED", ShipUpgrades.unlocked(p.ship_id, "warp"))
	# 4. Warp home.
	await warp_to("home", "HOME_")
	await make_town()
	p = demo.pilot
	out("HOME_PLACE", str(demo.planet.get("id", "")))
	out("HOME_SYSTEM", PlanetGen.current_system())
	out("HOME_BODIES", ",".join(bodies()))
	# 5. The red world itself loads (where a save made out there wakes you).
	GameFlow.planet_id = "port_red"
	GameFlow.arrival = {}
	await make_town()
	await frames(30)
	out("WORLD_PLACE", str(demo.planet.get("id", "")))
	out("WORLD_SYSTEM", PlanetGen.current_system())
	out("WORLD_BALL_R", PlanetSphere.current.radius if PlanetSphere.current != null else 0.0)
	out("WORLD_BODIES", ",".join(bodies()))
	out("WORLD_TOWN_BOXES", (demo.planet.get("town", {}).get("boxes", []) as Array).size())
	var pl = demo._player
	out("WORLD_PLAYER_ON_GROUND", pl != null and pl.is_on_floor())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	demo.queue_free()
	demo = null
	await frames(3)
	GameFlow.reset()
	quit()
