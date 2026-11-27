extends GutTest
## Issue #327: the belt cruiser, a second Remnant star cruiser by the ringed giant's
## space station. The same ship as the home one from its own config; where it hangs;
## taken on its own (its flag, saved with the world) without touching the home
## cruiser or the story; its pointer; and the bridge's holo of the whole system.

const BELT := "belt_cruiser"


func before_each() -> void:
	WorldState.new_game(WorldState.STORY)


func after_each() -> void:
	GameFlow.planet_id = ""
	WorldState.reset()


func _cruiser(cfg_id: String) -> RemnantCruiser:
	var c := RemnantCruiser.new()
	c.cfg_id = cfg_id
	c.cfg = CruiserHull.data_for(cfg_id)
	autofree(c)
	return c


func _giant() -> Dictionary:
	return PlanetGen.build("ringed_giant").get("world", {})


func _belt_landmark() -> Dictionary:
	for lm in CruiserHull.landmarks(_giant()):
		if CruiserHull.config_id(lm) == BELT:
			return lm
	return {}


func test_the_same_cruiser_from_its_own_config() -> void:
	var home := CruiserHull.data()
	var belt := CruiserHull.data_for(BELT)
	assert_eq(str(belt.id), BELT)
	assert_eq(str(belt.flag), "belt_cruiser_taken")
	assert_false(belt.has("base"))
	for k in ["pads", "dock", "crew", "droids", "general", "escort"]:
		assert_eq(belt[k], home[k], "%s is the home cruiser's" % k)
	assert_eq(str(belt.holo.kind), "system", "its holo shows the whole system")
	assert_eq(belt.lines.dock_hint, home.lines.dock_hint, "lines it does not list are the home one's")


func test_it_holds_station_by_the_station_its_bay_toward_it() -> void:
	var lm := _belt_landmark()
	assert_false(lm.is_empty(), "the ringed giant lists the belt cruiser")
	var sp := PlanetSphere.new(3500.0)
	var xf := CruiserHull.frame_for(sp, lm)
	var slm: Dictionary = StationHull.landmarks(_giant())[0]
	var st := StationHull.for_id(str(slm.station)).frame_for(sp, slm, _giant())
	var d := xf.origin.distance_to(st.origin)
	assert_between(d, 3800.0, 5500.0, "4 to 5 km from the station")
	assert_gt(xf.origin.y, st.origin.y, "over the station's deck line: seen from the bay and the windows")
	var to_station := Vector3(st.origin.x - xf.origin.x, 0.0, st.origin.z - xf.origin.z).normalized()
	assert_gt(xf.basis.x.dot(to_station), 0.95, "its bay turned toward the station")
	assert_gt(sp.altitude(xf.origin), 2000.0, "past this sky's edge of space")


func test_taking_it_takes_it_alone_and_survives_a_reload() -> void:
	var home := _cruiser(CruiserHull.HOME_ID)
	var belt := _cruiser(BELT)
	var chapter := Story.chapter()
	var credits := WorldState.credits
	var locals := int(WorldState.standing.get("locals", 0))
	var paid := WorldState.on_cruiser_taken("General Test", belt.cfg.reward, belt.line("event_taken"), belt.flag())
	assert_eq(paid, int(belt.cfg.reward.credits), "its own reward")
	assert_eq(WorldState.credits, credits + paid)
	assert_true(belt.taken(), "the belt cruiser is taken")
	assert_true(WorldState.has_flag("belt_cruiser_taken"))
	assert_false(Story.cruiser_taken(), "the story's cruiser is not")
	assert_false(home.taken(), "the home cruiser still has its crew")
	assert_eq(Story.chapter(), chapter, "the story is untouched")
	assert_false(WorldState.has_flag("locals_hero"), "the port's love is untouched")
	assert_eq(int(WorldState.standing.get("locals", 0)), locals)
	assert_eq(WorldState.on_cruiser_taken("General Test", belt.cfg.reward, "", belt.flag()), 0, "never paid twice")
	WorldState.from_save(WorldState.to_save())
	assert_true(belt.taken(), "reloaded: the belt cruiser is empty")
	assert_false(home.taken(), "and the home one is not")


func test_taking_the_home_cruiser_leaves_the_belt_one_crewed() -> void:
	Story.skip_to("fleet")
	var belt := _cruiser(BELT)
	WorldState.on_cruiser_taken("General Test", CruiserHull.data().reward)
	assert_true(Story.cruiser_taken())
	assert_false(belt.taken(), "the belt cruiser keeps its crew")
	WorldState.from_save(WorldState.to_save())
	assert_false(belt.taken())


