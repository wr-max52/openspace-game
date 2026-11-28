extends Node
## The opening cutscene's shots, filmed in-engine (v2: the one-minute cut).
## `-- shot=N [still=T] [fps=30] [res=720]`: films shot N into test_results/cine2/sN/,
## one fixed 1/60 s game step per frame (run Godot with --fixed-fps 60, see clip.sh);
## still=T saves only the frame T seconds in. Every shot runs PRE seconds of game
## first (smoke trails, walks and crowds settle).
##
## Smooth by construction: every camera is a keyframed path (Hermite, eased at its
## ends), never glued to a body; where it must follow someone it follows a damped
## point. The crashing ship flies its own straight track across each exterior shot,
## placed from that shot's framing, so it always reads in the sky.

const BOOT := 420
const STEP := 4
const PRE := 2.0
## Shots whose ground needs longer to build before the first frame (the wreck's far sand).
const PRE_AT := {}
const OUT := "res://test_results/cine2/s%d/%s.png"
const FONT := "res://assets/fonts/AnonymousPro-Bold.ttf"

## Each shot's action is authored in its own time (u, the v2 timings); TS slows it
## down (camera, ship, walkers, the race all together) and TAIL adds a last push in
## on the ship after the action (PUSH seconds), then holds on it, following it, for
## the rest of the tail. A shot runs BASE * TS + TAIL seconds.
const BASE := { 1: 10.0, 2: 4.0, 3: 4.0, 4: 2.6, 5: 3.0, 6: 5.0, 7: 6.0, 8: 4.0, 9: 3.0,
	10: 6.0, 11: 1.0, 12: 3.0, 13: 2.5, 14: 2.0, 15: 2.0, 16: 4.5 }
const TS := { 1: 1.0, 2: 1.3, 3: 1.15, 4: 1.4, 5: 1.25, 6: 1.35, 7: 1.2, 8: 1.5, 9: 1.1,
	10: 1.3, 11: 1.5, 12: 1.2, 13: 1.3, 14: 1.35, 15: 1.35, 16: 1.25 }
const TAIL := { 1: 3.8, 2: 2.6, 5: 2.5, 6: 2.5, 7: 2.4, 13: 2.5, 15: 2.4, 16: 5.0 }
const PUSH := 1.4
## Shots whose push takes longer than PUSH (the long lens in space).
const PUSH_AT := { 1: 2.4 }
## The spoken lines (Oda's voiceover and the dialogue), shown as subtitles timed to
## the recorded clips' speech (voice.py writes vo/spans.json).
const PUSH_MIN := { 1: 0.045 }
## Shot 8's orbit framing: the lens's start and end (metres from the wreck: height,
## sunward, sideways); each cruiser on a line of sight tipped up off the wreck's
## (degrees up, degrees round, metres out); the aim's tip up off the wreck; the lens.
const ORBIT := { "h0": 2600.0, "d0": 2000.0, "s0": 300.0, "h1": 2100.0, "d1": 1550.0, "s1": 220.0,
	"c0": Vector3(21.5, 7.0, 3600.0), "c1": Vector3(25.0, -9.0, 5000.0),
	"aim": 11.0, "f0": 46.0, "f1": 42.0, "max_sun": 0.85 }
## Shot 10: where the dark master stands behind the general (cruiser frame), the
## way he faces, and his arms (CharacterKit's parade rest: hands behind the back).
const DM_AT := Vector3(27.5, 58.0, 217.6)
const DM_FACE := Vector3(30.3, 58.0, 223.4)
const DM_POSE := { "chest": Vector3(-4, 0, 0), "head": Vector3(-6, 0, 0),
	"l_shoulder": Vector3(22, 165, 12), "r_shoulder": Vector3(22, -165, -12),
	"l_elbow": Vector3(-95, 0, 0), "r_elbow": Vector3(-95, 0, 0) }
## Shot 7: how wide the two survivors swerve round the wreck (m), over how much of
## the course (m), and how quickly they start to (u); where the camera turns to
## follow them (u) and its lens on them.
const DODGE := { "amp": [9.0, 10.0], "width": 18.0, "ramp": 0.35, "follow_u": 3.55, "follow_s": 0.9, "fov": 12.0 }
const LINES := "res://tools/opening/lines.json"
const SPANS := "res://test_results/cine2/vo/spans.json"

var shot := 0
var still := -1.0
var secs := 3.0
var demo
var sv: SubViewport
var cam: Camera3D
var rcam: Camera3D              ## the root viewport's camera, kept on ours (culling, fog, sky read it)
var caption: Label
var n := 0
var fi := -1
var lead := 0
var clock := 0.0
var _cycle := 0
var _sub := 0
var steps_per := 1            ## game steps per saved frame (2 = 30 fps)
var res_h := 1080
var _last := PackedByteArray()
var _retries := 0
var _log: FileAccess
var cast: Dictionary = {}       ## name -> NpcBody we drive
var v: Dictionary = {}          ## per-shot scratch
var sp                          ## PlanetSphere
var pilot
var ship: Node3D                ## the player's ship look, placed by hand
var keys: Array = []            ## this shot's camera: [t, eye, target, fov]
var up := Vector3.UP            ## this shot's camera up
var ts := 1.0                   ## this shot's slow-down (TS)
var captions: Array = []        ## [from, to, text] in shot seconds


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			shot = int(a.substr(5))
		elif a.begins_with("still="):
			still = float(a.substr(6))
		elif a.begins_with("fps="):
			steps_per = 60 / int(a.substr(4))
		elif a.begins_with("res="):
			res_h = int(a.substr(4))
	ts = TS.get(shot, 1.0)
	secs = BASE.get(shot, 3.0) * ts + TAIL.get(shot, 0.0)
	_load_captions()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results/cine2/s%d" % shot))
	_log = FileAccess.open("res://test_results/cine2/log_s%d.txt" % shot, FileAccess.WRITE)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var gf = load("res://src/systems/flow/game_flow.gd")
	gf.resumed = true
	gf.planet_id = ""
	gf.change_scene = func(_p: String) -> void: pass
	load("res://src/systems/llm/disclaimers.gd").launch_shown = true
	demo = load("res://scenes/town_demo.gd").new()
	demo.preset = "golden"
	demo.npc_brains = false
	demo.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(demo)
	sv = SubViewport.new()
	sv.size = Vector2i(res_h * 16 / 9, res_h)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.msaa_3d = Viewport.MSAA_4X
	sv.use_taa = false
	sv.use_debanding = true
	add_child(sv)
	cam = Camera3D.new()
	cam.far = 200000.0
	cam.near = 0.1
	sv.add_child(cam)
	cam.current = true
	rcam = Camera3D.new()
	rcam.far = 200000.0
	add_child(rcam)
	_build_caption()


func _build_caption() -> void:
	var layer := CanvasLayer.new()
	sv.add_child(layer)
	caption = Label.new()
	var ls := LabelSettings.new()
	ls.font = load(FONT)
	ls.font_size = int(res_h * 0.034)
	ls.font_color = Color(0.96, 0.94, 0.9)
	ls.outline_size = int(res_h * 0.006)
	ls.outline_color = Color(0, 0, 0, 0.75)
	ls.shadow_size = int(res_h * 0.01)
	ls.shadow_color = Color(0, 0, 0, 0.45)
	caption.label_settings = ls
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.size = Vector2(res_h * 16 / 9 * 0.8, res_h * 0.2)
	caption.position = Vector2(res_h * 16 / 9 * 0.1, res_h * 0.72)
	caption.modulate.a = 0.0
	layer.add_child(caption)


