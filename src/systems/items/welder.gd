class_name Welder
extends RefCounted
## Issue #722: the plasma welder's rules, pure and static. Its numbers are the
## item's "weld" block (content/core/items/plasma_welder.json):
##   weld_s         seconds of holding E (or fire, welder drawn) to fix something
##   reach          how close (m) you stand to a WeldSpot
##   unwelded_hull  mid-race without a welder, the patch-up puts you back at this
##                  share of full hull
##   ship_flasks    flasks of flask_item that fixing your own ship uses up
## Who welds: PlayerWelder on foot (any WeldSpot), SpeederNode in the race seat.

const ITEM := "plasma_welder"
const PATH := "res://content/core/items/plasma_welder.json"

static var _cfg: Dictionary = {}
## Tests: 1 = E counts as held, 0 = not held, -1 = read the key.
static var hold_override := -1
## True while PlayerWelder has a weld spot in front of you that E would weld:
## the other [E] users (droids, the ship) stand aside so one press does one thing.
static var claims_e := false


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg = (d as Dictionary).get("weld", {}) if d is Dictionary else {}
	return _cfg


static func owned() -> bool:
	return WorldState.inventory.has(ITEM)


static func weld_s() -> float:
	return float(cfg().get("weld_s", 2.0))


## Seconds to bring the welder up from hanging low to held out in front (and back).
static func raise_s() -> float:
	return maxf(0.01, float(cfg().get("raise_s", 0.25)))


static func reach() -> float:
	return float(cfg().get("reach", 3.0))


static func unwelded_hull() -> float:
	return clampf(float(cfg().get("unwelded_hull", 0.5)), 0.05, 1.0)


static func ship_flasks() -> int:
	return int(cfg().get("ship_flasks", 10))


static func flask_item() -> String:
	return str(cfg().get("flask_item", "refined_quantonium"))


static func flasks() -> int:
	return WorldState.inventory.count(flask_item())


## Enough quantonium to fix your own ship?
static func can_pay_ship() -> bool:
	return flasks() >= ship_flasks()


## Takes ship_flasks flasks. False (and nothing taken) when you carry fewer.
static func pay_ship() -> bool:
	if not can_pay_ship():
		return false
	for k in ship_flasks():
		WorldState.inventory.remove(flask_item())
	return true


## Is the interact key held (the hold that welds)?
static func e_held() -> bool:
	if hold_override >= 0:
		return hold_override == 1
	return InputMap.has_action("interact") and Input.is_action_pressed("interact")
