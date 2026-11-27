extends SceneTree
## Bakes a moon (a "ball" planet: the asteroid, the lava moon) into two prints
## (cubemaps, 3x2 faces) that a neighbour's sky draws on a smooth sphere instead
## of a lumpy low-poly rock (space_travel.gd, painted_ball.gdshader):
##
##   <id>_paint.png   RGB the ground's colour, A how much light it gives off of
##                    its own (the lava, the station's lamps): the shader ramps a
##                    from the glow colour to the hot one (the lava's, or the
##                    lamps' on a moon with none).
##   <id>_relief.png  RGB the ground's normal (world axes, *0.5 + 0.5), A unused.
##
## The rock is the same ball the moon's own scene walks on (AsteroidSphere, seated
## on its station like SpaceTravel._ball_steps), coloured the way its shader
## colours it seen from far off (moon_rock / lava_rock.gdshader), with the lava in
## the low ground. Its furnishings are painted flat on top from the planet's data:
## the domes (glass, ribs, the ring wall), the landing pit and its shield, the
## tunnels' roofs, and the outposts out on the rock ('landmarks').
##
##   godot --headless --path . -s res://tools/planets/bake_moon_paint.gd -- [ids=grit_station,cinder_station] [size=1024]
##
## Writes assets/planets/<id>_paint.png and <id>_relief.png. Re-run when a moon's
## rock, station or outposts change.

const OUT := "res://assets/planets/"
const METAL := Color("#7c8288")
const TRIM := Color("#9aa1a6")
const DARK := Color("#252a2d")
const GLASS := Color("#4f6470")
const GLASS_LIT := Color("#9fb6c2")
const SHIELD := Color("#5fc8e8")
const LAMP := Color("#f0c77c")
const OUTPOST := Color("#4a4f55")
const SHIP := Color("#33363b")

var size := 1024
var ids: Array = ["grit_station", "cinder_station"]
var _frame := 0

# Per moon, while it bakes.
var sphere
var radius := 1500.0
var look := {}
var lava := {}
var level := -INF
var keep_clear := 0.0
var station := {}
var outposts: Array = []
var big := FastNoiseLite.new()
var mid := FastNoiseLite.new()
var fine := FastNoiseLite.new()
var swirl := FastNoiseLite.new()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("size="):
			size = int(a.substr(5))
		elif a.begins_with("ids="):
			ids = Array(a.substr(4).split(","))


func _process(_dt: float) -> bool:
	# Autoloads first (PlanetGen names things through WorldState): a frame or two in.
	_frame += 1
	if _frame < 3:
		return false
	for id in ids:
		_bake(str(id))
	return true


