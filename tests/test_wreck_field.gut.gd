extends GutTest
## Wreck field: three more crashed starcruisers, spread round the whole ball (one on
## its far side), each lying its own way (heading, dive, list and how deep in the
## sand) with its decks, ramps and bridge fitted to that pose, and otherwise barely
## different from the original; the same crew aboard each, back three minutes after
## they fall or as soon as you are 500 ft away; a supply crate with a random prize
## on every wreck's bridge platform, the original's too.
## Pure WorldGround queries on the analytic planet, plus small scenes.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const IDS := ["starcruiser_wreck", "starcruiser_wreck_2", "starcruiser_wreck_3", "starcruiser_wreck_4"]

var _old_current: PlanetSphere
var _sp: PlanetSphere
var g: WorldGround
var _wrecks: Array = []


func before_each() -> void:
	WorldState.reset()
	_old_current = PlanetSphere.current
	_sp = PlanetSphere.new(5000.0)
	_sp.configure_site(Rect2(-200, -200, 400, 400), Rect2(-210, -210, 420, 420), [], 0.0)
	PlanetSphere.current = _sp
	var world: Dictionary = ItemKit._read_json("res://content/core/worlds/port_desert.json")
	_wrecks = world.landmarks.filter(func(lm): return str(lm.kind) == "wreck")
	g = WorldGround.new()
	g.setup({ "terrain": { "sphere_radius": 5000.0 }, "landmarks": _wrecks }, null, null)


func after_each() -> void:
	PlanetSphere.current = _old_current
	WorldState.reset()


func _lv(id: String, x: float, v: float, w: float) -> Vector3:
	return StarcruiserWreck.site_point(g, Vector3(x, v, w), "level", id)


## Same as test_crash_site's: floor under every step, nothing at the waist or head.
func _walkable(points: Array) -> String:
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 0.5))
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			var up := g.up_at(p)
			var h := g.height_above(p + up)
			if absf(h - 1.0) > 0.4:
				return "no floor at leg %d step %d (%.2f m under the waist)" % [i, k, h]
			for lift in [1.0, 1.7]:
				var what := g.hit(p + up * lift, 0.35)
				if what != "":
					return "%s in the way at leg %d step %d" % [what, i, k]
	return ""


# ---- where they lie ---------------------------------------------------------------

func _lm(id: String) -> Dictionary:
	return _wrecks.filter(func(lm): return str(lm.id) == id)[0]


func _pose(id: String) -> StarcruiserWreck.Pose:
	var lm := _lm(id)
	return StarcruiserWreck.Pose.new(float(lm.pitch_deg), float(lm.get("variant", {}).get("deck_drop", 0.0)))


## The sand under a point (along the ball's radius), as a point on it.
func _sand(p: Vector3) -> Vector3:
	var m := _sp.world_to_map(p)
	return _sp.surface_at(m.x, m.y)


func test_the_wrecks_lie_all_round_the_ball() -> void:
	assert_eq(_wrecks.size(), 4, "the original and three more")
	for id in IDS:
		assert_true(StarcruiserWreck.has_wreck(g, id), "%s is in the ground" % id)
	var dirs := {}
	for id in IDS:
		dirs[id] = (StarcruiserWreck.frame(g, id, "hull").origin - _sp.center).normalized()
	var round := func(id: String) -> float: return rad_to_deg(Vector3.UP.angle_to(dirs[id]))
	assert_lt(round.call(IDS[0]), 20.0, "the original still lies in sight of the port")
	var far := 0
	for id in IDS.slice(1):
		assert_gt(round.call(id), 50.0, "%s is far out round the ball" % id)
		if round.call(id) > 150.0:
			far += 1
	assert_eq(far, 1, "one on the far side of the planet")
	# Each off in its own direction from the port, not a line out one way.
	var headings := IDS.slice(1).map(func(id): return atan2(dirs[id].z, dirs[id].x))
	for i in headings.size():
		for j in range(i + 1, headings.size()):
			assert_gt(absf(angle_difference(headings[i], headings[j])), deg_to_rad(60.0), "two wrecks off the same way")


func test_far_apart() -> void:
	for i in IDS.size():
		var a := StarcruiserWreck.frame(g, IDS[i], "hull").origin
		for j in range(i + 1, IDS.size()):
			assert_gt(a.distance_to(StarcruiserWreck.frame(g, IDS[j], "hull").origin), 4000.0, "%s and %s far apart" % [IDS[i], IDS[j]])


