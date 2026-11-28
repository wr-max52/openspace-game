class_name HeistRaid
extends Node
## Issue #883: the speeders on a heist (content/core/story/heist.json). Every heist,
## either side's: the story's, the board's and the free chapter's.
##
##   the speeder wave  the third wave (the outpost's own guards, the breach's
##                     wave on foot, then this). With hack.speeder_wave.at_left_s
##                     left on the breach, a speeder of the side being robbed
##                     (Heist.wave_side: its paint, Heist.wave_paint) with `count`
##                     of the wave's soldier aboard turns up `dist` metres out on
##                     the door's side, comes in at full boost (driver skill
##                     `skill`), pulls up `park_m` out from the console on the
##                     door's side, and everyone gets off and fights (the
##                     outpost's wave: RemnantOutposts.join_wave). Once a heist
##                     (Heist "speeder_waved"). The crew calls it out and throws a
##                     grenade at it as it comes in (HeistCrew). Left behind
##                     empty, it is anyone's to ride.
##   the getaway       once the vault is breached, ride a speeder more than
##                     getaway.start_m from the console and a speeder of the
##                     robbed side with a driver and a gunner turns up spawn_m
##                     away, beyond the outpost, and comes after you: the chase
##                     loop the gate chase runs (SpeederChase), its driver on the
##                     harass loop (SpeederBrain.harass, skill `skill`: ram,
##                     tail and shoot, pass, drop back, tail). A ram jolts your
##                     speeder (ram_damage, ram_slow). Boost and you get away
##                     (past escape_m for give_up_s: they give up and are gone);
##                     dawdle and they keep shooting. Get off or get thrown off and
##                     they pull up and fight on foot, as at the gate; their
##                     speeder is left empty for you to take. Once a heist
##                     (Heist "chased").
##
## Anything of theirs you leave more than getaway.gone_m behind (nobody riding
## it) is cleared away. A LAN guest's town sends neither (the host's does).
##
## The headless test drives tick() and the public calls directly.

var demo                              ## town_demo.gd
var ground: WorldGround
## The speeder wave.
var raid: SpeederNode
var raid_state := ""                  ## "" | "coming" | "parking" | "off"
var raid_riders: Array = []
var raids := 0                        ## speeder waves sent (tests, traces)
var raid_wrecked := false
var _raid_park := Vector3.INF
var _raid_yaw := 0.0
var _raid_t := 0.0
## The getaway.
var chaser: SpeederNode
var chase: SpeederChase
var chase_riders: Array = []
var chase_garrison: Garrison
var chases := 0
var escapes := 0
var rams := 0
var _rams_seen := 0
var _reboarding := false


func setup(p_demo, p_ground: WorldGround) -> void:
	demo = p_demo
	ground = p_ground
	name = "HeistRaid"


func _physics_process(dt: float) -> void:
	tick(dt)


func tick(dt: float) -> void:
	if demo == null or bool(demo.get("lan_shared")):
		return
	_tick_raid(dt)
	_tick_getaway(dt)
	_tidy()


## The speeder wave while it is still coming in with people aboard, else null
## (what the crew throws at).
func coming() -> SpeederNode:
	if raid == null or not is_instance_valid(raid) or raid_state != "coming" or not raid.model.alive():
		return null
	return raid if not raid.npc_seats.is_empty() else null


func _player():
	return demo._player if demo != null else null


func _outposts():
	return demo.get("outposts") if demo != null else null


# ------------------------------------------------------------------ the speeder wave

func _tick_raid(dt: float) -> void:
	if raid == null:
		var ro = _outposts()
		if ro == null or ro.running_at == "" or ro.running < 0.0 \
				or ro.running > float(Heist.speeder_wave_cfg().get("at_left_s", 30.0)):
			return
		var o: Dictionary = ro.outpost(ro.running_at)
		if o.is_empty() or not Heist.take_once("speeder_waved"):
			return
		send_raid(o)
		return
	if not is_instance_valid(raid):
		raid = null
		return
	match raid_state:
		"coming":
			if raid.brain == null or not raid.npc_driven():
				_raid_off()              # the driver is down: the rest get off where it stopped
			elif raid.brain.done:
				raid.brain.park(_raid_park, _raid_yaw)
				raid_state = "parking"
				_raid_t = 0.0
		"parking":
			_raid_t += dt
			if raid.brain == null or not raid.npc_driven() or raid.brain.done \
					or (_raid_t > 1.0 and absf(raid.model.speed) < 1.5) \
					or _raid_t > float(Heist.speeder_wave_cfg().get("settle_s", 6.0)):
				_raid_off()


