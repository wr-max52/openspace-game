class_name StationTactics
extends RefCounted
## How the station's Remnant fight aboard (issue #314 follow-up). The station has
## no navmesh: its soldiers walk straight at a point (NpcBody.free_walk). Left to
## that, a trooper told to run at you through a wall, or at a cover spot of the
## town's far below, ends up pinned in a room's corner. This gives their garrison
## two things in the station's own terms:
##
##   route   where to walk next on the way to a point: out of the room by its door
##           (on the room's middle line), round the walkway ring, in at the
##           target's door. Every leg is straight across open floor: a room is a
##           wedge (convex), the walkway a ring walked in short chords. A point on
##           another floor or in another tower is as far as this floor goes: the
##           walkway, facing that way. Nobody rides the elevator.
##   cover   a spot behind the furniture of the room the soldier is in (bunks,
##           desks, card tables, lockers: the fill's own colliders), with that
##           furniture between it and the threat (CoverPicker). On the walkway,
##           behind what stands on it near him (the deck's barricades).
##
## With both, a trooper on the alarm ducks behind his room's furniture and fights
## from there (GuardBrain's COMBAT), and once nobody has been seen for its
## hunt_after_s he leaves by the door and hunts round the walkway (GuardBrain's
## hunt, its search points routed here).
##
## Layout and routing are pure, in the station's frame (route_local, where), so
## they test headless; the cover reads the fill's collision shapes once a floor is
## built. Numbers: the station config's "remnant" "tactics" block.

const UP := Vector3.UP

var station                         ## SpaceStation
var hull: StationHull
var cfg: Dictionary = {}            ## "remnant" "tactics"
var _rooms: Dictionary = {}         ## "tower/fi" -> StationHull.floor_rooms
var _boxes: Dictionary = {}         ## area key -> boxes in the area's frame (CoverPicker's)
var _spots: Dictionary = {}         ## area key -> CoverPicker.candidates of those boxes


func _init(space_station, station_hull: StationHull = null) -> void:
	station = space_station
	hull = station_hull if station_hull != null else space_station.hull
	cfg = hull.cfg.get("remnant", {}).get("tactics", {})


