class_name SpeederUpgrades
extends RefCounted
## Issue #95: the parts the mechanic sells for a speeder, and what they do. Pure
## (no nodes): which parts a speeder can take, what they cost, the speeder's
## numbers with them fitted, and what it is worth as scrap. Tested headless in
## tests/test_speeder_upgrades.gut.gd.
##
## A speeder's fit is { "paint": "<look.paints name or ''>", "parts": [part ids],
## "model": "<vehicle id>" }, kept per speeder in WorldState.speeder_fits
## (SpeederPost reads it when it parks one). Data:
## content/core/vehicles/speeder_upgrades.json.
##
## Issue #627: a fit's "model" is its vehicle file (speeder, racer, hauler; none =
## the Sand-boxer, so old saves load as they were). A model's "shop_groups" say
## which menu groups the bench offers it (none listed = all), and a part's "model"
## says which model it fits (none = the Sand-boxer): the racer and the box truck
## take their own paint jobs and nothing else.

const PATH := "res://content/core/vehicles/speeder_upgrades.json"
const CoreContent := preload("res://src/systems/dataload/core_content.gd")

static var _data: Dictionary = {}
static var _models: Dictionary = {}    ## issue #627: vehicle id -> its config (shop_groups, scrap_base)


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_data = d if d is Dictionary else {}
	return _data


static func mechanic() -> Dictionary:
	return data().get("mechanic", {})


## Issue #295: another shop's block ("shops": Skrugs's garage bench) laid over the
## mechanic's, so its menu labels, parts and prices are his. Empty if there is none.
static func shop(id: String) -> Dictionary:
	var own: Dictionary = data().get("shops", {}).get(id, {})
	if own.is_empty():
		return {}
	return CoreContent._merge(mechanic(), own)


static func parts() -> Array:
	return data().get("parts", [])


static func part(id: String) -> Dictionary:
	for p in parts():
		if str(p.get("id", "")) == id:
			return p
	return {}


static func in_group(group: String) -> Array:
	return parts().filter(func(p): return str(p.get("group", "")) == group)


static func new_fit(paint: String = "", model: String = "speeder") -> Dictionary:
	return { "paint": paint, "parts": [], "spent": 0, "model": model }


## Issue #627: the vehicle file this fit is for ("speeder" when it does not say).
static func model_of(fit: Dictionary) -> String:
	var m := str(fit.get("model", ""))
	return m if m != "" else "speeder"


static func _model_cfg(model: String) -> Dictionary:
	if not _models.has(model):
		_models[model] = HoverModel.load_config(model)
	return _models[model]


## The menu groups the bench offers this model (every group when it lists none).
static func groups_for(model: String) -> Array:
	var g = _model_cfg(model).get("shop_groups", null)
	return g if g is Array else ["paint", "looks", "performance", "lifter"]


## Part `p` goes on this model: its group is one the model takes, and it is made
## for this model (a part with no "model" is the Sand-boxer's).
static func fits_model(p: Dictionary, model: String) -> bool:
	var pm := str(p.get("model", ""))
	if (pm if pm != "" else "speeder") != model:
		return false
	return groups_for(model).has(str(p.get("group", "")))


## The parts in `group` that go on this model.
static func in_group_for(group: String, model: String) -> Array:
	return in_group(group).filter(func(p): return fits_model(p, model))


## True if `fit` already has this part (or the tier above it in its line).
static func has_part(fit: Dictionary, id: String) -> bool:
	var fitted: Array = fit.get("parts", [])
	if fitted.has(id):
		return true
	for other in fitted:
		if str(part(str(other)).get("requires", "")) == id:
			return true
	return false


## "" if `fit` can take part `id` now, else why not: "owned", "needs:<part id>",
## "unknown". Paint can always be bought again (unless it is the paint on it).
static func why_not(fit: Dictionary, id: String) -> String:
	var p := part(id)
	if p.is_empty():
		return "unknown"
	if not fits_model(p, model_of(fit)):
		return "wrong_model"           # issue #627: not for this model (the racer takes paint only)
	if str(p.get("slot", "")) == "paint":
		return "owned" if str(fit.get("paint", "")) == str(p.get("paint", "")) else ""
	if has_part(fit, id):
		return "owned"
	var req := str(p.get("requires", ""))
	if req != "" and not has_part(fit, req):
		return "needs:" + req
	return ""


## Fit part `id` (no money changes hands here: the caller pays). A part replaces
## whatever was in its slot (tier 2 replaces tier 1). False if it cannot go on.
static func fit_part(fit: Dictionary, id: String) -> bool:
	if why_not(fit, id) != "":
		return false
	var p := part(id)
	fit["spent"] = int(fit.get("spent", 0)) + int(p.get("price", 0))
	if str(p.get("slot", "")) == "paint":
		fit["paint"] = str(p.get("paint", ""))
		return true
	var keep: Array = []
	for other in fit.get("parts", []):
		if str(part(str(other)).get("slot", "")) != str(p.get("slot", "")):
			keep.append(other)
	keep.append(id)
	fit["parts"] = keep
	return true


## The speeder's config (content/core/vehicles/speeder.json) with `fit` applied:
## stat multipliers, and the Grav Lifter's "hover" block.
static func apply(base_cfg: Dictionary, fit: Dictionary) -> Dictionary:
	var cfg := base_cfg.duplicate(true)
	for id in fit.get("parts", []):
		var p := part(str(id))
		var mods: Dictionary = p.get("mods", {})
		for key in mods:
			var k := str(key)
			if k.begins_with("laser."):
				var laser: Dictionary = cfg.get("laser", {})
				var lk := k.substr(6)
				laser[lk] = float(laser.get(lk, 0.0)) * float(mods[key])
				cfg["laser"] = laser
			else:
				cfg[k] = float(cfg.get(k, 0.0)) * float(mods[key])
		if p.has("hover"):
			cfg["hover"] = (p.hover as Dictionary).duplicate()
	cfg["parts"] = (fit.get("parts", []) as Array).duplicate()
	return cfg


## What the mechanic pays for the speeder as scrap.
static func scrap_value(fit: Dictionary) -> int:
	var s: Dictionary = data().get("scrap", {})
	var base := int(_model_cfg(model_of(fit)).get("scrap_base", s.get("base", 35)))    # issue #627: per model
	return base + int(round(float(fit.get("spent", 0)) * float(s.get("parts_back", 0.25))))
