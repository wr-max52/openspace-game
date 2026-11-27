class_name QuantoniumRefinery
extends Node3D
## A Remnant outpost's quantonium refinery: a big tank of the stuff behind the
## control room, glowing amber, that goes up like a ship when you shoot it enough.
## RemnantOutposts builds two at every outpost (the port's, the moon's and the
## lava moon's: a globe tank and a reactor column, territory.json "units") and
## brings them back with the outpost. One going up sets off its partners.
##
## Its shape is one of three styles (content/look/refinery.json "style"):
##   globe: a storage sphere on eight braced legs, a glowing conduit up its middle
##          into a pump, a glowing band and portholes, a vent with a lamp on top.
##   silo:  a tall domed tank and two small ones, glowing sight glasses up their
##          sides, banded, a catwalk, pipes between them and a flare stack.
##   core:  a glowing column in a steel cage on an octagonal plinth, a cap and an
##          emitter on top, two tanks lying on cradles feeding it glowing pipes.
## Every style is boxes, cylinders, spheres and rings merged by material
## (PrimBatch, render rules 1 and 5): the outpost's own hull wall, steel, black,
## its faction mark (repainted when the outpost changes hands, LookMaterials) and
## the quantonium glow, one material shared by every refinery and breathing
## slowly. A blown refinery shows its ruin (stumps, plates, a scorched plinth) in
## the same materials, and smokes.
##
## The hit body (always built, look or not: render rule 9) takes bolts, blades,
## grenades and ship cannon like anything else with apply_damage. Gameplay numbers
## are territory.json "outposts" "refinery".

const CoreContent := preload("res://src/systems/dataload/core_content.gd")

signal blown

const LOOK_PATH := "res://content/look/refinery.json"
const STYLES := ["globe", "silo", "core"]

var cfg: Dictionary = {}            ## territory.json outposts.refinery
var look: Dictionary = {}           ## content/look/refinery.json
var style := "globe"
var label := ""                     ## the outpost's, for the toast and the log
var host: Node                      ## where the fireballs go (the town)
var player: Node                    ## the local player (Blast's friendly fire)
var hp := 600.0
var hp_max := 600.0
var alive := true
var back_at := -1.0                 ## WorldState.clock it may be built again at (-1: standing)
var last_shooter: Node
var partners: Array = []            ## the other refineries at its outpost: one going up sets them off
var blows := 0                      ## times it went up in this scene (tests, traces)
var rebuilds := 0

var _sets := { "keep": [], "intact": [], "ruin": [] }     ## set -> MeshInstance3D / CollisionShape3D
var _parts: Array = []              ## { set, mat, mesh | box, xf } while building
var _shapes: Array = []             ## { set, shape, xf } while building
var _light: OmniLight3D
var _smoke: CPUParticles3D
var _top := 16.0                    ## local height of its top (fireballs, the screen check)
var _mid := 8.0
var _rng := RandomNumberGenerator.new()
var _doomed := false                ## a partner went up: this one goes in chain_s, deaf to hits till then

static var _glow_mat: StandardMaterial3D        ## the quantonium, shared by every refinery
static var _glow_base := 2.4
static var _pulse := Vector2(0.35, 0.6)         ## depth, hz
static var _pulsed_frame := -1


static func look_cfg() -> Dictionary:
	return CoreContent.read_json(LOOK_PATH)


static func game_cfg() -> Dictionary:
	return Territory.cfg().get("outposts", {}).get("refinery", {})


## How far its plinth reaches from its middle, metres (the nav's hole). Every style
## keeps inside this.
static func footprint() -> float:
	return 5.6 * float(look_cfg().get("scale", 1.0))


