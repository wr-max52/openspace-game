class_name SkinnedBody
extends RefCounted
## Dresses a CharacterKit body in a rigged model (a .glb with a Skeleton3D). The kit's
## joints stay the source of truth: BodyAnimator and the two-bone IK keep driving
## them, and every frame `sync()` copies their rotations onto the mapped bones. The
## kit's primitive meshes are hidden; the joints, the holster grip and the weapon
## mounts stay, so gameplay never sees the difference.
##
## Rest poses differ (the kit's arms hang straight down, a rigged model usually
## stands in an A- or T-pose), so `bind()` turns each mapped limb bone onto its
## kit joint's limb axis once, and stores the offset. After that a joint at rest
## puts its bone at rest along the kit's limb, and a joint rotation turns the bone
## by the same amount.
##
## Config (content/look/characters.json, "model" on an archetype):
##   scene:   res:// path to the rigged .glb
##   height:  metres from the soles to the top of the hat, used to fit the model
##   fit:     "height" fits `height` even with a pelvis bone (a body whose hips sit
##            far lower than a person's, like the barge duke's stubby legs)
##   yaw_deg: extra turn if the model does not face +Z
##   bones:   { kit joint name: bone name }

## Joints whose limb hangs along the joint's local -Y (the rest point up +Y).
const LIMBS := ["l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist",
	"l_hip", "r_hip", "l_knee", "r_knee"]
## Joints that are not re-aimed at bind (feet point forward, not down the limb).
const NO_AIM := ["l_ankle", "r_ankle", "head"]

var model: Node3D
var skeleton: Skeleton3D
var joints: Dictionary = {}
var bone_of: Dictionary = {}       ## joint -> bone index
var joint_of: Dictionary = {}      ## bone index -> joint
var _offset: Dictionary = {}       ## bone index -> Basis (joint-space rotation of the bone)
var _root_bone := -1
var _root_rest_origin := Vector3.ZERO
var _pelvis_rest := Vector3.ZERO
var _skel_in_body := Transform3D()
var _order: Array = []             ## bone indices, parents first
var _finger_bone: Dictionary = {}  ## issue #631: finger bone name -> index (-1 = not in this skin)
## Issue #324: the hands' holds, kept on every sync (set_hold): side -> { rots:
## { bone name: Quaternion }, k: 0..1 }.
var holds: Dictionary = {}
var _grips: Dictionary = {}        ## issue #324: solved grips (HandGrip.solve), by hand and spec
var scene_path := ""               ## the model's .glb (issue #324: finger pivots are kept per model and outfit)
var pivots_seated := false


