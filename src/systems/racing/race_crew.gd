class_name RaceCrew
extends Node3D
## Issue #611: a speeder race crew (content/core/racing/crews/<id>.json) and the
## race they run on their course (RaceCourse, #610). One node runs any crew;
## nothing about a crew is in code.
##
## The crew hang out on foot by a desert place (their `hangout` landmark), their
## speeders parked beside them (`park`). The speeders are built once you come
## within build_near_m (rules.json), one a physics tick, and stay: parked and
## settled they sleep (no hover step) while you are far off, so a crew waiting
## costs nothing a frame. Their own Townsfolk runs them, so hurting one is
## hurting a local out here. A racer killed or a speeder wrecked stays gone until
## the world next loads, when the crew is built again whole.
##
##   [E] on the leader  -- a challenge, then the race menu: the course, its laps,
##                         the crew's rules, your best lap, and a buy-in from the
##                         crew's least up. The winner takes `multiple` times it.
##   accept             -- the buy-in is paid; one after another (leave_stagger_s)
##                         the racers walk to their parked speeders, climb on
##                         (SpeederNode seats, #609) and cruise to the grid at
##                         cruise_pace; a crowd of locals gathers at the line, one
##                         body a tick.
##   [Z] near the grid  -- your speeder drives itself onto your slot and holds.
##   3, 2, 1, GO        -- held until GO.
##   the race           -- laps through the gates in order (RaceLaps); the HUD
##                         shows your lap and place and the pointer the next gate.
##                         From the crew's shoot_from_lap a racer with you in its
##                         nose fires its lasers. Shoot them any time.
##   out                -- your speeder bursts, you get off, or you leave the course.
##   the end            -- win and the pot is paid into your credits at once
##                         (WorldState.on_race_won); the racers cruise
##                         back to their spots, park, climb off and walk back to
##                         where they stand. Their speeders stay parked.
##   rematch            -- while they head home, [Z] on your speeder near the line
##                         races them again for the same stake, if you can cover
##                         it (credits, then what Dorrin holds for you). Short, and
##                         they just go home; the leader's menu then offers the
##                         same stake first. Never for pink slips.
##   race quests        -- optional quests (Quests, quests() below) offered when a
##                         race ends: win and you are offered the next crew up the
##                         ladder (pointing at where they hang out) and a pink-slip
##                         rematch with this crew; lose and a rematch with them.
##
## The headless test drives accept(), line_up() and the frame directly.

enum Phase { IDLE, GRID, COUNTDOWN, RACING, RETURN }

const DIR := "res://content/core/racing/crews/"
const RULES_PATH := "res://content/core/racing/rules.json"
const YOU := "you"
const NpcRingsT := preload("res://src/systems/npc/npc_rings.gd")

static var _rules: Dictionary = {}

var demo                              ## town_demo.gd
var ground: WorldGround
var crew: Dictionary = {}
var id := ""
var course: RaceCourse
var xf := Transform3D()               ## the hangout landmark's frame (x toward the town)
var stall: SpeederStall               ## the crew file's "shop": a speeder mechanic's stall by the hangout, or null
var found := false
## { key, cfg, body: NpcBody, speeder: SpeederNode (parked at `park`), built (its
## speeder has been built this load: a wrecked one is not built again), fit (what
## it was built with), brain: SpeederBrain, slot, set_off (grid seconds when it
## heads for its speeder), seated, left_t (grid seconds it drove off), home
## (parked and off it), finished, out }
var racers: Array = []
var crowd: Array = []
var folk                              ## the crew's own Townsfolk
var phase := Phase.IDLE
var stake := 0
var laps: RaceLaps
var results: Array = []               ## keys in the order they finished
var winner := ""                      ## key of the winner, once the race is over
var player_out := ""                  ## why you are out ("" = still in)
var lined_up := false
var said := ""                        ## the last line spoken (tests)
var in_reach := false
var menu: DroidMenu
var races_run := 0
var track_beast: PlanetBeast          ## issue #612: the second beast, on the course while a race runs
var pink := false                     ## issue #617: this race is for pink slips (your speeder against the leader's)
## Issue #618: race feel.
var race_t := 0.0                     ## seconds since GO
var clean_gates := 0                  ## checkpoints you took dead centre (each a boost)
var finish_cam_on := false
var _lap_t0 := -1.0                   ## race_t when your current lap began
var _fc_end_ms := 0
var _fc_layer: CanvasLayer
var _fc_hidden: Array = []            ## the HUD layers the finish cam hid

var _hud: CanvasLayer
var _hud_lap: Label
var _hud_big: Label
var _hud_list: Label
var _big_left := 0.0
var _count := 0
var _count_left := 0.0
var _grid_t := 0.0
var _return_t := 0.0
var _last: Dictionary = {}            ## key -> where they were last frame
var _player_speeder: SpeederNode
var _lineup: SpeederBrain
var _rng := RandomNumberGenerator.new()
var _jeer_left := 0.0
var _crowd_left := 0                  ## crowd bodies still to build at the line (one every crowd_every_ticks)
var _spawn_wait := 0
var _beast_due := false               ## the track beast comes once the crowd is up
var _slips := ""                      ## issue #617: "won" / "lost" this race, settled once they are home
var last_stake := 0                   ## the buy-in of your last money race with this crew (0 = none yet)
var rematch_on := false               ## the race is over and [Z] races them again for last_stake


# ------------------------------------------------------------------ data

static func ids() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		var n := f.trim_suffix(".remap")
		if n.ends_with(".json"):
			out.append(n.trim_suffix(".json"))
	out.sort()
	return out


