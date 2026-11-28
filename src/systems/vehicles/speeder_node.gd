class_name SpeederNode
extends Node3D
## A speeder in the world (issue #42): the look, the hull bolts can hit, riding it,
## and its twin lasers. HoverModel decides how it moves; this node reads the keys
## (or a bot's command), draws it and drives the camera.
##
##   E beside it   -- ride (E again to get off; you step off to the left)
##   W / S         -- throttle / brake and reverse
##   A / D         -- steer
##   Shift         -- boost
##   Space or LMB  -- both lasers at once   V -- chase / close camera
##   Space         -- with a Grav Lifter fitted (issue #95): hop and hold, Space again
##                    drops it; W/S tilt the nose in the air (Shift boosts there too); LMB fires
##
## `rideable = false` is the one on Skrugs's display pad: it just sits there.
## Bolts hit the hull (a StaticBody child; bolts call apply_damage on its parent):
## at 0 hull it bursts and is gone, and anyone riding is thrown clear. Nothing
## else hurts it.
##
## Issue #609: NPCs ride it too. board() walks a body up to a seat ("driver" or
## "rider", content/core/vehicles/speeder.json `seats`) and sits it there; while
## an NPC sits in the driver's seat, `brain` (a SpeederBrain its owner set up)
## drives it through the same HoverModel as the player. step_off() puts a body
## back on its feet beside it; at 0 hull every rider is thrown clear, hurt but
## alive. A speeder with NPCs aboard is not yours to climb on.
##
## Riding hides your body, except in a speeder whose config sets show_driver (the
## racer's open cockpit): there you sit in the driver's seat, as an NPC does.

const ChaseCamera := preload("res://src/systems/camera/chase_camera.gd")
const GROUP := "speeders"             ## issue #616: every speeder in the world (seekers lock on, mines go off)
const WeaponActor := preload("res://src/systems/combat/weapon_actor.gd")
const Weapon := preload("res://src/systems/combat/weapon.gd")
const BodyAnimator := preload("res://src/systems/anim/body_animator.gd")

signal mounted
signal dismounted
signal destroyed(at: Vector3)
signal crashed_out(at: Vector3)       ## crash_repair_s on: 0 hull crashed you out instead of bursting
signal repaired
signal npc_boarded(body: Node3D, seat: String)
signal npc_left(body: Node3D, seat: String)
signal autopilot_done                 ## a called speeder pulled up on its spot (SpeederPost.call_speeder)

var demo                              ## town_demo.gd (player, rig, terrain)
var model: HoverModel
var cfg: Dictionary = {}
var rideable := true
## A race crew's own speeder, parked at their hangout: not yours to climb on
## (their racers still board it, and it still takes hits).
var locked := false
var paint := ""                       ## issue #82: a look.paints name ("" = look.scene)
var riding := false
var hull: StaticBody3D
var visual: Node3D
var chase = ChaseCamera.new()
var gun: WeaponActor
var feedback: HitFeedback             ## hit markers and the thud for the lasers, as on foot
var shots := 0
var log_events: Array = []            ## every HoverModel event, for traces and tests

var _external: Dictionary = {}        ## a bot's command; empty = read the keys
var _hud: CanvasLayer
var _readout: Label
var _prompt: Label
var _fan: Node3D
var _glow_mat: StandardMaterial3D
static var _heat_mat: StandardMaterial3D   ## the boosters' nozzle glow, shared by every speeder
static var _dim_glows := {}               ## the parts' glows, by colour
static var _fit_meshes := {}              ## model + parts -> the parts' meshes, by material
var _fit_node: Node3D                      ## the parts that only change numbers, shown (_build_fit_looks)
var _t := 0.0
var jolt := BoardJolt.new()      ## issue #87: sink, lift and shudder as you climb on
var _lean := Vector2.ZERO        ## smoothed (pitch, roll) for the eye
var _jolt_xf := Transform3D.IDENTITY
static var _hulls: Dictionary = {}   ## issue #82: model -> its hull shape (see _model_hull)
static var _stand_ins: Dictionary = {}   ## issue #627: a stand-in's pieces -> its meshes per colour and bounds
static var _yokes: Dictionary = {}       ## look.yoke + its material -> a yoke in the world, copied into every speeder of that look
var _mat_of: Dictionary = {}             ## the look's materials by name (hull, trim, metal, seat, glow, glass)
var _engine: AudioStreamPlayer3D   ## issue #16: the speeder's drone while you ride
## Issue #95: the mechanic's looks parts (cfg.parts) and how big the body is.
var _size := Vector3(2.4, 1.2, 5.0)
var _stand_in_box := AABB()          ## issue #627: the stand-in body's bounds (the hull with no model)
var _flames: Array = []              ## the turbo boosters' flames (scaled by boost)
var _roof: Node3D                    ## the soft-top's hinge (folds back while you ride)
var _roof_fold := 0.0                ## 0 = up, 1 = folded
var _lift_glow := 0.0                ## the hover glow's flare while the Grav Lifter holds it up
var _belly_k := 0.0                  ## 0..1, the light under it while the Grav Lifter holds it up
var _belly: Node3D                   ## that light: a glowing pad under the hull and a lamp on the sand
var _belly_mat: StandardMaterial3D
var _belly_lamp: OmniLight3D
var _lift_held := false              ## a bot's lift last frame (its lift is a button: one press, one toggle)
## Issue #609: NPC riders.
var brain: SpeederBrain              ## drives while an NPC sits in the driver's seat (its owner sets the mode)
var npc_seats: Dictionary = {}       ## seat ("driver" | "rider") -> NpcBody sitting there
var _boarding: Dictionary = {}       ## NpcBody walking to a seat -> { seat, t, free_walk }
var _npc_cmd: Dictionary = {}        ## what the NPC driver did this frame (the lean reads it)
var gear: SpeederGear                ## issue #616: seekers, mines, deflector (the parts fitted)
## Called (SpeederPost.call_speeder): nobody aboard, it drives itself to a spot
## with this brain (PARK), through the same HoverModel as anyone. Climbing on
## takes over; on the spot it is parked again (autopilot_done).
var autopilot: SpeederBrain
## Issue #627: parked speeders sleep (no hover step) while the player is beyond
## the config's sleep_distance, so owning one of each costs what one did.
var asleep := false
var parked_steps := 0                ## hover steps taken while parked (tests)
## Issue #618: a race's finish cam takes the camera while this is on.
var cam_override_on := false
var cam_override := Transform3D.IDENTITY
var cam_override_fov := 55.0
var _fov_k := 0.0                    ## the boost's camera widening, eased
var seated_avatar: PlayerAvatar      ## your body in the driver's seat while you ride (show_driver), else null
## Speeder race crash-outs: a race sets this on every speeder in it while it runs
## (yours, and its racers' a little longer). Above 0, a hit that would burst it
## while you or an NPC drive it crashes it out instead: a bang,
## it stops dead and sits smoking while it is patched up for this many seconds
## (no throttle, no guns, no hits), then it is back to full hull and you race on.
var crash_repair_s := 0.0
var repair_left := 0.0               ## seconds of patching up still to go (0 = not crashed out)
var crash_outs := 0                  ## times crashed out (tests)
var _repair_smoke: CPUParticles3D
## Issue #722: crashed out with a plasma welder, hold E in the seat for
## Welder.weld_s and it is back at full hull; the patch-up without welding puts it
## back at Welder.unwelded_hull. Off the track a damaged speeder nobody rides is
## welded on foot (its WeldSpot: welder drawn, hold fire; E mounts it).
var weld_t := 0.0                    ## seconds of the seat weld held so far
var welded_outs := 0                 ## crash-outs welded (tests)
var weld_spot: WeldSpot
var _weld_fx: WelderFx


func setup(town_demo, ground: WorldGround, config: Dictionary = {}, can_ride: bool = true, paint_job: String = "") -> void:
	demo = town_demo
	cfg = config if not config.is_empty() else HoverModel.load_config("speeder")
	rideable = can_ride
	paint = paint_job
	model = HoverModel.new(cfg, ground)
	gear = SpeederGear.new(cfg)
	name = "Speeder" if can_ride else "DisplaySpeeder"


func _ready() -> void:
	if rideable:
		add_to_group(GROUP)
	_build_visual()
	_build_parts()
	_build_hull()
	_build_yoke()               # after the hull: not part of its shape
	_engine = Sound.loop("speeder_engine", self)
	if rideable:
		_build_weld_spot()
		gun = WeaponActor.new()
		var laser: Dictionary = cfg.get("laser", {})
		gun.set_weapon(laser)
		gun.bolt_parent = demo if demo is Node3D else get_parent()
		var color := Color(str(laser.get("color", "#7fe0d0")))
		gun.configure_bolt = func(b):
			b.shooter = hull
			b.stylize = true
			b.sweep = true
			b.color = color
			# The speeder's laser keeps its own size (hand-gun bolts are thinner).
			b.streak_length = float(laser.get("bolt_length", 0.9))
			b.streak_radius = float(laser.get("bolt_radius", 0.035))
			b.on_hit.connect(_on_laser_hit)
			b.on_splash.connect(_on_laser_hit)
		chase.fit_to(float(cfg.get("look", {}).get("length", 4.6)))
		chase.chase_back = 9.0
		chase.chase_up = 3.2
		chase.look_ahead = 30.0
		_build_hud()
	_sync()


