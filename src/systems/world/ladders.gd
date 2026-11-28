extends RefCounted
## Ladders you can climb (the climb itself: src/systems/player/ladder_climb.gd; who
## gets you on one: src/systems/player/player_climber.gd).
##
## A registry, not nodes. Whatever draws a ladder's rails and rungs (StationHull's
## roof and gantry ladders, StationFill's stacked shacks and containers and the
## engine rooms' catwalk ladders) also writes one spec() for it, in its own frame;
## the node that frame hangs off adds it here (add), so the player looks the near
## ones up each tick with no tree scan. A spec:
##   xf    its frame: origin the middle of the rungs at their foot (the floor you
##         stand on at the bottom), x the way a climber faces it (into the rungs),
##         y up the ladder
##   h     how far above the foot the floor it leads to is (m): you climb out onto
##         that floor `exit` metres past the rungs (x), where there is room to stand
## A ladder is only as climbable as its spec: the rails and rungs are look only.

static var _all: Array = []         ## { node: WeakRef, xf, h, exit }

## Climbing out at the top: your feet this far past the rungs (along x).
const EXIT := 0.7
## Where you hang on a ladder: your middle this far back from its rungs.
const STAND := 0.5


## A ladder `h` high in some frame: its foot at `foot`, faced along `facing`
## (flattened), up `up`.
static func spec(foot: Vector3, facing: Vector3, h: float, up := Vector3.UP, exit := EXIT) -> Dictionary:
	var f := (facing - up * facing.dot(up)).normalized()
	return { "xf": Transform3D(Basis(f, up, f.cross(up)), foot), "h": h, "exit": exit }


## Note ladder `s` (a spec) against `anchor`, whose frame its xf is in. It goes when
## the anchor does.
static func add(anchor: Node3D, s: Dictionary) -> void:
	_all.append({ "node": weakref(anchor), "xf": s.xf, "h": float(s.h), "exit": float(s.get("exit", EXIT)) })


## Forget every ladder of `anchor` (or, with null, every one).
static func clear(anchor: Node3D = null) -> void:
	if anchor == null:
		_all.clear()
		return
	_all = _all.filter(func(e): return e.node.get_ref() != anchor)


static func count() -> int:
	return _all.size()


## A spec in the world, for ladder_climb: { foot, up, fwd, side, h, exit }.
static func world_of(s: Dictionary, frame := Transform3D.IDENTITY) -> Dictionary:
	var xf: Transform3D = frame * (s.xf as Transform3D)
	var b := xf.basis.orthonormalized()
	return { "foot": xf.origin, "fwd": b.x, "up": b.y, "side": b.z, "h": float(s.h), "exit": float(s.get("exit", EXIT)) }


## Every ladder within `radius` of `pos` (of the line up its rungs), in the world.
## Ladders whose anchor is gone are dropped as it goes.
static func near(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var dead := false
	for e in _all:
		var n = e.node.get_ref()
		if n == null or not is_instance_valid(n) or not (n as Node3D).is_inside_tree():
			dead = dead or n == null or not is_instance_valid(n)
			continue
		var w := world_of(e, (n as Node3D).global_transform)
		var l := local(w, pos)
		var above := clampf(l.y, 0.0, float(w.h))
		if Vector2(l.x, l.z).length() <= radius and absf(l.y - above) <= radius:
			out.append(w)
	if dead:
		_all = _all.filter(func(e): return e.node.get_ref() != null and is_instance_valid(e.node.get_ref()))
	return out


## `pos` in the ladder's frame: x how far past the rungs (+: the side you climb out
## on at the top), y how high over its foot, z across.
static func local(w: Dictionary, pos: Vector3) -> Vector3:
	var d := pos - (w.foot as Vector3)
	return Vector3(d.dot(w.fwd), d.dot(w.up), d.dot(w.side))


## Where you hang with your feet `u` metres up the ladder.
static func stand_at(w: Dictionary, u: float) -> Vector3:
	return (w.foot as Vector3) - (w.fwd as Vector3) * STAND + (w.up as Vector3) * u


## Where you stand once climbed out at the top.
static func exit_at(w: Dictionary) -> Vector3:
	return (w.foot as Vector3) + (w.fwd as Vector3) * float(w.exit) + (w.up as Vector3) * float(w.h)


## Standing at its foot (feet near the floor there), close in front of the rungs
## and not off to one side: walking into it now gets you on.
static func at_foot(w: Dictionary, pos: Vector3) -> bool:
	var l := local(w, pos)
	return l.y > -0.5 and l.y < minf(0.9, float(w.h) * 0.5) and l.x > -1.0 and l.x < 0.15 and absf(l.z) < 0.55


## Standing on the floor at its top, just past where it comes up: [E] climbs down.
static func at_top(w: Dictionary, pos: Vector3) -> bool:
	var l := local(w, pos)
	return absf(l.y - float(w.h)) < 0.6 and l.x > -0.2 and l.x < 1.9 and absf(l.z) < 1.0