## Build it. `mats`: the town's LookMaterials (null: no look, only the hit body).
## `wall` and `red`: the outpost's hull and faction mark. `sink`: how far the sand
## falls under its plinth below its middle.
func build(style_id: String, mats: LookMaterials, wall: Material, red: Material, sink: float, seed_text: String) -> void:
	cfg = game_cfg()
	look = look_cfg()
	style = style_id if style_id in STYLES else str(look.get("style", "globe"))
	hp_max = float(cfg.get("hp", 600.0))
	hp = hp_max
	_rng.seed = hash(seed_text)
	match style:
		"silo":
			_silo(sink)
		"core":
			_core(sink)
		_:
			_globe(sink)
	_build_body()
	if mats != null:
		_build_look(mats, wall, red)
	_parts.clear()
	_shapes.clear()
	_show(true)


# ------------------------------------------------------------------ damage

func hit(amount: float, shooter: Node) -> void:
	if not alive or _doomed or amount <= 0.0:
		return
	if shooter != null:
		last_shooter = shooter
	hp -= amount
	if hp <= 0.0:
		blow()
	elif hp < hp_max * float(cfg.get("leak_below", 0.5)) and _smoke == null and _has_look():
		_start_smoke(0.6)


## Up it goes: three fireballs one after another, everyone round it hurt (Blast),
## the ruin left smoking until it is built again.
func blow() -> void:
	if not alive:
		return
	alive = false
	_doomed = false
	blows += 1
	# The others at the outpost go up a moment later (their Blast would set them off
	# anyway; this way it rolls from one tank to the next).
	for other in partners:
		if is_instance_valid(other) and other.alive and not other._doomed:
			other._doomed = true
			other.last_shooter = last_shooter
			if is_inside_tree():
				get_tree().create_timer(float(cfg.get("chain_s", 0.7)), false).timeout.connect(other.blow)
			else:
				other.blow()
	back_at = WorldState.clock + float(Story.remnant_cfg().get("outpost_respawn_s", 180.0))
	_show(false)
	var s := float(look.get("scale", 1.0))
	var sizes: Array = look.get("blast_sizes", [2.0, 2.6, 3.4])
	var gap := float(look.get("blast_gap_s", 0.32))
	var spots := [Vector3(0, _mid * 0.6, 0), Vector3(0, _top * 0.8, 0), Vector3(0, _mid, 0)]
	for i in sizes.size():
		var at: Vector3 = to_global(spots[i % spots.size()] + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5)) * s)
		if i == 0:
			_boom(at, float(sizes[i]) * s)
		elif is_inside_tree():
			get_tree().create_timer(gap * i, false).timeout.connect(_boom.bind(at, float(sizes[i]) * s))
	var centre := to_global(Vector3(0, _mid * 0.5, 0))
	NoiseEvents.emit(centre, float(cfg.get("noise_radius", 220.0)), "explosion")
	if player == null and host != null and is_instance_valid(host):
		player = host.get("_player")
	if is_inside_tree():
		Blast.damage(get_world_3d().direct_space_state, centre, cfg, last_shooter, player)
	if _has_look():
		if _smoke != null:
			_smoke.queue_free()
			_smoke = null
		_start_smoke(1.0)
	WorldState.log_event("Someone blew up the quantonium refinery at %s." % label)
	blown.emit()


func _boom(at: Vector3, size: float) -> void:
	if host != null and is_instance_valid(host) and host.is_inside_tree():
		ExplosionFx.big(host, at, size)
		Sound.play("vehicle_boom", at)


## Built again: whole, full, not smoking.
func rebuild() -> void:
	if alive:
		return
	alive = true
	_doomed = false
	hp = hp_max
	back_at = -1.0
	last_shooter = null
	rebuilds += 1
	if _smoke != null:
		_smoke.queue_free()
		_smoke = null
	_show(true)


## Its time is up (the outposts' respawn has passed).
func due() -> bool:
	return not alive and back_at >= 0.0 and WorldState.clock >= back_at


## Where its top is (the outposts' screen check).
func top() -> Vector3:
	return to_global(Vector3(0, _top, 0))


func _show(whole: bool) -> void:
	for n in _sets.intact:
		_toggle(n, whole)
	for n in _sets.ruin:
		_toggle(n, not whole)
	if _light != null:
		_light.visible = whole


