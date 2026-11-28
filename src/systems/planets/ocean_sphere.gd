class_name OceanSphere
extends GasSphere
## Issue #879: a round sea, the water type made a real ball (the water_ball type in
## content/core/planets/types.json, the tide world: content/core/planets/port_tide.json).
## The gas ball's shape (GasSphere): its radius is the deck's level and the sea lies
## `depth` metres below it all the way round, a smooth ball. Unlike the cloud tops
## it holds things up: a speeder's hover model rides it (WorldGround.height_above),
## a ship can set down on it, and anything level the planet asks for (its outposts'
## pads, the speeder pad out front: PlanetTerrain's flat sites) stands up out of it.
## A person who ends up in it drowns (PlatformWorld.sea_ball).
##
## The swell: the water heaves `swell_m` metres every `swell_s` seconds in long
## crossing rollers. Only what floats on it feels that (height_above_ground, what
## the hover model asks); the collider, the mesh and anything standing on a pad keep
## the still sea of elevation(), so nothing built on it moves.
##
## Settings: the water_ball type's "surface".

var swell_m := 0.35
var swell_s := 7.0
var drown_m := 0.6
## A fixed clock for the swell (tests set it; the game leaves it -1: real time).
var swell_t := -1.0


func _init(r: float = 4500.0, surface: Dictionary = {}) -> void:
	super._init(r, surface)
	swell_m = float(surface.get("swell_m", swell_m))
	swell_s = maxf(0.5, float(surface.get("swell_s", swell_s)))
	drown_m = float(surface.get("drown_m", drown_m))


## The still sea, and every pad standing up out of it.
func elevation(dir: Vector3, _grow: float = 2.0, _soft: float = 0.0) -> float:
	if flat_sites.is_empty():
		return -depth
	var m := dir_map(dir)
	return _apply_flat_sites(m.x, m.y, -depth)


## The sea's own level here (no pads): metres above the bare ball.
func sea_level() -> float:
	return -depth


## The swell's lift at direction `dir` now: two long rollers crossing, metres
## (0 on a pad and on still water).
func swell(dir: Vector3) -> float:
	if swell_m <= 0.0:
		return 0.0
	var t := swell_t if swell_t >= 0.0 else Time.get_ticks_msec() / 1000.0
	var p := dir * radius
	var w := TAU / swell_s
	var a := sin(p.x * 0.045 + p.z * 0.02 - t * w)
	var b := sin(p.z * 0.05 - p.x * 0.015 - t * w * 0.73 + 1.3)
	return swell_m * (a * 0.6 + b * 0.4)


## How far over the water (or the pad) p is, with the swell under it on open water.
func height_above_ground(p: Vector3) -> float:
	var dir := (p - center).normalized()
	var e := elevation(dir)
	var lift := swell(dir) if e <= -depth + 0.01 else 0.0
	return (p - center).length() - radius - e - lift


## Is world point p in the sea: over open water (no pad under it) and within
## drown_m of the surface or below it?
func in_sea(p: Vector3) -> bool:
	var dir := (p - center).normalized()
	if elevation(dir) > -depth + 0.25:
		return false                   # a pad (or its ramp) is under it
	return (p - center).length() - radius + depth <= drown_m