func _bake(id: String) -> void:
	var pg = load("res://src/systems/planets/planet_gen.gd")
	var st = load("res://src/systems/planets/space_travel.gd")
	var p: Dictionary = pg.build(id)
	var tcfg: Dictionary = p.get("type_cfg", {})
	if str(tcfg.get("ground", "")) != "ball":
		push_error("%s is not a ball planet" % id)
		return
	var surf: Dictionary = tcfg.get("surface", {})
	radius = pg.ball_radius(p.cfg, null)
	sphere = load("res://src/systems/planets/asteroid_sphere.gd").new(radius, surf)
	var site: Dictionary = st.site_of(p.town)
	sphere.configure_site(site.floor, site.walls, site.sunken, 0.0)
	look = {}
	var lk: Dictionary = surf.get("look", {})
	for k in ["rock_light", "rock_mid", "rock_dark"]:
		look[k] = Color(str(lk.get(k, "#808080"))).srgb_to_linear()
	lava = sphere.lava
	level = sphere.lava_level()
	keep_clear = sphere.lava_keep_clear() + sphere.LAVA_MARGIN
	station = p.town.get("station", {})
	outposts = []
	for l in p.cfg.get("landmarks", []):
		var at = l.get("at", null)
		if at is Array:
			# Its own ground frame (as PlanetTerrain.outpost_flat_sites lays its pad):
			# far round the ball the map is stretched across, so the outpost is
			# measured on the ground, not on the map.
			var dir: Vector3 = sphere.map_dir(float(at[0]), float(at[2]))
			var b: Basis = sphere.tilt_to(dir) * Basis(Vector3.UP, deg_to_rad(float(l.get("yaw_deg", 0.0))))
			outposts.append({ "dir": dir, "x": b.x, "z": b.z })
	var seed := int(p.cfg.get("seed", 0)) + id.hash()
	for nz in [[big, 1.0 / 520.0, 4], [mid, 1.0 / 90.0, 3], [fine, 1.0 / 14.0, 2], [swirl, 1.0 / 40.0, 3]]:
		var n: FastNoiseLite = nz[0]
		n.seed = seed
		n.frequency = nz[1]
		n.fractal_octaves = nz[2]
		seed += 17

	var t0 := Time.get_ticks_msec()
	var paint: Array = []
	var relief: Array = []
	paint.resize(6)
	relief.resize(6)
	var task := WorkerThreadPool.add_group_task(func(f: int):
		var r := _face(f)
		paint[f] = r[0]
		relief[f] = r[1], 6, -1, true, "moon paint bake")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for pair in [[paint, "_paint.png"], [relief, "_relief.png"]]:
		# Godot's cubemap import, arrangement 3x2: +X -X +Y on top, -Y +Z -Z below.
		var atlas := Image.create(size * 3, size * 2, false, Image.FORMAT_RGBA8)
		for f in 6:
			atlas.blit_rect(pair[0][f], Rect2i(0, 0, size, size), Vector2i((f % 3) * size, (f / 3) * size))
		atlas.save_png(ProjectSettings.globalize_path(OUT + id + pair[1]))
	print("MOON PAINT %s: %dx%d faces, lava level %.2f, %d outposts, %d ms" % [id, size, size, level, outposts.size(), Time.get_ticks_msec() - t0])


## The direction through face f at face coords (s, t), each -1..1 (GL / Godot
## order; the same as tools/planets/bake_relief.gd).
static func face_dir(f: int, s: float, t: float) -> Vector3:
	match f:
		0: return Vector3(1.0, -t, -s).normalized()
		1: return Vector3(-1.0, -t, s).normalized()
		2: return Vector3(s, 1.0, t).normalized()
		3: return Vector3(s, -1.0, -t).normalized()
		4: return Vector3(s, -t, 1.0).normalized()
	return Vector3(-s, -t, -1.0).normalized()


func _face(f: int) -> Array:
	# Heights on the face's texel centres, one texel of border all round.
	var n := size + 2
	var pts := PackedVector3Array()
	pts.resize(n * n)
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	var dirs := PackedVector3Array()
	dirs.resize(n * n)
	var molten := PackedFloat32Array()
	molten.resize(n * n)
	for j in n:
		var t := (float(j - 1) + 0.5) / size * 2.0 - 1.0
		for i in n:
			var s := (float(i - 1) + 0.5) / size * 2.0 - 1.0
			var d := face_dir(f, s, t)
			var h: float = sphere.elevation(d)
			var k := j * n + i
			dirs[k] = d
			hs[k] = h
			var m := _molten_at(d, h)
			molten[k] = m
			# The pools are liquid: flat at the lava's level (as lava_rock.gdshader lifts them).
			pts[k] = d * (radius + lerpf(h, maxf(h, level), m))
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var nrm := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var texel := 2.0 / size * radius      # metres a texel spans at the face's middle
	for j in size:
		for i in size:
			var k := (j + 1) * n + (i + 1)
			var du := pts[k + 1] - pts[k - 1]
			var dv := pts[k + n] - pts[k - n]
			var nm := du.cross(dv).normalized()
			if nm.dot(pts[k]) < 0.0:
				nm = -nm
			nrm.set_pixel(i, j, Color(nm.x * 0.5 + 0.5, nm.y * 0.5 + 0.5, nm.z * 0.5 + 0.5, 1.0))
			img.set_pixel(i, j, _paint(dirs[k], hs[k], molten[k], nm, texel))
	return [img, nrm]


