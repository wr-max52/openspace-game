extends Node
## Throwaway probe (test_results/, not in the repo): the opening cutscene's shots.
## `-- shot=N [still=T]`: films shot N into test_results/cine/sN/, one game step per
## saved frame at 60 fps; still=T saves only the frame T seconds in (stills pass).
## Every shot runs PRE seconds of game steps first (smoke trails, walks settle).

const BOOT := 420
const STEP := 4
const PRE := 2.0
const OUT := "res://test_results/cine/s%d/%s.png"
const LINE_TROOPER := "Halt! Back in the dirt, sand rat."

const SECS := { 1: 3.0, 2: 2.0, 3: 3.0, 4: 2.0, 5: 2.0, 6: 3.0, 7: 5.0, 8: 3.0, 9: 6.0,
	10: 1.0, 11: 3.0, 12: 2.5, 13: 2.0, 14: 2.0, 15: 4.0 }

var shot := 0
var still := -1.0
var secs := 3.0
var demo
var sv: SubViewport
var cam: Camera3D
var rcam: Camera3D              ## the root viewport's camera, kept on ours (culling, fog, sky read it)
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
	secs = SECS.get(shot, 3.0)
	_log = FileAccess.open("res://test_results/cine/log_s%d.txt" % shot, FileAccess.WRITE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results/cine/s%d" % shot))
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
			c.visible = false
		sp = demo.terrain.sphere if demo.terrain != null and "sphere" in demo.terrain else null
		pilot = demo.pilot
		_setup()
		clock = -PRE
		lead = int((PRE + maxf(still, 0.0)) * 60.0)
		return
	if lead > 0:
		lead -= 1
		get_tree().paused = false
		_direct(clock)
		_place_camera(clock)
		clock += 1.0 / 60.0
		if lead == 0:
			fi = int(maxf(still, 0.0) * 60.0)
		return
	if _sub < steps_per:
		get_tree().paused = false
		_direct(float(fi + _sub) / 60.0)
		_sub += 1
		return
	get_tree().paused = true
	_hide_speech()
	_place_camera(float(fi + steps_per - 1) / 60.0)
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
	if fi % 30 == 0:
		say("frame %d / %d" % [fi, int(secs * 60.0)])
	if fi >= int(secs * 60.0):
		get_tree().quit()


## Speech shows as subtitles in the cut, not over heads.
func _hide_speech() -> void:
	for l: Label3D in demo.find_children("*", "Label3D", true, false):
		if l.visible and l.get_parent() is NpcBody:
			l.visible = false


func _spawn(key: String, soldier: String, at: Vector3, yaw: float) -> NpcBody:
	var cc = demo._content()
	var npc: NpcBody = demo.make_npc(cc.get_soldier(soldier), at, yaw, "cine_" + key, "")
	npc.target = null
	npc.nav = null
	npc.free_walk = true
	npc.home_target = rcam
	cast[key] = npc
	return npc


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


## Space: the sky follows our camera, not the player on the ground.
func _space_sky() -> void:
	if pilot == null or pilot.sky == null or sp == null:
		return
	pilot.sky._applied = -1.0
	pilot.sky.update_for(sp.altitude(cam.global_position), cam.global_position)
	if demo.detail != null:
		demo.detail.update_for(sp.altitude(cam.global_position))


## The ship's look, out of the pilot's hands: the damaged hull, engines lit, smoking.
func _take_ship() -> void:
	pilot.process_mode = Node.PROCESS_MODE_DISABLED
	ship = pilot.visual
	pilot._set_hull(false)
	WreckLook.apply(ship)
	ShipKit.throttle_flames(ship, 0.55, false, 0.0)
	var len: float = pilot._look_length()
	v.smoke = ExplosionFx.smoke_trail(ship, Vector3(0.0, 0.4, len * 0.42), 0.9, 110, 5.0)
	v.smoke2 = ExplosionFx.smoke_trail(ship, Vector3(len * 0.18, 0.2, len * 0.2), 1.0, 50, 3.5)


func _ship_at(at: Vector3, dir: Vector3, up: Vector3, roll := 0.0) -> void:
	var b := Basis.looking_at(dir, up)
	b = b.rotated(dir.normalized(), roll)
	ship.global_transform = Transform3D(b, at)


# ------------------------------------------------------------------ setup

func _setup() -> void:
	say("setup shot %d player %s" % [shot, demo._player.global_position])
	_hide_player()
	if sp != null:
		demo.terrain.follow_camera(func(): return cam.global_position)
	match shot:
		1, 2, 3:
			var c: Vector3 = sp.center
			var r: float = sp.radius
			var sun: Vector3 = demo.look.sun_dir.normalized()
			var side := sun.cross(Vector3.UP).normalized()
			v.c = c
			v.r = r
			v.dir = (sun * 0.3 + side * 0.85 + Vector3.UP * 0.3).normalized()
			v.side = side
			if shot == 3:
				_take_ship()
			say("sun %s dir %s" % [sun, v.dir])
		4, 5:
			var pk: Dictionary = demo.natives.pack("red_wind")
			var camp: Vector3 = pk.camp.center
			v.camp = camp
			_put_player(camp + _upv(camp) * 1.0 + _flat(Vector3(1, 0, 0), camp) * 14.0)
			demo.natives.set_physics_process(false)
			# An adult who is not the chief (the chief carries the pack's standard).
			var lead_m = demo.natives.leader(pk)
			var lead_npc = lead_m.npc if lead_m is Dictionary else lead_m
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
			var toward_port := _flat(-camp, camp)
			var side := toward_port.cross(_upv(camp)).normalized()
			v.port_dir = toward_port
			v.side = side
			# Out on the open sand past the camp (it shows behind him), walking across.
			var a: Vector3 = camp + side * 8.0 + toward_port * 24.0
			v.walk_a = a
			npc.global_position = a + _upv(a) * 0.3
			npc.go_to(a - side * 14.0)
			# The ship over him, coming down toward the port.
			v.ship0 = camp + _upv(camp) * 260.0 - toward_port * 150.0 + side * 40.0
			v.ship_vel = (toward_port * 95.0 - _upv(camp) * 40.0)
			_take_ship()
			v.smoke.scale_amount_min = 3.0
			v.smoke.scale_amount_max = 4.5
		6:
			var o: Dictionary = demo.outposts.outpost("remnant_outpost_near")
			v.o = o
			var W := func(l: Vector3) -> Vector3: return demo.outposts.world_point(o, l)
			v.W = W
			_put_player(W.call(Vector3(34, 1, 14)))
			var out_dir: Vector3 = (W.call(Vector3(1, 0, 0)) - W.call(Vector3.ZERO)).normalized()
			var tr := _spawn("trooper", "outpost_trooper", W.call(Vector3(20.5, 0.1, 2.0)), 0.0)
			tr.face_point(W.call(Vector3(40, 1.5, 0)))
			var lo := _spawn("local", "local_resident", W.call(Vector3(33, 0.1, -3.0)), 0.0)
			lo.go_to(W.call(Vector3(24.5, 0, -1.5)))
			v.out_dir = out_dir
			_take_ship()
		7:
			# The Basin Run, the racers' outpost 220 m down the course. The beast has
			# crawled onto the racing line; the race comes from behind the camera,
			# splits round it and runs on for the outpost, where the last racer puts
			# a seeker into the leader.
			var outpost := _surf(1461.0, 3616.0)
			var guess := _surf(1241.0, 3580.0)
			var d := _flat(outpost - guess, guess)
			var p0 := guess
			var u := _upv(p0)
			var side := d.cross(u).normalized()          # camera right
			v.p0 = p0
			v.d = d
			v.u = u
			v.side = side
			v.outpost = outpost
			_put_player(p0 + u * 1.0 - d * 30.0)
			var beast = demo.beast
			if beast != null:
				beast.set_physics_process(false)          # we walk it, slowly, at the camera
				beast.heading = (-d * 0.94 + side * 0.34).normalized()
				beast.home = beast._ground_at(p0 + d * 24.0 - side * 1.5)
				beast._seed_trail()
				beast._place(beast.home)
				beast._pose()
			# Three racers, a driver at each yoke.
			v.racers = []
			var paints := ["#d8452a", "#2a6fd8", "#e2bf3a"]
			for i in 3:
				var s = SpeederNode.new()
				s.setup(demo, pilot.ground, HoverModel.load_config("racer"), true, paints[i])
				demo.add_child(s)
				var drv := _spawn("racer%d" % i, "local_racer", p0 - d * 60.0, 0.0)
				s.seat_npc(drv, "driver")
				v.racers.append(s)
		8, 9:
			var c = demo.cruiser
			var L := func(l: Vector3) -> Vector3: return c.frame * l
			v.L = L
			_put_player(L.call(Vector3(0, 58.6, 250)))
			v.gen_at = Vector3(28.6, 58.0, 221.0)
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
		10, 11:
			_put_player(Vector3(-100.0, 0.3, 6.0))
			var patron := _spawn("patron", "local_patron", Vector3(-104.25, 0.0, -1.0), -PI * 0.5)
			patron.face_point(Vector3(-109.0, 1.6, -1.0))
			say("oda at %s" % (demo.cantina_owner.global_position if demo.cantina_owner != null else Vector3.INF))
		12:
			_put_player(Vector3(-80.0, 0.3, 4.0))
		13, 14:
			_put_player(Vector3(110.0, 0.3, 6.0))
			v.start = 128.0
			_spawn("general", "barracks_general", Vector3(v.start, 0.05, 0.0), -PI * 0.5)
			_spawn("guard_n", "gate_guard", Vector3(v.start + 1.8, 0.05, 1.9), -PI * 0.5)
			_spawn("guard_s", "gate_guard", Vector3(v.start + 1.8, 0.05, -1.9), -PI * 0.5)
		15:
			_put_player(Vector3(12.0, -5.7, 14.0))
			# The general and his two guards come down the ramp together.
			_spawn("general", "barracks_general", Vector3(36.0, 0.05, 0.0), -PI * 0.5)
			_spawn("guard_n", "gate_guard", Vector3(37.8, 0.05, 1.9), -PI * 0.5)
			_spawn("guard_s", "gate_guard", Vector3(37.8, 0.05, -1.9), -PI * 0.5)
			var t89 = demo.salesman
			v.t89 = t89
			# The frigate in for repairs on the pit floor, T-89 at her flank.
			var fr: Node3D = pilot.kit.build("frigate")
			demo.add_child(fr)
			# The camera looks +x up the ramp: the frigate sits off to the left (-z),
			# T-89 at her flank in the left foreground.
			fr.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(0.0)), Vector3(13.0, -6.0, -17.0))
			v.frigate = fr
			if t89 != null and t89.body != null:
				t89.set_physics_process(false)
				t89.body.global_position = Vector3(8.0, -6.0, -6.0)
			# No droids but T-89 in the pit (the cargo droid stays out of the shot).
			if demo.droids != null:
				for d3: Node3D in demo.droids.find_children("*", "Node3D", false, false):
					d3.visible = false
				for d3 in demo.droids.get_children():
					if d3 is Node3D:
						d3.visible = false
			_take_ship()
			v.smoke.scale_amount_min = 2.5
			v.smoke.scale_amount_max = 3.5
	say("cast %s" % str(cast.keys()))