func _toggle(n: Node, on: bool) -> void:
	if n is CollisionShape3D:
		(n as CollisionShape3D).set_deferred("disabled", not on)
	elif n is Node3D:
		(n as Node3D).visible = on


func _has_look() -> bool:
	return not _sets.keep.filter(func(n): return n is MeshInstance3D).is_empty()


func _start_smoke(thick: float) -> void:
	var sm: Dictionary = look.get("smoke", {})
	var s := float(look.get("scale", 1.0))
	_smoke = ExplosionFx.smoke_trail(self, Vector3(0, (_mid if alive else 1.5) * s, 0), float(sm.get("size", 2.2)) * s,
		maxi(4, roundi(float(sm.get("amount", 14)) * thick)), float(sm.get("life", 6.0)))
	if _smoke != null:
		_smoke.emitting = true


func _process(_dt: float) -> void:
	# One breath for the shared glow, whichever refinery gets here first this frame.
	var f := Engine.get_process_frames()
	if _glow_mat == null or _pulsed_frame == f:
		return
	_pulsed_frame = f
	var t := Time.get_ticks_msec() * 0.001
	_glow_mat.emission_energy_multiplier = _glow_base * (1.0 + _pulse.x * sin(t * TAU * _pulse.y))


# ------------------------------------------------------------------ building

func _build_body() -> void:
	var body := Hit.new()
	body.name = "Hit"
	add_child(body)
	for sh in _shapes:
		var cs := CollisionShape3D.new()
		cs.shape = sh.shape
		cs.transform = sh.xf
		body.add_child(cs)
		_sets[sh.set].append(cs)


func _build_look(mats: LookMaterials, wall: Material, red: Material) -> void:
	var by_mat := {
		"hull": wall if wall != null else mats.flat(Color("#34373d"), 0.5, 0.6),
		"steel": mats.flat(Color(str(look.get("steel", "#5d6168"))), 0.35, 0.75),
		"black": mats.flat(Color(str(look.get("black", "#141416"))), 0.55, 0.4),
		"red": red if red != null else mats.flat(LookMaterials.REMNANT_OXBLOOD, 0.6, 0.2),
		"glow": _glow(),
	}
	var batches := {}
	for p in _parts:
		var key := "%s|%s" % [p.set, p.mat]
		if not batches.has(key):
			batches[key] = PrimBatch.new()
		var b: PrimBatch = batches[key]
		if p.has("box"):
			b.add_box(p.box, p.xf)
		else:
			b.add(p.mesh, p.xf)
	for key in batches:
		var bits: PackedStringArray = str(key).split("|")
		var mi := MeshInstance3D.new()
		mi.name = "Refinery_%s_%s" % [bits[0], bits[1]]
		mi.mesh = (batches[key] as PrimBatch).commit()
		mi.material_override = by_mat[bits[1]]
		if bits[1] == "glow":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_sets[bits[0]].append(mi)
	var lc: Dictionary = look.get("light", {})
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = Color(str(lc.get("color", "#ffaa44")))
	_light.light_energy = float(lc.get("energy", 2.2))
	_light.omni_range = float(lc.get("range", 16.0)) * float(look.get("scale", 1.0))
	_light.shadow_enabled = false
	var dd: Dictionary = CoreContent.read_json(DrawDistance.LOOK_PATH).get("draw_distance", {})
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = float(dd.get("rules", {}).get("outdoor", {}).get("light_m", 300.0))
	_light.distance_fade_length = float(dd.get("light_fade_m", 20.0))
	add_child(_light)
	_light.position = Vector3(0, _mid * 0.75, 0)


