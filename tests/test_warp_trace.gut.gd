extends GutTest
## Issue #874: the warp drive, from the headless trace (scenes/warp_trace.gd,
## real physics, the real town scene): no drive, no warp (the key says why);
## T-89's drive fitted, hold, pick, at least 5 s of warp, then the red system's
## open space with only its own planets; a save made there loads there; and warp
## home the same way.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/warp_trace.txt")


func _true(k: String, why: String = "") -> void:
	assert_eq(t.get(k), "true", why if why != "" else k)


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/warp_trace.gd first (test_all.sh does)")


func test_starts_in_the_home_systems_open_space() -> void:
	assert_eq(t.get("START_PLACE"), "open_space")
	assert_eq(t.get("START_SYSTEM"), "home")
	assert_true(str(t.get("START_BODIES")).split(",").has("port_desert"))
	_true("START_FLYING")


func test_without_the_drive_the_picker_never_opens() -> void:
	assert_eq(t.get("NO_DRIVE_REASON"), "warp_no_drive")
	assert_eq(t.get("NO_DRIVE_PICKER"), "false", "holding the key opens nothing")
	assert_string_contains(str(t.get("NO_DRIVE_TOAST")), "T-89", "a line says why")
	assert_eq(t.get("NO_DRIVE_PICK"), "false")


func test_fitted_hold_opens_the_picker_with_the_other_system() -> void:
	_true("FITTED")
	_true("UNLOCKED", "an unlock upgrade, not a mult")
	_true("RED_PICKER_OPEN")
	assert_eq(t.get("RED_DESTINATIONS"), "red_reach", "one destination for now")
	_true("RED_PICKED")


func test_the_warp_lasts_at_least_five_seconds_and_looks_like_one() -> void:
	assert_gte(float(t.get("RED_WARP_S", 0)), 5.0, "the loop covers the load, min 5 s")
	assert_lt(float(t.get("RED_WARP_S", 99)), 10.0)
	assert_gt(float(t.get("RED_FOV_KICK_MAX", 0)), 20.0, "the FOV kicks")
	assert_gt(float(t.get("RED_FLAMES_MAX", 0)), 1.5, "the engines' flames lengthen")
	_true("RED_LEFT")
	assert_eq(t.get("RED_TO"), "open_space", "into open space, not a planet")
	assert_eq(t.get("RED_WARP_ARRIVAL"), "red_reach")


func test_in_the_red_system_only_its_planets_hang() -> void:
	assert_eq(t.get("RED_PLACE"), "open_space")
	assert_eq(t.get("RED_SYSTEM"), "red_reach")
	assert_eq(t.get("RED_BODIES"), "port_red", "the old system's planets are not drawn")
	assert_lt(float(t.get("RED_POS_ERR_M", 999)), 200.0, "where the warp put the ship")
	assert_gt(float(t.get("RED_FACING_DOT", 0)), 0.9, "pointed at the main planet")
	assert_between(float(t.get("RED_GAP_KM", 0)), 3.0, 10.0, "outside its bubble, a short hop in")
	_true("RED_SETTLING")
	assert_string_contains(str(t.get("RED_TOAST")), "Red system")
	_true("RED_FLYING")
	_true("RED_SETTLED", "the stars and the camera settle")
	_true("RED_STILL_HERE", "and nothing pulls you anywhere else")


func test_a_save_out_there_loads_there() -> void:
	assert_eq(t.get("SAVE_WHERE"), "port_red", "open space is never where you load; the system's main world is")
	assert_eq(t.get("SAVE_SYSTEM"), "red_reach")
	assert_eq(t.get("RESET_SYSTEM"), "home")
	assert_eq(t.get("LOAD_SYSTEM"), "red_reach")
	_true("LOAD_FITTED")


func test_warp_home_works_the_same_way() -> void:
	_true("HOME_PICKER_OPEN")
	assert_eq(t.get("HOME_DESTINATIONS"), "home")
	assert_gte(float(t.get("HOME_WARP_S", 0)), 5.0)
	assert_eq(t.get("HOME_SYSTEM"), "home")
	var b := str(t.get("HOME_BODIES")).split(",")
	assert_true(b.has("port_desert"))
	assert_false(b.has("port_red"))


func test_the_red_world_loads() -> void:
	assert_eq(t.get("WORLD_PLACE"), "port_red")
	assert_eq(t.get("WORLD_SYSTEM"), "red_reach")
	assert_eq(float(t.get("WORLD_BALL_R", 0)), 4000.0, "a whole ball")
	assert_eq(t.get("WORLD_BODIES"), "", "no home planet in its sky")
	assert_gt(int(t.get("WORLD_TOWN_BOXES", 0)), 10)
	_true("WORLD_PLAYER_ON_GROUND")