func test_at_the_station_the_pointer_is_its_bay_then_its_general() -> void:
	GameFlow.planet_id = "ringed_giant"
	assert_eq(str(Objective.other_cruiser().get("target", "")), "cruiser:bay")
	WorldState.set_flag(BELT + "_boarded")
	assert_eq(str(Objective.other_cruiser().get("target", "")), "cruiser:general")
	WorldState.set_flag("belt_cruiser_taken")
	assert_true(Objective.other_cruiser().is_empty(), "nothing once it is taken")
	GameFlow.planet_id = ""
	WorldState.set_flag("belt_cruiser_taken", false)
	assert_true(Objective.other_cruiser().is_empty(), "at home the story points at the home cruiser")


func _system_holo() -> CruiserHolo:
	var sp := PlanetSphere.new(3500.0)
	var xf := CruiserHull.frame_for(sp, _belt_landmark())
	var slm: Dictionary = StationHull.landmarks(_giant())[0]
	var hull := StationHull.for_id(str(slm.station))
	var stations := [{ "id": Territory.STATION + str(slm.id), "hull": hull, "frame": hull.frame_for(sp, slm, _giant()),
		"name": "Test Station" }]
	var moons: Array = []
	for n in PlanetGen.neighbours("ringed_giant"):
		var m: Dictionary = n.duplicate()
		m["name"] = "Test Moon"
		moons.append(m)
	var h := CruiserHolo.new()
	var spec: Dictionary = CruiserHull.data_for(BELT).holo
	h.setup_system(spec, sp, PlanetGen.build("ringed_giant").cfg.get("body", {}), xf, Vector3.ZERO, stations, moons,
		{ "cruiser": "Test" }, str(CruiserHull.data_for(BELT).flag))
	add_child_autofree(h)
	return h


func test_its_holo_shows_the_giant_its_ring_and_what_orbits_it() -> void:
	var h := _system_holo()
	var spec: Dictionary = CruiserHull.data_for(BELT).holo
	var turn := h.get_node("Turn")
	assert_not_null(turn.get_node_or_null("Planet"), "the giant")
	assert_not_null(turn.get_node_or_null("Ring"), "its ring")
	assert_eq((turn.get_node("Rocks") as MultiMeshInstance3D).multimesh.instance_count, int(spec.rocks), "the ring's rocks")
	assert_not_null(turn.get_node_or_null("Station_station_orbital_station"), "the station")
	assert_not_null(turn.get_node_or_null("Cruiser"), "the cruiser")
	var moon := turn.get_node_or_null("Moon_cinder_station") as Node3D
	assert_not_null(moon, "the lava moon, the giant's moon")
	assert_null(turn.get_node_or_null("Moon_grit_station"), "not the home planet's moon")
	assert_gt(moon.position.length(), float(spec.radius) * 2.5, "the moon outside the ring")
	for id in Territory.outposts("lava_moon"):
		assert_true(h.places.has(id), "%s pinned on the moon" % id)
	assert_true(h.places.has(Territory.barracks_of("lava_moon")), "the moon's barracks")
	assert_true(h.places.has("station_orbital_station"), "the station's barracks")
	assert_true(h.places.has(CruiserHolo.CRUISER), "the cruiser")


func test_its_holo_says_who_holds_each() -> void:
	var h := _system_holo()
	var cruiser: Label3D = h.places[CruiserHolo.CRUISER].label
	var station: Label3D = h.places["station_orbital_station"].label
	var moon := h.get_node("Turn/Moon_cinder_station").get_meta("label") as Label3D
	assert_string_contains(cruiser.text, "Remnant")
	assert_string_contains(station.text, "Barracks: Remnant")
	assert_string_contains(moon.text, "5 Remnant, 0 Locals")
	WorldState.set_flag("belt_cruiser_taken")
	Territory.take_station("station_orbital_station", "Test Station")
	WorldState.control["remnant_outpost_lava_glow"] = { "owner": Territory.LOCALS }
	h.refresh_owners()
	assert_string_contains(cruiser.text, "Empty", "the cruiser is empty once taken")
	assert_string_contains(station.text, "Barracks: Locals")
	assert_string_contains(moon.text, "4 Remnant, 1 Locals")
	assert_eq(h.owner_color("remnant_outpost_lava_glow"), Color(str(h.spec.owner_colors.locals)))


func test_its_escort_meets_you_flying_for_it_not_away() -> void:
	var sp := PlanetSphere.new(3500.0)
	var belt := _cruiser(BELT)
	belt.frame = CruiserHull.frame_for(sp, _belt_landmark())
	var slm: Dictionary = StationHull.landmarks(_giant())[0]
	var from := StationHull.for_id(str(slm.station)).frame_for(sp, slm, _giant()).origin + Vector3(0, 1800, 0)
	var toward := (belt.frame.origin - from).normalized()
	assert_true(belt.wants_escort(from, toward), "climbing out toward it")
	assert_false(belt.wants_escort(from, -toward), "leaving the other way")
	WorldState.set_flag("belt_cruiser_taken")
	assert_false(belt.wants_escort(from, toward), "nobody once it is taken")
