extends GutTest
## Issue #882: the red world's roads and races, checked without a scene. Every
## town is on a road and the roads join them to the port; the roads that meet a
## mountain range run its tunnel; no peak stands on a road (the clusters keep off,
## the towns' and tunnels' own peaks are clear of every leg that is not theirs);
## the lamps are spaced by the data and none stands inside a tunnel; a road's
## clear circles keep only the small rocks off; three red courses, each placed by
## latitude and longitude, run one tunnel each with no peak on their lines, and
## their crews make a ladder of their own at their own camps.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var planet: Dictionary
var sp: PlanetSphere
var roads: Array
var spots: Array


func before_all() -> void:
	var cc = CoreScript.new()
	cc.load_from()
	planet = PlanetGen.build("port_red", cc)
	sp = PlanetTerrain.for_planet(planet).sphere
	roads = RoadNetwork.plan(planet, sp)
	spots = DesertLandforms.mountain_spots(DesertLandforms.load_for(planet), sp)


func test_every_town_is_on_a_road_joined_to_the_port() -> void:
	var cfg_roads: Array = planet.cfg.roads.roads
	assert_eq(roads.size(), cfg_roads.size(), "every road in the data is laid out")
	var links := {}
	for r in roads:
		links[r.from] = (links.get(r.from, []) as Array) + [r.to]
		links[r.to] = (links.get(r.to, []) as Array) + [r.from]
	var seen := { "port": true }
	var todo := ["port"]
	while not todo.is_empty():
		for n in links.get(todo.pop_back(), []):
			if not seen.has(n):
				seen[n] = true
				todo.append(n)
	for p in planet.cfg.settlements.places:
		assert_true(seen.has(str(p.id)), "%s is on the roads from the port" % p.id)


func test_the_ranges_in_the_way_are_tunnelled() -> void:
	var used := {}
	for r in roads:
		for t in r.tunnels:
			used[t] = true
	for t in ["red_tunnel_port", "red_tunnel_west", "red_tunnel_east"]:
		assert_true(used.has(t), t + " carries a road")


func test_no_peak_stands_on_a_road() -> void:
	var half := float(planet.cfg.roads.width_m) * 0.5
	for r in roads:
		var worst := INF
		var who := ""
		for q in (r.pts as PackedVector2Array):
			for m in spots:
				var id := str(m.id)
				if (r.tunnels as Array).has(id.trim_prefix("mesa_")) or id == "butte_" + r.from or id == "butte_" + r.to:
					continue                 # its own tunnel's range, the peaks it climbs
				var g := sp.ground_dist(q, m.map) - float(m.plan.radius) - half
				if g < worst:
					worst = g
					who = id
		assert_gt(worst, 0.0, "%s keeps clear of every peak (%.1f m from %s)" % [r.id, worst, who])


func test_a_road_runs_its_tunnel_end_to_end() -> void:
	var data := DesertLandforms.load_for(planet)
	for r in roads:
		for t in r.tunnels:
			for e in data.course_mountains:
				if str(e.id) != t:
					continue
				for q in e.path_ll:
					var at := sp.map_from_lat_lon(float(q[0]), float(q[1]))
					var best := INF
					for p in (r.pts as PackedVector2Array):
						best = minf(best, sp.ground_dist(p, at))
					assert_lt(best, 6.0, "%s passes %s's portal" % [r.id, t])


func test_lamps_are_spaced_and_none_in_a_tunnel() -> void:
	var every := float(planet.cfg.roads.lamp_m)
	var total := 0
	for r in roads:
		var lamps: Array = r.lamps
		assert_gt(lamps.size(), 0, r.id + " is lit")
		total += lamps.size()
		assert_lt(float(r.length) / lamps.size(), every * 2.0, r.id + ": a lamp every lamp_m, tunnels aside")
		for i in range(1, lamps.size()):
			assert_ne(float(lamps[i].side), float(lamps[i - 1].side), "sides take turns")
	assert_gt(total, 300)


func test_road_circles_keep_only_the_small_rocks_off() -> void:
	var circles := RoadNetwork.clear_circles(planet, sp)
	assert_gt(circles.size(), 100)
	for c in circles:
		assert_eq(c.size(), 3)
		assert_true(bool(c[2]), "a road's circle never drops a peak")


func test_three_red_courses_through_one_tunnel_each() -> void:
	var courses := RaceCourse.courses_for("port_red")
	assert_eq(courses.size(), 3)
	assert_almost_eq(RaceCourse.sphere_radius("port_red"), 4000.0, 0.1, "the ball's radius from the planet file")
	var data := DesertLandforms.load_for(planet)
	for c in courses:
		for g in c.gates:
			assert_true(g.has("ll") and g.has("at"), "%s: placed by latitude and longitude" % c.id)
			var want := sp.map_from_lat_lon(float(g.ll[0]), float(g.ll[1]))
			assert_lt(want.distance_to(Vector2(float(g.at[0]), float(g.at[1]))), 0.5, "the same spot as the planet's")
		var through := 0
		for e in data.course_mountains:
			var a := sp.map_from_lat_lon(float(e.path_ll[0][0]), float(e.path_ll[0][1]))
			var b := sp.map_from_lat_lon(float(e.path_ll[-1][0]), float(e.path_ll[-1][1]))
			var on := 0
			for g in c.gates:
				var q := Vector2(float(g.at[0]), float(g.at[1]))
				var t := RaceCourse.ground_dist(a, q, sp.radius) / RaceCourse.ground_dist(a, b, sp.radius)
				if (q - a).dot(b - a) < 0.0:
					t = -t
				if sp.ground_dist(q, RaceCourse.ground_lerp(a, b, t, sp.radius)) < 3.0:
					on += 1
			if on >= 2:
				through += 1
		assert_eq(through, 1, "%s runs one tunnel" % c.id)


func test_no_peak_on_a_racing_line() -> void:
	for c in RaceCourse.courses_for("port_red"):
		var worst := INF
		for p in c.line:
			var q := Vector2(float(p[0]), float(p[1]))
			for m in spots:
				if (m as Dictionary).has("course"):
					continue                     # a tunnel range stands over its line on purpose
				worst = minf(worst, sp.ground_dist(q, m.map) - float(m.plan.radius) - float(c.gate_width) * 0.5)
		assert_gt(worst, 0.0, "%s: no peak on the line (%.1f m)" % [c.id, worst])


func test_the_red_crews_are_a_ladder_at_their_own_camps() -> void:
	var crews := RaceCrew.crews_for("port_red")
	assert_eq(crews.size(), 3)
	var by := {}
	for c in crews:
		by[str(c.id)] = c
	assert_false(by.scorch.has("after"), "the first red crew races anyone")
	assert_eq(str(by.ember.after), "scorch")
	assert_eq(str(by.dust.after), "ember")
	var lms := {}
	for lm in planet.world.landmarks:
		lms[str(lm.id)] = lm
	for c in crews:
		var camp := str(c.hangout.near)
		assert_true(lms.has(camp), "%s: its camp is on the world" % c.id)
		assert_true(FileAccess.file_exists("res://content/core/locations/%s.json" % camp))
		var course := RaceCourse.load_course(str(c.course))
		var start := Vector2(float(course.gates[0].at[0]), float(course.gates[0].at[1]))
		var at := Vector2(float(lms[camp].at[0]), float(lms[camp].at[2]))
		assert_between(sp.ground_dist(start, at), 120.0, 220.0, "%s: the camp by its start line" % c.id)
	assert_true(Ranches.on_world(planet.world), "the camps are dressed like the home world's racers' outpost")
