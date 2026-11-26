extends SceneTree
## Writes colour variants for each part of a fitted character (tools/look/fit_parts.gd).
## Every part has its own texture, so each part names the colour it swaps.
##
##   godot --headless --path . -s res://tools/look/recolor_fitted.gd -- id=smuggler
##   godot --headless --path . -s res://tools/look/recolor_fitted.gd -- id=smuggler analyze=1
##   godot --headless --path . -s res://tools/look/recolor_fitted.gd -- id=kit only=void
##   godot --headless --path . -s res://tools/look/recolor_fitted.gd -- id=kit part=nomad,cantina_owner
##
## Reads "part_colors" from content/look/character_models.json:
##   out:   res:// path with %s for the part and %s for the colour name
##   parts: { part: { mesh, tol: 0.35, min_l: 0.02, variants: { name: { "#from": "#to", ... } } } }
##   (a swap's "#to" can be ["#to", tol, min_l] to set those for that swap alone: a
##   saturated accent spreads further in chroma than a neutral base, and its dark
##   folds sit under a min_l that keeps a black undersuit out of a grey swap)
## mesh names the mesh whose texture is recoloured (default: the part name). A kit
## outfit's pieces share one texture, so one entry ("player", mesh "player_torso")
## gives every piece of that outfit its variants.
## min_l leaves texels darker than it alone (a black visor on a grey helmet).
## A variant is a list of swaps. A texel is swapped when its chroma (colour divided by
## brightness, so shading does not matter) is within `tol` of a `from`'s; its
## brightness relative to `from` is kept, so folds and stitching survive. Use the same
## variant names on every part so a whole outfit can match. analyze=1 prints each
## part's main colours instead.
##
## A part's optional "paint" paints zones of one mesh after the swaps, placed on the
## mesh, not the colours (a nomad's breather is the same sand as its hood):
##   paint: { mesh (whose triangles say where zones can land; default the part's),
##            scale (noise per metre for the wear, default 8),
##            cloth { fade, grain, grime, dust, mottle, seed }: the locals' worn cloth
##            (tools/look/wear_outfit.gd) over the whole piece before the zones,
##            zones: [ { color "#hex" | colors { variant: "#hex" } (a variant not
##                       listed leaves the zone alone),
##                       box [[x0,y0,z0],[x1,y1,z1]], ellipsoid [[cx,cy,cz],[rx,ry,rz]]
##                       (mesh space, metres; both = inside both), not [ shapes ],
##                       lens_ring [inner, outer] (metres out from the rim of each
##                       goggle lens, found by the low roughness in the mesh's ORM map,
##                       measured across the face and no more than lens_depth (default
##                       0.02) in front of or behind the lens; with box/ellipsoid =
##                       inside those too),
##                       ridge { centre [x, y, z], half, rise }: a crest along the
##                       middle of the head, what stands more than `rise` metres
##                       proud of the hood within `half` of the middle (the hood
##                       measured just beside it, all round `centre`),
##                       feather (metres of soft edge), max_s / min_l (texels more
##                       saturated / darker are left alone: a lit visor, a black lens),
##                       detail (0..1.5, how much of the texel's own light and shade
##                       the paint keeps, default 1),
##                       wear { amount, edges, dust, grime }: worn paint as on the
##                       speeders (tools/look/prep_vehicle.gd _weather): dulled, dust on
##                       what faces up, grime in creases, chipped back to the texel
##                       underneath (bare metal) along the outer edges and in specks } ] }
## The texture keeps its size and file, so a painted head costs nothing to load.

