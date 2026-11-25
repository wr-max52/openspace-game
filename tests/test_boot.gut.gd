extends GutTest
## Issue #545: the game starts. Reads the two runs of scenes/boot_trace.gd that
## scripts/ci.sh makes, each the main scene with the look on and a real save
## folder: a first launch (no save: the New Game menu, Enter, Story) and the next
## launch (the save is read, no menu). ci.sh also fails on any script error in
## either run's log, which is how the v1.6.4 first-launch crash would show.

const TraceReader := preload("res://tests/trace_reader.gd")
var first := {}
var again := {}


func before_all() -> void:
	first = TraceReader.read("res://test_results/boot_first.txt")
	again = TraceReader.read("res://test_results/boot_again.txt")


func test_both_launches_ran() -> void:
	assert_eq(first.get("phase"), "first", "the first launch wrote its trace")
	assert_eq(again.get("phase"), "again", "the next launch wrote its trace")


func test_a_first_launch_has_no_save() -> void:
	assert_eq(first.get("story_save_before"), "false", "ci.sh gave it an empty home")
	assert_eq(first.get("town_ready"), "true", "the town built")
	assert_eq(first.get("fresh"), "true", "the town saw a first launch")


func test_the_new_game_menu_opens_on_story() -> void:
	assert_eq(first.get("menu_open"), "true", "the menu is up and the game paused behind it")
	assert_eq(first.get("menu_lit"), "story")


func test_enter_starts_a_story_game() -> void:
	assert_eq(first.get("reloaded"), "true", "Enter reloaded the town")
	assert_eq(first.get("paused_after"), "false", "and the game runs")
	assert_eq(first.get("mode"), "story")
	assert_eq(first.get("slot"), "story")
	assert_eq(first.get("story_save_after"), "true", "the story save is on disk")
	assert_eq(first.get("player_in_tree"), "true", "the player stands in the port")


func test_the_next_launch_goes_on() -> void:
	assert_eq(again.get("story_save_before"), "true")
	assert_eq(again.get("town_ready"), "true")
	assert_eq(again.get("fresh"), "false", "the save was read, so no New Game menu")
	assert_eq(again.get("mode"), "story")
	assert_eq(again.get("player_in_tree"), "true")


## The frames are recorded, not judged: headless, the look's cost is all CPU (no
## GPU, no culling), so it is no fair budget. The frame budgets are the walk,
## flight and planet traces. This only checks the town kept running.
func test_the_town_keeps_running() -> void:
	for t in [first, again]:
		assert_gt(int(t.get("timed_frames", 0)), 200, "%s: frames went by in the port" % t.get("phase"))
