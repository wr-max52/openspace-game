extends GutTest
## Issue #876: the red system's ring station and cruiser, checked as data without a
## scene. The station is the home ring station's copy (the same towers, rooms, bay,
## pads, elevator, tunnels, owners and Remnant deck) that differs only in its look
## and its fill: darker metal, its own room colours and finishes. The cruiser is the
## belt cruiser's copy with its own flag and reward, and both hang in port_red's sky.

const StationFill := preload("res://src/systems/world/station_fill.gd")
const TownBuildings := preload("res://src/systems/world/town_buildings.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")

const SAME := ["segments", "floor_height", "plate", "gap_radius", "walkway", "shaft_radius", "towers", "crowd",
	"cantina", "drop_rooms", "remnant", "map", "droids", "rooms", "tunnel", "hatch", "floor_hatch", "tunnels",
	"elevator", "bay", "pads", "salesman", "dock", "outside"]


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func test_it_is_the_home_ring_station_built_again() -> void:
	var home := _json("res://content/core/stations/orbital_station.json")
	var dark := _json("res://content/core/stations/dark_station.json")
	assert_eq(str(dark.id), "dark_station")
	for k in SAME:
		assert_eq(JSON.stringify(dark.get(k)), JSON.stringify(home.get(k)), "%s is the home station's" % k)
	assert_false(dark.has("belt"), "no wreck belt: under it is the desert")
	var a := StationHull.for_id("dark_station")
	var b := StationHull.for_id("orbital_station")
	assert_not_null(a)
	assert_eq(a.dock_pad().at, b.dock_pad().at, "the same bay")
	assert_eq(a.ladders.size(), b.ladders.size(), "the same ladders")


func test_its_metal_is_darker() -> void:
	var look: Dictionary = _json("res://content/core/stations/dark_station.json").get("look", {})
	assert_false(look.is_empty(), "a look block")
	# The shader's own defaults (cruiser_metal.gdshader): hull 0.55..0.62, wall 0.40..0.45.
	assert_lt(Color(str(look.hull_color)).get_luminance(), Color(0.55, 0.58, 0.62).get_luminance() * 0.5, "the hull")
	assert_lt(Color(str(look.wall_color)).get_luminance(), Color(0.40, 0.42, 0.45).get_luminance() * 0.75, "the walls")
	assert_lt(Color(str(look.deck_color)).get_luminance(), Color(0.17, 0.18, 0.20).get_luminance(), "the decks")


func test_its_rooms_wear_its_own_colours() -> void:
	var kit := TownBuildings.new(LookMaterials.new(), null)
	var mat := func(_f: String) -> Material: return StandardMaterial3D.new()
	var dark = StationFill.new(kit, StationHull.for_id("dark_station"), mat)
	var home = StationFill.new(TownBuildings.new(LookMaterials.new(), null), StationHull.for_id("orbital_station"), mat)
	var dress: Dictionary = _json("res://content/core/stations/dark_station.json").fill.dressing
	assert_eq(dark._dc("gold", "#000000"), Color(str(dress.gold)), "its own brass")
	assert_ne(dark._dc("gold", "#000000"), home._dc("gold", "#000000"), "not the home station's")
	assert_eq(dark._dc("pond", "#000000"), Color(str(dress.pond)))
	assert_eq(home._dc("top_floor_bridge", "#000000"), Dressing.c("station_fill", "top_floor_bridge", "#000000"), "the home station keeps the shared palette")
	assert_eq(dark.paints[0], Color(str(dress.paints[0])), "its own paints")
	assert_eq(dark.neons.size(), (dress.neons as Array).size())
	assert_ne(dark.neons, home.neons, "its own neons")
	# A colour it does not name falls back to the shared palette.
	assert_eq(dark._dc("hazard", "#000000"), Dressing.c("station_fill", "hazard", "#000000"))
	var tops: Dictionary = _json("res://content/core/stations/dark_station.json").fill.top_floors
	assert_eq(str(tops.bridge), "marble", "its bridge floored in marble")
	for use in tops:
		assert_true(SpaceStation.FINISHES.has(str(tops[use])), "%s: %s is a station finish" % [use, tops[use]])


func test_every_floor_has_its_own_light_and_palette() -> void:
	var floors: Dictionary = _json("res://content/core/stations/dark_station.json").fill.floors
	for id in ["homes", "markets", "markets_2"]:
		assert_false((floors[id].get("paints", []) as Array).is_empty(), id + " paints")
		assert_false((floors[id].get("neons", []) as Array).is_empty(), id + " neons")
	for id in ["homes", "markets", "markets_2", "top", "engines"]:
		assert_true(floors[id].has("light"), id + " is lit its own way")


func test_both_hang_in_the_red_port_s_sky() -> void:
	var cc = CoreScript.new()
	cc.load_from()
	var planet := PlanetGen.build("port_red", cc)
	var lms: Array = planet.get("world", {}).get("landmarks", [])
	var st := lms.filter(func(l): return str(l.get("kind", "")) == "station")
	var cr := lms.filter(func(l): return str(l.get("kind", "")) == "cruiser")
	assert_eq(st.size(), 1)
	assert_eq(str(st[0].station), "dark_station")
	assert_eq(cr.size(), 1)
	assert_eq(str(cr[0].cruiser), "red_cruiser")
	assert_lt(float(st[0].altitude), float(planet.type_cfg.atmosphere.cloud_deck), "the station under the cloud deck")
	assert_lt(float(cr[0].altitude), float(planet.type_cfg.atmosphere.sky_black_at), "the cruiser in this sky")


func test_the_cruiser_is_its_own() -> void:
	var belt := _json("res://content/core/cruiser/belt_cruiser.json")
	var red := _json("res://content/core/cruiser/red_cruiser.json")
	assert_eq(str(red.base), str(belt.base), "the same ship")
	assert_eq(str(red.flag), "red_cruiser_taken")
	assert_ne(str(red.flag), str(belt.flag))
	assert_gt(int(red.reward.credits), 0, "its own reward")
	assert_true("red_cruiser" in _json("res://content/core/manifest.json").cruisers, "listed")
	assert_eq(CruiserHull.data_for("red_cruiser").get("flag"), "red_cruiser_taken", "read through its base")
	assert_false((CruiserHull.data_for("red_cruiser").get("crew", []) as Array).is_empty(), "the home ship's crew")
