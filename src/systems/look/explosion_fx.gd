class_name ExplosionFx
extends RefCounted
## Explosions, built from code: no textures and no models. Each one is a handful of
## one-shot CPUParticles3D under a Node3D that frees itself when the last of them is
## done, plus a short orange light so the ground and walls catch the flash.
##
##   small(): a droid going pop. A blue-white flash, a spray of sparks, a few bits
##            of casing and a wisp of smoke. About a second.
##   bolt():  a blaster bolt or a blade landing. small()'s flash and sparks with a
##            smaller lick of fire that burns out red rather than to soot; no bits
##            of casing and no smoke.
##   clash(): two energy blades meeting in a parry. A white-hot flash, a little
##            shock ring and a spray of sparks, no fire, smoke or bits. Half a second.
##   big():   a ship, speeder or grenade going up. A white flash, tongues of flame
##            thrown out of a fireball that burns white-hot in its billows and red in
##            its creases before it goes to soot, a skirt of dust blown out along the
##            ground (a shock ring instead, in space), embers and hull chunks on arcs,
##            then a column of dark smoke. About four seconds.
##
## The fireball, flame tongues, dust and smoke are explosion_puff.gdshader (noise
## discs that erode from the rim as they age); the flash, ring and sparks are
## explosion_glow.gdshader. Two shaders for every kind, and FxWarmup compiles both.

## Loaded at the first explosion, not with the script (every system that can blow
## something up refers to this class).
const PUFF_SHADER := "res://src/systems/look/shaders/explosion_puff.gdshader"
const GLOW_SHADER := "res://src/systems/look/shaders/explosion_glow.gdshader"

static var _m: Dictionary = {}      ## shared meshes, materials, ramps and curves (built once)


## Builds every shared mesh, material, ramp and curve now, so the first explosion
## does not (FxWarmup, as a town is built).
static func warm() -> void:
	_quad()
	_spark_mesh()
	_chunk_mesh()
	for k in ["fire", "fire_jet", "smoke", "flash", "ring", "spark", "chunk"]:
		_mat(k)
	for k in ["fire", "fire_clean", "smoke_dark", "smoke_light", "dust", "flash_hot", "flash_cold", "ring", "spark_hot", "spark_cold"]:
		_ramp(k)
	for k in ["pop", "ring", "billow", "rise", "shrink"]:
		_curve(k)


## A droid going pop at `at` (its middle).
static func small(parent: Node, at: Vector3) -> Node3D:
	var r := _pop(parent, at, "fire")
	if r == null:
		return null
	_light_smoke()
	_emit(r, _quad(), _mat("smoke"), 4, 1.5, { "delay": 0.1, "radius": 0.15, "speed": Vector2(0.5, 1.1), "dir": Vector3.UP, "spread": 25.0,
		"gravity": Vector3(0, 0.4, 0), "damping": Vector2(0.3, 0.6), "scale": Vector2(0.7, 1.1), "grow": _curve("rise"), "ramp": _ramp("smoke_light"), "spin": 15.0 })
	_free_after(r, 1.7)
	return r


## A blaster bolt (any gun's) or a blade landing at `at`: small()'s flash and
## sparks with a smaller lick of fire that burns out red instead of cooling to
## soot. No bits of casing fly and no smoke hangs about: a clean pop.
static func bolt(parent: Node, at: Vector3) -> Node3D:
	var r := _pop(parent, at, "fire_clean", 0.55, false)
	if r == null:
		return null
	_free_after(r, 1.0)
	return r