## Set it down at `at` facing `yaw` (on whatever ground is there).
func place(at: Vector3, yaw: float) -> void:
	model.place(at, yaw)
	_sync()


# ------------------------------------------------------------------ riding

func player() -> CharacterBody3D:
	return demo._player if demo != null else null


func can_mount() -> bool:
	var p := player()
	if not rideable or locked or riding or not npc_seats.is_empty() or p == null or p.locked or p.piloting or not model.alive():
		return false
	# Along the ground and along up (issue #77: up leans on the ball).
	var u := model.up()
	var rel: Vector3 = p.global_position - (model.position - u)
	var along := rel.dot(u)
	return (rel - u * along).length() <= float(cfg.get("board_reach", 3.2)) and absf(along) < 2.5


func mount() -> bool:
	if not can_mount():
		return false
	var p := player()
	riding = true
	p.piloting = true
	p.vehicle = self
	p.locked = true
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.visible = _seat_player()
	_player_collision(false)
	if demo.terrain != null:
		demo.terrain.follow(null)
	chase._primed = false
	_external = {}
	if _hud != null:
		_hud.visible = true
	jolt.start()
	autopilot = null            # a called speeder you climb on is yours to drive
	_ensure_parts()             # issue #100: the looks parts are on every time you get in
	mounted.emit()
	return true


## Get off, beside it (left, then right, then behind).
func dismount() -> bool:
	if not riding:
		return false
	var p := player()
	riding = false
	model.set_command(0.0, 0.0)
	if _engine != null:
		_engine.stop()
	var spot := _exit_spot()
	p.piloting = false
	p.vehicle = null
	if "last_vehicle" in p:
		p.last_vehicle = self
	p.locked = false
	p.process_mode = Node.PROCESS_MODE_INHERIT
	p.visible = true
	_player_collision(true)
	p.global_position = spot
	var rig = demo._rig
	if rig != null:
		rig.clear_override()
		rig.rig.yaw = model.yaw
		p.rotation.y = rig.rig.yaw
		if "player_kit" in demo and demo.player_kit != null and demo.player_kit.avatar != null:
			demo.player_kit.avatar.facing_yaw = rig.rig.yaw
	_unseat_player()
	if p.has_method("align_to_ground"):
		p.call("align_to_ground", true)
	else:
		p.velocity = Vector3.ZERO
		p.controller.velocity = Vector3.ZERO
		p.controller.body_pos = spot
	if demo.terrain != null:
		demo.terrain.follow(p)
	if _hud != null:
		_hud.visible = false
	dismounted.emit()
	return true


## A bot's command for this frame and on: { throttle, steer, boost, fire }.
## Pass {} to give control back to the keys.
func set_external_command(c: Dictionary) -> void:
	_external = c


## Issue #55: ridden inside town, the garrison treats it as hostile and shoots
## the hull. Out in the desert nobody minds it.
func hostile_in_town() -> bool:
	return riding and model.alive() and demo != null and TownNav.in_town(demo.get("town"), model.position)


## Ridden and whole: an outpost's troopers fight it as they would you on foot.
func targetable() -> bool:
	return riding and model.alive()


## What the troopers' eyes and bolts hit while you ride.
func hull_body() -> CollisionObject3D:
	return hull


func threat_velocity() -> Vector3:
	return model.travel_dir() * model.speed     # issue #627: a drifting truck moves along its slide


## Bolts land here (the hull's parent). Riding or parked, the hull takes it.
func apply_damage(amount: float) -> void:
	if repair_left > 0.0:
		return                           # crashed out and being patched up: nothing more to break
	if gear != null and model.alive() and gear.absorb():
		_lift_glow = 1.0                 # issue #616: the deflector took it: a flash round the hull
		Sound.play("ship_hit", model.position)
		return
	var killed := model.apply_damage(amount)
	for e in model.events:
		log_events.append(e)
	if killed:
		if crash_repair_s > 0.0 and (riding or npc_driven()):
			_crash_out()
		else:
			_burst()


## Crashed out in a race (crash_repair_s): a bang, dead stop, smoke while it is
## patched up. Kept alive at 1 hull so it still rides and syncs; finish_repair()
## puts the rest back.
func _crash_out() -> void:
	var at := model.position
	crash_outs += 1
	model.hp = 1
	model.speed = 0.0
	model.drift_dir = Vector3.ZERO
	model.set_command(0.0, 0.0)
	repair_left = crash_repair_s
	ExplosionFx.small(get_parent(), at + model.up() * 0.6)
	Sound.play("vehicle_boom", at)
	if visual != null and demo != null and bool(demo.get("use_look")):
		_repair_smoke = ExplosionFx.smoke_trail(visual, Vector3(0, 0.6, 0), 0.5, 10, 2.5)
	crashed_out.emit(at)


## Crashed out: a frame of patching up, the controls held at nothing. False when
## it is not crashed out (drive as normal). Issue #722: a rider with a welder holds
## E and is back at full hull in Welder.weld_s; left to the patch-up the player
## comes back at Welder.unwelded_hull (a crew's racer has no welder and comes back
## whole, as before).
func _tick_repair(dt: float) -> bool:
	if repair_left <= 0.0:
		return false
	repair_left -= dt
	model.set_command(0.0, 0.0)
	if riding and Welder.owned() and Welder.e_held():
		weld_t += dt
		_set_weld_fx(true)
		if weld_t >= Welder.weld_s():
			welded_outs += 1
			repair_left = maxf(repair_left, 0.01)
			finish_repair(1.0)
			return true
	elif weld_t > 0.0:
		weld_t = 0.0
		_set_weld_fx(false)
	if repair_left <= 0.0:
		repair_left = 0.01
		finish_repair(Welder.unwelded_hull() if riding else 1.0)
	return true


## Patched up: `share` of full hull (issue #722: full when welded, less when the
## race's patch-up did it), the smoke stops, the controls are yours again.
func finish_repair(share := 1.0) -> void:
	if repair_left <= 0.0:
		return
	repair_left = 0.0
	weld_t = 0.0
	_set_weld_fx(false)
	model.hp = maxi(1, int(round(model.max_hp * clampf(share, 0.0, 1.0))))
	repaired.emit()
	var smoke := _repair_smoke
	_repair_smoke = null
	if smoke != null and is_instance_valid(smoke):
		smoke.emitting = false             # the last puffs drift off, then it goes
		if not is_inside_tree():
			smoke.queue_free()
			return
		get_tree().create_timer(3.0).timeout.connect(func(): if is_instance_valid(smoke): smoke.queue_free())


## Issue #722: a damaged speeder nobody rides can be welded back to full hull on
## foot. E mounts it, so only fire with the welder drawn welds it (use_e false).
func _build_weld_spot() -> void:
	weld_spot = WeldSpot.make(
		func(): return not riding and npc_seats.is_empty() and model.alive() and model.hp < model.max_hp and repair_left <= 0.0,
		func(): return "the " + str(cfg.get("label", "speeder")),
		func(): model.hp = model.max_hp,
		Callable(), false)
	weld_spot.reach = float(cfg.get("board_reach", 3.2)) + 0.8
	weld_spot.spark_height = 0.5
	add_child(weld_spot)


## The seat weld's sparks, on the hull by your knees.
func _set_weld_fx(on: bool) -> void:
	if on and _weld_fx == null and visual != null:
		_weld_fx = WelderFx.make(Color("#a8e4ff"), 2.0)
		_weld_fx.position = Vector3(0.0, 0.45, -0.6)
		visual.add_child(_weld_fx)
	if _weld_fx != null and is_instance_valid(_weld_fx):
		_weld_fx.set_on(on)


# ------------------------------------------------------------------ frame

## Issue #627: parked and settled (nobody aboard or boarding, not moving, on the
## ground) with the player more than sleep_distance away. A parked speeder only
## settles its hover; asleep it keeps where it is until someone comes near.
func _sleeps() -> bool:
	if riding or autopilot != null or not npc_seats.is_empty() or not _boarding.is_empty():
		return false
	if model.airborne or absf(model.speed) > 0.05 or absf(model.vy) > 0.05:
		return false
	var reach := float(cfg.get("sleep_distance", 60.0))
	if reach <= 0.0:
		return false
	var p := player()
	if p == null or not is_instance_valid(p):
		return false                   # nobody to measure from (bare tests): as before
	return p.global_position.distance_squared_to(model.position) > reach * reach

func _physics_process(dt: float) -> void:
	if model == null or not model.alive():
		if _engine != null and _engine.playing:
			_engine.stop()
		return
	_t += dt
	_jolt_xf = jolt.step(dt)
	if gear != null:
		gear.step(dt)
	_tick_boarding(dt)
	model.parked = not riding and not npc_driven()     # at rest it sits on the slope (HoverModel._settle)
	if riding or npc_driven():
		_tick_tow(dt)
	if riding:
		_ride(dt)
	elif npc_driven():
		_npc_drive(dt)
	elif rideable:
		var free_now := can_mount() and not _hijack_claims()
		_show_prompt(free_now)
		if free_now and _just("interact"):
			mount()
			return
		if autopilot != null:
			_autopilot_drive(dt)
			return
		if _sleeps():
			# Issue #627: parked with every player far off: no hover step, no sync.
			asleep = true
			return
		asleep = false
		model.set_command(0.0, 0.0)
		parked_steps += 1
		for e in model.step(dt):
			log_events.append(e)
		_sync()
	_carry_riders()