## Every line in this shot, a caption per spoken sentence when the clip's pauses
## match its sentences (else one for the line). Dialogue in quotes.
func _load_captions() -> void:
	var lines = JSON.parse_string(FileAccess.get_file_as_string(LINES))
	var spans = JSON.parse_string(FileAccess.get_file_as_string(SPANS)) if FileAccess.file_exists(SPANS) else {}
	var rx := RegEx.new()
	rx.compile("[^.!?]+[.!?]+")
	for ln in lines.lines:
		var at := float(ln.at)
		# A line with a negative start begins over the end of the shot before.
		if int(ln.shot) == shot + 1 and at < 0.0:
			at += secs
		elif int(ln.shot) != shot:
			continue
		var text: String = ln.text
		var sp: Array = spans.get(ln.id, [[0.0, 3.0]])
		var parts := []
		for m in rx.search_all(text):
			parts.append(m.get_string().strip_edges())
		if parts.size() != sp.size():
			parts = [text]
			sp = [[sp[0][0], sp[sp.size() - 1][1]]]
		for i in parts.size():
			var tx: String = parts[i]
			if str(ln.id).begins_with("d"):
				tx = "\"%s\"" % tx
			captions.append([at + float(sp[i][0]) + 0.05, at + float(sp[i][1]) - 0.1, tx])


func _caption(t: float) -> void:
	caption.modulate.a = 0.0
	for c in captions:
		if t >= c[0] - 0.25 and t <= c[1] + 0.25:
			caption.text = c[2]
			caption.modulate.a = clampf(minf(t - (c[0] - 0.25), c[1] + 0.25 - t) / 0.25, 0.0, 1.0)


func say(s: String) -> void:
	print("CINE ", s)
	_log.store_line(s)
	_log.flush()


func _process(_dt: float) -> void:
	n += 1
	if n < BOOT:
		get_tree().paused = false
		return
	if n == BOOT:
		for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if not sv.is_ancestor_of(c):
				c.visible = false
		sp = demo.terrain.sphere if demo.terrain != null and "sphere" in demo.terrain else null
		pilot = demo.pilot
		_setup()
		var pre: float = PRE_AT.get(shot, PRE)
		clock = -pre
		lead = int((pre + maxf(still, 0.0)) * 60.0)
		return
	if lead > 0:
		lead -= 1
		get_tree().paused = false
		_direct(clock / ts)
		_place_camera(clock)
		clock += 1.0 / 60.0
		if lead == 0:
			fi = int(maxf(still, 0.0) * 60.0)
		return
	if _sub < steps_per:
		get_tree().paused = false
		_direct(float(fi + _sub) / 60.0 / ts)
		_sub += 1
		return
	get_tree().paused = true
	_hide_speech()
	_place_camera(float(fi + steps_per - 1) / 60.0)
	_caption(float(fi + steps_per - 1) / 60.0)
	_cycle += 1
	if _cycle < STEP - 1:
		return
	RenderingServer.force_draw(false)
	var img := sv.get_texture().get_image()
	var data := img.get_data()
	if data == _last and _retries < 8:
		_retries += 1
		return
	img.save_png(ProjectSettings.globalize_path(OUT % [shot, ("still_%.2f" % still) if still >= 0.0 else "f%04d" % (fi / steps_per)]))
	_last = data
	_retries = 0
	_cycle = 0
	_sub = 0
	if still >= 0.0:
		say("saved still")
		get_tree().quit()
		return
	fi += steps_per
	if fi % 60 == 0:
		say("frame %d / %d" % [fi, int(secs * 60.0)])
	if fi >= int(secs * 60.0):
		get_tree().quit()


## Speech shows as subtitles in the cut, not over heads.
func _hide_speech() -> void:
	for l: Label3D in demo.find_children("*", "Label3D", true, false):
		if l.visible and l.get_parent() is NpcBody:
			l.visible = false


# ------------------------------------------------------------------ helpers

func _spawn(key: String, soldier: String, at: Vector3, yaw: float) -> NpcBody:
	var cc = demo._content()
	var npc: NpcBody = demo.make_npc(cc.get_soldier(soldier), at, yaw, "cine_" + key, "")
	npc.target = null
	npc.nav = null
	npc.free_walk = true
	npc.home_target = rcam
	# Aboard the cruiser the town's Npcs node is hidden: the bridge cast stand outside it.
	if shot >= 8 and shot <= 10 and npc.get_parent() != null and not npc.get_parent().is_visible_in_tree():
		npc.reparent(demo, true)
	cast[key] = npc
	return npc


func _walk_speed(npc: NpcBody, mps: float) -> void:
	if npc.controller != null and "walk_speed" in npc.controller:
		npc.controller.walk_speed = mps / ts


func _hide_player() -> void:
	var pl: Node3D = demo._player
	pl.visible = false
	if demo.player_kit != null:
		for c in demo.player_kit.find_children("*", "Node3D", true, false):
			(c as Node3D).visible = false


func _put_player(at: Vector3) -> void:
	var pl: CharacterBody3D = demo._player
	pl.global_position = at
	pl.velocity = Vector3.ZERO


func _surf(mx: float, mz: float) -> Vector3:
	return sp.surface_at(mx, mz) if sp != null else Vector3(mx, 0, mz)


func _upv(p: Vector3) -> Vector3:
	return sp.up_at(p) if sp != null else Vector3.UP


func _flat(d: Vector3, at: Vector3) -> Vector3:
	var u := _upv(at)
	return (d - u * d.dot(u)).normalized()


## Right, up and forward of a camera at `eye` looking at `target`.
func _frame_of(eye: Vector3, target: Vector3, u: Vector3) -> Array:
	var f := (target - eye).normalized()
	var r := f.cross(u).normalized()
	return [r, r.cross(f).normalized(), f]


## A point given in a framing's own metres: x right, y up, z forward.
func _rel(eye: Vector3, target: Vector3, u: Vector3, x: float, y: float, z: float) -> Vector3:
	var b := _frame_of(eye, target, u)
	return eye + b[0] * x + b[1] * y + b[2] * z


func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Everyone in sight gets their own clock: no crowd idles, sways or dances in step.
func _stagger() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for b: NpcBody in demo.find_children("*", "NpcBody", true, false):
		if b.anim != null:
			b.anim.time += rng.randf_range(0.0, 40.0)
			b.anim.dance_time += rng.randf_range(0.0, 10.0)
			b.anim.phase += rng.randf_range(0.0, TAU)


## Space: the sky follows our camera, not the player on the ground.
func _space_sky() -> void:
	if pilot == null or pilot.sky == null or sp == null:
		return
	pilot.sky._applied = -1.0
	pilot.sky.update_for(sp.altitude(cam.global_position), cam.global_position)
	if demo.detail != null:
		demo.detail.update_for(sp.altitude(cam.global_position))


## The ship's look, out of the pilot's hands: the damaged hull, engines lit, smoking.
## `big` scales the smoke for ships seen far off.
func _take_ship(big := 1.0) -> void:
	pilot.process_mode = Node.PROCESS_MODE_DISABLED
	ship = pilot.visual
	pilot._set_hull(false)
	WreckLook.apply(ship)
	ShipKit.throttle_flames(ship, 0.55, false, 0.0)
	var length: float = pilot._look_length()
	v.ship_len = length
	v.smoke = ExplosionFx.smoke_trail(ship, Vector3(0.0, 0.4, length * 0.42), 0.9 * big, 110, 5.0)
	v.smoke2 = ExplosionFx.smoke_trail(ship, Vector3(length * 0.18, 0.2, length * 0.2), 1.0 * big, 50, 3.5)
	if big > 1.0:
		v.smoke.scale_amount_min = 1.2 * big
		v.smoke.scale_amount_max = 1.8 * big