## Two blades meeting in a parry at `at` (where they crossed): a small burst of
## sparks. `tint`: the light's colour (the blades' glow).
static func clash(parent: Node, at: Vector3, tint := Color("#ffd2a0")) -> Node3D:
	var r := _root(parent, at)
	if r == null:
		return null
	_light(r, tint, 9.0, 6.0, 0.25)
	_emit(r, _quad(), _mat("flash"), 1, 0.1, { "scale": Vector2(1.6, 1.6), "grow": _curve("pop"), "ramp": _ramp("flash_hot"), "radius": 0.01, "speed": Vector2.ZERO })
	_emit(r, _quad(), _mat("ring"), 1, 0.22, { "scale": Vector2(2.2, 2.2), "grow": _curve("ring"), "ramp": _ramp("ring"), "radius": 0.01, "speed": Vector2.ZERO })
	_emit(r, _spark_mesh(), _mat("spark"), 40, 0.5, { "radius": 0.05, "speed": Vector2(5.0, 12.0), "gravity": Vector3(0, -9.8, 0), "damping": Vector2(2.0, 4.0),
		"scale": Vector2(0.25, 0.45), "grow": _curve("shrink"), "ramp": _ramp("spark_hot"), "streak": true, "spin": 0.0, "life_rand": 0.5 })
	_free_after(r, 0.7)
	return r


## The flash, fire and sparks small() and bolt() share. `fire`: the fire's ramp.
## `smoke`: how much fire there is, 1 being a droid's worth (fewer, smaller puffs
## below that). `bits`: whether hot bits of casing fly out too.
static func _pop(parent: Node, at: Vector3, fire: String, smoke := 1.0, bits := true) -> Node3D:
	var r := _root(parent, at)
	if r == null:
		return null
	_light(r, Color("#bfe0ff"), 6.0, 7.0, 0.3)
	_emit(r, _quad(), _mat("flash"), 1, 0.12, { "scale": Vector2(2.4, 2.4), "grow": _curve("pop"), "ramp": _ramp("flash_cold"), "radius": 0.01, "speed": Vector2.ZERO })
	var puffs := maxi(1, roundi(7.0 * smoke))
	var puff_scale := lerpf(0.75, 1.0, clampf(smoke, 0.0, 1.0))
	_emit(r, _quad(), _mat("fire"), puffs, 0.5, { "radius": 0.2, "speed": Vector2(1.0, 2.6), "damping": Vector2(5.0, 7.0),
		"gravity": Vector3(0, 1.0, 0), "scale": Vector2(0.9, 1.4) * puff_scale, "grow": _curve("billow"), "ramp": _ramp(fire) })
	_emit(r, _spark_mesh(), _mat("spark"), 26, 0.6, { "speed": Vector2(4.0, 9.0), "gravity": Vector3(0, -9.8, 0), "damping": Vector2(1.0, 2.0),
		"scale": Vector2(0.3, 0.5), "grow": _curve("shrink"), "ramp": _ramp("spark_cold"), "streak": true, "spin": 0.0, "life_rand": 0.5 })
	if bits:
		_emit(r, _chunk_mesh(), _mat("chunk"), 6, 0.9, { "speed": Vector2(2.5, 5.5), "dir": Vector3.UP, "spread": 70.0, "gravity": Vector3(0, -12.0, 0),
			"scale": Vector2(0.06, 0.12), "grow": _curve("shrink"), "spin_speed": 540.0 })
	return r


