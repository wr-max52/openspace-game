class_name HeistCrew
extends Node
## Issue #310: who goes with you on a heist (Heist). While one is on:
##   - a crew member: the side's soldier profile (heist_crew_local / _remnant) as
##     a body in no garrison and no townsfolk, so nobody's alarm is theirs and the
##     guards' senses stay on you. They keep a few steps behind you (on the navmesh
##     where there is one, straight over open sand where there is not), catch up
##     when you run, and turn up on your trail when you leave them far behind.
##     They shoot only whoever is fighting you (DroidController.enemies(): a
##     garrison whose alarm is up, someone who shot at you), so sneaking in works
##     with them along. Barks from content/core/story/heist.json; a short AI card
##     (heist_crew_card.json) you can talk to on [E].
##   - an assassin droid lent by DroidController (lend): it follows and fights like
##     one of yours, but is not in your roster.
## Killed (or knocked out), they stay down for the rest of the heist; the heist
## goes on without them. When it ends (paid, downed, called off, flasks lost) the
## crew member walks off and is gone, and the droid goes home.
##
## Issue #883, on every heist (the story's, the board's, the free chapter's):
##   - rides with you: climb on any speeder with a free rider seat while they are
##     within crew.ride_reach and they hop on behind you ("ride" bark: "Nice
##     ride, comrade."); no seat free and they say so ("no_room") and catch up on
##     foot. Get off (you step off to the left) and they step off across from you.
##     Thrown clear if it bursts, like any rider. The droid follows on foot.
##   - calls the waves out loud (call_out, through shout()): the breach's wave,
##     the speeder wave, the getaway chase and losing it. With them down (or none
##     out) the HUD toasts it instead.
##   - throws a grenade at every speeder wave as it comes in (crew.grenade): within
##     at_m (not nearer than min_m) with a clear line, "Grenade out!". It is aimed
##     where the speeder will be (hit_chance) or miss_m off it; a hit wrecks it
##     (the riders are thrown clear and fight on foot) and they say "Got that one
##     taken care of."; a miss, nothing.
##
## The headless test drives tick() with its own player node.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")

var demo                              ## town_demo.gd (or null in a test)
var player: Node3D
var gear: GearController
var body: NpcBody                     ## the crew member, while one is out
var spot: TalkSpot
var host
var fights := 0                       ## shots fired at enemies, for tests and traces
var _run := -1                        ## the heist run the crew is out for
var _leaving := 0.0                   ## > 0: walking off, seconds left before they go
var _leave_to := Vector3.INF
var _burst := 0.0
var _rest := 0.0
var _bark_cd := 0.0
var _foe: Node3D
var _free_walk_left := 0.0
var _fails_seen := 0
var _was_hacked := false
## Issue #883.
var seat_in: SpeederNode              ## the speeder they ride in, while they do
var _ride_tried: SpeederNode          ## the speeder you climbed on that they already tried to ride
var _nade_for: SpeederNode            ## the speeder wave they already threw at
var grenades := 0                     ## thrown, for tests and traces
var grenade_hits := 0
var force_grenade_hit := -1           ## tests: 1 always hits, 0 always misses, -1 rolls hit_chance


func setup(p_demo, p_player: Node3D, p_gear: GearController) -> void:
	demo = p_demo
	player = p_player
	gear = p_gear
	name = "HeistCrew"
	if demo != null and demo.get("pilot") != null:
		demo.pilot.woke.connect(_on_woke)


func attach_host(h) -> void:
	host = h


func c(key: String, fallback: float) -> float:
	return float(Heist.crew_cfg().get(key, fallback))


func _bark(kind: String) -> void:
	var lines: Array = Heist.crew_cfg().get("barks", {}).get(kind, [])
	if body != null and is_instance_valid(body) and not body.dead and not lines.is_empty():
		body.say(str(lines[randi() % lines.size()]), 3.0)
		_bark_cd = maxf(_bark_cd, 2.5)        # a fight bark does not talk over it


