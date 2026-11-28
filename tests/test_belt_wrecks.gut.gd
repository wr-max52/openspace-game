extends GutTest
## Issue #317: three wrecked cruisers hanging in the belt under the ring station,
## stacked one under another 50 to 100 m apart and never touching, each at its own
## heading, dive and list, the first nose down like the home planet's nearest wreck
## with its bow in the clouds (BeltWrecks, the station's "belt" block). You go down
## on foot through the engine deck's drop hatch and from wreck to wreck with a
## jetpack burn (every drop can be landed, worked out from the jetpack's own
## numbers), and back up by calling your ship to a pad. The station's up holds
## over them; each has the desert wrecks' crew (and more on its spine, the deeper
## the more), a crate that pays better the deeper it is and stray loot. Fall off
## a side, or into the clouds, and the belt has you.

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


# ------------------------------------------------------------------ the stack

func _falls() -> Dictionary:
	return CoreScript.read_json("res://content/core/flow/falls.json")


func test_three_wrecks_stacked_each_50_to_100_m_under_the_last() -> void:
	var h := _hull()
	var ws := BeltWrecks.layout(h)
	assert_eq(ws.map(func(w): return w.id), WRECKS)
	var hatch := h.drop_hatch()
	assert_false(hatch.is_empty(), "the engine deck has its drop hatch")
	var p0: Vector3 = ws[0].pad
	assert_almost_eq(Vector2(p0.x, p0.z).distance_to(Vector2(hatch.at.x, hatch.at.z)), 0.0, 0.01, "the first pad straight under the hatch")
	for d in BeltWrecks.drops(h):
		assert_between(float(d.drop), 50.0, 100.0, "%s: 50 to 100 m" % d.what)
	var poses := {}
	for w in ws:
		poses["%d/%d/%d" % [int(w.spec.get("yaw_deg", 0)), int(w.spec.get("pitch_deg", 0)), int(w.spec.get("roll_deg", 0))]] = true
		for k in ["yaw_deg", "pitch_deg", "roll_deg"]:
			var same := ws.filter(func(o): return float(o.spec.get(k, 0.0)) == float(w.spec.get(k, 0.0)))
			assert_eq(same.size(), 1, "%s: its own %s" % [w.id, k])
	assert_eq(float(ws[0].spec.pitch_deg), StarcruiserWreck.PITCH_DEG, "the first dives like the home planet's nearest wreck")


func test_no_two_wrecks_touch() -> void:
	var h := _hull()
	var ws := BeltWrecks.layout(h)
	var need := float(BeltWrecks.cfg_of(h).clearance_m)
	for i in ws.size():
		for j in range(i + 1, ws.size()):
			assert_gt(BeltWrecks.gap_between(ws[i], ws[j]), need, "%s and %s keep apart" % [ws[i].id, ws[j].id])
	var g := _ground()
	var fr := StationHull.frame(g, ID)
	for w in ws:
		var inside := 0
		for b in g.boxes:
			if not b.has("wreck_finish") or str(b.id).begins_with(str(w.id) + "/"):
				continue
			var c: Vector3 = fr.affine_inverse() * (WorldGround.box_xf(b) * (((b.min as Vector3) + (b.max as Vector3)) * 0.5))
			if BeltWrecks.in_wreck([w], c):
				inside += 1
		assert_eq(inside, 0, "nothing of another wreck inside %s" % w.id)
	for b in g.boxes:
		if b.has("wreck_finish"):
			var c: Vector3 = fr.affine_inverse() * (WorldGround.box_xf(b) * (((b.min as Vector3) + (b.max as Vector3)) * 0.5))
			if h.aboard(c):
				fail_test("%s is inside the station" % b.id)
				return


func test_every_drop_can_be_landed_with_a_jetpack_burn_and_not_without() -> void:
	var h := _hull()
	var falls := _falls()
	assert_eq(BeltWrecks.too_hard(h, _jet(), falls), [], "a full tank lands every drop")
	for d in BeltWrecks.drops(h):
		var bare := minf(sqrt(2.0 * BeltWrecks.GRAVITY * float(d.drop)), float(falls.terminal_speed))
		assert_gte(BeltWrecks.FallDamage.damage(bare, falls), int(falls.lethal_damage), "%s kills you without the pack" % d.what)
	var weak := _jet().duplicate()
	weak["fuel"] = 0.4
	assert_gt(BeltWrecks.too_hard(h, weak, falls).size(), 0, "a jetpack change that cannot land them fails")


