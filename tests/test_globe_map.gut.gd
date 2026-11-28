extends GutTest
## The F11 Map page: the places that stay put on the home planet, the places off
## it, and the waypoint the objective pointer follows.


func before_each() -> void:
	WorldState.reset()
	GameFlow.reset()


func after_all() -> void:
	WorldState.reset()
	GameFlow.reset()


func _home() -> Dictionary:
	return PlanetGen.build(PlanetGen.home_id())


func _by_id(pins: Array) -> Dictionary:
	var out := {}
	for p in pins:
		out[str(p.id)] = p
	return out


func test_pins_are_the_places_that_stay_put() -> void:
	var home := _home()
	var pins := _by_id(GlobeMap.pins(home.world, home))
	assert_true(pins.has("port"), "the port itself")
	for id in ["remnant_outpost_near", "droid_post_wash", "mechanic_yard", "skrugs_post", "starcruiser_wreck", "outpost"]:
		assert_true(pins.has(id), "on the map: " + id)
	assert_eq(str(pins.droid_post_wash.kind), "droid_merchant_outpost")
	assert_eq(str(pins.droid_post_wash.label), "Drywash Droid Relay", "a location's own name")
	assert_eq(str(pins.remnant_outpost_near.label), "The dry wash outpost")
	assert_eq(str(pins.skrugs_post.label), "Speeder stall", "the data's label wins")
	assert_false(pins.has("skrugs_ramp"), "skipped")
	assert_false(pins.has("remnant_cruiser"), "the cruiser is off planet, not on the ground")
	var camps := pins.keys().filter(func(k): return str(k).begins_with("camp_"))
	assert_eq(camps.size(), 2, "each native pack's camp")
	assert_true(pins.camp_bone_teeth.hostile)
	assert_eq(pins.camp_bone_teeth.map, Vector2(3800, -6582), "where the planet's data puts it")


func test_off_planet_lists_planets_and_every_cruiser() -> void:
	var off := GlobeMap.off_planet([{ "id": "grit_station", "name": "Grit Station" }])
	var cruisers := GlobeMap.system_cruisers()
	assert_eq(cruisers.size(), 2, "the home cruiser and the belt one")
	assert_eq(off.size(), 1 + cruisers.size() + GlobeMap.system_stations().size(), "and every station after them")
	assert_eq(str(off[0].label), "Grit Station")
	assert_eq(str(off[0].target), "planet:grit_station")
	assert_eq(str(off[1].target), "cruiser")
	assert_eq(str(off[1].planet), PlanetGen.home_id(), "the home planet's first")
	assert_ne(str(off[2].planet), str(off[1].planet), "each over its own planet")


func test_map_dir_matches_the_ball() -> void:
	var sphere := PlanetSphere.new(5000.0)
	for m in [Vector2.ZERO, Vector2(1000, -600), Vector2(-7650, 420)]:
		assert_almost_eq(GlobeMap.dir(m, 5000.0), sphere.map_dir(m.x, m.y), Vector3.ONE * 0.0001)
		assert_almost_eq(GlobeMap.dir_map(GlobeMap.dir(m, 5000.0), 5000.0), m, Vector2.ONE * 0.01)


func test_waypoint_drives_the_objective_and_saves() -> void:
	var home := _home()
	var pin: Dictionary = _by_id(GlobeMap.pins(home.world, home)).droid_post_wash
	GlobeMap.set_waypoint(pin, PlanetGen.home_id())
	var o := Objective.current()
	assert_eq(str(o.text), "Waypoint: Drywash Droid Relay")
	var at: Vector2 = pin.map
	assert_eq(str(o.target), "map:%.1f,%.1f" % [at.x, at.y])
	var saved := WorldState.to_save()
	WorldState.reset()
	assert_eq(GlobeMap.waypoint_id(), "", "reset clears it")
	WorldState.from_save(saved)
	assert_eq(GlobeMap.waypoint_id(), "droid_post_wash", "kept in the save")


