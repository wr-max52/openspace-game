class_name WelderFx
extends Node3D
## Issue #722: the plasma welder at work: sparks spitting off the nozzle, with a
## flickering blue light. Hung on the nozzle (the welder in your hand) and on
## whatever is being welded (PlayerWelder's target sparks, the speeder you sit in).
## `arcs` adds a crackle of electricity round it; off for now (sparks only). set_on() starts and stops it; nothing ticks while it is off.
## Reuses ExplosionFx's spark mesh, glow material and colour ramps (warmed with the
## town, so no shader compiles on first use), and one shared unshaded line material
## for the arcs.

const ARC_STEP_S := 0.05            ## how often the arcs jump to a new shape
const ARCS := 3                     ## crooked lines at once
const ARC_KINKS := 5                ## points along each

static var _arc_mat: StandardMaterial3D

var on := false
var arcs := false                   ## the electric arcs too (off for now: sparks only)
var arc_color := Color("#a8e4ff")
var size := 1.0                     ## 1 = hand-held; bigger for a whole vehicle
var _sparks: CPUParticles3D
var _arcs: MeshInstance3D
var _mesh: ImmediateMesh
var _light: OmniLight3D
var _arc_t := 0.0
var _rng := RandomNumberGenerator.new()


static func make(p_color := Color("#a8e4ff"), p_size := 1.0) -> WelderFx:
	var fx := WelderFx.new()
	fx.name = "WelderFx"
	fx.arc_color = p_color
	fx.size = p_size
	return fx


func _ready() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.name = "Sparks"
	_sparks.mesh = ExplosionFx._spark_mesh()
	_sparks.material_override = ExplosionFx._mat("spark")
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparks.amount = 28
	_sparks.lifetime = 0.45
	_sparks.lifetime_randomness = 0.5
	_sparks.explosiveness = 0.0
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 0.01 * size
	_sparks.direction = Vector3.UP
	_sparks.spread = 55.0
	_sparks.gravity = Vector3(0, -9.8, 0)
	_sparks.initial_velocity_min = 1.5 * size
	_sparks.initial_velocity_max = 4.0 * size
	_sparks.damping_min = 1.0
	_sparks.damping_max = 2.0
	_sparks.scale_amount_min = 0.06 * size
	_sparks.scale_amount_max = 0.14 * size
	_sparks.scale_amount_curve = ExplosionFx._curve("shrink")
	_sparks.color_ramp = ExplosionFx._ramp("spark_cold")
	_sparks.particle_flag_align_y = true
	_sparks.local_coords = false
	_sparks.emitting = false
	add_child(_sparks)
	if _arc_mat == null:
		_arc_mat = StandardMaterial3D.new()
		_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_arc_mat.vertex_color_use_as_albedo = true
		_arc_mat.no_depth_test = false
	_mesh = ImmediateMesh.new()
	_arcs = MeshInstance3D.new()
	_arcs.name = "Arcs"
	_arcs.mesh = _mesh
	_arcs.material_override = _arc_mat
	_arcs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arcs.visible = false
	add_child(_arcs)
	_light = OmniLight3D.new()
	_light.name = "WeldLight"
	_light.light_color = arc_color
	_light.omni_range = 2.5 * size
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	set_physics_process(false)
	set_on(on)


func set_on(v: bool) -> void:
	on = v
	if _sparks == null:
		return                       # not built yet: _ready picks it up
	_sparks.emitting = v
	_arcs.visible = v and arcs
	_light.visible = v
	set_physics_process(v)
	if v and arcs:
		_redraw()


func _physics_process(dt: float) -> void:
	_arc_t += dt
	if arcs and _arc_t >= ARC_STEP_S:
		_arc_t = 0.0
		_redraw()
	_light.light_energy = _rng.randf_range(0.6, 1.8)


## New crooked arcs out from the nozzle, a few centimetres long.
func _redraw() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var hot := arc_color.lerp(Color.WHITE, 0.5)
	for a in ARCS:
		var end := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.2, 1.0), _rng.randf_range(-1, 1)).normalized() \
			* _rng.randf_range(0.04, 0.09) * size
		var prev := Vector3.ZERO
		for k in range(1, ARC_KINKS + 1):
			var t := float(k) / ARC_KINKS
			var p := end * t
			if k < ARC_KINKS:
				p += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.012 * size
			_mesh.surface_set_color(hot)
			_mesh.surface_add_vertex(prev)
			_mesh.surface_set_color(arc_color)
			_mesh.surface_add_vertex(p)
			prev = p
	_mesh.surface_end()
