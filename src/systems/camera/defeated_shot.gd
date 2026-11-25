class_name DefeatedShot
extends Node
## Issue #684: going down on foot. The killing hit flashes the screen white over a
## close shot of you starting to fall (the ragdoll, #25) in slow motion, then the
## camera cuts to a shot from high above the body, holding on it as it falls and
## rising slowly away, "Defeated" comes up over it, and the screen goes black. Your
## body shows for the whole shot even from first person (put back after).
## `done` fires at the black: the owner (Garrison) wakes you in the port's pit and
## calls clear(), which lifts the black and frees the shot.
##
## Time is unscaled frame time, so the slow motion does not stretch the rest. Never slows
## time on LAN (NetSession: the session's clock is shared). Every number and the
## text are content/core/flow/defeated.json.

signal done

const PATH := "res://content/core/flow/defeated.json"

var cfg: Dictionary = {}
var player: Node3D
var rig: Node                      ## CameraRigNode (set_override / snap_override / clear_override)
var t := 0.0                       ## real seconds since the hit
var finished := false              ## `done` has fired
var slowed := false
var _clearing := -1.0              ## real seconds into clear(), or -1
var _cut := false
var _back := Vector3.BACK          ## horizontal, from the body toward where the camera was
var _side := Vector3.RIGHT         ## horizontal, the flash shot's side of the body
var _phase := ""                   ## "flash" or "above": the camera shot on screen
var _avatar: Node                  ## the player's PlayerAvatar, shown in third person for the shot
var _was_first := false
var _layer: CanvasLayer
var _flash: ColorRect
var _black: ColorRect
var title: Label


## Starts the shot under `parent` (the town). `rig` may be null (headless traces):
## then there is no camera move, the rest runs as usual.
static func start(parent: Node, who: Node3D, camera_rig: Node) -> DefeatedShot:
	var s := DefeatedShot.new()
	s.name = "DefeatedShot"
	s.player = who
	s.rig = camera_rig
	s.cfg = CharacterKit._read_json(PATH)
	parent.add_child(s)
	return s


func total() -> float:
	return float(cfg.get("total", 3.8))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	_flash = _rect(Color(1, 1, 1, float(cfg.get("flash_alpha", 0.85))))
	_black = _rect(Color(0, 0, 0, 0))
	title = Label.new()
	title.text = str(cfg.get("text", "Defeated"))
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ty := float(cfg.get("title_y", 0.68))
	title.anchor_top = ty - 0.1
	title.anchor_bottom = ty + 0.1
	title.offset_top = 0.0
	title.offset_bottom = 0.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_override("font", RetroUI.font())
	title.add_theme_font_size_override("font_size", int(cfg.get("title_size", 72)))
	title.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 10)
	title.modulate.a = 0.0
	_layer.add_child(title)
	_layer.move_child(_black, -1)
	if float(cfg.get("slow_scale", 1.0)) < 1.0 and not NetSession.active():
		Engine.time_scale = float(cfg.slow_scale)
		slowed = true


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(r)
	return r


func _exit_tree() -> void:
	_unslow()
	if rig != null and is_instance_valid(rig) and _cut:
		rig.call("clear_override")
	if _avatar != null and is_instance_valid(_avatar):
		_avatar.call("set_first_person", _was_first)


func _unslow() -> void:
	if slowed:
		Engine.time_scale = 1.0
		slowed = false


func _process(dt: float) -> void:
	step(dt / Engine.time_scale if Engine.time_scale > 0.0 else dt)   # unscaled: the slow motion does not stretch the shot


## Advance by `dt` real seconds (the frame does this; traces call it directly).
func step(dt: float) -> void:
	if _clearing >= 0.0:
		_clearing += dt
		var k := clampf(_clearing / float(cfg.get("clear_s", 0.7)), 0.0, 1.0)
		_black.color.a = 1.0 - k
		if k >= 1.0:
			queue_free()
		return
	t += dt
	_flash.color.a = float(cfg.get("flash_alpha", 0.85)) * clampf(1.0 - t / float(cfg.get("flash_s", 0.18)), 0.0, 1.0)
	if slowed and t >= float(cfg.get("slow_s", 0.45)):
		_unslow()
	if t >= float(cfg.get("cut_at", 0.45)):
		_overhead()
	else:
		_flash_shot()
	var title_at := float(cfg.get("title_at", 0.75))
	title.modulate.a = clampf((t - title_at) / maxf(float(cfg.get("title_fade", 0.5)), 0.01), 0.0, 1.0)
	var black_from := float(cfg.get("black_from", 3.0))
	_black.color.a = clampf((t - black_from) / maxf(total() - black_from, 0.01), 0.0, 1.0)
	if t >= total() and not finished:
		finished = true
		done.emit()


