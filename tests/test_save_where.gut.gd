extends GutTest
## Issue #113: the save remembers which planet you were on and where on it, and a
## run opened from that save resumes there (once).

const SaveSystemT := preload("res://src/systems/save/save_system.gd")
const PATH := "user://test_save_where.json"


func after_each() -> void:
	GameFlow.reset()
	GameFlow.resumed = false
	GameFlow.resume_pos = Vector3.INF
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _write(planet: String, pos, has_pos := true) -> void:
	var s := SaveSystemT.new()
	s.new_game()
	s.set_where(planet, pos, has_pos)
	s.save_to(PATH)


func test_round_trip() -> void:
	_write("grit_station", Vector3(12.5, 3.0, -40.0))
	var w := SaveSystemT.where_in(PATH)
	assert_eq(str(w.planet), "grit_station")
	assert_eq(w.pos, [12.5, 3.0, -40.0])


func test_resumes_on_the_saved_planet_and_spot_once() -> void:
	_write("grit_station", Vector3(12.5, 3.0, -40.0))
	assert_true(GameFlow.resume_from_save(PATH))
	assert_eq(GameFlow.current_planet_id(), "grit_station")
	assert_eq(GameFlow.take_resume_pos(), Vector3(12.5, 3.0, -40.0))
	assert_eq(GameFlow.take_resume_pos(), Vector3.INF, "the spot is taken once")
	GameFlow.planet_id = ""
	assert_false(GameFlow.resume_from_save(PATH), "once per run")
	assert_eq(GameFlow.current_planet_id(), PlanetGen.home_id())


func test_home_planet_and_planet_without_a_spot() -> void:
	_write(PlanetGen.home_id(), Vector3.ZERO, false)
	assert_true(GameFlow.resume_from_save(PATH))
	assert_eq(GameFlow.planet_id, "", "the home planet is the default")
	assert_eq(GameFlow.take_resume_pos(), Vector3.INF, "no spot saved: the spawn")


func test_old_save_or_unknown_planet_changes_nothing() -> void:
	var s := SaveSystemT.new()
	s.new_game()
	s.save_to(PATH)
	assert_false(GameFlow.resume_from_save(PATH))
	GameFlow.resumed = false
	_write("no_such_planet", Vector3.ONE)
	assert_false(GameFlow.resume_from_save(PATH))
	assert_eq(GameFlow.current_planet_id(), PlanetGen.home_id())


## Issue #703: quitting in open space (no bar out there) still saves the world, and
## where you load stays the last planet's spot.
func test_quitting_in_open_space_saves_the_world_and_keeps_the_planet() -> void:
	WorldState.reset()
	_write("grit_station", Vector3(12.5, 3.0, -40.0))
	WorldState.credits = 4321
	WorldState.set_flag("issue_703_open_space")
	GameFlow.planet_id = PlanetGen.open_space_id()
	ConversationHost.save_world(PATH)
	var s := SaveSystemT.new()
	assert_true(s.load_from(PATH))
	assert_eq(int(s.get_world().get("credits", 0)), 4321, "the credits are saved")
	assert_true(s.get_world().get("flags", {}).has("issue_703_open_space"), "and the world's flags")
	assert_eq(str(s.get_where().planet), "grit_station", "you load on the last planet")
	assert_eq(s.get_where().pos, [12.5, 3.0, -40.0], "at its spot")
	WorldState.reset()
