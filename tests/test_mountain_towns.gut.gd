extends GutTest
## Issue #877: the mountain towns' data, checked without a scene. Every place's
## layout validates rule for rule, its people are its own folk (no Remnant, no
## home port local), each town has its cantina, barkeep and stall, every town
## fits on its peak's top, the lift's shaft stands clear of the rock with its
## bridge reaching the town's apron, the road curls up once round its peak clear
## of the rock, and every place has its pin on the map.

const TownLayout := preload("res://src/systems/world/town_layout.gd")
const Landforms := preload("res://src/systems/look/desert_landforms.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var cc
var planet: Dictionary
var st: Dictionary
var sp: PlanetSphere
var sites: Dictionary = {}


func before_all() -> void:
	cc = CoreScript.new()
	cc.load_from()
	planet = PlanetGen.build("port_red", cc)
	st = planet.cfg.settlements
	sp = PlanetTerrain.for_planet(planet).sphere
	var spots := {}
	for m in Landforms.mountain_spots(Landforms.load_for(planet), sp):
		spots[str(m.id)] = m
	for p in st.places:
		var m: Dictionary = spots.get("butte_" + str(p.id), {})
		if not m.is_empty():
			sites[str(p.id)] = Settlements.site(p, st, sp, m)


func test_seven_places_three_kinds() -> void:
	assert_eq((st.places as Array).size(), 7)
	assert_eq(sites.size(), 7, "every place has its peak")
	var kinds := {}
	for p in st.places:
		kinds[str(p.kind)] = int(kinds.get(str(p.kind), 0)) + 1
	assert_eq(kinds, { "town": 2, "ring": 1, "ledge": 4 })


func test_every_layout_validates() -> void:
	for id in sites:
		var t := TownLayout.new()
		t.load_from_dict(sites[id].lay)
		var errs: Array = t.validate()
		assert_eq(errs.size(), 0, "%s: %s" % [id, str(errs.slice(0, 3))])


func test_the_people_are_each_place_s_own_folk() -> void:
	for id in sites:
		var folk := str(sites[id].place.folk)
		for sid in SettlementGen.soldiers(sites[id].lay):
			if str(sid).ends_with("_dancer"):
				continue                     # the stage's dancer is the town kit's own
			assert_true(str(sid).begins_with(folk + "_"), "%s: %s is %s folk" % [id, sid, folk])
			assert_true(FileAccess.file_exists("res://content/core/soldiers/%s.json" % sid), sid + " has a profile")
		for m in sites[id].lay.markers:
			assert_ne(str(m.get("role", "")), "trooper_post", "%s: no Remnant post up here" % id)


func test_each_town_has_its_cantina_barkeep_and_stall() -> void:
	for id in sites:
		var lay: Dictionary = sites[id].lay
		var ids: Array = lay.boxes.map(func(b): return str(b.id))
		assert_true(lay.boxes.any(func(b): return str(b.get("look", "")) == "stall"), id + " has a stall")
		if str(sites[id].place.kind) == "ledge":
			assert_true(ids.has("shrine") and ids.has("watch"), id + ": a shrine and a watch tower")
			continue
		assert_true(ids.has("cantina_roof") and ids.has("bar_counter"), id + " has a cantina")
		var keep: Array = lay.markers.filter(func(m): return str(m.get("soldier", "")).ends_with("_barkeep"))
		assert_eq(keep.size(), 1, id + " has its barkeep")
		assert_gte(lay.boxes.filter(func(b): return str(b.get("look", "")).begins_with("hut_") or str(b.get("look", "")).begins_with("tower_")).size(), 4, id + ": homes")


func test_sootwell_has_a_dancer_on_its_stage() -> void:
	var lay: Dictionary = sites.sootwell.lay
	assert_true(lay.markers.any(func(m): return str(m.id).contains("dancer")), "the mining town's stage has its dancer")


func test_every_town_fits_on_its_top() -> void:
	for id in sites:
		var s: Dictionary = sites[id]
		var top: Dictionary = (s.plan.tiers as Array)[-1]
		var least := INF
		for i in 72:
			least = minf(least, RockMountain.wall(top, TAU * float(i) / 72.0, float(s.height)))
		assert_lt(SettlementGen.fit(s.lay), least - 2.0, "%s fits on its top (%.1f m in a %.1f m top)" % [id, SettlementGen.fit(s.lay), least])


func test_the_lift_stands_clear_and_its_bridge_reaches_the_town() -> void:
	var lifts := 0
	for id in sites:
		var s: Dictionary = sites[id]
		if not s.has("lift"):
			continue
		lifts += 1
		var l: Dictionary = s.lift
		var foot: Dictionary = (s.plan.tiers as Array)[0]
		var most := 0.0
		for i in 9:
			most = maxf(most, RockMountain._lobed(foot, deg_to_rad(-8.0 + 2.0 * i)))
		assert_gt(float(l.x) - float(st.lift.car_radius) - 0.35, most + 2.0, id + ": the tube stands off the rock")
		assert_gt(float(l.top) - float(l.bottom), 20.0, id + ": a real ride")
		var apron := float(s.lay.bounds.max[0]) - float(s.centre.x)
		assert_lte(float(l.deck[0]), apron, id + ": the bridge reaches the apron")
	assert_eq(lifts, 2)


func test_the_road_curls_up_once_round_its_peak_clear_of_the_rock() -> void:
	var s: Dictionary = sites.sootwell
	var rp: Dictionary = s.ramp
	assert_lt(-float(rp.start_angle), TAU - 0.3, "once round: it never runs over itself")
	assert_gt(float(rp.radius) - float(rp.width) * 0.5, float(s.plan.radius) + 5.0, "its inner kerb clear of the foot")
	var segs: Array = rp.segments
	for i in range(1, segs.size()):
		assert_almost_eq(float(segs[i].y0), float(segs[i - 1].y1), 0.01, "no step between pieces")
	assert_almost_eq(float(segs[-1].y1), float(s.height), 0.01, "it ends at the top")
	assert_true(segs[-1].mouth, "the bridge turns in where it ends")
	assert_false(segs[0].mouth)
	for sg in segs:
		var grade := (float(sg.y1) - float(sg.y0)) / float(sg.len)
		assert_lt(grade, 0.13, "a speeder's climb")


func test_every_place_has_its_pin() -> void:
	var pins := GlobeMap.settlement_pins(planet)
	assert_eq(pins.size(), 7)
	for p in pins:
		assert_eq(str(p.kind), "village")
		var id := str(p.id).trim_prefix("settlement_")
		assert_lt(sp.ground_dist(p.map, sites[id].map), 1.0, id + ": its pin is on its peak")