## The ground's up where you fell (a round planet's, not the world's).
func _up() -> Vector3:
	var tilt = player.get("tilt")
	return (tilt as Basis).y.normalized() if tilt is Basis else Vector3.UP


func _ok() -> bool:
	return rig != null and is_instance_valid(rig) and player != null and is_instance_valid(player)


## Your body shows in third person for the shot (first person draws it as a shadow).
func _show_body() -> void:
	if _avatar != null:
		return
	var kit := player.get_node_or_null("PlayerKit")
	_avatar = kit.get("avatar") if kit != null else null
	if _avatar != null and _avatar.has_method("set_first_person"):
		_was_first = bool(_avatar.get("first_person"))
		_avatar.call("set_first_person", false)


## The flash frame: close on you from the side, a little above, as you start to go.
func _flash_shot() -> void:
	if not _ok():
		return
	_show_body()
	var up := _up()
	var at := body_point()
	if _phase != "flash":
		var r: Vector3 = player.global_basis.x
		_side = (r - up * r.dot(up)).normalized()
	var pos := at + _side * float(cfg.get("flash_side", 2.4)) + up * float(cfg.get("flash_up", 0.9)) \
		- (player.global_basis.z - up * player.global_basis.z.dot(up)).normalized() * 0.8
	var xf := Transform3D(Basis.looking_at(at - pos, up), pos)
	_place(xf, "flash", float(cfg.get("flash_fov", 50.0)))


func _place(xf: Transform3D, phase: String, fov: float) -> void:
	if _phase != phase:
		_phase = phase
		_cut = true
		rig.call("snap_override", xf, fov)       # a cut, not a glide
	else:
		rig.call("set_override", xf, fov)


## The camera high over the body, looking down at it, rising and turning slowly.
func _overhead() -> void:
	if not _ok():
		return
	_show_body()
	var up := _up()
	var at := body_point()
	if _phase != "above":
		var cam: Camera3D = rig.call("camera")
		var from := cam.global_position - at if cam != null else Vector3.BACK
		from -= up * from.dot(up)
		_back = from.normalized() if from.length() > 0.01 else (player.global_basis.z - up * player.global_basis.z.dot(up)).normalized()
	var since := t - float(cfg.get("cut_at", 0.45))
	var turn := Basis(up, deg_to_rad(float(cfg.get("orbit_deg_s", 9.0)) * since))
	var pos := at + up * (float(cfg.get("height", 6.5)) + float(cfg.get("rise", 0.45)) * since) \
		+ turn * _back * float(cfg.get("back", 2.5))
	var xf := Transform3D(Basis.looking_at(at - pos, turn * -_back), pos)
	_place(xf, "above", float(cfg.get("fov", 55.0)))


## Where the body is: the ragdoll's pelvis (PlayerKit's avatar), else the player.
func body_point() -> Vector3:
	var kit := player.get_node_or_null("PlayerKit")
	if kit != null and kit.get("avatar") != null:
		var j: Dictionary = kit.avatar.joints
		if j.has("pelvis") and is_instance_valid(j.pelvis):
			return (j.pelvis as Node3D).global_position
	return player.global_position


## After the respawn: the camera goes back to you and the black lifts, then the
## shot frees itself.
func clear() -> void:
	_unslow()
	title.visible = false
	_flash.color.a = 0.0
	_black.color.a = 1.0
	if rig != null and is_instance_valid(rig) and _cut:
		rig.call("clear_override")
		rig.set("_override_blend", 0.0)     # a cut back to you, not a swoop down
		_cut = false
	if _avatar != null and is_instance_valid(_avatar):
		_avatar.call("set_first_person", _was_first)
	_avatar = null
	_clearing = 0.0