const CFG_PATH := "res://content/look/character_models.json"
const Vehicle := preload("res://tools/look/prep_vehicle.gd")


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var id := str(args.get("id", "smuggler"))
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	var cfg: Dictionary = all.get(id, {})
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if not cfg.has("fit") or doc.append_from_file(ProjectSettings.globalize_path(str(cfg.fit.out)), state) != OK:
		push_error("recolor: no fitted model for '%s' (run fit_parts.gd first)" % id)
		quit(1)
		return
	var scene := doc.generate_scene(state)
	var pc: Dictionary = cfg.get("part_colors", {"parts": {}})
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var img := _albedo(mi)
		if img != null and args.has("analyze"):
			_analyze(String(mi.name), img)
	for part in ({} if args.has("analyze") else pc.parts):
		if args.has("part") and not str(args.part).split(",").has(str(part)):
			continue            # only these parts: leave the others' files alone
		var p: Dictionary = pc.parts[part]
		var mi := scene.find_child(str(p.get("mesh", part)), true, false) as MeshInstance3D
		var img := _albedo(mi) if mi != null else null
		if img == null:
			push_error("recolor: no textured mesh for '%s'" % part)
			continue
		var painter := _paint_prep(scene, p.paint, img) if p.has("paint") else {}
		for name in p.variants:
			if args.has("only") and str(name) != str(args.only):
				continue        # one new variant: leave the others' files alone
			var out := ProjectSettings.globalize_path(str(pc.out) % [part, name])
			DirAccess.make_dir_recursive_absolute(out.get_base_dir())
			var v := img
			for from in p.variants[name]:
				var to = p.variants[name][from]
				var tol := float(p.get("tol", 0.35))
				var min_l := float(p.get("min_l", 0.02))
				if to is Array:
					tol = float(to[1])
					min_l = float(to[2]) if to.size() > 2 else min_l
					to = to[0]
				v = _recolor(v, Color(str(from)), Color(str(to)), tol, min_l)
			if not painter.is_empty():
				v = _paint(v, img, painter, str(name))
			v.save_png(out)
			print("recolor: wrote ", out)
	scene.free()
	quit()


## The mesh's albedo texture as RGBA8, or null.
static func _albedo(mi: MeshInstance3D) -> Image:
	var mat := mi.mesh.surface_get_material(0)
	if not (mat is BaseMaterial3D) or (mat as BaseMaterial3D).albedo_texture == null:
		return null
	var img := (mat as BaseMaterial3D).albedo_texture.get_image()
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _chroma(c: Color) -> Vector3:
	var l := maxf(c.get_luminance(), 0.02)
	return Vector3(c.r, c.g, c.b) / l


static func _recolor(src: Image, from: Color, to: Color, tol: float, min_l: float) -> Image:
	var img := src.duplicate() as Image
	var fc := _chroma(from)
	var fl := maxf(from.get_luminance(), 0.001)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.get_luminance() < min_l:
				continue
			var m := 1.0 - smoothstep(tol * 0.6, tol, _chroma(c).distance_to(fc))
			if m <= 0.0:
				continue
			var k := c.get_luminance() / fl
			img.set_pixel(x, y, c.lerp(Color(to.r * k, to.g * k, to.b * k, c.a).clamp(), m))
	return img


## The eight most common colours (4 bits a channel), with their share of the texture.
static func _analyze(part: String, img: Image) -> void:
	var bins := {}
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var key := Vector3i(int(c.r * 15.0), int(c.g * 15.0), int(c.b * 15.0))
			var e: Array = bins.get(key, [0, Vector3.ZERO])
			bins[key] = [e[0] + 1, e[1] + Vector3(c.r, c.g, c.b)]
			n += 1
	var keys := bins.keys()
	keys.sort_custom(func(a, b): return bins[a][0] > bins[b][0])
	var line := []
	for key in keys.slice(0, 8):
		var avg: Vector3 = bins[key][1] / bins[key][0]
		line.append("%s %d%%" % [Color(avg.x, avg.y, avg.z).to_html(false), 100 * bins[key][0] / n])
	print("analyze %s: %s" % [part, ", ".join(line)])


