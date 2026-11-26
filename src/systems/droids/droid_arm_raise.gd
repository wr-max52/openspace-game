class_name DroidArmRaise
extends SkeletonModifier3D
## Issue #722: brings a rigged droid's arm up and out in front, on top of whatever
## clip is playing (the assassin model has no clip with an arm raised). The upper
## arm and then the forearm are each turned to point along a direction given in
## `frame`'s space (the droid's look, facing -Z); the hand follows. `influence`
## (SkeletonModifier3D's own) blends it in from the clip: 0 the clip as it is, 1
## the arm fully out. T-89 holds his plasma welder out this way to weld your ship;
## any droid could hold a tool or a gun out the same way.

var frame: Node3D                          ## the look whose space the directions are in
var upper := "RightArm"
var fore := "RightForeArm"
var hand := "RightHand"
var upper_dir := Vector3(0.12, -0.5, -0.86)  ## the upper arm: forward and down from the shoulder
var fore_dir := Vector3(-0.2, 0.15, -0.97)   ## the forearm: straight ahead, a little in and up


## Added under `rig`'s skeleton, its directions in `p_frame`'s space (the droid's
## "Model", facing -Z); `dirs` { upper, fore } (a carry's "raise") overrides them.
## Null when the rig has no such arm.
static func make(rig: Node3D, p_frame: Node3D, dirs: Dictionary = {}) -> DroidArmRaise:
	var sk := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null or sk.find_bone("RightArm") < 0:
		return null
	var r := DroidArmRaise.new()
	r.name = "ArmRaise"
	r.frame = p_frame
	r.influence = 0.0
	r.active = false
	if dirs.get("upper") is Array:
		r.upper_dir = Vector3(float(dirs.upper[0]), float(dirs.upper[1]), float(dirs.upper[2]))
	if dirs.get("fore") is Array:
		r.fore_dir = Vector3(float(dirs.fore[0]), float(dirs.fore[1]), float(dirs.fore[2]))
	sk.add_child(r)
	return r


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or frame == null or not is_instance_valid(frame):
		return
	var to_sk := sk.global_transform.basis.orthonormalized().inverse() * frame.global_transform.basis.orthonormalized()
	_aim(sk, sk.find_bone(upper), sk.find_bone(fore), (to_sk * upper_dir).normalized())
	_aim(sk, sk.find_bone(fore), sk.find_bone(hand), (to_sk * fore_dir).normalized())


## Turn bone `b` (in skeleton space) so the line to its child `c` runs along `want`.
func _aim(sk: Skeleton3D, b: int, c: int, want: Vector3) -> void:
	if b < 0 or c < 0:
		return
	var g := sk.get_bone_global_pose(b)
	var cur := sk.get_bone_global_pose(c).origin - g.origin
	if cur.length_squared() < 1e-8:
		return
	g.basis = Basis(Quaternion(cur.normalized(), want)) * g.basis
	sk.set_bone_global_pose(b, g)