func n(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


# ------------------------------------------------------------------ where

## The walkway ring's radius where routes run: clear of the deck's barricades
## (their outer face 15.85 m out) and the checkpoint arch's posts (17.6 m).
func ring_r() -> float:
	return hull.gap_r + hull.walk * n("ring", 0.7)


func rooms(t: Dictionary, fi: int) -> Array:
	var key := "%s/%d" % [str(t.id), fi]
	if not _rooms.has(key):
		_rooms[key] = hull.floor_rooms(t, fi)
	return _rooms[key]


## The floor of tower `t` a body at height `y` stands on (-1: none).
func floor_index(t: Dictionary, y: float) -> int:
	var fl: Array = t.floors
	for i in fl.size():
		var fy := float(fl[i].y)
		if y >= fy - 0.6 and y < fy + hull.floor_h - 0.5:
			return i
	return -1


## Where point `p` (the station's frame) is: { kind, tower, fi, y (the floor's), c
## (the tower's middle, Vector2), r (out from it), a (round it), room (kind "room" /
## "shut") }. kind: "room" (an open room), "shut" (a locked one), "walk" (the
## walkway ring), "tunnel" (the ring of rooms where no room is: a tunnel's
## corridor), "gap" (over the open middle or a bridge to the shaft), "none".
func where(p: Vector3) -> Dictionary:
	for t in hull.towers:
		var fi := floor_index(t, p.y)
		if fi < 0:
			continue
		var f: Dictionary = t.floors[fi]
		var c: Vector2 = t.c
		var r := Vector2(p.x - c.x, p.z - c.y).length()
		if r > float(f.r):
			continue
		var w := { "tower": t, "fi": fi, "y": float(f.y), "c": c, "r": r, "a": atan2(p.z - c.y, p.x - c.x) }
		if r < hull.gap_r:
			w["kind"] = "gap"
		elif r <= hull.gap_r + hull.walk + 0.2:
			w["kind"] = "walk"
		else:
			w["kind"] = "tunnel"
			for room in rooms(t, fi):
				if absf(wrapf(float(w.a) - float(room.a), -PI, PI)) <= float(room.half):
					w["kind"] = "room" if bool(room.open) else "shut"
					w["room"] = room
					break
		return w
	return { "kind": "none" }


static func _same_floor(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("kind", "none")) != "none" and str(b.get("kind", "none")) != "none" \
		and str(a.tower.id) == str(b.tower.id) and int(a.fi) == int(b.fi)


## A point `r` out at angle `a` round where `w` is (its tower, its floor).
static func polar(w: Dictionary, a: float, r: float) -> Vector3:
	var c: Vector2 = w.c
	return Vector3(c.x + cos(a) * r, float(w.y), c.y + sin(a) * r)


# ------------------------------------------------------------------ route

## Where to walk next from `from` on the way to `to` (both in the station's frame).
func route_local(from: Vector3, to: Vector3) -> Vector3:
	var a := where(from)
	var k := str(a.kind)
	if k == "none" or k == "gap":
		return to
	var b := where(to)
	var rw := ring_r()
	# Not on this floor (another floor, the other tower, the bay, outside): the
	# walkway here, the side facing it, is as far as we go.
	if not _same_floor(a, b) or str(b.kind) in ["gap", "shut"]:
		var c: Vector2 = a.c
		var toward := atan2(to.z - c.y, to.x - c.x) if str(b.kind) != "shut" else float(b.a)
		to = polar(a, toward, rw)
		b = where(to)
	var door_in := n("door_in_m", 0.8)
	match k:
		"room", "shut":
			if str(b.kind) == "room" and int(b.room.k) == int(a.room.k):
				return to                                   # the same room: straight there (a wedge is convex)
			# arrive_m past the door point: a body stops walking 0.8 m short of its
			# point (NpcBody._free_walk), so a closer test would hold it there for good.
			if float(a.r) > float(a.room.r0) + door_in + n("arrive_m", 1.2):
				return polar(a, float(a.room.a), float(a.room.r0) + door_in)    # to the door
			return polar(a, float(a.room.a), rw)                                # out onto the walkway
		"tunnel":
			if str(b.kind) == "tunnel" and absf(wrapf(float(b.a) - float(a.a), -PI, PI)) * float(a.r) < 3.0:
				return to
			return polar(a, float(a.a), rw)
	# On the walkway: round the ring to the target's angle, then in.
	var ta := float(b.room.a) if str(b.kind) == "room" else float(b.a)
	var d := wrapf(ta - float(a.a), -PI, PI)
	var step := deg_to_rad(n("step_deg", 20.0))
	if absf(d) * rw <= n("at_door_m", 1.2):
		match str(b.kind):
			"room":
				return polar(a, ta, float(b.room.r0) + door_in)              # in at its door
			"tunnel":
				return polar(a, ta, float(b.r))
		return to
	if str(b.kind) == "walk" and absf(d) <= step:
		return to
	return polar(a, float(a.a) + signf(d) * minf(absf(d), step), rw)


## route_local for a body in the world: its next point, in the world (`to` itself
## when there is nothing to route: INF, or off the station), stepped round the
## furniture in its way (around). Worked out every repath_s a body, not each frame.
var _legs: Dictionary = {}          ## Node3D -> [msec, goal (world), next (world)]

func route(g: Node3D, to: Vector3) -> Vector3:
	if to == Vector3.INF or station == null:
		return to
	var now := Time.get_ticks_msec()
	var leg = _legs.get(g, null)
	if leg != null and now - int(leg[0]) < int(n("repath_s", 0.25) * 1000.0) and (leg[1] as Vector3).distance_to(to) < 0.5:
		return leg[2]
	var here: Vector3 = station.to_local_point(g.global_position)
	var next: Vector3 = around(here, route_local(here, station.to_local_point(to)))
	var out: Vector3 = station.to_world(next)
	if not _legs.has(g) and _legs.size() >= 64:
		for k in _legs.keys():                 # bodies gone (dead and cleared, the deck reset)
			if not is_instance_valid(k):
				_legs.erase(k)
	_legs[g] = [now, to, out]
	return out


## `next` (the station's frame) or, when furniture of the area `from` is in (its
## room, or the walkway) stands across the straight line to it, a corner of the
## first such box to walk to first: the corner of the box grown by a body's
## width that is shortest from here to there and that can be walked to straight.
## Right beside that corner already, the next corner on round it.
func around(from: Vector3, next: Vector3) -> Vector3:
	var w := where(from)
	if not (str(w.kind) in ["room", "walk"]):
		return next
	var bx = boxes(w)
	if bx == null or (bx as Array).is_empty():
		return next
	var fr := area_frame(w)
	var to_area := fr.affine_inverse()
	var a3 := to_area * from
	var b3 := to_area * next
	var a := Vector2(a3.x, a3.z)
	var b := Vector2(b3.x, b3.z)
	var grow := n("body_r", 0.45)
	var hit: Array = []
	var best_t := INF
	for box in bx:
		if float(box.max[1]) - float(box.min[1]) < 0.3 or float(box.min[1]) > 1.2:
			continue                                   # a mat, a shelf overhead: walked over or under
		var r := [float(box.min[0]) - grow, float(box.min[2]) - grow, float(box.max[0]) + grow, float(box.max[2]) + grow]
		if a.x > r[0] and a.x < r[2] and a.y > r[1] and a.y < r[3]:
			continue                                   # brushing it already: walk on (the body's own unsticking)
		if not CoverPicker.segment_hits_rect(a, b, r):
			continue
		var t := _entry(a, b, r)
		if t < best_t:
			best_t = t
			hit = r
	if hit.is_empty():
		return next
	var m := 0.2
	var corners := [Vector2(hit[0] - m, hit[1] - m), Vector2(hit[2] + m, hit[1] - m), Vector2(hit[2] + m, hit[3] + m), Vector2(hit[0] - m, hit[3] + m)]
	var best := -1
	var best_len := INF
	for i in 4:
		var c: Vector2 = corners[i]
		if not _inside(w, Vector3(c.x, 0, c.y)):
			continue
		if CoverPicker.segment_hits_rect(a, c, hit):
			continue
		var l := a.distance_to(c) + c.distance_to(b)
		if l < best_len:
			best_len = l
			best = i
	if best < 0:
		return next
	var pick: Vector2 = corners[best]
	if a.distance_to(pick) < n("arrive_m", 1.2):
		# At that corner: on to whichever corner beside it is nearer the goal.
		var c1: Vector2 = corners[(best + 1) % 4]
		var c2: Vector2 = corners[(best + 3) % 4]
		pick = c1 if c1.distance_to(b) < c2.distance_to(b) else c2
		if not _inside(w, Vector3(pick.x, 0, pick.y)):
			return next
	return fr * Vector3(pick.x, 0.0, pick.y)


## Where along a-b (0..1) the segment enters rect r [minx, minz, maxx, maxz].
static func _entry(a: Vector2, b: Vector2, r: Array) -> float:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var ps := [-d.x, d.x, -d.y, d.y]
	var qs := [a.x - float(r[0]), float(r[2]) - a.x, a.y - float(r[1]), float(r[3]) - a.y]
	for i in 4:
		var pp: float = ps[i]
		var q: float = qs[i]
		if absf(pp) < 1e-9:
			continue
		var t := q / pp
		if pp < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
	return t0


# ------------------------------------------------------------------ cover

## The frame an area's boxes and spots are in: a room's (x out along its middle
## line, z across, origin the tower's middle on the floor), else the floor's (the
## station's axes, origin the tower's middle on the floor).
static func area_frame(w: Dictionary) -> Transform3D:
	var c: Vector2 = w.c
	var o := Vector3(c.x, float(w.y), c.y)
	if str(w.kind) == "room":
		var x := Vector3(cos(float(w.room.a)), 0, sin(float(w.room.a)))
		return Transform3D(Basis(x, UP, x.cross(UP)), o)
	return Transform3D(Basis.IDENTITY, o)


static func area_key(w: Dictionary) -> String:
	if not (str(w.get("kind", "none")) in ["room", "walk", "tunnel", "shut"]):
		return str(w.get("kind", "none"))
	if str(w.get("kind", "none")) == "room":
		return "%s/%d/room%d" % [str(w.tower.id), int(w.fi), int(w.room.k)]
	return "%s/%d/walk" % [str(w.tower.id), int(w.fi)]


## The fill's colliders in area `w`, as CoverPicker boxes in its frame ({ id, kind,
## min, max }), or null while that floor's fill is not built yet.
func boxes(w: Dictionary):
	var key := area_key(w)
	if _boxes.has(key):
		return _boxes[key]
	var node: Node3D = null
	if station != null and station.get("fill_floors") is Array:
		for ff in station.fill_floors:
			if str(ff.tower.id) == str(w.tower.id) and int(ff.i) == int(w.fi):
				if not bool(ff.built):
					return null
				node = ff.node
	if node == null or not node.is_inside_tree():
		return null
	var to_area: Transform3D = area_frame(w).affine_inverse() * station.frame.affine_inverse()
	var out: Array = []
	for cs in node.find_children("*", "CollisionShape3D", true, false):
		var box := (cs as CollisionShape3D).shape as BoxShape3D
		if box == null:
			continue
		var xf: Transform3D = to_area * (cs as CollisionShape3D).global_transform
		var at := where(area_frame(w) * xf.origin)          # the box's middle, in the station's frame
		if area_key(at) != key or str(at.kind) != str(w.kind):
			continue
		var half := box.size * 0.5
		var ext := Vector3(
			absf(xf.basis.x.x) * half.x + absf(xf.basis.y.x) * half.y + absf(xf.basis.z.x) * half.z,
			absf(xf.basis.x.y) * half.x + absf(xf.basis.y.y) * half.y + absf(xf.basis.z.y) * half.z,
			absf(xf.basis.x.z) * half.x + absf(xf.basis.y.z) * half.y + absf(xf.basis.z.z) * half.z)
		var mn := xf.origin - ext
		var mx := xf.origin + ext
		out.append({ "id": "b%d" % out.size(), "kind": "solid", "min": [mn.x, mn.y, mn.z], "max": [mx.x, mx.y, mx.z] })
	_boxes[key] = out
	return out


## True if a spot (the area's frame) is inside area `w` with room for a body: in a
## room, between its door and window and off its side walls; on the walkway, on it.
func _inside(w: Dictionary, p: Vector3) -> bool:
	if str(w.kind) == "room":
		var room: Dictionary = w.room
		return p.x > float(room.r0) + 0.3 and Vector2(p.x, p.z).length() < float(room.r1) - 0.5 \
			and absf(p.z) <= p.x * tan(float(room.half)) - StationHull.INNER_WALL - 0.45
	var r := Vector2(p.x, p.z).length()
	return r > hull.gap_r + 0.6 and r < hull.gap_r + hull.walk - 0.4


## A cover spot (the world) for body `g` against `threat` (the world): behind the
## furniture of the room it is in (or what stands on the walkway near it), not in
## `taken` (world spots others hold). INF: none here.
func cover(g: Node3D, threat: Vector3, taken: Array = []) -> Vector3:
	if station == null or threat == Vector3.INF:
		return Vector3.INF
	var here := station.to_local_point(g.global_position) as Vector3
	var w := where(here)
	if not (str(w.kind) in ["room", "walk"]):
		return Vector3.INF
	var bx = boxes(w)
	if bx == null:
		return Vector3.INF
	var key := area_key(w)
	var fr := area_frame(w)
	var to_area := fr.affine_inverse()
	if not _spots.has(key):
		var all: Array = CoverPicker.candidates(bx, Vector3.ZERO, 1000.0, n("standoff", 0.8), n("spot_step", 1.4),
			["solid"], n("cover_min_height", 0.75))
		_spots[key] = all.filter(func(s): return _inside(w, s.pos))
	var spots: Array = _spots[key]
	if str(w.kind) == "walk":
		var me := to_area * here
		var reach := n("walk_cover_reach", 12.0)
		spots = spots.filter(func(s): return Vector2((s.pos as Vector3).x - me.x, (s.pos as Vector3).z - me.z).length() <= reach)
	var mine: Array = taken.map(func(p): return to_area * (station.to_local_point(p) as Vector3))
	var from := to_area * here
	var th := to_area * (station.to_local_point(threat) as Vector3)
	var i := CoverPicker.pick(from, th, spots, mine, n("cover_min_d", 1.5), n("cover_max_d", 80.0))
	if i < 0:
		return Vector3.INF
	var p: Vector3 = spots[i].pos
	return station.to_world(fr * Vector3(p.x, 0.0, p.z))