func test_the_pads_stand_and_open_to_the_sky() -> void:
	var g := _ground()
	var h := _hull()
	var fr := StationHull.frame(g, ID)
	var ws := BeltWrecks.layout(h)
	var bc := BeltWrecks.cfg_of(h)
	for i in ws.size():
		var p: Vector3 = ws[i].pad
		assert_almost_eq(g.height_above(fr * (p + Vector3(0, 1, 0))), 1.0, 0.3, "%s: its pad stands where the layout says" % ws[i].id)
		assert_gt(p.y, float(bc.clouds_y) + 40.0, "%s: its pad is well over the clouds" % ws[i].id)
		if i > 0:
			assert_true(BeltWrecks.pad_open(h, ws, i), "%s: a ship can come straight down onto its pad" % ws[i].id)
		var pw: Vector3 = fr * p
		var m := g.sphere().world_to_map(pw)
		assert_gt(g.sphere().altitude(pw) - g.sphere().altitude(g.sphere().surface_at(m.x, m.y)), 10.0,
			"%s: its pad is over the giant's surface (what a ship reads as ground)" % ws[i].id)
	var hatch: Vector3 = h.drop_hatch().at
	assert_almost_eq(g.height_above(fr * (hatch + Vector3(0, 1, 0))), 1.0 + hatch.y - (ws[0].pad as Vector3).y, 0.5,
		"from the hatch nothing until the first pad")
	var beside: Vector3 = hatch + (h.drop_hatch().xf as Transform3D).basis.x * 3.5
	assert_almost_eq(g.height_above(fr * (beside + Vector3(0, 1, 0))), 1.0, 0.05, "and the floor round the hole stands")
	# The first one's bow, nose down, sinks into the clouds as the home one's does into the sand.
	var bow: Vector3 = (ws[0].xf as Transform3D) * Vector3(0, 0, -StarcruiserWreck.HALF_LENGTH)
	assert_lt(bow.y, float(bc.clouds_y), "the first one's bow is down in the clouds")


func test_the_station_holds_its_up_over_every_wreck() -> void:
	var g := _ground()
	var fr := StationHull.frame(g, ID)
	for w in BeltWrecks.layout(_hull()):
		for at_l in [(w.pad as Vector3) + Vector3(0, 2, 0), (w.xf as Transform3D) * Vector3(0, 41, 250)]:
			assert_almost_eq(g.up_at(fr * at_l).dot(fr.basis.y), 1.0, 0.0001, "%s: the station's up, not the ball's" % w.id)


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


func test_the_dock_path_never_goes_under_the_towers_into_the_wrecks() -> void:
	var h := _hull()
	var path := h.dock_path(Vector3(500, -90, 50))
	assert_gt((path[0] as Vector3).y, h.top_y(), "from below it climbs over the towers")


## The height over the wrecks' and the station's boxes alone at world point `p`
## (what the colliders hold you on). The giant's ball reads as ground for ships
## about 200 m under the station, and the deep wrecks' holds hang below that.
func _box_height(g: WorldGround, p: Vector3) -> float:
	var up := g.up_at(p)
	var h := INF
	for b in g.boxes:
		if b.has("wreck_finish") or b.has("station_frame"):
			h = minf(h, WorldGround.box_height_below(b, p, up))
	return h


func _box(g: WorldGround, id: String) -> Dictionary:
	for b in g.boxes:
		if str(b.id) == id:
			return b
	return {}


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
				var ha := _box_height(g, at + g.up_at(at) * 3.0)
				assert_between(ha, 1.5, 4.5, "%s route %s: a floor under %s" % [id, name, str(pt)])
				assert_gt((fr.affine_inverse() * at).y, float(BeltWrecks.cfg_of(_hull()).clouds_y), "%s route %s: over the clouds" % [id, name])


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
		assert_between(_box_height(g, at + g.up_at(at) * 2.0), 0.4, 3.6, "%s lies on a floor" % str(n.pickup.id))
		assert_gt((StationHull.frame(g, ID).affine_inverse() * at).y, float(BeltWrecks.cfg_of(_hull()).clouds_y), "%s is over the clouds" % str(n.pickup.id))
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


## Fall from station point `from` (still) onto whatever is under it, holding jump
## from the best height over `floor_y` (BeltWrecks.best_burn): the landing a player
## who times the burn gets. Returns the damage taken.
func _drop_and_burn(s, p, from: Vector3, floor_y: float) -> int:
	_put(s, p, from)
	p.jetpack.refill()
	var burn := BeltWrecks.best_burn(from.y - floor_y, _jet())
	var hp0: int = p.health.hp
	var landed := false
	for i in 900:
		var l: Vector3 = s.inv * p.global_position
		var hold: bool = l.y - floor_y <= burn.x
		p.set_command(Vector2.ZERO, false, false, false, hold)
		await wait_physics_frames(1)
		if i > 5 and _on(p):
			landed = true
			break
	p.set_command(Vector2.ZERO, false, false, false, false)
	assert_true(landed, "landed")
	return hp0 - int(p.health.hp)