func _ship_at(at: Vector3, dir: Vector3, u: Vector3, roll := 0.0) -> void:
	var b := Basis.looking_at(dir, u)
	b = b.rotated(dir.normalized(), roll)
	ship.global_transform = Transform3D(b, at)


## The ship on its track for this shot: v.ship_a at v.ship_t0, v.ship_b at v.ship_t1,
## straight and steady (a slow, small wallow), nose along the track.
func _fly_ship(t: float) -> void:
	if ship == null or not v.has("ship_a"):
		return
	var t0: float = v.get("ship_t0", 0.0)
	var t1: float = v.get("ship_t1", secs)
	var k := (t - t0) / (t1 - t0)
	if v.has("ship_ease") and k > 0.0:
		# Gliding in slow past the lens, then gathering speed down the dive.
		k = v.ship_ease * k + (1.0 - v.ship_ease) * k * k
	var a: Vector3 = v.ship_a
	var b: Vector3 = v.ship_b
	var at := a.lerp(b, k)
	var dir := (b - a).normalized()
	_ship_at(at, dir, _upv(at), 0.22 + 0.08 * sin(t * 1.3))


## A damped point: chases `target` at `rate` per second (a camera's aim, never a body).
func _follow(key: String, target: Vector3, rate := 3.0) -> Vector3:
	var cur: Vector3 = v.get(key, target)
	cur = cur.lerp(target, 1.0 - exp(-rate / 60.0))
	v[key] = cur
	return cur


# ------------------------------------------------------------------ the camera path

## This shot's keys at time t: Hermite through every key, still at the first and
## last (eased in and out), smooth through the middle ones.
func _path(t: float) -> Array:
	var nk := keys.size()
	if nk == 1 or t <= keys[0][0]:
		return [keys[0][1], keys[0][2], keys[0][3]]
	if t >= keys[nk - 1][0]:
		return [keys[nk - 1][1], keys[nk - 1][2], keys[nk - 1][3]]
	var i := 0
	while keys[i + 1][0] < t:
		i += 1
	var t0: float = keys[i][0]
	var t1: float = keys[i + 1][0]
	var s := (t - t0) / (t1 - t0)
	var out := []
	for j in [1, 2, 3]:
		var p0 = keys[i][j]
		var p1 = keys[i + 1][j]
		var m0 = p0 * 0.0
		var m1 = p0 * 0.0
		if i > 0:
			m0 = (p1 - keys[i - 1][j]) / (t1 - keys[i - 1][0]) * (t1 - t0)
		if i + 2 < nk:
			m1 = (keys[i + 2][j] - p0) / (keys[i + 2][0] - t0) * (t1 - t0)
		var s2 := s * s
		var s3 := s2 * s
		out.append(p0 * (2 * s3 - 3 * s2 + 1) + m0 * (s3 - 2 * s2 + s) + p1 * (-2 * s3 + 3 * s2) + m1 * (s3 - s2))
	return out


func _look(at: Vector3, target: Vector3, u := Vector3.UP, fov := 50.0) -> void:
	cam.fov = fov
	cam.global_position = at
	if (target - at).normalized().cross(u).length() < 0.01:
		u = Vector3.FORWARD
	cam.look_at(target, u)


# ------------------------------------------------------------------ setup

func _setup() -> void:
	say("setup shot %d player %s" % [shot, demo._player.global_position])
	_hide_player()
	if sp != null:
		demo.terrain.follow_camera(func(): return cam.global_position)
	match shot:
		1:
			_setup_space()
		2:
			_setup_wreck()
		3, 4:
			_setup_nomad()
		5:
			_setup_barge()
		6:
			_setup_outpost()
		7:
			_setup_race()
		8, 9, 10:
			_setup_cruiser()
		11, 12, 13:
			_setup_cantina()
		14, 15:
			_setup_walk()
		16:
			_setup_pit()
	say("cast %s keys %d" % [str(cast.keys()), keys.size()])


## Shot 1, one move: the stars, a tilt down onto the planet with the Remnant's
## cruiser hanging over it, a slow push in, and the ship streaks in past us, over
## the cruiser and on down toward the ball.
func _setup_space() -> void:
	var cr = demo.cruiser
	var c: Vector3 = sp.center
	var C: Vector3 = _sunlit_cruiser()
	var uc := (C - c).normalized()
	var sun: Vector3 = demo.look.sun_dir.normalized()
	var side := uc.cross(sun).normalized()
	var sunward := (sun - uc * sun.dot(uc)).normalized()
	_put_player(cr.frame * Vector3(0, 58.6, 250))
	# Out above the cruiser, the sun over our shoulder: it hangs against the lit
	# planet with the terminator beyond.
	var eye: Vector3 = C + uc * 1500.0 + side * 420.0 + sunward * 380.0
	var aim: Vector3 = C + (c - C).normalized() * 260.0
	var b := _frame_of(eye, aim, uc)
	var stars: Vector3 = eye + (aim - eye).rotated(b[0], deg_to_rad(70.0))
	var eye2: Vector3 = eye.lerp(C, 0.18)
	up = uc
	keys = [[0.0, eye, stars, 44.0], [0.9, eye, stars, 44.0], [4.6, eye.lerp(eye2, 0.3), aim, 42.0], [10.0, eye2, aim, 40.0]]
	v.space = true
	_take_ship()
	# From just behind our right shoulder (where the lens is when it comes), close
	# past us and away into the frame, over the cruiser and down at the planet.
	var at_pass: Vector3 = eye.lerp(eye2, 0.32)
	v.ship_a = _rel(at_pass, aim, uc, 8.0, -2.5, -15.0)
	v.ship_b = _rel(at_pass, aim, uc, 60.0, -150.0, 2200.0)
	v.ship_t0 = 4.9
	v.ship_t1 = 20.0
	v.ship_ease = 0.6
	say("cruiser %s eye %s dist %.0f" % [C, eye, eye.distance_to(C)])


## The cruiser's hull, moved for the exterior shots to hang over the sunlit side
## near the terminator (its real orbit is over the night side at golden hour).
## Returns its middle.
func _sunlit_cruiser() -> Vector3:
	var cr = demo.cruiser
	var c: Vector3 = sp.center
	var sun: Vector3 = demo.look.sun_dir.normalized()
	var port_up := (_surf(0.0, 0.0) - c).normalized()
	var rd := (sun * 0.55 + port_up * 0.45).normalized()
	var pos: Vector3 = c + rd * (sp.radius + 7000.0)
	var sw := (sun - rd * sun.dot(rd)).normalized()
	var fwd := rd.cross(sw).normalized()          # starboard (+x) faces the sun
	var bas := Basis.looking_at(fwd, rd)
	# In the cruiser's own frame z runs bow to stern, so its bow is -z.
	var fr := Transform3D(bas, pos)
	cr._hull.transform = fr
	v.cr_frame = fr
	return fr * Vector3(0, 30, -20)


