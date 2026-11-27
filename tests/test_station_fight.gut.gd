extends GutTest
## Issue #701: a fight aboard the station (StationCrowd's fighters, NpcBody.free_walk:
## no navmesh aboard). A fighter that walks straight at you into a stall steps back
## and round it instead of standing pinned there, and the real body that replaces a
## crowd puppet wears the puppet's own pieces.

const TownDemo := preload("res://scenes/town_demo.gd")
const StationCrowd := preload("res://src/systems/world/station_crowd.gd")
const StationFill := preload("res://src/systems/world/station_fill.gd")
const TownBuildings := preload("res://src/systems/world/town_buildings.gd")
const HOST := "ringed_giant"

var _sphere_before: PlanetSphere


func before_each() -> void:
	WorldState.reset()
	_sphere_before = PlanetSphere.current


func after_each() -> void:
	PlanetSphere.current = _sphere_before
	GameFlow.reset()
	WorldState.reset()


func _host():
	GameFlow.reset()
	GameFlow.resumed = true
	GameFlow.planet_id = HOST
	GameFlow.change_scene = func(_p: String) -> void: pass
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = true
	add_child_autofree(t)
	return t


func _station(t):
	for i in 120:
		if not t.stations.is_empty():
			return t.stations[0]
		await wait_physics_frames(1)
	return null


## The crowd's 10 fighters for 30 s: none stands pinned (wants to walk, does not
## get anywhere) for more than 3 s.
func test_a_fight_aboard_has_nobody_stuck_on_the_stalls() -> void:
	var t = _host()
	var s = await _station(t)
	assert_not_null(s, "the giant's scene builds the station")
	if s == null or s.crowd == null:
		return
	var crowd = s.crowd
	for i in 300:
		if crowd.built:
			break
		await wait_physics_frames(1)
	assert_true(crowd.built, "the crowd is aboard")
	# You on the markets' walkway, among the armed locals, and not to be killed.
	var on: Array = crowd.people.filter(func(p): return str(p.home) == "markets" and p.armed and not p.dead)
	assert_gt(on.size(), 3, "armed locals on the markets floor")
	var first: Dictionary = on[0]
	var f: Dictionary = (first.tower as Dictionary).floors[int(first.fi)]
	var c: Vector2 = first.tower.c
	var player = t._player
	player.invulnerable_left = 1.0e9
	player.global_position = s.frame * Vector3(c.x + s.hull.gap_r + 3.5, float(f.y) + 0.5, c.y)
	await wait_physics_frames(5)
	crowd.hurt(first, 1.0, player)
	var last := {}            # fighter -> where it was at the last look
	var pinned := {}          # fighter -> seconds it has wanted to walk and not got anywhere
	var worst := 0.0
	var most := 0
	for k in 60:              # 30 s, a look every 0.5 s
		player.invulnerable_left = 1.0e9
		await wait_physics_frames(30)
		var fighters: Array = []
		for p in crowd.people:
			if p.fighter != null and is_instance_valid(p.fighter) and not (p.fighter as NpcBody).dead:
				fighters.append(p.fighter)
		most = maxi(most, fighters.size())
		for g in fighters:
			var at: Vector3 = (g as Node3D).global_position
			var wants: bool = (g as NpcBody).command.go_to != Vector3.INF and not (g as NpcBody).arrived()
			if last.has(g) and wants and at.distance_to(last[g]) < 0.15:
				pinned[g] = float(pinned.get(g, 0.0)) + 0.5
			else:
				pinned[g] = 0.0
			worst = maxf(worst, float(pinned[g]))
			last[g] = at
	assert_gte(most, 5, "the alarm roused a squad")
	assert_lte(worst, 3.0, "nobody is pinned on a stall for more than 3 s (worst %.1f s)" % worst)