## Issue #883: the crew member is out and alive, and says `kind` (a bark pool).
## False when there is nobody to say it.
func call_out(kind: String) -> bool:
	if body == null or not is_instance_valid(body) or body.dead or _leaving > 0.0:
		return false
	if (Heist.crew_cfg().get("barks", {}).get(kind, []) as Array).is_empty():
		return false
	_bark(kind)
	return true


## Issue #883: what the heist wants called out (`kind`: "wave", "speeder_wave",
## "chase", "chase_lost"): the crew member shouts it, else the HUD toasts the
## line of the same name.
static func shout(p_demo, kind: String) -> void:
	var crew = p_demo.get("heist_crew") if p_demo != null else null
	if crew != null and is_instance_valid(crew) and crew.call_out(kind):
		return
	var gear = p_demo.get("gear") if p_demo != null else null
	if gear != null and gear.hud != null and Heist.line(kind) != "":
		gear.hud.toast(Heist.line(kind), 5.0)


func _toast(text: String) -> void:
	if text != "" and gear != null and gear.hud != null:
		gear.hud.toast(text, 5.0)


## You woke up after being downed: the heist is off, or (issue #550) another
## player's heist goes on without you.
func _on_woke() -> void:
	if Heist.on_downed():
		_toast(Heist.line("downed"))
	elif Heist.on():
		_toast(Heist.line("downed_shared"))


func _physics_process(dt: float) -> void:
	tick(dt)