func _ride(dt: float) -> void:
	var fire := false
	if _tick_repair(dt):
		pass                             # crashed out: it sits where it stopped till patched up
	elif _external.is_empty():
		if _just("interact") and not model.airborne and not _hijack_claims():
			dismount()
			return
		_lift_held = false               # the keys have it: a bot's next lift is a fresh press
		var throttle := _axis("move_back", "move_forward")
		var steer := _axis("move_left", "move_right")
		model.set_command(throttle, steer, _held("sprint_mod") or _held("flight_boost"))
		if model.has_lifter():
			# Issue #95: Space is the Grav Lifter now; the mouse fires.
			fire = _held("fire")
			if _just("jump"):
				model.lift()
		else:
			fire = _held("jump") or _held("fire") or _held("flight_fire")
		# Issue #616: race gear. Right mouse fires a seeker at the speeder in your
		# nose (straight if none); the grenade key drops a mine behind.
		if gear != null and (_just("alt_fire") or _just("flight_missile")):
			gear.fire_seeker(self, gear.pick_target(self))
		if gear != null and _just("throw"):
			gear.drop_mine(self)
		if _just("flight_radio"):
			radio_next()
	else:
		model.set_command(float(_external.get("throttle", 0.0)), float(_external.get("steer", 0.0)),
			bool(_external.get("boost", false)))
		fire = bool(_external.get("fire", false))
		_bot_lift(bool(_external.get("lift", false)))
	for e in model.step(dt):
		log_events.append(e)
	_fire(dt, fire)
	_sync()
	_place_seated()
	if _engine != null:
		if not _engine.playing:
			_engine.play()
		_engine.pitch_scale = 1.1 + clampf(absf(model.speed) / 40.0, 0.0, 1.0) * 0.6
	var p := player()
	p.global_position = model.position
	if demo.terrain != null and model.height_over_ground() < 30.0:
		# Ground to step off onto, built in the background, but only while slow
		# enough for it to finish (flow data speeder_prefetch_speed): faster, the
		# half-built one is dropped. Render rules: never build what you outrun.
		if absf(model.speed) <= GameFlow.setting("speeder_prefetch_speed", 20.0):
			demo.terrain.prefetch(model.position)
		elif demo.terrain.has_method("drop_near_rows"):
			demo.terrain.drop_near_rows()
	# Issue #618: speed feel: the view widens a little while you boost, easing back
	# after. A finish cam takes the view while it runs. (The boost's dust streaks
	# went: a particle system and an alpha material compiled on the first boost,
	# for a look nobody missed. Render rules: speed comes first.)
	_fov_k = move_toward(_fov_k, 1.0 if model.boosting() else 0.0, dt * 2.5)
	if demo._rig != null:
		var view := chase.update(dt, model.transform().translated_local(Vector3(0, 0.6, 0)))
		if cam_override_on:
			demo._rig.set_override(cam_override, cam_override_fov)
		else:
			demo._rig.set_override(view, float(cfg.get("fov", 75.0)) + _fov_k * float(cfg.get("fov_kick", 10.0)))
	if demo.detail != null:
		demo.detail.update_for(model.ground.altitude(model.position) if model.ground != null else model.position.y)
	_update_hud()


func _fire(dt: float, trigger: bool) -> void:
	if gun == null:
		return
	# The weapon keeps the rate and the ammo; one trigger pull fires both barrels
	# together, left and right.
	if gun.weapon.start_firing(dt, trigger) == Weapon.Result.SHOT:
		var b := model.transform().basis
		# Issue #64: the barrels sit either side of the nose, so two parallel bolts
		# straddled anyone straight ahead. Both converge on what the nose points at.
		var aim := _aim_point(b)
		var m := _muzzle()
		for side in [-1.0, 1.0]:
			var origin := model.position + b * Vector3(side * m.x, m.y, m.z)
			gun._make_bolt(aim - origin, origin, float(gun.weapon.config.get("damage", 18.0)),
				float(gun.weapon.config.get("bolt_speed", 90.0)))
			gun.shots_fired += 1
		shots += 1
		Sound.play("speeder_laser", model.position)


## A laser bolt landed on `target`: the hit marker pops if it really took damage
## (people, droids, other speeders, ships), as for the guns on foot.
## J steps the radio, as in a ship (issue #291): the next station, then off,
## with the same line on screen.
func radio_next() -> String:
	var station := Sound.radio_next()
	var gear_ctl = demo.get("gear") if demo != null else null
	if gear_ctl != null and gear_ctl.hud != null:
		gear_ctl.hud.toast(ShipPilot.radio_line(station), 3.0)
	return station


func _on_laser_hit(target: Object) -> void:
	if feedback != null:
		feedback.on_hit(target)


## Where the lasers meet: the first thing straight ahead of the nose (not the
## speeder or its rider), else a point at the guns' convergence range.
func _aim_point(b: Basis) -> Vector3:
	var from := model.position + b * Vector3(0, _muzzle().y, _muzzle().z)
	var far := from + model.forward() * float(gun.weapon.config.get("range", 140.0))
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(from, far)
		var skip: Array[RID] = [hull.get_rid()]
		if player() != null:
			skip.append(player().get_rid())
		q.exclude = skip
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and from.distance_to(hit.position) > 3.0:
			return hit.position
	return from + model.forward() * float(cfg.get("laser", {}).get("converge", 30.0))


func _sync() -> void:
	global_transform = model.transform()
	if visual != null:
		# Lean into turns and pitch with the climb and the W/S tilt (under the lifter), for the eye only.
		var steer_now := float(_npc_cmd.get("steer", 0.0)) if npc_driven() else float(_external.get("steer", 0.0))
		var lean := clampf(model.speed / 40.0, -1.0, 1.0) * (_axis("move_left", "move_right") if riding and _external.is_empty() else steer_now)
		_lean.y = lerpf(_lean.y, -lean * 0.25, 0.15)
		_lean.x = lerpf(_lean.x, clampf(clampf(model.vy / 30.0, -0.35, 0.35) + model.air_pitch, -0.6, 0.6), 0.2)
		visual.transform = Transform3D(Basis.from_euler(Vector3(_lean.x, 0.0, _lean.y)), Vector3(0, 0.04 * sin(_t * 3.0), 0)) * _jolt_xf
	if _fan != null:
		_fan.rotation.z += 0.3 + absf(model.speed) * 0.02
	_lift_glow = move_toward(_lift_glow, 1.0 if model.lifting() else 0.0, 0.08)
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 1.5 + absf(model.speed) / 10.0 + 6.0 * _lift_glow
	_sync_lift_glow()
	_sync_parts()


## The underside lights up while the Grav Lifter holds it up: a glowing pad under
## the hull and a lamp just below it that lights the belly and the sand, in the
## speeder's glow colour (the lifter's "glow" block sizes it). Built once with the
## lifter (hidden, so the first lift does not hitch on it); one light, no shadow,
## and only while lifting (docs/RENDER_RULES.md 7).
func _sync_lift_glow() -> void:
	if not model.has_lifter() or visual == null:
		if _belly != null and is_instance_valid(_belly):
			_belly.visible = false
		return
	if _belly == null or not is_instance_valid(_belly):
		_build_lift_glow()
	_belly_k = move_toward(_belly_k, 1.0 if model.lifting() else 0.0, 0.1)
	_belly.visible = _belly_k > 0.01
	if not _belly.visible:
		return
	var g: Dictionary = model.lifter().get("glow", {})
	var hum := 1.0 + 0.08 * sin(_t * 23.0)       # a little hum in it
	_belly_mat.emission_energy_multiplier = (2.0 + 4.0 * _belly_k) * hum
	_belly_lamp.light_energy = float(g.get("light_energy", 3.0)) * _belly_k * hum
	_belly.scale = Vector3.ONE * lerpf(0.6, 1.0, _belly_k)


func _build_lift_glow() -> void:
	var lk: Dictionary = cfg.get("look", {})
	var g: Dictionary = model.lifter().get("glow", {})
	var col := Color(str(lk.get("glow", "#7fe0d0")))
	var length := float(lk.get("length", 4.6))
	var base_y := float(lk.get("base_y", -0.65))
	_belly = Node3D.new()
	_belly.name = "LiftGlow"
	_belly.position = Vector3(0, base_y - 0.08, 0)
	_belly.visible = false
	visual.add_child(_belly)
	# The hover glow's own kind of material (unshaded, emissive), so no new shader.
	_belly_mat = StandardMaterial3D.new()
	_belly_mat.albedo_color = col
	_belly_mat.emission_enabled = true
	_belly_mat.emission = col
	_belly_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	pad.mesh = LookMeshKit.cyl(0.5, 0.5, 0.02, 12)
	pad.scale = Vector3(length * float(g.get("width", 0.42)), 1.0, length * float(g.get("length", 0.8)))
	pad.material_override = _belly_mat
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_belly.add_child(pad)
	_belly_lamp = OmniLight3D.new()
	_belly_lamp.name = "Lamp"
	_belly_lamp.light_color = col
	_belly_lamp.light_energy = 0.0
	_belly_lamp.omni_range = float(g.get("light_range", 6.0))
	_belly_lamp.shadow_enabled = false
	_belly_lamp.distance_fade_enabled = true
	_belly_lamp.distance_fade_begin = 80.0
	_belly_lamp.distance_fade_length = 20.0
	_belly_lamp.position = Vector3(0, -0.35, 0)
	_belly.add_child(_belly_lamp)