func test_one_pointer_at_a_time() -> void:
	var q: Dictionary = Quests.all()[0] if not Quests.all().is_empty() else {}
	if q.is_empty() or str(q.get("target", "")) == "":
		pass_test("no quest with a target to try")
		return
	Quests.unlock(str(q.id))
	assert_true(Quests.toggle_waypoint(str(q.id)))
	GlobeMap.set_waypoint(GlobeMap.spot_pin(Vector2(10, 20)), PlanetGen.home_id())
	assert_false(bool(WorldState.quests[str(q.id)].waypoint), "the map's waypoint turns the quest's off")
	assert_true(Quests.toggle_waypoint(str(q.id)))
	assert_eq(GlobeMap.waypoint_id(), "", "and a quest's turns the map's off")


func test_planet_waypoint_clears_on_arrival() -> void:
	GlobeMap.set_waypoint({ "id": "planet_grit_station", "label": "Grit Station", "kind": "planet",
		"target": "planet:grit_station" }, PlanetGen.home_id())
	assert_eq(str(GlobeMap.waypoint().target), "planet:grit_station")
	GameFlow.planet_id = "grit_station"
	assert_true(GlobeMap.waypoint().is_empty(), "there: done")
	assert_eq(GlobeMap.waypoint_id(), "")


func test_surface_waypoint_only_on_its_planet() -> void:
	GlobeMap.set_waypoint(GlobeMap.spot_pin(Vector2(10, 20)), PlanetGen.home_id())
	# Off its planet the pointer leads to that planet first and does not clear on
	# the way (GlobeMap.waypoint: arrive -1); on it, to the spot.
	GameFlow.planet_id = "grit_station"
	var w := GlobeMap.waypoint()
	assert_eq(str(w.get("target", "")), "planet:" + PlanetGen.home_id(), "leads home first")
	assert_eq(float(w.get("arrive", 0.0)), -1.0)
	GameFlow.planet_id = PlanetGen.home_id()
	assert_true(str(GlobeMap.waypoint().get("target", "")).begins_with("map:"), "then to the spot")


func test_zoom_buttons_zoom_the_globe() -> void:
	var g := GlobeView.new()
	add_child_autofree(g)
	var zin: Button = g.find_child("ZoomIn", true, false)
	var zout: Button = g.find_child("ZoomOut", true, false)
	assert_not_null(zin)
	assert_not_null(zout)
	zin.pressed.emit()
	assert_almost_eq(g.zoom, GlobeView.BUTTON_STEP, 0.001)
	zout.pressed.emit()
	zout.pressed.emit()
	assert_almost_eq(g.zoom, GlobeView.ZOOM_MIN, 0.001, "never past all the way out")


func test_off_planet_kinds_have_icons() -> void:
	var pins: Dictionary = GlobeMap.look().get("pins", {})
	for kind in ["planet", "cruiser"]:
		assert_true(pins.has(kind), "an icon for " + kind)


func test_pins_say_who_holds_the_outposts_and_the_port() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	var home := _home()
	var pins := _by_id(GlobeMap.pins(home.world, home))
	assert_eq(str(pins.remnant_outpost_near.owner), Territory.REMNANT, "the Remnant's to start")
	assert_eq(str(pins.port.owner), Territory.REMNANT)
	assert_eq(GlobeView.pin_look(pins.remnant_outpost_near).color, GlobeMap.look().roles.hostile, "not recoloured: the Remnant's red")
	assert_false(pins.droid_post_wash.has("owner"), "only what Territory holds")
	Territory.take("remnant_outpost_near")
	pins = _by_id(GlobeMap.pins(home.world, home))
	var near: Dictionary = pins.remnant_outpost_near
	assert_eq(str(near.owner), Territory.LOCALS)
	assert_eq(GlobeView.pin_look(near).color, GlobeMap.look().owners.locals, "green when the locals hold it")
	assert_string_contains(str(near.status), "Held by the locals")
	assert_almost_eq(float(near.hold), 1.0, 0.001, "a full ring on a fresh hold")
	assert_eq(float(pins.remnant_outpost_mid.hold), -1.0, "no clock on the Remnant's")
	assert_eq(str(pins.remnant_outpost_mid.owner), Territory.REMNANT, "the others stay")


