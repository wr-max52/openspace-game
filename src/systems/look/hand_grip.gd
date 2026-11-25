class_name HandGrip
extends RefCounted
## A rigged hand closed round a grip (issue #324), solved from the skin's own bones,
## not hand-tuned angles.
##
## A grip is a bar: the sword's hilt, a rifle's pistol grip, its handguard. The bar
## lies across the palm along the knuckle line (little finger to index, so toward
## the thumb), turned `tilt_deg` so its little-finger end sits nearer the wrist, the
## way a fist really closes on a stick. Each finger is swung in line with the
## others (the model's rest hand is splayed, and a splayed finger curled about its
## own joint crosses the bar instead of wrapping it), then wrapped round the bar:
## each joint goes where the circle its segment can reach meets the circle `radius`
## round the bar's axis (the bar's own radius plus half a finger). The thumb wraps
## the other way round, over the front of the bar, and comes to rest on the index
## finger ("wrap"), or lies along the bar ("along").
##
## solve() works in the hand bone's rest frame, where nothing moves with the arm, so
## a solve is done once per skin and grip spec and kept. It gives the finger bones'
## local rotations, and `frame`: where the bar is in the hand (origin its middle
## under the fingers, +Z along it toward the thumb, +X out of the palm), which is
## what a hold puts on the weapon's grip.
##
## Spec (content/look/hand_weapons.json "hold_3p" "hands", per hand):
##   radius:   m from the bar's axis to the finger bones (bar radius + half a finger)
##   curl:     0..1 per finger [index, middle, ring, little] (1 = wrapped right
##             round; a trigger finger less)
##   tilt_deg: the bar's turn across the palm, little-finger end toward the wrist
##   thumb:    "wrap" or "along"; thumb_radius m from the axis to the thumb's bones
##   max_deg:  the most each finger joint bends [base, middle, tip]

const FINGERS := ["Index", "Middle", "Ring", "Pinky"]
const TIP := 0.8      ## a finger's last segment, as a share of the one before it


## { rots: { bone name: Quaternion (local pose) }, frame: Transform3D (hand bone
## space) }, or {} when the skin has no such hand.
static func solve(skel: Skeleton3D, hand: String, spec: Dictionary) -> Dictionary:
	var hb := skel.find_bone(hand)
	if hb < 0 or skel.find_bone(hand + "Index1") < 0 or skel.find_bone(hand + "Pinky1") < 0:
		return {}
	var to_hand := global_rest(skel, hb).affine_inverse()
	var rest := func(n: String) -> Transform3D:
		var bi := skel.find_bone(n)
		return to_hand * global_rest(skel, bi) if bi >= 0 else Transform3D()
	var radius := float(spec.get("radius", 0.029))
	var curl: Array = spec.get("curl", [1.0, 1.0, 1.0, 1.0])
	var mx: Array = spec.get("max_deg", [90.0, 105.0, 80.0])
	var k_index: Vector3 = rest.call(hand + "Index1").origin
	var k_pinky: Vector3 = rest.call(hand + "Pinky1").origin
	var axis := (k_index - k_pinky).normalized()
	# The palm side: the way a finger bends, which is the side the thumb is on.
	var mid_dir := (rest.call(hand + "Middle2").origin - rest.call(hand + "Middle1").origin as Vector3).normalized()
	var palm := axis.cross(mid_dir).normalized()
	var turn := 1.0
	if palm.dot(rest.call(hand + "Thumb2").origin - k_index) < 0.0:
		palm = -palm
		turn = -1.0
	# Across the palm: the little-finger end toward the wrist (away from the fingers).
	var tilt := deg_to_rad(float(spec.get("tilt_deg", 0.0)))
	if tilt != 0.0:
		var t := Basis(palm, tilt)
		if (t * axis).dot(mid_dir) < axis.dot(mid_dir):
			t = Basis(palm, -tilt)
		axis = (t * axis).normalized()
	# One bar for every finger: its axis through the middle of the knuckles' centres.
	var mid := Vector3.ZERO
	for f in FINGERS:
		mid += (rest.call(hand + str(f) + "1").origin as Vector3) + palm * radius
	mid /= FINGERS.size()
	var bar := { "mid": mid, "axis": axis, "radius": radius }
	var rots := {}
	var chains := {}
	for fi in FINGERS.size():
		var names := _chain(skel, hand + str(FINGERS[fi]))
		if names.is_empty():
			continue
		var w := float(curl[fi]) if fi < curl.size() else 1.0
		chains[FINGERS[fi]] = _wrap(names, rest, Basis(), bar, axis * turn, w, mx, INF, rots)
	if chains.is_empty():
		return {}
	var frame := Transform3D(Basis(palm, axis.cross(palm), axis).orthonormalized(), mid)
	var thumb := _chain(skel, hand + "Thumb")
	if not thumb.is_empty():
		var parent: Basis = rest.call(skel.get_bone_name(skel.get_bone_parent(skel.find_bone(thumb[0])))).basis.orthonormalized()
		var tb := bar.duplicate()
		tb.radius = float(spec.get("thumb_radius", radius + 0.003))
		if str(spec.get("thumb", "wrap")) == "along":
			_along(thumb, rest, parent, tb, rots)
		else:
			# Over the front of the bar, the other way round from the fingers, drifting
			# along it onto the index finger.
			var idx: Array = chains.get("Index", [])
			var to := axis.dot((idx[0] if not idx.is_empty() else mid) - mid) + float(spec.get("thumb_over", 0.004))
			_wrap(thumb, rest, parent, tb, -axis * turn, 1.0, [120.0, 90.0, 90.0], to, rots)
	return { "rots": rots, "frame": frame }