# ------------------------------------------------------------------ hijacking (Hijack)

## E is the town's Hijack's this frame (a vehicle someone else rides is in reach).
func _hijack_claims() -> bool:
	var h = demo.get("hijack") if demo != null else null
	return h != null and is_instance_valid(h) and h.claims_e()


## Someone may take it from you now: you ride it, it is whole, on the ground.
func can_be_hijacked() -> bool:
	return riding and model.alive() and not model.airborne


## Player `by` threw you off (Hijack.on_take): you are beside it, and it is not
## here for you while they ride it (hidden, still, nothing to hit). Returns what
## their game needs to build it ({} when it can not be taken now).
func thrown_out(by: int) -> Dictionary:
	if not can_be_hijacked():
		return {}
	var st := { "cfg": cfg, "paint": paint, "xf": model.transform(), "yaw": model.yaw, "speed": model.speed }
	if has_meta("hijacked_from"):
		st["owner"] = int(get_meta("hijacked_from"))   # issue #551: one you had taken goes on as its owner's
	set_meta("hijacked_by", by)        # before dismount: being thrown off is not getting off (Hijack._speeder_let_go)
	dismount()
	visible = false
	set_physics_process(false)
	if hull != null:
		set_meta("hull_layer", hull.collision_layer)
		hull.collision_layer = 0
	return st


## They let it go at `xf` (Hijack.on_back): it stands there again, yours; or,
## `wrecked`, it burst under them.
func hijack_returned(xf: Transform3D, wrecked: bool) -> void:
	if not has_meta("hijacked_by"):
		return
	remove_meta("hijacked_by")
	place(xf.origin, _yaw_from(xf))
	visible = true
	set_physics_process(true)
	if hull != null:
		hull.collision_layer = int(get_meta("hull_layer", 1))
	if wrecked:
		model.apply_damage(1.0e6)
		_burst()


func _yaw_from(xf: Transform3D) -> float:
	var f := -xf.basis.z
	var u := model.up()
	f -= u * f.dot(u)
	var local := PlanetSphere.tilt_to(u).inverse() * f
	return atan2(-local.x, -local.z) if Vector2(local.x, local.z).length() > 0.01 else model.yaw


## Issue #618: drafting. Behind another speeder, inside its tow, the draft builds
## (HoverModel.tow); out of it, it fades.
func _tick_tow(dt: float) -> void:
	var want := 0.0
	var reach := float(cfg.get("tow_m", 24.0))
	var cone := deg_to_rad(float(cfg.get("tow_cone_deg", 14.0)))
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group(GROUP):
			var s := n as SpeederNode
			if s == null or s == self or not is_instance_valid(s) or not s.model.alive() or s.model.speed < 8.0:
				continue
			var to := s.model.position - model.position
			var d := to.length()
			if d > 2.0 and d < reach and model.forward().angle_to(to) < cone and s.model.forward().dot(model.forward()) > 0.8:
				want = 1.0
				break
	model.tow = move_toward(model.tow, want, dt / maxf(float(cfg.get("tow_build_s", 1.0)), 0.01))


# ------------------------------------------------------------------ NPC riders (issue #609)

## An NPC sits in the driver's seat (and is alive).
func npc_driven() -> bool:
	var d = npc_seats.get("driver")
	return d != null and is_instance_valid(d) and not d.dead


## The NPC in `seat`, or null.
func npc_in(seat: String) -> NpcBody:
	var b = npc_seats.get(seat)
	return b if b != null and is_instance_valid(b) else null


## Who sits where: the speeder's local seat spots (feet), from its config.
func seat_offset(seat: String) -> Vector3:
	var a = cfg.get("seats", {}).get(seat, null)
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3(0.0, -0.6, 0.35) if seat == "driver" else Vector3(0.0, -0.55, 1.5)


func seat_names() -> Array:
	var seats = cfg.get("seats", {})
	return (seats as Dictionary).keys() if seats is Dictionary and not (seats as Dictionary).is_empty() else ["driver", "rider"]


## The seat is free: nobody sits there, nobody is walking to it, and you are not
## riding (you take the driver's seat).
func seat_free(seat: String) -> bool:
	if npc_in(seat) != null or (seat == "driver" and riding):
		return false
	for b in _boarding:
		if str(_boarding[b].seat) == seat:
			return false
	return seat in seat_names()


## Send `body` to `seat`: it walks up and climbs on (at once, if it is in reach).
## False if the seat is taken, the speeder is wrecked or the body is dead.
func board(body: NpcBody, seat: String = "driver") -> bool:
	if body == null or body.dead or not model.alive() or not seat_free(seat) or npc_seats.values().has(body):
		return false
	if _in_reach(body):
		return seat_npc(body, seat)
	_boarding[body] = { "seat": seat, "t": 0.0, "free_walk": body.free_walk }
	if body.nav == null or not body.nav.is_ready:
		body.free_walk = true          # out in the sand: straight at it, as a pack walks
	body.go_to(model.position)
	return true


## Sit `body` in `seat` now, wherever it stands.
func seat_npc(body: NpcBody, seat: String = "driver") -> bool:
	if body == null or body.dead or not model.alive() or npc_in(seat) != null or (seat == "driver" and riding):
		return false
	if _boarding.has(body):
		body.free_walk = bool(_boarding[body].free_walk)
		_boarding.erase(body)
	npc_seats[seat] = body
	body.stop()
	body.velocity = Vector3.ZERO
	body.set_physics_process(false)
	body.set_process(false)
	if body.look_body != null and is_instance_valid(body.look_body) and body._look_rest != Vector3.INF:
		body.look_body.position = body._look_rest
	_body_collision(body, false)
	if seat == "driver" and bool(cfg.get("show_driver", false)):
		_sit_npc(body)
	if not body.died.is_connected(_on_rider_died):
		body.died.connect(_on_rider_died.bind(body))
	_carry_riders()
	npc_boarded.emit(body, seat)
	return true


## Put `body` (or, with null, everyone) back on their feet beside the speeder:
## left, then right, then behind. Their own brain carries on as it was.
func step_off(body: NpcBody = null) -> bool:
	var left := false
	var taken: Array = []
	for seat in npc_seats.keys():
		var b = npc_seats[seat]
		if body != null and b != body:
			continue
		npc_seats.erase(seat)
		if b == null or not is_instance_valid(b):
			continue
		var spot := _npc_exit_spot(taken)
		taken.append(spot)
		_free_body(b, spot)
		npc_left.emit(b, seat)
		left = true
	if not npc_driven():
		_npc_cmd = {}
		model.set_command(0.0, 0.0)
	return left


func _free_body(b: NpcBody, spot: Vector3) -> void:
	if b.died.is_connected(_on_rider_died):
		b.died.disconnect(_on_rider_died)
	if b.has_meta("seated_weapon"):
		var w = b.get_meta("seated_weapon")
		b.remove_meta("seated_weapon")
		if w != null and is_instance_valid(w):
			(w as Node3D).visible = true    # their own walk poses them again from here
	_body_collision(b, true)
	b.global_position = spot
	b.velocity = Vector3.ZERO
	b.controller.velocity = Vector3.ZERO
	b.controller.body_pos = spot
	b.set_physics_process(true)
	b.set_process(true)
	b.stop()


func _on_rider_died(b: NpcBody) -> void:
	# Shot dead in the seat: off it, so the body falls where it was.
	if npc_seats.values().has(b):
		step_off(b)


## The speeder burst: everyone aboard lands on their feet nearby, a little hurt
## (thrown_damage, never the last hp).
func _throw_riders_clear() -> void:
	var aboard: Array = npc_seats.values().filter(func(b): return b != null and is_instance_valid(b))
	step_off()
	var dmg := SpeederBrain.rule("thrown_damage", 15.0)
	for b: NpcBody in aboard:
		if not b.dead and b.health.hp > 1:
			b.apply_damage(minf(dmg, float(b.health.hp - 1)))
	_boarding.clear()


## The NPC driver's frame: its brain's command (or a bot's) through the model.
func _npc_drive(dt: float) -> void:
	if _tick_repair(dt):
		# Crashed out: the driver sits it out, no throttle, no guns.
		_npc_cmd = {}
		if brain != null:
			brain.command = { "throttle": 0.0, "steer": 0.0, "boost": false, "fire": false }
	elif brain != null:
		brain.model = model
		_npc_cmd = brain.update(dt)
	else:
		_npc_cmd = _external
	model.set_command(float(_npc_cmd.get("throttle", 0.0)), float(_npc_cmd.get("steer", 0.0)),
		bool(_npc_cmd.get("boost", false)))
	_bot_lift(bool(_npc_cmd.get("lift", false)))
	for e in model.step(dt):
		log_events.append(e)
	_fire(dt, bool(_npc_cmd.get("fire", false)))
	_sync()
	if _engine != null:
		if not _engine.playing:
			_engine.play()
		_engine.pitch_scale = 1.1 + clampf(absf(model.speed) / 40.0, 0.0, 1.0) * 0.6