## How molten the ground is at a direction (0 rock .. 1 lava), its height `h`.
func _molten_at(d: Vector3, h: float) -> float:
	if lava.is_empty():
		return 0.0
	var m: Vector2 = sphere.dir_map(d)
	var clear := smoothstep(keep_clear - 20.0, keep_clear, m.length())
	for o in outposts:
		clear = minf(clear, smoothstep(26.0, 34.0, d.angle_to(o.dir) * radius))   # each outpost on its dry pad
	return clear * (1.0 - smoothstep(level - 0.6, level + 0.6, h))


## A texel's colour (linear while mixed, sRGB out) and how much of it glows.
func _paint(d: Vector3, h: float, m: float, nm: Vector3, texel: float) -> Color:
	var p := d * radius
	var b := big.get_noise_3dv(p) * 0.5 + 0.5
	var b2 := mid.get_noise_3dv(p) * 0.5 + 0.5
	var fn := fine.get_noise_3dv(p) * 0.5 + 0.5
	# The rock as its shader colours it from far off: big patches, darker on steep walls.
	var col: Color = look.rock_mid.lerp(look.rock_light, smoothstep(0.3, 0.8, b * 0.5 + b2 * 0.5))
	var slope := 1.0 - clampf(nm.dot(d), 0.0, 1.0)
	col = col.lerp(look.rock_dark, smoothstep(0.12, 0.5, slope) * 0.75)
	col = _mul(col, 0.9 + 0.2 * fn)
	var glow := 0.0
	if not lava.is_empty():
		# The lava's light on the rock just above it.
		var bounce := (1.0 - smoothstep(level, level + 1.8, h)) * (1.0 - m)
		glow = 0.05 * bounce
		if m > 0.0:
			# The lava: a dark crust giving off its heat, hotter in the deep middle.
			var sw := swirl.get_noise_3dv(p) * 0.5 + 0.5
			var depth := clampf((level - h) / 2.0, 0.0, 1.0)
			var heat := clampf((0.25 + 0.8 * smoothstep(0.3, 0.8, sw) + 0.35 * depth) / 1.4, 0.0, 1.0)
			col = col.lerp(_lin(str(lava.get("crust", "#0f0503"))), m)
			glow = lerpf(glow, heat, m)
	var fur := _furnish(d, sphere.dir_map(d), texel)
	var fc: Color = fur[0]
	if fc.a > 0.0:
		col = col.lerp(Color(fc.r, fc.g, fc.b), fc.a)
		glow = lerpf(glow, float(fur[1]), fc.a)
	var out := col.linear_to_srgb()
	return Color(out.r, out.g, out.b, clampf(glow, 0.0, 1.0))


static func _mul(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)


static func _lin(hex: String) -> Color:
	return Color(hex).srgb_to_linear()


# ------------------------------------------------------------------ furnishings
# Every shape returns [colour (linear, a = how much of the texel it covers), glow].

const NONE := [Color(0, 0, 0, 0), 0.0]


## The station and the outposts painted at direction `d`, map point `m` (metres
## from the port).
func _furnish(d: Vector3, m: Vector2, texel: float) -> Array:
	var w := texel * 0.6                  # soft edges: about a texel
	var out: Array = NONE
	if not station.is_empty() and m.length() < 260.0:
		out = _station(m, w)
	for o in outposts:
		out = _over(out, _outpost(d, o, w))
	return out


