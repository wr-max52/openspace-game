extends GutTest
## Issue #874: star systems are data (types.json space.systems, a planet's
## "system"), and the warp drive is an unlock upgrade (t89.json "warp").

func before_each() -> void:
	WorldState.reset()
	GameFlow.reset()


func test_two_systems_each_with_its_own_sun_and_main_world() -> void:
	var ids := PlanetGen.system_ids()
	assert_true(ids.has("home"))
	assert_true(ids.has("red_reach"))
	assert_false(ids.has("note"), "the note is not a system")
	assert_eq(PlanetGen.main_planet("home"), "port_desert")
	assert_eq(PlanetGen.main_planet("red_reach"), "port_red")
	assert_ne(PlanetGen.sun_id("home"), PlanetGen.sun_id("red_reach"))


func test_every_planet_has_a_system() -> void:
	assert_eq(PlanetGen.system_of("port_desert"), "home")
	assert_eq(PlanetGen.system_of("grit_station"), "home", "a moon is in its planet's system")
	assert_eq(PlanetGen.system_of("cinder_station"), "home")
	assert_eq(PlanetGen.system_of("port_red"), "red_reach")


func test_another_system_never_hangs_in_a_sky() -> void:
	var home: Array = PlanetGen.build("port_desert").neighbours.map(func(n): return str(n.id))
	assert_false(home.has("port_red"))
	var red: Array = PlanetGen.build("port_red").neighbours.map(func(n): return str(n.id))
	assert_false(red.has("port_desert"))
	assert_false(red.has("grit_station"))


func test_open_space_is_the_current_systems() -> void:
	GameFlow.planet_id = PlanetGen.open_space_id()
	WorldState.system = "red_reach"
	assert_eq(PlanetGen.current_system(), "red_reach")
	var ids: Array = PlanetGen.build(PlanetGen.open_space_id()).neighbours.map(func(n): return str(n.id))
	assert_eq(ids, ["port_red"])
	WorldState.system = "home"
	ids = PlanetGen.build(PlanetGen.open_space_id()).neighbours.map(func(n): return str(n.id))
	assert_true(ids.has("port_desert"))
	assert_false(ids.has("port_red"))


func test_landing_puts_you_in_that_planets_system() -> void:
	GameFlow.change_scene = func(_p: String) -> void: pass
	GameFlow.travel(null, "port_red")
	assert_eq(str(WorldState.system), "red_reach")
	GameFlow.travel(null, "grit_station")
	assert_eq(str(WorldState.system), "home")
	GameFlow.reset()


func test_the_system_is_saved() -> void:
	WorldState.system = "red_reach"
	var d := WorldState.to_save()
	WorldState.reset()
	assert_eq(str(WorldState.system), "home")
	WorldState.from_save(d)
	assert_eq(str(WorldState.system), "red_reach")
	WorldState.from_save({})
	assert_eq(str(WorldState.system), "home", "an old save is in the home system")


func test_the_warp_drive_is_an_unlock_upgrade() -> void:
	assert_eq(ShipUpgrades.price("warp"), 10000)
	assert_true(ShipUpgrades.ids().has("warp"), "T-89 sells it with the others")
	assert_false(ShipUpgrades.unlocked("interceptor", "warp"))
	assert_true(ShipUpgrades.fit("interceptor", "warp"))
	assert_true(ShipUpgrades.unlocked("interceptor", "warp"))
	assert_false(ShipUpgrades.unlocked("courier", "warp"), "once per ship")
	var cfg := { "hull": 100.0 }
	assert_eq(ShipUpgrades.apply(cfg, "interceptor").get("hull"), 100.0, "it multiplies nothing")


func test_a_warp_drops_you_outside_the_main_worlds_bubble() -> void:
	var a := WarpDrive.arrival("red_reach")
	var c = PlanetGen.system_centre("port_red")
	var gap: float = (a.position as Vector3).distance_to(c) - PlanetGen.bubble_radius("port_red", true)
	assert_gt(gap, 1000.0, "outside the bubble, or its scene would take over at once")
	assert_gt((-(a.basis as Basis).z).dot(((c as Vector3) - a.position).normalized()), 0.9, "nose on it")


func test_the_key_is_bound() -> void:
	assert_true(InputMap.has_action("flight_warp"))
