extends GutTest
## Issue #875: the red desert world's data, checked without a scene. The town
## validates and is tall, the locals are the red folk, the mountains keep to
## their pockets with sand between them, every tunnel range is roofed end to end,
## the outposts stand clear of the rock, and the native packs keep to the desert
## half.

const TownLayout := preload("res://src/systems/world/town_layout.gd")
const Landforms := preload("res://src/systems/look/desert_landforms.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var cc
var planet: Dictionary


func before_all() -> void:
	cc = CoreScript.new()
	cc.load_from()
	planet = PlanetGen.build("port_red", cc)


func _sphere() -> PlanetSphere:
	return PlanetTerrain.for_planet(planet).sphere


func test_it_is_the_red_system_s_desert() -> void:
	assert_eq(str(planet.get("type", "")), "red_desert")
	assert_eq(PlanetGen.system_of("port_red"), "red_reach", "it hangs in the red system")
	assert_eq(str(planet.cfg.get("encounter", "")), "orbital_skirmish", "a skirmish waits on the way up")


func test_the_town_is_valid_and_tall() -> void:
	var t := TownLayout.new()
	t.load_from_dict(planet.town)
	assert_eq(t.validate().size(), 0, str(t.validate().slice(0, 3)))
	var towers := (planet.town.boxes as Array).filter(func(b): return str(b.get("look", "")).begins_with("tower_"))
	assert_gte(towers.size(), 4, "towers stand over the street")
	var tallest := 0.0
	for b in towers:
		tallest = maxf(tallest, float((b.get("max", [0, 0, 0]) as Array)[1]))
	assert_gt(tallest, 20.0, "taller than the home port's tallest tower (20 m)")


func test_the_locals_are_the_red_folk() -> void:
	var red := 0
	var plain := 0
	for m in planet.town.markers:
		var s := str(m.get("soldier", ""))
		if s.begins_with("red_local"):
			red += 1
		elif s in ["local_resident", "local_merchant", "local_patron"]:
			plain += 1
	assert_gt(red, 0, "red locals stand in the town")
	assert_eq(plain, 0, "no home port local left unswapped")
	for id in ["red_local_resident", "red_local_merchant", "red_local_patron"]:
		assert_true(FileAccess.file_exists("res://content/core/soldiers/%s.json" % id), id + " has a profile")


func test_the_mountains_keep_to_pockets_with_sand_between() -> void:
	var data := Landforms.load_for(planet)
	var sp := _sphere()
	var spots: Array = Landforms.mountain_spots(data, sp)
	assert_gte(spots.size(), 40, "a planet of mountains")
	assert_lte(spots.size(), 80, "but not so many it chokes the frame")
	# Sand between every two loose peaks (course ranges are one piece).
	var loose := spots.filter(func(m): return not m.has("course"))
	var tight := INF
	for i in loose.size():
		for j in range(i + 1, loose.size()):
			var a: Dictionary = loose[i]
			var b: Dictionary = loose[j]
			var gap := sp.ground_dist(a.map, b.map) - float(a.plan.radius) - float(b.plan.radius)
			tight = minf(tight, gap)
	assert_gt(tight, 20.0, "no two mountains run into each other")
	# Clear of the port and of every outpost pad.
	var keep: Array = [Vector2.ZERO]
	for lm in planet.get("world", {}).get("landmarks", []):
		keep.append(Vector2(float(lm.at[0]), float(lm.at[2])))
	for m in spots:
		for k in keep:
			assert_gt(sp.ground_dist(m.map, k) - float(m.plan.radius), 60.0, "%s stands clear of %s" % [m.get("id", "?"), str(k)])


func test_every_tunnel_range_is_roofed_end_to_end() -> void:
	var data := Landforms.load_for(planet)
	var ranges := 0
	for m in Landforms.mountain_spots(data, _sphere()):
		if not m.has("course"):
			continue
		ranges += 1
		var tn: Dictionary = m.plan.tunnel
		var pts := RockMountain._resample(tn.path, 2.0)
		var open := 0
		for i in range(int(ceil(tn.gates.s_entry / 2.0)), int(tn.gates.s_exit / 2.0)):
			if not tn.roofs.any(func(poly): return Geometry2D.is_point_in_polygon(pts[i], poly)):
				open += 1
		assert_eq(open, 0, "%s: roofed from end to end" % m.id)
		assert_gt(float(tn.gates.s_exit) - float(tn.gates.s_entry), 150.0, "%s: a real ride under rock" % m.id)
	assert_eq(ranges, 6, "six tunnel ranges")


func test_the_natives_keep_to_the_desert_half() -> void:
	var nat: Dictionary = planet.get("natives", {})
	assert_false(nat.is_empty(), "the world has its own people")
	assert_gte((nat.packs as Array).size(), 2)
	assert_true(str(nat.people.label).begins_with("the "), "named for the world")
	for p in nat.packs:
		for q in p.route:
			assert_gt((q as Vector2).y, 0.0, "%s walks the desert half (map z > 0)" % p.id)