## Shot 2: down on the sand under the buried star cruiser; the camera cranes up its
## hull as the ship streaks over, smoking.
func _setup_wreck() -> void:
	var at := _surf(1350.0, -120.0)
	var best: Node3D = null
	for w in demo.find_children("*", "Node3D", true, false):
		if w is StarcruiserWreck and (best == null or w.global_position.distance_to(at) < best.global_position.distance_to(at)):
			best = w
	var wc: Vector3 = best.global_position if best != null else at
	say("wreck %s (%s) %.0f m from the landmark" % [wc, best, wc.distance_to(at)])
	var g := _surf(0.0, 0.0)
	var u := _upv(wc)
	var to_port := _flat(g - wc, wc)
	var side := to_port.cross(u).normalized()
	var e0: Vector3 = wc + to_port * 300.0 + side * 140.0
	e0 = sp.surface_at_dir((e0 - sp.center).normalized()) if sp.has_method("surface_at_dir") else e0
	e0 += u * 12.0         # over the near dune's crest (a hard seam in the sand from lower)
	_put_player(e0 + u * 1.0)
	var t0: Vector3 = wc + u * 40.0
	var e1: Vector3 = e0 + u * 34.0 - to_port * 40.0
	up = u
	keys = [[0.0, e0, t0, 52.0], [4.0, e1, wc + u * 70.0, 48.0]]
	_take_ship(2.5)
	v.ship_a = _rel(e0, t0, u, -190.0, 150.0, 260.0)
	v.ship_b = _rel(e0, t0, u, 170.0, 105.0, 210.0)
	v.ship_t0 = -0.6
	v.ship_t1 = 4.4


## Shots 3 and 4: a Red Wind nomad walks out of camp toward the camera, stops and
## looks up; the camera tilts with him to the ship. Then his view, a slow push in.
func _setup_nomad() -> void:
	var pk: Dictionary = demo.natives.pack("red_wind")
	var camp: Vector3 = pk.camp.center
	var u := _upv(camp)
	demo.natives.set_physics_process(false)
	var lead_npc = demo.natives.leader(pk)
	var npc: NpcBody = null
	for mm in pk.members:
		if mm.npc != lead_npc and not bool(mm.get("child", false)) and is_instance_valid(mm.npc):
			npc = mm.npc
			break
	if npc == null:
		npc = lead_npc
	for st in npc.find_children("Standard*", "Node3D", true, false):
		st.visible = false
	npc.process_mode = Node.PROCESS_MODE_INHERIT
	npc.home_target = rcam
	cast.nomad = npc
	_walk_speed(npc, 1.25)
	# Toward the port, away from camp: the camp stays behind him.
	var out := _flat(-camp, camp)
	var side := out.cross(u).normalized()
	var a: Vector3 = camp + out * 16.0 + side * 2.0
	var stop_at: Vector3 = a + out * 4.2
	var eye: Vector3 = a + out * 10.5 + side * 1.4 + u * 0.9
	_put_player(eye + u)
	npc.global_position = a + u * 0.3
	npc.go_to(stop_at)
	v.stop_at = stop_at
	v.out = out
	v.u = u
	var chest0: Vector3 = a + u * 1.3
	v.eye = eye
	up = u
	# Where he looks: up and over the camera's right, the ship crossing.
	var sky_dir: Vector3 = (-out * 0.55 + u * 0.8 + side * 0.15).normalized()
	_take_ship(1.6)
	if shot == 3:
		var sky_pt: Vector3 = eye + sky_dir * 300.0
		v.ship_a = sky_pt - side * 210.0 + u * 40.0
		v.ship_b = sky_pt + side * 150.0 - u * 20.0
		v.ship_t0 = 0.0
		v.ship_t1 = 4.6
		v.chest0 = chest0
		keys = [[0.0, eye, chest0, 40.0]]
	else:
		# His eyes, the moment after: the ship further on, a long lens pushing in.
		var head: Vector3 = stop_at + u * 1.7
		npc.global_position = stop_at + u * 0.3
		npc.stop()
		var look_pt: Vector3 = head + sky_dir.rotated(u, deg_to_rad(-25.0)) * 330.0
		var sd := (look_pt - head).cross(u).normalized()
		v.ship_a = look_pt + sd * -40.0
		v.ship_b = look_pt + sd * 70.0 - u * 55.0 + (look_pt - head).normalized() * 60.0
		v.ship_t0 = 0.0
		v.ship_t1 = 2.6
		v.head = head
		keys = [[0.0, head, look_pt, 24.0]]
	say("camp %s nearest outpost %s" % [camp, _nearest_outpost(camp)])


func _nearest_outpost(p: Vector3) -> String:
	var best := ""
	var bd := INF
	for o in demo.outposts.outposts:
		var w: Vector3 = demo.outposts.world_point(o, Vector3.ZERO)
		if w.distance_to(p) < bd:
			bd = w.distance_to(p)
			best = "%s %.0f m" % [o.id, bd]
	return best


## Shot 5: the party barge parked on the dunes, the party on its decks; the
## ship passes over and the camera trucks along her side.
func _setup_barge() -> void:
	var bg = demo.barge
	var bp: Vector3 = bg.global_position
	var u := _upv(bp)
	var hd: Vector3 = _flat(bg.heading, bp)
	var side := hd.cross(u).normalized()
	var e0: Vector3 = bp + hd * 40.0 + side * 30.0 + u * 13.0
	var e1: Vector3 = bp + hd * 26.0 + side * 36.0 + u * 15.0
	_put_player(bp + side * 20.0 + u)
	up = u
	var tg: Vector3 = bp + u * 9.0 + hd * 2.0
	keys = [[0.0, e0, tg, 46.0], [3.0, e1, tg - hd * 6.0, 46.0]]
	_take_ship(1.8)
	v.ship_a = _rel(e0, tg, u, 220.0, 150.0, 340.0)
	v.ship_b = _rel(e0, tg, u, -200.0, 115.0, 300.0)
	v.ship_t0 = -0.2
	v.ship_t1 = 3.4


## Shot 6: wide on the Remnant outpost and its refinery, pushing in to the gate,
## where the trooper turns a local back, then shoots him.
func _setup_outpost() -> void:
	var o: Dictionary = demo.outposts.outpost("remnant_outpost_near")
	var W := func(l: Vector3) -> Vector3: return demo.outposts.world_point(o, l)
	v.W = W
	var u := _upv(W.call(Vector3.ZERO))
	_put_player(W.call(Vector3(34, 0, 14)) + u)
	var tr := _spawn("trooper", "outpost_trooper", W.call(Vector3(20.5, 0.0, 1.5)) + u * 0.1, 0.0)
	tr.face_point(W.call(Vector3(40, 1.5, 0)))
	var lo := _spawn("local", "local_resident", W.call(Vector3(29.0, 0.0, -3.0)) + u * 0.1, 0.0)
	_walk_speed(lo, 1.2)
	lo.go_to(W.call(Vector3(24.0, 0, -1.0)))
	up = u
	var e0: Vector3 = W.call(Vector3(62, 0, 30)) + u * 9.0
	var t0: Vector3 = W.call(Vector3(6, 0, -6)) + u * 3.0
	var e1: Vector3 = W.call(Vector3(23.2, 0, 7.4)) + u * 1.7
	var t1: Vector3 = W.call(Vector3(22.2, 0, 0.2)) + u * 1.35
	keys = [[0.0, e0, t0, 44.0], [2.4, e1, t1, 42.0], [5.0, e1 + (e1 - t1).normalized() * 0.5, t1, 42.0]]
	_take_ship(3.0)
	v.ship_a = _rel(e1, t1, u, -160.0, 215.0, 620.0)
	v.ship_b = _rel(e1, t1, u, 60.0, 165.0, 560.0)
	v.ship_t0 = 0.0
	v.ship_t1 = 5.5


