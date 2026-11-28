extends SceneTree
## Issue #175: stills and a clip of a sandstorm in the real town (its look, the
## town's fixed review cameras from content/look/town_shots.json). Not CI.
##
## Needs a real renderer (not --headless); see tools/storm/shoot_storm.sh.
## User args (after "--"):
##   mode=stills  shots=gate_approach,desert_look_back  levels=0,0.5,1
##   mode=clip    shots=gate_approach  clear_s=2 build_s=10 full_s=6 fade_s=6 pan_deg=6
##   out=res://test_results/storm   warm=90 (frames before the first picture)
## A clip runs the storm on a fast clock (build_s etc. are the clip's seconds, not
## the game's) while the dust and sand run at their real speed. Frames are PNGs in
## out/clip/; tools/storm/shoot_storm.sh makes the mp4 with ffmpeg.

var demo
var args := {}
var out := "res://test_results/storm"
var jobs: Array = []           ## stills: [shot, level]
var frame := 0
var warm := 90
var _job := -1
var _wait := 0
var _clip := {}
var _clip_frame := 0
var _clip_frames := 0
var _shot_basis := Basis.IDENTITY


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	out = str(args.get("out", out))
	warm = int(args.get("warm", "90"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "/clip"))
	WorldState.reset()
	GameFlow.reset()
	GameFlow.change_scene = func(_p: String) -> void: pass
	get_root().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	demo = load("res://scenes/town_demo.gd").new()
	demo.lookdev_mode = true
	demo.npc_brains = false
	get_root().add_child(demo)


func _process(dt: float) -> bool:
	frame += 1
	if frame == 2:
		_plan()
	if frame == warm - 1 and demo.storm == null:
		demo._add_storm()            # lookdev_mode stops its build before the storm step
		if demo.storm != null:
			demo.storm.set_process(false)
	if frame < warm or demo.storm == null:
		if frame > warm + 600:
			print("STORM SHOOT: no storm on this planet")
			quit(1)
		return false
	if str(args.get("mode", "stills")) == "clip":
		return _clip_step(dt)
	return _still_step()


func _plan() -> void:
	var shots: PackedStringArray = str(args.get("shots", "gate_approach")).split(",")
	for s in shots:
		for l in str(args.get("levels", "0,1")).split(","):
			jobs.append([s, float(l)])
	if demo.storm != null:
		demo.storm.set_process(false)


func _set_level(level: float) -> void:
	var st = demo.storm
	st.ramp = level
	st.level = smoothstep(0.0, 1.0, level)
	st.seen = st.level
	st._draw()


func _still_step() -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var j: Array = jobs[_job]
			var path := "%s/%s_storm%d.png" % [out, j[0], roundi(float(j[1]) * 100.0)]
			get_root().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("STORM SHOOT: ", path)
		return false
	_job += 1
	if _job >= jobs.size():
		print("STORM SHOOT: done")
		quit()
		return true
	var j: Array = jobs[_job]
	demo.show_shot(str(j[0]))
	_set_level(float(j[1]))
	_wait = int(args.get("frames", "40"))      # the dust fills in, the shadows settle
	return false


## The storm on the clip's clock: clear, build, full, fade, a little clear again.
func _clip_step(dt: float) -> bool:
	if _clip.is_empty():
		_clip = { "clear": float(args.get("clear_s", "2")), "build": float(args.get("build_s", "10")),
			"full": float(args.get("full_s", "6")), "fade": float(args.get("fade_s", "6")), "after": float(args.get("after_s", "1.5")) }
		var total: float = _clip.clear + _clip.build + _clip.full + _clip.fade + _clip.after
		_clip_frames = roundi(total / maxf(dt, 0.001))
		demo.show_shot(str(args.get("shots", "gate_approach")).split(",")[0])
		_shot_basis = demo.camera.global_basis
		_set_level(0.0)
		print("STORM SHOOT: clip of %d frames" % _clip_frames)
		return false
	var t := _clip_frame * dt
	var lv := 0.0
	var a: float = _clip.clear
	if t < a:
		lv = 0.0
	elif t < a + _clip.build:
		lv = (t - a) / _clip.build
	elif t < a + _clip.build + _clip.full:
		lv = 1.0
	elif t < a + _clip.build + _clip.full + _clip.fade:
		lv = 1.0 - (t - a - _clip.build - _clip.full) / _clip.fade
	_set_level(lv)
	# A slow pan across the shot, so the blowing dust reads as moving air.
	var pan := deg_to_rad(float(args.get("pan_deg", "6"))) * (t / maxf(0.1, _clip_frames * dt) - 0.5)
	var up: Vector3 = _shot_basis.y
	demo.camera.global_basis = Basis(up, -pan) * _shot_basis
	if _clip_frame > 0:
		var path := "%s/clip/f%05d.png" % [out, _clip_frame - 1]
		get_root().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		if _clip_frame % 30 == 0:
			print("STORM SHOOT: frame %d / %d  level %.2f  state %s" % [_clip_frame, _clip_frames, lv, demo.storm.state])
	_clip_frame += 1
	if _clip_frame > _clip_frames:
		print("STORM SHOOT: done")
		quit()
		return true
	return false