# ------------------------------------------------------------------ direction

func _direct(ts: float) -> void:
	match shot:
		3:
			var c: Vector3 = v.c
			var eye: Vector3 = c + v.dir * v.r * 1.95
			var fwd: Vector3 = (c - eye).normalized()
			var right: Vector3 = fwd.cross(Vector3.UP).normalized()
			var up: Vector3 = right.cross(fwd).normalized()
			v.eye = eye
			v.fwd = fwd
			# From just behind and right of the camera, past it, on toward the ball.
			var at: Vector3 = eye + right * 11.0 + up * -3.0 + fwd * (ts * 95.0 - 12.0)
			_ship_at(at, fwd + up * -0.02, up, 0.25 * sin(ts * 3.0) + 0.3)
		4, 5:
			var at: Vector3 = v.ship0 + v.ship_vel * ts
			var u := _upv(at)
			var wob := 0.18 * sin(ts * 7.0) + 0.1 * sin(ts * 13.0)
			_ship_at(at, v.ship_vel.normalized(), u, wob)
			var npc: NpcBody = cast.nomad
			if shot == 4 and ts >= 1.0 and not v.has("stopped"):
				v.stopped = true
				npc.stop()
				npc.face_point(at)
			if shot == 5 or ts >= 1.0:
				var k := clampf((ts - 1.0) / 0.5, 0.0, 1.0) if shot == 4 else 1.0
				npc.hold_pose = { "neck": Vector3(-14.0 * k, 0, 0), "head": Vector3(-28.0 * k, 0, 0) }
				if shot == 5:
					npc.stop()
					npc.face_point(at)
		6:
			var tr: NpcBody = cast.trooper
			var lo: NpcBody = cast.local
			var at: Vector3 = v.W.call(Vector3(120, 0, -60)) + _upv(tr.global_position) * 1700.0
			_ship_at(at, v.out_dir * -1.0 - _upv(at) * 0.4, _upv(at), 0.2)
			if ts >= 0.0 and not v.has("halt"):
				v.halt = true
				tr.say(LINE_TROOPER, 2.0, true)
				lo.stop()
				lo.face_point(tr.global_position + Vector3(0, 1.6, 0))
			if ts >= 0.0:
				tr.face_point(lo.global_position)
			if ts >= 1.5 and not lo.dead:
				tr.fire_at(lo.global_position + _upv(lo.global_position) * 1.2, 1.0 / 60.0)
			if ts >= 1.7 and not lo.dead:
				lo.apply_damage_from(9999.0, tr)
		7:
			var beast = demo.beast
			var dt := 1.0 / 60.0
			if beast != null:
				var head: Vector3 = beast.global_position - _upv(beast.global_position) * beast.radius
				var g: Vector3 = beast._ground_at(head + beast.heading * 1.1 * dt)
				beast.travelled += 1.1 * dt
				beast._t += dt
				beast._place(g)
				beast._push_trail(g)
				beast._pose()
			# Each racer: [time it passes the camera, side offset at the camera, side
			# offset passing the beast]. Red leads; yellow trails and fires.
			var plan := [[0.7, 3.2, 8.5], [0.95, -3.6, -9.0], [1.25, -2.4, -6.5]]
			var speed := 38.0
			for i in v.racers.size():
				var s = v.racers[i]
				if not is_instance_valid(s) or (i == 0 and v.has("burst")):
					continue
				var x := speed * (ts - float(plan[i][0]))          # metres down the course from the camera
				var y := _race_y(x, plan[i])
				var y2 := _race_y(x + 1.0, plan[i])
				var at: Vector3 = v.p0 + v.d * x + v.side * y
				at = beast._ground_at(at) if beast != null else at
				var heading: Vector3 = (v.d + v.side * (y2 - y)).normalized()
				var yaw := atan2(-heading.x, -heading.z)
				s.place(at + v.u * 1.1, yaw)
				if s.model.has_method("forward") and s.model.forward().dot(heading) < 0.0:
					s.place(at + v.u * 1.1, yaw + PI)
			var shooter = v.racers[2]
			var target = v.racers[0]
			if ts >= 2.45 and not v.has("seeker") and is_instance_valid(shooter) and is_instance_valid(target):
				v.seeker = _seeker(shooter.model.position + v.u * 1.3 + v.d * 2.5, target.visual)
				say("t=%.2f seeker away, gap %.1f" % [ts, shooter.model.position.distance_to(target.model.position)])
			if v.has("seeker") and not v.has("burst") and is_instance_valid(target):
				var sk = v.seeker
				if not is_instance_valid(sk) or sk.global_position.distance_to(target.model.position) < 3.5:
					v.burst = true
					var where: Vector3 = target.model.position
					target.apply_damage(9999.0)
					ExplosionFx.big(demo, where, 1.6)
					say("t=%.2f seeker hit %.0f m out" % [ts, (where - v.p0).dot(v.d)])
		8, 9:
			var c = demo.cruiser
			var L: Callable = v.L
			var g: NpcBody = c.general if "general" in c else null
			if g != null and is_instance_valid(g):
				g.global_position = L.call(v.gen_at)
				g.velocity = Vector3.ZERO
				g.face_point(L.call(v.gen_at + Vector3(10, -1.5, 0)))
				g.home_target = rcam
				cast.general = g
			if shot == 9:
				if not cast.has("guard"):
					_spawn("guard", "cruiser_honour_guard", L.call(Vector3(27.0, 58.0, 225.6)), 0.0)
				var gd: NpcBody = cast.guard
				var k := clampf((ts + 0.5) / 2.0, 0.0, 1.0)
				gd.global_position = L.call(Vector3(27.0, 58.0, 225.6).lerp(Vector3(27.6, 58.0, 222.6), k))
				gd.velocity = Vector3.ZERO
				gd.face_point(L.call(v.gen_at + Vector3(0, 1.6, 0)))
				# The holo map over his left shoulder (moved in for the shot).
				var holo := _find_holo()
				if holo != null:
					holo.global_position = L.call(Vector3(25.2, 60.5, 218.4))
		10, 11:
			if ts >= -0.15 and not v.has("served") and demo.cantina_owner != null:
				v.served = true
				demo.cantina_owner.serve({ "paid": true })
		13, 14:
			var spd := 1.45
			var d := (ts + PRE) * spd
			for k in cast:
				var npc: NpcBody = cast[k]
				var off := Vector3.ZERO if k == "general" else Vector3(1.8, 0, 1.9 if k == "guard_n" else -1.9)
				npc.go_to(Vector3(v.start - d - 20.0, 0, 0) + off)
			if int((ts + PRE) * 60.0) % 30 == 0:
				say("t=%.2f general %s vel %s" % [ts, cast.general.global_position, cast.general.velocity])
		15:
			var g: NpcBody = cast.general
			var top := Vector3(37.0, 0.05, 0.0)
			var foot := Vector3(9.0, -5.95, 0.0)
			var k := clampf((ts + PRE) / (PRE + 4.0), 0.0, 1.0)
			for key in cast:
				var off := Vector3.ZERO if key == "general" else Vector3(1.8, 0, 1.9 if key == "guard_n" else -1.9)
				cast[key].go_to(top.lerp(foot, k) + Vector3(-3.0, 0, 0) + off)
			if int((ts + PRE) * 60.0) % 30 == 0:
				say("t=%.2f general %s" % [ts, g.global_position])
			var t89 = v.t89
			if t89 != null and t89.look != null:
				var fr: Vector3 = v.frigate.global_position
				var body: Vector3 = t89.body.global_position
				if ts < 1.2:
					t89._face(fr - body)
					DroidKit.raise_arm(t89.look, 1.0)
					t89._sparks(true)
				elif ts < 2.4:
					t89._sparks(false)
					DroidKit.raise_arm(t89.look, clampf(1.0 - (ts - 1.2) * 2.5, 0.0, 1.0))
					t89._face(g.global_position - body)
				else:
					t89._face(v.get("ship_now", fr) - body)
			# The ship far up in the sky, coming in.
			var at := Vector3(224.0, 127.0, -98.0) + Vector3(-30.0, -15.0, 18.0) * ts
			v.ship_now = at
			_ship_at(at, Vector3(-30.0, -15.0, 18.0).normalized(), Vector3.UP, 0.2 * sin(ts * 5.0))