func test_each_wreck_lies_its_own_way() -> void:
	var pitches := {}
	var rolls := {}
	for lm in _wrecks:
		pitches[float(lm.get("pitch_deg", StarcruiserWreck.PITCH_DEG))] = true
		rolls[float(lm.get("roll_deg", 0.0))] = true
	assert_eq(pitches.size(), 4, "each dives at its own angle")
	assert_eq(rolls.size(), 4, "and lists its own way")
	var flat := 0
	var sunk := 0
	var listing := 0
	for id in IDS:
		var lm := _lm(id)
		var hull := func(x, y, z): return StarcruiserWreck.site_point(g, Vector3(x, y, z), "hull", id)
		var mid: Vector3 = hull.call(0, 0, 0)
		var keel: Vector3 = hull.call(0, -38, 0)
		if absf(float(lm.pitch_deg)) <= 10.0 and _sp.height_above_ground(keel) < 0.0 and _sp.height_above_ground(mid) > 0.0:
			flat += 1           # nearly level, resting on its belly
		if _sp.height_above_ground(mid) < 0.0:
			sunk += 1           # more than half its height under the sand amidships
			assert_lt(_sp.height_above_ground(hull.call(0, 38, 0)), 30.0, "%s: mostly sunken" % id)
		if absf(float(lm.get("roll_deg", 0.0))) >= 5.0:
			listing += 1
	assert_gte(flat, 1, "one lies flat on its belly")
	assert_gte(sunk, 1, "one is mostly sunk in the sand")
	assert_gte(listing, 2, "and some list onto a flank")


# ---- barely unique ----------------------------------------------------------------

## A part is the same on two wrecks if it is the same size and stands in the same
## place in the hull (plating, engines) or in the interior's frame (decks, ramps).
func test_each_wreck_is_barely_unique() -> void:
	var sets := {}
	for id in IDS:
		var parts := {}
		var hull_inv := StarcruiserWreck.frame(g, id, "hull").affine_inverse()
		var level_inv := StarcruiserWreck.frame(g, id, "level").affine_inverse()
		for b in g.boxes:
			if str(b.id).begins_with(id + "/"):
				var size := (b.max as Vector3).snapped(Vector3.ONE * 0.01)
				var xf := WorldGround.box_xf(b)
				parts[str(b.id).trim_prefix(id + "/")] = ["%s|%s" % [size, (hull_inv * xf).origin.snapped(Vector3.ONE * 0.05)],
					"%s|%s" % [size, (level_inv * xf).origin.snapped(Vector3.ONE * 0.05)]]
		sets[id] = parts
	var yaws := {}
	for lm in _wrecks:
		yaws[float(lm.yaw_deg)] = true
	assert_eq(yaws.size(), 4, "each lies on its own heading")
	for i in IDS.size():
		for j in range(i + 1, IDS.size()):
			var a: Dictionary = sets[IDS[i]]
			var b: Dictionary = sets[IDS[j]]
			var same := 0
			for k in a:
				if b.has(k) and (b[k][0] == a[k][0] or b[k][1] == a[k][1]):
					same += 1
			var total := maxi(a.size(), b.size())
			assert_lt(same, total, "%s and %s differ" % [IDS[i], IDS[j]])
			assert_gt(float(same) / total, 0.8, "%s and %s are nearly the same ship" % [IDS[i], IDS[j]])


## Wreck poses: whatever the pose, the decks, catwalks and ramps stay inside the
## hull, over its hold floor, and level with the horizon but for the wreck's list.
func test_every_wreck_interior_sits_inside_its_hull() -> void:
	const OUTSIDE := ["bridge_platform", "bridge_ramp", "lower_deck", "lower_deck_stern", "upper_gallery", "fallen_boarding_plate", "speeder_kicker"]
	for id in IDS:
		var inv := StarcruiserWreck.frame(g, id, "hull").affine_inverse()
		var level := StarcruiserWreck.frame(g, id, "level")
		var bad := []
		for b in g.boxes:
			var name := str(b.id).trim_prefix(id + "/")
			if not str(b.id).begins_with(id + "/") or b.kind != "floor" or name in OUTSIDE:
				continue
			var xf := WorldGround.box_xf(b)
			for k in 8:
				var c := Vector3(b.max.x if k & 1 else b.min.x, b.max.y if k & 2 else b.min.y, b.max.z if k & 4 else b.min.z)
				var h := inv * (xf * c)
				if absf(h.x) > _hull_half_width(h.y) + 1.2 or h.y < StarcruiserWreck.DECK_Y - 1.5 or absf(h.z) > 299.0:
					bad.append("%s %s" % [name, h.snapped(Vector3.ONE * 0.1)])
					break
			if name.ends_with("_deck") or name.ends_with("_catwalk") or name.ends_with("_ledge") or name.ends_with("_balcony"):
				assert_gt(xf.basis.y.normalized().dot(level.basis.y.normalized()), cos(deg_to_rad(1.0)), "%s %s is level in the interior" % [id, name])
		assert_eq(bad, [], "%s: the interior fits its hull" % id)


