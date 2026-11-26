class_name SightGate
extends RefCounted
## Issue #693: build by sight. Could the viewer see a thing at `at` yet? A thing
## is only worth building once it could come into view: near enough (`range_m`)
## and not hidden over the curve of a round planet. On a flat world only the
## range counts. Pure maths, no nodes: every builder asks the same question
## (outposts, ranches, native camps, the barge, the wreck field), so the next
## planet, outpost or town gets "nothing built on the far side" for free.
##
## Numbers are data: the "sight" block of a world's "detail"
## (content/core/worlds/<id>.json, or content/core/planets/types.json):
##   range_m          -- never built further off than this (metres)
##   horizon_margin_m -- built this far before it crests the horizon
##   release_m        -- let go again only this much further out than it came in
##
## A thing that has come in stays until it is `release_m` past where it came in
## (keep()), so it never flickers in and out on the edge.

var range_m := 9000.0
var horizon_margin_m := 1500.0
var release_m := 2500.0


func setup(cfg: Dictionary) -> SightGate:
	range_m = float(cfg.get("range_m", range_m))
	horizon_margin_m = float(cfg.get("horizon_margin_m", horizon_margin_m))
	release_m = float(cfg.get("release_m", release_m))
	return self


## From a world's "detail" block (its "sight" block inside; defaults if none).
static func from_detail(detail: Dictionary) -> SightGate:
	return SightGate.new().setup(detail.get("sight", {}))


## True when a thing at `at`, standing `height` metres tall, could be in view from
## `eye`. `center`/`radius` are the planet's ball (radius 0 = flat ground).
func could_see(eye: Vector3, at: Vector3, center: Vector3, radius: float, height := 30.0) -> bool:
	return visible_within(eye, at, center, radius, height, 0.0)


## The same with the release margin added: for a thing already built.
func keep(eye: Vector3, at: Vector3, center: Vector3, radius: float, height := 30.0) -> bool:
	return visible_within(eye, at, center, radius, height, release_m)


func visible_within(eye: Vector3, at: Vector3, center: Vector3, radius: float, height: float, extra: float) -> bool:
	var d := eye.distance_to(at)
	if d > range_m + extra:
		return false
	if radius <= 0.0:
		return true
	return d <= horizon_reach(eye, center, radius, height) + horizon_margin_m + extra


## How far the line of sight reaches past the ball's rim: the eye's distance to
## its horizon plus a `height` m tall thing's distance to the same horizon.
static func horizon_reach(eye: Vector3, center: Vector3, radius: float, height: float) -> float:
	var er := eye.distance_to(center)
	var to_eye := sqrt(maxf(er * er - radius * radius, 0.0))
	var top := radius + maxf(height, 0.0)
	var to_top := sqrt(maxf(top * top - radius * radius, 0.0))
	return to_eye + to_top
