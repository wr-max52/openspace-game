class_name ModelCache
extends RefCounted
## The game's imported models (.glb / .tscn) and the characters' outfit textures,
## loaded once a run and kept.
##
## A planet handoff swaps the whole town scene. Without this, the old scene's
## models are freed with it and the new scene loads them again from disk on the
## main thread: a Hyper3D speeder is ~145 ms each, so flying home froze for a
## third of a second on the speeders alone, and the ship, items and droids added
## to both directions. Holding the PackedScene here keeps Godot's resource cache
## warm across change_scene, so a second build is just an instantiate().
##
## Static on purpose (no autoload), like GameFlow: the state survives scene
## changes and nothing runs until something asks for a model.

static var _scenes: Dictionary = {}       ## path -> Resource (what load() gave)
static var _pending: Dictionary = {}      ## path -> true: prefetch() asked a worker thread for it

## Issue #693: which models each planet asked for, kept between runs, so flying
## in from somewhere else (the giant, a save made off home) can load them on
## worker threads before that planet's scene takes over (SpaceTravel's approach).
## A cache, not a save: losing it only means the first arrival loads as before.
const USE_PATH := "user://model_use.json"
static var _planet := ""                  ## the planet whose build is asking now
static var _used: Dictionary = {}         ## planet id -> { path: true }
static var _use_read := false
static var _use_dirty := false


## load(path), once per path per run. Same result as load(): null when missing.
static func scene(path: String) -> Resource:
	_note(path)
	if _scenes.has(path):
		return _scenes[path]
	var res: Resource
	if _pending.has(path):
		_pending.erase(path)
		res = ResourceLoader.load_threaded_get(path)   # waits only if the worker is not done yet
	else:
		res = load(path)
	if res != null:
		_scenes[path] = res
	return res


## Issue #162: start loading `paths` on worker threads, so a later scene() is only
## a lookup. A planet handoff builds its people a frame at a time; a 2048² outfit
## texture read from disk on the main thread was a 35-110 ms stall per new colour.
static func prefetch(paths: Array) -> void:
	for p in paths:
		var path := str(p)
		if _scenes.has(path) or _pending.has(path) or ResourceLoader.has_cached(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending[path] = true


## Paths asked for by prefetch() and not yet picked up by scene().
static func pending() -> Array:
	return _pending.keys()


## Forget everything (tests; the models load again on next use).
static func clear() -> void:
	for path in _pending:
		ResourceLoader.load_threaded_get(path)   # let the worker's result go
	_pending.clear()
	_scenes.clear()


## Issue #693: from now on the models asked for are this planet's.
static func begin_planet(id: String) -> void:
	_planet = id


## The models `id` asked for in this run or an earlier one.
static func used_by(id: String) -> Array:
	_read_use()
	return (_used.get(id, {}) as Dictionary).keys()


## Starts loading on worker threads every model `id` used last time.
static func prefetch_planet(id: String) -> void:
	prefetch(used_by(id))


## Writes the record when it grew (a scene leaving, the game quitting).
static func save_use() -> void:
	if not _use_dirty:
		return
	var f := FileAccess.open(USE_PATH, FileAccess.WRITE)
	if f == null:
		return
	var out := {}
	for id in _used:
		out[id] = (_used[id] as Dictionary).keys()
	f.store_string(JSON.stringify(out))
	_use_dirty = false


static func _note(path: String) -> void:
	if _planet == "":
		return
	_read_use()
	if not _used.has(_planet):
		_used[_planet] = {}
	var d: Dictionary = _used[_planet]
	if not d.has(path):
		d[path] = true
		_use_dirty = true


static func _read_use() -> void:
	if _use_read:
		return
	_use_read = true
	if not FileAccess.file_exists(USE_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(USE_PATH))
	if not parsed is Dictionary:
		return
	for id in parsed:
		var d := {}
		if parsed[id] is Array:
			for p in parsed[id]:
				d[str(p)] = true
		_used[str(id)] = d