## A ship or speeder going up at `at`. `size` 1 is a ship (a fireball some 5 m
## across); a speeder is about 0.6, a grenade 0.7. `space`: nothing falls, no dust
## or smoke hangs about, and a shock ring stands in for the dust.
##
## Seven emitters and one light, as before it had: the second knot of fire is the
## one fire emitter letting its puffs out over the first instants, and the dust
## takes the ground ring's place. On the ground the blast stands on the planet's up.
static func big(parent: Node, at: Vector3, size := 1.0, space := false) -> Node3D:
	var r := _root(parent, at)
	if r == null:
		return null
	var s := maxf(0.1, size)
	var t := pow(s, 0.35)            # bigger burns a little longer, not proportionally
	var up := Vector3.UP
	if not space:
		up = _up_at(at)
		if up.dot(Vector3.UP) < -0.9999:        # the far side: the arc has no single axis
			r.global_basis = Basis(Vector3.RIGHT, PI)
		elif up.dot(Vector3.UP) < 0.9999:
			r.global_basis = Basis(Quaternion(Vector3.UP, up))
	var fall := Vector3.ZERO if space else up * -14.0
	if not space:
		_light_smoke()
	_light(r, Color("#fff0d0"), 26.0, 32.0 * s, 0.9 * t, 0.12, Color("#ff7a30"))
	_emit(r, _quad(), _mat("flash"), 1, 0.16 * t, { "scale": Vector2(10.0, 10.0) * s, "grow": _curve("pop"), "ramp": _ramp("flash_hot"), "radius": 0.01, "speed": Vector2.ZERO })
	if space:
		_emit(r, _quad(), _mat("ring"), 1, 0.4 * t, { "scale": Vector2(20.0, 20.0) * s, "grow": _curve("ring"), "ramp": _ramp("ring"), "radius": 0.01, "speed": Vector2.ZERO })
	else:
		# The blast throws the sand out flat and fast, and it hangs as it slows.
		_emit(r, _quad(), _mat("smoke"), 7, 1.8 * t, { "radius": 0.6 * s, "dir": Vector3.RIGHT, "spread": 180.0, "flat": 0.92,
			"speed": Vector2(8.0, 14.0) * s, "damping": Vector2(10.0, 16.0) * s, "gravity": up * 0.3 * s, "scale": Vector2(3.2, 5.0) * s,
			"grow": _curve("rise"), "ramp": _ramp("dust"), "spin": 40.0, "life_rand": 0.35 })
	# The fireball: its puffs come out over the first instants (burst under 1), so it
	# does not peak all at once, and they swell fast then creep.
	_emit(r, _quad(), _mat("fire"), 17, 1.2 * t, { "burst": 0.88, "radius": 1.1 * s, "speed": Vector2(2.0, 9.0) * s, "damping": Vector2(5.0, 8.0) * s,
		"gravity": up * (0.0 if space else 2.2) * s, "scale": Vector2(3.0, 5.6) * s, "grow": _curve("billow"), "ramp": _ramp("fire") })
	# Tongues of flame shot out of it, drawn long along their flight, pulling in as they stop.
	_emit(r, _quad(), _mat("fire_jet"), 8, 0.55 * t, { "radius": 0.4 * s, "speed": Vector2(16.0, 28.0) * s, "damping": Vector2(26.0, 40.0) * s,
		"dir": Vector3.UP, "spread": 180.0 if space else 80.0, "scale": Vector2(1.3, 2.1) * s, "grow": _curve("billow"), "ramp": _ramp("fire_clean"),
		"streak": true, "spin": 0.0, "life_rand": 0.4 })
	_emit(r, _spark_mesh(), _mat("spark"), 48, 1.3 * t, { "radius": 0.5 * s, "speed": Vector2(12.0, 30.0) * s, "gravity": fall, "damping": Vector2(2.0, 4.0) * s,
		"scale": Vector2(0.6, 1.3) * s, "grow": _curve("shrink"), "ramp": _ramp("spark_hot"), "streak": true, "spin": 0.0, "life_rand": 0.5 })
	_emit(r, _chunk_mesh(), _mat("chunk"), 10, 1.8 * t, { "radius": 0.6 * s, "speed": Vector2(7.0, 17.0) * s, "dir": Vector3.UP, "spread": 180.0 if space else 75.0,
		"gravity": fall, "scale": Vector2(0.25, 0.6) * s, "grow": _curve("shrink"), "spin_speed": 400.0 })
	if not space:
		_emit(r, _quad(), _mat("smoke"), 12, 3.4 * t, { "delay": 0.25, "burst": 0.7, "radius": 1.4 * s, "speed": Vector2(1.5, 3.5) * s, "dir": Vector3.UP,
			"spread": 30.0, "gravity": up * 0.6 * s, "damping": Vector2(0.4, 0.8), "scale": Vector2(3.4, 5.6) * s, "grow": _curve("rise"),
			"ramp": _ramp("smoke_dark"), "spin": 20.0 })
	_free_after(r, (4.0 if not space else 2.2) * t)
	return r