## The octagon's half-width (plating mid-line) at hull height y.
func _hull_half_width(y: float) -> float:
	var corner := Vector2(cos(PI / 4.0) * StarcruiserWreck.HULL_RX, sin(PI / 4.0) * StarcruiserWreck.HULL_RY)
	y = absf(y)
	if y <= corner.y:
		return StarcruiserWreck.HULL_RX - (StarcruiserWreck.HULL_RX - corner.x) * y / corner.y
	return corner.x * maxf(0.0, StarcruiserWreck.HULL_RY - y) / (StarcruiserWreck.HULL_RY - corner.y)


func test_every_wreck_crew_route_runs_on_a_floor() -> void:
	var dc: Dictionary = DroidRoster.config().wreck
	for site in dc.sites:
		var id := str(site.landmark)
		for name in dc.routes:
			if str(name) in site.get("skip_routes", []):
				continue
			var r: Dictionary = dc.routes[name]
			var pts: Array = r.points.map(func(p): return StarcruiserWreck.site_point(g, Vector3(p[0], p[1], p[2]), str(r.frame), id))
			pts.append(pts[0])
			assert_eq(_walkable(pts), "", "%s route %s" % [id, name])


## Wreck poses: on every wreck there is a way up from the hold (its floor, or the
## sand where the sand has buried it) to the landing pad: the stern ramp where the
## floor meets the starboard deck, else the climb ramp to the low balcony and the
## drop, ledge and stair up from it.
func test_every_wreck_has_a_way_up_from_the_hold_to_the_pad() -> void:
	const U := StarcruiserWreck.INTERIOR_V
	const M := StarcruiserWreck.MID_V
	const L := StarcruiserWreck.LOW_V
	const B := StarcruiserWreck.BRIDGE_V
	var kinds := {}
	for lm in _wrecks:
		var id := str(lm.id)
		var pose := _pose(id)
		var c := StarcruiserWreck._connectors(pose, lm.get("variant", {}))
		var lv := func(x, v, w): return _lv(id, x, v, w)
		var route: Array = []
		if c.has("stern"):
			kinds["stern"] = true
			var head: Vector3 = c.stern
			var step_on := Vector3(28, pose.v_at(StarcruiserWreck.DECK_Y, head.z - 0.5), head.z - 0.5)
			route = [
				# Up the hold floor beside the ramp (it overhangs the floor bow-ward of its head).
				StarcruiserWreck.site_point(g, Vector3(24, -24, 150), "hull", id),
				StarcruiserWreck.site_point(g, Vector3(24, -24, pose.hull(step_on).z), "hull", id),
				lv.call(step_on.x, step_on.y, step_on.z), lv.call(31, head.y, head.z),
				lv.call(33, U, 232), lv.call(30, U, 228), lv.call(30, U, 188), lv.call(30, U, 182),
			]
		else:
			assert_true(c.has("climb"), "%s has a way up" % id)
			kinds["climb"] = true
			var foot: Vector3 = c.climb
			var top := Vector3(StarcruiserWreck.CLIMB_X, L, 199.5)
			# From where the climb ramp leaves the floor, or comes up out of the sand.
			var t := 0.0
			while _sp.height_above_ground(_lv(id, foot.x, lerpf(foot.y, top.y, t), lerpf(foot.z, top.z, t))) < 0.3:
				t += 0.02
			assert_lt(t, 0.8, "%s: the climb ramp stands out of the sand" % id)
			var start := foot.lerp(top, t + 0.04)
			var lo: float = c.drop_lo
			var hi: float = c.drop_hi
			route = [
				lv.call(start.x, start.y, start.z), lv.call(top.x, top.y, top.z), lv.call(top.x, L, 203),
				lv.call(lo - 1.0, L, 203), lv.call(lo, L, 200.5), lv.call(hi, M, 176.5), lv.call(hi - 1.0, M, 172),
				lv.call(33, M, 170), lv.call(33, M, 152), lv.call(23, M, 152), lv.call(23, M, 154),
				lv.call(23, U, 178), lv.call(23, U, 182),
			]
		route.append_array([lv.call(0, U, 182), lv.call(0, U, 180), lv.call(0, B, 150), lv.call(0, B, 132)])
		assert_eq(_walkable(route), "", "%s: hold -> %s -> catwalk -> bridge ramp -> pad" % [id, "stern ramp" if c.has("stern") else "climb ramp, drop, stair"])
	assert_eq(kinds.size(), 2, "some climb by the stern ramp, some by the climb ramp")