static func load_crew(crew_id: String) -> Dictionary:
	var f := FileAccess.open(DIR + crew_id + ".json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}


static func rules() -> Dictionary:
	if _rules.is_empty():
		var f := FileAccess.open(RULES_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_rules = d if d is Dictionary else {}
	return _rules


static func rule(key: String, fallback: float) -> float:
	return float(rules().get(key, fallback))


static func rule_text(key: String) -> String:
	return str(rules().get(key, key))


func r(key: String, fallback: float) -> float:
	return float(crew.get("rules", {}).get(key, fallback))


## A crew line with its {words} filled in; a list picks one. A line the crew's
## file does not have comes from rules.json `lines` (the same for every crew).
func line(key: String, extra: Dictionary = {}) -> String:
	var v = crew.get("lines", {}).get(key, rules().get("lines", {}).get(key, key))
	if v is Array:
		v = (v as Array)[_rng.randi() % maxi(1, (v as Array).size())] if not (v as Array).is_empty() else key
	var words := { "name": leader_name(), "crew": str(crew.get("label", id)), "stake": stake,
		"pot": stake * int(r("multiple", 10)) }
	words.merge(extra, true)
	return str(v).format(words)


# ------------------------------------------------------------------ setup

func setup(town_demo, world_ground: WorldGround, crew_data: Dictionary, race_course: RaceCourse) -> void:
	demo = town_demo
	ground = world_ground
	crew = crew_data
	course = race_course
	id = str(crew.get("id", "crew"))
	name = "RaceCrew_" + id
	_rng.randomize()


func _ready() -> void:
	_find_hangout()
	if not found or course == null:
		return
	var face := _ground(_v2(crew.get("hangout", {}).get("face", [0, 0])))
	var bodies: Array = []
	var i := 0
	for rc in crew.get("racers", []):
		var at := _ground(_v2(rc.get("stand", [0, 0])))
		var key := "racer_%d" % i
		var post := "race/%s/%d" % [id, i]
		var b := _body(str(crew.get("profile", "local_racer")), at, atan2(face.x - at.x, face.z - at.z), post,
			{ "outfit": rc.get("look", {}) })
		if b == null:
			continue
		b.set_meta("race_crew", id)
		_pad(at)
		racers.append({ "key": key, "cfg": rc, "body": b, "speeder": null, "built": false, "fit": {}, "brain": null,
			"slot": 0, "set_off": 0.0, "seated": false, "left_t": 0.0, "home": true, "finished": false, "out": false })
		bodies.append(b)
		i += 1
	if not bodies.is_empty() and demo.has_method("make_townsfolk"):
		folk = demo.make_townsfolk("RaceFolk_" + id, bodies)
	menu = DroidMenu.new()
	add_child(menu)
	_build_hud()
	_build_stall()


## The crew file's "shop" block: a speeder mechanic's stall (SpeederStall: one of
## Dorrin's cousins, his shop) at `at` in the hangout's frame, turned `yaw_deg`.
func _build_stall() -> void:
	var sh: Dictionary = crew.get("shop", {})
	if sh.is_empty() or str(sh.get("id", "")) == "":
		return
	var o := _ground(_v2(sh.get("at", [0, 0])))
	var up := ground.up_at(o) if ground != null else Vector3.UP
	var basis := Basis(Quaternion(xf.basis.y.normalized(), up)) * xf.basis * Basis(Vector3.UP, deg_to_rad(float(sh.get("yaw_deg", 0.0))))
	stall = SpeederStall.new()
	stall.setup(demo, ground, Transform3D(basis.orthonormalized(), o), str(sh.id), course.to_world_near)
	add_child(stall)


## A body from a soldier profile, in no town list (the town's locals walk the
## town; these stay with the race): the crew's own Townsfolk runs the racers, and
## the crowd just stands and watches.
func _body(profile_id: String, at: Vector3, yaw: float, post: String, extra: Dictionary = {}) -> NpcBody:
	var soldier: Dictionary = demo._content().get_soldier(profile_id)
	if soldier.is_empty():
		push_error("RaceCrew: unknown soldier profile " + profile_id)
		return null
	if not extra.is_empty():
		soldier = soldier.duplicate(true)
		soldier.merge(extra, true)
	return demo.make_npc(soldier, at, yaw, post, "npc:" + post, self)


## Something to stand on out here: the sand's collider only follows the player,
## so a body standing far from them (the crew at their spots, the crowd at the
## line while you ride) would fall through. A small flat pad at the sand under `at`.
func _pad(at: Vector3) -> StaticBody3D:
	var up := ground.up_at(at) if ground != null else Vector3.UP
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 0.4, 1.6)
	col.shape = box
	body.add_child(col)
	add_child(body)
	body.global_transform = Transform3D(PlanetSphere.tilt_to(up), at - up * 0.2)
	return body


func _find_hangout() -> void:
	var near := str(crew.get("hangout", {}).get("near", ""))
	var world: Dictionary = demo.world if demo != null and "world" in demo else {}
	for lm in world.get("landmarks", []):
		if str(lm.get("location", "")) != near and str(lm.get("id", "")) != near:
			continue
		var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
		var origin := Vector3(at.x, 0.0, at.z)
		var sp := ground.sphere()
		if sp != null:
			origin = sp.surface_at(at.x, at.z)
		elif ground.terrain != null:
			origin.y = ground.terrain.height_at(at.x, at.z)
		xf = Transform3D(PlanetSphere.tilt_to(ground.up_at(origin)) * Basis(Vector3.UP, deg_to_rad(float(lm.get("yaw_deg", 0.0)))), origin)
		found = true
		return


## A point in the hangout's frame, on the sand.
func _ground(local: Vector2) -> Vector3:
	return course.to_world_near(xf * Vector3(local.x, 0.0, local.y)) if course != null else xf * Vector3(local.x, 0.0, local.y)


static func _v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and (a as Array).size() >= 2 else Vector2.ZERO


# ------------------------------------------------------------------ the parked speeders

## Where a racer's speeder parks, and which way it faces there (toward the line).
func _park_pos(rc: Dictionary) -> Vector3:
	return _ground(_v2(rc.cfg.get("park", rc.cfg.get("stand", [0, 0]))))


func _park_yaw(rc: Dictionary) -> float:
	var at := _park_pos(rc)
	var up := ground.up_at(at)
	var to := _flat((course.gates[0].pos as Vector3) - at, up) if not course.gates.is_empty() else Vector3.ZERO
	return RaceCourse.yaw_of(to.normalized(), up) if to.length() > 0.5 else 0.0


## A racer's own ride from its crew file: model (speeder classes: speeder,
## racer or hauler; none = the Sand-boxer), paint and parts.
static func _own_fit(cfg: Dictionary) -> Dictionary:
	return { "paint": str(cfg.get("paint", "")), "parts": (cfg.get("parts", []) as Array).duplicate(),
		"model": SpeederUpgrades.model_of(cfg) }


## What a racer's speeder is built with: its model, paint and parts and the
## crew's race gear; the leader's is whatever they ride now (issue #617: maybe
## your old one).
func _fit_of(rc: Dictionary) -> Dictionary:
	var fit := _own_fit(rc.cfg)
	if bool(rc.cfg.get("leader", false)):
		fit = _own_fit(leader_ride())
	fit.parts = (fit.parts as Array) + gear_parts()
	return fit


## Build a racer's speeder, parked at its spot and locked to you.
func _build_speeder(rc: Dictionary) -> void:
	var fit := _fit_of(rc)
	var sp := SpeederNode.new()
	sp.setup(demo, ground, SpeederUpgrades.apply(HoverModel.load_config(SpeederUpgrades.model_of(fit)), fit), true, str(fit.get("paint", "")))
	sp.locked = true
	add_child(sp)
	sp.place(_park_pos(rc), _park_yaw(rc))
	rc.speeder = sp
	rc.fit = fit
	rc.built = true


## Near enough (build_near_m) and some still to build: one speeder this tick, so
## coming up on the hangout never builds them all in one frame.
func _tick_build() -> void:
	var p := _player()
	if p != null and p.global_position.distance_to(xf.origin) > rule("build_near_m", 500.0):
		return
	for rc in racers:
		if not bool(rc.built):
			_build_speeder(rc)
			return


## Every speeder not yet built, now (a race accepted before they were up).
func _ensure_speeders() -> void:
	for rc in racers:
		if not bool(rc.built):
			_build_speeder(rc)


func _speeder_ok(rc: Dictionary) -> bool:
	return rc.speeder != null and is_instance_valid(rc.speeder) and rc.speeder.model.alive()


func _body_ok(rc: Dictionary) -> bool:
	return rc.body != null and is_instance_valid(rc.body) and not rc.body.dead


func leader() -> NpcBody:
	for rc in racers:
		if bool(rc.cfg.get("leader", false)):
			return rc.body if is_instance_valid(rc.body) else null
	return racers[0].body if not racers.is_empty() and is_instance_valid(racers[0].body) else null


func leader_name() -> String:
	var l := leader()
	return l.display_name if l != null and l.display_name != "" else "the leader"


func _player() -> CharacterBody3D:
	return demo._player if demo != null else null


func _gear():
	return demo.get("gear") if demo != null else null


func _say(body: NpcBody, text: String) -> void:
	said = text
	if body != null and is_instance_valid(body) and not body.dead:
		body.say(text, 3.0)


func _toast(text: String, secs: float = 3.5) -> void:
	var g = _gear()
	if g != null and g.hud != null:
		g.hud.toast(text, secs)


# ------------------------------------------------------------------ the race menu

## Issue #615: the ladder. This crew races you once you have beaten the crew
## before them (`after`; "" = the first rung).
func ladder_open() -> bool:
	var after := str(crew.get("after", ""))
	return after == "" or WorldState.has_flag("crew_beaten_" + after)


## Issue #615: you have heard of `c` (a crew's data): the first rung once you own a
## speeder (Skrugs tells you), the rest once the crew below has told you of them.
static func heard_of(c: Dictionary) -> bool:
	var cid := str(c.get("id", ""))
	if WorldState.has_flag("heard_crew_" + cid) or WorldState.has_flag("crew_beaten_" + cid):
		return true
	var after := str(c.get("after", ""))
	if after == "":
		return WorldState.count("speeders_owned") > 0
	return WorldState.has_flag("crew_beaten_" + after)


## [E] on the leader: a challenge, then the menu (or, up the ladder too soon, a
## line telling you who to beat first).
func talk() -> void:
	var l := leader()
	if l == null or phase != Phase.IDLE:
		return
	if not ladder_open():
		_say(l, line("not_yet"))
		return
	_say(l, line("challenge"))
	menu.open(line("menu_title"), menu_options(), _on_pick, menu_body())


func menu_options() -> Array:
	var out: Array = []
	if last_stake > 0 and can_afford(last_stake):
		out.append({ "id": "rematch", "text": line("rematch_option",
			{ "stake": last_stake, "pot": last_stake * int(r("multiple", 10)) }) })
	var least := int(r("min_buy_in", 100))
	var step := int(r("buy_in_step", 100))
	for k in int(r("buy_in_steps", 6)):
		var s := least + step * k
		if not can_afford(s) and k > 0:
			break
		out.append({ "id": "buy:%d" % s, "text": line("buy_in", { "stake": s, "pot": s * int(r("multiple", 10)) }) })
	if slips_offered():
		out.append({ "id": "slips", "text": line("pink_slips", { "ride": ride_label(leader_ride()) }) })
	out.append({ "id": "walk", "text": line("walk_away") })
	return out


func menu_body() -> String:
	var shoot := int(r("shoot_from_lap", 2))
	var rule_line := line("rule_shoot", { "lap": shoot }) if shoot > 0 else line("rule_clean")
	var best := best_lap()
	return line("menu_body", { "course": course.label(), "laps": course.laps_total(), "rule": rule_line,
		"multiple": int(r("multiple", 10)), "best": ("%.1f s" % best) if best > 0.0 else "none yet" })


## Your best lap on this crew's course (issue #618 fills it in; 0 = none).
func best_lap() -> float:
	return float(WorldState.counters.get("race_best_" + course.id, 0)) / 1000.0


func _on_pick(choice: String) -> void:
	if choice.begins_with("buy:"):
		accept(int(choice.get_slice(":", 1)))
	elif choice == "rematch":
		accept(last_stake)
	elif choice == "slips":
		accept_slips()


# ------------------------------------------------------------------ pink slips (issue #617)

## Pink slips are on (racing rules) and you have beaten this crew for money.
func slips_offered() -> bool:
	return bool(rules().get("pink_slips", true)) and WorldState.has_flag("crew_beaten_" + id)


## What the leader rides now: your old speeder if they won it off you, else their own.
func leader_ride() -> Dictionary:
	var won: Dictionary = WorldState.race_rides.get(id, {})
	if not won.is_empty():
		return won
	for rc in racers:
		if bool(rc.cfg.get("leader", false)):
			return _own_fit(rc.cfg)
	return SpeederUpgrades.new_fit()


## "the remnant Sand-boxer (engine II, thrusters II)"; the racer and the box
## truck by the model half of their label ("the Boxcar (racing engine)").
static func ride_label(fit: Dictionary) -> String:
	var parts: Array = []
	for p in fit.get("parts", []):
		var nm := str(SpeederUpgrades.part(str(p)).get("label", p))
		parts.append(nm.get_slice(" (", 0).to_lower())
	var paint := str(fit.get("paint", ""))
	var label := str(HoverModel.load_config(SpeederUpgrades.model_of(fit)).get("label", "Sand-boxer"))
	var kind := label.get_slice(" ", label.get_slice_count(" ") - 1)
	return "the %s%s%s" % [(paint + " ") if paint != "" else "", kind, (" (" + ", ".join(PackedStringArray(parts)) + ")") if not parts.is_empty() else ""]


## Race the leader for pink slips: "" if it is on; else why not ("ladder",
## "beaten", "speeder", "not_yours", "full", "busy").
func accept_slips() -> String:
	if phase != Phase.IDLE or leader() == null:
		return "busy"
	if not ladder_open():
		_say(leader(), line("not_yet"))
		return "ladder"
	if not slips_offered():
		return "beaten"
	var s := your_speeder()
	if s == null:
		_say(leader(), line("no_speeder"))
		return "speeder"
	if not _owned(s):
		_say(leader(), line("slips_not_yours"))   # a speeder that is not yours yet is no bet
		return "not_yours"
	var post = demo.get("speeder_post")
	if post != null and WorldState.count("speeders_owned") >= post.owned_cap():
		_say(leader(), line("no_room"))
		return "full"
	stake = 0
	pink = true
	_start_grid()
	_say(leader(), line("slips_accept"))
	return ""


## The pink-slip race is over: win and their ride is yours, waiting in the row
## outside the back gate; lose and the speeder you raced is theirs.
func _settle_slips(won: bool) -> void:
	var post = demo.get("speeder_post")
	_slips = "won" if won else "lost"
	if won:
		var fit := leader_ride()
		WorldState.race_rides.erase(id)
		if post != null and post.add_owned(fit) != null:
			_toast(line("slips_won", { "ride": ride_label(fit) }), 6.0)
		return
	var mine := _player_speeder
	if mine == null or not is_instance_valid(mine) or post == null or not post.speeders.has(mine):
		return
	WorldState.race_rides[id] = post.fit_for(int(mine.get_meta("slot", 0))).duplicate(true)
	if mine.riding:
		mine.dismount()
	post.remove(mine)
	_player_speeder = null
	_toast(line("slips_lost", { "ride": ride_label(WorldState.race_rides[id]) }), 6.0)


## Back home after a pink-slip race: won, and the leader's speeder is yours (it
## is gone from their spot until the world next loads); lost, and they park the
## one they won off you in its place.
func _settle_leader_ride() -> void:
	var res := _slips
	_slips = ""
	if res == "":
		return
	for rc in racers:
		if not bool(rc.cfg.get("leader", false)):
			continue
		if rc.speeder != null and is_instance_valid(rc.speeder):
			rc.speeder.step_off()
			rc.speeder.queue_free()
			rc.speeder = null
		if res == "lost" and _body_ok(rc):
			_build_speeder(rc)
		return


## Take the race at `amount`. "" if it is on; else why not ("poor", "speeder",
## "busy").
func accept(amount: int) -> String:
	if phase != Phase.IDLE or leader() == null:
		return "busy"
	if not ladder_open():
		_say(leader(), line("not_yet"))
		return "ladder"
	stake = amount
	if amount < int(r("min_buy_in", 100)) or not can_afford(amount):
		stake = int(r("min_buy_in", 100))
		_say(leader(), line("too_poor"))
		return "poor"
	if your_speeder() == null:
		_say(leader(), line("no_speeder"))
		return "speeder"
	_pay(amount)
	_start_grid()
	_say(leader(), line("accept"))
	return ""


## What you can put down: your credits and the winnings Dorrin holds for you
## (the crew know he is good for it).
static func spendable() -> int:
	return WorldState.credits + maxi(0, WorldState.count("race_winnings"))


static func can_afford(amount: int) -> bool:
	return spendable() >= amount


## Pay a buy-in: your credits first, the rest out of what Dorrin holds.
static func _pay(amount: int) -> void:
	var from_pot := clampi(amount - WorldState.credits, 0, maxi(0, WorldState.count("race_winnings")))
	WorldState.credits -= amount - from_pot
	if from_pot > 0:
		WorldState.bump("race_winnings", -from_pot)
	Sound.play("coin_spend")


# ------------------------------------------------------------------ race quests

static var _quests: Array = []            ## built once from the crew files (Quests.all() asks often)


static func quest_id(kind: String, crew_id: String) -> String:
	return "race_%s_%s" % [kind, crew_id]


## The crew one rung above `crew_id` on the ladder (the one whose `after` is it),
## or {} at the top.
static func next_crew(crew_id: String) -> Dictionary:
	for cid in ids():
		var c := load_crew(cid)
		if str(c.get("after", "")) == crew_id and crew_id != "":
			return c
	return {}


## "the salt crew" -> "Salt crew".
static func crew_name(c: Dictionary) -> String:
	var label := str(c.get("label", c.get("id", "")))
	if label.to_lower().begins_with("the "):
		label = label.substr(4)
	return label.substr(0, 1).to_upper() + label.substr(1)


static func _quest_words(c: Dictionary) -> Dictionary:
	return { "crew": str(c.get("label", c.get("id", ""))), "Crew": crew_name(c),
		"course": str(RaceCourse.load_course(str(c.get("course", ""))).get("label", "course")) }


## Every race quest, for Quests.all(): per crew a "next" (race them: offered when
## you beat the crew below), a "slips" (race them for pink slips: offered when you
## beat them) and a "rematch" (race them again: offered when they beat you). Each
## points at where that crew hangs out ("crew:<id>").
static func quests() -> Array:
	if not _quests.is_empty():
		return _quests
	var q: Dictionary = rules().get("quests", {})
	if q.is_empty():
		return _quests
	var crews: Dictionary = {}
	for cid in ids():
		crews[cid] = load_crew(cid)
	for cid in crews:
		var c: Dictionary = crews[cid]
		var words := _quest_words(c)
		var below: Dictionary = crews.get(str(c.get("after", "")), {})
		words["beaten"] = str(below.get("label", "the crew below them"))
		for kind in ["next", "slips", "rematch"]:
			var k: Dictionary = q.get(kind, {})
			if k.is_empty() or (kind == "next" and below.is_empty()):
				continue
			_quests.append({ "id": quest_id(kind, str(cid)), "title": str(k.get("title", kind)).format(words),
				"text": str(k.get("text", "")).format(words), "target": "crew:" + str(cid) })
	return _quests


## A race with `crew_id` is over: settle and offer its quests. Won: the rematch
## and (after a pink-slip race) the slips quest are done, and you are offered the
## next crew up (unless you have beaten them) and a pink-slip rematch here. Lost:
## you are offered a rematch only. Any pink-slip race, won or lost, does the
## slips quest.
static func settle_quests(crew_id: String, won: bool, was_pink: bool) -> void:
	if was_pink:
		_finish(quest_id("slips", crew_id))
	if not won:
		Quests.offer_again(quest_id("rematch", crew_id))
		return
	_finish(quest_id("rematch", crew_id))
	_finish(quest_id("next", crew_id))
	var up := next_crew(crew_id)
	if not up.is_empty() and not WorldState.has_flag("crew_beaten_" + str(up.get("id", ""))):
		Quests.offer_again(quest_id("next", str(up.get("id", ""))))
	if bool(rules().get("pink_slips", true)):
		Quests.offer_again(quest_id("slips", crew_id))


## Done, if it was offered (Quests.complete would also mark one never offered as
## done, which would fill the job log with races nobody asked you to run).
static func _finish(qid: String) -> void:
	if Quests.state(qid) == "open":
		Quests.complete(qid)


# ------------------------------------------------------------------ the rematch

## The race is over and the crew are heading home: race them again at once for
## the same stake. "" if it is on; else why not ("busy", "poor", "speeder").
func rematch() -> String:
	if phase != Phase.RETURN or not rematch_on or leader() == null:
		return "busy"
	if not can_afford(last_stake):
		rematch_on = false
		return "poor"
	if your_speeder() == null:
		return "speeder"
	rematch_on = false
	for rc in racers:
		# Anyone not driving (thrown clear, or their racer down) is sorted out as
		# _put_away would; the rest turn round from wherever they are.
		if not bool(rc.home) and not (_speeder_ok(rc) and rc.speeder.npc_driven()):
			_settle_home(rc)
	_remove_beast()                         # it was crawling off: a fresh one comes in
	if _hud_list != null:
		_hud_list.visible = false
	stake = last_stake
	_pay(stake)
	var standing := crowd.size()
	_start_grid()
	_crowd_left = maxi(0, _crowd_left - standing)   # the crowd still at the line stay
	_say(leader(), line("rematch_accept"))
	line_up()                               # already by the grid: straight onto your slot
	return ""


## While they head home: the [Z] prompt on your speeder near the line.
func _tick_rematch() -> void:
	if not rematch_on:
		return
	var p := _player()
	if p == null or not (p.piloting and p.vehicle is SpeederNode) or course.gates.is_empty():
		return
	if (p.vehicle as SpeederNode).model.position.distance_to(course.gates[0].pos) > r("off_course_m", 400.0):
		return
	var g = _gear()
	if g != null and g.hud != null:
		g.hud.set_prompt(line("rematch", { "stake": last_stake, "pot": last_stake * int(r("multiple", 10)) }))
	if InputMap.has_action("bay_land") and Input.is_action_just_pressed("bay_land"):
		rematch()


## A speeder you can race nearby: the one you ride, one you own within 120 m, or
## the one you last got off within 120 m. The crew don't ask whose it is, so a
## stolen gate speeder counts before GateChase has made it yours.
func your_speeder() -> SpeederNode:
	var p := _player()
	if p == null:
		return null
	if p.piloting and p.vehicle is SpeederNode and is_instance_valid(p.vehicle):
		return p.vehicle
	var post = demo.get("speeder_post")
	if post != null and is_instance_valid(post):
		for s in post.speeders:
			if _near_and_free(s, p):
				return s
	var last = p.get("last_vehicle")
	if last is SpeederNode and _near_and_free(last, p):
		return last
	return null


## `s` is whole, nobody else is on it, and it is within 120 m of you.
static func _near_and_free(s, p: Node3D) -> bool:
	return is_instance_valid(s) and s.rideable and s.model.alive() and not s.npc_driven() \
		and s.model.position.distance_to(p.global_position) < 120.0


## A speeder you own (in the row's list) is what you can put up for pink slips.
func _owned(s: SpeederNode) -> bool:
	var post = demo.get("speeder_post") if demo != null else null
	return s != null and post != null and is_instance_valid(post) and post.speeders.has(s)


# ------------------------------------------------------------------ the grid

func _start_grid() -> void:
	phase = Phase.GRID
	races_run += 1
	results.clear()
	winner = ""
	player_out = ""
	lined_up = false
	_grid_t = 0.0
	_slips = ""
	laps = course.new_laps()
	laps.add_racer(YOU)
	course.build_gates()
	_ensure_speeders()
	var slot := 1
	var order := 0
	for rc in racers:
		rc.finished = false
		rc.out = false
		rc.seated = false
		rc.home = true
		if not _body_ok(rc) or not _speeder_ok(rc):
			rc.out = true                        # dead, or their speeder wrecked: back next load
			continue
		var sp: SpeederNode = rc.speeder
		var to_grid: Dictionary = course.grid_slot(slot)
		var brain := SpeederBrain.new(sp.model, str(rc.cfg.get("skill", "racer")), _rng.randi())
		brain.pace = rule("cruise_pace", 0.4)    # no racing to the line
		brain.may_boost = false
		brain.park(to_grid.pos, float(to_grid.yaw))
		sp.brain = brain
		rc.brain = brain
		rc.slot = slot
		rc.set_off = order * rule("leave_stagger_s", 4.0)
		rc.home = false
		laps.add_racer(rc.key)
		slot += 1
		order += 1
	_start_crowd()
	Objective.race = { "text": line("go_line"), "target": "race:%s:0" % course.id, "key": "race" }


## The racers head off one after another: at its set_off a racer walks to its
## speeder and climbs on (sat on it if still walking board_grace_s later), and
## its brain cruises it to its grid slot.
func _tick_set_off() -> void:
	for rc in racers:
		if bool(rc.out) or bool(rc.seated) or _grid_t < float(rc.set_off):
			continue
		var sp = rc.speeder
		if not _speeder_ok(rc) or not _body_ok(rc):
			rc.out = true
			continue
		if sp.npc_driven():
			rc.seated = true
			rc.left_t = _grid_t
		elif _grid_t > float(rc.set_off) + rule("board_grace_s", 6.0):
			sp.seat_npc(rc.body, "driver")
		elif sp.seat_free("driver"):
			sp.board(rc.body, "driver")


func _flat(v: Vector3, up: Vector3) -> Vector3:
	return v - up * v.dot(up)


## The crowd and the track beast, spread over ticks (one every crowd_every_ticks):
## each body is a full kit build, and ten of them in the accept frame was most of
## its hitch.
func _start_crowd() -> void:
	var span: Array = crew.get("rules", {}).get("crowd", [5, 10])
	_crowd_left = _rng.randi_range(int(span[0]), int(span[1]))
	_beast_due = true
	_spawn_wait = 0


func _tick_spawns() -> void:
	_spawn_wait -= 1
	if _spawn_wait > 0:
		return
	_spawn_wait = int(rule("crowd_every_ticks", 5.0))
	if _crowd_left > 0:
		_crowd_left -= 1
		_spawn_crowd_one(crowd.size())
	elif _beast_due:
		_beast_due = false
		_spawn_beast()


func _spawn_crowd_one(i: int) -> void:
	var pool: Array = rules().get("crowd_profiles", ["local_resident"])
	var band: Dictionary = rules().get("crowd_band", {})
	var out_r: Array = band.get("out", [4.0, 14.0])
	var back_r: Array = band.get("back", [-6.0, 10.0])
	var g: Dictionary = course.gates[0]
	var side := -1.0 if i % 2 == 0 else 1.0
	var at: Vector3 = (g.pos as Vector3) + (g.right as Vector3) * side * (float(g.half) + _rng.randf_range(float(out_r[0]), float(out_r[1]))) \
		- (g.fwd as Vector3) * _rng.randf_range(float(back_r[0]), float(back_r[1]))
	at = course.to_world_near(at)
	var post := "race/%s/crowd_%d" % [id, i]
	var b := _body(str(pool[_rng.randi() % pool.size()]), at,
		atan2((g.pos as Vector3).x - at.x, (g.pos as Vector3).z - at.z), post)
	if b != null:
		b.face_point(g.pos)
		b.set_meta("pad", _pad(at))
		crowd.append(b)


# ------------------------------------------------------------------ the track beast (issue #612)

## The flag the course's track beast dies under (beast_slain_<this>).
func beast_key() -> String:
	var b: Dictionary = course.course.get("beast", {})
	var planet_id := str(demo.planet.get("id", "")) if demo != null and "planet" in demo else ""
	return str(b.get("key", planet_id + "_track"))


## A race starts: the course's beast, if it has one and it is not dead, crawls in
## on the course (leashed round it).
func _spawn_beast() -> void:
	var block: Dictionary = (course.course.get("beast", {}) as Dictionary).duplicate()
	if block.is_empty() or PlanetBeast.is_slain(beast_key()) or demo == null:
		return
	if "with_beast" in demo and not demo.with_beast:
		return
	if not block.has("home"):
		var c := Vector2.ZERO
		var line_pts: Array = course.course.get("line", [])
		for p in line_pts:
			c += Vector2(float(p[0]), float(p[1]))
		c /= maxf(1.0, float(line_pts.size()))
		block["home"] = [c.x, c.y]
	var b := PlanetBeast.new()
	b.setup_extra(demo, ground, demo.planet if "planet" in demo else {}, block, beast_key())
	add_child(b)
	track_beast = b


func _remove_beast() -> void:
	if track_beast != null and is_instance_valid(track_beast):
		track_beast.queue_free()
	track_beast = null


## The beast's body parts this tick ([[centre, radius]]; none if it is gone).
func _beast_points() -> Array:
	if track_beast == null or not is_instance_valid(track_beast) or track_beast.dead:
		return []
	return track_beast.body_points()


## A racer at `at` touching it (the player's own rule, PlanetBeast.touches_speeder).
func _beast_touches(at: Vector3, parts: Array) -> bool:
	var margin := float(track_beast.cfg.get("speeder_margin", 1.4)) if not parts.is_empty() else 0.0
	for p in parts:
		if at.distance_to(p[0]) <= float(p[1]) + margin:
			return true
	return false


## The beast's body near `at`, for a racer to steer round (`parts`: this tick's
## _beast_points, or null to read them).
func _beast_avoid(at: Vector3, parts = null) -> Array:
	var out: Array = []
	if parts == null:
		parts = _beast_points()
	for i in range(0, (parts as Array).size(), 2):
		var p: Array = parts[i]
		if (p[0] as Vector3).distance_to(at) < 80.0:
			out.append({ "pos": p[0], "radius": float(p[1]) + 1.0 })
	return out


## A racer drove into it: dead, as you would be, and out of the race.
func _eaten(rc: Dictionary) -> void:
	rc.out = true
	var sp = rc.speeder
	var b = rc.body
	if sp != null and is_instance_valid(sp):
		sp.step_off()
		sp.apply_damage(1.0e6)
	if b != null and is_instance_valid(b) and not b.dead:
		b.apply_damage(float(b.health.hp) + 9999.0)


## Issue #615: beaten for the first time: the next crew up is heard of, and in
## story mode the parts this crew held back are on sale at Dorrin's.
func _on_first_beat() -> void:
	for cid in ids():
		if str(load_crew(cid).get("after", "")) == id:
			WorldState.set_flag("heard_crew_" + cid)
	if not WorldState.story_mode():
		return
	var g = _gear()
	for p in SpeederUpgrades.unlocked_by_crew(id):
		if g != null and g.hud != null:
			g.hud.toast_after(SpeederUpgrades.data().get("mechanic", {}).get("labels", {}).get("unlocked_toast", "%s now at Dorrin's.") % str(p.get("label", p.get("id", ""))), 4.0)


# ------------------------------------------------------------------ race gear (issue #616)

const GEAR_PARTS := { "seekers": "seekers", "mines": "mines", "deflector": "deflector", "nitro": "nitro_2" }


## The parts the crew's rules allow them (rules.gear: seekers, mines, deflector, nitro).
func gear_parts() -> Array:
	var out: Array = []
	for g in crew.get("rules", {}).get("gear", []):
		if GEAR_PARTS.has(str(g)):
			out.append(GEAR_PARTS[str(g)])
	return out


## A racer allowed to fight now: a seeker at you when you are in its nose, a
## mine when you are close behind it. Chances per second from rules.json.
func _use_gear(sp: SpeederNode, dt: float) -> void:
	if sp.gear == null or _player_speeder == null or not is_instance_valid(_player_speeder):
		return
	var to := _player_speeder.model.position - sp.model.position
	var ahead := to.dot(sp.model.forward())
	if sp.gear.can_seek() and ahead > 0.0 and sp.gear.pick_target(sp) == _player_speeder.hull \
			and _rng.randf() < rule("seeker_chance_s", 0.35) * dt:
		sp.gear.fire_seeker(sp, _player_speeder.hull)
	elif sp.gear.can_mine() and ahead < 0.0 and to.length() < rule("mine_behind_m", 30.0) \
			and _rng.randf() < rule("mine_chance_s", 0.6) * dt:
		sp.gear.drop_mine(sp)


## Someone crossed the line: the crowd waves.
func _cheer() -> void:
	for b in crowd:
		if is_instance_valid(b) and not b.dead and _rng.randf() < 0.7:
			b.act("gesture_wave")


func _clear_crowd() -> void:
	for b in crowd:
		if is_instance_valid(b):
			var pad = b.get_meta("pad", null)
			if pad != null and is_instance_valid(pad):
				pad.queue_free()
			b.queue_free()
	crowd.clear()


## [Z] near the grid: your speeder drives itself onto slot 0 and holds there.
func line_up() -> bool:
	if phase != Phase.GRID or lined_up:
		return false
	var p := _player()
	if p == null or not (p.piloting and p.vehicle is SpeederNode):
		return false
	var sp: SpeederNode = p.vehicle
	if pink and not _owned(sp):
		return false                             # pink slips: race the speeder you bet
	var s0: Dictionary = course.grid_slot(0)
	if sp.model.position.distance_to(s0.pos) > rule("line_up_reach", 45.0):
		return false
	_player_speeder = sp
	_lineup = SpeederBrain.new(sp.model)
	_lineup.park(s0.pos, float(s0.yaw))
	lined_up = true
	_toast(line("taunts"), 2.5)
	return true


func _tick_grid(dt: float) -> void:
	_grid_t += dt
	_tick_set_off()
	_tick_spawns()
	var p := _player()
	if not lined_up:
		var near: bool = p != null and p.piloting and p.vehicle is SpeederNode \
			and (p.vehicle as SpeederNode).model.position.distance_to(course.grid_slot(0).pos) <= rule("line_up_reach", 45.0)
		if near:
			var g = _gear()
			if g != null and g.hud != null:
				g.hud.set_prompt(line("line_up"))
			if InputMap.has_action("bay_land") and Input.is_action_just_pressed("bay_land"):
				line_up()
		return
	if _player_speeder == null or not is_instance_valid(_player_speeder) or not _player_speeder.riding:
		lined_up = false                         # got off or lost it: line up again
		return
	_player_speeder.set_external_command(_lineup.update(dt) if not _lineup.done else { "throttle": 0.0 })
	var ready := _lineup.done
	for rc in racers:
		if bool(rc.out) or rc.brain == null:
			continue
		if not bool(rc.seated):
			ready = false
		elif not rc.brain.done:
			if _grid_t - float(rc.left_t) > rule("grid_timeout_s", 40.0):
				var s: Dictionary = course.grid_slot(int(rc.slot))
				rc.speeder.place(s.pos, float(s.yaw))
				rc.brain.done = true
			else:
				ready = false
	if ready and _crowd_left <= 0:
		_start_countdown()


func _start_countdown() -> void:
	phase = Phase.COUNTDOWN
	_count = 3
	_count_left = rule("countdown_s", 1.0)
	_big(str(_count), 1.0)
	Sound.play(rule_text("beep"))
	for rc in racers:
		if not bool(rc.out) and rc.brain != null:
			rc.brain.idle()
	if not racers.is_empty():
		_say(racers[_rng.randi() % racers.size()].body, line("taunts"))


func _tick_countdown(dt: float) -> void:
	_tick_spawns()
	if _player_speeder != null and is_instance_valid(_player_speeder):
		_player_speeder.set_external_command({ "throttle": 0.0 })
	_count_left -= dt
	if _count_left > 0.0:
		return
	_count -= 1
	_count_left = rule("countdown_s", 1.0)
	if _count > 0:
		_big(str(_count), 1.0)
		Sound.play(rule_text("beep"))
		return
	go()


## GO: control back, the racers off along the racing line.
func go() -> void:
	phase = Phase.RACING
	_big(str(rules().get("hud", {}).get("go", "GO!")), 1.2)
	Sound.play(rule_text("go_sound"))
	course.flash(0, false)
	race_t = 0.0
	_lap_t0 = -1.0
	clean_gates = 0
	if _player_speeder != null and is_instance_valid(_player_speeder):
		_player_speeder.set_external_command({})
		_last[YOU] = _player_speeder.model.position
		_player_speeder.gear.refill()           # issue #616: a full load of race gear at the start
	var start := _line_start()
	var route: Array = []
	for k in course.line.size():
		route.append(course.line[(start + k) % course.line.size()])
	for rc in racers:
		if bool(rc.out) or rc.brain == null:
			continue
		rc.brain.pace = 1.0                       # race pace now
		rc.brain.may_boost = true
		rc.brain.follow(route, true)
		_last[rc.key] = rc.speeder.model.position


## The first racing-line point past the start line.
func _line_start() -> int:
	var g: Dictionary = course.gates[0]
	var best := 0
	var best_d := INF
	for i in course.line.size():
		var rel: Vector3 = (course.line[i] as Vector3) - (g.pos as Vector3)
		if rel.dot(g.fwd) <= 5.0:
			continue
		if rel.length() < best_d:
			best_d = rel.length()
			best = i
	return best


# ------------------------------------------------------------------ racing

func _tick_racing(dt: float) -> void:
	_tick_spawns()
	var you_pos := _you_pos()
	if player_out == "":
		var why := _why_out()
		if why != "":
			_out(why)
		elif _last.has(YOU) and you_pos != Vector3.INF:
			for e in course.step_racer(laps, YOU, _last[YOU], you_pos, true):
				_you_event(e)
		if you_pos != Vector3.INF:
			_last[YOU] = you_pos
	race_t += dt
	var shoot_lap := int(r("shoot_from_lap", 2))
	_jeer_left -= dt
	var beast_pts := _beast_points()
	for rc in racers:
		if bool(rc.out):
			continue
		var sp = rc.speeder
		if sp == null or not is_instance_valid(sp) or not sp.model.alive() or not sp.npc_driven():
			rc.out = true
			_hold(rc.body)
			continue
		var at: Vector3 = sp.model.position
		for e in course.step_racer(laps, rc.key, _last.get(rc.key, at), at, false):
			if str(e.type) == "pass" and int(e.gate) == 0:
				_cheer()
			if str(e.type) == "finish" and not results.has(rc.key):
				results.append(rc.key)
				rc.finished = true
				rc.brain.pace = 0.5
		_last[rc.key] = at
		# Lap `shoot_lap` on: you in their nose, in range: lasers.
		var lap_now := laps.lap(rc.key) + 1
		var shoot := shoot_lap > 0 and lap_now >= shoot_lap and player_out == "" and you_pos != Vector3.INF and not bool(rc.finished)
		rc.brain.shoot_at = you_pos if shoot else Vector3.INF
		if shoot:
			_use_gear(sp, dt)
		if shoot and rc.brain.command.get("fire", false) and _jeer_left <= 0.0:
			_jeer_left = 6.0
			_say(rc.body, line("jeers"))
		var avoid: Array = _beast_avoid(at, beast_pts)
		if _beast_touches(at, beast_pts):
			_eaten(rc)
			continue
		for other in racers:
			if other != rc and not bool(other.out) and other.speeder != null and is_instance_valid(other.speeder):
				if other.speeder.model.position.distance_to(at) < 40.0:
					avoid.append({ "pos": other.speeder.model.position, "radius": 2.0 })
		if _player_speeder != null and is_instance_valid(_player_speeder) and _player_speeder.model.position.distance_to(at) < 40.0:
			avoid.append({ "pos": _player_speeder.model.position, "radius": 2.0 })
		rc.brain.avoid = avoid
	_update_hud()
	if player_out == "":
		Objective.race = { "text": _gate_text(), "target": "race:%s:%d" % [course.id, laps.next_gate(YOU)], "key": "race" }
	if results.has(YOU) or player_out != "":
		_end_race()


## One of your crossings (RaceLaps events): the finish, the crowd's cheer, the
## clean-gate boost and the lap clock (issue #618).
func _you_event(e: Dictionary) -> void:
	match str(e.type):
		"finish":
			results.append(YOU)
			_maybe_finish_cam()
		"pass":
			if int(e.gate) == 0:
				_cheer()
		"start":
			_lap_t0 = race_t
		"gate":
			if float(e.off) <= rule("gate_boost_off", 0.25):
				_clean_gate()
		"lap":
			_lap_done()


## Dead centre through a checkpoint: a little boost back, a chime.
func _clean_gate() -> void:
	clean_gates += 1
	if _player_speeder != null and is_instance_valid(_player_speeder):
		var m := _player_speeder.model
		var tank := m.p("boost_time", 3.5)
		m.boost_left = minf(tank, m.boost_left + tank * rule("gate_boost", 0.35))
	Sound.play("droid_beep")


## A lap of yours done: its time against your best on this course.
func _lap_done() -> void:
	if _lap_t0 < 0.0:
		return
	var t := race_t - _lap_t0
	_lap_t0 = race_t
	var key := "race_best_" + course.id
	var best := int(WorldState.counters.get(key, 0))
	var ms := int(round(t * 1000.0))
	if best == 0 or ms < best:
		WorldState.counters[key] = ms
		_toast(str(rules().get("hud", {}).get("record", "New lap record: %s")) % clock(t), 3.5)
		course.refresh_record()


## "1:12.4".
static func clock(t: float) -> String:
	if t <= 0.0:
		return "--:--.-"
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


# ------------------------------------------------------------------ finish cam (issue #618)

## You crossed the line: a close finish (another racer within finish_gap_s of the
## line) or a win gets the finish cam.
func _maybe_finish_cam() -> void:
	if not bool(rules().get("finish_cam", true)):
		return
	var close := results.size() == 1                # you won
	var g: Dictionary = course.gates[0]
	for rc in racers:
		if bool(rc.out) or rc.speeder == null or not is_instance_valid(rc.speeder):
			continue
		var m: HoverModel = rc.speeder.model
		var gap := absf(((g.pos as Vector3) - m.position).dot(g.fwd)) / maxf(absf(m.speed), 1.0)
		if gap <= rule("finish_gap_s", 1.0):
			close = true
	if close:
		start_finish_cam()


## Time slows to `finish_slow` for finish_cam_s (real seconds); the view cuts to a
## low side shot of your speeder; the replay filter goes over it.
func start_finish_cam() -> void:
	if finish_cam_on or _player_speeder == null or not is_instance_valid(_player_speeder):
		return
	finish_cam_on = true
	Engine.time_scale = rule("finish_slow", 0.33)
	_fc_end_ms = Time.get_ticks_msec() + int(rule("finish_cam_s", 2.2) * 1000.0)
	_aim_finish_cam()
	_player_speeder.cam_override_on = true
	_player_speeder.cam_override_fov = rule("finish_fov", 50.0)
	if bool(rules().get("finish_filter", true)):
		_filter(true)


func _aim_finish_cam() -> void:
	var m := _player_speeder.model
	var right := m.forward().cross(m.up()).normalized()
	var at := m.position + right * rule("finish_cam_side_m", 7.0) + m.forward() * 6.0 + m.up() * 0.9
	_player_speeder.cam_override = Transform3D(Basis.IDENTITY, at).looking_at(m.position + m.up() * 0.6, m.up())


func _tick_finish_cam() -> void:
	if not finish_cam_on:
		return
	if Time.get_ticks_msec() >= _fc_end_ms or _player_speeder == null or not is_instance_valid(_player_speeder):
		stop_finish_cam()
		return
	_aim_finish_cam()


func stop_finish_cam() -> void:
	finish_cam_on = false
	Engine.time_scale = 1.0
	if _player_speeder != null and is_instance_valid(_player_speeder):
		_player_speeder.cam_override_on = false
	_filter(false)


## The replay look: letterbox bars, the vignette turned up, a warm wash. No new
## shaders: two bars and a tint on a canvas layer, and the look's own vignette.
func _filter(on: bool) -> void:
	var f: Dictionary = rules().get("finish_filter_look", {})
	if on and _fc_layer == null:
		_fc_layer = CanvasLayer.new()
		_fc_layer.layer = int(f.get("layer", 50))       # over the HUD: a replay has no HUD bars
		add_child(_fc_layer)
		var wash := ColorRect.new()
		wash.color = Color(str(f.get("tint", "#ffb060"))) * Color(1, 1, 1, float(f.get("tint_alpha", 0.12)))
		wash.set_anchors_preset(Control.PRESET_FULL_RECT)
		wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fc_layer.add_child(wash)
		for top in [true, false]:
			var bar := ColorRect.new()
			bar.color = Color.BLACK
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var px := float(f.get("bar_px", 70.0))
			bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
			if top:
				bar.offset_bottom = px
			else:
				bar.offset_top = -px
			_fc_layer.add_child(bar)
	if _fc_layer != null:
		_fc_layer.visible = on
	# A replay has no HUD: hide the other canvas layers while it runs, then put
	# back exactly the ones that were showing.
	if on:
		_fc_hidden.clear()
		for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var cl := c as CanvasLayer
			if cl != _fc_layer and cl.visible and cl.layer < _fc_layer.layer:
				cl.visible = false
				_fc_hidden.append(cl)
	else:
		for cl in _fc_hidden:
			if is_instance_valid(cl):
				cl.visible = true
		_fc_hidden.clear()
	var look = demo.get("look") if demo != null else null
	if look != null and is_instance_valid(look) and look.get("vignette") != null:
		var vm = look.vignette.material
		if vm is ShaderMaterial:
			if on:
				vm.set_shader_parameter("strength", float(f.get("vignette", 0.6)))
			elif look.has_method("_apply_vignette"):
				look._apply_vignette()


func _exit_tree() -> void:
	if finish_cam_on:
		Engine.time_scale = 1.0


func _you_pos() -> Vector3:
	if _player_speeder != null and is_instance_valid(_player_speeder) and _player_speeder.model.alive():
		return _player_speeder.model.position
	var p := _player()
	return p.global_position if p != null else Vector3.INF


func _why_out() -> String:
	if _player_speeder == null or not is_instance_valid(_player_speeder) or not _player_speeder.model.alive():
		return "why_wrecked"
	if not _player_speeder.riding:
		return "why_off"
	var at := _player_speeder.model.position
	var best := INF
	for p in course.line:
		best = minf(best, at.distance_to(p))
	if best > r("off_course_m", 400.0):
		return "why_far"
	return ""


func _out(why: String) -> void:
	player_out = why
	_toast(line("out", { "why": line(why) }), 4.0)


func _end_race() -> void:
	phase = Phase.RETURN
	_return_t = 0.0
	Objective.race = {}
	SpeederMine.clear_all()                 # issue #616: no mines left lying on the course
	# Finishers first, then whoever was furthest round.
	var order: Array = results.duplicate()
	var rest: Array = []
	for rc in racers:
		if not order.has(rc.key) and not bool(rc.out):
			rest.append(rc.key)
	rest.sort_custom(func(a, b): return laps.progress(a) > laps.progress(b))
	order.append_array(rest)
	winner = str(order[0]) if not order.is_empty() else ""
	var pot := stake * int(r("multiple", 10))
	var was_pink := pink
	if pink:
		_settle_slips(winner == YOU)
		pink = false
	if winner == YOU:
		var first := not WorldState.has_flag("crew_beaten_" + id)
		WorldState.on_race_won(id, pot)
		Sound.play("quest_success")
		_toast(line("won", { "pot": pot }), 5.0)
		_say(leader(), line("leader_lost") + " " + line("next_crew"))
		if first:
			_on_first_beat()
	else:
		_toast(line("lost", { "winner": _name_of(winner) }), 5.0)
		_say(leader(), line("leader_won"))
	settle_quests(id, winner == YOU, was_pink)
	_show_results(order)
	_offer_rematch(was_pink)
	for rc in racers:
		if rc.brain != null and _speeder_ok(rc) and rc.speeder.npc_driven():
			rc.brain.shoot_at = Vector3.INF
			rc.brain.pace = rule("cruise_pace", 0.4)   # a slow cruise home, no racing
			rc.brain.may_boost = false
			rc.brain.park(_park_pos(rc), _park_yaw(rc))
	if _player_speeder != null and is_instance_valid(_player_speeder):
		_player_speeder.set_external_command({})
	if track_beast != null and is_instance_valid(track_beast) and not track_beast.dead:
		# It crawls off, away from the course, and is gone once the racers are home.
		var away := track_beast.global_position - course.center
		track_beast.home = track_beast.global_position + (away.normalized() if away.length() > 1.0 else Vector3.RIGHT) * 1500.0


## A money race is over: the rematch is open if you can cover the same stake;
## if not, a line saying so, and they head home where you can challenge them again.
func _offer_rematch(was_pink: bool) -> void:
	rematch_on = false
	if was_pink or stake <= 0:
		return
	last_stake = stake
	if can_afford(last_stake):
		rematch_on = true
		return
	var g = _gear()
	var text := line("rematch_poor", { "stake": last_stake })
	if g != null and g.hud != null:
		g.hud.toast_after(text, 4.0)


func _name_of(key: String) -> String:
	if key == YOU:
		return str(rules().get("hud", {}).get("you", "You"))
	for rc in racers:
		if rc.key == key and is_instance_valid(rc.body):
			return rc.body.display_name if rc.body.display_name != "" else key
	return key


func _tick_return(dt: float) -> void:
	_return_t += dt
	if _return_t > 5.0 and not crowd.is_empty():
		_clear_crowd()
	var all_home := true
	for rc in racers:
		if bool(rc.home):
			continue
		if rc.brain == null or not _speeder_ok(rc) or not rc.speeder.npc_driven():
			continue                             # out of it: sorted out by _put_away
		if rc.brain.done:
			_park_home(rc)
		else:
			all_home = false
	if all_home or _return_t > rule("return_s", 90.0):
		_put_away()


## Parked on its spot: the racer climbs off and walks back to where they stand
## (set down there if you are too far off for the sand to hold them).
func _park_home(rc: Dictionary) -> void:
	var sp: SpeederNode = rc.speeder
	sp.step_off()
	sp.brain = null
	rc.brain = null
	rc.home = true
	if _body_ok(rc):
		var at := _ground(_v2(rc.cfg.get("stand", [0, 0])))
		var p := _player()
		if p != null and p.global_position.distance_to(at) <= rule("walk_home_m", 80.0):
			rc.body.go_to(at)
		else:
			_stand_at(rc.body, at)


func _stand_at(b: NpcBody, at: Vector3) -> void:
	b.stop()
	b.global_position = at
	b.controller.body_pos = at
	b.velocity = Vector3.ZERO
	b.set_physics_process(true)


## A racer thrown clear out on the course stands where they landed until the
## race is over (no sand collider out there unless you are near).
func _hold(b: NpcBody) -> void:
	if b == null or not is_instance_valid(b) or b.dead:
		return
	await get_tree().physics_frame          # off the seat first (SpeederNode.step_off)
	if not is_instance_valid(b) or b.dead:
		return
	var at := course.to_world_near(b.global_position)
	b.global_position = at
	b.controller.body_pos = at
	b.set_physics_process(false)


## The race is over and everyone who can is home. Anyone still out (thrown
## clear, or not back by return_s) is set down at their spot, their speeder parked
## again if it lives; a speeder whose racer died is gone until the world next
## loads. Issue #617: a pink-slip race changes what the leader parks.
func _put_away() -> void:
	for rc in racers:
		_settle_home(rc)
	rematch_on = false
	_settle_leader_ride()
	_crowd_left = 0
	_beast_due = false
	_clear_crowd()
	_remove_beast()
	_player_speeder = null
	phase = Phase.IDLE
	if _hud_list != null:
		_hud_list.visible = false
	if _hud_lap != null:
		_hud_lap.visible = false


## One racer home now: their speeder parked on its spot (or gone, if it or they
## are), and they stand at their spot.
func _settle_home(rc: Dictionary) -> void:
	var sp = rc.speeder
	var alive := _body_ok(rc)
	if sp != null and is_instance_valid(sp):
		if sp.model.alive() and alive:
			if not bool(rc.home):
				sp.step_off()
				sp.place(_park_pos(rc), _park_yaw(rc))
			sp.brain = null
		else:
			sp.step_off()
			sp.queue_free()
			rc.speeder = null
	rc.brain = null
	if alive and not bool(rc.home):
		_stand_at(rc.body, _ground(_v2(rc.cfg.get("stand", [0, 0]))))
	rc.home = true


## Placings now: { key -> place (1 = first) } by finish order, then progress.
func places() -> Dictionary:
	var keys: Array = [YOU]
	for rc in racers:
		if not bool(rc.out):
			keys.append(rc.key)
	keys.sort_custom(func(a, b):
		var fa := results.find(a)
		var fb := results.find(b)
		if fa >= 0 or fb >= 0:
			return fa >= 0 and (fb < 0 or fa < fb)
		var pa := laps.progress(a)
		var pb := laps.progress(b)
		if pa != pb:
			return pa > pb
		return _to_next(a) < _to_next(b))
	var out := {}
	for i in keys.size():
		out[keys[i]] = i + 1
	return out


func _to_next(key: String) -> float:
	var at: Vector3 = _last.get(key, Vector3.INF)
	var g := course.gate_pos(laps.next_gate(key))
	return at.distance_to(g) if at != Vector3.INF and g != Vector3.INF else INF


func _gate_text() -> String:
	var n := laps.next_gate(YOU)
	var total := course.gates.size()
	return "%s  %s" % [course.label(), ("Finish line" if n == 0 else "Gate %d/%d" % [n, total - 1])]


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	if not found:
		return
	_tick_rings()
	_tick_finish_cam()
	match phase:
		Phase.IDLE:
			_tick_build()
			_tick_focus()
		Phase.GRID:
			_tick_grid(dt)
		Phase.COUNTDOWN:
			_tick_countdown(dt)
		Phase.RACING:
			_tick_racing(dt)
		Phase.RETURN:
			_tick_return(dt)
			if phase == Phase.RETURN:
				_tick_rematch()
	if _big_left > 0.0:
		_big_left -= dt
		if _big_left <= 0.0 and _hud_big != null:
			_hud_big.visible = false


## Speeder race lag: the crew and the crowd think by distance, on the town's own
## rings (NpcRings, content/core/npcs/wake_rings.json): full near you, slower
## further out, asleep past the draw distance. NpcRings itself only walks the
## garrison and the townsfolk, so these ran every tick wherever you were. A body
## walking to its speeder, hurt, or after you is kept awake.
func _tick_rings() -> void:
	var rings = demo.get("npc_rings") if demo != null else null
	var p := _player()
	if rings == null or not is_instance_valid(rings) or p == null:
		return
	var at := p.global_position
	for rc in racers:
		var b = rc.body
		if b == null or not is_instance_valid(b):
			continue
		var awake: bool = b.dead or b.hostile or b.perception.noticed or b.health.hp < b.health.max_hp \
			or (phase == Phase.GRID and not bool(rc.seated) and _grid_t >= float(rc.set_off))
		_ring(rings, b, at, awake)
	for b in crowd:
		if is_instance_valid(b):
			_ring(rings, b, at, b.dead or b.hostile or b.perception.noticed)


func _ring(rings, b: NpcBody, at: Vector3, awake: bool) -> void:
	var was := int(rings.ring_of.get(b, NpcRingsT.Ring.FULL))
	rings._put(b, NpcRingsT.Ring.FULL if awake else rings.ring_for(b.global_position.distance_to(at), was))


func _tick_focus() -> void:
	var p := _player()
	var l := leader()
	var g = _gear()
	if p == null or l == null or menu.is_open():
		in_reach = false
		return
	var to := p.global_position - l.global_position
	in_reach = not p.piloting and to.length() <= 3.4 and (g == null or g.focus.is_empty())
	if not in_reach:
		return
	if g != null and g.hud != null:
		g.hud.set_prompt(line("talk"))
	if not p.locked and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		talk()


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	_hud_lap = _hud_label(28, Vector2(-260, 90), HORIZONTAL_ALIGNMENT_RIGHT)
	_hud_big = _hud_label(84, Vector2(-200, -120), HORIZONTAL_ALIGNMENT_CENTER)
	_hud_list = _hud_label(22, Vector2(-200, -40), HORIZONTAL_ALIGNMENT_CENTER)


func _hud_label(size: int, at: Vector2, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("#ffe6b0"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.size = Vector2(400, 200)
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		l.position = Vector2(at.x - 160, at.y)
	else:
		l.set_anchors_preset(Control.PRESET_CENTER)
		l.position = at
	l.visible = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(l)
	return l


func _big(text: String, secs: float) -> void:
	if _hud_big == null:
		return
	_hud_big.text = text
	_hud_big.visible = true
	_big_left = secs


func _update_hud() -> void:
	if _hud_lap == null or laps == null:
		return
	var h: Dictionary = rules().get("hud", {})
	var total := course.laps_total()
	var lap_now := mini(laps.lap(YOU) + 1, total)
	var place := int(places().get(YOU, 1))
	var names: Array = h.get("places", ["1st", "2nd", "3rd", "4th"])
	_hud_lap.text = (str(h.get("lap", "LAP %d/%d")) % [lap_now, total]) + "\n" + str(names[clampi(place - 1, 0, names.size() - 1)])
	# Issue #618: this lap's clock against your best here.
	if _lap_t0 >= 0.0:
		_hud_lap.text += "\n" + str(h.get("split", "%s  best %s")) % [clock(race_t - _lap_t0), clock(best_lap())]
	_hud_lap.visible = true


func _show_results(order: Array) -> void:
	if _hud_list == null:
		return
	var h: Dictionary = rules().get("hud", {})
	var rows: Array = []
	for i in order.size():
		rows.append(str(h.get("results", "%d. %s")) % [i + 1, _name_of(str(order[i]))])
	_hud_list.text = "\n".join(rows)
	_hud_list.visible = true


## The crews on a world (their course's world).
static func crews_for(world_id: String) -> Array:
	var out: Array = []
	for cid in ids():
		var c := load_crew(cid)
		if str(RaceCourse.load_course(str(c.get("course", ""))).get("world", "")) == world_id:
			out.append(c)
	return out
