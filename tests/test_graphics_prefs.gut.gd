extends GutTest
## The preferences in the save (SavePrefs: graphics and the AI answer): every save
## file carries them, a loaded save puts them back, a change in F11 > Options
## re-writes the saves, and the first start's questions (Low or Full, then AI
## characters) are asked once only. Runs in its own save folder and AI settings
## file; the player's graphics.cfg is put back after each test.

const ROOT := "user://test_graphics_prefs/"
const SaveSystem := preload("res://src/systems/save/save_system.gd")

var _had_cfg := false
var _cfg := PackedByteArray()


func before_each() -> void:
	var path := LookEnvironment.SETTINGS_PATH
	_had_cfg = FileAccess.file_exists(path)
	_cfg = FileAccess.get_file_as_bytes(path) if _had_cfg else PackedByteArray()
	_clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	SaveSlots.root = ROOT
	SaveSlots.active = ""
	SavePrefs.ai_path = ROOT + "llm_config.json"


func after_each() -> void:
	SavePrefs.ai_path = LLMConfig.USER_PATH
	SaveSlots.root = "user://"
	SaveSlots.active = ""
	_clear()
	var path := LookEnvironment.SETTINGS_PATH
	if _had_cfg:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(_cfg)
		f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_reload()


func _clear() -> void:
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT))


## Forget what LookEnvironment read, so the next call reads graphics.cfg again.
func _reload() -> void:
	LookEnvironment._cut = {}
	LookEnvironment._taa = -1
	LookEnvironment._indirect = -1.0


func _prefs_in(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d.get("prefs", {}).get("graphics", {}) if d is Dictionary else {}


func test_every_save_carries_the_graphics_choices() -> void:
	LookEnvironment.save_low_graphics(true)
	var s := SaveSystem.new()
	s.new_game()
	var path := ROOT + "one.json"
	assert_true(s.save_to(path))
	var g := _prefs_in(path)
	assert_true(bool(g.get("low", false)), "low graphics in the save")
	for p in LookEnvironment.pieces():
		assert_eq(bool(g.pieces[str(p.id)]), LookEnvironment.cut(str(p.id)), str(p.id))
	assert_true(g.has("taa") and g.has("indirect"))


func test_a_loaded_save_puts_its_choices_back() -> void:
	LookEnvironment.save_low_graphics(true)
	var block := GraphicsPrefs.to_save()
	LookEnvironment.save_low_graphics(false)
	assert_false(LookEnvironment.low_graphics())
	assert_true(GraphicsPrefs.from_save(block), "something changed")
	assert_true(LookEnvironment.low_graphics(), "the save's low graphics is back")
	_reload()
	assert_true(LookEnvironment.low_graphics(), "and on this machine too (graphics.cfg)")
	assert_false(GraphicsPrefs.from_save(block), "the same block again changes nothing")
	assert_false(GraphicsPrefs.from_save({}), "a save from before the block changes nothing")


func test_a_change_rewrites_every_save_file() -> void:
	LookEnvironment.save_low_graphics(false)
	for mode in SaveSlots.FILES:
		var s := SaveSystem.new()
		s.new_game()
		s.save_to(SaveSlots.path(mode))
		assert_false(bool(_prefs_in(SaveSlots.path(mode)).low))
	LookEnvironment.save_low_graphics(true)
	SavePrefs.write_saves()
	for mode in SaveSlots.FILES:
		assert_true(bool(_prefs_in(SaveSlots.path(mode)).low), str(mode) + " save updated")


func test_the_first_answer_is_saved_and_never_asked_again() -> void:
	LookEnvironment._save_setting("first_run", "asked", false)
	assert_false(GraphicsPrefs.asked())
	GraphicsPrefs.choose(true)
	assert_true(GraphicsPrefs.asked())
	assert_true(LookEnvironment.low_graphics())
	assert_false(LookEnvironment.cut("bloom"), "bloom is not part of Low graphics")
	assert_true(bool(GraphicsPrefs.to_save().chosen))


func test_the_question_never_shows_headless() -> void:
	assert_null(GraphicsChoiceOverlay.show_if_unasked(self))


func test_the_pieces_fold_under_advanced_graphics_settings() -> void:
	var panel := DevSettingsPanel.new()
	add_child_autofree(panel)
	panel._build_tabs()          # the pages are built when the panel first opens
	var fold := panel.find_child("AdvancedGraphics", true, false) as Button
	var list := panel.find_child("AdvancedGraphicsList", true, false) as Control
	assert_not_null(fold)
	assert_not_null(list)
	assert_false(list.visible, "closed to start")
	assert_eq(list.get_child_count(), LookEnvironment.pieces().size() + 1, "a note and a box per piece")
	fold.pressed.emit()
	assert_true(list.visible, "a click opens it")
	fold.pressed.emit()
	assert_false(list.visible, "another closes it")


func _ai(asked: bool, on: bool) -> void:
	var f := FileAccess.open(SavePrefs.ai_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "first_run_asked": asked, "ai_enabled": on }))
	f.close()


func _save_with(prefs: Dictionary) -> void:
	var s := SaveSystem.new()
	s.new_game()
	s.save_to(SaveSlots.current_path())
	var d = JSON.parse_string(FileAccess.get_file_as_string(SaveSlots.current_path()))
	d["prefs"] = prefs
	var f := FileAccess.open(SaveSlots.current_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func test_every_save_carries_the_ai_answer() -> void:
	_ai(true, true)
	var s := SaveSystem.new()
	s.new_game()
	var path := ROOT + "two.json"
	s.save_to(path)
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(d.prefs.ai, { "asked": true, "on": true })
	assert_true(d.prefs.has("graphics"), "the graphics beside it")


func test_a_loaded_save_puts_the_ai_answer_back() -> void:
	_ai(false, false)
	SavePrefs.from_save({ "ai": { "asked": true, "on": true } })
	assert_eq(SavePrefs.ai_to_save(), { "asked": true, "on": true }, "written to this machine's AI settings")


func test_the_questions_are_for_the_first_start_only() -> void:
	LookEnvironment._save_setting("first_run", "asked", false)
	assert_true(SavePrefs.ask_graphics(), "a first start asks graphics")
	assert_false(SavePrefs.ai_asked(), "and AI characters")
	_ai(true, false)
	assert_true(SavePrefs.ai_asked(), "AI answered: never again")
	assert_false(SavePrefs.ask_graphics(), "a player from before the graphics question is not asked it")
	_ai(false, false)
	GraphicsPrefs.set_asked()
	assert_false(SavePrefs.ask_graphics(), "graphics answered: never again")


func test_a_save_with_the_answers_asks_nothing() -> void:
	LookEnvironment._save_setting("first_run", "asked", false)
	_ai(false, false)
	_save_with({ "graphics": { "chosen": true }, "ai": { "asked": true, "on": false } })
	assert_false(SavePrefs.ask_graphics(), "the save has the graphics answer")
	assert_true(SavePrefs.ai_asked(), "the save has the AI answer")
	assert_null(DisclaimerOverlay.show_once(self), "the AI question never shows (and never headless)")
