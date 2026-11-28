extends GutTest
## Issue #838: the belt's front (content/core/story/territory.json "fronts" "belt";
## territory.gd, pure): the belt cruiser locks the station city's Remnant deck (its
## barracks), the barracks stop the skimmer outposts' clocks. Before that a skimmer
## the locals take runs on the home world's clock, a supply run fills it, and when it
## runs out the Remnant have it back; after, they keep it, and the Remnant's run down.

const F := "belt"
const EAST := "station_skimmer_east"
const NW := "station_skimmer_northwest"
const SW := "station_skimmer_southwest"
const DECK := "station_orbital_station"


func before_each() -> void:
	WorldState.new_game(WorldState.FREEPLAY)


func after_each() -> void:
	GameFlow.planet_id = ""


func after_all() -> void:
	WorldState.reset()


func _barracks_to_locals() -> void:
	WorldState.control[DECK] = { "owner": Territory.LOCALS }


func test_the_front_is_the_belts() -> void:
	assert_eq(Territory.front_for_planet("ringed_giant"), F, "the giant's front")
	assert_eq(Territory.outposts(F), [EAST, NW, SW], "its three skimmers")
	assert_eq(Territory.barracks_of(F), DECK, "the station city's Remnant deck is its barracks")
	for id in Territory.outposts(F) + [DECK]:
		assert_eq(Territory.owner(id), Territory.REMNANT, "%s starts the Remnant's" % id)
		assert_eq(Territory.front_of(id), F)
	assert_ne(Story.outpost_label(EAST), EAST, "a skimmer goes by its name in a line")
	assert_eq(Territory.places().filter(func(p): return str(p) == EAST).size(), 1, "and is one of the places")


func test_the_belt_cruiser_locks_the_barracks() -> void:
	assert_true(Territory.station_locked(DECK), "the cruiser stands: clearing the deck hands nothing over")
	assert_false(Territory.station_locked(EAST), "the skimmers are not locked")
	assert_false(Territory.locked(EAST), "a skimmer can be cleared any time")
	WorldState.set_flag("belt_cruiser_taken")
	assert_false(Territory.station_locked(DECK), "the cruiser fallen, the deck can be taken")


func test_a_skimmer_runs_on_the_home_worlds_clock_till_the_barracks_fall() -> void:
	Territory.take(EAST)
	assert_eq(Territory.owner(EAST), Territory.LOCALS)
	assert_almost_eq(Territory.hold_left(EAST), Territory.n("hold_s", 0.0), 0.01, "a full hold")
	assert_true(Territory.locals_clocked(F))
	assert_between(Territory.hold_frac(EAST), 0.99, 1.0, "the map shows its clock")
	Territory.tick(Territory.n("hold_s", 0.0) - Territory.n("supply_warn_s", 0.0) + 1.0)
	assert_true(Territory.short(EAST), "running short")
	assert_true(WorldState.has_flag("outpost_short"), "the board knows")
	GameFlow.planet_id = "ringed_giant"
	assert_eq(Territory.supply_target(), EAST, "on the giant the supply run goes there")
	GameFlow.planet_id = ""
	Territory.tick(Territory.n("supply_warn_s", 0.0))
	assert_eq(Territory.owner(EAST), Territory.REMNANT, "out of time: the Remnant have it back")


func test_a_supply_run_fills_a_skimmers_clock() -> void:
	Territory.take(EAST)
	Territory.tick(Territory.n("hold_s", 0.0) - 100.0)
	GameFlow.planet_id = "ringed_giant"
	assert_true(Territory.start_supply(), "the station city's supply job")
	assert_eq(Territory.supply_out(), EAST)
	assert_true(Territory.can_deliver(EAST))
	var before := WorldState.credits
	var pay := Territory.deliver(EAST)
	assert_gt(pay, 0, "paid")
	assert_eq(WorldState.credits, before + pay)
	assert_almost_eq(Territory.hold_left(EAST), Territory.n("hold_s", 0.0), 0.01, "a full hold again")


func test_the_locals_guards_dying_hands_it_back_on_the_next_tick() -> void:
	Territory.take(EAST)
	Territory.guards_lost(EAST)
	assert_eq(Territory.owner(EAST), Territory.LOCALS, "still theirs this tick")
	Territory.tick(1.0)
	assert_eq(Territory.owner(EAST), Territory.REMNANT, "the Remnant move back in")


func test_with_the_barracks_theirs_the_locals_keep_what_they_hold() -> void:
	Territory.take(EAST)
	_barracks_to_locals()
	assert_false(Territory.locals_clocked(F), "the clocks stop")
	assert_lt(Territory.hold_frac(EAST), 0.0, "no clock on the map")
	WorldState.control[EAST].hold = 1.0
	Territory.tick(10.0)
	assert_eq(Territory.owner(EAST), Territory.LOCALS, "still theirs, though its old clock ran out")
	assert_false(Territory.short(EAST))
	assert_false(Territory.locals_locked(EAST), "but not for ever:")
	Territory.guards_lost(EAST)
	assert_eq(Territory.owner(EAST), Territory.REMNANT, "their guards dead, the Remnant have it at once")