## A bone's rest in skeleton space, from the local rests up its chain
## (Skeleton3D.get_bone_global_rest is stale on a skeleton not yet in the tree).
static func global_rest(skel: Skeleton3D, bi: int) -> Transform3D:
	var t := Transform3D()
	while bi >= 0:
		t = skel.get_bone_rest(bi) * t
		bi = skel.get_bone_parent(bi)
	return t


## The bone names of a finger, base to tip ("RightHandIndex1".."3"), or [].
static func _chain(skel: Skeleton3D, prefix: String) -> Array:
	var names: Array = []
	for i in 3:
		if skel.find_bone(prefix + str(i + 1)) < 0:
			return []
		names.append(prefix + str(i + 1))
	return names


## Wrap a three-bone chain round the bar, turning about `about` (the bar's axis, the
## way this chain closes): each segment swung in line, then aimed at the point on
## the bar's circle it can reach. `w` scales the bends (0 = straight), `mx` caps
## each joint (degrees). `to` (finite) drifts the chain along the bar to that axial
## place by the last joint. Writes the local rotations into `rots`; returns the
## joints' new places (hand space), base to tip.
static func _wrap(names: Array, rest: Callable, parent: Basis, bar: Dictionary, about: Vector3, w: float,
		mx: Array, to: float, rots: Dictionary) -> Array:
	var axis: Vector3 = bar.axis
	var mid: Vector3 = bar.mid
	var radius: float = bar.radius
	var xf: Array = [rest.call(names[0]), rest.call(names[1]), rest.call(names[2])]
	var pts: Array = [xf[0].origin, xf[1].origin, xf[2].origin]
	pts.append(pts[2] + (pts[2] - pts[1]) * TIP)
	var d := (pts[1] - pts[0] as Vector3).normalized()
	var flat := (d - axis * d.dot(axis)).normalized()
	var spread := _arc(d, flat)
	var p: Vector3 = pts[0]
	var prev := 0.0
	var out: Array = [p]
	for i in 3:
		var seg := spread * (pts[i + 1] - pts[i] as Vector3)
		var seg_flat := seg - axis * seg.dot(axis)
		var length := seg.length()
		var step := 0.0
		if is_finite(to):
			step = clampf((to - axis.dot(p - mid)) / float(3 - i), -length * 0.7, length * 0.7)
		var reach := sqrt(maxf(length * length - step * step, 0.0))
		# Where a circle `reach` round this joint meets the bar's circle, the way the
		# chain closes.
		var c := mid + axis * axis.dot(p - mid)
		var v := p - c
		v -= axis * v.dot(axis)
		var rp := maxf(v.length(), 0.0001)
		var cos_a := clampf((rp * rp + radius * radius - reach * reach) / (2.0 * rp * radius), -1.0, 1.0)
		var q := c + Basis(about, acos(cos_a)) * (v / rp * radius)
		var ang := flat.signed_angle_to((q - p).normalized(), about) * w
		ang = minf(ang, prev + deg_to_rad(float(mx[i])))
		prev = ang
		var g := Basis(about, ang - flat.signed_angle_to(seg_flat.normalized(), about)) * spread
		if step != 0.0:
			# Lean the segment along the bar by the drift.
			var now := g * (pts[i + 1] - pts[i] as Vector3)
			var want := (now - axis * now.dot(axis)).normalized() * reach + axis * step
			g = _arc(now.normalized(), want.normalized()) * g
		var bone_basis: Basis = g * (xf[i].basis as Basis).orthonormalized()
		rots[names[i]] = (parent.inverse() * bone_basis).get_rotation_quaternion()
		parent = bone_basis
		p = p + g * (pts[i + 1] - pts[i])
		out.append(p)
	return out


## The thumb laid along the bar toward its +Z end (the blade, the muzzle), on the
## bar's surface on the palm side.
static func _along(names: Array, rest: Callable, parent: Basis, bar: Dictionary, rots: Dictionary) -> void:
	var axis: Vector3 = bar.axis
	var mid: Vector3 = bar.mid
	var radius: float = bar.radius
	var xf: Array = [rest.call(names[0]), rest.call(names[1]), rest.call(names[2])]
	var pts: Array = [xf[0].origin, xf[1].origin, xf[2].origin]
	pts.append(pts[2] + (pts[2] - pts[1]) * TIP)
	var p: Vector3 = pts[0]
	for i in 3:
		var seg := pts[i + 1] - pts[i] as Vector3
		var c := mid + axis * axis.dot(p - mid)
		var v := p - c
		v -= axis * v.dot(axis)
		# Along the bar, closing in on its surface over the three segments.
		var inward := (radius - v.length()) / float(3 - i)
		var want := axis * seg.length() + (v.normalized() * clampf(inward, -seg.length() * 0.7, seg.length() * 0.7))
		var g := _arc(seg.normalized(), want.normalized())
		var bone_basis: Basis = g * (xf[i].basis as Basis).orthonormalized()
		rots[names[i]] = (parent.inverse() * bone_basis).get_rotation_quaternion()
		parent = bone_basis
		p = p + g * seg


## The shortest turn taking unit vector a onto b.
static func _arc(a: Vector3, b: Vector3) -> Basis:
	var c := a.cross(b)
	var s := c.length()
	var dot := clampf(a.dot(b), -1.0, 1.0)
	if s < 1e-6:
		return Basis() if dot > 0.0 else Basis(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT, PI)
	return Basis(c / s, atan2(s, dot))