func _station(m: Vector2, w: float) -> Array:
	var col: Array = NONE
	var rc := _xz(station.get("center", [0, 0, 0]))
	var rw := float(station.get("radius", 36.0))
	var pit: Dictionary = station.get("pit", {})
	var pc := _xz(pit.get("center", [0, 0, 0]))
	var pr := float(pit.get("radius", 28.0))
	# Tunnels first (the domes and the pit sit over their ends).
	var hall: Dictionary = station.get("hall", {})
	if not hall.is_empty():
		col = _over(col, _tunnel(m, pc, Vector2.LEFT, pc.x - float(hall.x0), pc.x - float(hall.end), float(hall.half), w))
	for dm in station.get("domes", []):
		var hb: Dictionary = dm.get("hall", {})
		if not hb.is_empty():
			var dir := Vector2(float(hb.dir[0]), float(hb.dir[1])).normalized()
			col = _over(col, _tunnel(m, pc, dir, float(hb.far), float(hb.end), float(hb.half), w))
	col = _over(col, _pit(m, pc, pr, w))
	col = _over(col, _dome(m, rc, rw, w, 1))
	for dm in station.get("domes", []):
		col = _over(col, _dome(m, _xz(dm.center), float(dm.radius), w, str(dm.id).hash()))
	return col


## A tunnel's metal roof from `far` to `end` metres along `dir` from the pit's middle.
func _tunnel(m: Vector2, pc: Vector2, dir: Vector2, far: float, end: float, half: float, w: float) -> Array:
	var rel := m - pc
	var s := rel.dot(dir)
	var t := absf(rel.dot(Vector2(-dir.y, dir.x)))
	var a := minf(far, end)
	var b := maxf(far, end)
	var cover := (1.0 - smoothstep(half + 0.3 - w, half + 0.3 + w, t)) * smoothstep(a - w, a + w, s) * (1.0 - smoothstep(b - w, b + w, s))
	if cover <= 0.0:
		return NONE
	# A lit strip down the middle of the roof, darker edges.
	var c := _lin_c(METAL).lerp(_lin_c(DARK), smoothstep(half - 1.2, half + 0.3, t) * 0.6)
	var strip := 1.0 - smoothstep(0.6, 0.6 + w, t)
	c = c.lerp(_lin_c(LAMP), strip * 0.5)
	return [Color(c.r, c.g, c.b, cover), strip * 0.25]


## The landing pit: its tall metal liner round a dark floor under a cyan shield.
func _pit(m: Vector2, pc: Vector2, pr: float, w: float) -> Array:
	var r := m.distance_to(pc)
	var cover := 1.0 - smoothstep(pr + 0.8 - w, pr + 0.8 + w, r)
	if cover <= 0.0:
		return NONE
	var c := _lin_c(DARK).lerp(_lin_c(SHIELD), 0.25 + 0.15 * smoothstep(pr * 0.9, 0.0, r))
	var rim := smoothstep(pr - 2.2 - w, pr - 2.2 + w, r)
	c = c.lerp(_lin_c(TRIM), rim)
	# The landing marks: a ring and a cross on the floor.
	var ring := 1.0 - smoothstep(0.5, 0.5 + w, absf(r - pr * 0.55))
	var rel := m - pc
	var cross := (1.0 - smoothstep(0.5, 0.5 + w, minf(absf(rel.x), absf(rel.y)))) * (1.0 - smoothstep(pr * 0.4, pr * 0.4 + w, r))
	var mark := maxf(ring, cross) * (1.0 - rim)
	c = c.lerp(_lin_c(LAMP), mark * 0.6)
	return [Color(c.r, c.g, c.b, cover), mark * 0.35]