func test_down_through_the_hatch_and_from_wreck_to_wreck_with_the_jetpack() -> void:
	var t = _host()
	var s = await _station(t)
	if s == null:
		fail_test("no station")
		return
	assert_true(s.frame.basis.is_equal_approx(Basis.IDENTITY), "the station is level and unturned here")
	assert_eq(s.belt.size(), 3, "the station knows its belt")
	var p = t._player
	_wear_jetpack(t)
	var cap := int(BeltWrecks.cfg_of(s.hull).landing.max_damage)
	var hatch: Dictionary = s.hull.drop_hatch()
	var hat: Vector3 = hatch.at
	var ws: Array = s.belt
	# 1. Through the hatch: from the floor beside it, step on and drop, burning for the pad.
	_put(s, p, hat - (hatch.xf as Transform3D).basis.x * 3.5 + Vector3(0, 0.2, 0))
	await wait_physics_frames(10)
	assert_true(s.aboard(p.global_position), "in the cargo hold")
	await _drive(s, p, hat, 240, false, func(l): return l.y < hat.y - 3.0)
	var pad1: Vector3 = ws[0].pad
	var dmg := await _drop_and_burn(s, p, s.inv * p.global_position, pad1.y)
	var l: Vector3 = s.inv * p.global_position
	assert_almost_eq(l.y, pad1.y, 1.5, "down through the hatch onto the first wreck's pad")
	assert_lte(dmg, cap, "a soft landing with the burn (%d damage)" % dmg)
	assert_eq(s.falls, 0, "not pulled back: over the belt the pull is off")
	# 2. And on down: from the height of each pad, out over the next one, drop and burn.
	for i in range(1, 3):
		var up: Vector3 = ws[i - 1].pad
		var down: Vector3 = ws[i].pad
		dmg = await _drop_and_burn(s, p, Vector3(down.x, up.y + 1.0, down.z), down.y)
		l = s.inv * p.global_position
		assert_almost_eq(l.y, down.y, 1.5, "dropped from %s's height onto %s's pad" % [ws[i - 1].id, ws[i].id])
		assert_lte(dmg, cap, "and lived (%d damage)" % dmg)
	assert_eq(s.belt_falls, 0, "alive all the way down")
	assert_false(p.is_downed)


func test_call_your_ship_down_to_the_deepest_wreck() -> void:
	WorldState.hangar = "courier"          # a ship of your own, parked in the bay
	var t = _host()
	var s = await _station(t)
	if s == null:
		fail_test("no station")
		return
	var p = t._player
	var pilot: ShipPilot = t.pilot
	var pad3: Vector3 = s.belt[2].pad
	_put(s, p, pad3 + Vector3(-9, 0.5, 0))
	await wait_physics_frames(20)
	assert_true(_on(p), "standing on the last wreck's pad")
	assert_eq(pilot.call_ship(), "", "your ship is on her way")
	for i in 60 * 60:
		if not pilot.calling:
			break
		await wait_physics_frames(1)
	assert_false(pilot.calling, "she came")
	assert_eq(pilot.atmo.state, AtmoFlight.State.PARKED, "and set down")
	var at: Vector3 = s.inv * pilot.atmo.position()
	assert_lt(Vector2(at.x - pad3.x, at.z - pad3.z).length(), 30.0, "by you on the wreck")
	assert_almost_eq(at.y - pilot.atmo.clearance, pad3.y, 2.0, "on its pad")
	assert_eq(s.belt_falls, 0)


func test_off_the_side_and_the_belt_has_you() -> void:
	var t = _host()
	var s = await _station(t)
	if s == null:
		fail_test("no station")
		return
	var p = t._player
	var w: Dictionary = s.belt[2]
	var on: Vector3 = (w.pad as Vector3) + Vector3(0, 0.5, 0)
	_put(s, p, on)
	for i in 60:
		await wait_physics_frames(1)
		if _on(p):
			break
	assert_true(_on(p), "standing on the last wreck's pad")
	var log_before := WorldState.events.size()
	# Out past its flank, then let go.
	var side: Vector3 = (w.xf as Transform3D).basis.x
	side = Vector3(side.x, 0, side.z).normalized()
	_put(s, p, on + side * 62.0)
	for i in 300:
		await wait_physics_frames(1)
		if s.belt_falls > 0:
			break
	assert_eq(s.belt_falls, 1, "fell into the belt")
	assert_true(s.aboard(p.global_position), "and woke in the station's bay")
	assert_true(t.gear.hud.toast_label.text.begins_with(str(BeltWrecks.cfg_of(s.hull).lines.fell)), "with the belt's line")
	assert_gt(WorldState.events.size(), log_before, "and the world remembers it")