func _glow() -> StandardMaterial3D:
	if _glow_mat == null:
		var c := Color(str(look.get("glow", "#ffb347")))
		var m := StandardMaterial3D.new()          # mats.glow()'s kind: no new shader variant
		m.albedo_color = c.darkened(0.25)
		m.emission_enabled = true
		m.emission = c
		_glow_base = float(look.get("glow_energy", 2.4))
		var pu: Dictionary = look.get("pulse", {})
		_pulse = Vector2(float(pu.get("depth", 0.35)), float(pu.get("hz", 0.6)))
		m.emission_energy_multiplier = _glow_base
		_glow_mat = m
	return _glow_mat


## One part: a box (`what` a Vector3 size) or a primitive mesh, turned by `xf`, in
## set "keep" (whole or not), "intact" or "ruin", of material `mat`.
func _p(set: String, mat: String, what, xf: Transform3D) -> void:
	var s := float(look.get("scale", 1.0))
	xf = Transform3D(xf.basis.scaled(Vector3.ONE * s), xf.origin * s)
	if what is Vector3:
		_parts.append({ "set": set, "mat": mat, "box": what, "xf": xf })
	else:
		_parts.append({ "set": set, "mat": mat, "mesh": what, "xf": xf })


## One collision shape in set `set`, at `at` (local, before scale).
func _shape(set: String, shape: Shape3D, at: Vector3, basis := Basis.IDENTITY) -> void:
	var s := float(look.get("scale", 1.0))
	if shape is CylinderShape3D:
		(shape as CylinderShape3D).radius *= s
		(shape as CylinderShape3D).height *= s
	elif shape is SphereShape3D:
		(shape as SphereShape3D).radius *= s
	elif shape is BoxShape3D:
		(shape as BoxShape3D).size *= s
	_shapes.append({ "set": set, "shape": shape, "xf": Transform3D(basis, at * s) })


static func _at(p: Vector3, b := Basis.IDENTITY) -> Transform3D:
	return Transform3D(b, p)


static func _ring(r: float, tube: float, seg := 32) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r - tube
	t.outer_radius = r + tube
	t.rings = seg
	t.ring_segments = 6
	return t