## A called speeder's frame (nobody aboard): its autopilot's command through the
## model, the engine's drone so you hear it coming; parked once it is on the spot.
func _autopilot_drive(dt: float) -> void:
	autopilot.model = model
	var cmd := autopilot.update(dt)
	model.set_command(float(cmd.get("throttle", 0.0)), float(cmd.get("steer", 0.0)), bool(cmd.get("boost", false)))
	for e in model.step(dt):
		log_events.append(e)
	_sync()
	if _engine != null:
		if not _engine.playing:
			_engine.play()
		_engine.pitch_scale = 1.1 + clampf(absf(model.speed) / 40.0, 0.0, 1.0) * 0.6
	# On the spot and stopped is parked, whichever way it ended up facing (a
	# hover turns slowly standing still).
	var on_spot := autopilot.park_at != Vector3.INF and absf(model.speed) < 0.8 \
		and autopilot._flat(autopilot.park_at - model.position).length() <= autopilot.s("park_reach", 2.5) + 0.5
	if autopilot.done or on_spot:
		stop_autopilot()
		autopilot_done.emit()


## Off autopilot, where it is (done, or the call gave up).
func stop_autopilot() -> void:
	autopilot = null
	model.set_command(0.0, 0.0)
	if _engine != null and not riding:
		_engine.stop()


## A bot's lift is held in its command from frame to frame; the Grav Lifter is a
## button (press on, press off), so only the frame it goes down counts.
func _bot_lift(held: bool) -> void:
	if held and not _lift_held:
		model.lift()
	_lift_held = held


## Seated bodies go where the speeder goes, facing its way.
func _carry_riders() -> void:
	if npc_seats.is_empty():
		return
	var xf := model.transform()
	var f := model.forward()
	# A seated driver at a yoke (show_driver) bobs with the look, as the yoke does.
	var at_yoke := bool(cfg.get("show_driver", false)) and visual != null
	for seat in npc_seats:
		var b = npc_seats[seat]
		if b == null or not is_instance_valid(b):
			continue
		var frame := xf * visual.transform if at_yoke and str(seat) == "driver" else xf
		b.global_position = frame * seat_offset(str(seat))
		b.facing = atan2(f.x, f.z)
		b.rotation.y = b.facing
		b.velocity = Vector3.ZERO
		b.controller.body_pos = b.global_position


## Bodies walking to a seat: climb on in reach; give up after board_timeout_s.
func _tick_boarding(dt: float) -> void:
	if _boarding.is_empty():
		return
	for b in _boarding.keys():
		if b == null or not is_instance_valid(b) or b.dead:
			_boarding.erase(b)
			continue
		var st: Dictionary = _boarding[b]
		st.t = float(st.t) + dt
		if _in_reach(b):
			seat_npc(b, str(st.seat))
		elif float(st.t) > SpeederBrain.rule("board_timeout_s", 25.0) or not model.alive():
			b.free_walk = bool(st.free_walk)
			b.stop()
			_boarding.erase(b)
		else:
			b.go_to(model.position)


func _in_reach(b: Node3D) -> bool:
	var u := model.up()
	var rel: Vector3 = b.global_position - (model.position - u)
	var along := rel.dot(u)
	return (rel - u * along).length() <= float(cfg.get("board_reach", 3.2)) and absf(along) < 2.5


func _npc_exit_spot(taken: Array) -> Vector3:
	var b := model.transform().basis
	var g := model.ground
	var u := model.up()
	for off in [-b.x * 2.6, b.x * 2.6, b.z * 4.0, -b.x * 2.6 + b.z * 2.0, b.x * 2.6 + b.z * 2.0]:
		var q: Vector3 = model.position + off
		var at: Vector3 = g.surface_below(q) + u * 0.05 if g != null else Vector3(q.x, 0.05, q.z)
		if taken.any(func(t): return (t as Vector3).distance_to(at) < 1.0):
			continue
		if g == null or g.hit(at + u, 0.6) == "":
			return at
	return model.position + u * 0.5


func _body_collision(b: Node, on: bool) -> void:
	for ch in b.get_children():
		if ch is CollisionShape3D:
			ch.set_deferred("disabled", not on)


# ------------------------------------------------------------------ helpers

func _exit_spot() -> Vector3:
	var b := model.transform().basis
	var g := model.ground
	var u := model.up()
	for off in [-b.x * 2.6, b.x * 2.6, b.z * 4.0]:
		var q: Vector3 = model.position + off
		var at: Vector3 = g.surface_below(q) + u * 0.05 if g != null else Vector3(q.x, 0.05, q.z)
		if g == null or g.hit(at + u, 0.6) == "":
			return at
	return model.position + u * 0.5


# ------------------------------------------------------------------ your body in the seat

## Your avatar (the M11 body, in whatever outfit), or null (the greybox has none).
func _player_avatar() -> PlayerAvatar:
	if demo == null or not ("player_kit" in demo) or demo.player_kit == null:
		return null
	var av = demo.player_kit.avatar
	return av if av != null and is_instance_valid(av) else null


## Climbing on a show_driver speeder: your body stays in view, sat in the
## driver's seat (BodyAnimator.sit_pose) with the weapon in hand put out of sight, drawn from outside
## (never first person) and carried by the speeder rather than the player node
## (whose yaw the camera rig keeps turning). True if it is shown.
func _seat_player() -> bool:
	var av := _player_avatar()
	if av == null or not bool(cfg.get("show_driver", false)):
		return false
	seated_avatar = av
	av.set_first_person(false)
	# Settle into the idle stance (it was mid-stride walking up).
	for i in 30:
		av.animate(1.0 / 30.0, { "velocity": Vector3.ZERO, "grounded": true,
			"upper": BodyAnimator.UPPER_FREE, "cam_yaw": av.facing_yaw })
	for w in av.weapons.values():
		(w as Node3D).visible = false    # the next animate on foot shows the one in hand again
	_sit(av.joints)             # the next animate on foot stands it up again
	av._sync_skin()
	av.top_level = true
	_place_seated()
	return true


## The seated body goes where the hull goes: the driver's seat, facing the nose,
## leaning, bobbing and sinking with the look (as the NPC riders sit, plus the lean).
func _place_seated() -> void:
	if seated_avatar == null or not is_instance_valid(seated_avatar):
		return
	var frame := model.transform()
	if visual != null:
		frame = frame * visual.transform
	seated_avatar.global_transform = Transform3D(frame.basis.orthonormalized() * Basis(Vector3.UP, PI),
		frame * seat_offset("driver"))


## Getting off: the body is the player node's again, as it was before climbing on.
func _unseat_player() -> void:
	var av = seated_avatar
	seated_avatar = null
	if av == null or not is_instance_valid(av):
		return
	av.top_level = false
	var rig = demo.get("_rig") if demo != null else null
	av.set_first_person(rig != null and rig.rig != null and rig.rig.is_first_person())
	var p := player()
	var tilt = p.get("tilt") if p != null else null
	av.align_to_ground(tilt if tilt is Basis else Basis.IDENTITY)
	av.reset_render_smoothing()


## Joints (the kit's skeleton, the player's or an NPC's) sat down at the bars.
static func _sit(joints: Dictionary) -> void:
	var sit := BodyAnimator.sit_pose()
	for jn in sit.joints:
		if joints.has(jn):
			(joints[jn] as Node3D).rotation_degrees = sit.joints[jn]
	if joints.has("pelvis"):
		(joints.pelvis as Node3D).position = Vector3(0.0, float(sit.pelvis_y), 0.0)


## A rival at the wheel of a show_driver speeder sits as you do, hands on the
## yoke, its weapon out of sight until it steps off. Seated, its body is not
## animated (seat_npc stops its processing), so the pose holds.
func _sit_npc(b: NpcBody) -> void:
	if b.joints.is_empty() or b.look_body == null or not is_instance_valid(b.look_body):
		return                                 # the greybox capsule: nothing to pose
	_sit(b.joints)
	if b.look_body.has_meta("weapon"):
		var w: Node3D = b.look_body.get_meta("weapon")
		if w != null and is_instance_valid(w) and w.visible:
			w.visible = false
			b.set_meta("seated_weapon", w)
	if b.look_body.has_meta("skin"):
		var sk := b.look_body.get_meta("skin") as SkinnedBody
		sk.holds.clear()                       # the hands let go of the gun
		sk.sync(b.look_body)


func _exit_tree() -> void:
	_unseat_player()           # gone with you aboard (a scene change): give the body back


func _player_collision(on: bool) -> void:
	for ch in player().get_children():
		if ch is CollisionShape3D:
			ch.set_deferred("disabled", not on)


func _burst() -> void:
	var at := model.position
	if riding:
		dismount()
	_throw_riders_clear()
	if not _crash():
		ExplosionFx.big(get_parent(), at + Vector3(0, 0.6, 0), 0.6)
		Sound.play("vehicle_boom", at)
	destroyed.emit(at)
	queue_free()


## Issue #404: with the look on, the speeder's own model tumbles on, hits the sand,
## splits and burns (CrashWreck); a small blast here, the big one at impact. False
## (greybox, no ground): it pops as it always did.
func _crash() -> bool:
	if visual == null or model.ground == null or demo == null or not bool(demo.get("use_look")):
		return false
	var g: WorldGround = model.ground
	var start := { "pos": global_position, "basis": global_transform.basis, "up": model.up(),
		"vel": model.forward() * model.speed + model.up() * model.vy }
	var w := CrashWreck.spawn(get_parent(), "speeder", visual, start, func(p: Vector3) -> Vector3: return g.surface_below(p))
	if w == null:
		return false
	visual = null
	ExplosionFx.big(get_parent(), global_position + model.up() * 0.6, 0.3)
	return true


