extends GutTest
## Issue #838: the Remnant skimmer outposts over the ringed giant
## (content/core/stations/skimmer_outpost.json, three "station" landmarks in
## content/core/planets/ringed_giant.json). The station kit at its smallest: one
## deck, a small bay; hung just over the horizon from the station city, level with
## the ball where each hangs; Z docks you in its bay; its deck is the Remnant's.

const TownDemo := preload("res://scenes/town_demo.gd")
const StationRemnant := preload("res://src/systems/world/station_remnant.gd")
const ID := "skimmer_outpost"
const HOST := "ringed_giant"
const CITY := "orbital_station"

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


func _landmarks() -> Array:
	return StationHull.landmarks(PlanetGen.build(HOST).world).filter(func(lm): return str(lm.get("station", "")) == ID)


func _city_landmark() -> Dictionary:
	for lm in StationHull.landmarks(PlanetGen.build(HOST).world):
		if str(lm.get("station", "")) == CITY:
			return lm
	return {}


func _giant() -> GasSphere:
	var g := PlanetGen.build(HOST)
	return GasSphere.new(PlanetGen.ball_radius(g.cfg, null), g.type_cfg.surface)


## The highest point of a hull (its mast's beacon), in its own frame.
static func _top(h: StationHull) -> float:
	var y := -INF
	for p in h.parts:
		y = maxf(y, (p.xf as Transform3D).origin.y + (p.size as Vector3).y * 0.5)
	return y