## Shot 7, the Basin Run: the beast crawls across the racing line, the racers'
## outpost behind it. The race tears past the camera and swings round in front of
## its head (its body trails off the other way, so nothing ever touches it); the
## last racer puts a seeker into the leader in front of the outpost.
func _setup_race() -> void:
	var outpost := _surf(1461.0, 3616.0)
	var guess := _surf(1241.0, 3580.0)
	var d := _flat(outpost - guess, guess)
	var p0 := guess
	var u := _upv(p0)
	var side := d.cross(u).normalized()          # course right
	v.p0 = p0
	v.d = d
	v.u = u
	v.side = side
	_put_player(p0 + u * 1.0 + d * 10.0)
	var beast = demo.beast
	if beast != null:
		beast.set_physics_process(false)
		beast.heading = -side                     # crawling right to left across the line
		beast.home = beast._ground_at(p0 + d * 36.0 + side * 9.5)
		beast._seed_trail()
		beast._place(beast.home)
		beast._pose()
	v.racers = []
	var paints := ["#d8452a", "#2a6fd8", "#e2bf3a"]
	for i in 3:
		var s = SpeederNode.new()
		s.setup(demo, pilot.ground, HoverModel.load_config("racer"), true, paints[i])
		demo.add_child(s)
		var drv := _spawn("racer%d" % i, "local_racer", p0 - d * 60.0, 0.0)
		s.seat_npc(drv, "driver")
		v.racers.append(s)
	up = u
	var cam0: Vector3 = p0 - side * 15.0 + u * 0.7
	var head0: Vector3 = p0 + d * 36.0 + side * 9.5 + u * 2.6
	var far: Vector3 = p0 + d * 118.0 - side * 3.0 + u * 2.0
	keys = [[0.0, cam0, head0.lerp(outpost + u * 8.0, 0.08), 38.0], [1.2, cam0, head0.lerp(outpost + u * 8.0, 0.08), 38.0],
		[3.3, cam0 + u * 4.0 + d * 4.0, p0 + d * 70.0 + u * 2.0, 30.0], [6.0, cam0 + u * 7.0 + d * 8.0, far, 22.0]]
	_take_ship(3.0)
	v.ship_a = _rel(cam0, far, u, -90.0, 140.0, 700.0)
	v.ship_b = _rel(cam0, far, u, 30.0, 105.0, 650.0)
	v.ship_t0 = 0.0
	v.ship_t1 = 6.5


## Shots 8 to 10, the Remnant's cruiser: gliding along its hull to the bridge, then
## inside, the planet through the window and the general by it.
func _setup_cruiser() -> void:
	var c = demo.cruiser
	var L := func(l: Vector3) -> Vector3: return c.frame * l
	v.L = L
	_put_player(L.call(Vector3(0, 58.6, 250)))
	up = (c.frame.basis.y).normalized()
	v.gen_at = Vector3(28.6, 58.0, 221.0)
	if shot == 8:
		v.space = true
		_sunlit_cruiser()
		var F: Transform3D = v.cr_frame
		up = F.basis.y.normalized()
		_setup_orbit()
		return
	# The planet's warm light on him through the side window (a fill for the shot).
	var fill := OmniLight3D.new()
	fill.light_color = Color("#ffc890")
	fill.light_energy = 2.2
	fill.omni_range = 9.0
	add_child(fill)
	fill.global_position = L.call(Vector3(30.4, 60.6, 221.6))
	var rim := OmniLight3D.new()
	rim.light_color = Color("#7fb8ff")
	rim.light_energy = 1.2
	rim.omni_range = 7.0
	add_child(rim)
	rim.global_position = L.call(Vector3(26.0, 61.0, 218.5))
	var head: Vector3 = L.call(v.gen_at + Vector3(0.0, 1.62, -0.1))
	if shot == 9:
		var holo := _find_holo()
		if holo != null:
			holo.global_position = L.call(Vector3(26.0, 60.4, 218.6))
		var hc: Vector3 = L.call(Vector3(26.0, 60.4, 218.6))
		keys = [[0.0, L.call(Vector3(26.4, 60.5, 221.0)), hc, 44.0],
			[3.0, L.call(Vector3(31.4, 60.3, 227.6)), L.call(Vector3(27.6, 59.8, 220.4)), 46.0]]
	else:
		# Close on him, three-quarter, the map over his left shoulder; the guard
		# comes up into the left of frame.
		keys = [[0.0, L.call(Vector3(30.3, 59.85, 223.4)), head, 32.0],
			[6.0, L.call(Vector3(30.2, 59.85, 223.15)), head, 31.0]]


## Shot 8, from orbit: the old wreck in the sand far below, the planet's curve, and
## two Remnant cruisers hanging in orbit beyond it (the home hull and a copy of it,
## starboard to the sun); a slow push down toward the wreck.
func _setup_orbit() -> void:
	var c = demo.cruiser
	var at := _surf(1350.0, -120.0)
	var wc := at
	var sun: Vector3 = demo.look.sun_dir.normalized()
	# The wreck of the field that lies most in the sun (the port's is at golden hour).
	var best := -2.0
	for id in ["starcruiser_wreck", "starcruiser_wreck_2", "starcruiser_wreck_3", "starcruiser_wreck_4"]:
		if pilot.ground != null and StarcruiserWreck.has_wreck(pilot.ground, id):
			var o: Vector3 = StarcruiserWreck.frame(pilot.ground, id).origin
			var lit := _upv(o).dot(sun)
			say("wreck %s at %s sun %.2f" % [id, o, lit])
			if lit > best and lit < ORBIT.max_sun:
				best = lit
				wc = o
	var u := _upv(wc)
	var sf := _flat(sun, wc)                       # toward the sun along the ground
	var side := sf.cross(u).normalized()
	v.orbit_wc = wc
	# The sun over our shoulder: the wreck, the dunes and the hulls all lit.
	var e0: Vector3 = wc + u * ORBIT.h0 + sf * ORBIT.d0 + side * ORBIT.s0
	var e1: Vector3 = wc + u * ORBIT.h1 + sf * ORBIT.d1 + side * ORBIT.s1
	# Lines of sight from the lens: the wreck's, and lines tipped up off it (over
	# the planet's edge, so whatever hangs on them is against space).
	var tip := func(e: Vector3, deg: float, yaw: float) -> Vector3:
		var d: Vector3 = (wc - e).normalized()
		var r: Vector3 = d.cross(u).normalized()
		var a: Vector3 = d.rotated(r, deg_to_rad(deg))
		if a.dot(u) < d.dot(u):
			a = d.rotated(r, -deg_to_rad(deg))
		return a.rotated(u, deg_to_rad(yaw))
	var cr0: Vector3 = e0 + tip.call(e0, ORBIT.c0.x, ORBIT.c0.y) * ORBIT.c0.z
	var cr1: Vector3 = e0 + tip.call(e0, ORBIT.c1.x, ORBIT.c1.y) * ORBIT.c1.z
	var hull := func(pos: Vector3) -> Transform3D:
		var rd: Vector3 = (pos - sp.center).normalized()
		var sw: Vector3 = (sun - rd * sun.dot(rd)).normalized()
		return Transform3D(Basis.looking_at(rd.cross(sw).normalized(), rd), pos)
	c._hull.transform = hull.call(cr0)
	var twin: Node3D = c._hull.duplicate()
	c.add_child(twin)
	twin.transform = hull.call(cr1) * Transform3D(Basis(Vector3.UP, deg_to_rad(-6.0)), Vector3.ZERO)
	v.twin = twin
	up = u
	keys = [[0.0, e0, e0 + tip.call(e0, ORBIT.aim, 0.0) * 1000.0, ORBIT.f0],
		[4.0, e1, e1 + tip.call(e1, ORBIT.aim, 0.0) * 1000.0, ORBIT.f1]]
	say("orbit cruisers alt %.0f %.0f" % [sp.altitude(cr0), sp.altitude(cr1)])
	_put_player(wc + u * 400.0)
	say("orbit wreck %s cruisers %s %s eye %s alt %.0f" % [wc, cr0, cr1, e0, sp.altitude(e0)])


