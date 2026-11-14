extends SceneTree
## Wreck poses: a photo of every wreck in the field from outside, and one inside
## along its decks. A review tool, NOT the CI/GUT suite. Needs a display:
## godot --path . -s res://tools/review/wreck_poses_shot.gd -- shots=/absolute/dir
## (headless, under xvfb-run: add --rendering-driver opengl3).

var shots := ""
var sand: PlanetTerrain
var ground: WorldGround


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			shots = arg.trim_prefix("shots=").trim_suffix("/")
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var cfg: Dictionary = (ItemKit._read_json("res://content/core/worlds/port_desert.json") as Dictionary).duplicate(true)
	cfg.landmarks = cfg.landmarks.filter(func(lm): return str(lm.kind) == "wreck")
	sand = PlanetTerrain.new()
	sand.near_cells = 96
	sand.near_step = 2.0
	sand.mid_cells = 128
	sand.mid_step = 20.0
	sand.far_chunks = 2
	sand.far_cells = 64
	sand.town_cells = 32
	sand.threaded = false
	sand.collider_center = WorldGround._v3(cfg.landmarks[0].at)
	PlanetSphere.current = sand.sphere
	scene.add_child(sand)
	sand.build(true)
	sand.set_process(false)
	ground = WorldGround.new()
	ground.setup(cfg, null, null, sand.height_at, sand.extent)
	var scenery := WorldScenery.new()
	scenery.setup(ground)
	scene.add_child(scenery)
	scenery.build_visuals()
	var look := LookEnvironment.new()
	scene.add_child(look)
	look.apply("golden")
	look.set_suppressed(["sdfgi", "ssil", "volumetric"])
	var camera := Camera3D.new()
	camera.far = 16000
	camera.fov = 65
	scene.add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute(shots)
	for lm in cfg.landmarks:
		var id := str(lm.id)
		var hull := func(x: float, y: float, z: float) -> Vector3:
			return StarcruiserWreck.site_point(ground, Vector3(x, y, z), "hull", id)
		var lv := func(x: float, v: float, w: float) -> Vector3:
			return StarcruiserWreck.site_point(ground, Vector3(x, v, w), "level", id)
		var mid: Vector3 = hull.call(0, 0, 0)
		var up := ground.up_at(mid)
		var side: Vector3 = (hull.call(1, 0, 0) - mid).normalized()
		var aft: Vector3 = (hull.call(0, 0, 1) - mid).normalized()
		var flat_side := (side - up * side.dot(up)).normalized()
		var flat_aft := (aft - up * aft.dot(up)).normalized()
		var eye := _above_sand(mid + flat_side * 720.0 - flat_aft * 260.0, 70.0)
		await _photo(camera, eye, mid + up * 20.0, "%s/%s_outside.png" % [shots, id])
		await _photo(camera, lv.call(-30, 131, 140), lv.call(10, 122, 215), "%s/%s_decks.png" % [shots, id])
		await _photo(camera, hull.call(26, -10, 60), hull.call(10, -12, 260), "%s/%s_hold.png" % [shots, id])
	quit()


func _above_sand(p: Vector3, lift: float) -> Vector3:
	var m := sand.sphere.world_to_map(p)
	var s := sand.sphere.surface_at(m.x, m.y)
	return s + ground.up_at(s) * lift


func _photo(camera: Camera3D, at: Vector3, target: Vector3, path: String) -> void:
	camera.position = at
	camera.look_at(target, ground.up_at(at))
	sand.snap_to(at)
	var map := sand.sphere.world_to_map(at)
	sand._apply("mid", sand._compute("mid", map))
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("WRECK SHOT ", path)