## Wreck poses: where the sand has buried the breach's deck you walk in on the
## sand: the breach stands open over it, and there is no boarding plate.
func test_you_walk_into_a_sunken_wreck_over_the_sand() -> void:
	var sunk := 0
	for id in IDS:
		var hull := func(x, y, z): return StarcruiserWreck.site_point(g, Vector3(x, y, z), "hull", id)
		if _sp.height_above_ground(hull.call(33, StarcruiserWreck.DECK_Y, -35)) >= 0.0:
			assert_false(_box(id, "fallen_boarding_plate").is_empty(), "%s: a plate up to the breach" % id)
			continue
		sunk += 1
		assert_true(_box(id, "fallen_boarding_plate").is_empty(), "%s: no plate into the sand" % id)
		var route: Array = []
		for k in 86:
			route.append(_sand(hull.call(90.0 - k, 0, 0)))          # in through the breach
		for k in 121:
			route.append(_sand(hull.call(5.0, 0, float(k))))        # and aft along the sand inside
		assert_eq(_walkable(route), "", "%s: in through the breach on the sand" % id)
	assert_gte(sunk, 1, "one is sunk past its breach's deck")


func _box(id: String, name: String) -> Dictionary:
	for b in g.boxes:
		if str(b.id) == id + "/" + name:
			return b
	return {}


# ---- the crew ---------------------------------------------------------------------

func _droids() -> Array:
	WorldState.droids.wrecks_seeded = true
	var root := Node3D.new()
	add_child_autofree(root)
	var p := FakePlayer.new()
	root.add_child(p)
	var ctl := DroidController.new()
	ctl.setup(null, p, null)
	ctl.ground = g
	root.add_child(ctl)
	return [ctl, p]


func test_every_wreck_has_its_crew_and_only_the_first_its_hauler() -> void:
	var s := _droids()
	await wait_physics_frames(2)
	var ctl: DroidController = s[0]
	var dc: Dictionary = DroidRoster.config().wreck
	for site in dc.sites:
		var id := str(site.landmark)
		var want: Array = (dc.units as Array).filter(func(u): return not (str(u.route) in site.get("skip_routes", [])))
		var crew: Array = ctl.remnant.filter(func(u): return str(u.spec.get("site", "")) == id)
		assert_eq(crew.size(), want.size(), "%s is manned" % id)
		assert_eq(crew.filter(func(u): return str(u.spec.route) == "pad").size(), 2, "%s: assassins on its pad" % id)
	assert_eq(str(ctl.wreck_hauler.spec.site), IDS[0], "the saber's hauler stays on the original")


func test_a_fallen_wreck_droid_is_back_after_three_minutes() -> void:
	var s := _droids()
	await wait_physics_frames(2)
	var ctl: DroidController = s[0]
	var p: FakePlayer = s[1]
	var u = ctl.remnant.filter(func(x): return str(x.spec.get("site", "")) == IDS[2])[0]
	p.global_position = u.global_position + g.up_at(u.global_position) * 30.0   # near: no walk-away
	ctl.on_unit_hit(u, 9999.0, null)
	assert_true(u.dead)
	assert_almost_eq(u.respawn_left, 180.0, 0.01, "three minutes")
	ctl._tick_remnant_respawns(179.0)
	assert_true(is_instance_valid(u) and ctl.remnant.has(u), "still down at 2:59")
	ctl._tick_remnant_respawns(1.5)
	assert_false(ctl.remnant.has(u), "gone from the list")
	var back: Array = ctl.remnant.filter(func(x): return str(x.spec.get("site", "")) == IDS[2] and not x.dead)
	assert_eq(back.size(), ctl.remnant.filter(func(x): return str(x.spec.get("site", "")) == IDS[2]).size(), "back on its route")


