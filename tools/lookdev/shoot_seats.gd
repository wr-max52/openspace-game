extends SceneTree
## Issue #883: a still of every speeder full: the Sand-boxer with four troopers
## (a heist's speeder wave), the racer and the box truck with a driver and a
## rider. Built the way SpeederNode builds the look and seats its NPCs (an open
## cockpit sits everyone in the driver's pose).
##
##   godot --path . --resolution 1600x700 -s res://tools/lookdev/shoot_seats.gd
## (Linux with no display: xvfb-run -a -s "-screen 0 1600x700x24" godot --rendering-driver vulkan ...)
## Writes res://test_results/lookdev/seats.png (OUT=<file> to write elsewhere).

const W := 1600
const H := 700
const ROW := { "speeder": [-7.5, "yard_trooper"], "racer": [0.0, "local_guard"], "hauler": [8.5, "local_guard"] }

var vp: SubViewport


func _initialize() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	_run()


func _run() -> void:
	await process_frame
	var stage := Node3D.new()
	vp.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#d9c39a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#bfb39c")
	env.environment.ambient_light_energy = 0.7
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	stage.add_child(sun)
	var sand := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	sand.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("#c8a46e")
	sand.material_override = sm
	stage.add_child(sand)
	var mats := LookMaterials.new()
	var cc = load("res://src/systems/dataload/core_content.gd").shared()
	var node_script = load("res://src/systems/vehicles/speeder_node.gd")
	for id in ROW:
		var sp = node_script.new()
		sp.cfg = HoverModel.load_config(id)
		var look: Dictionary = sp.cfg.get("look", {})
		sp.paint = str(look.get("display_paint", ""))
		sp._build_visual()
		var v: Node3D = sp.visual
		sp.remove_child(v)
		var at := Vector3(float(ROW[id][0]), float(sp.cfg.get("hover_height", 0.9)), 0.0)
		var holder := Node3D.new()
		holder.position = at
		holder.rotation.y = PI * 0.5             # nose to the left of the shot
		stage.add_child(holder)
		holder.add_child(v)
		var soldier: Dictionary = cc.get_soldier(str(ROW[id][1]))
		for seat in sp.cfg.get("seats", {}):
			var b := NpcBody.new()
			b.setup(soldier, Vector3.ZERO, 0.0, mats)
			stage.add_child(b)
			b.set_physics_process(false)
			b.set_process(false)
			var a: Array = sp.cfg.seats[seat]
			b.global_position = holder.global_transform * Vector3(float(a[0]), float(a[1]), float(a[2]))
			b.rotation.y = holder.rotation.y + PI
			if sp.sits_riders():
				sp._sit_npc(b)
		sp.free()
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.fov = 40.0
	cam.global_position = Vector3(0.5, 5.5, 15.0)
	cam.look_at(Vector3(0.5, 0.8, 0.0), Vector3.UP)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "res://test_results/lookdev/seats.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	vp.get_texture().get_image().save_png(out)
	print("SEATS ", out)
	quit()
