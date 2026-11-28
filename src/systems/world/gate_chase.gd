class_name GateChase
extends Node3D
## Issue #613: the gate chase (content/core/flow/gate_chase.json).
##
## Whoever holds the town (the Remnant while Story.town_garrison(), else the
## locals) has the gate speeder (TownDemo._park_gate_speeders, now rideable) and a
## chase speeder on the 'chase_speeder' marker with two guards standing by it. The
## guards are members of the holder's garrison (Garrison.add_member), so on foot
## they are troopers like any other.
##
##   steal       climb on the gate speeder: the holder's alarm goes up.
##   the chase   their alarm up and you on any speeder: the two climb on, a driver
##               and a gunner behind (SpeederNode seats, #609), and ride after you.
##               The driver pursues (SpeederBrain) and fires the speeder's lasers;
##               the gunner's rifle is the garrison brain's.
##   on foot     you get off: they pull up nearby, climb off and fight on foot.
##   escape      more than escape_m away for give_up_s: they give up, drive home,
##               park and stand by it again.
##   wreck       the chase speeder bursts: both thrown clear, and they fight on;
##               a new one stands on the marker respawn_s later.
##   the prize   get away on the stolen gate speeder (they give up, or both are
##               dead): it is yours (SpeederPost.adopt, marked stolen). Ride it to
##               Skrugs's stall and [Z] sells it to him.
##   no chase    nobody can come after you (no alarm, no garrison, no riders or
##               no chase speeder): ride it more than escape_m from where it was
##               parked and it is yours all the same.
##   full row    you own all the speeders you can (SpeederPost.owned_cap): a toast
##               says so and it stays a loose speeder, not yours and not saved.
##               Riding it again raises no alarm; it becomes yours the next time
##               you climb on with room in the row.
##
## Issue #883: the chase itself (pursue, pull up, give up) is SpeederChase, the
## loop the heist's getaway (HeistRaid) runs too.
##
## The headless test drives tick() and the public calls directly.

enum State { IDLE, CHASE, PULL_UP, RETURN }

const CFG_PATH := "res://content/core/flow/gate_chase.json"
static var _cfg: Dictionary = {}

