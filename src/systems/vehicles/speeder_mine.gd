class_name SpeederMine
extends Node3D
## Issue #616: a mine dropped behind a speeder (SpeederGear.drop_mine). It sits on
## the sand, arms after arm_s, and bursts when any speeder rides within
## trigger_m of it: the grenade's Blast with the mine's numbers (its "gear" block
## in content/core/vehicles/speeder_upgrades.json). The world holds at most
## `cap` (the oldest goes); clear_all() sweeps them when a race ends.
##
## Render rules: a squat disc and a lamp from shared meshes and materials; it
## ticks only while armed and looks at the speeders group, not physics.

static var live: Array = []
static var _mesh: CylinderMesh
static var _lamp_mesh: SphereMesh
static var _mat: StandardMaterial3D
static var _lamp_mat: StandardMaterial3D

var cfg: Dictionary = {}
var shooter: Node                     ## the hull that dropped it (so the blast counts as theirs)
var dropper: SpeederNode
var armed := false
var _t := 0.0


func setup(gear_cfg: Dictionary, from: SpeederNode) -> void:
	cfg = gear_cfg
	dropper = from
	shooter = from.hull if from != null else null
	name = "SpeederMine"


static func clear_all() -> void:
	for m in live:
		if is_instance_valid(m):
			m.queue_free()
	live.clear()


func _ready() -> void:
	live = live.filter(func(m): return is_instance_valid(m))
	live.append(self)
	var cap := int(cfg.get("cap", 6))
	while live.size() > cap:
		var old = live.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	if _mesh == null:
		_mesh = CylinderMesh.new()
		_mesh.top_radius = 0.45
		_mesh.bottom_radius = 0.55
		_mesh.height = 0.18
		_mesh.radial_segments = 10
		_lamp_mesh = SphereMesh.new()
		_lamp_mesh.radius = 0.09
		_lamp_mesh.height = 0.18
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color("#2a2b2e")
		_mat.metallic = 0.6
		_mat.roughness = 0.5
		_lamp_mat = StandardMaterial3D.new()
		_lamp_mat.albedo_color = Color("#ff3a24")
		_lamp_mat.emission_enabled = true
		_lamp_mat.emission = Color("#ff3a24")
		_lamp_mat.emission_energy_multiplier = 4.0
	var disc := MeshInstance3D.new()
	disc.mesh = _mesh
	disc.material_override = _mat
	disc.position = Vector3(0, 0.09, 0)
	add_child(disc)
	var lamp := MeshInstance3D.new()
	lamp.mesh = _lamp_mesh
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(0, 0.22, 0)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lamp)


func _physics_process(dt: float) -> void:
	_t += dt
	if not armed:
		armed = _t >= float(cfg.get("arm_s", 1.0))
		return
	if _t > float(cfg.get("life_s", 120.0)):
		queue_free()
		return
	var r := float(cfg.get("trigger_m", 2.6))
	for n in get_tree().get_nodes_in_group(SpeederNode.GROUP):
		var s := n as SpeederNode
		if s == null or not is_instance_valid(s) or not s.model.alive():
			continue
		if s.model.position.distance_to(global_position) <= r + float(s.model.p("body_radius", 1.3)):
			burst()
			return


## It goes off: the blast (Blast.burst: the fx, the sound, the damage).
func burst() -> void:
	var host := get_parent()
	var player = dropper.demo._player if dropper != null and is_instance_valid(dropper) and dropper.demo != null else null
	Blast.burst(host, global_position + Vector3(0, 0.3, 0), cfg, shooter if is_instance_valid(shooter) else null, player)
	live.erase(self)
	queue_free()