func _just(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _held(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func _axis(neg: String, pos: String) -> float:
	if not InputMap.has_action(neg) or not InputMap.has_action(pos):
		return 0.0
	return Input.get_axis(neg, pos)


# ------------------------------------------------------------------ look

## An original hover sled (docs/ART_DIRECTION.md: big readable shapes, sand and
## madder red, no franchise silhouettes): a low open tub on two long outrigger
## skids, a ducted fan at the back, a teal glow under the skids.
func _build_visual() -> void:
	var look: Dictionary = cfg.get("look", {})
	# The town's materials: a new LookMaterials builds its own textures, a 60 ms
	# hitch at the moment you buy one.
	var mats: LookMaterials = demo._flat_mats() if demo != null and demo.has_method("_flat_mats") else LookMaterials.new()
	var hullm := mats.flat(Color(str(look.get("hull", "#c9a46a"))), 0.6)
	var trim := mats.flat(Color(str(look.get("trim", "#8e3a26"))), 0.7)
	var metal := mats.flat(Color(str(look.get("metal", "#4a4c52"))), 0.4, 0.6)
	var seat := mats.flat(Color(str(look.get("seat", "#3a2a20"))), 0.9)
	_glow_mat = StandardMaterial3D.new()
	var gc := Color(str(look.get("glow", "#7fe0d0")))
	_glow_mat.albedo_color = gc
	_glow_mat.emission_enabled = true
	_glow_mat.emission = gc
	_glow_mat.emission_energy_multiplier = 2.0
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual = Node3D.new()
	visual.name = "Look"
	add_child(visual)
	var mat_of := { "hull": hullm, "trim": trim, "metal": metal, "seat": seat, "glow": _glow_mat,
		"glass": mats.flat(Color(str(look.get("glass", "#22323f"))), 0.15, 0.3) }
	_mat_of = mat_of
	var scene := str(look.get("paints", {}).get(paint, look.get("scene", "")))
	if _build_model(scene, float(look.get("base_y", -0.65))):
		_build_bolt_ons(look.get("parts", []), mat_of)
		return
	_build_stand_in(look, mat_of)


## Issue #628: extra pieces bolted onto a model (look.parts, the stand-in's piece
## format, in the speeder's frame): what Rodin draws badly, like the racer's
## glowing beam between its fork prongs. Batched and shared like the stand-in;
## glow pieces stay out of the hull (_model_hull skips the glow material).
func _build_bolt_ons(pieces: Array, mat_of: Dictionary) -> void:
	if pieces.is_empty():
		return
	var key := str(pieces).hash()
	if not _stand_ins.has(key):
		_stand_ins[key] = _stand_in_meshes(pieces)
	var meshes: Dictionary = _stand_ins[key].meshes
	for mat_name in meshes:
		_part(meshes[mat_name], mat_of.get(mat_name, mat_of.hull), Vector3.ZERO).name = "Part_" + str(mat_name)


## The driver's yoke (look.yoke: at, scale, mat), for an open cockpit where you
## see the driver (show_driver): the ship cockpit's own yoke (CockpitView.build_yoke,
## a ram's-horn wheel of tube with rubber grips, a trigger cap, a thumb hat and a
## boss), in one of the look's colours. It stays put. Copied from another racer's
## while one is about, so racers share its meshes and materials.
func _build_yoke() -> void:
	var y: Dictionary = cfg.get("look", {}).get("yoke", {})
	if y.is_empty() or visual == null:
		return
	var skin: Material = _mat_of.get(str(y.get("mat", "metal")), _mat_of.get("hull"))
	var key := str(y) + str(skin.get_instance_id() if skin != null else 0)
	# Copied from a racer's yoke still in the world (no orphan template), else built.
	var from = _yokes.get(key)
	var yoke: Node3D = (from as Node3D).duplicate() if from != null and is_instance_valid(from) else CockpitView.build_yoke(skin)
	_yokes[key] = yoke
	yoke.name = "Yoke"
	yoke.position = _v3(y.get("at", [0, 0, 0]))
	yoke.scale = Vector3.ONE * float(y.get("scale", 1.0))
	visual.add_child(yoke)


## Issue #627: the primitive body from data (look.stand_in), built when there is
## no model: the Sand-boxer's old sled, and the racer's and the box truck's until
## issue #628 renders them. Each piece is a box (size) or a cyl (top, bottom, h)
## at `at`, turned `rot` degrees, in one of the look's colours; `mirror` builds it
## on both sides (x and the y and z turns flipped). The pieces end as one mesh per
## colour (docs/RENDER_RULES.md 1 and 5: batched, built from our own numbers),
## shared by every speeder of that look. `fan` is a spinning rear fan. The body's
## size (for the looks parts and the hull) is the pieces' bounds, glow left out,
## and the blasters go on at laser.muzzle as on a model.
func _build_stand_in(look: Dictionary, mat_of: Dictionary) -> void:
	var key := str(look.get("stand_in", [])).hash()
	if not _stand_ins.has(key):
		_stand_ins[key] = _stand_in_meshes(look.get("stand_in", []))
	var built: Dictionary = _stand_ins[key]
	var meshes: Dictionary = built.meshes
	for mat_name in meshes:
		var mi := _part(meshes[mat_name], mat_of.get(mat_name, mat_of.hull), Vector3.ZERO)
		mi.name = "StandIn_" + str(mat_name)
	var box: AABB = built.box
	if box.size != Vector3.ZERO:
		_size = box.size
		_stand_in_box = box
	var fan: Dictionary = look.get("fan", {})
	if not fan.is_empty():
		_fan = Node3D.new()
		_fan.position = _v3(fan.get("at", [0, 0, 0]))
		visual.add_child(_fan)
		var blades := int(fan.get("blades", 3))
		for k in blades:
			var blade := MeshInstance3D.new()
			blade.mesh = LookMeshKit.box(_v3(fan.get("size", [0.12, 1.0, 0.04])))
			blade.material_override = mat_of.get(str(fan.get("mat", "trim")), mat_of.trim)
			blade.rotation.z = k * PI / float(blades)
			_fan.add_child(blade)
	_build_blasters()


## The stand-in's pieces as { meshes: colour -> ArrayMesh, box: bounds without
## the glow }.
static func _stand_in_meshes(pieces: Array) -> Dictionary:
	var tools := {}
	var box := AABB()
	var first := true
	for piece in pieces:
		var pc: Dictionary = piece
		var mat := str(pc.get("mat", "hull"))
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_smooth_group(-1)          # flat, faceted normals
			tools[mat] = st
		var at := _v3(pc.get("at", [0, 0, 0]))
		var rot := _v3(pc.get("rot", [0, 0, 0]))
		var sides: Array = [1.0, -1.0] if bool(pc.get("mirror", false)) else [1.0]
		for side in sides:
			var r := Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y * side), deg_to_rad(rot.z * side))
			var xf := Transform3D(Basis.from_euler(r), Vector3(at.x * side, at.y, at.z))
			var pts: PackedVector3Array
			if str(pc.get("shape", "box")) == "cyl":
				var top := float(pc.get("top", 0.1))
				pts = _add_cyl(tools[mat], xf, top, float(pc.get("bottom", top)), float(pc.get("h", 1.0)))
			else:
				pts = _add_box(tools[mat], xf, _v3(pc.get("size", [1, 1, 1])))
			if mat == "glow":
				continue                     # the hover glow is light, not body
			for q in pts:
				box = AABB(q, Vector3.ZERO) if first else box.expand(q)
				first = false
	var meshes := {}
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.generate_normals()
		meshes[mat] = st.commit()
	return { "meshes": meshes, "box": box }