func test_a_short_hold_shows_and_the_town_goes_green() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	var home := _home()
	Territory.take("remnant_outpost_near")
	Territory.tick(Territory.n("hold_s", 900.0) - Territory.n("supply_warn_s", 420.0) + 1.0)
	var pins := _by_id(GlobeMap.pins(home.world, home))
	assert_false(pins.remnant_outpost_near.short, "not shown until you take the supply job")
	assert_false(str(pins.remnant_outpost_near.status).contains("Resupply needed"))
	assert_true(WorldState.accept_job(Territory.SUPPLY_JOB))
	pins = _by_id(GlobeMap.pins(home.world, home))
	assert_true(pins.remnant_outpost_near.short)
	assert_eq(GlobeView.pin_look(pins.remnant_outpost_near).color, GlobeMap.look().owners.short)
	assert_string_contains(str(pins.remnant_outpost_near.status), "Resupply needed")
	assert_between(float(pins.remnant_outpost_near.hold), 0.0, 0.5, "the ring has drained past half")
	WorldState.set_flag("remnant_fleet_beaten")
	pins = _by_id(GlobeMap.pins(home.world, home))
	assert_eq(str(pins.port.owner), Territory.LOCALS, "the barracks are the locals' once the fleet is beaten")
	assert_eq(GlobeView.pin_look(pins.port).color, GlobeMap.look().owners.locals)


## Issue #712: the ringed giant's globe pins its ring station (in place of the
## port, since the giant's town is the station's bay), and the station's places
## are waypoints the objective pointer follows ("station:<place>").
func test_ringed_giant_pins_its_ring_station() -> void:
	var giant := PlanetGen.build("ringed_giant")
	var all_pins: Array = GlobeMap.pins(giant.world, giant)
	var stations: Array = all_pins.filter(func(p): return str(p.kind) == "station")
	assert_eq(stations.size(), 1, "one pin for the ring station")
	# Issue #838: the skimmer outposts are stations too, but pinned as the Remnant's
	# outposts, each saying who holds its deck.
	var posts: Array = all_pins.filter(func(p): return str(p.id).begins_with("station_skimmer_"))
	assert_eq(posts.size(), 3, "a pin for each skimmer outpost")
	for p in posts:
		assert_eq(str(p.kind), "remnant_outpost", "%s pinned as an outpost" % p.id)
		assert_eq(str(p.owner), Territory.REMNANT, "%s the Remnant's" % p.id)
		assert_ne(str(p.label), "", "%s has its name" % p.id)
	WorldState.control["station_skimmer_east"] = { "owner": Territory.LOCALS }
	var east: Array = GlobeMap.pins(giant.world, giant).filter(func(p): return str(p.id) == "station_skimmer_east")
	assert_eq(str(east[0].owner) if not east.is_empty() else "", Territory.LOCALS, "taken, its pin says the locals")
	WorldState.control.erase("station_skimmer_east")
	if stations.is_empty():
		return
	assert_eq(str(stations[0].view), "station:ringed_giant", "clicking it opens the station's side view")
	assert_eq(str(stations[0].get("owner", "")), Territory.REMNANT, "the station's pin says who holds its deck")
	Territory.take_station("station_orbital_station", "Test Station")
	var taken: Array = GlobeMap.pins(giant.world, giant).filter(func(p): return str(p.kind) == "station")
	assert_eq(str(taken[0].owner), Territory.LOCALS, "taken, the station's pin says the locals")
	assert_ne(str(taken[0].status), "", "with the map's line under its name")
	assert_ne(str(stations[0].label), "", "it has a name")
	var st: Dictionary = {}
	for s in GlobeMap.system_stations():
		if str(s.planet) == "ringed_giant":
			st = s
	assert_false(st.is_empty(), "the system chart knows the station too")
	var places := _by_id(GlobeMap.orbital_pins(st))
	assert_true(places.has("station_bay"), "the side view has the landing bay")
	if not places.has("station_bay"):
		return
	GlobeMap.set_waypoint(places.station_bay, "ringed_giant")
	assert_eq(str(WorldState.map_waypoint.planet), "ringed_giant")
	assert_eq(str(GlobeMap.waypoint().target), "planet:ringed_giant", "from home the pointer leads to the giant first")
	GameFlow.planet_id = "ringed_giant"
	assert_eq(str(GlobeMap.waypoint().target), "station:bay", "then, in its sky, to the station's bay")