## The rich floor (the suites, homes_2) is the barge bosses': everyone who lives
## there wears a variation of the barge duke, carries nothing, and stays home, and
## nobody from the other floors goes up there.
func test_the_suites_are_the_barge_bosses_and_theirs_alone() -> void:
	var t = _host()
	var s = await _station(t)
	assert_not_null(s, "the giant's scene builds the station")
	if s == null or s.crowd == null:
		return
	var crowd = s.crowd
	for i in 300:
		if crowd.built:
			break
		await wait_physics_frames(1)
	assert_true(crowd.built, "the crowd is aboard")
	var rich: Array = crowd.people.filter(func(p): return str(p.home) == "homes_2")
	var looks: Array = crowd.floor_cfg("homes_2").get("looks", [])
	assert_eq(rich.size(), int(crowd.cfg.floors.homes_2), "the suites' people are aboard")
	assert_gte(looks.size(), 3, "a few variations of the boss")
	var kit := CharacterKit.new(LookMaterials.new())
	for a in looks:
		assert_true(kit.archetypes().has(a), "%s is a look (content/look/characters.json)" % a)
		assert_eq(str(kit.palettes[a].get("base", "")), "barge_duke", "%s is a variation of the barge duke" % a)
	var worn := {}
	for p in rich:
		assert_true(looks.has(p.look), "%s on the suites is a boss" % p.look)
		assert_false(p.armed, "the bosses carry nothing")
		worn[p.look] = true
	assert_gt(worn.size(), 1, "more than one variation walks the suites")
	assert_false(crowd.people.any(func(p): return str(p.home) != "homes_2" and looks.has(p.look)), "the bosses live only on the suites")
	var on_suites := func(p) -> bool: return str((p.tower as Dictionary).floors[int(p.fi)].id) == "homes_2"
	for k in 40:              # 40 s of walking, elevators and tunnels
		await wait_physics_frames(60)
		for p in crowd.people:
			assert_eq(on_suites.call(p), str(p.home) == "homes_2", "%s (home %s) keeps to its own side of the suites' door" % [p.look, p.home])
			if on_suites.call(p) != (str(p.home) == "homes_2"):
				return


## The real body that replaces a puppet is dressed in the puppet's pieces.
func test_a_roused_local_wears_its_puppets_outfit() -> void:
	var kit := CharacterKit.new(LookMaterials.new())
	var crowd := StationCrowd.new()
	crowd.cfg = { "fighter": "local_resident" }
	for i in 4:                 # the kit deals the pieces round, so each body differs
		var puppet := kit.build("station_local", "walker")
		var worn: Dictionary = puppet.get_meta("outfit", {})
		assert_false(worn.is_empty(), "the puppet wears kit pieces")
		var soldier: Dictionary = crowd.fighter_soldier({ "look": "station_local", "body": puppet })
		var g := NpcBody.new()
		g.setup(soldier, Vector3.ZERO, 0.0, LookMaterials.new())
		add_child_autofree(g)
		assert_eq(g.look_body.get_meta("outfit", {}), worn, "fighter %d dressed as its puppet" % i)
		puppet.free()
	crowd.free()


## The crowd's aisle in front of a packed ring of booths keeps clear of the deepest
## of them (deeper and shallower booths side by side), not just of its own booth.
func test_a_packed_rings_aisle_clears_its_deepest_booth() -> void:
	var hull := StationHull.for_id("orbital_station")
	var fill = StationFill.new(TownBuildings.new(LookMaterials.new(), null), hull, func(_f: String) -> Material: return StandardMaterial3D.new())
	fill.solids_only = true
	var t: Dictionary = hull.towers[0]
	for face in ["in", "out"]:
		var ring := { "r": 30.0, "face": face, "depth": [2.8, 3.4] }
		var net := { "alleys": [], "stops": [] }
		fill._pack_ring(t, float(t.floors[0].y), ring, [], 0, net)
		assert_gt((net.stops as Array).size(), 10, "a ring of booths")
		var clear := snappedf(3.4, 0.25) * 0.5 + 0.9
		var short: Array = (net.stops as Array).filter(func(st): return absf(float(st.r) - float(st.face_r)) < clear - 0.001)
		assert_eq(short.size(), 0, "%s ring: the aisle is in front of the deepest booth" % face)