static func _cyl_shape(r: float, h: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	return c


static func _box_shape(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


## A rod from `a` to `b` (local), `w` thick: a brace or a pipe as a box.
func _rod(set: String, mat: String, a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_p(set, mat, Vector3(w, d.length(), w), _at((a + b) * 0.5, Basis(x, y, z)))


## A pipe from `a` to `b` (a cylinder lying along it).
func _pipe(set: String, mat: String, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	_p(set, mat, LookMeshKit.cyl(r, r, d.length(), 8, 1), _at((a + b) * 0.5, Basis(x, y, x.cross(y))))


## Burnt plates thrown about the plinth (the ruin).
func _debris(n: int, reach: float, size: Vector2) -> void:
	for i in n:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(reach * 0.35, reach)
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.9, 0.9))
		var w := _rng.randf_range(size.x, size.y)
		_p("ruin", "black" if i % 3 else "hull", Vector3(w, 0.18, w * _rng.randf_range(0.4, 0.9)),
			_at(Vector3(cos(a) * r, 0.9 + _rng.randf() * 0.6, sin(a) * r), b))


# ------------------------------------------------------------------ globe

## A storage sphere on eight braced legs.
func _globe(sink: float) -> void:
	var R := 5.0
	var cy := 10.0
	var legs := 8
	var lr := 4.6
	_top = cy + R + 3.6
	_mid = cy
	var ph := 0.6 + sink
	_p("keep", "black", LookMeshKit.cyl(5.4, 5.4, ph, 24, 1), _at(Vector3(0, 0.6 - ph * 0.5, 0)))
	_shape("keep", _cyl_shape(5.4, ph), Vector3(0, 0.6 - ph * 0.5, 0))
	for i in legs:
		var a := TAU * float(i) / legs
		var foot := Vector3(cos(a) * lr, 0.0, sin(a) * lr)
		_p("keep", "steel", Vector3(0.9, 0.3, 0.9), _at(foot + Vector3(0, 0.75, 0), Basis(Vector3.UP, -a)))
		_p("intact", "steel", LookMeshKit.cyl(0.3, 0.3, 7.4, 8, 1), _at(foot + Vector3(0, 4.3, 0)))
		var a2 := TAU * float(i + 1) / legs
		var foot2 := Vector3(cos(a2) * lr, 0.0, sin(a2) * lr)
		var lo := 1.2 if i % 2 == 0 else 6.6
		var hi := 6.6 if i % 2 == 0 else 1.2
		_rod("intact", "black", foot + Vector3(0, lo, 0), foot2 + Vector3(0, hi, 0), 0.14)
		_rod("intact", "black", foot + Vector3(0, 7.2, 0), foot2 + Vector3(0, 7.2, 0), 0.16)
		# The ruin: the legs snapped off, leaning.
		var stub := _rng.randf_range(0.8, 3.2)
		_p("ruin", "black", LookMeshKit.cyl(0.3, 0.3, stub, 8, 1), _at(foot + Vector3(0, 0.6 + stub * 0.5, 0),
			Basis(Vector3(sin(a), 0, -cos(a)), _rng.randf_range(-0.3, 0.3))))
	_p("intact", "hull", LookMeshKit.ball(R, 24, 12), _at(Vector3(0, cy, 0)))
	_p("intact", "red", _ring(R + 0.05, 0.22), _at(Vector3(0, cy, 0)))
	_p("intact", "steel", _ring(R * 0.8, 0.12), _at(Vector3(0, cy + R * 0.6, 0)))
	# The quantonium: a band glowing round its belly, portholes, a conduit up its middle.
	var by := cy - 1.9
	_p("intact", "glow", _ring(sqrt(R * R - 1.9 * 1.9) + 0.02, 0.2), _at(Vector3(0, by, 0)))
	for i in 6:
		var a := TAU * (float(i) + 0.5) / 6.0
		var h := 1.3
		var rr := sqrt(R * R - h * h)
		_p("intact", "glow", LookMeshKit.ball(0.42, 10, 5), _at(Vector3(cos(a) * rr, cy + h, sin(a) * rr)))
		_p("intact", "black", _ring(0.42, 0.08, 12), _at(Vector3(cos(a) * rr, cy + h, sin(a) * rr),
			Basis.looking_at(Vector3(cos(a), h / R, sin(a))) * Basis(Vector3.RIGHT, PI * 0.5)))
	_p("keep", "steel", Vector3(2.4, 1.6, 2.4), _at(Vector3(0, 1.4, 0)))
	_p("intact", "glow", LookMeshKit.cyl(0.38, 0.38, 3.4, 10, 1), _at(Vector3(0, 3.9, 0)))
	_p("intact", "black", _ring(0.46, 0.1, 12), _at(Vector3(0, 3.0, 0)))
	_p("intact", "black", _ring(0.46, 0.1, 12), _at(Vector3(0, 4.8, 0)))
	_pipe("keep", "steel", Vector3(1.2, 1.0, 0), Vector3(5.6, 1.0, 0), 0.28)
	# A hatch, a vent and a lamp on top.
	_p("intact", "steel", LookMeshKit.cyl(1.3, 1.3, 0.6, 12, 1), _at(Vector3(0, cy + R + 0.1, 0)))
	_p("intact", "black", LookMeshKit.cyl(0.24, 0.24, 3.0, 8, 1), _at(Vector3(0.6, cy + R + 1.8, 0)))
	_p("intact", "glow", LookMeshKit.ball(0.36, 10, 5), _at(Vector3(0.6, cy + R + 3.4, 0)))
	_p("intact", "steel", Vector3(0.12, 8.2, 0.7), _at(Vector3(lr + 0.35, 4.7, 0)))   # a ladder up a leg
	var ball := SphereShape3D.new()
	ball.radius = R
	_shape("intact", ball, Vector3(0, cy, 0))
	_shape("intact", _cyl_shape(lr + 0.3, 7.6), Vector3(0, 4.4, 0))
	# The ruin: the pump crushed, a half shell of the sphere, plates everywhere.
	_p("ruin", "hull", LookMeshKit.ball(R * 0.7, 16, 6, -1.0, true), _at(Vector3(1.2, 0.5, -0.8), Basis(Vector3(1, 0, 1).normalized(), 2.6)))
	_shape("ruin", _cyl_shape(3.4, 2.4), Vector3(1.0, 1.2, -0.6))
	_debris(14, 5.2, Vector2(0.8, 2.2))


# ------------------------------------------------------------------ silo

## A tall domed tank and two small ones, banded, with sight glasses and a flare.
func _silo(sink: float) -> void:
	var R := 3.0
	var H := 13.0
	var y0 := 0.5
	_top = y0 + H + R
	_mid = y0 + H * 0.55
	var ph := 0.5 + sink
	_p("keep", "black", Vector3(9.6, ph, 9.4), _at(Vector3(-0.9, 0.5 - ph * 0.5, 0)))
	_shape("keep", _box_shape(Vector3(9.6, ph, 9.4)), Vector3(-0.9, 0.5 - ph * 0.5, 0))
	_p("intact", "hull", LookMeshKit.cyl(R, R, H, 24, 1), _at(Vector3(0, y0 + H * 0.5, 0)))
	_p("intact", "hull", LookMeshKit.ball(R, 24, 8, -1.0, true), _at(Vector3(0, y0 + H, 0)))
	_shape("intact", _cyl_shape(R, H + R), Vector3(0, y0 + (H + R) * 0.5, 0))
	for y in [2.0, 7.0]:
		_p("intact", "steel", _ring(R + 0.04, 0.14), _at(Vector3(0, y0 + y, 0)))
	_p("intact", "red", _ring(R + 0.05, 0.3), _at(Vector3(0, y0 + H - 0.6, 0)))
	# Sight glasses: the quantonium's level, glowing up the side.
	for a in [0.0, PI * 0.6, -PI * 0.6]:
		var n := Vector3(cos(a), 0, -sin(a))
		_p("intact", "glow", Vector3(0.18, 9.4, 0.5), _at(n * (R + 0.04) + Vector3(0, y0 + 1.2 + 4.7, 0), Basis(Vector3.UP, a)))
		for side in [-0.33, 0.33]:
			_p("intact", "black", Vector3(0.22, 9.8, 0.16), _at(n * (R + 0.06) + Vector3(0, y0 + 5.9, 0)
				+ Basis(Vector3.UP, a) * Vector3(0, 0, side), Basis(Vector3.UP, a)))
	# A catwalk round it with a rail.
	var cw := y0 + 10.0
	_p("intact", "steel", LookMeshKit.cyl(R + 0.9, R + 0.9, 0.14, 24, 1), _at(Vector3(0, cw, 0)))
	_p("intact", "steel", _ring(R + 0.85, 0.05), _at(Vector3(0, cw + 1.0, 0)))
	for i in 12:
		var a := TAU * float(i) / 12.0
		_p("intact", "steel", Vector3(0.07, 1.0, 0.07), _at(Vector3(cos(a) * (R + 0.85), cw + 0.5, sin(a) * (R + 0.85))))
	# The two small tanks behind, piped to the big one.
	for sz in [-1.0, 1.0]:
		var c := Vector3(-3.9, 0, 2.3 * sz)
		var r := 1.5
		var h := 8.5
		_p("intact", "hull", LookMeshKit.cyl(r, r, h, 16, 1), _at(c + Vector3(0, y0 + h * 0.5, 0)))
		_p("intact", "hull", LookMeshKit.ball(r, 16, 6, -1.0, true), _at(c + Vector3(0, y0 + h, 0)))
		_p("intact", "red", _ring(r + 0.04, 0.16, 24), _at(c + Vector3(0, y0 + h - 0.5, 0)))
		_p("intact", "glow", Vector3(0.4, 5.6, 0.14), _at(c + Vector3(0, y0 + 4.0, (r + 0.04) * sz)))
		_pipe("intact", "steel", c + Vector3(0, y0 + 2.6, 0), Vector3(0, y0 + 2.6, 0), 0.3)
		_pipe("intact", "glow", c + Vector3(0.5, y0 + h + 0.6, 0), Vector3(-1.2, y0 + H + 0.9, 0), 0.16)
		_shape("intact", _cyl_shape(r, h + r), c + Vector3(0, y0 + (h + r) * 0.5, 0))
		var stub := _rng.randf_range(1.4, 2.6)
		_p("ruin", "black", LookMeshKit.cyl(r, r, stub, 12, 1), _at(c + Vector3(0, y0 + stub * 0.5, 0)))
	# The pump by the doorway side and a flare stack with a burning tip.
	_p("keep", "steel", Vector3(1.8, 1.4, 1.8), _at(Vector3(3.6, y0 + 0.7, 0)))
	_pipe("intact", "steel", Vector3(R - 0.1, y0 + 1.0, 0), Vector3(3.6, y0 + 1.0, 0), 0.3)
	var fs := Vector3(2.6, 0, -3.4)
	_p("intact", "steel", LookMeshKit.cyl(0.3, 0.3, 18.0, 8, 1), _at(fs + Vector3(0, y0 + 9.0, 0)))
	_p("intact", "black", _ring(0.34, 0.08, 10), _at(fs + Vector3(0, y0 + 17.6, 0)))
	_p("intact", "glow", LookMeshKit.ball(0.55, 10, 5), _at(fs + Vector3(0, y0 + 18.4, 0)))
	_shape("intact", _cyl_shape(0.4, 18.0), fs + Vector3(0, y0 + 9.0, 0))
	# The ruin: a burst stump of the big tank, the stack toppled, plates about.
	_p("ruin", "black", LookMeshKit.cyl(R, R, 3.2, 16, 1), _at(Vector3(0, y0 + 1.6, 0)))
	for i in 7:
		var a := TAU * float(i) / 7.0 + _rng.randf() * 0.4
		_p("ruin", "hull", Vector3(1.4, _rng.randf_range(1.2, 2.6), 0.16), _at(Vector3(cos(a) * R, y0 + 3.4, sin(a) * R),
			Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, _rng.randf_range(-0.5, 0.5))))
	_shape("ruin", _cyl_shape(R, 3.2), Vector3(0, y0 + 1.6, 0))
	_p("ruin", "black", LookMeshKit.cyl(0.3, 0.3, 12.0, 8, 1), _at(fs + Vector3(1.5, y0 + 0.3, 5.0), Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.FORWARD, 0.3)))
	_debris(12, 5.0, Vector2(0.7, 1.8))