## Shots 11 to 13: the cantina.
func _setup_cantina() -> void:
	_put_player(Vector3(-100.0, 0.3, 6.0))
	var patron := _spawn("patron", "local_patron", Vector3(-104.25, 0.0, -1.0), -PI * 0.5)
	patron.face_point(Vector3(-109.0, 1.6, -1.0))
	_stagger()
	var oda: Node3D = demo.cantina_owner
	var o := oda.global_position if oda != null else Vector3(-107.55, 0, 0)
	say("oda at %s" % o)
	match shot:
		11:
			keys = [[0.0, Vector3(-105.3, 1.16, o.z + 1.2), Vector3(o.x, 1.2, o.z - 0.2), 40.0],
				[1.0, Vector3(-105.3, 1.18, o.z + 1.05), Vector3(o.x, 1.25, o.z - 0.2), 40.0]]
		12:
			keys = [[0.0, Vector3(-105.8, 1.62, o.z - 2.4), Vector3(o.x + 0.1, 1.5, o.z + 0.3), 42.0],
				[3.0, Vector3(-105.8, 1.6, o.z - 2.0), Vector3(o.x + 0.1, 1.5, o.z + 0.3), 40.0]]
		13:
			_put_player(Vector3(-80.0, 0.3, 4.0))
			keys = [[0.0, Vector3(-92.0, 1.7, 0.0), Vector3(-106.0, 1.5, 0.0), 50.0],
				[2.5, Vector3(-73.0, 2.4, 0.0), Vector3(-104.0, 1.6, 0.0), 50.0]]
			# Outside, over the roofs as we leave: the ship coming down.
			_take_ship(1.4)
			var e1 := Vector3(-73.0, 2.4, 0.0)
			v.ship_a = e1 + Vector3(-150.0, 205.0, -150.0)
			v.ship_b = e1 + Vector3(-190.0, 195.0, 40.0)
			v.ship_t0 = 0.0
			v.ship_t1 = 4.4


## Shots 14 and 15: the general and two gate guards walk the main street toward
## the pit, at a general's stride.
func _setup_walk() -> void:
	_put_player(Vector3(110.0, 0.3, 6.0))
	v.start = 130.0
	var g := _spawn("general", "barracks_general", Vector3(v.start, 0.05, 0.0), -PI * 0.5)
	var gn := _spawn("guard_n", "gate_guard", Vector3(v.start + 1.8, 0.05, 1.9), -PI * 0.5)
	var gs := _spawn("guard_s", "gate_guard", Vector3(v.start + 1.8, 0.05, -1.9), -PI * 0.5)
	for b in [g, gn, gs]:
		_walk_speed(b, 1.5)
	_stagger()
	# They walk from t = -1.6 at 1.5 m/s; the cameras ride the same line.
	var x0: float = v.start - 0.6
	if shot == 14:
		keys = [[0.0, Vector3(x0 - 6.2, 1.5, 1.1), Vector3(x0, 1.45, 0.2), 40.0],
			[2.0, Vector3(x0 - 3.0 - 6.4, 1.5, 1.0), Vector3(x0 - 3.0, 1.45, 0.2), 40.0]]
		_take_ship(1.6)
		var e := Vector3(x0 - 6.2, 1.5, 1.1)
		v.ship_a = e + Vector3(260.0, 140.0, 80.0)
		v.ship_b = e + Vector3(250.0, 118.0, -20.0)
	else:
		var x1: float = x0 - 3.0
		keys = [[0.0, Vector3(x1 + 11.0, 5.2, 2.4), Vector3(x1 - 22.0, -0.5, 0.0), 48.0],
			[2.0, Vector3(x1 + 11.0 - 3.2, 4.9, 2.0), Vector3(x1 - 25.0, -1.0, 0.0), 48.0]]
		_take_ship(1.6)
		var e2 := Vector3(x1 + 7.0, 4.6, 2.2)
		v.ship_a = e2 + Vector3(-300.0, 120.0, -150.0)
		v.ship_b = e2 + Vector3(-280.0, 95.0, -40.0)
	v.ship_t0 = 0.0
	v.ship_t1 = 2.4


## Shot 16, the pit: T-89 welding the frigate in the left foreground; the general and
## his guards come down the ramp beyond; T-89 turns to them, then up at the ship.
func _setup_pit() -> void:
	_put_player(Vector3(12.0, -5.7, 14.0))
	for k in ["general", "guard_n", "guard_s"]:
		var off := Vector3.ZERO if k == "general" else Vector3(1.8, 0, 1.9 if k == "guard_n" else -1.9)
		var b := _spawn(k, "barracks_general" if k == "general" else "gate_guard", Vector3(31.0, -1.4, 0.0) + off, -PI * 0.5)
		_walk_speed(b, 1.5)
	_stagger()
	var t89 = demo.salesman
	v.t89 = t89
	var fr: Node3D = pilot.kit.build("frigate")
	demo.add_child(fr)
	fr.global_transform = Transform3D.IDENTITY
	var bb := _aabb(fr)
	var yaw := 0.0 if bb.size.x >= bb.size.z else PI * 0.5
	fr.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	bb = _aabb(fr)
	# Long side along the pit, her flank 5.6 m off the ramp's line, wheels on the floor.
	fr.global_position = Vector3(6.0 - bb.get_center().x, -6.0 - bb.position.y, -5.6 - bb.end.z)
	say("frigate size %s at %s" % [bb.size, fr.global_position])
	v.frigate = fr
	v.weld = Vector3(7.0, -4.6, -5.6)
	v.t89_at = Vector3(7.0, -6.0, -4.2)
	if t89 != null and t89.body != null:
		t89.set_physics_process(false)
		t89.set_process(false)
		t89.body.global_position = v.t89_at
	if demo.droids != null:
		for d3 in demo.droids.get_children():
			if d3 is Node3D:
				d3.visible = false
	# Low behind T-89's right shoulder: him left, the frigate beyond him, the ramp right.
	var e0 := Vector3(-1.5, -4.5, 6.5)
	var tg0 := Vector3(16.0, -3.6, -2.6)
	keys = [[0.0, e0, tg0, 50.0], [2.6, e0 + Vector3(0.3, 0.0, 0.4), tg0, 50.0],
		[4.5, e0 + Vector3(0.4, -0.2, 0.6), tg0 + Vector3(4.0, 7.0, 0.0), 50.0]]
	_take_ship(1.4)
	v.ship_a = _rel(e0, tg0 + Vector3(4, 7, 0), Vector3.UP, 60.0, 120.0, 260.0)
	v.ship_b = _rel(e0, tg0 + Vector3(4, 7, 0), Vector3.UP, 10.0, 75.0, 220.0)
	v.ship_t0 = 1.5
	v.ship_t1 = 7.5


# ------------------------------------------------------------------ direction

