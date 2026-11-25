extends SceneTree
## The Ledger's ship and speeder icons. Renders each ship look (ShipKit) and each
## speeder model (its vehicle file, built the way SpeederNode builds it) flat white
## on a clear background, nose to the right, so the inventory shows a silhouette of
## what you own: ships from straight above (their wings are what tell them apart),
## the Sand-boxer and the box truck side on, the racer from above (side on it is a
## hair-line). No new art: the same models
## you fly and ride.
##
## Needs a real renderer:
##   godot --path . --resolution 640x320 -s res://tools/lookdev/vehicle_icons.gd
## Writes res://assets/ui/vehicle_icons/<look id or speeder model>.png. Run again
## if a model changes. VIEW=side|top|three (env) shoots everything from that angle
## instead; OUT=<dir> writes somewhere else.

const OUT := "res://assets/ui/vehicle_icons/"
const SHIP_LOOKS := ["interceptor", "freighter", "courier", "gunship", "remnant_fighter", "remnant_heavy"]
const SPEEDERS := { "speeder": "side", "racer": "top", "hauler": "side" }   ## model -> the angle it reads best from
const W := 512
const H := 256
const MARGIN := 1.1
## The camera's way in to the model, in its own frame (nose is -Z, up is +Y):
## from the right side (+X), a little above and a little ahead.
const VIEWS := {
	"three": Vector3(1.0, 0.75, -0.45),
	"side": Vector3(1.0, 0.0, 0.0),
	"top": Vector3(0.0, 1.0, 0.001),
}

var vp: SubViewport
var cam: Camera3D
var stage: Node3D
var out_dir := OUT
var view := ""                     ## "" = top for ships, SPEEDERS for speeders


func _initialize() -> void:
	if OS.get_environment("OUT") != "":
		out_dir = OS.get_environment("OUT").path_join("")
	if OS.get_environment("VIEW") != "":
		view = OS.get_environment("VIEW")
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	stage = Node3D.new()
	vp.add_child(stage)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	_run()


func _run() -> void:
	await process_frame
	var kit = load("res://src/systems/look/ship_kit.gd").new()
	for id in SHIP_LOOKS:
		var n: Node3D = kit.build(id)
		for c in n.find_children("Flames", "", true, false):
			c.visible = false
		await _shoot(n, str(id), "top")
	var hover = load("res://src/systems/vehicles/hover_model.gd")
	var node_script = load("res://src/systems/vehicles/speeder_node.gd")
	for id in SPEEDERS:
		var sp = node_script.new()
		sp.cfg = hover.load_config(id)
		var look: Dictionary = sp.cfg.get("look", {})
		sp.paint = str(look.get("display_paint", ""))
		sp._build_visual()
		var v: Node3D = sp.visual
		sp.remove_child(v)
		sp.free()
		await _shoot(v, str(id), str(SPEEDERS[id]))
	quit()


func _shoot(n: Node3D, id: String, angle: String) -> void:
	if view != "":
		angle = view
	stage.add_child(n)
	_flatten(n)
	await process_frame
	var box := _bounds(n)
	var centre := box.get_center()
	var dir: Vector3 = VIEWS.get(angle, VIEWS.three).normalized()
	var r := box.size.length()
	cam.global_position = centre + dir * r * 3.0
	# Nose to the right on screen: up is world up, except from straight above.
	cam.look_at(centre, Vector3.FORWARD.rotated(Vector3.UP, PI * 0.5) if angle == "top" else Vector3.UP)
	cam.near = 0.05
	cam.far = r * 8.0
	cam.size = r * MARGIN
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img = img.get_region(img.get_used_rect().grow(4).intersection(Rect2i(0, 0, W, H)))   # trimmed; the Ledger fits it to its box
	img.save_png(out_dir + id + ".png")
	print("ICON ", id, " ", img.get_size())
	stage.remove_child(n)
	n.queue_free()


## Everything white and unlit, so only the outline reads.
func _flatten(n: Node) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color.WHITE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		var gi := c as GeometryInstance3D
		gi.material_override = m
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.find_children("*", "Light3D", true, false):
		c.visible = false
	for c in n.find_children("*", "GPUParticles3D", true, false):
		c.visible = false


func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