## Where a part's paint zones land, worked out once for all its variants: for each
## zone the texels it covers, how strongly, the shade each keeps and its wear.
static func _paint_prep(scene: Node, cfg: Dictionary, base: Image) -> Dictionary:
	var mi := scene.find_child(str(cfg.get("mesh", "")), true, false) as MeshInstance3D
	if mi == null:
		push_error("recolor: paint has no mesh '%s'" % cfg.get("mesh", ""))
		return {}
	var size := base.get_size()
	var box := mi.mesh.get_aabb()
	var t0 := Time.get_ticks_msec()
	var baked: Array = Vehicle._bake_place(mi, 0, mi, box, mini(size.x, 2048))
	var place: Image = baked[0]
	var edges: Image = baked[1]
	if place.get_width() != size.x:
		place.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		edges.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	var covered := PackedInt32Array()
	var pos := PackedVector3Array()
	for y in size.y:
		for x in size.x:
			var pl := place.get_pixel(x, y)
			if pl.a >= 0.05:
				covered.append(y * size.x + x)
				pos.append(box.position + Vector3(pl.r, pl.g, pl.b) * box.size)
	var lenses := _lenses(mi, base, covered, pos, box) if cfg.zones.any(func(z): return z.has("lens_ring")) else []
	var ctx := {"lenses": lenses}
	for z: Dictionary in cfg.zones:
		if z.has("ridge") and not ctx.has(str(z.ridge)):
			ctx[str(z.ridge)] = _ridge_profile(z.ridge, pos)
	var sc := float(cfg.get("scale", 8.0))
	var patches := Vehicle._noise(41, 0.7, 4)
	var breakup := Vehicle._noise(47, 7.0, 3)
	var speck := Vehicle._noise_img(size, 53, 0.09, 1)
	var zones := []
	for z: Dictionary in cfg.zones:
		var idx := PackedInt32Array()
		var wt := PackedFloat32Array()
		var lum := PackedFloat32Array()
		for i in covered.size():
			var t := covered[i]
			var c := base.get_pixel(t % size.x, t / size.x)
			if c.s > float(z.get("max_s", 2.0)) or c.get_luminance() < float(z.get("min_l", -1.0)):
				continue
			var w := _zone_w(z, pos[i], ctx)
			if w <= 0.0:
				continue
			idx.append(t)
			wt.append(w)
			lum.append(c.get_luminance())
		var sum := 0.0
		var n := 0
		for i in idx.size():
			if wt[i] > 0.5:
				sum += lum[i]
				n += 1
		var ref := maxf(sum / maxf(n, 1), 0.02)
		var detail := float(z.get("detail", 1.0))
		var kk := PackedFloat32Array()
		kk.resize(idx.size())
		for i in idx.size():
			kk[i] = clampf(lerpf(1.0, lum[i] / ref, detail), 0.3, 1.7)
		var zone := {"cfg": z, "idx": idx, "w": wt, "k": kk}
		if z.has("wear"):
			# per texel: dull, dust, crease, chip (0..1 each), as on the speeders
			var wr: Dictionary = z.wear
			var amt := float(wr.get("amount", 1.0))
			var edge_amt := float(wr.get("edges", 1.0)) * amt
			var wear := PackedColorArray()
			wear.resize(idx.size())
			var at := {}
			for i in covered.size():
				at[covered[i]] = i
			for i in idx.size():
				var t := idx[i]
				var p: Vector3 = pos[at[t]] * sc
				var ed := edges.get_pixel(t % size.x, t / size.x)  # r outer edge, g inner crease
				var up := (place.get_pixel(t % size.x, t / size.x).a - 0.1) / 0.9
				var pn := 0.5 + 0.5 * patches.get_noise_3dv(p)
				var bn := 0.5 + 0.5 * breakup.get_noise_3dv(p)
				var settle := smoothstep(0.55, 0.95, up) * smoothstep(0.3, 0.7, 1.0 - pn) * float(wr.get("dust", 1.0))
				var crease := smoothstep(0.15, 0.6, ed.g) * (0.6 + 0.4 * pn) * float(wr.get("grime", 1.0))
				var chip := smoothstep(0.45, 0.75, ed.r + (bn - 0.5) * 0.7) * edge_amt
				var k := speck.get_pixel(t % size.x, t / size.x).r
				if k > 1.0 - 0.06 * amt or k < 0.03 * amt:
					chip = maxf(chip, 0.85)
				chip = maxf(chip, smoothstep(0.7, 0.9, pn) * smoothstep(0.62, 0.8, bn) * amt)   # rubbed patches
				wear[i] = Color(0.5 * amt, clampf(settle * 0.45 * amt, 0.0, 0.6), clampf(crease * 0.7 * amt, 0.0, 0.8), clampf(chip, 0.0, 0.95))
			zone["wear"] = wear
		zones.append(zone)
		print("recolor: paint zone %d: %d texels" % [zones.size() - 1, idx.size()])
	var cloth := _cloth_prep(mi, cfg.cloth, size, covered, pos, place, box) if cfg.has("cloth") else {}
	if cfg.has("orm_out"):
		_write_orm(mi, cfg, size, zones)
	print("recolor: paint prep %d ms, lenses %s" % [Time.get_ticks_msec() - t0, lenses])
	return {"size": size, "zones": zones, "cloth": cloth}


