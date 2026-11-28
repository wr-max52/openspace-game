extends GutTest
## Issue #317: three wrecked cruisers adrift in the belt under the ring station,
## end to end like stairs (BeltWrecks, the station's "belt" block). Every joint and
## the drop hatch are in the jetpack's reach, worked out from the jetpack's own
## numbers; the hatch is a hole in the engine deck; the station's up holds over
## them; each has the desert wrecks' crew (and more on its spine, the deeper the
## more), a crate that pays better the deeper it is and stray loot. With real
## physics: drop through the hatch to the first, step off its end down to the
## second and the third, jetpack back up every joint and in through the hatch;
## step off a side and the belt has you.

const TownDemo := preload("res://scenes/town_demo.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const Jetpack := preload("res://src/systems/player/jetpack.gd")
const ID := "orbital_station"
const HOST := "ringed_giant"
const WRECKS := ["belt_wreck_1", "belt_wreck_2", "belt_wreck_3"]

var _sphere_before: PlanetSphere


func before_each() -> void:
	WorldState.reset()
	_sphere_before = PlanetSphere.current


func after_each() -> void:
	PlanetSphere.current = _sphere_before
	GameFlow.reset()
	WorldState.reset()


func _hull() -> StationHull:
	return StationHull.for_id(ID)


func _jet() -> Dictionary:
	var content = CoreScript.new()
	content.load_from()
	return content.get_item("jetpack").get("jetpack", {})


## The giant's own ground: the station and its belt, as the scene has them.
func _ground() -> WorldGround:
	var world: Dictionary = PlanetGen.build(HOST).world
	PlanetSphere.current = PlanetSphere.new(float(world.terrain.sphere_radius))
	var g := WorldGround.new()
	g.setup(world)
	return g


# ------------------------------------------------------------------ the stairs

func test_three_wrecks_end_to_end_each_lower_than_the_last() -> void:
	var h := _hull()
	var bc := BeltWrecks.cfg_of(h)
	var ws := BeltWrecks.layout(h)
	assert_eq(ws.map(func(w): return w.id), WRECKS)
	var hatch := h.drop_hatch()
	assert_false(hatch.is_empty(), "the engine deck has its drop hatch")
	assert_almost_eq((ws[0].near as Vector3).y, (hatch.at as Vector3).y - float(bc.drop_m), 0.01, "the first is drop_m under the hatch")
	for i in range(1, ws.size()):
		var up: Vector3 = ws[i - 1].far
		var down: Vector3 = ws[i].near
		assert_almost_eq(up.y - down.y, float(bc.step_m), 0.01, "%s is step_m under %s" % [ws[i].id, ws[i - 1].id])
		assert_almost_eq(Vector2(up.x - down.x, up.z - down.z).length(), float(bc.gap_m), 0.01, "across gap_m")
	assert_eq((ws[0].spec as Dictionary).get("roll_deg", 0.0), 0.0, "the first lies level")
	for i in range(1, ws.size()):
		assert_ne(float(ws[i].spec.get("roll_deg", 0.0)), 0.0, "%s is tilted" % ws[i].id)


func test_the_jetpack_reaches_every_climb_with_room_to_spare() -> void:
	var top := BeltWrecks.reach(_jet())
	assert_almost_eq(top, 17.0, 0.6, "a jump and a full tank: about 17 m (the issue's sums: 16.9 by hand, 17.0 stepped)")
	var climbs := BeltWrecks.climbs(_hull())
	assert_eq(climbs.size(), 3, "the hatch and two joints")
	assert_eq(BeltWrecks.out_of_reach(_hull(), _jet()), [], "every climb is in reach")


func test_a_weaker_jetpack_fails_the_check() -> void:
	var weak := _jet().duplicate()
	weak["fuel"] = 1.0
	assert_lt(BeltWrecks.reach(weak), 12.0)
	var bad := BeltWrecks.out_of_reach(_hull(), weak)
	assert_eq(bad.size(), 3, "a jetpack change that cannot make the climbs fails: %s" % [bad])


func test_the_ground_agrees_with_the_layout() -> void:
	var g := _ground()
	var h := _hull()
	var fr := StationHull.frame(g, ID)
	for id in WRECKS:
		assert_true(StarcruiserWreck.has_wreck(g, id), "%s is in the giant's ground" % id)
		assert_true(_box(g, id + "/fallen_boarding_plate").is_empty(), "%s: adrift, no plate down to any sand" % id)
		assert_false(_box(g, id + "/plank_0").is_empty(), "%s: a plank over the hole in front of its bridge" % id)
	var ws := BeltWrecks.layout(h)
	for w in ws:
		for key in ["near", "far"]:
			var p: Vector3 = w[key]
			var inward: float = -2.0 if key == "far" else 2.0
			var at: Vector3 = p + (w.xf as Transform3D).basis.z * inward
			assert_almost_eq(_surface(g, fr, at), p.y, 0.3, "%s: its spine where the layout says, %s end" % [w.id, key])
	# Down through the hatch: nothing to stand on until the first wreck's spine.
	var hatch: Vector3 = h.drop_hatch().at
	assert_almost_eq(g.height_above(fr * (hatch + Vector3(0, 1, 0))), 1.0 + float(BeltWrecks.cfg_of(h).drop_m), 0.3,
		"from the hatch it is drop_m down to the first wreck")
	var beside: Vector3 = hatch + (h.drop_hatch().xf as Transform3D).basis.x * 3.5
	assert_almost_eq(g.height_above(fr * (beside + Vector3(0, 1, 0))), 1.0, 0.05, "and the floor round the hole stands")


func test_the_spine_is_walkable_bow_to_bridge_and_stern_to_end() -> void:
	var g := _ground()
	var fr := StationHull.frame(g, ID)
	for w in BeltWrecks.layout(_hull()):
		var xf: Transform3D = w.xf
		var y0 := BeltWrecks.spine_top(w.spec.get("variant", {}), float(w.spec.get("roll_deg", 0.0)), 0, 0.0).y
		var prev := NAN
		var bad := ""
		var z := -296.0
		# Along the ridge (round the radiators on its starboard slope), onto the plank,
		# along the bridge house's roof; then from the pit's stern edge to the end.
		while z <= 296.0 and bad == "":
			if z > 179.0 and z < 213.0:
				z = 213.0
				prev = NAN
			if absf(fposmod(z + 15.0, 30.0) - 15.0) < 0.2:
				z += 0.75                  # the 0.2 m seam between two sections' plates: narrower than a foot
				continue
			var x := 6.0 * _round_radiators(g, str(w.id), z)
			var p := xf * Vector3(x, y0 + 4.0, z)
			var ha := g.height_above(fr * p)
			if ha > 7.0:
				bad = "no spine at z %.1f" % z
				break
			var y := p.y - ha
			if not is_nan(prev) and absf(y - prev) > 0.6:
				bad = "a %.1f m step at z %.1f" % [y - prev, z]
			for lift in [1.0, 1.7]:
				var what := g.hit(fr * Vector3(p.x, y + lift, p.z), 0.3)
				if what != "" and not what.ends_with("radiator"):
					bad = "%s in the way at z %.1f" % [what, z]
			prev = y
			z += 0.75
		assert_eq(bad, "", "%s: its spine is a walk" % w.id)


## How far out onto the starboard slope (0..1 of 6 m) the walk is at z: out round
## each radiator on the ridge (StarcruiserWreck.parts: 11 m long every 29 m from
## z 104), easing out and back over 8 m either side.
func _round_radiators(g: WorldGround, id: String, z: float) -> float:
	var k := 0.0
	for i in 6:
		if _box(g, "%s/radiator_%d" % [id, i]).is_empty():
			continue
		var d := absf(z - (104.0 + i * 29.0))
		k = maxf(k, clampf((14.0 - d) / 8.0, 0.0, 1.0))
	return k


func test_the_station_holds_its_up_over_every_wreck() -> void:
	var g := _ground()
	var fr := StationHull.frame(g, ID)
	for w in BeltWrecks.layout(_hull()):
		for key in ["near", "far"]:
			var at: Vector3 = fr * ((w[key] as Vector3) + Vector3(0, 2, 0))
			assert_almost_eq(g.up_at(at).dot(fr.basis.y), 1.0, 0.0001, "%s %s: the station's up, not the ball's" % [w.id, key])


func test_the_drop_hatch_is_a_shielded_hole_in_the_cargo_hold() -> void:
	var h := _hull()
	var hatch := h.drop_hatch()
	assert_eq(str(hatch.tower), "main")
	assert_eq(str(h.tower("main").floors[int(hatch.floor)].id), "engines", "on the engine deck")
	var uses: Array = h.cfg.fill.floors.engines.rooms
	assert_eq(str(uses[int(hatch.room) % uses.size()]), "cargo", "in a cargo hold")
	assert_false(h.drop_shield.is_empty(), "a shield over it, as the tunnels' roof hatches")
	assert_eq(h.hatches.size(), h.tunnels.size(), "which are still one a tunnel")
	assert_true(h.over_hatch(hatch.at))
	assert_false(h.over_hatch((hatch.at as Vector3) + Vector3(0, 0, 5)))


func test_dock_path_from_under_the_station_passes_under_the_wrecks() -> void:
	var h := _hull()
	var lowest := INF
	for w in BeltWrecks.layout(h):
		lowest = minf(lowest, (w.xf as Transform3D).origin.y - BeltWrecks.BOX_HALF.y)
	assert_lt(float(h.cfg.dock.under_y), lowest - 10.0, "the autopilot's way under the towers clears the wrecks' keels")
	var over_wreck: Vector3 = (BeltWrecks.layout(h)[1].far as Vector3) + Vector3(0, 30, 0)
	var path := h.dock_path(over_wreck)
	assert_gt((path[0] as Vector3).y, h.top_y(), "from over a wreck it climbs over the towers, not down through the wreck")


func _box(g: WorldGround, id: String) -> Dictionary:
	for b in g.boxes:
		if str(b.id) == id:
			return b
	return {}


## The height of what you stand on at station point `at` (over or under it).
func _surface(g: WorldGround, fr: Transform3D, at: Vector3) -> float:
	var from := at + Vector3(0, 3, 0)
	return from.y - g.height_above(fr * from)


# ------------------------------------------------------------------ crews and loot

class FakePlayer extends CharacterBody3D:
	var piloting := false
	var locked := false
	var jetpack = null


func test_every_belt_wreck_is_manned_more_the_deeper() -> void:
	var g := _ground()
	WorldState.droids.wrecks_seeded = true
	var root := Node3D.new()
	add_child_autofree(root)
	var p := FakePlayer.new()
	root.add_child(p)
	var ctl := DroidController.new()
	ctl.setup(null, p, null)
	ctl.ground = g
	root.add_child(ctl)
	await wait_physics_frames(2)
	var dc: Dictionary = DroidRoster.config().wreck
	var extras := []
	for id in WRECKS:
		var site: Dictionary = dc.sites.filter(func(s): return str(s.landmark) == id)[0]
		var want: Array = ((dc.units as Array) + (site.get("extra_units", []) as Array)).filter(func(u): return not (str(u.route) in site.get("skip_routes", [])))
		var crew: Array = ctl.remnant.filter(func(u): return str(u.spec.get("site", "")) == id)
		assert_eq(crew.size(), want.size(), "%s is manned" % id)
		assert_eq(crew.filter(func(u): return str(u.spec.route) == "pad").size(), 2, "%s: assassins on its pad" % id)
		extras.append((site.get("extra_units", []) as Array).size())
		for u in crew:
			assert_true(ctl.is_zombie(u), "%s: zombies, as the desert's" % id)
	assert_lt(extras[0], extras[1], "more guards on the second")
	assert_lt(extras[1], extras[2], "and more again on the last")
	assert_null(ctl.wreck_hauler, "no hauler out here")


func test_every_belt_crew_route_runs_on_a_floor() -> void:
	var g := _ground()
	var fr := StationHull.frame(g, ID)
	var dc: Dictionary = DroidRoster.config().wreck
	for id in WRECKS:
		var site: Dictionary = dc.sites.filter(func(s): return str(s.landmark) == id)[0]
		for u in (dc.units as Array) + (site.get("extra_units", []) as Array):
			var name := str(u.route)
			if name in site.get("skip_routes", []):
				continue
			var r: Dictionary = dc.routes[name]
			for pt in r.points:
				var at := StarcruiserWreck.site_point(g, Vector3(pt[0], pt[1], pt[2]), str(r.frame), id)
				var ha := g.height_above(at + g.up_at(at))
				assert_almost_eq(ha, 1.0, 0.6, "%s route %s: a floor under %s" % [id, name, str(pt)])


func test_a_crate_on_every_bridge_platform_the_deepest_the_best() -> void:
	var g := _ground()
	var content = CoreScript.new()
	content.load_from()
	var crates: Array = content.get_site_crates("ringed_giant_town")
	assert_eq(crates.map(func(c): return str(c.site)), WRECKS)
	var values := []
	for c in crates:
		var pt: Array = c.site_point
		var at := StarcruiserWreck.site_point(g, Vector3(pt[0], pt[1], pt[2]), "level", str(c.site))
		var up := g.up_at(at)
		assert_almost_eq(g.height_above(at + up), 1.0, 0.3, "%s sits on the platform" % c.id)
		assert_eq(g.hit(at + up * 1.0, 0.6), "", "%s is not inside anything" % c.id)
		var prize: Dictionary = (c.prizes as Array)[0]
		var item: Dictionary = content.get_item(str(prize.item))
		assert_false(item.is_empty(), "%s's prize is an item" % c.id)
		values.append(int(item.get("value", 0)) * int(prize.get("count", 1)))
	assert_lt(values[0], values[1], "the second crate pays better than the first")
	assert_lt(values[1], values[2], "and the last best of all")


func test_crates_open_once_and_pay_their_own_prize() -> void:
	var g := _ground()
	var root := Node3D.new()
	add_child_autofree(root)
	var p := FakePlayer.new()
	root.add_child(p)
	var gear := GearController.new()
	gear.setup(null, null, p, null, "ringed_giant_town")
	gear.ground = g
	root.add_child(gear)
	gear.set_physics_process(false)
	gear._build_site_crates()
	var crates: Array = gear.pickups.filter(func(n): return bool(n.pickup.get("crate", false)))
	assert_eq(crates.size(), 3, "a crate on each belt wreck")
	var loot: Array = gear.pickups.filter(func(n): return str(n.pickup.get("site", "")) in WRECKS and not bool(n.pickup.get("crate", false)))
	assert_gt(loot.size(), 20, "stray loot on all three")
	for n in loot:
		var at: Vector3 = n.global_position if n.is_inside_tree() else n.transform.origin
		assert_lt(g.height_above(at + g.up_at(at)), 1.6, "%s lies on a floor" % str(n.pickup.id))
	var deepest = crates.filter(func(n): return str(n.pickup.id) == "belt_crate_3")[0]
	assert_eq(gear._open_crate(deepest), "opened")
	assert_eq(gear.inv().count("seeker_launcher"), 1, "the bottom of the stairs pays a seeker launcher")
	assert_true(gear.inv().is_taken("belt_crate_3"), "opened once, it stays open")


# ------------------------------------------------------------------ in the giant's scene

func _host() -> Node:
	GameFlow.reset()
	GameFlow.resumed = true
	GameFlow.planet_id = HOST
	GameFlow.change_scene = func(_p: String) -> void: pass
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	return t


func _station(t):
	for i in 180:
		if not t.stations.is_empty() and t.gear != null:
			return t.stations[0]
		await wait_physics_frames(1)
	return null


func _wear_jetpack(t) -> void:
	var content = CoreScript.new()
	content.load_from()
	t.gear.inv().add("jetpack", 1)
	t.gear.inv().attach("jetpack", content.get_item("jetpack"))
	t.gear.sync_gear()
	t._player.jetpack.refill()


## Stand the player at station point `l`, still, facing nowhere in particular.
func _put(s, p, l: Vector3) -> void:
	p.global_position = s.frame * l
	p.rotation = Vector3.ZERO
	p.velocity = Vector3.ZERO
	p.align_to_ground(true)


## Walk (or fly, holding jump) toward station point `goal` until `done` says so or
## `frames` run out. The body's yaw stays 0, so the command's x/y is the world's x/z
## (the station's frame is level and unturned over the giant: asserted below).
func _drive(s, p, goal: Vector3, frames: int, jump := false, done: Callable = Callable()) -> void:
	for i in frames:
		var l: Vector3 = s.inv * p.global_position
		var to := Vector2(goal.x - l.x, goal.z - l.z)
		var dir := to.normalized() if to.length() > 0.3 else Vector2.ZERO
		p.set_command(dir, true, false, jump and i == 0, jump)
		await wait_physics_frames(1)
		if done.is_valid() and bool(done.call(s.inv * p.global_position)):
			break
	p.set_command(Vector2.ZERO, false, false, false, false)


func _on(p) -> bool:
	return (p as CharacterBody3D).is_on_floor()


func test_down_the_stairs_and_back_up_into_the_station() -> void:
	var t = _host()
	var s = await _station(t)
	if s == null:
		fail_test("no station")
		return
	assert_true(s.frame.basis.is_equal_approx(Basis.IDENTITY), "the station is level and unturned here")
	assert_eq(s.belt.size(), 3, "the station knows its belt")
	var p = t._player
	_wear_jetpack(t)
	var h: StationHull = s.hull
	var hatch := h.drop_hatch()
	var hat: Vector3 = hatch.at
	var ws: Array = s.belt
	# 1. Through the hatch: step onto it from the floor beside it, drop to the first wreck.
	var beside: Vector3 = hat - (hatch.xf as Transform3D).basis.x * 3.5 + Vector3(0, 0.2, 0)
	_put(s, p, beside)
	await wait_physics_frames(10)
	assert_true(s.aboard(p.global_position), "in the cargo hold")
	await _drive(s, p, hat, 240, false, func(l): return l.y < hat.y - 5.0)
	for i in 180:
		await wait_physics_frames(1)
		if _on(p) and (s.inv * p.global_position).y < hat.y - 5.0:
			break
	var l: Vector3 = s.inv * p.global_position
	assert_almost_eq(l.y, (ws[0].near as Vector3).y, 1.5, "dropped through the hatch onto the first wreck's spine")
	assert_eq(s.falls, 0, "not pulled back: over the belt the pull is off")
	# 2. Down: from near the end of each wreck, walk off it onto the next.
	for i in range(1, 3):
		var far: Vector3 = ws[i - 1].far
		var dir: Vector3 = (ws[i - 1].xf as Transform3D).basis.z
		dir = Vector3(dir.x, 0, dir.z).normalized()
		_put(s, p, far - dir * 12.0 + Vector3(0, 0.5, 0))
		await wait_physics_frames(10)
		var target: Vector3 = (ws[i].near as Vector3) + (ws[i].xf as Transform3D).basis.z * 10.0
		var low: float = (ws[i].near as Vector3).y + 2.0
		await _drive(s, p, target, 300, false, func(q): return q.y < low and _on(p))
		l = s.inv * p.global_position
		assert_almost_eq(l.y, (ws[i].near as Vector3).y, 1.5, "walked off %s's end down onto %s" % [ws[i - 1].id, ws[i].id])
		assert_eq(s.belt_falls, 0, "still alive")
	# 3. Up: jetpack from each wreck's bow up onto the one before it.
	for i in [2, 1]:
		var near: Vector3 = ws[i].near
		var dir: Vector3 = (ws[i].xf as Transform3D).basis.z
		dir = Vector3(dir.x, 0, dir.z).normalized()
		_put(s, p, near + dir * 3.0 + Vector3(0, 0.5, 0))
		await wait_physics_frames(20)
		p.jetpack.refill()
		var goal: Vector3 = (ws[i - 1].far as Vector3) - (ws[i - 1].xf as Transform3D).basis.z * 6.0
		var high: float = (ws[i - 1].far as Vector3).y - 1.0
		await _drive(s, p, goal, 360, true, func(q): return q.y > high and _on(p))
		l = s.inv * p.global_position
		assert_almost_eq(l.y, (ws[i - 1].far as Vector3).y, 1.5, "jetpacked up from %s onto %s" % [ws[i].id, ws[i - 1].id])
	# 4. Up through the hatch: from the spine under it, rise and steer onto the floor.
	_put(s, p, (ws[0].near as Vector3) + Vector3(0, 0.5, 0) + (hat - (ws[0].near as Vector3)) * Vector3(1, 0, 1))
	await wait_physics_frames(20)
	p.jetpack.refill()
	var land: Vector3 = hat + (hatch.xf as Transform3D).basis.x * 3.5
	var climb := func(q): return q.y > hat.y - 0.5 and _on(p)
	for i in 400:
		var q: Vector3 = s.inv * p.global_position
		# Under the floor: hold over the hole's middle; above it, out onto the floor.
		var aim: Vector3 = hat if q.y < hat.y + 1.0 else land
		var to := Vector2(aim.x - q.x, aim.z - q.z)
		p.set_command(to.normalized() if to.length() > 0.2 else Vector2.ZERO, false, false, i == 0, true)
		await wait_physics_frames(1)
		if climb.call(s.inv * p.global_position):
			break
	p.set_command(Vector2.ZERO, false, false, false, false)
	await wait_physics_frames(10)
	assert_true(s.aboard(p.global_position), "back up through the hatch, aboard")
	l = s.inv * p.global_position
	assert_almost_eq(l.y, hat.y, 0.6, "standing on the engine deck")
	assert_eq(s.belt_falls, 0, "and alive all the way")


func test_off_the_side_and_the_belt_has_you() -> void:
	var t = _host()
	var s = await _station(t)
	if s == null:
		fail_test("no station")
		return
	var p = t._player
	var w: Dictionary = s.belt[1]
	var side: Vector3 = (w.xf as Transform3D).basis.x
	side = Vector3(side.x, 0, side.z).normalized()
	var on: Vector3 = (w.near as Vector3) + (w.xf as Transform3D).basis.z * 64.0 + Vector3(0, 0.5, 0)
	_put(s, p, on)
	for i in 60:
		await wait_physics_frames(1)
		if _on(p):
			break
	assert_true(_on(p), "standing on the second wreck's spine (at %s, %.2f m over the ground)" % [str(s.inv * p.global_position),
		t.pilot.ground.height_above(p.global_position + Vector3.UP)])
	var log_before := WorldState.events.size()
	# Out past the flank, then let go.
	_put(s, p, on + side * 60.0)
	for i in 240:
		await wait_physics_frames(1)
		if s.belt_falls > 0:
			break
	assert_eq(s.belt_falls, 1, "fell into the belt")
	assert_true(s.aboard(p.global_position), "and woke in the station's bay")
	assert_true(t.gear.hud.toast_label.text.begins_with(str(BeltWrecks.cfg_of(s.hull).lines.fell)), "with the belt's line")
	assert_gt(WorldState.events.size(), log_before, "and the world remembers it")


## The other way down: fly there and set her down on the first wreck's landing pad
## (its bridge platform), then step out onto it.
func test_you_can_set_your_ship_down_on_the_first_wrecks_pad() -> void:
	var t = _host()
	var s = await _station(t)
	if s == null:
		fail_test("no station")
		return
	var pilot: ShipPilot = t.pilot
	var g: WorldGround = pilot.ground
	var pad := StarcruiserWreck.site_point(g, Vector3(0, StarcruiserWreck.BRIDGE_V, 136), "level", WRECKS[0])
	pilot._seat_arriving()
	pilot.atmo.place_flying(pad + Vector3(0, 30, 0), Vector3.FORWARD, 0.0, 0.0)
	pilot._set_hull(true)
	await wait_physics_frames(2)
	assert_true(pilot.atmo.land(), "low enough over the pad to land")
	for i in 60 * 20:
		if pilot.atmo.state == AtmoFlight.State.PARKED:
			break
		await wait_physics_frames(1)
	assert_eq(pilot.atmo.state, AtmoFlight.State.PARKED, "down")
	var at := pilot.atmo.position()
	assert_almost_eq(at.y - pilot.atmo.clearance, pad.y, 0.6, "on the pad, not on the plating round the pit")
	assert_true(pilot.exit_ship())
	await wait_physics_frames(30)
	var p = t._player
	assert_true(p.is_on_floor(), "and you step out onto the wreck")
	assert_eq(s.belt_falls, 0)