## A dome from above: glass over the town's lights, ribs, the ring wall round it.
func _dome(m: Vector2, c0: Vector2, r0: float, w: float, seed: int) -> Array:
	var rel := m - c0
	var r := rel.length()
	var cover := 1.0 - smoothstep(r0 + 0.6 - w, r0 + 0.6 + w, r)
	if cover <= 0.0:
		return NONE
	var u := clampf(r / r0, 0.0, 1.0)
	# The glass: darker over the middle, the sky caught toward the rim.
	var c := _lin_c(GLASS).lerp(_lin_c(GLASS_LIT), smoothstep(0.45, 0.98, u) * 0.6)
	# The town's lights through the glass, a few warm blocks.
	var cell := Vector2(floorf(rel.x / 6.0), floorf(rel.y / 6.0))
	var hsh := fposmod(sin(cell.dot(Vector2(12.9898, 78.233)) + float(seed % 997)) * 43758.5453, 1.0)
	var lit := (1.0 if hsh > 0.72 else 0.0) * (1.0 - smoothstep(0.8, 0.9, u))
	c = c.lerp(_lin_c(LAMP), lit * 0.55)
	# Ribs: radial every 30 degrees and two rings, then the ring wall's rim.
	var ang := atan2(rel.y, rel.x)
	var seg := TAU / 12.0
	var off := absf(fposmod(ang + seg * 0.5, seg) - seg * 0.5) * r
	var rib := (1.0 - smoothstep(0.35, 0.35 + w, off)) * smoothstep(0.12, 0.2, u)
	rib = maxf(rib, 1.0 - smoothstep(0.35, 0.35 + w, absf(r - r0 * 0.5)))
	rib = maxf(rib, 1.0 - smoothstep(0.35, 0.35 + w, absf(r - r0 * 0.8)))
	c = c.lerp(_lin_c(TRIM), rib * 0.85)
	var wall := smoothstep(r0 - 1.0 - w, r0 - 1.0 + w, r)
	c = c.lerp(_lin_c(METAL), wall)
	return [Color(c.r, c.g, c.b, cover), lit * 0.3 * (1.0 - rib) * (1.0 - wall)]


## An outpost out on the rock: its trodden pad, the block, the ship parked by it.
func _outpost(d: Vector3, o: Dictionary, w: float) -> Array:
	var od: Vector3 = o.dir
	if d.dot(od) < cos(30.0 / radius):
		return NONE
	# Local frame: +x faces the station (yaw about up, as the landmark turns it).
	var rel := (d - od) * radius
	var lx := rel.dot(o.x)
	var lz := rel.dot(o.z)
	var r := Vector2(lx, lz).length()
	if r > 26.0:
		return NONE
	var c: Color = look.rock_light
	var a: float = (1.0 - smoothstep(18.0, 24.0, r)) * 0.45
	var ship := _box(lx, lz, -14.0, 2.0, 5.0, 4.0, w)
	c = c.lerp(_lin_c(SHIP), ship)
	a = maxf(a, ship)
	var block := _box(lx, lz, 0.0, 0.0, 4.0, 3.0, w)
	var edge := 1.0 - _box(lx, lz, 0.0, 0.0, 3.2, 2.2, w)
	c = c.lerp(_lin_c(OUTPOST).lerp(_lin_c(TRIM), edge * 0.7), block)
	a = maxf(a, block)
	var lamp := 1.0 - smoothstep(0.8, 0.8 + w, Vector2(lx - 5.0, lz).length())
	c = c.lerp(_lin_c(LAMP), lamp)
	a = maxf(a, lamp)
	return [Color(c.r, c.g, c.b, a), lamp * 0.6]


## Coverage of an axis-aligned box (half sizes hx, hz) centred at (cx, cz), local.
static func _box(x: float, z: float, cx: float, cz: float, hx: float, hz: float, w: float) -> float:
	var dx := absf(x - cx) - hx
	var dz := absf(z - cz) - hz
	return 1.0 - smoothstep(-w, w, maxf(dx, dz))


## `top` over `under` ([colour, glow] each, a = cover); the glow follows the top where it covers.
static func _over(under: Array, top: Array) -> Array:
	var tc: Color = top[0]
	if tc.a <= 0.0:
		return under
	var uc: Color = under[0]
	var a := tc.a + uc.a * (1.0 - tc.a)
	var k := (uc.a * (1.0 - tc.a)) / maxf(a, 0.0001)
	var c := Color(tc.r, tc.g, tc.b).lerp(Color(uc.r, uc.g, uc.b), k)
	return [Color(c.r, c.g, c.b, a), lerpf(float(top[1]), float(under[1]), k)]


static func _lin_c(c: Color) -> Color:
	return c.srgb_to_linear()


static func _xz(v) -> Vector2:
	return Vector2(float(v[0]), float(v[2]))