## The locals' worn cloth (tools/look/wear_outfit.gd) on a piece that is all cloth:
## sun-faded patches, a mottle, the weave's grain, grime in the folds and pale
## ridges (from the normal map's slope), dust on what faces up and on the lowest
## hem. Per covered texel, the same for every variant: Color(fade, grain, cavity,
## edge) and the dust in its own array. `cloth` { fade, grain, grime, dust, seed }.
static func _cloth_prep(mi: MeshInstance3D, c: Dictionary, size: Vector2i, covered: PackedInt32Array, pos: PackedVector3Array, place: Image, box: AABB) -> Dictionary:
	var mat := mi.mesh.surface_get_material(0) as BaseMaterial3D
	var nrm: Image = null
	if mat != null and mat.normal_texture != null:
		nrm = mat.normal_texture.get_image()
		nrm.decompress()
		nrm.convert(Image.FORMAT_RGBA8)
		nrm.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	var seed := int(c.get("seed", 611))
	var big := FastNoiseLite.new()
	big.seed = seed
	big.frequency = 2.2 * 4.0           # a head is a quarter of a body: the same patches, smaller
	big.fractal_octaves = 3
	var mid := FastNoiseLite.new()
	mid.seed = seed + 1
	mid.frequency = 5.0 * 4.0
	mid.fractal_octaves = 4
	var weave := FastNoiseLite.new()
	weave.seed = seed + 4
	weave.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	weave.frequency = 140.0 * 2.0
	weave.fractal_type = FastNoiseLite.FRACTAL_NONE
	var fade_k := float(c.get("fade", 1.0))
	var grain_k := float(c.get("grain", 1.0))
	var grime_k := float(c.get("grime", 1.0))
	var dust_k := float(c.get("dust", 1.0))
	var w := PackedColorArray()
	w.resize(covered.size())
	var dust := PackedFloat32Array()
	dust.resize(covered.size())
	for i in covered.size():
		var t := covered[i]
		var x := t % size.x
		var y := t / size.x
		var p := pos[i]
		var cav := 0.0
		var edg := 0.0
		if nrm != null:
			var curv := (nrm.get_pixel(mini(x + 2, size.x - 1), y).r - nrm.get_pixel(maxi(x - 2, 0), y).r) \
				- (nrm.get_pixel(x, mini(y + 2, size.y - 1)).g - nrm.get_pixel(x, maxi(y - 2, 0)).g)
			cav = clampf(-curv * 2.2, 0.0, 1.0)
			edg = clampf(curv * 2.2, 0.0, 1.0)
		var nb := big.get_noise_3dv(p)
		var fade := clampf(0.5 + nb * 1.4, 0.0, 1.0) * fade_k
		var grain := clampf(weave.get_noise_3dv(p) * 1.6, -1.0, 1.0) * grain_k
		var up := (place.get_pixel(x, y).a - 0.1) / 0.9
		var h := (p.y - box.position.y) / box.size.y          # 0 at the hem, 1 at the crown
		var low := clampf((0.3 - h) / 0.3, 0.0, 1.0)
		dust[i] = clampf((smoothstep(0.6, 0.95, up) * 0.6 + low * 0.5 + 0.1) * (0.6 + mid.get_noise_3dv(p) * 0.8), 0.0, 1.0) * dust_k
		w[i] = Color(fade, grain, cav * grime_k, edg * grime_k)
	return {"idx": covered, "w": w, "dust": dust, "mottle": c.get("mottle", 0.12)}