var demo                              ## town_demo.gd
var ground: WorldGround
var state := State.IDLE
var chaser: SpeederNode               ## the chase speeder
var riders: Array = []                ## its two guards (NpcBody)
var holder_now := ""                  ## "remnant" | "locals"
var home := Transform3D()             ## the marker: where it parks
var stolen: SpeederNode               ## the gate speeder you took, while it is not yet yours
var stolen_from := Vector3.ZERO       ## where it was parked when you took it
var loose := 0                        ## got away with it, but the row was full
var chases := 0                       ## chases started (tests, traces)
var escapes := 0
var kept := 0
var sold := 0
var chase: SpeederChase              ## issue #883: the chase loop, shared with the heist's getaway
var _respawn_left := -1.0
var _joined := false                  ## the riders are in the holder's garrison


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(CFG_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg = d if d is Dictionary else {}
	return _cfg


static func n(key: String, fallback: float) -> float:
	return float(cfg().get(key, fallback))


static func line(key: String) -> String:
	return str(cfg().get("lines", {}).get(key, key))


## Who holds the town now: "remnant" or "locals".
static func holder() -> String:
	return "remnant" if Story.town_garrison() else "locals"


## The holder's paint for the gate and chase speeders (the marker's own if none).
static func paint_for(who: String, fallback: String = "") -> String:
	return str(cfg().get("holders", {}).get(who, {}).get("paint", fallback))


func setup(town_demo, world_ground: WorldGround) -> void:
	demo = town_demo
	ground = world_ground
	name = "GateChase"


func _ready() -> void:
	var town = demo.get("town")
	var ms: Array = town.markers_with_role("vehicle_chase") if town != null else []
	if ms.is_empty():
		return
	var m: Dictionary = ms[0]
	var at: Vector3 = town.marker_pos(str(m.id))
	at.y = ground.terrain.height_at(at.x, at.z) if ground != null and ground.terrain != null else at.y
	home = Transform3D(Basis(Vector3.UP, deg_to_rad(float(m.get("yaw_deg", 0.0)))), at)
	holder_now = holder()
	_spawn_chaser()
	_spawn_riders()
	for s in demo.gate_speeders:
		if is_instance_valid(s):
			s.mounted.connect(_on_gate_mounted.bind(s))


func _yaw() -> float:
	return home.basis.get_euler().y


func _spawn_chaser() -> void:
	chaser = SpeederNode.new()
	chaser.setup(demo, ground, {}, true, paint_for(holder_now, "remnant"))
	add_child(chaser)
	chaser.name = "ChaseSpeeder"
	chaser.place(home.origin, _yaw())
	chaser.set_meta("gate_chaser", holder_now)
	chaser.destroyed.connect(_on_chaser_destroyed)


## Two guards beside it, in the holder's garrison once it is up.
func _spawn_riders() -> void:
	riders.clear()
	_joined = false
	var ids: Array = cfg().get("holders", {}).get(holder_now, {}).get("riders", ["gate_guard", "gate_guard"])
	var side := home.basis.x
	for i in ids.size():
		var at := home.origin + side * (3.0 if i == 0 else -3.0)
		var soldier: Dictionary = demo._content().get_soldier(str(ids[i]))
		if soldier.is_empty():
			continue
		var b: NpcBody = demo.make_npc(soldier, at, _yaw(), "gate_chase/%d" % i, "npc:gate_chase/%d" % i, self)
		riders.append(b)


## The holder's garrison (Remnant: the town's; locals: the locals' gate garrison).
func garrison() -> Garrison:
	var g = demo.get("garrison") if holder_now == "remnant" else demo.get("locals_garrison")
	return g if g != null and is_instance_valid(g) else null


func alarm_up() -> bool:
	var g := garrison()
	return g != null and g.alarm != null and g.alarm.active()


func _join_garrison() -> void:
	if _joined:
		return
	var g := garrison()
	if g == null:
		return
	for b in riders:
		if is_instance_valid(b) and not b.dead:
			g.add_member(b)
	_joined = true


# ------------------------------------------------------------------ stealing

func _on_gate_mounted(s: SpeederNode) -> void:
	if not s.has_meta("gate_speeder") or s.has_meta("adopted"):
		return
	stolen = s
	if s.has_meta("loose"):
		_keep_stolen()                # already got away with it: yours if there is room now
		return
	stolen_from = s.model.position
	var g := garrison()
	if g != null:
		g._raise("speeder_stolen", s.model.position)
	_toast(line("stolen"))


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	tick(dt)


func tick(dt: float) -> void:
	if chaser == null and _respawn_left < 0.0:
		return
	_join_garrison()
	if _respawn_left >= 0.0:
		_respawn_left -= dt
		if _respawn_left <= 0.0 and holder() == holder_now:
			_respawn_left = -1.0
			_spawn_chaser()
			if _alive_riders().is_empty():
				_spawn_riders()
		return
	_tick_sell()
	var p = demo._player
	var riding_speeder: bool = p != null and p.piloting and p.vehicle is SpeederNode
	match state:
		State.IDLE:
			if alarm_up() and riding_speeder and not _alive_riders().is_empty() and is_instance_valid(chaser):
				_start_chase()
			elif stolen != null and is_instance_valid(stolen) and _alive_riders().is_empty():
				_keep_stolen()            # nobody left to chase you: it is yours
			elif _rode_off(p, riding_speeder):
				_keep_stolen()            # no chase could start and you rode off with it
		State.CHASE, State.PULL_UP:
			_tick_chase(dt, p)
		State.RETURN:
			if chaser == null or not is_instance_valid(chaser) or chaser.brain == null or chaser.brain.done:
				if chaser != null and is_instance_valid(chaser):
					chaser.step_off()
					chaser.brain = null
				_stand_riders()
				state = State.IDLE


## You are on the stolen speeder, more than escape_m from where it was parked,
## and nobody is coming after you (the IDLE chase check above did not fire).
func _rode_off(p, riding_speeder: bool) -> bool:
	if stolen == null or not is_instance_valid(stolen) or not riding_speeder or p.vehicle != stolen:
		return false
	return stolen.model.position.distance_to(stolen_from) > n("escape_m", 800.0)


func _alive_riders() -> Array:
	return riders.filter(func(b): return is_instance_valid(b) and not b.dead)


## Their alarm is up and you are on a speeder: both climb on and come after you.
func _start_chase() -> void:
	var alive := _alive_riders()
	var seats := ["driver", "rider"]
	for i in mini(alive.size(), 2):
		var b: NpcBody = alive[i]
		if not chaser.seat_npc(b, seats[i]):
			chaser.board(b, seats[i])
	if not chaser.npc_driven():
		return
	chaser.brain = SpeederBrain.new(chaser.model, str(cfg().get("skill", "chaser")), 613)
	chase = SpeederChase.new(chaser, n("pull_up_m", 18.0), n("escape_m", 800.0), n("give_up_s", 6.0))
	chase.start()
	state = State.CHASE
	chases += 1
	_toast(line("chase"))


## The chase loop (SpeederChase): get off and they pull up and get off; get away
## and they give up.
func _tick_chase(dt: float, p) -> void:
	if chase == null:
		state = State.IDLE
		return
	match chase.tick(dt, p):
		"pull_up":
			state = State.PULL_UP
		"back_on":
			state = State.CHASE
		"stepped_off", "ended":
			state = State.IDLE
		"lost":
			_give_up()


## They lost you: home, park, back by the speeder. A stolen gate speeder is yours.
func _give_up() -> void:
	escapes += 1
	state = State.RETURN
	chaser.brain.park(home.origin, _yaw())
	_toast(line("gave_up"))
	if stolen != null and is_instance_valid(stolen):
		_keep_stolen()


func _keep_stolen() -> void:
	var post = demo.get("speeder_post")
	var s := stolen
	stolen = null
	if post == null or s == null or not is_instance_valid(s):
		return
	var fit := SpeederUpgrades.new_fit(s.paint)
	fit["stolen"] = true
	if post.adopt(s, fit):
		s.set_meta("adopted", true)
		s.remove_meta("loose")
		demo.gate_speeders.erase(s)
		kept += 1
		_toast(line("lost_them"))
	elif not s.has_meta("loose"):
		# Your row is full: you got away with it, but it is not yours (not saved).
		s.set_meta("loose", true)
		loose += 1
		_toast(line("row_full"))


func _stand_riders() -> void:
	for b in _alive_riders():
		b.post_pos = b.global_position


func _on_chaser_destroyed(_at: Vector3) -> void:
	chaser = null
	state = State.IDLE
	_respawn_left = n("respawn_s", 120.0)


# ------------------------------------------------------------------ selling it

## Riding a stolen speeder of yours within sell_m of Skrugs's stall: [Z] sells it.
func _tick_sell() -> void:
	var p = demo._player
	var post = demo.get("speeder_post")
	if p == null or post == null or not (p.piloting and p.vehicle is SpeederNode):
		return
	var s: SpeederNode = p.vehicle
	if not post.is_stolen(s) or s.model.position.distance_to(post.world_point("customer")) > n("sell_m", 25.0):
		return
	var g = demo.get("gear")
	if g != null and g.hud != null:
		g.hud.set_prompt(line("sell") % int(n("sell_price", 350)))
	if InputMap.has_action("bay_land") and Input.is_action_just_pressed("bay_land"):
		sell(s)


## Sell stolen speeder `s` to Skrugs. Returns the credits paid.
func sell(s: SpeederNode) -> int:
	var post = demo.get("speeder_post")
	var paid: int = post.sell_stolen(s, int(n("sell_price", 350))) if post != null else 0
	if paid > 0:
		sold += 1
		Sound.play("coin_gain")
		_toast(line("sold") % paid)
	return paid


func _toast(text: String) -> void:
	var g = demo.get("gear") if demo != null else null
	if g != null and g.hud != null:
		g.hud.toast(text, 3.5)
