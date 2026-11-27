class_name SavePrefs
extends RefCounted
## The preferences every save file carries ("prefs"), beside the game in it:
##   graphics -- GraphicsPrefs.to_save(): Low or Full, the advanced pieces, TAA, indirect light
##   ai       -- { asked, on }: the first start's AI characters answer, and on or off now
##
## This machine keeps its own copy too (user://settings/graphics.cfg and
## user://llm_config.json), read before any save is. SaveSystem.save_to stamps
## the block on every write; a change in the settings re-writes every save file
## now (write_saves); the town loading a save puts its block back (from_save).
##
## The first start's questions (graphics, then AI characters) are asked once:
## never again once this machine or the save being played has an answer.

const SaveSystem := preload("res://src/systems/save/save_system.gd")

static var ai_path := LLMConfig.USER_PATH     ## tests point this elsewhere
static var _pending := false


static func to_save() -> Dictionary:
	return { "graphics": GraphicsPrefs.to_save(), "ai": ai_to_save() }


## The AI answer as this machine has it (only the player's overrides hold it;
## the shipped defaults have AI off and never asked).
static func ai_to_save() -> Dictionary:
	var u := LLMConfig._read(ai_path)
	return { "asked": bool(u.get("first_run_asked", false)), "on": bool(u.get("ai_enabled", false)) }


## Put a save's block back. `host` (the town's ConversationHost) turns the AI
## characters on or off live; without one the machine's settings are written.
## Returns true when the graphics changed (the live look then needs
## GraphicsPrefs.show_on).
static func from_save(prefs: Dictionary, host: Node = null) -> bool:
	var g = prefs.get("graphics", {})
	var changed := GraphicsPrefs.from_save(g) if g is Dictionary else false
	var ai = prefs.get("ai", {})
	if ai is Dictionary and not (ai as Dictionary).is_empty():
		ai_from_save(ai, host)
	return changed


static func ai_from_save(d: Dictionary, host: Node = null) -> void:
	var asked := bool(d.get("asked", false))
	var on := bool(d.get("on", false))
	if host != null and host.get("llm") != null and host.llm.config != null:
		var cfg: LLMConfig = host.llm.config
		if cfg.ai_enabled() == on and (cfg.first_run_asked() or not asked):
			return
		if asked:
			cfg.set_first_run_asked()
		host.set_ai_enabled(on, false)
		cfg.save_user()
		return
	var c := LLMConfig.new()
	c.user_path = ai_path
	c.load_all()
	if c.ai_enabled() == on and (c.first_run_asked() or not asked):
		return
	if asked:
		c.set_first_run_asked()
	c.set_ai_enabled(on)
	c.save_user()


## The prefs in the save being played, read straight from its file ({} if none).
static func in_current_save() -> Dictionary:
	var path := SaveSlots.current_path()
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var p = (d as Dictionary).get("prefs", {}) if d is Dictionary else {}
	return p if p is Dictionary else {}


## Has the AI characters question been answered, here or in the save?
static func ai_asked() -> bool:
	if bool(ai_to_save().asked):
		return true
	var ai = in_current_save().get("ai", {})
	return ai is Dictionary and bool((ai as Dictionary).get("asked", false))


## Ask the graphics question? Only on the first start: not once this machine or
## the save has a graphics answer, nor once the AI question was answered (a
## player from before the question started the game long ago).
static func ask_graphics() -> bool:
	if GraphicsPrefs.asked() or ai_asked():
		return false
	var g = in_current_save().get("graphics", {})
	return not (g is Dictionary and bool((g as Dictionary).get("chosen", false)))


## Every save file there is (story and free roam) gets the prefs now. Writing a
## save stamps them anyway (SaveSystem.save_to); this only re-writes the files.
static func write_saves() -> void:
	_pending = false
	for mode in SaveSlots.FILES:
		var path := SaveSlots.path(mode)
		var s := SaveSystem.new()
		if FileAccess.file_exists(path) and s.load_from(path):
			s.save_to(path)


## write_saves, half a second after the last change (a slider sends one per step).
static func save_soon(tree: SceneTree) -> void:
	if tree == null:
		write_saves()
		return
	if _pending:
		return
	_pending = true
	tree.create_timer(0.5, true).timeout.connect(func(): if _pending: write_saves())
