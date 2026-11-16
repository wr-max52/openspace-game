extends GutTest
## Issues #575 and #576: open space's cruise and the star system. Pure and
## headless: the courier flown straight across open space on the real flight model
## (AtmoFlight over open space's WorldGround), and the system frame as a tree
## (sun -> desert planet -> moon, sun -> ringed giant -> lava moon).

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownDemo := preload("res://scenes/town_demo.gd")
const DT := 1.0 / 60.0

var cc


func before_all() -> void:
	cc = CoreContent.new()
	cc.load_from()


func after_each() -> void:
	PlanetGen.clear_cache()


## Open space's ground: altitude, up and the bubbles, all planets in it.
func _void() -> WorldGround:
	var g := WorldGround.new()
	g.setup(PlanetGen.build(PlanetGen.open_space_id(), cc).world)
	return g


## A planet's centre in open space's frame.
func _centre(id: String) -> Vector3:
	return PlanetGen.system_centre(id, cc) - PlanetGen.system_port(PlanetGen.open_space_id(), cc)


## The ship flown straight from just outside `from`'s bubble (where its scene lets
## go) at the edge of space's speed, full throttle, no boost, until it crosses
## `to`'s bubble: { seconds, top, cross, edge } (m/s; edge is today's top out there).
func _leg(from: String, to: String, ship := "courier") -> Dictionary:
	var a := _centre(from)
	var b := _centre(to)
	var dir := (b - a).normalized()
	var atmo := AtmoFlight.new()
	atmo.setup(cc.get_ship(ship), _void())
	var edge := atmo.p("max_speed", 0.0) * atmo.p("edge_speed_mult", 1.0)
	atmo.place_flying(a + dir * (PlanetGen.bubble_radius(from, true, cc) + 1.0), dir, edge, 1.0)
	atmo.set_command(0.0, 0.0, 0.0, 1.0, false)
	var arrive := PlanetGen.bubble_radius(to, false, cc)
	var t := 0.0
	var top := 0.0
	while atmo.position().distance_to(b) > arrive and t < 600.0:
		atmo.step(DT)
		t += DT
		top = maxf(top, atmo.speed())
	return { "seconds": t, "top": top, "cross": atmo.speed(), "edge": edge }


# ---------------------------------------------------------------- #575 cruise

func test_cruise_speeds_up_between_planets_and_lets_go_before_the_next() -> void:
	var leg := _leg("grit_station", "ringed_giant")
	assert_gt(float(leg.top), float(leg.edge) * 1.5, "out in open space she goes well past today's top speed")
	assert_lte(float(leg.cross), float(leg.edge) + 0.5, "and crosses the giant's bubble no faster than today")


func test_cruise_eases_in_over_seconds() -> void:
	var g := _void()
	var atmo := AtmoFlight.new()
	atmo.setup(cc.get_ship("courier"), g)
	var a := _centre("port_desert")
	var dir := (_centre("ringed_giant") - a).normalized()
	atmo.place_flying(a + dir * (PlanetGen.bubble_radius("port_desert", true, cc) + 20000.0), dir, 588.0, 1.0)
	atmo.set_command(0.0, 0.0, 0.0, 1.0, false)
	atmo.step(DT)
	assert_lt(atmo.cruise, 1.1, "no jump: it starts from none, even far out")
	for i in int(atmo.cruise_ease_in / DT) + 2:
		atmo.step(DT)
	assert_almost_eq(atmo.cruise, atmo.p("cruise_mult", 1.0), 0.01, "full after cruise_ease_in seconds")
	assert_almost_eq(atmo.flight.turn_mult, atmo.p("cruise_turn_scale", 1.0), 0.01, "turning scaled down, from data")
	assert_almost_eq(atmo.cruise_k(), 1.0, 0.01)


func test_no_cruise_in_a_planets_scene() -> void:
	PlanetSphere.current = PlanetSphere.new(1500.0)
	var g := WorldGround.new()
	g.setup(PlanetGen.build("grit_station", cc).world)
	var atmo := AtmoFlight.new()
	atmo.setup(cc.get_ship("courier"), g)
	atmo.place_flying(Vector3(0, 1100.0, 0), Vector3.FORWARD, 400.0, 1.0)
	atmo.set_command(0.0, 0.0, 0.0, 1.0, false)
	var before := atmo.air_scale()
	for i in 300:
		atmo.step(DT)
	assert_eq(atmo.cruise, 1.0, "the top speed in any planet's scene is unchanged")
	assert_almost_eq(atmo.air_scale(), before, 0.05)
	assert_eq(atmo.flight.turn_mult, 1.0)