## The planet's up at `at` (straight up off a planet, or on its flat middle).
static func _up_at(at: Vector3) -> Vector3:
	var ps := PlanetSphere.current
	if ps == null or not is_instance_valid(ps):
		return Vector3.UP
	return ps.up_at(at)


## Issue #404: a wreck's light smoke, curling up from `parent` (local `at`) for as
## long as it emits. Not one-shot: the caller thins it (`amount_ratio`) and stops it.
## `size` 1 is a ship's.
static func smoke_trail(parent: Node3D, at: Vector3, size := 1.0, amount := 14, life := 4.5) -> CPUParticles3D:
	if parent == null or not is_instance_valid(parent):
		return null
	var s := maxf(0.1, size)
	_light_smoke()
	var p := _emit(parent, _quad(), _mat("smoke"), amount, life, { "radius": 0.6 * s, "speed": Vector2(0.8, 2.0) * s, "dir": Vector3.UP,
		"spread": 18.0, "gravity": Vector3(0.4, 1.1, 0.2) * s, "damping": Vector2(0.2, 0.5), "scale": Vector2(1.6, 3.2) * s,
		"grow": _curve("rise"), "ramp": _ramp("smoke_light"), "spin": 40.0, "burst": 0.0, "life_rand": 0.4 })
	p.one_shot = false
	p.local_coords = false
	p.position = at
	return p


## The smoke is lit by the sun and the sky's fill (explosion_puff.gdshader): hand the
## one shared smoke material the look's sun now. Three uniforms per smoky blast, so
## the smoke follows the time of day without tracking every frame.
static func _light_smoke() -> void:
	var look := LookEnvironment.active
	if look == null or not is_instance_valid(look) or look.sun == null:
		return
	var m := _mat("smoke") as ShaderMaterial
	var c := look.sun.light_color * minf(look.sun.light_energy, 1.3) * 1.35
	var fill := 0.53 * look.ambient_now()
	m.set_shader_parameter("sun_dir", look.sun_dir)
	m.set_shader_parameter("sun_col", Vector3(c.r, c.g, c.b) * (1.0 if look.sun.visible else 0.0))
	m.set_shader_parameter("amb_col", Vector3(1.0, 0.91, 0.97) * fill)


# ------------------------------------------------------------------ building

static func _root(parent: Node, at: Vector3) -> Node3D:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var r := Node3D.new()
	r.name = "Explosion"
	parent.add_child(r)
	r.global_position = at
	return r


