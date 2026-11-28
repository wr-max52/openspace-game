extends Node
## Issue #715: a place's people come in as you walk up and go when you leave.
## The town's ambient people (the cantina's patrons and band, the market's
## merchants, the residents) used to be built on the way down, at ~7 km up,
## long before anyone could see them, and were never let go. Now:
##
##   - within in_m of the town (the nearest player), one body a tick is built
##     until all of them stand;
##   - past out_m they are freed, a few a tick, and their state kept: who died
##     stays dead, and the same marker builds the same person again (the same
##     name key, so the same name and anything said to them);
##   - in between nothing changes (NpcRings still puts the far ones to sleep).
##
## Numbers from the "by_distance" block of content/core/npcs/wake_rings.json.
## The town's guards are not touched (their garrison's alarms, respawns and
## bounties rely on them being there), nor anyone something else talks through:
## the fence and the player-made stall keepers (their talk spots hold the body).
## Off on a LAN game (the host runs everyone; a guest shows the host's).
##
## TownDemo builds a managed marker through this node: `defer` instead of
## building it (a handoff from the sky), or `track` once it is built.

const NpcRingsT := preload("res://src/systems/npc/npc_rings.gd")

var demo                               ## town_demo.gd
var in_m := 300.0
var out_m := 900.0
var free_per_tick := 4
var roles: Array = ["ambient"]
var built: Dictionary = {}             ## marker id -> NpcBody
var dead: Dictionary = {}              ## marker id -> true: died this visit, not built again
var _markers: Dictionary = {}          ## marker id -> marker (every one this manages)
var _keep: Dictionary = {}             ## marker ids never managed (talk spots hold them)
var _centre := Vector3.ZERO
var builds := 0                        ## bodies built here (tests, probes)
var frees := 0                         ## bodies let go (tests, probes)


static func config() -> Dictionary:
	return NpcRingsT.config().get("by_distance", {})


## Null when the rule is off (no block, a LAN game, npcs off).
static func make(town_demo) -> Node:
	var c := config()
	if c.is_empty() or not bool(c.get("on", true)) or NetSession.active():
		return null
	var p = load("res://src/systems/npc/people_by_distance.gd").new()
	p.setup(town_demo, c)
	return p


func setup(town_demo, c: Dictionary) -> void:
	demo = town_demo
	name = "PeopleByDistance"
	in_m = float(c.get("in_m", in_m))
	out_m = maxf(float(c.get("out_m", out_m)), in_m + 50.0)
	free_per_tick = maxi(1, int(c.get("free_per_tick", free_per_tick)))
	roles = c.get("roles", roles)
	_centre = TownNav.town_bounds(demo.town).get_center()
	_centre.y = 0.0
	if demo.gear != null:
		for v in demo.gear.vendors:
			if str(v.cfg.get("id", "")) == "fence":
				_keep[str(v.cfg.get("marker", ""))] = true


## Whether marker `m` comes and goes with distance.
func manages(m: Dictionary) -> bool:
	var id := str(m.get("id", ""))
	if not m.has("soldier") or not roles.has(str(m.get("role", ""))) or _keep.has(id):
		return false
	if not demo._community().look_for(id).is_empty():
		return false                  # a player-made stall keeper: their talk spot holds the body
	return true


## True when a managed marker should wait (nobody near the town yet).
func far() -> bool:
	return _viewer_dist() > in_m


## Not built now: built when someone comes within in_m.
func defer(m: Dictionary) -> void:
	_markers[str(m.id)] = m


## Built by the town: from now on it comes and goes.
func track(m: Dictionary, body: NpcBody) -> void:
	var id := str(m.id)
	_markers[id] = m
	if body == null:
		return
	built[id] = body
	body.died.connect(func(): dead[id] = true)


func has_any() -> bool:
	return not _markers.is_empty()


func _physics_process(_dt: float) -> void:
	if demo == null or _markers.is_empty():
		return
	var d := _viewer_dist()
	if d <= in_m:
		_build_one()
	elif d >= out_m:
		_free_some()


func _build_one() -> void:
	for id in _markers:
		if built.has(id) or dead.has(id):
			continue
		var body: NpcBody = demo._build_npc(_markers[id], true)
		builds += 1
		if body == null:
			dead[id] = true           # nothing to build there (a post left empty): never ask again
			return
		track(_markers[id], body)
		# make_soldier put a fighting local in demo.locals (the band stays out):
		# the town's Townsfolk runs it from now on.
		if demo.townsfolk != null and is_instance_valid(demo.townsfolk) and demo.locals.has(body):
			demo.townsfolk.add_member(body)
		return


func _free_some() -> void:
	var n := 0
	for id in built.keys():
		if n >= free_per_tick:
			return
		var body = built[id]
		built.erase(id)
		n += 1
		if not is_instance_valid(body):
			continue
		if demo.townsfolk != null and is_instance_valid(demo.townsfolk):
			demo.townsfolk.remove_member(body)
		demo.locals.erase(body)
		demo.stage_performers.erase(body)
		demo.characters.erase(id)
		body.queue_free()
		frees += 1


## How far the viewer (the camera, else the ship) is from the town's middle.
func _viewer_dist() -> float:
	if demo == null or not demo.is_inside_tree():
		return INF
	return (demo.sight_eye() as Vector3).distance_to(_centre)