## Paint over metal is not metal: one roughness/metal map for every variant (the
## zones and their chips are the same in each), the mesh's own map with each zone
## that sets `roughness` / `metallic` laid over it and its chips left bare. Written
## at `orm_size` (default 1024) to `orm_out`; characters.json "maps" hands it to the
## variants' colours.
static func _write_orm(mi: MeshInstance3D, cfg: Dictionary, size: Vector2i, zones: Array) -> void:
	var mat := mi.mesh.surface_get_material(0) as BaseMaterial3D
	if mat == null or mat.roughness_texture == null:
		push_error("recolor: paint orm_out needs the mesh's ORM map")
		return
	var orm := mat.roughness_texture.get_image()
	orm.decompress()
	orm.convert(Image.FORMAT_RGBA8)
	orm.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	for zone: Dictionary in zones:
		var z: Dictionary = zone.cfg
		if not z.has("roughness") and not z.has("metallic"):
			continue
		var idx: PackedInt32Array = zone.idx
		var wt: PackedFloat32Array = zone.w
		var wear: PackedColorArray = zone.get("wear", PackedColorArray())
		for i in idx.size():
			var x := idx[i] % size.x
			var y := idx[i] / size.x
			var c := orm.get_pixel(x, y)
			var w := wt[i] * (1.0 - (wear[i].a if not wear.is_empty() else 0.0))
			if z.has("roughness"):
				c.g = lerpf(c.g, float(z.roughness), w)
			if z.has("metallic"):
				c.b = lerpf(c.b, float(z.metallic), w)
			orm.set_pixel(x, y, c)
	var n := int(cfg.get("orm_size", 1024))
	orm.resize(n, n, Image.INTERPOLATE_LANCZOS)
	var out := ProjectSettings.globalize_path(str(cfg.orm_out))
	orm.save_png(out)
	print("recolor: wrote ", out)


## How far inside a zone's shapes a point is (0 outside, 1 well inside).
static func _zone_w(z: Dictionary, p: Vector3, ctx: Dictionary) -> float:
	var f := float(z.get("feather", 0.004))
	var lenses: Array = ctx.lenses
	var w := 1.0
	if z.has("ridge"):
		w = minf(w, _ridge_w(z.ridge, p, ctx[str(z.ridge)], f))
	if z.has("box"):
		w = minf(w, _box_w(z.box, p, f))
	if z.has("ellipsoid"):
		w = minf(w, _ellipsoid_w(z.ellipsoid, p, f))
	if z.has("lens_ring"):
		var best := 0.0
		for l: Array in lenses:
			var lc: Vector3 = l[0]
			if absf(p.z - lc.z) > float(z.get("lens_depth", 0.02)):
				continue                  # in front of or behind the rim: the face, the hood
			var d := Vector2(p.x - lc.x, p.y - lc.y).length() - float(l[1])   # goggles look along +Z
			var lo := float(z.lens_ring[0])
			var hi := float(z.lens_ring[1])
			best = maxf(best, smoothstep(lo - f, lo, d) * (1.0 - smoothstep(hi - f, hi, d)))
		w = minf(w, best)
	for s: Dictionary in z.get("not", []):
		if w <= 0.0:
			break
		var o := 1.0
		if s.has("box"):
			o = minf(o, _box_w(s.box, p, f))
		if s.has("ellipsoid"):
			o = minf(o, _ellipsoid_w(s.ellipsoid, p, f))
		w *= 1.0 - o
	return w