func test_with_the_barracks_theirs_the_remnants_skimmers_run_short_and_give_up() -> void:
	_barracks_to_locals()
	assert_true(Territory.remnant_cut_off(F), "the Remnant on the belt are cut off")
	Territory.tick(1.0)
	assert_gt(Territory.hold_left(NW), 0.0, "their skimmers are on a clock")
	Territory.tick(Territory.rn("hold_s", 0.0) + 1.0)
	for id in Territory.outposts(F):
		assert_eq(Territory.owner(id), Territory.LOCALS, "%s gave up" % id)
	assert_true(Territory.driven_off(F), "and the Remnant are off the belt")


func test_holding_all_three_drives_the_remnant_off_the_belt() -> void:
	for id in Territory.outposts(F):
		Territory.take(id)
	assert_true(Territory.driven_off(F))
	assert_true(WorldState.has_flag("belt_remnant_driven_off"))
	Territory.tick(Territory.n("hold_s", 0.0) * 2.0)
	assert_eq(Territory.owner(EAST), Territory.LOCALS, "nothing runs out once they are gone")


func test_losing_the_barracks_starts_the_clocks_again() -> void:
	_barracks_to_locals()
	Territory.take(EAST)
	assert_false(Territory.locals_clocked(F))
	Territory.lose_station(DECK)
	assert_eq(Territory.owner(DECK), Territory.REMNANT, "the Remnant have the deck back")
	assert_true(Territory.locals_clocked(F), "and the skimmers' clocks run again")


func test_the_home_fronts_rules_are_unchanged() -> void:
	assert_true(Territory.locals_clocked(), "the port's locals are on a clock before the cruiser")
	Territory.take("remnant_outpost_near")
	assert_almost_eq(Territory.hold_left("remnant_outpost_near"), Territory.n("hold_s", 0.0), 0.01)
	assert_false(Territory.short("barracks"), "the barracks are never short")
	assert_false(Territory.clocked_by_barracks("moon"))
	assert_false(Territory.clocked_by_barracks("lava_moon"))
	assert_true(Territory.locked("remnant_outpost_lava_basalt"), "the lava moon's outposts still answer to the belt cruiser")


# ------------------------------------------------------------------ the supply run at the station city (issue #886)

func _short_skimmer() -> void:
	Territory.take(EAST)
	Territory.tick(Territory.n("hold_s", 0.0) - Territory.n("supply_warn_s", 0.0) + 1.0)


func _board_has_supply() -> bool:
	return WorldState.open_jobs("confidant").any(func(j): return str(j.id) == Territory.SUPPLY_JOB)


func test_the_station_citys_cantina_offers_the_skimmers_supply_run() -> void:
	_short_skimmer()
	GameFlow.planet_id = "ringed_giant"
	assert_true(_board_has_supply(), "the supplies card is on the station city's board")
	assert_eq(Territory.supply_target(), EAST, "naming the skimmer")
	assert_true(Territory.start_supply())
	var o := Objective.of("supply")
	assert_eq(str(o.get("target", "")), "outpost:" + EAST, "the pointer goes to the skimmer")
	assert_true(str(o.get("text", "")).contains(Story.outpost_label(EAST)), "by its name")


func test_the_ports_oda_keeps_to_the_desert() -> void:
	_short_skimmer()
	GameFlow.planet_id = ""
	assert_eq(Territory.supply_target(), "", "no desert outpost is short: Oda has no run")
	assert_false(_board_has_supply(), "and no card at the port for a skimmer")


func test_each_cantina_sends_you_to_its_own_planets_outpost() -> void:
	Territory.take("remnant_outpost_near")
	Territory.take(EAST)
	Territory.tick(Territory.n("hold_s", 0.0) - Territory.n("supply_warn_s", 0.0) + 1.0)
	GameFlow.planet_id = ""
	assert_eq(Territory.supply_target(), "remnant_outpost_near", "the port's Oda: the desert outpost")
	GameFlow.planet_id = "ringed_giant"
	assert_eq(Territory.supply_target(), EAST, "the station city's: the skimmer")


func test_no_supply_card_where_no_front_runs_a_clock() -> void:
	_short_skimmer()
	GameFlow.planet_id = "grit_station"
	assert_false(_board_has_supply(), "the moon's cantina has no supply run")


func test_once_a_supplier_the_card_leaves_the_board() -> void:
	_short_skimmer()
	GameFlow.planet_id = "ringed_giant"
	assert_true(Territory.start_supply())
	assert_eq(Territory.deliver(EAST) > 0, true, "delivered")
	_short_skimmer()
	WorldState.control[EAST].hold = 100.0
	assert_false(_board_has_supply(), "no card again: any short skimmer takes your supplies now")
	assert_true(Territory.supplier() and Territory.can_deliver(EAST))