## The segment a-b passes under radius `r` round `c` (the cloud tops are in the way).
static func _blocked(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	var ab := b - a
	var t := clampf((c - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (a + ab * t).distance_to(c) < r


# ------------------------------------------------------------------ shape

func test_one_deck_and_a_bay_the_moon_pits_size() -> void:
	var h := _hull()
	assert_not_null(h)
	assert_eq(h.towers.size(), 1, "one tower")
	var fl: Array = h.towers[0].floors
	assert_eq(fl.size(), 1, "of one floor")
	assert_almost_eq(float(fl[0].r) * 2.0, 80.0, 0.01, "80 m across")
	assert_almost_eq(float(h.bay.r) * 2.0, 56.0, 0.01, "the bay is the moon's landing pit's size")
	assert_eq(h.pads().size(), 2, "two pads: yours and the Remnant's")
	assert_false(h.dock_pad().is_empty())
	assert_eq(h.tunnels.size(), 1, "one tunnel, deck to bay")
	assert_almost_eq(float(h.tunnels[0].length), 22.0, 1.0, "about 22 m long (it runs into both walls)")
	for p in h.pads():
		var l: Vector2 = p.local
		assert_lt(l.length() + float(p.radius), float(h.bay.r), "pad %s inside the bay's wall" % p.id)
	assert_true(h.aboard(h.spawn_point() + Vector3(0, 0.5, 0)), "the spot beside the dock pad is aboard")
	assert_true(h.elevators().is_empty(), "one floor: no elevator")


func test_its_deck_is_the_remnants() -> void:
	var h := _hull()
	assert_false(StationRemnant.deck(h).is_empty(), "the whole floor is the Remnant's deck")
	var uses: Array = StationRemnant.rooms(h).map(func(r): return str(r.use))
	assert_true(uses.has("control") and uses.has("command") and uses.has("armoury") and uses.has("bunks"), str(uses))
	var posts := StationRemnant.posts(h)
	assert_gt(posts.size(), 6, "troopers to stand")
	assert_eq(posts.filter(func(p): return str(p.soldier) == "commander").size(), 1, "a commander in command")
	for lm in _landmarks():
		assert_eq(Territory.owner("station_" + str(lm.id)), Territory.REMNANT, "%s starts the Remnant's" % lm.id)


# ------------------------------------------------------------------ where

func test_three_just_over_the_horizon_at_the_citys_height() -> void:
	var lms := _landmarks()
	assert_eq(lms.size(), 3, "three outposts")
	var sp := _giant()
	var city := StationHull.for_id(CITY).frame_for(sp, _city_landmark(), { "planet": HOST })
	var city_up := (city.origin - sp.center).normalized()
	var dirs: Array = []
	for lm in lms:
		var xf := _hull().frame_for(sp, lm, { "planet": HOST })
		var up := (xf.origin - sp.center).normalized()
		dirs.append(up)
		assert_almost_eq(xf.origin.distance_to(sp.center), city.origin.distance_to(sp.center), 0.5, "%s at the city's height" % lm.id)
		assert_almost_eq(rad_to_deg(up.angle_to(city_up)), 52.0, 0.5, "%s 52 degrees round the ball" % lm.id)
		assert_almost_eq(xf.basis.y.angle_to(up), 0.0, 0.001, "%s level with the ball where it hangs" % lm.id)
		var mouth: Vector3 = xf.basis * _hull().bay_out()
		var to_city := city.origin - xf.origin
		to_city -= up * to_city.dot(up)
		assert_gt(mouth.dot(to_city.normalized()), 0.99, "%s's bay faces the city" % lm.id)
	for i in dirs.size():
		for j in range(i + 1, dirs.size()):
			assert_gt(rad_to_deg((dirs[i] as Vector3).angle_to(dirs[j])), 80.0, "the outposts well apart")


func test_the_clouds_hide_them_from_the_city_even_from_its_top_floor() -> void:
	var sp := _giant()
	var city_h := StationHull.for_id(CITY)
	var city := city_h.frame_for(sp, _city_landmark(), { "planet": HOST })
	var clouds := sp.radius - sp.depth
	var eyes: Array = [city * Vector3(0, 1.7, 0), city * Vector3(0, city_h.top_y(), 0)]
	for lm in _landmarks():
		var xf := _hull().frame_for(sp, lm, { "planet": HOST })
		var top: Vector3 = xf * Vector3(0, _top(_hull()), 0)
		for eye in eyes:
			assert_true(_blocked(eye, top, sp.center, clouds), "%s's mast top is under the horizon" % lm.id)
		# ... and only just: from 200 m higher it shows.
		assert_false(_blocked(city * Vector3(0, city_h.top_y() + 200.0, 0), top, sp.center, clouds), "%s just over it" % lm.id)


func test_its_parts_stand_and_its_gravity_is_its_own_up() -> void:
	var sp := _giant()
	PlanetSphere.current = sp
	var lm: Dictionary = _landmarks()[0]
	var g := WorldGround.new()
	g.setup({ "terrain": { "sphere_radius": sp.radius }, "landmarks": [lm], "planet": HOST })
	var xf := StationHull.frame(g, str(lm.id))
	assert_ne(xf, Transform3D.IDENTITY, "its boxes are in the ground")
	var deck: Vector3 = xf * Vector3(25, 1.0, 0)
	assert_almost_eq(g.sphere().up_at(deck).angle_to(xf.basis.y), 0.0, 0.001, "up aboard is the outpost's up")
	assert_almost_eq(g.height_above(deck), 1.0, 0.1, "its floor holds you")


# ------------------------------------------------------------------ in the scene

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


func _outpost(t, lm_id: String):
	for i in 120:
		for s in t.stations:
			if str(s.id) == lm_id:
				return s
		await wait_physics_frames(1)
	return null


func test_the_scene_builds_all_three_with_names_of_their_own() -> void:
	var t = _host()
	var s = await _outpost(t, "skimmer_east")
	assert_not_null(s)
	var names := {}
	for st in t.stations:
		if str(st.cfg.get("id", "")) == ID:
			names[st.label()] = true
			assert_not_null(st.remnant, "%s has its Remnant deck" % st.id)
	assert_eq(names.size(), 3, "three outposts, three names: %s" % str(names.keys()))


func test_z_docks_you_in_an_outposts_bay_level_with_it() -> void:
	var t = _host()
	var s = await _outpost(t, "skimmer_east")
	assert_not_null(s, "the giant's scene builds the outpost")
	if s == null:
		return
	var pilot: ShipPilot = t.pilot
	pilot._seat_arriving()
	pilot.atmo.place_flying(s.frame * Vector3(-400, 40, 30), Vector3.FORWARD, 0.0, 0.5)
	pilot._set_hull(true)
	await wait_physics_frames(2)
	assert_true(pilot.near_dock(), "in reach of its bay")
	assert_eq(pilot.dock_target(), s, "the outpost, not the city")
	assert_true(pilot.dock())
	for i in 60 * 40:
		if pilot.atmo.state == AtmoFlight.State.PARKED:
			break
		await wait_physics_frames(1)
	assert_eq(pilot.atmo.state, AtmoFlight.State.PARKED, "down on the pad")
	var at: Vector3 = s.to_local_point(pilot.atmo.position())
	var pad: Vector3 = s.hull.dock_pad().at
	assert_almost_eq(Vector2(at.x, at.z).distance_to(Vector2(pad.x, pad.z)), 0.0, 1.0, "on the dock pad")
	assert_lt(pilot.atmo.flight.basis.y.angle_to(s.frame.basis.y), 0.05, "sat level on the tilted deck")
	assert_true(pilot.exit_ship())
	await wait_physics_frames(30)
	var p = t._player
	assert_true(s.aboard(p.global_position), "you step out aboard")
	assert_true(p.is_on_floor())


# ------------------------------------------------------------------ the roof

## A solid or floor part of `h` holds the point `p` (its frame's box, a little grown).
static func _inside_part(h: StationHull, p: Vector3) -> bool:
	for part in h.parts:
		if not (str(part.kind) in ["solid", "floor"]):
			continue
		var l := (part.xf as Transform3D).affine_inverse() * p
		var e: Vector3 = (part.size as Vector3) * 0.5 + Vector3(0.05, 0.05, 0.05)
		if absf(l.x) <= e.x and absf(l.y) <= e.y and absf(l.z) <= e.z:
			return true
	return false


func test_a_shielded_hatch_and_a_ladder_up_to_the_roof() -> void:
	var h := _hull()
	var roof_hatches: Array = h.floor_hatches.filter(func(x): return int(x.floor) == 0)
	assert_eq(roof_hatches.size(), 4, "the station kit's four ceiling hatches")
	if roof_hatches.is_empty():
		return
	var hx: Transform3D = roof_hatches[0].xf
	var f: Dictionary = h.towers[0].floors[0]
	var ceil_mid := float(f.y) + h.floor_h + h.plate * 0.5
	assert_almost_eq(hx.origin.y, ceil_mid, 0.1, "in the ceiling")
	var flat := Vector2(hx.origin.x, hx.origin.z)
	assert_between(flat.length(), h.gap_r, h.gap_r + h.walk, "over the walkway")
	assert_false(_inside_part(h, hx.origin), "the hatch is a hole, closed only by its shield")
	var beside := hx.origin + hx.basis.z.normalized() * 3.5
	assert_true(_inside_part(h, beside), "the ceiling round it is solid")
	var roof := float(f.y) + h.floor_h + h.plate
	assert_false(_inside_part(h, Vector3(hx.origin.x, roof + 0.6, hx.origin.z)), "nothing on the roof over it")
	var out := hx.origin + hx.basis.x.normalized() * 1.0
	assert_false(_inside_part(h, Vector3(out.x, roof + 0.6, out.z)), "the roof ring leaves the way out open")
	assert_true(h.on_roof(Vector3(hx.origin.x, roof + 1.0, hx.origin.z)), "up through it you are out on the roof")
	var rails := h.parts.filter(func(p): return str(p.id).contains("_roof_ladder_rail_"))
	assert_eq(rails.size(), 2, "a ladder's two rails")
	for r in rails:
		var top: float = (r.xf as Transform3D).origin.y + (r.size as Vector3).y * 0.5
		var bottom: float = (r.xf as Transform3D).origin.y - (r.size as Vector3).y * 0.5
		assert_almost_eq(bottom, float(f.y), 0.05, "from the walkway")
		assert_gt(top, roof + 0.5, "up past the roof, a handhold")


func test_antennas_and_a_launcher_guard_on_the_roof() -> void:
	var h := _hull()
	assert_eq(h.parts.filter(func(p): return str(p.id).ends_with("_dish")).size(), 2, "two dishes")
	assert_eq(h.parts.filter(func(p): return str(p.id).ends_with("_rod")).size(), 3, "three whip antennas")
	assert_false(h.parts.filter(func(p): return str(p.id).ends_with("_beacon")).is_empty(), "the mast's beacon")
	var f: Dictionary = h.towers[0].floors[0]
	var roof := float(f.y) + h.floor_h + h.plate
	var up: Array = StationRemnant.posts(h).filter(func(p): return str(p.soldier) == "roof")
	assert_eq(up.size(), 1, "one roof guard")
	if up.is_empty():
		return
	assert_almost_eq((up[0].at as Vector3).y, roof, 0.01, "standing on the roof")
	assert_gt((up[0].patrol as Array).size(), 4, "walking a loop round it")
	for pt in up[0].patrol:
		assert_false(_inside_part(h, (pt as Vector3) + Vector3(0, 0.9, 0)), "nothing in the way at %s" % str(pt))
	assert_eq(str(h.cfg.remnant.roof_trooper), "roof_launcher", "the Remnant's carries a seeker launcher")
	assert_eq(str(h.cfg.remnant.roof_guard), "local_launcher", "so do the locals'")


func test_you_drop_back_down_through_the_hatch_onto_the_walkway() -> void:
	var t = _host()
	var s = await _outpost(t, "skimmer_east")
	assert_not_null(s)
	if s == null:
		return
	var hx: Transform3D = s.hull.floor_hatches.filter(func(x): return int(x.floor) == 0)[0].xf
	var roof: float = s.hull.floor_h + s.hull.plate
	var p = t._player
	p.global_position = s.frame * Vector3(hx.origin.x - 0.6, roof + 0.6, hx.origin.z)
	p.velocity = Vector3.ZERO
	for i in 120:
		await wait_physics_frames(1)
		if p.is_on_floor() and s.to_local_point(p.global_position).y < 4.0:
			break
	var at: Vector3 = s.to_local_point(p.global_position)
	assert_lt(at.y, 4.0, "fell through the hatch's shield, 15 m down to the walkway: %s" % str(at))
	assert_true(p.is_on_floor(), "and stands on the walkway")
	assert_true(s.aboard(p.global_position), "inside")


func test_the_roof_guard_takes_his_post_with_the_deck() -> void:
	var t = _host()
	var s = await _outpost(t, "skimmer_east")
	assert_not_null(s)
	if s == null or s.remnant == null:
		return
	s.remnant._wake()
	for i in 90:
		await wait_physics_frames(1)
		if s.remnant._queue.is_empty():
			break
	var roof: float = s.hull.floor_h + s.hull.plate
	var up: Array = s.remnant.troopers.filter(func(g): return is_instance_valid(g) and s.to_local_point(g.global_position).y > roof - 0.5)
	assert_eq(up.size(), 1, "a trooper on the roof")


# ------------------------------------------------------------------ the skimmer

func test_the_skimmer_gantry_hangs_under_its_control_room() -> void:
	var h := _hull()
	var units := h.skimmer_units()
	assert_eq(units.map(func(u): return str(u.style)), ["globe", "core"], "the outposts' two tanks")
	var t: Dictionary = h.towers[0]
	var plate_under := float(t.floors[0].y) - h.plate
	var deck_y := plate_under - float(t.skimmer.depth)
	var probe := QuantoniumRefinery.new()
	for u in units:
		var xf: Transform3D = u.xf
		assert_almost_eq(xf.origin.y, deck_y, 0.01, "%s on the gantry's deck" % u.style)
		assert_true(_inside_part(h, xf.origin + Vector3(0, -0.3, 0)), "%s stands on solid deck" % u.style)
		probe.build(str(u.style), null, null, null, 0.0, "probe")
		assert_lt(xf.origin.y + probe._top, plate_under - 1.0, "%s clears the floor above" % u.style)
		for leg in h.parts.filter(func(p): return str(p.id).contains("_skimmer_leg_")):
			var lo: Vector3 = (leg.xf as Transform3D).origin
			assert_gt(Vector2(lo.x - xf.origin.x, lo.z - xf.origin.z).length(), QuantoniumRefinery.footprint() + 0.4, "%s clear of the trusses" % u.style)
	probe.free()
	var room: Array = StationRemnant.rooms(h).filter(func(r): return str(r.use) == "skimmer")
	assert_eq(room.size(), 1, "a skimmer control room on the deck")
	var holes: Array = h.hatches.filter(func(x): return str(x.tunnel).ends_with("_floor"))
	assert_eq(holes.size(), 1, "a hatch in the floor")
	if room.is_empty() or holes.is_empty():
		return
	var hx: Transform3D = holes[0].xf
	assert_almost_eq(Vector2(hx.origin.x, hx.origin.z).angle(), wrapf(float(room[0].room.a), -PI, PI), 0.01, "in the skimmer room")
	assert_false(_inside_part(h, hx.origin), "the hatch is a hole in the plate")
	assert_true(_inside_part(h, Vector3(hx.origin.x, deck_y - 0.3, hx.origin.z)), "the gantry's deck under it")
	var rails := h.parts.filter(func(p): return str(p.id).contains("_floor_ladder_rail_"))
	assert_eq(rails.size(), 2, "a ladder down to the gantry")
	for r in rails:
		assert_almost_eq((r.xf as Transform3D).origin.y - (r.size as Vector3).y * 0.5, deck_y, 0.05, "standing on the gantry")


func test_the_blast_reaches_the_troopers_in_the_room_above() -> void:
	var h := _hull()
	var radius := float(QuantoniumRefinery.game_cfg().get("blast_radius", 22.0))
	var posts: Array = StationRemnant.posts(h).filter(func(p): return str(p.id).begins_with("skimmer_"))
	assert_eq(posts.size(), 2, "two troopers in skimmer control")
	var probe := QuantoniumRefinery.new()
	for u in h.skimmer_units():
		probe.build(str(u.style), null, null, null, 0.0, "probe")
		var centre: Vector3 = (u.xf as Transform3D) * Vector3(0, probe._mid * 0.5, 0)
		for p in posts:
			assert_lt((p.at as Vector3).distance_to(centre), radius - 1.0, "%s's blast reaches %s" % [u.style, p.id])
	probe.free()


func test_the_tanks_chain_blow_kill_the_room_above_and_come_back() -> void:
	var t = _host()
	var s = await _outpost(t, "skimmer_east")
	assert_not_null(s)
	if s == null:
		return
	assert_eq(s.refineries.size(), 2, "two tanks on the gantry")
	s.remnant._wake()
	for i in 90:
		await wait_physics_frames(1)
		if s.remnant._queue.is_empty():
			break
	var spots: Array = StationRemnant.posts(s.hull).filter(func(p): return str(p.id).begins_with("skimmer_")).map(func(p): return s.to_world(p.at))
	var room: Array = s.remnant.troopers.filter(func(g): return is_instance_valid(g) and spots.any(func(q): return g.global_position.distance_to(q) < 1.5))
	var far: Array = s.remnant.troopers.filter(func(g): return is_instance_valid(g) and str(g.name).ends_with("_command_4"))
	assert_eq(room.size(), 2, "both at their posts in skimmer control")
	s.refineries[0].hit(5000.0, null)
	await wait_seconds(1.5)
	assert_false(s.refineries[0].alive, "it went up")
	assert_false(s.refineries[1].alive, "and set the other off")
	for g in room:
		assert_true(not is_instance_valid(g) or g.dead, "%s died in the blast" % str(g.name))
	for g in far:
		assert_true(is_instance_valid(g) and not g.dead, "the commander, across the deck, lived")
	s.rebuild_skimmer()
	assert_true(s.refineries[0].alive and s.refineries[1].alive, "built again")


func test_you_drop_through_the_floor_hatch_onto_the_gantry() -> void:
	var t = _host()
	var s = await _outpost(t, "skimmer_east")
	assert_not_null(s)
	if s == null:
		return
	var hx: Transform3D = s.hull.hatches.filter(func(x): return str(x.tunnel).ends_with("_floor"))[0].xf
	var p = t._player
	p.global_position = s.frame * (hx * Vector3(-0.5, 1.2, 0))
	p.velocity = Vector3.ZERO
	for i in 180:
		await wait_physics_frames(1)
		if p.is_on_floor() and s.to_local_point(p.global_position).y < -10.0:
			break
	var at: Vector3 = s.to_local_point(p.global_position)
	assert_lt(at.y, -18.0, "down through the hatch: %s" % str(at))
	assert_true(p.is_on_floor(), "standing on the gantry")


# ------------------------------------------------------------------ the capture chain

func _woke(s) -> void:
	s.remnant._wake()
	for i in 120:
		await wait_physics_frames(1)
		if s.remnant._queue.is_empty():
			break


func _kill_all(list: Array) -> void:
	for g in list:
		if is_instance_valid(g) and not g.dead:
			g.apply_damage(100000.0)
	await wait_physics_frames(3)


## Tick the deck's front rules once with the player at `p` (30 calls: one real tick).
func _rules(s, p: Vector3) -> void:
	for i in 30:
		s.remnant._tick_front_rules(p)


func test_the_station_citys_deck_is_locked_while_the_belt_cruiser_stands() -> void:
	var t = _host()
	var s = await _outpost(t, CITY)
	assert_not_null(s)
	if s == null or s.remnant == null:
		return
	await _woke(s)
	assert_gt(s.remnant.troopers.size(), 5)
	await _kill_all(s.remnant.troopers)
	assert_eq(Territory.owner("station_" + CITY), Territory.REMNANT, "every trooper dead and still the Remnant's")
	assert_true(s.remnant.restock, "more will come")
	s.remnant.reset_people()
	assert_true(s.remnant.troopers.is_empty() and not s.remnant.woke, "they come back the next time you come near")
	WorldState.set_flag("belt_cruiser_taken")
	await _woke(s)
	await _kill_all(s.remnant.troopers)
	assert_eq(Territory.owner("station_" + CITY), Territory.LOCALS, "the cruiser fallen, the deck is the locals'")


func test_a_cleared_skimmer_changes_hands_only_later_and_far_off() -> void:
	var t = _host()
	var s = await _outpost(t, "skimmer_east")
	assert_not_null(s)
	if s == null or s.remnant == null:
		return
	var place := "station_skimmer_east"
	await _woke(s)
	await _kill_all(s.remnant.troopers)
	assert_eq(Territory.owner(place), Territory.REMNANT, "cleared, not yet taken")
	assert_gte(s.remnant.cleared_at, 0.0)
	WorldState.clock += Territory.n("move_in_s", 45.0) + 1.0
	_rules(s, s.to_world(Vector3(25, 1, 0)))
	assert_eq(Territory.owner(place), Territory.REMNANT, "not while you are aboard")
	# Far off and out of sight it swaps: as the tick does once you have gone.
	Territory.take(place)
	s.remnant.cleared_at = -1.0
	s.remnant.reset_people()
	await _woke(s)
	assert_eq(s.remnant.held_by, Territory.LOCALS)
	for i in 600:
		await wait_physics_frames(1)
		if not s.remnant.guards.is_empty() and s.remnant._queue.is_empty():
			break
	assert_false(s.remnant.guards.is_empty(), "the locals' guards stand the posts")
	var roof: float = s.hull.floor_h + s.hull.plate
	assert_eq(s.remnant.guards.filter(func(g): return s.to_local_point(g.global_position).y > roof - 0.5).size(), 1, "one on the roof")
	await _kill_all(s.remnant.guards)
	Territory.tick(1.0)
	assert_eq(Territory.owner(place), Territory.REMNANT, "their guards dead, the Remnant have it back")


func test_supplies_are_handed_over_aboard_a_short_skimmer() -> void:
	var t = _host()
	var s = await _outpost(t, "skimmer_east")
	assert_not_null(s)
	if s == null or s.remnant == null:
		return
	var place := "station_skimmer_east"
	Territory.take(place)
	WorldState.control[place].hold = 60.0
	assert_true(Territory.start_supply(), "carrying the load")
	_rules(s, s.to_world(Vector3(0, 0, 400)))
	assert_eq(s.remnant.supplied, 0, "nothing handed over from out in space")
	var p = t._player
	p.global_position = s.to_world(Vector3(25, 1.0, 0))
	await wait_physics_frames(2)
	_rules(s, p.global_position)
	assert_eq(s.remnant.supplied, 1, "handed over aboard")
	assert_almost_eq(Territory.hold_left(place), Territory.n("hold_s", 0.0), 0.01, "a full hold")


## A trooper's gun lies where he fell, on the deck turned 52 degrees with the ball
## (Ragdoll.drop along the ground's down; with world gravity it slid away across the
## walkway and out of the bay).
func test_a_dead_troopers_gun_lies_on_the_deck_where_he_fell() -> void:
	GameFlow.reset()
	GameFlow.resumed = true
	GameFlow.planet_id = HOST
	GameFlow.change_scene = func(_p: String) -> void: pass
	var t = TownDemo.new()
	t.use_look = true                    # the gun is the look's
	t.npc_brains = false
	add_child_autofree(t)
	var s = await _outpost(t, "skimmer_east")
	assert_not_null(s)
	if s == null or s.remnant == null:
		return
	await _woke(s)
	var walkers: Array = s.remnant.troopers.filter(func(g): return is_instance_valid(g) and str(g.name).contains("_patrol_"))
	assert_false(walkers.is_empty(), "a trooper walking the walkway")
	if walkers.is_empty():
		return
	var g = walkers[0]
	var fell: Vector3 = s.to_local_point(g.global_position)
	assert_lt(g.tilt.y.angle_to(s.frame.basis.y), 0.01, "he stands along the deck's up, though asleep far off")
	g.apply_damage(100000.0)
	await wait_seconds(4.0)
	var w = g.dropped_weapon
	assert_true(w != null and is_instance_valid(w), "he dropped his gun")
	if w == null or not is_instance_valid(w):
		return
	var at: Vector3 = s.to_local_point(w.global_position)
	assert_between(at.y, 0.0, 0.6, "on the deck (%s)" % at)
	assert_lt(Vector2(at.x - fell.x, at.z - fell.z).length(), 2.5, "by him, not slid off across the deck (%s, he fell at %s)" % [at, fell])
	assert_lt(w.linear_velocity.length(), 0.1, "and still")
