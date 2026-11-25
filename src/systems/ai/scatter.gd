class_name Scatter
extends RefCounted
## Issue #605: who hears a fight start. Pure: the tuning (content/core/flow/
## scatter.json) and the test "does someone at `pos` hear noise `e`" (a NoiseEvents
## event: { id, pos, radius, kind }). The listeners (StationCrowd, Townsfolk,
## PartyBarge, MerchantNPC, CantinaOwnerNPC) each keep the last noise id they read
## and decide for themselves where to run.

const PATH := "res://content/core/flow/scatter.json"

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_cfg = parsed
		if _cfg.is_empty():
			_cfg = { "kinds": ["shot", "shot_guard", "explosion"] }
	return _cfg


static func quiet_s() -> float:
	return float(cfg().get("quiet_s", 12.0))


## True when someone at `pos` hears `e` as a fight: a scary kind, within its reach
## (and, with `max_dy` finite, on the same floor).
static func hears(e: Dictionary, pos: Vector3, max_dy := INF) -> bool:
	if not (str(e.get("kind", "")) in (cfg().get("kinds", []) as Array)):
		return false
	var at: Vector3 = e.pos
	if absf(at.y - pos.y) > max_dy:
		return false
	var reach := float(e.get("radius", 45.0)) * float(cfg().get("reach_mult", 1.0))
	return at.distance_squared_to(pos) <= reach * reach


## The newest scary noise heard at `pos` among NoiseEvents after `after_id`, or {}.
## Returns [last id read, event or {}].
static func newest(after_id: int, pos: Vector3, max_dy := INF) -> Array:
	var got := {}
	var last := after_id
	for e in NoiseEvents.after(after_id):
		last = maxi(last, int(e.id))
		if hears(e, pos, max_dy):
			got = e
	return [last, got]