## Load and attach. Returns null (and changes nothing) if the model or its skeleton
## is missing, so a checkout without the asset keeps the primitive body.
static func dress(body: Node3D, cfg: Dictionary) -> SkinnedBody:
	var path := str(cfg.get("scene", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var packed = ModelCache.scene(path)
	if not packed is PackedScene:
		return null
	var inst := (packed as PackedScene).instantiate() as Node3D
	var skel := _find_skeleton(inst)
	if skel == null:
		inst.free()
		return null
	var sb := SkinnedBody.new()
	sb.model = inst
	sb.skeleton = skel
	sb.joints = body.get_meta("joints")
	inst.name = "Skin"
	body.add_child(inst)
	sb.scene_path = path
	sb._fit(cfg)
	sb._bind(body, cfg.get("bones", {}))
	if not body.has_meta("skin"):
		sb._hide_primitives(body)
	if cfg.has("tint"):
		sb.tint(cfg.tint)
	return sb


## Issue #45: a variant of a model without a new model: every surface's colour
## multiplied by "albedo", and anything that glows (goggles, a prosthetic) glowing
## "emission" instead. Materials are copied, so the original keeps its look; issue
## #695: one copy per material and tint, shared by every body of the look.
static var _tinted := {}


func tint(t: Dictionary) -> void:
	var alb := Color(str(t.get("albedo", "#ffffff")))
	var has_em := t.has("emission")
	var em := Color(str(t.get("emission", "#ffffff")))
	for mi in _meshes(model):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var src = m.get_surface_override_material(i)
			if src == null:
				src = m.mesh.surface_get_material(i)
			if not src is BaseMaterial3D:
				continue
			var key := "%d_%s_%s" % [src.get_instance_id(), alb.to_html(), em.to_html() if has_em else ""]
			if not _tinted.has(key):
				var c := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				c.albedo_color = c.albedo_color * alb
				if has_em and c.emission_enabled:
					c.emission = em
				_tinted[key] = c
			m.set_surface_override_material(i, _tinted[key])


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null


## Stand the model on y = 0 facing +Z, scaled so its hips sit at the kit's pelvis
## height: the legs then match the kit's legs, which keeps the feet on the ground
## whatever the hat adds on top. Without a pelvis bone (or with fit "height"), fit
## `height` instead.
func _fit(cfg: Dictionary) -> void:
	model.rotation_degrees.y = float(cfg.get("yaw_deg", 0.0))
	var aabb := _aabb(model, Transform3D())
	var s := float(cfg.get("height", 1.8)) / maxf(aabb.size.y, 0.001)
	var hips := skeleton.find_bone(str(cfg.get("bones", {}).get("pelvis", "")))
	if hips >= 0 and joints.has("pelvis") and str(cfg.get("fit", "")) != "height":
		var hy := (_rel(model, skeleton) * skeleton.get_bone_global_rest(hips).origin).y - aabb.position.y
		if hy > 0.001:
			s = (joints.pelvis as Node3D).position.y / hy
	model.scale = Vector3.ONE * s
	model.position = Vector3(0, -aabb.position.y * s, 0)


static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var here := xf * ((n as Node3D).transform if n is Node3D else Transform3D())
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out = here * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var a := _aabb(c, here)
		if a.size != Vector3.ZERO:
			out = a if first else out.merge(a)
			first = false
	return out


func _bind(body: Node3D, bones: Dictionary) -> void:
	for jn in bones:
		var bi := skeleton.find_bone(str(bones[jn]))
		if bi >= 0 and joints.has(jn):
			bone_of[jn] = bi
			joint_of[bi] = jn
	_skel_in_body = _rel(body, skeleton)
	# The kit at rest: every joint rotation zero. Measure it, then put the pose back.
	var saved := {}
	for jn in joints:
		saved[jn] = (joints[jn] as Node3D).transform.basis
		(joints[jn] as Node3D).transform.basis = Basis()
	var inv := _skel_in_body.affine_inverse()
	for bi in skeleton.get_bone_count():
		_order.append(bi)
	_order.sort_custom(func(a, b): return _depth(a) < _depth(b))
	for bi in joint_of:
		var jn: String = joint_of[bi]
		var jb := _rot(inv * _rel(body, joints[jn]))
		var bb := skeleton.get_bone_global_rest(bi).basis.orthonormalized()
		if not NO_AIM.has(jn):
			var kit_dir := jb * (Vector3.DOWN if LIMBS.has(jn) else Vector3.UP)
			var bone_dir := _bone_dir(bi)
			if bone_dir != Vector3.ZERO:
				bb = _turn(bone_dir, kit_dir.normalized()) * bb
		_offset[bi] = jb.inverse() * bb
	if bone_of.has("pelvis"):
		_root_bone = bone_of.pelvis
		_root_rest_origin = skeleton.get_bone_global_rest(_root_bone).origin
		_pelvis_rest = (inv * _rel(body, joints.pelvis)).origin
	for jn in saved:
		(joints[jn] as Node3D).transform.basis = saved[jn]


func _depth(bi: int) -> int:
	var d := 0
	var p := skeleton.get_bone_parent(bi)
	while p >= 0:
		d += 1
		p = skeleton.get_bone_parent(p)
	return d


## Rest direction from a bone to its first mapped (or any) child, in skeleton space.
func _bone_dir(bi: int) -> Vector3:
	var kids := skeleton.get_bone_children(bi)
	if kids.is_empty():
		return Vector3.ZERO
	var pick: int = kids[0]
	for k in kids:
		if joint_of.has(k):
			pick = k
			break
	var d := skeleton.get_bone_global_rest(pick).origin - skeleton.get_bone_global_rest(bi).origin
	return d.normalized() if d.length() > 0.0001 else Vector3.ZERO


static func _turn(from: Vector3, to: Vector3) -> Basis:
	var axis := from.cross(to)
	var s := axis.length()
	if s < 0.00001:
		return Basis() if from.dot(to) > 0.0 else Basis(Vector3.RIGHT if absf(from.x) < 0.9 else Vector3.UP, PI)
	return Basis(axis / s, atan2(s, from.dot(to)))


static func _rot(t: Transform3D) -> Basis:
	return t.basis.orthonormalized()


static func _rel(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D()
	var n: Node = node
	while n != null and n != root:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _hide_primitives(body: Node3D) -> void:
	# A held prop (the kit's rifle, body meta "weapon") stays: the hands are posed on it.
	var prop: Node = body.get_meta("weapon") if body.has_meta("weapon") else null
	for m in _meshes(body):
		if model.is_ancestor_of(m) or (prop != null and (prop == m or prop.is_ancestor_of(m))):
			continue
		(m as GeometryInstance3D).visible = false


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is GeometryInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


## Every mesh of the skin (for first-person shadow-only switching).
func skin_meshes() -> Array:
	return _meshes(model)


## Where joint `jn`'s bone is now, as the joint's own frame (its bind offset taken
## back out), in body space. The skin's limbs are not the kit's lengths, so a skin
## hand is not quite where the kit's IK put the kit's. Call after sync().
func joint_xf(jn: String) -> Transform3D:
	var bi: int = bone_of[jn]
	var g := skeleton.get_bone_global_pose(bi)
	var t := _skel_in_body * Transform3D(g.basis.orthonormalized() * (_offset[bi] as Basis).inverse(), g.origin)
	t.basis = t.basis.orthonormalized()
	return t


## Issue #324: a model's finger bones (Left/RightHand + Thumb..Pinky + 1..3) do not
## sit at the glove's own knuckles. The kit's parts.glb carries every outfit's
## meshes on one skeleton and one Skin, and each outfit's glove is somewhere else:
## the player's finger creases are 5 to 10 cm from the bones, so a finger bone turned
## swings its glove finger on a long lever instead of bending it at the knuckle, and
## no curl could close a fist. Once the outfit is on (CharacterKit), each finger
## bone's rest is moved onto its crease in the meshes that show (the middle of the
## vertices it shares with its parent bone), and those meshes get their own Skin
## with the bind poses moved to match, so the hand looks exactly as before at rest
## and bends where the glove bends. Worked out once per model and outfit.
static var _pivots: Dictionary = {}   ## model + shown meshes -> { rests: { bone: local rest }, skins: { mesh: Skin } }
const PIVOT_RE := "^(Left|Right)Hand(Thumb|Index|Middle|Ring|Pinky)[1-3]$"


func seat_finger_pivots() -> void:
	if pivots_seated:
		return
	pivots_seated = true
	var re := RegEx.create_from_string(PIVOT_RE)
	var fingers: Array = []
	for bi in _order_by_depth():
		if re.search(skeleton.get_bone_name(bi)) != null:
			fingers.append(bi)
	if fingers.is_empty():
		return
	var meshes: Array = []
	var names: Array = []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.skin != null and m.mesh != null and _shown(m) and _weights_any(m, fingers):
			meshes.append(m)
			names.append(str(m.name))
	if meshes.is_empty():
		return
	names.sort()
	var key := scene_path + ":" + ",".join(names)
	if not _pivots.has(key):
		_pivots[key] = _work_out_pivots(fingers, meshes)
	var p: Dictionary = _pivots[key]
	for bi in fingers:
		var bn := skeleton.get_bone_name(bi)
		if p.rests.has(bn):
			skeleton.set_bone_rest(bi, p.rests[bn])
			skeleton.set_bone_pose_position(bi, (p.rests[bn] as Transform3D).origin)
	for m in meshes:
		if p.skins.has(str(m.name)):
			(m as MeshInstance3D).skin = p.skins[str(m.name)]


## Visible within the model (an outfit hides the pieces it does not wear).
func _shown(n: Node3D) -> bool:
	while n != null and n != model.get_parent():
		if not n.visible:
			return false
		n = n.get_parent() as Node3D
	return true


static var _weighted: Dictionary = {}   ## mesh resource id -> any vertex weighted to a finger bone (by bind name)


## Has `m` any vertex on a finger bone (kept per mesh resource).
func _weights_any(m: MeshInstance3D, fingers: Array) -> bool:
	var id := m.mesh.get_instance_id()
	if not _weighted.has(id):
		var names := {}
		for bi in fingers:
			names[skeleton.get_bone_name(bi)] = true
		var finger_binds := {}
		for i in m.skin.get_bind_count():
			var b := m.skin.get_bind_bone(i)
			var bn := skeleton.get_bone_name(b) if b >= 0 else str(m.skin.get_bind_name(i))
			if names.has(bn):
				finger_binds[i] = true
		var any := false
		for surf in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(surf)
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null:
				continue
			for k in bones.size():
				if weights[k] > 0.0 and finger_binds.has(bones[k]):
					any = true
					break
			if any:
				break
		_weighted[id] = any
	return _weighted[id]


## The finger bones' new local rests (turned as they were, each origin on the crease
## it shares with its parent, skeleton space at rest), and a Skin per mesh with its
## finger binds moved to match.
func _work_out_pivots(fingers: Array, meshes: Array) -> Dictionary:
	var crease := {}       ## bone -> [sum, weight]
	for m in meshes:
		var skin: Skin = (m as MeshInstance3D).skin
		var bind_of := {}
		var idx_of := {}
		var finger_bind := {}
		for i in skin.get_bind_count():
			var b := skin.get_bind_bone(i)
			if b < 0:
				b = skeleton.find_bone(skin.get_bind_name(i))
			bind_of[i] = b
			idx_of[b] = i
			if fingers.has(b):
				finger_bind[i] = true
		for surf in (m as MeshInstance3D).mesh.get_surface_count():
			var arr := (m as MeshInstance3D).mesh.surface_get_arrays(surf)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null or verts.is_empty():
				continue
			var per: int = bones.size() / verts.size()
			for vi in verts.size():
				var on_finger := false
				for k in per:
					if weights[vi * per + k] > 0.0 and finger_bind.has(bones[vi * per + k]):
						on_finger = true
						break
				if not on_finger:
					continue
				var wb := {}
				for k in per:
					var w: float = weights[vi * per + k]
					if w > 0.0:
						wb[bind_of.get(bones[vi * per + k], -1)] = w
				for b in wb:
					if not fingers.has(b):
						continue
					var pb := skeleton.get_bone_parent(b)
					if not wb.has(pb) or not idx_of.has(pb):
						continue
					var ww: float = minf(wb[b], wb[pb])
					var at: Vector3 = HandGrip.global_rest(skeleton, pb) * (skin.get_bind_pose(idx_of[pb]) * verts[vi])
					if not crease.has(b):
						crease[b] = [Vector3.ZERO, 0.0]
					crease[b][0] += at * ww
					crease[b][1] += ww
	var old_glob := {}
	var glob := {}
	var rests := {}
	for bi in fingers:
		var rest := HandGrip.global_rest(skeleton, bi)
		old_glob[bi] = rest
		if crease.has(bi) and float(crease[bi][1]) > 0.5:
			rest.origin = crease[bi][0] / float(crease[bi][1])
		glob[bi] = rest
		var pb := skeleton.get_bone_parent(bi)
		var parent: Transform3D = glob[pb] if glob.has(pb) else HandGrip.global_rest(skeleton, pb)
		rests[skeleton.get_bone_name(bi)] = parent.affine_inverse() * rest
	var skins := {}
	for m in meshes:
		var skin: Skin = ((m as MeshInstance3D).skin as Skin).duplicate()
		for i in skin.get_bind_count():
			var bi := skin.get_bind_bone(i)
			if bi < 0:
				bi = skeleton.find_bone(skin.get_bind_name(i))
			if glob.has(bi):
				skin.set_bind_pose(i, (glob[bi] as Transform3D).affine_inverse() * (old_glob[bi] as Transform3D) * skin.get_bind_pose(i))
		skins[str(m.name)] = skin
	return { "rests": rests, "skins": skins }


func _order_by_depth() -> Array:
	var order: Array = []
	for bi in skeleton.get_bone_count():
		order.append(bi)
	order.sort_custom(func(a, b): return _depth(a) < _depth(b))
	return order


## Issue #324: the hand bone for a side ("r" / "l"), the mapped wrist bone's name
## ("RightHand"), or "" when this skin has none.
func hand_bone(side: String) -> String:
	var jn := side + "_wrist"
	return skeleton.get_bone_name(int(bone_of[jn])) if bone_of.has(jn) else ""


## Issue #324: the grip `spec` solved for this skin's `side` hand (HandGrip.solve),
## kept: { rots, frame }, frame in the hand bone's space. {} without a hand.
func grip(side: String, spec: Dictionary) -> Dictionary:
	seat_finger_pivots()
	var key := side + str(spec.hash())
	if not _grips.has(key):
		var hand := hand_bone(side)
		# The spec is in metres; the skeleton is in its own units (the model is
		# scaled to fit the body).
		var in_skel := spec.duplicate()
		in_skel["radius"] = float(spec.get("radius", 0.029)) / _unit()
		_grips[key] = HandGrip.solve(skeleton, hand, in_skel) if hand != "" else {}
	return _grips[key]


## Metres per skeleton unit (the model's fit scale).
func _unit() -> float:
	return maxf(_skel_in_body.basis.get_scale().x, 0.0001)


## Issue #324: where the grip `spec` closes in `side`'s hand, in the kit wrist
## joint's frame (joint_xf): origin the bar's middle, +Z along the bar toward the
## thumb, +X out of the palm. Identity without a hand.
func grip_frame(side: String, spec: Dictionary) -> Transform3D:
	var g := grip(side, spec)
	var jn := side + "_wrist"
	if g.is_empty() or not bone_of.has(jn):
		return Transform3D()
	var off: Basis = _offset[int(bone_of[jn])]
	var f: Transform3D = g.frame
	return Transform3D((off * f.basis).orthonormalized(), off * f.origin * _unit())


## Issue #324: close `side`'s hand round the grip `spec` (HandGrip), `k` of the way
## from its rest (0) to the full grip (1); an empty spec or k 0 lets it go. Kept on
## every sync from then on, so the fingers never spring open between frames.
func set_hold(side: String, spec: Dictionary, k: float = 1.0) -> void:
	if spec.is_empty() or k <= 0.0:
		holds.erase(side)
		return
	var g := grip(side, spec)
	if g.is_empty():
		holds.erase(side)
		return
	holds[side] = { "rots": g.rots, "k": clampf(k, 0.0, 1.0) }


## Copy the kit joints onto the bones. Call after the animator and IK have run.
func sync(body: Node3D) -> void:
	var skins = body.get_meta("skins", [])
	if skins is Array and not skins.is_empty():
		for layer in skins:
			if layer is SkinnedBody:
				(layer as SkinnedBody)._sync_one(body)
				(layer as SkinnedBody)._apply_holds(holds)
		return
	_sync_one(body)
	_apply_holds(holds)


## Issue #324: the holds' finger turns, over the rest pose the sync just put back.
func _apply_holds(from: Dictionary) -> void:
	for side in from:
		var h: Dictionary = from[side]
		var k := float(h.k)
		var rots: Dictionary = h.rots
		for bn in rots:
			var bi: int = _finger_bone.get(bn, -2)
			if bi == -2:
				bi = skeleton.find_bone(bn)
				_finger_bone[bn] = bi
			if bi < 0:
				continue
			var q: Quaternion = rots[bn]
			if k < 1.0:
				q = skeleton.get_bone_rest(bi).basis.get_rotation_quaternion().slerp(q, k)
			skeleton.set_bone_pose_rotation(bi, q)


func _sync_one(body: Node3D) -> void:
	var inv := _skel_in_body.affine_inverse()
	var want := {}                 ## bone -> skeleton-space basis this frame
	for bi in _order:
		var parent := skeleton.get_bone_parent(bi)
		var pg: Basis = want.get(parent, Basis()) if parent >= 0 else Basis()
		var g: Basis
		if joint_of.has(bi):
			g = _rot(inv * _rel(body, joints[joint_of[bi]])) * _offset[bi]
		else:
			g = pg * skeleton.get_bone_rest(bi).basis.orthonormalized()
		want[bi] = g
		skeleton.set_bone_pose_rotation(bi, (pg.inverse() * g).get_rotation_quaternion())
	if _root_bone >= 0:
		var now := (inv * _rel(body, joints.pelvis)).origin
		var origin := _root_rest_origin + (now - _pelvis_rest)
		var parent := skeleton.get_bone_parent(_root_bone)
		if parent >= 0:
			origin = skeleton.get_bone_global_pose(parent).affine_inverse() * origin
		skeleton.set_bone_pose_position(_root_bone, origin)