## A box of `size` centred on xf's origin; returns its corners.
static func _add_box(st: SurfaceTool, xf: Transform3D, size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	var c := PackedVector3Array()
	for k in 8:
		c.append(xf * Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
	var b := xf.basis
	LookMeshKit.add_quad(st, c[1], c[3], c[7], c[5], b.x)     # +x
	LookMeshKit.add_quad(st, c[0], c[4], c[6], c[2], -b.x)    # -x
	LookMeshKit.add_quad(st, c[2], c[6], c[7], c[3], b.y)     # +y
	LookMeshKit.add_quad(st, c[0], c[1], c[5], c[4], -b.y)    # -y
	LookMeshKit.add_quad(st, c[4], c[5], c[7], c[6], b.z)     # +z
	LookMeshKit.add_quad(st, c[0], c[2], c[3], c[1], -b.z)    # -z
	return c


## A cylinder along xf's y, `h` tall, radius `top` above and `bottom` below, 12
## sides, capped; returns its rim points.
static func _add_cyl(st: SurfaceTool, xf: Transform3D, top: float, bottom: float, h: float) -> PackedVector3Array:
	const N := 12
	var up := xf * Vector3(0, h * 0.5, 0)
	var down := xf * Vector3(0, -h * 0.5, 0)
	var rim := PackedVector3Array()
	for k in N + 1:
		var a := TAU * float(k % N) / float(N)
		var d := Vector3(cos(a), 0, sin(a))
		rim.append(xf * (d * top + Vector3(0, h * 0.5, 0)))
		rim.append(xf * (d * bottom + Vector3(0, -h * 0.5, 0)))
	for k in N:
		var a := TAU * (float(k) + 0.5) / float(N)
		var out := xf.basis * Vector3(cos(a), 0, sin(a))
		var t0 := rim[k * 2]
		var b0 := rim[k * 2 + 1]
		var t1 := rim[k * 2 + 2]
		var b1 := rim[k * 2 + 3]
		if top > 0.0001 or bottom > 0.0001:
			LookMeshKit.add_quad(st, t0, t1, b1, b0, out)
		if top > 0.0001:
			LookMeshKit.add_tri(st, up, t0, t1, xf.basis.y)
		if bottom > 0.0001:
			LookMeshKit.add_tri(st, down, b0, b1, -xf.basis.y)
	return rim


static func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


## Issue #43: the Hyper3D speeder (the look's "scene", prepped by
## tools/look/prep_vehicle.gd: facing -Z, metres, centred). Its underside sits at
## `base_y` (where the stand-in's skids are), with the hover glow under it. False
## when there is no model, so the stand-in is built instead.
func _build_model(path: String, base_y: float) -> bool:
	if path == "" or not ResourceLoader.exists(path):
		return false
	var res = ModelCache.scene(path)
	var inst = (res as PackedScene).instantiate() if res is PackedScene else null
	if not (inst is Node3D):
		if inst != null:
			inst.free()
		return false
	var m := inst as Node3D
	m.name = "Model"
	visual.add_child(m)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = _local_xf(mi, m) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	m.position = Vector3(-box.get_center().x, base_y - box.position.y, -box.get_center().z)
	_size = box.size
	for side in [-1.0, 1.0]:
		_part(LookMeshKit.box(Vector3(0.24, 0.04, box.size.z * 0.75)), _glow_mat, Vector3(side * box.size.x * 0.32, base_y - 0.02, 0))
	_build_blasters()
	return true


## Issue #82: the twin blasters under the nose, where the bolts come from
## (laser.muzzle). Bolted on here so every paint job has them.
func _build_blasters() -> void:
	var mats: LookMaterials = demo._flat_mats() if demo != null and demo.has_method("_flat_mats") else LookMaterials.new()
	var gunmetal := mats.flat(Color(str(cfg.get("look", {}).get("metal", "#4a4c52"))), 0.4, 0.6)
	var m := _muzzle()
	for side in [-1.0, 1.0]:
		var at := Vector3(side * m.x, m.y, m.z)
		_part(LookMeshKit.box(Vector3(0.24, 0.2, 0.7)), gunmetal, at + Vector3(0, 0, 1.0)).name = "BlasterHousing"
		_part(LookMeshKit.cyl(0.07, 0.07, 1.0, 12), gunmetal, at + Vector3(0, 0, 0.5), Vector3(90, 0, 0)).name = "Blaster"
		_part(LookMeshKit.cyl(0.09, 0.09, 0.06, 12), _glow_mat, at + Vector3(0, 0, 0.03), Vector3(90, 0, 0))


## Where each laser's bolt starts (the right barrel's tip; the left is mirrored).
func _muzzle() -> Vector3:
	var v: Array = cfg.get("laser", {}).get("muzzle", [0.55, 0.25, -2.4])
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


static func _local_xf(n: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != top:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return top.transform * xf


# ------------------------------------------------------------------ parts (issue #95)

func has_part(id: String) -> bool:
	return (cfg.get("parts", []) as Array).has(id)


## Issue #100: the boosters and the soft-top went missing when you got back in.
## Rebuild the looks parts if any of them is gone (freed, or never built because the
## body was not ready), so whatever the mechanic fitted is always on.
func _ensure_parts() -> void:
	if visual == null:
		return
	var want_boosters := has_part("turbo_boosters")
	var want_roof := has_part("soft_top")
	var have_boosters := not _flames.is_empty() and _flames.all(func(f): return is_instance_valid(f) and (f as Node).is_inside_tree())
	var have_roof := _roof != null and is_instance_valid(_roof) and _roof.is_inside_tree()
	var want_fit := _fit_looks().size() > 0
	var have_fit := _fit_node != null and is_instance_valid(_fit_node) and _fit_node.is_inside_tree()
	if (want_boosters and not have_boosters) or (want_roof and not have_roof) or (want_fit and not have_fit):
		for n in visual.get_children():
			if str(n.name).begins_with("Booster") or n.name == "SoftTop" or n.name == "FitParts":
				n.queue_free()
		_flames = []
		_roof = null
		_fit_node = null
		_build_parts()


## The mechanic's looks parts, on whatever body this is (sized from _size).
func _build_parts() -> void:
	var mats: LookMaterials = demo._flat_mats() if demo != null and demo.has_method("_flat_mats") else LookMaterials.new()
	var metal := mats.flat(Color(str(cfg.get("look", {}).get("metal", "#4a4c52"))), 0.35, 0.7)
	var hx := _size.x * 0.5
	var back := _size.z * 0.5
	var base_y := float(cfg.get("look", {}).get("base_y", -0.65))
	if has_part("turbo_boosters"):
		var flame_mat := StandardMaterial3D.new()
		flame_mat.albedo_color = Color("#ffb060")
		flame_mat.emission_enabled = true
		flame_mat.emission = Color("#ff8a30")
		flame_mat.emission_energy_multiplier = 4.0
		flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flame_mat.albedo_color.a = 0.85
		# Plated like the ships' bolt-ons (ShipKit.plate_material): a gunmetal can,
		# a band in the speeder's trim, a dark flared nozzle with a dim heat glow.
		var can := ShipKit.plate_material(Color(str(cfg.get("look", {}).get("metal", "#4a4c52"))).lightened(0.12))
		var band := ShipKit.plate_material(Color(str(cfg.get("look", {}).get("trim", "#8e3a26"))))
		var nozzle := ShipKit.plate_material(Color("#2a2b2f"))
		if _heat_mat == null:
			_heat_mat = StandardMaterial3D.new()
			_heat_mat.albedo_color = Color("#2a1a12")
			_heat_mat.emission_enabled = true
			_heat_mat.emission = Color("#ff8a40")
			_heat_mat.emission_energy_multiplier = 0.45
		for side in [-1.0, 1.0]:
			# Issue #100: out past the tail, so the body never swallows them.
			var at := Vector3(side * (hx * 0.62), base_y + 0.55, back + 0.1)
			_part(LookMeshKit.cyl(0.19, 0.22, 1.2, 12), can, at, Vector3(90, 0, 0)).name = "Booster"
			_part(LookMeshKit.cyl(0.225, 0.225, 0.1, 12), band, at + Vector3(0, 0, -0.3), Vector3(90, 0, 0)).name = "BoosterBand"
			_part(LookMeshKit.cyl(0.23, 0.2, 0.16, 12), nozzle, at + Vector3(0, 0, 0.66), Vector3(90, 0, 0)).name = "BoosterRing"
			_part(LookMeshKit.cyl(0.12, 0.12, 0.02, 12), _heat_mat, at + Vector3(0, 0, 0.745), Vector3(90, 0, 0)).name = "BoosterGlow"
			var flame := _part(LookMeshKit.cyl(0.16, 0.0, 1.0, 12), flame_mat, at + Vector3(0, 0, 1.2), Vector3(-90, 0, 0))
			flame.name = "BoosterFlame"
			flame.visible = false
			_flames.append(flame)
	if has_part("soft_top"):
		var cloth := mats.canvas(Color(str(cfg.get("look", {}).get("roof", "#8a7456"))))   # woven, sun-faded (StallTextures)
		metal = ShipKit.plate_material(Color(str(cfg.get("look", {}).get("metal", "#4a4c52"))))
		_roof = Node3D.new()
		_roof.name = "SoftTop"
		_roof.position = Vector3(0, base_y + _size.y * 0.78, 0.9)   # the hinge, behind the seat
		visual.add_child(_roof)
		var w := minf(_size.x * 0.7, 1.6)
		for k in [[0.0, 0.0], [-0.55, 0.0], [-1.1, 0.0]]:
			var bar := MeshInstance3D.new()
			bar.mesh = LookMeshKit.box(Vector3(w, 0.05, 0.05))
			bar.material_override = metal
			bar.position = Vector3(0, 0.55, float(k[0]))
			_roof.add_child(bar)
		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			post.mesh = LookMeshKit.box(Vector3(0.05, 0.6, 0.05))
			post.material_override = metal
			post.position = Vector3(side * w * 0.5, 0.27, 0.0)
			_roof.add_child(post)
		var top := MeshInstance3D.new()
		top.mesh = LookMeshKit.box(Vector3(w + 0.06, 0.03, 1.25))
		top.material_override = cloth
		top.position = Vector3(0, 0.6, -0.58)
		_roof.add_child(top)
		for z in [-1.2, 0.04]:                   # the canvas rolled over the front and back bars
			var hem := MeshInstance3D.new()
			hem.mesh = LookMeshKit.cyl(0.035, 0.035, w + 0.06, 12)
			hem.material_override = cloth
			hem.position = Vector3(0, 0.6, z)
			hem.rotation_degrees = Vector3(0, 0, 90)
			_roof.add_child(hem)
	_build_fit_looks()


## The looks of the parts that only change numbers (engines, thrusters, cannons,
## the Grav Lifter, race gear), so what you bought shows: each part's "look" in
## speeder_upgrades.json, pieces at one of this model's look.mounts. Small and in
## the speeder's own metal and trim (ShipKit.plate_material), the glows dim. Every
## piece of every part ends in one mesh per material (docs/RENDER_RULES.md 1),
## shared by every speeder with the same parts.
func _build_fit_looks() -> void:
	var looks := _fit_looks()
	if looks.is_empty() or visual == null:
		return
	var key := str(cfg.get("look", {}).get("scene", "")) + str(cfg.get("parts", []))
	if not _fit_meshes.has(key):
		var pieces: Array = []
		for look: Dictionary in looks:
			pieces.append_array(_mounted(look))
		_fit_meshes[key] = _stand_in_meshes(pieces).meshes
	var lk: Dictionary = cfg.get("look", {})
	var metal := Color(str(lk.get("metal", "#4a4c52")))
	var mat_of := {
		"plate": ShipKit.plate_material(metal.lightened(0.12)),
		"dark": ShipKit.plate_material(Color("#2a2b2f")),
		"trim": ShipKit.plate_material(Color(str(lk.get("trim", "#8e3a26")))),
		"glow": _dim_glow(Color(str(lk.get("glow", "#7fe0d0")))),
	}
	_fit_node = Node3D.new()
	_fit_node.name = "FitParts"
	visual.add_child(_fit_node)
	var meshes: Dictionary = _fit_meshes[key]
	for mat_name in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[mat_name]
		mi.material_override = mat_of.get(mat_name, mat_of.plate)
		if mat_name == "glow":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_fit_node.add_child(mi)


## The fitted parts' looks (each { mount, pieces }).
func _fit_looks() -> Array:
	var out: Array = []
	for id in cfg.get("parts", []):
		var look: Dictionary = SpeederUpgrades.part(str(id)).get("look", {})
		if not look.is_empty():
			out.append(look)
	return out


## A part's pieces placed at its mount, in the speeder's frame: turned by the
## mount's tilt, and a "mirror" piece copied across the centre line (so a right
## side mount's piece gets its left twin).
func _mounted(look: Dictionary) -> Array:
	var mount_id := str(look.get("mount", ""))
	var lk: Dictionary = cfg.get("look", {})
	var at := Vector3.ZERO
	var tilt := 0.0
	match mount_id:
		"muzzle":
			at = _muzzle()
		"belly":
			at = Vector3(0, float(lk.get("base_y", -0.65)), 0)
		_:
			var m: Dictionary = lk.get("mounts", {}).get(mount_id, {})
			if m.is_empty():
				return []                  # this model has no such mount: nothing shows
			at = _v3(m.get("at", [0, 0, 0]))
			tilt = float(m.get("tilt", 0.0))
	var mount := Transform3D(Basis.from_euler(Vector3(deg_to_rad(tilt), 0, 0)), at)
	var flip := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	var out: Array = []
	for pc: Dictionary in look.get("pieces", []):
		var r := _v3(pc.get("rot", [0, 0, 0])) * (PI / 180.0)
		var xf := mount * Transform3D(Basis.from_euler(r), _v3(pc.get("at", [0, 0, 0])))
		var sides: Array = [xf]
		if bool(pc.get("mirror", false)):
			sides.append(Transform3D(flip * xf.basis * flip, flip * xf.origin))
		for t: Transform3D in sides:
			var q := pc.duplicate()
			q.erase("mirror")
			var e := t.basis.get_euler() * (180.0 / PI)
			q["at"] = [t.origin.x, t.origin.y, t.origin.z]
			q["rot"] = [e.x, e.y, e.z]
			out.append(q)
	return out


## A dim glow for the parts (vents, the lifter's rings, the deflector), one per colour.
static func _dim_glow(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if not _dim_glows.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c.darkened(0.5)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.5
		_dim_glows[k] = m
	return _dim_glows[k]


## Boost lights the flames; the roof folds back while someone rides.
func _sync_parts() -> void:
	var lit := model.boosting() and riding
	for f in _flames:
		(f as Node3D).visible = lit
		if lit:
			(f as Node3D).scale = Vector3(1, 0.8 + 0.4 * absf(sin(_t * 41.0)), 1)
	if _roof != null:
		_roof_fold = move_toward(_roof_fold, 1.0 if riding else 0.0, 0.03)
		var e := _roof_fold * _roof_fold * (3.0 - 2.0 * _roof_fold)
		# Issue #100: folded back behind the seat, still in sight (it used to fold
		# down into the body and vanish while you rode).
		_roof.rotation.x = deg_to_rad(-95.0 * e)
		_roof.scale = Vector3(1, 1, lerpf(1.0, 0.55, e))


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	visual.add_child(mi)
	return mi


## The hull: what bolts hit (and what you bump into on foot). Its parent (this
## node) takes the damage.
func _build_hull() -> void:
	hull = StaticBody3D.new()
	hull.name = "Hull"
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = _model_hull()
	if cs.shape == null:
		# Issue #627: no model: the stand-in's own bounds, so bolts hit what you see.
		var shape := BoxShape3D.new()
		var b := _stand_in_box if _stand_in_box.size != Vector3.ZERO else AABB(Vector3(-1.5, -0.7, -2.3), Vector3(3.0, 1.0, 4.6))
		shape.size = b.size
		cs.shape = shape
		cs.position = b.get_center()
	hull.add_child(cs)
	add_child(hull)


## Issue #82: the hull is the model's own shape (its convex hull, blasters and
## all), not a box: bolts that miss the body miss the speeder. One shape per
## model, shared by every speeder that uses it. Null with no model. Issue #628:
## keyed by the look's own model (look.scene), not the paint's file: a paint job
## is a recolour of the same mesh (content/look/vehicle_models.json), so a model
## reads its mesh back once (docs/RENDER_RULES.md 5), not once per paint.
func _model_hull() -> ConvexPolygonShape3D:
	var m := visual.get_node_or_null("Model") as Node3D if visual != null else null
	if m == null:
		return null
	var key := str(cfg.get("look", {}).get("scene", m.scene_file_path)) + str(m.position)
	if _hulls.has(key):
		return _hulls[key]
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override == _glow_mat:
			continue                       # the hover glow is light, not metal
		var xf := _local_xf(mi, visual)
		for sf in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(sf)[Mesh.ARRAY_VERTEX]
			var step := maxi(1, verts.size() / 4000)
			for i in range(0, verts.size(), step):
				pts.append(xf * verts[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	var cloud := ArrayMesh.new()
	cloud.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var shape := cloud.create_convex_shape(true, false)     # just the hull's corners
	_hulls[key] = shape
	return shape


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	_hud.visible = false
	add_child(_hud)
	_readout = Label.new()
	_readout.position = Vector2(18, 54)
	_readout.add_theme_font_size_override("font_size", RetroUI.size("speeder_readout", 24))   # issue #71
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_readout.add_theme_constant_override("outline_size", 4)
	_hud.add_child(_readout)
	var help := Label.new()
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.position = Vector2(-420, -100)
	help.size = Vector2(840, 28)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var shift := "Drift" if model.ability() == "drift" else "Boost"     # issue #627: the box truck drifts
	help.text = ("[W]/[S] Throttle   [A]/[D] Steer   [Shift] %s   [LMB] Lasers   [Space] Grav Lifter on/off ([W]/[S] tilt in the air)   [J] Radio   [E] Get off" \
		if model.has_lifter() else "[W]/[S] Throttle   [A]/[D] Steer   [Shift] %s   [Space]/[LMB] Lasers   [J] Radio   [E] Get off") % shift
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	help.add_theme_constant_override("outline_size", 4)
	_hud.add_child(help)
	feedback = HitFeedback.new()
	add_child(feedback)
	feedback.setup(_hud)
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-300, -170)
	_prompt.size = Vector2(600, 28)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.text = "[E]  Ride speeder"
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.visible = false
	RetroUI.prompt(_prompt)
	layer.add_child(_prompt)


func _show_prompt(on: bool) -> void:
	if _prompt != null:
		_prompt.visible = on


func _update_hud() -> void:
	if _readout == null:
		return
	_readout.text = "SPEEDER\nSPEED  %3d m/s   %3d km/h\nHULL   %3d / %d\n%s  %3d%%%s" % [
		int(absf(model.speed)), int(absf(model.speed) * 3.6), model.hp, model.max_hp,
		"DRIFT" if model.ability() == "drift" else "BOOST",
		int(model.boost_left / maxf(model.p("boost_time", 3.5), 0.001) * 100.0),
		"\nAIRBORNE" if model.airborne else ""]
	if repair_left > 0.0:
		_readout.text += "\nCRASHED  REPAIRING %.1fs" % repair_left
		if weld_t > 0.0:
			_readout.text += "  WELDING %d%%" % int(100.0 * weld_t / maxf(Welder.weld_s(), 0.01))
		elif Welder.owned():
			_readout.text += "  [HOLD E] WELD"
	if model.has_lifter():
		var lifter_text := "%.1fs" % model.lift_cooldown
		if model.lifting():
			lifter_text = "ON %.1fs [SPACE] drop" % model.float_left
		elif model.lift_ready():
			lifter_text = "READY [SPACE]"
		_readout.text += "\nLIFTER %s" % lifter_text
	if gear != null and gear.has_any():
		_readout.text += gear.hud_text()