func _direct(u: float) -> void:
	_fly_ship(u)
	match shot:
		3:
			var npc: NpcBody = cast.nomad
			if u >= 1.9 and not v.has("stopped"):
				v.stopped = true
				npc.stop()
				npc.face_point(npc.global_position + v.out * 5.0)
			var k := _ease((u - 1.9) / 0.8)
			npc.hold_pose = { "neck": Vector3(-14.0 * k, 0, 0), "head": Vector3(-26.0 * k, 0, 0) }
			_follow("aim", npc.global_position + v.u * 1.35, 2.5)
		4:
			var npc: NpcBody = cast.nomad
			npc.hold_pose = { "neck": Vector3(-14.0, 0, 0), "head": Vector3(-26.0, 0, 0) }
		6:
			var tr: NpcBody = cast.trooper
			var lo: NpcBody = cast.local
			if u >= 2.37 and not v.has("halt"):
				v.halt = true
				tr.say("Halt! Back in the dirt, sand rat.", 2.0, true)
				lo.stop()
			if u >= 2.37 and not lo.dead:
				lo.face_point(tr.global_position + _upv(tr.global_position) * 1.6)
			if u >= 0.8:
				tr.face_point(lo.global_position)
			if u >= 4.55 and not lo.dead:
				tr.fire_at(lo.global_position + _upv(lo.global_position) * 1.2, 1.0 / 60.0)
			if u >= 4.7 and not lo.dead:
				lo.apply_damage_from(9999.0, tr)
			if not lo.dead:
				v.lo_last = lo.global_position
			var mid: Vector3 = tr.global_position.lerp(v.get("lo_last", lo.global_position), 0.5)
			_follow("aim", mid + _upv(mid) * 1.3, 2.0)
		7:
			_direct_race(u)
		9, 10:
			var c = demo.cruiser
			var L: Callable = v.L
			var g: NpcBody = c.general if "general" in c else null
			if g != null and is_instance_valid(g):
				g.global_position = L.call(v.gen_at)
				g.velocity = Vector3.ZERO
				g.face_point(L.call(Vector3(34.0, 58.6, 229.0)) if shot == 10 else L.call(v.gen_at + Vector3(10, -1.5, 0.6)))
				g.home_target = rcam
				cast.general = g
			if shot == 10:
				if not cast.has("guard"):
					_spawn("guard", "cruiser_honour_guard", L.call(Vector3(24.6, 58.0, 222.8)), 0.0)
				var gd: NpcBody = cast.guard
				var k := _ease((u + 0.3) / 1.6)
				gd.global_position = L.call(Vector3(24.6, 58.0, 222.8).lerp(Vector3(27.0, 58.0, 220.1), k))
				gd.velocity = Vector3.ZERO
				gd.face_point(L.call(v.gen_at + Vector3(0, 1.6, 0)))
				# The general hears him out, half turned to him, then looks back out of
				# the window for the last line.
				if g != null and u > 0.7 and u < 3.75:
					g.face_point(gd.global_position.lerp(L.call(Vector3(34.0, 58.6, 229.0)), 0.45))
				# The dark master behind him: hands behind his back, still as stone.
				if not cast.has("master"):
					var dm := _spawn("master", "dark_master", L.call(DM_AT), 0.0)
					dm.hold_pose = DM_POSE
				var dmb: NpcBody = cast.master
				dmb.global_position = L.call(DM_AT)
				dmb.velocity = Vector3.ZERO
				dmb.face_point(L.call(DM_FACE))
				if OS.has_environment("CINE_SHIPLOG") and fmod(u, 0.5) < 0.02:
					say("u=%.2f master screen %s behind %s vis %s tree %s dist %.1f look %s parent %s" % [u, cam.unproject_position(dmb.global_position + up * 1.2), cam.is_position_behind(dmb.global_position), dmb.visible, dmb.is_visible_in_tree(), cam.global_position.distance_to(dmb.global_position), dmb.look_body.visible if dmb.look_body != null else "none", dmb.get_parent().name])
				var holo := _find_holo()
				if holo != null:
					holo.global_position = L.call(Vector3(26.0, 60.4, 218.6))
			else:
				var holo := _find_holo()
				if holo != null:
					holo.global_position = L.call(Vector3(26.0, 60.4, 218.6))
		11, 12:
			if u >= -0.15 and not v.has("served") and demo.cantina_owner != null:
				v.served = true
				demo.cantina_owner.serve({ "paid": true })
		14, 15:
			if u >= -1.6 and not v.has("walking"):
				v.walking = true
				for k in cast:
					var off := Vector3.ZERO if k == "general" else Vector3(1.8, 0, 1.9 if k == "guard_n" else -1.9)
					cast[k].go_to(Vector3(v.start - 40.0, 0, 0) + off)
			if int((u + PRE) * 60.0) % 30 == 0:
				say("t=%.2f general %s" % [u, cast.general.global_position])
		16:
			var g: NpcBody = cast.general
			if u >= -1.5 and not v.has("walking"):
				v.walking = true
				for k in cast:
					var off := Vector3.ZERO if k == "general" else Vector3(1.8, 0, 1.9 if k == "guard_n" else -1.9)
					cast[k].go_to(Vector3(14.0, -6.0, 0.0) + off)
			var t89 = v.t89
			if t89 != null and t89.look != null:
				var fr: Vector3 = v.weld
				var body: Vector3 = t89.body.global_position
				t89.body.global_position = v.t89_at
				if u < 1.4:
					t89._face(fr - body)
					DroidKit.raise_arm(t89.look, 1.0)
					t89._sparks(true)
				elif u < 2.8:
					t89._sparks(false)
					DroidKit.raise_arm(t89.look, clampf(1.0 - (u - 1.4) * 2.0, 0.0, 1.0))
					t89._face(g.global_position - body)
				else:
					t89._face(ship.global_position - body)


func _direct_race(u: float) -> void:
	var beast = demo.beast
	var dt := 1.0 / 60.0 / ts
	if beast != null:
		var head: Vector3 = beast.global_position - _upv(beast.global_position) * beast.radius
		var g: Vector3 = beast._ground_at(head + beast.heading * 1.4 * dt)
		beast.travelled += 1.4 * dt
		beast._t += dt
		beast._place(g)
		beast._push_trail(g)
		beast._pose()
	# Each racer: [time it passes the camera, lane at the camera, lane past the
	# beast's head] (m, course right +). Red leads; yellow trails and fires.
	var plan := [[0.55, -4.5, -5.5], [0.8, -3.0, -8.5], [1.1, -6.0, -7.0]]
	var speed := 36.0
	for i in v.racers.size():
		var s = v.racers[i]
		if not is_instance_valid(s) or (i == 0 and v.has("burst")):
			continue
		var x := speed * (u - float(plan[i][0]))
		var y := _race_y(x, plan[i]) + _dodge(i, x, u)
		var y2 := _race_y(x + 1.0, plan[i]) + _dodge(i, x + 1.0, u)
		var at: Vector3 = v.p0 + v.d * x + v.side * y
		at = beast._ground_at(at) if beast != null else at
		var heading: Vector3 = (v.d + v.side * (y2 - y)).normalized()
		var yaw := atan2(-heading.x, -heading.z)
		s.place(at + v.u * 1.1, yaw)
		if s.model.has_method("forward") and s.model.forward().dot(heading) < 0.0:
			s.place(at + v.u * 1.1, yaw + PI)
		if beast != null and abs(x - 36.0) < 8.0:
			var clear := INF
			for seg in beast.segments:
				clear = minf(clear, (seg.node as Node3D).global_position.distance_to(at) - float(seg.r))
			clear = minf(clear, beast.global_position.distance_to(at) - beast.radius)
			v["clear%d" % i] = minf(v.get("clear%d" % i, INF), clear)
	var shooter = v.racers[2]
	var target = v.racers[0]
	if u >= 3.5 and not v.has("seeker") and is_instance_valid(shooter) and is_instance_valid(target):
		v.seeker = _seeker(shooter.model.position + v.u * 1.3 + v.d * 2.5, target.visual)
		say("t=%.2f seeker away; clearances %s %s %s" % [u, v.get("clear0"), v.get("clear1"), v.get("clear2")])
	if v.has("seeker") and not v.has("burst") and is_instance_valid(target):
		var sk = v.seeker
		if not is_instance_valid(sk) or sk.global_position.distance_to(target.model.position) < 3.5:
			v.burst = true
			var where: Vector3 = target.model.position
			target.apply_damage(9999.0)
			ExplosionFx.big(demo, where, 1.7)
			v.hit_x = (where - v.p0).dot(v.d)
			v.hit_u = u
			say("t=%.2f seeker hit %.0f m out" % [u, (where - v.p0).dot(v.d)])