func test_slow_ships_catch_up() -> void:
	var fast := _leg("port_desert", "ringed_giant", "courier")
	var slow := _leg("port_desert", "ringed_giant", "freighter")
	var fast_edge := float(fast.edge)
	var slow_edge := float(slow.edge)
	assert_lt(float(slow.seconds) / float(fast.seconds), fast_edge / slow_edge * 0.8,
		"the freighter's trip is much closer to the courier's than their top speeds are")


# ---------------------------------------------------------------- #576 star system

func test_the_system_is_a_tree_round_the_sun() -> void:
	var sun := PlanetGen.system_sun(cc)
	assert_true(sun.is_finite(), "the home planet orbits the sun")
	assert_eq(str(cc.planets.port_desert.near), PlanetGen.sun_id())
	assert_eq(str(cc.planets.ringed_giant.near), PlanetGen.sun_id())
	assert_eq(str(cc.planets.grit_station.near), "port_desert", "the moon stays round the desert planet")
	assert_eq(str(cc.planets.cinder_station.near), "ringed_giant", "the lava moon orbits the giant")
	assert_eq(PlanetGen.system_centre("port_desert", cc), Vector3(0, -5000, 0), "home's port is still the frame's origin")
	assert_eq(PlanetGen.system_centre("ringed_giant", cc), sun + GameFlow.vec(cc.planets.ringed_giant.at))
	var giant_port: Vector3 = PlanetGen.system_port("ringed_giant", cc)
	assert_eq(PlanetGen.system_centre("cinder_station", cc), giant_port + GameFlow.vec(cc.planets.cinder_station.at), "a moon of a planet of the sun")
	var home_orbit := sun.distance_to(PlanetGen.system_centre("port_desert", cc))
	var giant_orbit := sun.distance_to(PlanetGen.system_centre("ringed_giant", cc))
	assert_gt(giant_orbit, home_orbit, "the giant orbits further out")
	assert_eq(PlanetGen.system_port(PlanetGen.open_space_id(), cc), sun, "open space's origin is the sun, the middle of the system")


func test_trip_lengths_are_in_their_bands() -> void:
	var trips: Dictionary = PlanetGen.space_cfg().get("trips", {})
	assert_false((trips.get("bands", []) as Array).is_empty(), "trip bands in data")
	for band in trips.get("bands", []):
		var s: Array = band.seconds
		for pair in [[band.from, band.to], [band.to, band.from]]:
			var leg := _leg(str(pair[0]), str(pair[1]), str(trips.get("ship", "courier")))
			gut.p("%s -> %s: %.1f s, top %.0f m/s" % [pair[0], pair[1], leg.seconds, leg.top])
			assert_between(float(leg.seconds), float(s[0]), float(s[1]), "%s -> %s" % pair)


func test_every_planet_shows_in_every_sky() -> void:
	for id in PlanetGen.ids(cc).filter(func(i): return PlanetGen.is_planet(str(i), cc)):
		var near: Array = PlanetGen.build(str(id), cc).neighbours
		assert_eq(near.size(), 3, str(id) + " sees the other three")
		var demo = TownDemo.new()
		demo.planet = PlanetGen.build(str(id), cc)
		for n in near:
			assert_gt(demo.sky_reach(), (n.at as Vector3).length() + float(n.radius), "%s whole in %s's view" % [n.id, id])
		demo.free()


func test_the_chart_centres_on_the_sun() -> void:
	var v := SystemView.new()
	v.size = Vector2(600, 600)
	v.bodies = GlobeMap.system()
	v.sun = PlanetGen.system_sun()
	v.reset()
	var c := v.home_pan()
	assert_almost_eq(c.x, v.sun.x, 1.0)
	assert_almost_eq(c.y, v.sun.z, 1.0)
	for b in v.bodies:
		var at := v.project(b.centre)
		assert_true(Rect2(Vector2.ZERO, v.size).has_point(at), str(b.id) + " on the chart")
	v.free()
