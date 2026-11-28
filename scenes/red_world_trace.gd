extends SceneTree
## Issue #875 trace (headless, real physics, the real town scene): the red desert
## world. It loads (PLACE_*), its town stands with red locals in it (TOWN_*), its
## five Remnant outposts are built (OUTPOSTS_*), its own people walk the desert
## half (NATIVES_*), a skirmish waits on the way up (ENCOUNTER), and standing in
## the thickest mountain pocket costs no more frame than the street (FRAME_*).
## Writes test_results/red_world_trace.txt for tests/test_red_world_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/red_world_trace.gd

const OUT := "res://test_results/red_world_trace.txt"
const Landforms := preload("res://src/systems/look/desert_landforms.gd")

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


## The worst frame over `n` frames from here (after `settle` frames to let any
## rebuild land).
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
	demo.npc_brains = false
	demo.use_look = false
	get_root().add_child(demo)
	await frames(40)
	var planet: Dictionary = demo.planet
	out("PLACE", str(planet.get("id", "")))
	out("SYSTEM", PlanetGen.current_system())
	out("TYPE", str(planet.get("type", "")))
	out("BALL_R", PlanetSphere.current.radius if PlanetSphere.current != null else 0.0)
	out("ENCOUNTER", demo.pilot.encounter_id() if demo.pilot != null else "")
	# The town and who lives in it.
	var boxes: Array = demo.town.boxes()
	out("TOWN_BOXES", boxes.size())
	out("TOWN_TOWERS", boxes.filter(func(b): return str(b.get("look", "")).begins_with("tower_")).size())
	out("TOWN_ERRORS", demo.town.validate().size())
	var red: Array = demo.town.markers().filter(func(m): return str(m.get("soldier", "")).begins_with("red_local"))
	out("TOWN_RED_LOCALS", red.size())
	var pl = demo._player
	out("PLAYER_ON_GROUND", pl != null and pl.is_on_floor())
	# The outposts.
	var op = demo.outposts
	out("OUTPOSTS_BUILT", op.outposts.size() if op != null else 0)
	out("OUTPOSTS_GUARDS", op.guards.size() if op != null else 0)
	out("OUTPOSTS_IDS", ",".join((op.outposts if op != null else []).map(func(o): return str(o.id))))
	# The natives.
	var nd = demo.natives
	out("NATIVES_PACKS", nd.packs.size() if nd != null else 0)
	out("NATIVES_LABEL", str(planet.get("natives", {}).get("people", {}).get("label", "")))
	# The mountains: how many, and the worst frame among the thickest pocket.
	var data := Landforms.load_for(planet)
	var sp: PlanetSphere = PlanetSphere.current
	var spots: Array = Landforms.mountain_spots(data, sp)
	out("MOUNTAINS", spots.size())
	out("TUNNEL_RANGES", spots.filter(func(m): return m.has("course")).size())
	out("FRAME_STREET_MS", await worst_over(120))
	# The pocket with the most peaks within 600 m of its middle.
	var best := Vector2.ZERO
	var most := -1
	for c in data.get("mountain_clusters", []):
		var m := sp.map_from_lat_lon(float(c.lat), float(c.lon))
		var n := spots.filter(func(s): return sp.ground_dist(s.map, m) < 600.0).size()
		if n > most:
			most = n
			best = m
	out("POCKET_PEAKS", most)
	var at := sp.surface_at(best.x, best.y)
	place(at + sp.up_at(at) * 2.0)
	out("FRAME_POCKET_MS", await worst_over(240, 120))
	out("POCKET_ON_GROUND", pl != null and pl.is_on_floor())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	demo.queue_free()
	demo = null
	await frames(3)
	GameFlow.reset()
	quit()