## Send the speeder wave at outpost `o` now (the hack's timer calls it; tests too).
func send_raid(o: Dictionary) -> SpeederNode:
	var ro = _outposts()
	if ro == null or o.is_empty():
		return null
	var wc := Heist.speeder_wave_cfg()
	var c: Vector3 = o.room.stand if o.has("room") else Vector3.ZERO
	var a := randf_range(-0.6, 0.6)            # round the door's side (+x local, toward the town)
	var start: Vector3 = ro.world_point(o, c + Vector3(cos(a), 0.0, sin(a)) * float(wc.get("dist", 500.0)))
	_raid_park = ro.world_point(o, c + Vector3(float(wc.get("park_m", 14.0)), 0.0, 0.0))
	var dir := _raid_park - start
	_raid_yaw = atan2(-dir.x, -dir.z)          # HoverModel yaw: 0 faces -Z
	var holder := Heist.wave_side()
	raid = SpeederNode.new()
	raid.setup(demo, ground, {}, true, Heist.wave_paint(holder))
	add_child(raid)
	raid.name = "HeistRaidSpeeder"
	raid.place(start + _up(start) * 1.0, _raid_yaw)
	raid.set_meta("heist_raid", int(WorldState.heist.get("run", 0)))
	raid.destroyed.connect(_on_raid_destroyed)
	raid_wrecked = false
	raid_riders.clear()
	var soldier := Heist.wave_soldier(holder)
	var run := int(WorldState.heist.get("run", 0))
	var id := str(o.id)
	var seats := _seats(raid)
	for i in mini(int(wc.get("count", 4)), seats.size()):
		var g: NpcBody = demo.make_soldier(soldier, start, _raid_yaw,
			"%s/heist_raid_%d" % [id, i], "npc:%s/heist_raid/%d#%d" % [id, run, i])
		if g == null:
			continue
		raid.seat_npc(g, str(seats[i]))
		raid_riders.append(g)
	if not raid_riders.is_empty():
		ro.join_wave(o, raid_riders)
	raid.brain = SpeederBrain.new(raid.model, str(wc.get("skill", "wave_rush")), 883)
	raid.brain.follow([_raid_park], false)
	raid_state = "coming"
	raids += 1
	HeistCrew.shout(demo, "speeder_wave")
	return raid


## The speeder's seats, the driver's first.
static func _seats(s: SpeederNode) -> Array:
	var out: Array = s.seat_names().duplicate()
	if out.has("driver"):
		out.erase("driver")
		out.push_front("driver")
	return out


## Pulled up (or the driver is down): everyone off, to fight.
func _raid_off() -> void:
	if raid != null and is_instance_valid(raid):
		raid.step_off()
		raid.brain = null
		raid.model.set_command(0.0, 0.0)
	raid_state = "off"


func _on_raid_destroyed(_at: Vector3) -> void:
	raid_wrecked = true                        # the riders were thrown clear (SpeederNode)
	raid_state = "off"
	raid = null


# ------------------------------------------------------------------ the getaway

func _tick_getaway(dt: float) -> void:
	var p = _player()
	if chaser == null:
		if not Heist.on() or not Heist.hacked() or not SpeederChase.riding(p):
			return
		var ro = _outposts()
		if ro == null:
			return
		var o: Dictionary = ro.outpost(Heist.target())
		if o.is_empty():
			return
		var v: SpeederNode = p.vehicle
		if v.model.position.distance_to(ro.console_point(o)) < float(Heist.getaway_cfg().get("start_m", 150.0)):
			return
		if not Heist.take_once("chased"):
			return
		start_getaway(o)
		return
	if not is_instance_valid(chaser):
		chaser = null
		chase = null
		return
	if chase == null:
		return
	match chase.tick(dt, p):
		"stepped_off":
			_rehome()
		"lost":
			escapes += 1
			HeistCrew.shout(demo, "chase_lost")
			_drop_getaway()
			return
	if chaser != null and chaser.brain != null and chaser.brain.rams > _rams_seen:
		_rams_seen = chaser.brain.rams
		_ram(p)
	_tick_reboard(p)


## Send the getaway chaser after you now, from beyond outpost `o` (tests too).
func start_getaway(o: Dictionary) -> SpeederNode:
	var p = _player()
	var ro = _outposts()
	if p == null or ro == null:
		return null
	var gc := Heist.getaway_cfg()
	var me: Vector3 = SpeederChase.target_of(p)[0]
	var up := _up(me)
	var back: Vector3 = ro.console_point(o) - me
	back -= up * back.dot(up)
	if back.length() < 1.0:
		back = Vector3.FORWARD
	var at := me + back.normalized() * float(gc.get("spawn_m", 450.0))
	if ground != null:
		at = ground.surface_below(at + up * 200.0)
	var dir := me - at
	var yaw := atan2(-dir.x, -dir.z)
	var holder := Heist.wave_side()
	chaser = SpeederNode.new()
	chaser.setup(demo, ground, {}, true, Heist.wave_paint(holder))
	add_child(chaser)
	chaser.name = "HeistChaseSpeeder"
	chaser.place(at + up * 1.0, yaw)
	chaser.set_meta("heist_chaser", int(WorldState.heist.get("run", 0)))
	chaser.destroyed.connect(_on_chaser_destroyed)
	chase_riders.clear()
	var soldier: Dictionary = demo._content().get_soldier(Heist.wave_soldier(holder))
	var seats := ["driver", "rider"]
	for i in mini(int(gc.get("riders", 2)), seats.size()):
		if soldier.is_empty():
			break
		var b: NpcBody = demo.make_npc(soldier, at, yaw, "heist_chase/%d" % i, "npc:heist_chase/%d#%d" % [int(WorldState.heist.get("run", 0)), i], self)
		if b == null:
			continue
		chaser.seat_npc(b, seats[i])
		chase_riders.append(b)
	if not chase_riders.is_empty() and demo.has_method("_make_garrison"):
		chase_garrison = demo._make_garrison("HeistChase", chase_riders, false, Vector3.INF, true, [])
		chase_garrison.respawn_rule = Callable()    # the dead stay dead
		chase_garrison.place = str(o.get("label", ""))
		chase_garrison.join_alarm(me, "heist")
	chaser.brain = SpeederBrain.new(chaser.model, str(gc.get("skill", "heist_chaser")), 884)
	chaser.brain.harass = true
	chase = SpeederChase.new(chaser, float(gc.get("pull_up_m", 18.0)), float(gc.get("escape_m", 600.0)), float(gc.get("give_up_s", 4.0)))
	chase.start()
	_rams_seen = 0
	_reboarding = false
	chases += 1
	HeistCrew.shout(demo, "chase")
	return chaser


