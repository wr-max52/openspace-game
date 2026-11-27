class_name GraphicsPrefs
extends RefCounted
## The graphics choices as preferences in the save. LookEnvironment keeps them per
## machine (user://settings/graphics.cfg), read before anything is drawn; this
## puts the same choices in every save file ("prefs": { "graphics": ... }) and
## reads them back when a save loads, so a save carries how it is drawn.
##
##   asked() / set_asked()  -- the first launch's question (GraphicsChoiceOverlay) answered?
##   choose(low)            -- that answer: Low graphics or Full, saved, never asked again
##   to_save() / from_save  -- the block a save holds, and putting one back
##   show_on(demo)          -- the live look redrawn with what is saved
## The save's whole preferences block (graphics and AI) is SavePrefs'.


static func asked() -> bool:
	var f := ConfigFile.new()
	return f.load(LookEnvironment.SETTINGS_PATH) == OK and bool(f.get_value("first_run", "asked", false))


static func set_asked() -> void:
	LookEnvironment._save_setting("first_run", "asked", true)


## The first launch's answer: every piece Low graphics takes in on or off (the
## advanced pieces follow it), and the question is never asked again.
static func choose(low: bool) -> void:
	LookEnvironment.save_low_graphics(low)
	set_asked()


## What a save holds: { chosen, low, taa, indirect, pieces: { id: cut } }.
static func to_save() -> Dictionary:
	var pieces := {}
	for p in LookEnvironment.pieces():
		pieces[str(p.id)] = LookEnvironment.cut(str(p.id))
	return { "chosen": asked(), "low": LookEnvironment.low_graphics(), "taa": LookEnvironment.taa(),
		"indirect": LookEnvironment.indirect_level(), "pieces": pieces }


## Put a save's block back on this machine. Returns true when anything changed
## (the live look then needs show_on). A save from before the block changes nothing.
static func from_save(d: Dictionary) -> bool:
	if d.is_empty():
		return false
	var changed := false
	if d.has("taa") and bool(d.taa) != LookEnvironment.taa():
		LookEnvironment.save_taa(bool(d.taa))
		changed = true
	if d.has("indirect") and not is_equal_approx(float(d.indirect), LookEnvironment.indirect_level()):
		LookEnvironment.save_indirect_level(float(d.indirect))
		changed = true
	var pieces = d.get("pieces", {})
	if pieces is Dictionary:
		for p in LookEnvironment.pieces():
			var id := str(p.id)
			if (pieces as Dictionary).has(id) and bool(pieces[id]) != LookEnvironment.cut(id):
				LookEnvironment.save_cut(id, bool(pieces[id]))
				changed = true
	if bool(d.get("chosen", false)) and not asked():
		set_asked()
	return changed


## Redraw the live look (sky, light, render scale, draw ranges) from what is saved.
static func show_on(demo: Node) -> void:
	if demo == null:
		return
	var look = demo.get("look")
	if look != null and is_instance_valid(look):
		look.set_indirect(LookEnvironment.indirect_level())
		look.set_taa(LookEnvironment.taa())
		look.apply_low()
	var dd = demo.get("draw_distance")
	if dd != null and is_instance_valid(dd):
		dd.apply_low_graphics()
