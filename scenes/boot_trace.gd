extends SceneTree
## Issue #545: the CI gate's login check. The game is started the way a player
## starts it, as the main scene (town_demo.tscn, the look on) with nothing in
## user://, and it must reach a playable town without a script error.
##
##   phase=first  a first launch: no save, so the New Game menu opens; Enter picks
##                Story, the town reloads (the v1.6.4 crash was here: the menu
##                used get_viewport() after the reload took it out of the tree),
##                the story save is on disk and the player stands in the port.
##   phase=again  the next launch: the save from phase=first is read, no menu, the
##                story game goes on, the player stands in the port.
##
## Each phase writes test_results/boot_<phase>.txt (KEY=value), read by
## tests/test_boot.gut.gd. It also records the frames once the town is playable
## (median, worst, how many over 50 ms), for the record only: headless, the look
## layer's cost is all CPU with no GPU and no culling, so it is not a fair budget
## (the frame budgets are the walk, flight and planet traces, look off).
## scripts/ci.sh also fails the gate on any script error in this run's log.
##
## It plays with the real save folder, so it only runs where user:// is a folder
## made for it: scripts/ci.sh points HOME (and XDG_DATA_HOME) at an empty temp
## folder and sets BOOT_HOME to it. Run anywhere else, it stops before it reads
## or writes a thing, and the player's saves are never touched.
##
## Run: ./scripts/ci.sh (it runs both phases), not by hand.

const TOWN := "res://scenes/town_demo.tscn"
const READY_TIMEOUT_S := 120.0     ## a town that takes longer than this to build is a fail
const SETTLE_S := 0.5              ## a fresh town's first half second is not timed (as the other traces)
const MEASURE_S := 5.0             ## then this long of play is timed

var phase := "first"
var lines := PackedStringArray()
var _last := 0
var _measure := false
var worst_ms := 0.0
var _timed := 0
var _over := 0
var _ms: Array[float] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("phase="):
			phase = a.substr(6)
	var home := OS.get_environment("BOOT_HOME")
	var data := ProjectSettings.globalize_path("user://")
	if home == "" or not data.begins_with(home):
		printerr("BOOTTRACE refuses to run: user:// (%s) is not under BOOT_HOME. Run scripts/ci.sh, which gives it an empty home; this keeps your saves safe." % data)
		quit(2)
		return
	_run()


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _measure and _last > 0:
		var ms := (now - _last) / 1000.0
		worst_ms = maxf(worst_ms, ms)
		_ms.append(ms)
		_timed += 1
		if ms > 50.0:
			_over += 1
	_last = now
	return false


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])


func frames(n: int) -> void:
	for i in n:
		await process_frame


## The town is playable: the player is in it and the F11 panel (built last of the
## LATER steps, with the New Game menu) is there.
func playable(demo: Node) -> bool:
	return demo != null and is_instance_valid(demo) and demo.is_inside_tree() \
		and demo.get("_player") != null and demo.get("dev_settings") != null


## Wait for the current scene to be a playable town. Returns it, or null on a timeout.
func wait_town(not_this: Node = null) -> Node:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < READY_TIMEOUT_S * 1000.0:
		var s := current_scene
		if s != null and s != not_this and playable(s):
			return s
		await process_frame
	return null


## Start the main scene as the engine does: instance it, add it under the root,
## make it the current scene (so a reload reloads it).
func launch() -> Node:
	var demo: Node = load(TOWN).instantiate()
	get_root().add_child(demo)
	current_scene = demo
	return demo


## Time MEASURE_S of play after SETTLE_S, with the player standing in the town.
func time_play(demo: Node) -> void:
	await frames(int(SETTLE_S * 60.0))
	_measure = true
	await frames(int(MEASURE_S * 60.0))
	_measure = false
	out("timed_frames", _timed)
	_ms.sort()
	out("median_ms", "%.1f" % (_ms[_ms.size() / 2] if not _ms.is_empty() else -1.0))
	out("worst_ms", "%.1f" % worst_ms)
	out("frames_over_50ms", _over)
	out("player_in_tree", demo.get("_player") != null and demo._player.is_inside_tree())


func _run() -> void:
	var started := Time.get_ticks_msec()
	out("phase", phase)
	out("story_save_before", SaveSlots.exists(WorldState.STORY))
	launch()
	var demo := await wait_town()
	out("town_ready", demo != null)
	if demo == null:
		_finish(started)
		return
	out("fresh", demo.bar.fresh)
	if phase == "first":
		await _first(demo)
	else:
		out("mode", WorldState.mode)
		out("slot", SaveSlots.active)
		await time_play(demo)
	_finish(started)


func _first(demo: Node) -> void:
	# NewGameMenu.show_if_fresh, minus its headless guard: the same menu, under the
	# same town, wired to the same F11 panel.
	var menu := NewGameMenu.new()
	menu.settings = demo.dev_settings
	demo.add_child(menu)
	await frames(2)
	out("menu_open", menu.visible and paused)
	out("menu_lit", NewGameMenu.CHOICES[menu.selected][0])
	# Enter, through the viewport as a key press reaches it.
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	get_root().push_input(enter)
	var up := enter.duplicate()
	up.pressed = false
	get_root().push_input(up)
	var town := await wait_town(demo)
	out("reloaded", town != null)
	if town == null:
		return
	out("paused_after", paused)
	out("mode", WorldState.mode)
	out("slot", SaveSlots.active)
	out("story_save_after", SaveSlots.exists(WorldState.STORY))
	await time_play(town)


func _finish(started: int) -> void:
	out("total_s", "%.1f" % ((Time.get_ticks_msec() - started) / 1000.0))
	if not DirAccess.dir_exists_absolute("res://test_results"):
		DirAccess.make_dir_recursive_absolute("res://test_results")
	var f := FileAccess.open("res://test_results/boot_%s.txt" % phase, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("BOOTTRACE wrote test_results/boot_%s.txt" % phase)
	quit(0)