## It rammed you: a jolt, lost speed and a dent; it bounces off slower too.
func _ram(p) -> void:
	rams += 1
	if not SpeederChase.riding(p):
		return
	var v: SpeederNode = p.vehicle
	var gc := Heist.getaway_cfg()
	v.model.speed *= float(gc.get("ram_slow", 0.7))
	v.jolt.start()
	v.apply_damage(float(gc.get("ram_damage", 8.0)))
	if chaser != null and is_instance_valid(chaser):
		chaser.model.speed *= 0.5
	Sound.play("ship_hit", v.model.position)


## On foot far from where they set off: their post is where they stand, so they
## fight you here instead of walking back.
func _rehome() -> void:
	for b in _alive(chase_riders):
		b.post_pos = b.global_position
		if chase_garrison != null and is_instance_valid(chase_garrison) and chase_garrison.brains.has(b):
			chase_garrison.brains[b].patrol_points = [b.global_position]


## They got off to fight and you rode off again (not on their speeder): back on
## theirs and after you.
func _tick_reboard(p) -> void:
	if chase == null or chaser == null or not is_instance_valid(chaser) or not chaser.model.alive():
		return
	if chase.state != SpeederChase.State.IDLE:
		_reboarding = false
		return
	if _reboarding:
		if chaser.npc_driven():
			chase.start()
			_reboarding = false
		return
	if not SpeederChase.riding(p) or p.vehicle == chaser or not chaser.npc_seats.is_empty():
		return
	var alive := _alive(chase_riders)
	if alive.is_empty():
		return
	var seats := ["driver", "rider"]
	for i in mini(alive.size(), 2):
		chaser.board(alive[i], seats[i])       # climbs on at once in reach, else walks up first
	_reboarding = true


func _on_chaser_destroyed(_at: Vector3) -> void:
	_rehome()                                  # thrown clear: they fight on where they landed
	chaser = null
	if chase != null:
		chase.state = SpeederChase.State.IDLE


## They gave up: out of sight already, so gone.
func _drop_getaway() -> void:
	if chase_garrison != null and is_instance_valid(chase_garrison):
		chase_garrison.queue_free()
	chase_garrison = null
	for b in chase_riders:
		if is_instance_valid(b):
			b.queue_free()
	chase_riders.clear()
	if chaser != null and is_instance_valid(chaser) and not chaser.riding:
		chaser.queue_free()
	chaser = null
	chase = null


static func _alive(bodies: Array) -> Array:
	return bodies.filter(func(b): return is_instance_valid(b) and not b.dead)


# ------------------------------------------------------------------ clearing up

## Anything of theirs you left far behind (gone_m), nobody riding it, goes.
func _tidy() -> void:
	var p = _player()
	if p == null or not is_instance_valid(p):
		return
	var me: Vector3 = SpeederChase.target_of(p)[0]
	var gone := float(Heist.getaway_cfg().get("gone_m", 300.0))
	if raid != null and is_instance_valid(raid) and raid_state == "off" and not raid.riding \
			and raid.model.position.distance_to(me) > gone:
		raid.queue_free()
		raid = null
	if chaser == null and chase == null and not chase_riders.is_empty():
		var near := chase_riders.any(func(b): return is_instance_valid(b) and b.global_position.distance_to(me) <= gone)
		if not near:
			_drop_getaway()
	elif chaser != null and is_instance_valid(chaser) and chase != null and chase.state == SpeederChase.State.IDLE \
			and not chaser.riding and chaser.model.position.distance_to(me) > gone \
			and not chase_riders.any(func(b): return is_instance_valid(b) and b.global_position.distance_to(me) <= gone):
		_drop_getaway()


func _up(at: Vector3) -> Vector3:
	var sp = ground.sphere() if ground != null else null
	return (at - sp.center).normalized() if sp != null else Vector3.UP
