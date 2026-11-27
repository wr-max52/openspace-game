class_name SeekerAim
extends RefCounted
## The seeker launcher's lock (content/core/weapons/seeker_launcher.json). Aimed in,
## it picks the ship or speeder nearest the crosshair inside lock_cone_deg and
## lock_range, and MissileLock (the ship seekers' own) builds the lock while it
## stays there: lock_time seconds to lock, bleeding off twice as fast once it
## drifts out, starting over on a new target. Not aimed in, nothing builds.
##
## What it can lock: every speeder still in one piece (SpeederNode.GROUP, its
## hull) and every ShipHull whose owner says hand weapons count on it now
## (ShipHull.lockable: the Remnant interceptor in the air, a barracks pad's
## interceptor). The pick is pure (best()), so it is tested headless.

const MissileLock := preload("res://src/systems/flight/missile_lock.gd")
const LeadSolver := preload("res://src/systems/flight/lead_solver.gd")

var lock = MissileLock.new()
var target: Node3D = null            ## what the lock is on (or building on); null: nothing in the cone
var cone_deg := 6.0
var reach := 450.0


func configure(c: Dictionary) -> void:
	lock.configure(c)
	cone_deg = float(c.get("lock_cone_deg", cone_deg))
	reach = float(c.get("lock_range", c.get("range", reach)))


func reset() -> void:
	lock.reset()
	target = null


## One frame. `active`: the launcher is up and aimed in. `from` and `fwd` are the
## view's eye and forward (the crosshair's ray).
func update(dt: float, active: bool, from: Vector3, fwd: Vector3, tree: SceneTree) -> void:
	if not active or tree == null:
		reset()
		return
	var nodes := candidates(tree)
	# Keep the target it has while it is still in the cone: a second one passing
	# closer to the crosshair does not snatch the lock away.
	if target != null and (not is_instance_valid(target) or not nodes.has(target)):
		target = null
	if target == null or LeadSolver.angle_deg(fwd, target.global_position - from) > cone_deg \
			or from.distance_to(target.global_position) > reach:
		var pts: Array[Vector3] = []
		for n: Node3D in nodes:
			pts.append(n.global_position)
		var i := best(from, fwd, pts, cone_deg, reach)
		if i >= 0:
			target = nodes[i]
		elif target != null and lock.progress <= 0.0:
			target = null
	if target == null:
		lock.update(dt, -1, fwd, Vector3.ZERO)
		return
	lock.update(dt, target.get_instance_id(), fwd, target.global_position - from)


func locked() -> bool:
	return target != null and is_instance_valid(target) and lock.is_locked()


## 0..1, the lock building (the HUD's ring).
func fraction() -> float:
	return lock.fraction() if target != null else 0.0


## What a seeker fired now homes on: the target once locked, else null (straight).
func seek_node() -> Node3D:
	return target if locked() else null


## The things it can lock on now, as nodes a seeker can turn after.
static func candidates(tree: SceneTree) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in tree.get_nodes_in_group(SpeederNode.GROUP):
		var s := n as SpeederNode
		if s == null or not is_instance_valid(s) or not s.is_inside_tree() or s.hull == null or s.riding:
			continue
		if s.model == null or not s.model.alive():
			continue
		out.append(s.hull)
	for n in tree.get_nodes_in_group(ShipHull.GROUP):
		var h := n as ShipHull
		if h != null and is_instance_valid(h) and h.is_inside_tree() and h.lockable():
			out.append(h)
	return out


## Index of the point nearest the crosshair's ray (the smallest angle off `fwd`)
## within `cone` degrees and `reach` m of `from`; -1 when none is.
static func best(from: Vector3, fwd: Vector3, points: Array[Vector3], cone: float, reach_m: float) -> int:
	var pick := -1
	var best_ang := INF
	for i in points.size():
		var to: Vector3 = points[i] - from
		var d := to.length()
		if d < 2.0 or d > reach_m:
			continue
		var ang := LeadSolver.angle_deg(fwd, to)
		if ang <= cone and ang < best_ang:
			best_ang = ang
			pick = i
	return pick