## A ridge along the middle of the head (a crest): seen side on, round `centre`,
## the hood's distance from it at each angle, from the texels just beside the
## ridge (`half` to `half` + 0.02 from the middle).
static func _ridge_profile(r: Dictionary, pos: PackedVector3Array) -> PackedFloat32Array:
	var c := Vector3(r.centre[0], r.centre[1], r.centre[2])
	var half := float(r.get("half", 0.03))
	var bins := []
	bins.resize(180)
	for i in 180:
		bins[i] = []
	for p in pos:
		var dx := absf(p.x - c.x)
		if dx < half or dx > half + 0.02:
			continue
		var v := Vector2(p.z - c.z, p.y - c.y)
		bins[int(fposmod(rad_to_deg(v.angle()), 360.0) / 2.0) % 180].append(v.length())
	var raw := PackedFloat32Array()
	raw.resize(180)
	for i in 180:
		var b: Array = bins[i]
		raw[i] = _median(b) if b.size() > 3 else -1.0
	# an angle with too few texels beside the ridge takes its nearest neighbour's
	var out := raw.duplicate()
	for i in 180:
		if raw[i] >= 0.0:
			continue
		for k in range(1, 12):
			if raw[(i + k) % 180] >= 0.0:
				out[i] = raw[(i + k) % 180]
				break
			if raw[(i - k + 180) % 180] >= 0.0:
				out[i] = raw[(i - k + 180) % 180]
				break
	return out


## How far a point stands proud of the hood on the ridge: 0 below `rise`
## (metres above the hood), 1 from `rise` + feather.
static func _ridge_w(r: Dictionary, p: Vector3, hood: PackedFloat32Array, f: float) -> float:
	var c := Vector3(r.centre[0], r.centre[1], r.centre[2])
	if absf(p.x - c.x) > float(r.get("half", 0.03)):
		return 0.0
	var v := Vector2(p.z - c.z, p.y - c.y)
	var h := hood[int(fposmod(rad_to_deg(v.angle()), 360.0) / 2.0) % 180]
	if h < 0.0:
		return 0.0
	return smoothstep(0.0, f, v.length() - h - float(r.get("rise", 0.006)))


static func _box_w(b: Array, p: Vector3, f: float) -> float:
	var lo := Vector3(b[0][0], b[0][1], b[0][2])
	var hi := Vector3(b[1][0], b[1][1], b[1][2])
	var inside := minf(minf(minf(p.x - lo.x, hi.x - p.x), minf(p.y - lo.y, hi.y - p.y)), minf(p.z - lo.z, hi.z - p.z))
	return smoothstep(0.0, f, inside)


static func _ellipsoid_w(e: Array, p: Vector3, f: float) -> float:
	var c := Vector3(e[0][0], e[0][1], e[0][2])
	var r := Vector3(e[1][0], e[1][1], e[1][2])
	var d := ((p - c) / r).length()          # 1 on the shell
	var fr := f / maxf(minf(r.x, minf(r.y, r.z)), 0.001)
	return 1.0 - smoothstep(1.0 - fr, 1.0, d)


