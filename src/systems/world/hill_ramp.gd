class_name HillRamp
extends RefCounted
## Issue #877: the lit road up a mountain town's peak. Pure geometry: a road
## `width_m` wide curling up round the peak at `grade` (rise over run), out past
## the rock's widest foot, from the sand to the top, where it comes round to the
## gate's side (+x) and runs straight in over the shelves to the town's apron as a
## level bridge. All in the peak's own frame (RockMountain's: y up from its
## mesh's origin, the top at y = `top`).
##
## Each piece is a box the way the town's ramps are: a chord of the curve, its own
## frame turned to run along +x, rising +x from `y0` to `y1` (WorldGround's rise
## boxes, so a speeder rides up it), with a kerb each side. Settlements turns them
## into ground, colliders and a look.

## The road: { segments: [{ xf (Transform3D, peak frame: +x along the road, +z in
## toward the rock), len, y0, y1, a0, a1, mouth (where the bridge turns in) }], bridge:
## { x0, x1, y }, radius, start_angle, lamps: [Vector3 peak frame], path:
## [Vector3, ...] (the middle of the road from the sand to the gate, for a driver) }.
## `sand`: Callable(angle) -> the sand's height under the road at that angle.
## `top_edge`: how far out the top reaches toward +x (where the bridge starts).
static func plan(cfg: Dictionary, foot: float, top: float, top_edge: float, sand: Callable) -> Dictionary:
	var w := float(cfg.get("width_m", 10.0))
	var r := foot + float(cfg.get("out_m", 16.0)) + w * 0.5
	var grade := maxf(float(cfg.get("grade", 0.1)), 0.02)
	var seg := float(cfg.get("segment_m", 9.0))
	# Where it starts: as far back round the peak as its climb needs (the sand's
	# height there decides the climb, so twice over).
	var y0 := float(sand.call(-PI))
	var sweep := 0.0
	for _i in 2:
		sweep = (top - y0) / grade / r
		y0 = float(sand.call(-sweep))
	sweep = maxf((top - y0) / grade / r, 0.2)
	var n := maxi(2, ceili(sweep * r / seg))
	var segs: Array = []
	var path: Array = []
	var lamps: Array = []
	var lamp_m := float(cfg.get("lamp_m", 18.0))
	var next_lamp := 0.0
	var along := 0.0
	for i in n:
		var a0 := -sweep + sweep * float(i) / float(n)
		var a1 := -sweep + sweep * float(i + 1) / float(n)
		var p0 := Vector3(cos(a0) * r, lerpf(y0, top, float(i) / float(n)), sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, lerpf(y0, top, float(i + 1) / float(n)), sin(a1) * r)
		var d := Vector2(p1.x - p0.x, p1.z - p0.z)
		var mid := (p0 + p1) * 0.5
		var yaw := atan2(-d.y, d.x)
		# The last pieces, where the bridge turns in, have no kerb on their inner side.
		segs.append({ "xf": Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, 0.0, mid.z)), "len": d.length() + 0.6,
			"y0": p0.y, "y1": p1.y, "a0": a0, "a1": a1, "mouth": a1 > -PI * 0.5 and sin(a1) * r > -w * 0.5 - 0.5 })
		path.append(p0)
		while next_lamp <= along + d.length():
			var t := (next_lamp - along) / maxf(d.length(), 0.001)
			var q := p0.lerp(p1, t)
			lamps.append(q + Vector3(cos(lerpf(a0, a1, t)), 0.0, sin(lerpf(a0, a1, t))) * (w * 0.5 - 0.3))
			next_lamp += lamp_m
		along += d.length()
	var gate := Vector3(r, top, 0.0)
	path.append(gate)
	# The bridge in: level, from the road's end to just over the top's edge.
	var x0 := top_edge - 3.0
	var bx := x0 + 1.0
	while bx < r - w * 0.5:
		lamps.append(Vector3(bx, top, w * 0.5 - 0.3))
		lamps.append(Vector3(bx, top, -w * 0.5 + 0.3))
		bx += lamp_m
	path.append(Vector3(x0, top, 0.0))
	return { "segments": segs, "bridge": { "x0": x0, "x1": r + w * 0.5, "y": top, "half": w * 0.5 },
		"radius": r, "start_angle": -sweep, "width": w, "lamps": lamps, "path": path, "y0": y0 }


## A piece's slab collider: its centre and basis in the piece's own frame (rising
## +x from y0 to y1), `thick` deep under its top face.
static func slab(len: float, y0: float, y1: float, thick := 0.5) -> Transform3D:
	var angle := atan2(y1 - y0, len)
	var basis := Basis(Vector3(0, 0, 1), angle)
	return Transform3D(basis, Vector3(0.0, (y0 + y1) * 0.5, 0.0) - basis.y * (thick * 0.5))