## One frame: the crew follow the heist's state.
func tick(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if Heist.on() and Heist.check_lost():
		_toast(Heist.line("lost"))
	if not Heist.on():
		_dismiss(dt)
		return
	var run := int(WorldState.heist.get("run", 0))
	if run != _run:
		_run = run
		_leaving = 0.0
		_was_hacked = false
		_nade_for = null
	if bool(player.get("piloting")):
		var v = player.get("vehicle")
		if v is SpeederNode and (v as SpeederNode).riding:
			_ride(v)                    # issue #883: they hop on behind you
		return                          # they wait while you fly; they catch up on landing
	_ride_tried = null
	_off_speeder()
	_sync_droid()
	if body == null and not bool(WorldState.heist.get("crew_down", false)):
		_spawn()
	if body != null and is_instance_valid(body) and not body.dead:
		_drive(dt)
		_tick_grenade()
		if Heist.hacked() and not _was_hacked:
			_bark("hacked")
	_was_hacked = Heist.hacked()


# ------------------------------------------------------------------ the ride (issue #883)

## You ride speeder `v`: they climb into a free rider seat once, if they are near.
func _ride(v: SpeederNode) -> void:
	if body == null or not is_instance_valid(body) or body.dead or _leaving > 0.0:
		return
	if seat_in == v and v.npc_seats.values().has(body):
		return                          # aboard
	if seat_in != null and seat_in != v:
		_off_speeder()
	if _ride_tried == v:
		return
	_ride_tried = v
	if body.global_position.distance_to(v.model.position) > c("ride_reach", 14.0):
		return                          # too far back: they catch up on foot when you stop
	var seat := free_rider_seat(v)
	if seat == "":
		_bark("no_room")
		return
	if v.seat_npc(body, seat):
		seat_in = v
		_bark("ride")


## A rider seat on `v` nobody has (not the driver's: that is yours), or "".
static func free_rider_seat(v: SpeederNode) -> String:
	for seat in v.seat_names():
		if str(seat) != "driver" and v.seat_free(str(seat)):
			return str(seat)
	return ""


## You got off: they step off across from you (you get off to the left). Thrown
## clear (it burst) or shot off, they are already on their feet.
func _off_speeder() -> void:
	var v := seat_in
	seat_in = null
	if v == null or not is_instance_valid(v) or body == null or not is_instance_valid(body):
		return
	if not v.npc_seats.values().has(body):
		return
	var right := v.model.transform().basis.x
	var mine: float = (player.global_position - v.model.position).dot(right)
	v.step_off(body, -1.0 if mine > 0.0 else 1.0)
	body.stop()


# ------------------------------------------------------------------ the grenade (issue #883)

## The speeder wave coming in: one grenade at it, from the crew member on foot.
func _tick_grenade() -> void:
	var raid = demo.get("heist_raid") if demo != null else null
	if raid == null or seat_in != null or _leaving > 0.0:
		return
	var s: SpeederNode = raid.coming()
	if s == null or s == _nade_for:
		return
	var gc: Dictionary = Heist.crew_cfg().get("grenade", {})
	var d := body.global_position.distance_to(s.model.position)
	if d > float(gc.get("at_m", 45.0)) or d < float(gc.get("min_m", 12.0)) or not _clear(s.hull if s.hull != null else s):
		return
	_nade_for = s
	throw_at(s)


## Throw a grenade at speeder `s`: where it will be when the grenade gets there
## (a hit, by hit_chance) or miss_m off it, bursting on arrival (or on touching
## anything). Returns the grenade (tests).
func throw_at(s: SpeederNode) -> Grenade:
	var gc: Dictionary = Heist.crew_cfg().get("grenade", {})
	var cfg: Dictionary = CoreContent.read_json(Grenade.CFG_PATH).duplicate()
	cfg["blast_damage"] = float(gc.get("blast_damage", cfg.get("blast_damage", 400)))
	var hit := randf() < float(gc.get("hit_chance", 0.4)) if force_grenade_hit < 0 else force_grenade_hit == 1
	var from := body.eye_position()
	var d := from.distance_to(s.model.position)
	var fl: Array = gc.get("flight_s", [0.9, 1.8])
	var t := lerpf(float(fl[0]), float(fl[1]), clampf(d / maxf(float(gc.get("at_m", 45.0)), 1.0), 0.0, 1.0))
	var up := PlanetSphere.current.up_at(from) if PlanetSphere.current != null else Vector3.UP
	var aim: Vector3 = s.model.position + s.model.forward() * s.model.speed * t + up * 0.6
	if not hit:
		var mm: Array = gc.get("miss_m", [11.0, 17.0])
		var dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		dir -= up * dir.dot(up)
		aim += (dir.normalized() if dir.length() > 0.01 else up.cross(Vector3.RIGHT).normalized()) * randf_range(float(mm[0]), float(mm[1]))
	var g := float(cfg.get("gravity", 20.0))
	var vel := (aim - from) / t + up * g * t * 0.5
	var nade := Grenade.new()
	nade.setup(cfg, from, vel, body)
	nade.fuse_left = t
	nade.player = player
	var into: Node = demo if demo is Node else self
	into.add_child(nade)
	nade.burst.connect(_on_nade_burst.bind(s))
	grenades += 1
	_bark("grenade")
	return nade


func _on_nade_burst(_at: Vector3, hurt: Array, s) -> void:
	if hurt.has(s) or not is_instance_valid(s) or not (s as SpeederNode).model.alive():
		grenade_hits += 1
		_bark("grenade_hit")


# ------------------------------------------------------------------ the droid

func _sync_droid() -> void:
	var dc = demo.get("droids") if demo != null else null
	if dc == null:
		return
	if dc.lent_down:
		WorldState.heist["droid_down"] = true
	if bool(WorldState.heist.get("droid_down", false)):
		return
	var side: Dictionary = Heist.crew_cfg().get(Heist.side(), {})
	dc.lend("assassin", str(side.get("droid", "white")))


# ------------------------------------------------------------------ the crew member

func _spawn() -> void:
	if demo == null or not demo.has_method("make_npc"):
		return
	var side: Dictionary = Heist.crew_cfg().get(Heist.side(), {})
	var soldier: Dictionary = demo._content().get_soldier(str(side.get("soldier", "heist_crew_local")))
	if soldier.is_empty():
		return
	var at := _behind(c("follow", 3.0))
	var key := "npc:heist_crew/%d" % _run
	body = demo.make_npc(soldier, at, player.rotation.y, "heist_crew", key)
	if body == null:
		return
	body.set_meta("heist_crew", true)
	body.died.connect(_on_died)
	if str(WorldState.heist.get("crew", "")) == "":
		WorldState.heist["crew"] = body.display_name if body.display_name != "" else "your crew"
		_toast(Heist.line("joined") % Heist.crew_name())
		_bark("start")
	_add_spot()


func _on_died() -> void:
	WorldState.heist["crew_down"] = true
	_toast(Heist.line("crew_down") % Heist.crew_name())
	_drop_spot()


const BLOCK_PROBE_H := 0.5           ## the wall check runs this high off the ground (m), as the droids'


## A point `back` metres behind you, on the sand. You face +Z (CharacterBody
## walks along its basis.z), so behind is -Z: the old -basis.z put the crew
## member in front of you, behind the bar where Oda stands. Pulled in short of
## a wall between you and the point (a ray at knee height), so they never turn
## up on the far side of a wall or a counter.
func _behind(back: float) -> Vector3:
	var fwd := player.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.BACK
	var from: Vector3 = player.global_position
	var at: Vector3 = from - fwd.normalized() * back
	if player.is_inside_tree():
		var lift := Vector3(0, BLOCK_PROBE_H, 0)
		var q := PhysicsRayQueryParameters3D.create(from + lift, at + lift, 1)
		if player is CollisionObject3D:
			q.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and absf((hit.normal as Vector3).y) < 0.7:
			var dir := (at - from).normalized()
			at = (hit.position as Vector3) - lift - dir * 0.6
	return at + Vector3(0, 0.3, 0)


## Follow, or fight whoever is fighting you.
func _drive(dt: float) -> void:
	_bark_cd -= dt
	var d := body.global_position.distance_to(player.global_position)
	if d > c("rejoin", 45.0):
		body.global_position = _behind(c("follow", 3.0) + 2.0)      # left far behind: on your trail
		body.stop()
		return
	_walk_mode(dt)
	_foe = _enemy()
	if _foe != null:
		_fight(dt)
		if d > c("catch_up", 9.0):
			body.go_to(_behind(c("follow", 3.0)), true)
		else:
			body.stop()
		return
	body.aim_point = Vector3.INF
	body.hold_fire(dt)
	body.clear_face()
	if d > c("follow", 3.0) + 1.0:
		body.go_to(_behind(c("follow", 3.0)), d > c("catch_up", 9.0))
	elif body.command.go_to != Vector3.INF:
		body.stop()


## The navmesh where it has a path, straight over the sand where it does not
## (the desert between the town and the outposts has none).
func _walk_mode(dt: float) -> void:
	if demo == null:
		return
	if _free_walk_left > 0.0:
		_free_walk_left -= dt
		if _free_walk_left <= 0.0:
			body.nav = demo.nav
			body.free_walk = false
			_fails_seen = body.path_failures
		return
	if body.path_failures > _fails_seen:
		_fails_seen = body.path_failures
		body.nav = null
		body.free_walk = true
		_free_walk_left = 3.0


## The nearest one fighting you, in range with a clear line, or null.
func _enemy() -> Node3D:
	var dc = demo.get("droids") if demo != null else null
	if dc == null:
		return null
	var best: Node3D = null
	var best_d := c("range", 35.0)
	for e in dc.enemies():
		if not is_instance_valid(e) or e == body:
			continue
		var dd: float = body.global_position.distance_to(e.global_position)
		if dd < best_d and _clear(e):
			best = e
			best_d = dd
	return best


func _clear(e: Node3D) -> bool:
	if not body.is_inside_tree():
		return true
	var to := _chest(e)
	var q := PhysicsRayQueryParameters3D.create(body.eye_position(), to)
	q.exclude = [body.get_rid(), player.get_rid()] if player is CollisionObject3D else [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var col: Object = hit.collider
	return col == e or (col is Node and (e.is_ancestor_of(col) or (col as Node).is_ancestor_of(e)))


func _chest(e: Node3D) -> Vector3:
	if e.has_method("center"):
		return e.center()
	if e.has_method("eye_position"):
		return e.eye_position() - Vector3(0, 0.3, 0)
	return e.global_position + Vector3(0, 1.2, 0)


## Bursts at the foe's chest once the rifle is up.
func _fight(dt: float) -> void:
	var at := _chest(_foe)
	body.face_point(at)
	body.aim_point = at
	if _bark_cd <= 0.0:
		_bark("fight")
		_bark_cd = c("bark_s", 7.0)
	if _rest > 0.0:
		_rest -= dt
		body.hold_fire(dt)
		return
	_burst += dt
	if _burst >= c("burst_s", 1.2):
		_burst = 0.0
		_rest = c("rest_s", 0.9)
	if body.carry.on_target():
		if body.fire_at(at, dt):
			fights += 1
	else:
		body.hold_fire(dt)


# ------------------------------------------------------------------ talk

func _add_spot() -> void:
	if host == null or body == null:
		return
	var card := NpcBrain._read(str(Heist.crew_cfg().get("card", "res://content/core/npcs/heist_crew_card.json")))
	card["name"] = Heist.crew_name()
	var brain := NpcBrain.new(null, card)
	brain.extra_brief = _brief
	spot = TalkSpot.new(brain, body, body.global_position)
	spot.radius = 2.2
	spot.face_height = 1.6
	host.add_spot(spot)


func _drop_spot() -> void:
	if host != null and spot != null:
		if host.active == spot:
			host.end_talk()
		host.spots.erase(spot)
	spot = null


## What the crew member knows: whose side, the outpost, who holds it, how many guards.
func _brief() -> Array:
	var id := Heist.target()
	var holder := Territory.owner(id)
	var guards := 0
	var ro = demo.get("outposts") if demo != null else null
	if ro != null:
		var o: Dictionary = ro.outpost(id)
		if not o.is_empty():
			guards = ro.people(o, holder).filter(func(g): return not g.dead).size()
	var mine := "the locals (the port's own people)" if Heist.side() == "locals" else "the Remnant (the old empire's army)"
	var them := "the Remnant" if holder == Territory.REMNANT else "the locals"
	var stage := "the flasks are in hand; now get them home" if Heist.holding() else \
		("the console is hacked; the stash lies in front of it" if Heist.hacked() else "you have not got in yet")
	return ["THE JOB: you work for %s. The target is the control room at %s, held by %s with %d guards there. Status: %s. Your cut is %d%% of the pay." % [
		mine, Story.outpost_label(id), them, guards, stage, roundi(Heist.cut() * 100.0)]]


# ------------------------------------------------------------------ the end

## The heist is over: the crew member walks off and is gone; the droid goes home.
func _dismiss(dt: float) -> void:
	var dc = demo.get("droids") if demo != null else null
	if dc != null and not dc.lent.is_empty():
		dc.give_back()
	if body == null:
		return
	if not is_instance_valid(body):
		body = null
		return
	if _leaving <= 0.0 and not body.dead:
		_drop_spot()
		_leaving = c("leave_s", 8.0)
		if str(WorldState.heist.get("ended", "")) == "paid":
			_bark("paid")
		var away: Vector3 = body.global_position - player.global_position
		away.y = 0.0
		_leave_to = body.global_position + (away.normalized() if away.length() > 0.1 else Vector3.BACK) * 40.0
		body.go_to(_leave_to)
		return
	_leaving -= dt
	if _leaving <= 0.0 or body.dead:
		_drop_spot()
		body.queue_free()
		body = null
		_leaving = 0.0


func _process(dt: float) -> void:
	if spot != null and body != null and is_instance_valid(body):
		spot.stand = body.global_position
	# Seated, their own frame is off (SpeederNode.seat_npc): their line over
	# their head still goes when its time is up.
	if seat_in != null and body != null and is_instance_valid(body) and not body.is_processing() and body._speech_left > 0.0:
		body._speech_left -= dt
		if body._speech_left <= 0.0:
			body.say("")