## The goggle lenses: texels the mesh's ORM map marks smooth and the texture dark
## (glass; a polished frame is smooth too, but light), split left and right of the
## middle. Each [centre, radius] in mesh space.
static func _lenses(mi: MeshInstance3D, base: Image, covered: PackedInt32Array, pos: PackedVector3Array, box: AABB) -> Array:
	var mat := mi.mesh.surface_get_material(0) as BaseMaterial3D
	if mat == null or mat.roughness_texture == null:
		return []
	var orm := mat.roughness_texture.get_image()
	orm.decompress()
	orm.convert(Image.FORMAT_RGBA8)
	var size := base.get_size()
	orm.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	var mid := box.get_center().x
	var sides := [[], []]
	for i in covered.size():
		var t := covered[i]
		if orm.get_pixel(t % size.x, t / size.x).g < 0.45 and base.get_pixel(t % size.x, t / size.x).get_luminance() < 0.35:
			sides[0 if pos[i].x < mid else 1].append(pos[i])
	var out := []
	for s: Array in sides:
		if s.size() < 20:
			continue
		# the median, then the mean of what lies near it: stray smooth texels elsewhere
		# on the head (a buckle, a seam) do not drag the lens
		var c := Vector3(_median(s.map(func(p): return p.x)), _median(s.map(func(p): return p.y)), _median(s.map(func(p): return p.z)))
		var near: Array = s.filter(func(p): return p.distance_to(c) < 0.05)
		if near.size() < 20:
			continue
		c = Vector3.ZERO
		for p: Vector3 in near:
			c += p
		c /= near.size()
		var ds: Array = near.map(func(p): return p.distance_to(c))
		ds.sort()
		out.append([c, float(ds[int(ds.size() * 0.85)])])
	return out


static func _median(a: Array) -> float:
	a.sort()
	return float(a[a.size() / 2])


## The variant's texture with its paint zones painted on. `base` is the texture
## before any swap: the shade the paint keeps and the bare metal its chips show.
static func _paint(src: Image, base: Image, painter: Dictionary, variant: String) -> Image:
	var img := src.duplicate() as Image
	var w_px: int = painter.size.x
	var dull := Color(0.9, 0.86, 0.8)
	var dust := Color("#b39468")
	var shade := Color("#1b1510")
	var cloth: Dictionary = painter.get("cloth", {})
	if not cloth.is_empty():
		var cidx: PackedInt32Array = cloth.idx
		var cw: PackedColorArray = cloth.w
		var cd: PackedFloat32Array = cloth.dust
		var cloth_dust := Color("#b39a76")      # wear_outfit.gd's DUST
		for i in cidx.size():
			var x := cidx[i] % w_px
			var y := cidx[i] / w_px
			var c := img.get_pixel(x, y)
			var a := c.a
			var f := cw[i]                          # r fade, g grain, b cavity, a edge
			var l := c.get_luminance()
			c = c.lerp(Color(l, l, l).lerp(c, 0.55).lightened(0.18), f.r * 0.55)
			c = c * (1.0 + (f.r - 0.5) * float(cloth.mottle) * -2.0)   # faded patches thinner, the rest deeper
			c = c * (1.0 + f.g * 0.08)
			c = c * (1.0 - f.b * 0.45)
			c = c.lerp(c.lightened(0.35), f.a * 0.3)
			c = c.lerp(cloth_dust, cd[i] * 0.5)
			c.a = a
			img.set_pixel(x, y, c.clamp())
	for zone: Dictionary in painter.zones:
		var z: Dictionary = zone.cfg
		var hex := str(z.get("colors", {}).get(variant, z.get("color", "")))
		if hex == "":
			continue
		var col := Color(hex)
		var idx: PackedInt32Array = zone.idx
		var wt: PackedFloat32Array = zone.w
		var kk: PackedFloat32Array = zone.k
		var wear: PackedColorArray = zone.get("wear", PackedColorArray())
		for i in idx.size():
			var x := idx[i] % w_px
			var y := idx[i] / w_px
			var c := img.get_pixel(x, y)
			var out := Color(col.r * kk[i], col.g * kk[i], col.b * kk[i]).clamp()
			if not wear.is_empty():
				var wr := wear[i]                      # r dull, g dust, b crease, a chip
				out = out.lerp(out * dull, wr.r)
				out = out.lerp(dust, wr.g)
				out = out.lerp(shade, wr.b)
				out = out.lerp(base.get_pixel(x, y), wr.a)
			out.a = c.a
			img.set_pixel(x, y, c.lerp(out, wt[i]))
	return img