## One one-shot emitter under `r`. `o`: radius, dir, spread (degrees), speed and
## damping (min, max), gravity, scale (min, max), grow (a Curve over its life),
## ramp (a Gradient over its life), spin (start angle range, degrees), spin_speed
## (degrees/s), streak (stretch along its flight), burst (explosiveness), life_rand,
## delay (seconds before it fires), flat (0..1: how far the spread keeps to the
## emitter's own flat plane). Direction and spread turn with the root; gravity is
## the world's, so a turned root passes it already turned.
static func _emit(r: Node3D, mesh: Mesh, mat: Material, amount: int, life: float, o: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = float(o.get("burst", 1.0))
	p.lifetime_randomness = float(o.get("life_rand", 0.3))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(0.01, float(o.get("radius", 0.1)))
	p.direction = o.get("dir", Vector3.UP)
	p.spread = float(o.get("spread", 180.0))
	p.flatness = float(o.get("flat", 0.0))
	p.gravity = o.get("gravity", Vector3.ZERO)
	var v: Vector2 = o.get("speed", Vector2(1.0, 2.0))
	p.initial_velocity_min = v.x
	p.initial_velocity_max = v.y
	var d: Vector2 = o.get("damping", Vector2.ZERO)
	p.damping_min = d.x
	p.damping_max = d.y
	var sc: Vector2 = o.get("scale", Vector2.ONE)
	p.scale_amount_min = sc.x
	p.scale_amount_max = sc.y
	if o.has("grow"):
		p.scale_amount_curve = o.grow
	if o.has("ramp"):
		p.color_ramp = o.ramp
	var spin := float(o.get("spin", 180.0))
	p.angle_min = -spin
	p.angle_max = spin
	var spin_speed := float(o.get("spin_speed", 30.0))
	p.angular_velocity_min = -spin_speed
	p.angular_velocity_max = spin_speed
	# A steady random number per particle for the puff shader's noise (INSTANCE_CUSTOM.z).
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	p.particle_flag_align_y = bool(o.get("streak", false))
	p.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.emitting = false
	r.add_child(p)
	var delay := float(o.get("delay", 0.0))
	if delay > 0.0:
		r.create_tween().tween_callback(p.set.bind("emitting", true)).set_delay(delay)
	else:
		p.emitting = true
	return p


## A short light, no shadow. `flash` > 0: it starts at `energy` and drops to a
## third of it in that many seconds (the flash), then fades over `life` while its
## colour goes to `burn` (the fire's glow).
static func _light(r: Node3D, color: Color, energy: float, reach: float, life: float, flash := 0.0, burn := Color(0, 0, 0, 0)) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = false
	r.add_child(l)
	var tw := l.create_tween()
	if flash > 0.0:
		tw.tween_property(l, "light_energy", energy / 3.0, flash).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if burn.a > 0.0:
			tw.parallel().tween_property(l, "light_color", burn, flash + life * 0.5)
	tw.tween_property(l, "light_energy", 0.0, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


static func _free_after(r: Node3D, seconds: float) -> void:
	r.create_tween().tween_callback(r.queue_free).set_delay(seconds)


# ------------------------------------------------------------------ shared resources

static func _quad() -> Mesh:
	if not _m.has("quad"):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		_m.quad = q
	return _m.quad


## A spark: a thin box along its Y, which the emitter turns along its flight.
static func _spark_mesh() -> Mesh:
	if not _m.has("spark_mesh"):
		var b := BoxMesh.new()
		b.size = Vector3(0.05, 1.0, 0.05)
		_m.spark_mesh = b
	return _m.spark_mesh


static func _chunk_mesh() -> Mesh:
	if not _m.has("chunk_mesh"):
		var b := BoxMesh.new()
		b.size = Vector3(1.0, 0.45, 0.7)
		_m.chunk_mesh = b
	return _m.chunk_mesh


static func _mat(key: String) -> Material:
	var k := "mat_" + key
	if _m.has(k):
		return _m[k]
	var m: Material
	match key:
		"fire":
			m = _puff({ "erode": 0.8, "soft": 0.1, "energy": 2.6, "heat": 1.1, "shade": 0.0, "lumps": 2.6, "roil": 1.0 })
		"fire_jet":
			m = _puff({ "erode": 0.9, "soft": 0.12, "energy": 2.8, "heat": 1.0, "shade": 0.0, "lumps": 2.0, "roil": 1.0, "stretch": 3.2 })
		"smoke":
			m = _puff({ "erode": 0.7, "soft": 0.16, "energy": 1.0, "heat": 0.0, "shade": 1.0, "lumps": 2.0 })
		"flash":
			m = _glow(0, 6.0)
		"ring":
			m = _glow(1, 4.0)
		"spark":
			m = _glow(2, 5.0)
		"chunk":
			var c := StandardMaterial3D.new()
			c.albedo_color = Color("#2b2723")
			c.roughness = 0.85
			c.metallic = 0.3
			# A dull hot glow: fresh off the fire.
			c.emission_enabled = true
			c.emission = Color("#ff5a1e")
			c.emission_energy_multiplier = 0.2
			m = c
	_m[k] = m
	return m


static func _puff(params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(PUFF_SHADER)
	for p in params:
		m.set_shader_parameter(p, params[p])
	return m


static func _glow(shape: int, energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(GLOW_SHADER)
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("energy", energy)
	return m


## Colour over a particle's life. Values stay in 0..1; the shaders add the HDR.
static func _ramp(key: String) -> Gradient:
	var k := "ramp_" + key
	if _m.has(k):
		return _m[k]
	var stops: Array = []
	match key:
		"fire":
			stops = [[0.0, "#fff3d6"], [0.12, "#ffc35a"], [0.3, "#ff7a1c"], [0.5, "#c2340f"], [0.68, "#3a2620e8"], [0.85, "#221a16a0"], [1.0, "#1a141100"]]
		"fire_clean":    # fire that fades out hot, never going to soot
			stops = [[0.0, "#fff3d6"], [0.15, "#ffc35a"], [0.4, "#ff7a1c"], [0.7, "#c2340fa0"], [1.0, "#80200000"]]
		"smoke_dark":    # black soot off the fire, greying as it thins
			stops = [[0.0, "#16120f00"], [0.08, "#16120ff2"], [0.45, "#2b2622dc"], [1.0, "#6e686200"]]
		"smoke_light":   # a wreck's: thinner, greyer
			stops = [[0.0, "#2a242000"], [0.12, "#2a2420e0"], [0.6, "#4a4440b0"], [1.0, "#8a847e00"]]
		"dust":          # sand thrown out by the blast, a dusty grey-brown that suits any ground
			stops = [[0.0, "#4a3e3200"], [0.06, "#4a3e3290"], [0.5, "#5a4e4278"], [1.0, "#6a5e5200"]]
		"flash_hot":
			stops = [[0.0, "#fffaf0"], [0.5, "#ffd890c0"], [1.0, "#ff9a4a00"]]
		"flash_cold":
			stops = [[0.0, "#ffffff"], [0.5, "#bfe4ffc0"], [1.0, "#7fc8ff00"]]
		"ring":
			stops = [[0.0, "#fff1d8"], [1.0, "#ffb06000"]]
		"spark_hot":
			stops = [[0.0, "#fff6d8"], [0.35, "#ffb040"], [0.8, "#ff5a1ca0"], [1.0, "#c0300000"]]
		"spark_cold":
			stops = [[0.0, "#ffffff"], [0.25, "#a8dcff"], [0.6, "#ffb040c0"], [1.0, "#ff5a1c00"]]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(st): return float(st[0])))
	g.colors = PackedColorArray(stops.map(func(st): return Color(str(st[1]))))
	_m[k] = g
	return g


## Size over a particle's life (0..1).
static func _curve(key: String) -> Curve:
	var k := "curve_" + key
	if _m.has(k):
		return _m[k]
	var pts: Array = []
	match key:
		"pop":       # the flash: there at once, swells a little
			pts = [[0.0, 0.55], [0.4, 1.0], [1.0, 0.85]]
		"ring":      # the shock ring races out and slows
			pts = [[0.0, 0.1], [0.35, 0.75], [1.0, 1.0]]
		"billow":    # fire bursts out, then keeps creeping
			pts = [[0.0, 0.2], [0.07, 0.7], [0.25, 0.9], [1.0, 1.0]]
		"rise":      # smoke spreads as it climbs
			pts = [[0.0, 0.45], [1.0, 1.0]]
		"shrink":    # sparks and chunks: whole most of the way, gone at the end
			pts = [[0.0, 1.0], [0.75, 0.85], [1.0, 0.0]]
	var c := Curve.new()
	for pt in pts:
		c.add_point(Vector2(float(pt[0]), float(pt[1])))
	_m[k] = c
	return c