## A seeker the way NpcLauncher.fire builds one (content/core/weapons/npc_seeker.json
## numbers), homing on `target`.
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
	Sound.play("ship_missile", origin)
	return b


## A racer's side offset (m, camera right +) at x metres down the course: close
## by the camera, swung wide round the beast, then easing back toward the line.
func _race_y(x: float, p: Array) -> float:
	var a: float = p[1]
	var b: float = p[2]
	if x < 24.0:
		var k := clampf((x + 20.0) / 44.0, 0.0, 1.0)
		return lerpf(a, b, k * k * (3.0 - 2.0 * k))
	var k2 := clampf((x - 24.0) / 70.0, 0.0, 1.0)
	return lerpf(b, b * 0.45, k2 * k2 * (3.0 - 2.0 * k2))


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

func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _look(at: Vector3, target: Vector3, up := Vector3.UP, fov := 50.0) -> void:
	cam.fov = fov
	cam.global_position = at
	if (target - at).normalized().cross(up).length() < 0.01:
		up = Vector3.FORWARD
	cam.look_at(target, up)


func _place_camera(t: float) -> void:
	var k := clampf(t / secs, 0.0, 1.0)
	match shot:
		1:
			# Stars, tilting down until the planet's limb rises into the frame.
			var c: Vector3 = v.c
			var eye: Vector3 = c + v.dir * v.r * 2.6
			var to_c := (c - eye).normalized()
			var right := to_c.cross(Vector3.UP).normalized()
			var away := to_c.rotated(right, deg_to_rad(68.0))
			var end_dir: Vector3 = (c + to_c.cross(right).normalized() * -v.r * 0.0 - eye).normalized().rotated(right, deg_to_rad(19.0))
			var e := _ease(k)
			_look(eye, eye + away.slerp(end_dir, e), Vector3.UP, 42.0)
			_space_sky()
		2:
			var c: Vector3 = v.c
			var dir: Vector3 = v.dir.rotated(Vector3.UP, deg_to_rad(-2.0 * k))
			var eye: Vector3 = c + dir * v.r * lerpf(3.25, 3.1, k)
			_look(eye, c, Vector3.UP, 42.0)
			_space_sky()
		3:
			var c: Vector3 = v.c
			_look(v.eye, c + Vector3.UP * v.r * 0.25, Vector3.UP, 48.0)
			_space_sky()
		4:
			# Low on the dunes, side on: he walks across, stops and looks up.
			var npc: NpcBody = cast.nomad
			var p: Vector3 = npc.global_position
			var u := _upv(p)
			# From the port side, looking back at him with the camp behind.
			# Then, as he looks up, the camera tilts up with him to the ship.
			var at: Vector3 = v.walk_a + v.port_dir * 7.0 - v.side * 5.0 + u * 0.8
			var to_him := (p + u * 1.35 - at).normalized()
			var to_ship := (ship.global_position - at).normalized()
			var e := _ease((t - 0.9) / 1.05)
			_look(at, at + to_him.slerp(to_ship, e) * 50.0, u, lerpf(36.0, 30.0, e))
		5:
			# His eyes: a shaky push in on the ship coming down, smoking.
			var npc: NpcBody = cast.nomad
			var p: Vector3 = npc.global_position
			var u := _upv(p)
			var eye: Vector3 = p + u * 1.75 + v.port_dir * -0.6
			var target: Vector3 = ship.global_position
			var e := _ease(k)
			var shake := Vector3(sin(t * 23.0) * 0.6 + sin(t * 41.0) * 0.3, cos(t * 19.0) * 0.5 + sin(t * 37.0) * 0.25, 0.0) * lerpf(1.0, 2.2, e)
			var right := (target - eye).normalized().cross(u).normalized()
			_look(eye, target + right * shake.x * 6.0 + u * shake.y * 6.0, u, lerpf(34.0, 9.0, e))
		6:
			# A medium two-shot of the trooper and the local, from the side away from
			# the outpost so its buildings and the refinery stand behind them.
			var W: Callable = v.W
			var tp: Vector3 = cast.trooper.global_position
			var lp: Vector3 = cast.local.global_position
			if cast.local.dead and v.has("local_last"):
				lp = v.local_last
			else:
				v.local_last = lp
			var mid := tp.lerp(lp, 0.45)
			var u := _upv(mid)
			var along := _flat(lp - tp, mid)
			var perp := along.cross(u).normalized()
			if perp.dot(W.call(Vector3.ZERO) - mid) > 0.0:
				perp = -perp
			var a: Vector3 = mid + perp * 7.0 + along * 1.5 + u * 1.55
			_look(a, mid + u * 1.25, u, 44.0)
		7:
			# Down on the sand, long lens: the beast's head filling the frame, the
			# outpost over its back. The race tears past either side of us; we crane
			# up behind it, the beast falling below frame, and the leader goes up in
			# front of the outpost.
			var u: Vector3 = v.u
			var beast = demo.beast
			var head: Vector3 = beast.global_position if beast != null else v.p0 + v.d * 24.0
			var e := _ease(clampf((t - 1.15) / 3.5, 0.0, 1.0))
			var at: Vector3 = v.p0 + u * lerpf(0.45, 15.0, e) + v.d * lerpf(0.0, 9.0, e) + v.side * 0.3
			var start_look: Vector3 = (head + u * 1.4).lerp(v.outpost + u * 6.0, 0.18)
			var end_look: Vector3 = v.p0 + v.d * 160.0 + u * 4.0
			_look(at, start_look.lerp(end_look, e), u, lerpf(34.0, 42.0, e))
		8:
			# At the side window on the planet, backing away to show the general.
			var L: Callable = v.L
			var e := _ease(k)
			var a: Vector3 = L.call(Vector3(30.2, 60.3, 222.0).lerp(Vector3(24.0, 60.2, 223.8), e))
			var target: Vector3 = L.call(Vector3(40.0, 57.6, 221.0).lerp(v.gen_at + Vector3(1.8, 1.4, -0.6), e))
			_look(a, target, Vector3.UP, 50.0)
		9:
			# Close on the general's face, the window's light on him, the map
			# glowing over his left shoulder.
			var L: Callable = v.L
			var a: Vector3 = L.call(Vector3(30.5, 59.95, 222.55 + k * 0.1))
			_look(a, L.call(v.gen_at + Vector3(0.0, 1.62, -0.25)), Vector3.UP, 34.0)
		10:
			# On the counter, low: the bottle lands in the foreground, Oda behind it.
			var oda: Node3D = demo.cantina_owner
			var o := oda.global_position if oda != null else Vector3(-109, 0, 0)
			_look(Vector3(-105.25, 1.2, o.z + 1.4), Vector3(o.x, 1.25, o.z - 0.3), Vector3.UP, 42.0)
		11:
			# The end of the bar: Oda behind it on the left, the patrons on the right.
			var oda: Node3D = demo.cantina_owner
			var o := oda.global_position if oda != null else Vector3(-109, 0, 0)
			_look(Vector3(-105.9, 1.6, o.z - 5.5 + k * 0.4), Vector3(-106.9, 1.4, o.z + 1.0), Vector3.UP, 50.0)
		12:
			# Backing out of the club through its door into the square.
			var e := _ease(k)
			_look(Vector3(lerpf(-90.0, -72.0, e), lerpf(1.7, 2.6, e), 0.0), Vector3(-104.0, 1.6, 0.0), Vector3.UP, 50.0)
		13:
			# In front of them, walking backwards with them down the main street.
			var g: Vector3 = cast.general.global_position
			_look(Vector3(g.x - 5.5, 1.45, g.z + 0.9), g + Vector3(0, 1.35, 0), Vector3.UP, 44.0)
		14:
			# Behind and above them, the pit ahead down the street.
			var g: Vector3 = cast.general.global_position
			_look(Vector3(g.x + 6.5, 4.2, g.z + 1.5), Vector3(g.x - 26.0, -2.0, 0.0), Vector3.UP, 52.0)
		15:
			# Beside T-89 at the frigate: the general coming down the ramp; then up.
			var t89 = v.t89
			var b: Vector3 = t89.body.global_position if t89 != null else Vector3(2.5, -6, 15.5)
			# Low over T-89's shoulder (he is in the left foreground), the ramp beyond.
			var a := b + Vector3(-4.0, 1.5, 3.5)
			var ramp := Vector3(20.0, -3.2, 0.0)
			var up_t := _ease(clampf((t - 2.4) / 1.2, 0.0, 1.0))
			var target := ramp.lerp(ship.global_position, up_t * 0.6)
			_look(a, target, Vector3.UP, 54.0)
		_:
			var pp: Vector3 = demo._player.global_position
			_look(pp + Vector3(6, 4, 10), pp + Vector3(0, 1, 0))
	rcam.global_transform = cam.global_transform
	rcam.fov = cam.fov
	rcam.current = true
