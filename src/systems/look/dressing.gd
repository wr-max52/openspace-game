class_name Dressing
extends RefCounted
## Issue #542: the dressings' palettes (the barge, the club, the market, the
## station's floors, the outposts), from content/look/dressing.json, so a restyle
## is data, not six scripts. Read once and cached.
##
##   Dressing.c("club", "bar_top", "#3a2a1e")   a named colour, the fallback if the
##                                              file or the name is missing
##   Dressing.list("market", "cloths", "#a8322a")   a short list (Colors), in order,
##                                              so seeded picks pick the same colours
##
## A planet (or station world) can name a variant in its config, the way "style"
## names a town style: "dressing": "club_moon" (or a list of them). A variant is an
## entry of "variants" with a "base" (the palette it changes) and only the names
## it changes; the rest is the base's. TownDemo calls use() as the planet loads.

const DATA_PATH := "res://content/look/dressing.json"

static var _data: Dictionary = {}
static var _chosen: Array = []          ## variant ids the current planet names
static var _overrides: Dictionary = {}  ## palette id -> names over everything (tests, look-dev)
static var _merged: Dictionary = {}     ## palette id -> the palette after variants and overrides
static var _colors: Dictionary = {}     ## palette id -> { name: Color }, parsed once


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


## The variant(s) the current planet names ("" or [] for none): its "dressing".
static func use(spec) -> void:
	_chosen = []
	if spec is String:
		if spec != "":
			_chosen.append(spec)
	elif spec is Array:
		for v in spec:
			_chosen.append(str(v))
	_flush()


## Names that win over the file and the variants for palette `id` (a test, a
## look-dev pass). {} clears.
static func override(id: String, names: Dictionary) -> void:
	if names.is_empty():
		_overrides.erase(id)
	else:
		_overrides[id] = names
	_flush()


## Palette `id`: the file's, with the chosen variants whose "base" is `id` over it.
static func palette(id: String) -> Dictionary:
	if _merged.has(id):
		return _merged[id]
	var d := data()
	var out: Dictionary = (d.get("palettes", {}) as Dictionary).get(id, {}).duplicate()
	var variants: Dictionary = d.get("variants", {})
	for v in _chosen:
		var var_pal: Dictionary = variants.get(v, {})
		if str(var_pal.get("base", "")) != id:
			continue
		for k in var_pal:
			if k != "base":
				out[k] = var_pal[k]
	if _overrides.has(id):
		var ov: Dictionary = _overrides[id]
		for k in ov:
			out[k] = ov[k]
	_merged[id] = out
	return out


## Colour `name` of palette `id`, or `fallback` (a "#rrggbb") when it has none.
static func c(id: String, name: String, fallback: String) -> Color:
	var cache: Dictionary = _colors.get(id, {})
	if cache.is_empty():
		_colors[id] = cache
	if cache.has(name):
		return cache[name]
	var v = palette(id).get(name, fallback)
	var col := Color(str(v)) if v is String else Color(fallback)
	cache[name] = col
	return col


## List `name` of palette `id` (Colors, in the file's order), or [fallback].
## `at_least`: a caller that indexes it by position gets that many, the list
## repeated (a shorter list, or the fallback, never runs out).
static func list(id: String, name: String, fallback: String, at_least := 1) -> Array:
	var out: Array = []
	var v = palette(id).get(name, null)
	if v is Array:
		for x in v:
			out.append(Color(str(x)))
	if out.is_empty():
		out.append(Color(fallback))
	var n := out.size()
	while out.size() < at_least:
		out.append(out[out.size() % n])
	return out


static func _flush() -> void:
	_merged.clear()
	_colors.clear()