## The two left racing swerve wide round the burning leader, one either side
## (metres of lane, course right +), easing out over the first moments after the hit.
func _dodge(i: int, x: float, u: float) -> float:
	if i == 0 or not v.has("hit_x"):
		return 0.0
	var side := -1.0 if i == 1 else 1.0
	var amp: float = side * float(DODGE.amp[i - 1]) * _ease((u - float(v.hit_u)) / float(DODGE.ramp))
	var k: float = (x - float(v.hit_x)) / float(DODGE.width)
	return amp * exp(-k * k)


## A seeker the way NpcLauncher.fire builds one, homing on `target`.
func _seeker(origin: Vector3, target: Node3D) -> Node3D:
	var b = load("res://scenes/entities/bolt.tscn").instantiate()
	b.direction = (target.global_position - origin).normalized()
	b.speed = 75.0
	b.damage = 0.0
	b.range_m = 400.0
	b.stylize = true
	b.sweep = true
	b.color = Color.html("#ffd28a")
	b.streak_length = 1.0
	b.streak_radius = 0.1
	b.seek = target
	b.turn_rate = 4.0
	b.proximity = 3.0
	b.blast_size = 0.6
	var sphere := PlanetSphere.current
	if sphere != null:
		b.over_ground = func(p: Vector3) -> float: return sphere.height_above_ground(p)
		b.ground_up = func(p: Vector3) -> Vector3: return sphere.up_at(p)
	demo.add_child(b)
	b.global_position = origin
	return b


## A racer's lane (m, course right +) x metres down the course from the camera:
## its own lane by the camera, swung out round the beast's head, easing back after.
func _race_y(x: float, p: Array) -> float:
	var a: float = p[1]
	var b: float = p[2]
	if x < 36.0:
		return lerpf(a, b, _ease((x + 10.0) / 42.0))
	return lerpf(b, b * 0.4, _ease((x - 36.0) / 60.0))


func _aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var bx: AABB = mi.global_transform * mi.get_aabb()
		out = bx if first else out.merge(bx)
		first = false
	return out


func _find_holo() -> Node3D:
	if v.has("holo"):
		return v.holo
	for nd in demo.cruiser.find_children("*", "Node3D", true, false):
		var s = nd.get_script()
		if s != null and str(s.resource_path).ends_with("cruiser_holo.gd"):
			v.holo = nd
			return nd
	return null


# ------------------------------------------------------------------ cameras

## The last TAIL seconds of a shot: over PUSH seconds the camera turns onto the ship
## and the lens closes in until it fills about a third of the frame, never tighter
## than PUSH_MIN of the shot's own lens (the far dive in space); then it holds on
## the ship, following it, the lens still creeping in a little to the cut.
func _ship_push(t: float, eye: Vector3, tgt: Vector3, fov: float) -> Array:
	var tail: float = TAIL.get(shot, 0.0)
	if tail <= 0.0 or ship == null:
		return [tgt, fov]
	var into := t - (secs - tail)
	var push: float = minf(PUSH_AT.get(shot, PUSH), tail)
	var k := _ease(into / push)
	if k <= 0.0:
		return [tgt, fov]
	var hold := maxf(tail - push, 0.01)
	var creep := 1.0 - 0.12 * _ease((into - push) / hold)
	var to := ship.global_position - eye
	var dir := (tgt - eye).normalized().slerp(to.normalized(), k)
	var want := clampf(rad_to_deg(2.0 * atan(float(v.get("ship_len", 12.0)) * 1.5 / to.length())), 1.5, fov)
	want = maxf(want, fov * float(PUSH_MIN.get(shot, 0.15)))
	# The lens closes evenly to the eye (in zoom, not degrees), so no snap at the end.
	var z0 := log(tan(deg_to_rad(fov) * 0.5))
	var z1 := log(tan(deg_to_rad(want * creep) * 0.5))
	return [eye + dir * 10.0, rad_to_deg(2.0 * atan(exp(lerpf(z0, z1, k))))]


func _place_camera(t: float) -> void:
	var u := t / ts
	if keys.is_empty():
		var pp: Vector3 = demo._player.global_position
		_look(pp + Vector3(6, 4, 10), pp + Vector3(0, 1, 0))
	else:
		var p := _path(u)
		var eye: Vector3 = p[0]
		var tgt: Vector3 = p[1]
		var fov: float = p[2]
		match shot:
			3:
				# On him (a damped point, not his bob), then up with his look to the ship.
				var aim: Vector3 = v.get("aim", v.chest0)
				var k := _ease((u - 1.95) / 1.6)
				var to_ship: Vector3 = ship.global_position.lerp(v.ship_b, 0.15)
				tgt = aim.lerp(eye + (to_ship - eye).normalized() * eye.distance_to(aim), k)
				fov = lerpf(40.0, 46.0, k)
			6:
				if v.has("aim"):
					tgt = tgt.lerp(v.aim, _ease((u - 1.0) / 1.4))
			7:
				# After the hit: on the two still racing as they swerve round the wreck.
				var live: Array = []
				for i in [1, 2]:
					if i < v.racers.size() and is_instance_valid(v.racers[i]):
						live.append(v.racers[i].model.position)
				if not live.is_empty():
					var mid: Vector3 = (live[0] + live[live.size() - 1]) * 0.5 + v.u * 1.2
					var on := _follow("race_aim", mid, 4.0)
					var k := _ease((u - float(DODGE.follow_u)) / float(DODGE.follow_s))
					tgt = tgt.lerp(on, k)
					fov = lerpf(fov, DODGE.fov, k)
			4:
				var e := _ease(t / secs)
				eye = v.head
				tgt = ship.global_position
				fov = lerpf(24.0, 9.0, e)
		var pushed := _ship_push(t, eye, tgt, fov)
		_look(eye, pushed[0], up, pushed[1])
		if OS.has_environment("CINE_SHIPLOG") and ship != null and fmod(t, 0.25) < 1.0 / 60.0:
			say("t=%.2f ship local %s screen %s dist %.0f fov %.1f" % [t, cam.to_local(ship.global_position).snapped(Vector3.ONE * 0.1),
				cam.unproject_position(ship.global_position).snapped(Vector2.ONE), cam.global_position.distance_to(ship.global_position), cam.fov])
	if v.get("space", false):
		_space_sky()
	rcam.global_transform = cam.global_transform
	rcam.fov = cam.fov
	rcam.current = true
