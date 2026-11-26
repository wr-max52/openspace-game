extends GutTest
## Issue #706: far from the origin (the cruiser hangs 11.5 km out) the pistol's
## iron sights and the arms wobbled about a millimetre against the eye: they were
## drawn through world positions, which round to a millimetre out there. Aimed
## in, the same pose must put the gun, the sights and the gloves at the same place
## from the eye 11.5 km out as at the origin. (The rendered 0 px drift probe needs
## a GPU; this is its headless half.)

const BodyAnimator := preload("res://src/systems/anim/body_animator.gd")
const GunSights := preload("res://src/systems/look/gun_sights.gd")


func _aimed_pistol(at: Vector3) -> Array:
	var body := Node3D.new()          # the player's body, the avatar under it as in play
	add_child_autofree(body)
	body.global_position = at
	var a := PlayerAvatar.new()
	body.add_child(a)
	a.build_weapons(["pistol_blaster", "energy_blade", "rifle_blaster"])
	a.set_first_person(true)
	var cam := Camera3D.new()
	add_child_autofree(cam)
	a.ads_camera = cam
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-0.2, 1.1, 0.0)), at + Vector3(0.0, 1.6, 0.0))
	a.current = "pistol_blaster"
	a.drawn = 1.0
	a.ads_on = true
	for i in 30:
		a.animate(1.0 / 60.0, { "upper": BodyAnimator.UPPER_AIM, "cam_yaw": 1.1, "aim_pitch": -0.2 })
		a._process(1.0 / 60.0)
	return [a, cam]


func _pin_of(g: GeometryInstance3D) -> Transform3D:
	var x: Vector4 = g.get_instance_shader_parameter("pin_x")
	var y: Vector4 = g.get_instance_shader_parameter("pin_y")
	var z: Vector4 = g.get_instance_shader_parameter("pin_z")
	return Transform3D(Basis(Vector3(x.x, y.x, z.x), Vector3(x.y, y.y, z.y), Vector3(x.z, y.z, z.z)), Vector3(x.w, y.w, z.w))


## Where `g` is drawn from the eye: its pin, or (not pinned) its world place
## through the camera, as the GPU's view * model makes it.
func _from_eye(g: GeometryInstance3D, cam: Camera3D) -> Transform3D:
	if g.get_instance_shader_parameter("pin_on") == 1.0:
		return _pin_of(g)
	return cam.global_transform.affine_inverse() * g.global_transform


func _pinned_meshes(a: PlayerAvatar) -> Array:
	return GunSights.parts(a.weapon_node("pistol_blaster")).pinned + a._fpv.meshes()


func test_far_out_the_gun_sights_and_gloves_sit_where_they_do_at_the_origin() -> void:
	var near := _aimed_pistol(Vector3.ZERO)
	var far := _aimed_pistol(Vector3(11500.0, 40.0, -300.0))
	var a := _pinned_meshes(near[0])
	var b := _pinned_meshes(far[0])
	assert_eq(a.size(), b.size())
	var worst := 0.0
	for i in a.size():
		var d := _from_eye(a[i], near[1]).origin.distance_to(_from_eye(b[i], far[1]).origin)
		worst = maxf(worst, d)
	assert_lt(worst, 0.00001, "11.5 km out, the gun, sights and gloves sit where they do at the origin, from the eye (worst %.7f m)" % worst)