func test_a_fallen_wreck_droid_is_back_once_you_walk_500_feet_away() -> void:
	var s := _droids()
	await wait_physics_frames(2)
	var ctl: DroidController = s[0]
	var p: FakePlayer = s[1]
	var u = ctl.remnant.filter(func(x): return str(x.spec.get("site", "")) == IDS[1])[0]
	var at: Vector3 = u.global_position
	var up := g.up_at(at)
	p.global_position = at + up * 10.0
	ctl.on_unit_hit(u, 9999.0, null)
	assert_true(u.dead)
	ctl._tick_remnant_respawns(1.0)
	assert_true(ctl.remnant.has(u), "you are still close: it stays down")
	p.global_position = u.global_position + up * 140.0
	ctl._tick_remnant_respawns(1.0)
	assert_true(ctl.remnant.has(u), "140 m is not 500 ft")
	p.global_position = u.global_position + up * 160.0
	ctl._tick_remnant_respawns(1.0)
	assert_false(ctl.remnant.has(u), "500 ft away: it is back on its route")


# ---- the prize crates -------------------------------------------------------------

func test_a_supply_crate_stands_on_every_bridge_platform() -> void:
	var content = CoreScript.new()
	content.load_from()
	var crates: Array = content.get_site_crates("port_town")
	var sites := {}
	for c in crates:
		sites[str(c.site)] = true
		var pt: Array = c.site_point
		assert_almost_eq(float(pt[1]), StarcruiserWreck.BRIDGE_V, 0.01, "%s is on the top deck" % c.id)
		var at := StarcruiserWreck.site_point(g, Vector3(pt[0], pt[1], pt[2]), "level", str(c.site))
		var up := g.up_at(at)
		assert_almost_eq(g.height_above(at + up), 1.0, 0.3, "%s sits on the platform" % c.id)
		assert_eq(g.hit(at + up * 1.0, 0.6), "", "%s is not inside anything" % c.id)
	for id in IDS:
		assert_true(sites.has(id), "a crate on %s, the original too" % id)
	var kinds := {}
	for e in content.get_crate_prizes("port_town"):
		kinds["credits" if e.has("credits") else str(e.item)] = e.get("credits", e.get("count", 0))
	assert_true(content.get_crate_prizes("port_town").any(func(e): return int(e.get("credits", 0)) == 300), "300 credits")
	assert_eq(int(kinds.get("food", 0)), 10, "10 food")
	assert_eq(int(kinds.get("refined_quantonium", 0)), 5, "5 refined quantonium")


func _gear() -> Array:
	var root := Node3D.new()
	add_child_autofree(root)
	var p := FakePlayer.new()
	root.add_child(p)
	var gear := GearController.new()
	gear.setup(null, null, p, null, "port_town")
	gear.ground = g
	root.add_child(gear)
	gear.set_physics_process(false)    # interact() by hand, as the trace does
	return [gear, p]


func test_opening_a_crate_gives_its_prize_once() -> void:
	var s := _gear()
	var gear: GearController = s[0]
	var p: FakePlayer = s[1]
	var crates: Array = gear.pickups.filter(func(n): return bool(n.pickup.get("crate", false)))
	assert_eq(crates.size(), 4, "one on every wreck")
	var crate = crates[2]
	var cid := str(crate.pickup.id)
	p.global_position = crate.base + g.up_at(crate.base) * 0.2 + crate.basis.x * 1.0
	gear.focus = gear._find_focus()
	assert_eq(gear.prompt_text(), gear._l("open_crate"))
	crate.pickup["prize"] = { "credits": 300 }
	var cr0 := WorldState.credits
	assert_eq(gear.interact(), "opened")
	assert_eq(WorldState.credits, cr0 + 300, "300 credits")
	assert_true(WorldState.inventory.is_taken(cid), "it stays open")
	assert_false(gear.pickups.has(crate))
	# And another: goods.
	var c2 = gear.pickups.filter(func(n): return bool(n.pickup.get("crate", false)))[0]
	c2.pickup["prize"] = { "item": "refined_quantonium", "count": 5 }
	p.global_position = c2.base + g.up_at(c2.base) * 0.2
	gear.focus = {}
	assert_eq(gear.interact(), "opened")
	assert_eq(WorldState.inventory.count("refined_quantonium"), 5, "5 refined quantonium")
	# Opened crates are not put out again.
	var again := _gear()
	var left: Array = (again[0] as GearController).pickups.filter(func(n): return bool(n.pickup.get("crate", false)))
	assert_eq(left.size(), 2)


func test_the_prize_is_rolled_from_the_table() -> void:
	var s := _gear()
	var gear: GearController = s[0]
	gear.rng.seed = 7
	var seen := {}
	for i in 200:
		var pr := gear.roll_crate_prize()
		assert_false(pr.is_empty())
		seen["credits:%d" % int(pr.credits) if pr.has("credits") else str(pr.item)] = true
	assert_gte(seen.size(), 4, "it varies")


class FakePlayer extends CharacterBody3D:
	var piloting := false
	var locked := false
	var jetpack = null
