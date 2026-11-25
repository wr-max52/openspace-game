extends GutTest
## Issue #497: who crews the cruiser once it is taken, without a scene. Its own
## crew before it falls; the locals on the bay and the bridge once the dark master
## has left it; his Remnant on the same posts, on your side, on his oath; nobody
## while he is aboard. The holders lend you a bay ship, and the holo shows who
## holds it.

const BAY_Y := -14.0
const CoreContent := preload("res://src/systems/dataload/core_content.gd")


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()


func _cruiser() -> RemnantCruiser:
	var c := RemnantCruiser.new()
	c.cfg_id = CruiserHull.HOME_ID
	c.cfg = CruiserHull.data_for(CruiserHull.HOME_ID)
	c.id = str(c.cfg.get("id", c.id))
	autofree(c)
	return c


## Taken in story mode, the dark master dead aboard: the locals' turn.
func _taken_he_is_dead() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("fleet")
	WorldState.on_cruiser_taken("General Test", CruiserHull.data().get("reward", {}))
	DarkPact.refuse()
	DarkPact.on_killed("cruiser")


func _faction(soldier: String) -> String:
	var cc := CoreContent.new()
	cc.load_from()
	return str(cc.get_soldier(soldier).get("faction", ""))


## The bay (its deck, from the bow wall to the corridor door) or the bridge.
func _bay_or_bridge(at: Vector3) -> bool:
	var bay := absf(at.y - BAY_Y) < 0.5 and at.z >= CruiserHull.BAY_Z.x and at.z <= CruiserHull.BAY_Z.y
	var bridge := at.y >= CruiserHull.BRIDGE_Y - 4.0 and at.z >= CruiserHull.BRIDGE_Z.x - 10.0 and at.z <= CruiserHull.BRIDGE_Z.y
	return bay or bridge


func test_before_it_falls_the_crew_is_unchanged() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("fleet")
	var c := _cruiser()
	assert_eq(c.holder(), "remnant")
	assert_eq(c.crew_plan().size(), (c.cfg.crew as Array).size(), "every crew post")
	assert_eq(c.crew_plan().size(), 25)
	assert_true(c.crew_always_hostile(), "the Remnant crew shoot on sight")
	assert_eq(RemnantCruiser.home_holder(), Territory.REMNANT)


func test_the_locals_crew_it_once_he_is_gone() -> void:
	_taken_he_is_dead()
	var c := _cruiser()
	assert_eq(c.holder(), "locals")
	var plan := c.crew_plan()
	assert_between(plan.size(), 6, 8, "a handful of posts")
	for p in plan:
		assert_eq(_faction(str(p.soldier)), "locals", "%s is a local" % p.soldier)
		assert_true(_bay_or_bridge(WorldGround._v3(p.at)), "post %d is in the bay or on the bridge" % int(p.post))
	assert_false(c.crew_always_hostile(), "they go by your standing with the locals")
	WorldState.standing["locals"] = 40
	assert_eq(c.lender(), "locals", "a friend borrows a bay ship")
	WorldState.standing["locals"] = 0
	assert_eq(c.lender(), "", "anyone else steals it")
	assert_eq(RemnantCruiser.home_holder(), Territory.LOCALS)


func test_nobody_while_he_is_aboard() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("fleet")
	WorldState.on_cruiser_taken("General Test", CruiserHull.data().get("reward", {}))
	assert_true(DarkPact.on_cruiser(), "he waits to make his offer")
	var c := _cruiser()
	assert_eq(c.holder(), "", "nobody")
	assert_true(c.crew_plan().is_empty())


func test_on_the_oath_his_remnant_crew_it_on_your_side() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("fleet")
	WorldState.on_cruiser_taken("General Test", CruiserHull.data().get("reward", {}))
	DarkPact.join()
	var c := _cruiser()
	assert_eq(c.holder(), "oath")
	assert_eq(Territory.owner(Territory.BARRACKS), Territory.LOCALS, "the town is still the locals'")
	var plan := c.crew_plan()
	var locals_posts := (c.holder_cfg("locals").posts as Dictionary).keys().map(func(k): return int(k))
	for p in plan:
		assert_eq(_faction(str(p.soldier)), "imperial_remnant", "%s is Remnant" % p.soldier)
		assert_has(locals_posts, int(p.post), "the same posts as the locals'")
	assert_false(c.crew_always_hostile())
	assert_false(Story.remnant_hostile(), "on your side")
	assert_eq(c.lender(), "imperial_remnant", "your own side lends you a ship")
	assert_eq(RemnantCruiser.home_holder(), Territory.REMNANT)


func test_breaking_the_oath_empties_it_until_he_dies_then_the_locals() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("fleet")
	WorldState.on_cruiser_taken("General Test", CruiserHull.data().get("reward", {}))
	DarkPact.join()
	DarkPact.break_oath()
	var c := _cruiser()
	assert_eq(c.holder(), "", "he is back aboard as an enemy")
	DarkPact.on_killed("cruiser")
	assert_eq(c.holder(), "locals")


func test_the_holo_shows_the_locals_holding_it() -> void:
	var holo := CruiserHolo.new()
	holo.spec = CruiserHull.data_for(CruiserHull.HOME_ID).get("holo", {})
	autofree(holo)
	WorldState.new_game(WorldState.STORY)
	var remnant_col := holo.owner_color(CruiserHolo.CRUISER)
	_taken_he_is_dead()
	var locals_col := holo.owner_color(CruiserHolo.CRUISER)
	assert_eq(locals_col, Color(str(holo.spec.owner_colors.locals)), "the locals' colour")
	assert_ne(locals_col, remnant_col)
	var row: Dictionary = GlobeMap.off_planet([], ItemKit._read_json("res://content/core/worlds/port_desert.json")).filter(
		func(o): return str(o.kind) == "cruiser").front()
	assert_eq(str(row.owner), Territory.LOCALS, "and the Map page's cruiser row")
