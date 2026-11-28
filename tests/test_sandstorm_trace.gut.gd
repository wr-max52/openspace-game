extends GutTest
## Issue #175: planet-wide sandstorms, from the headless trace
## (scenes/sandstorm_trace.gd): built on the sand home planet, started from F11,
## a slow build-up, about a minute at full strength and a fade, each change on
## its signal; the light, fog, dust and sand move with it and come back; it fades
## as you fly up and mostly under a roof; only the sand types get storms.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/sandstorm_trace.txt")


func _true(k: String) -> void:
	assert_eq(t.get(k), "true", k)


func test_built_on_the_home_planet() -> void:
	_true("STORM_BUILT")
	assert_eq(t.get("PLANET_TYPE"), "sand")
	_true("HOOK_IS_THIS")
	assert_eq(t.get("STATE_START"), "clear")
	_true("FIRST_IN_RANGE")
	_true("HAS_LOOK")
	_true("HAS_DUST")
	_true("HAS_SAND")
	_true("DUST_LAYERS_CLEAR")


func test_f11_starts_one() -> void:
	_true("F11_BUTTON")
	assert_eq(t.get("STATE_AFTER_BUTTON"), "building")
	assert_eq(t.get("HOOK_STATE"), "building")


func test_shape_over_time() -> void:
	assert_eq(t.get("STATES"), "building,full,fading,clear", "each change said on the signal")
	assert_almost_eq(float(t.get("BUILD_S", 0)), 50.0, 0.5, "a slow build-up")
	assert_almost_eq(float(t.get("FULL_S", 0)), 60.0, 0.5, "about a minute at full strength")
	assert_almost_eq(float(t.get("FADE_S", 0)), 40.0, 0.5, "then dies down")
	_true("NEXT_IN_RANGE")
	_true("NEXT_CAME_BY_ITSELF")


func test_effects_move() -> void:
	_true("MID_FOG_BETWEEN")
	_true("MID_SUN_DIMMER")
	assert_eq(float(t.get("FULL_LEVEL", 0)), 1.0)
	_true("FULL_FOG_THICK")
	assert_lt(float(t.get("FULL_SUN_RATIO", 1)), 0.5, "the sun dims")
	_true("FULL_AMBIENT_LOWER")
	_true("FULL_SKY_BROWN")
	_true("FULL_EXPOSURE_LOWER")
	assert_gt(float(t.get("FULL_DRIFT", 0)), 2.0, "the sand's blowing sheets turned up")
	assert_eq(float(t.get("FULL_DUST", 0)), 1.0)
	_true("FULL_DUST_ON")
	_true("FULL_GUST_HELD")
	_true("PRESET_KEEPS_STORM")


func test_a_ground_thing() -> void:
	assert_eq(float(t.get("HIGH_SEEN", 1)), 0.0, "gone once flown up")
	_true("HIGH_FOG_CLEAR")
	assert_eq(float(t.get("HIGH_DUST", 1)), 0.0)
	assert_eq(float(t.get("GROUND_SEEN", 0)), 1.0)
	assert_almost_eq(float(t.get("INDOORS_SEEN", 1)), 0.15, 0.01, "mostly kept out by a roof")
	assert_eq(float(t.get("OUTDOORS_SEEN", 0)), 1.0)
	_true("HOOK_FULL")


func test_back_to_clear() -> void:
	_true("CLEAR_FOG_BACK")
	_true("CLEAR_SUN_BACK")
	_true("CLEAR_AMBIENT_BACK")
	_true("CLEAR_DRIFT_BACK")
	_true("CLEAR_DUST_OFF")


func test_only_sand_types() -> void:
	assert_eq(t.get("TYPES_WITH_STORMS"), "red_desert,sand", "no snow, water, lava, gas or asteroid storms")