# ------------------------------------------------------------------ core

## A glowing column in a cage between two tanks lying on cradles.
func _core(sink: float) -> void:
	var y0 := 1.0
	var H := 11.0
	_top = y0 + H + 4.4
	_mid = y0 + H * 0.5
	var ph := 1.0 + sink
	_p("keep", "black", LookMeshKit.cyl(5.4, 5.4, ph, 8, 1), _at(Vector3(0, y0 - ph * 0.5, 0), Basis(Vector3.UP, PI / 8.0)))
	_shape("keep", _cyl_shape(5.2, ph), Vector3(0, y0 - ph * 0.5, 0))
	_p("keep", "steel", LookMeshKit.cyl(2.4, 2.4, 1.6, 16, 1), _at(Vector3(0, y0 + 0.8, 0)))
	_p("intact", "glow", LookMeshKit.cyl(1.25, 1.25, H, 16, 1), _at(Vector3(0, y0 + H * 0.5, 0)))
	for i in 8:
		var a := TAU * float(i) / 8.0
		_p("intact", "steel", Vector3(0.24, H + 0.4, 0.36), _at(Vector3(cos(a) * 1.9, y0 + H * 0.5, sin(a) * 1.9), Basis(Vector3.UP, -a)))
		_p("ruin", "black", Vector3(0.24, _rng.randf_range(1.6, 3.4), 0.36), _at(Vector3(cos(a) * 1.9, y0 + 1.6, sin(a) * 1.9),
			Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, _rng.randf_range(-0.5, 0.5))))
	for k in 5:
		var y := y0 + 1.6 + k * (H - 2.2) / 4.0
		_p("intact", "red" if k == 2 else "steel", _ring(1.98, 0.16 if k == 2 else 0.12), _at(Vector3(0, y, 0)))
	_p("intact", "black", LookMeshKit.cyl(2.6, 2.6, 1.4, 16, 1), _at(Vector3(0, y0 + H + 0.6, 0)))
	_p("intact", "red", _ring(2.62, 0.12), _at(Vector3(0, y0 + H + 0.6, 0)))
	_p("intact", "steel", LookMeshKit.cyl(0.22, 1.2, 2.2, 12, 1), _at(Vector3(0, y0 + H + 2.4, 0)))
	_p("intact", "glow", LookMeshKit.ball(0.5, 12, 6), _at(Vector3(0, y0 + H + 3.7, 0)))
	_shape("intact", _cyl_shape(2.6, H + 3.6), Vector3(0, y0 + (H + 3.6) * 0.5, 0))
	# The two tanks lying on cradles either side, glowing pipes into the cage.
	for sx in [-1.0, 1.0]:
		var c := Vector3(3.55 * sx, y0 + 1.75, 0)
		var r := 1.35
		var L := 5.4
		var lie := Basis(Vector3.RIGHT, PI * 0.5)
		_p("intact", "hull", LookMeshKit.cyl(r, r, L, 16, 1), _at(c, lie))
		for sz in [-1.0, 1.0]:
			var cap := lie if sz > 0 else lie * Basis(Vector3.RIGHT, PI)     # domes out of each end
			_p("intact", "hull", LookMeshKit.ball(r, 16, 6, -1.0, true), _at(c + Vector3(0, 0, L * 0.5 * sz), cap))
			_p("keep", "black", Vector3(2.2, 1.0, 0.5), _at(Vector3(c.x, y0 + 0.5, 1.7 * sz)))
		_p("intact", "red", _ring(r + 0.03, 0.12, 24), _at(c, lie))
		_p("intact", "glow", Vector3(0.5, 0.14, L * 0.8), _at(c + Vector3(0, r + 0.02, 0)))
		var top := c + Vector3(0, r, 0)
		_pipe("intact", "steel", top, top + Vector3(0, 1.4, 0), 0.24)
		_pipe("intact", "glow", top + Vector3(0, 1.4, 0), Vector3(1.9 * sx, top.y + 1.4, 0), 0.18)
		_shape("intact", _box_shape(Vector3(2.8, 2.8, L + 2.6)), c)
		_p("ruin", "black", LookMeshKit.cyl(r, r, 2.0, 12, 1), _at(c + Vector3(0, -0.4, 1.2 * sx), lie * Basis(Vector3.FORWARD, 0.4 * sx)))
	_p("ruin", "black", LookMeshKit.cyl(2.2, 2.2, 1.0, 12, 1), _at(Vector3(0, y0 + 2.1, 0)))
	_shape("ruin", _cyl_shape(2.4, 2.6), Vector3(0, y0 + 1.3, 0))
	_debris(14, 5.0, Vector2(0.7, 1.9))


## What bolts, blades, grenades and ship cannon hit: hits go to the refinery.
class Hit extends StaticBody3D:
	func apply_damage(amount: float) -> void:
		(get_parent() as QuantoniumRefinery).hit(amount, null)

	func apply_damage_from(amount: float, shooter: Node) -> void:
		(get_parent() as QuantoniumRefinery).hit(amount, shooter)

	## Only the player's energy sword calls this.
	func apply_blade_hit(amount: float, _dir: Vector3) -> void:
		var r := get_parent() as QuantoniumRefinery
		r.hit(amount, r.player)
