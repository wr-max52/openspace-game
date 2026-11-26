extends SceneTree
## Writes worn variants of a kit outfit's colour textures: sun fade, dust that
## climbs from the boots, grease where hands wipe (thighs, belly, cuffs), grime in
## the folds, scuffed leather, a cloth grain; and one roughness/metal map for them
## all (grease shines, buckles and goggle rims read as metal, dust is matte).
##
##   godot --headless --path . -s res://tools/look/wear_outfit.gd -- id=local_worn
##   godot --headless --path . -s res://tools/look/wear_outfit.gd -- id=local_worn only=worn_blue
##
## Reads "wear" from the "kit" block of content/look/character_models.json:
##   { "<id>": { "meshes": [...], "base": albedo of the uncoloured piece,
##     "colors": { "<new colour>": "<source colour>" ("" = base) },
##     "source": colour texture pattern (%s = source colour),
##     "out": albedo pattern (%s = new colour),
##     "cloth": [two source colours]: where they differ is cloth, the rest is
##       leather, metal or the goggles (left their own colour, scuffed),
##     "normal", "orm": the piece's maps; "orm_out": the worn ORM,
##     "seed", "grease", "dust", "fade": how worn } }
## The noise is laid out on the body, not the texture (each texel's place on the
## piece's rest pose, rasterised from the meshes' UVs), so it runs across seams
## and the dirt sits where it would: dust low, grease at hand height.
## CharacterKit wears the ORM with every colour that begins with the id
## (characters.json, model.maps).

const CFG_PATH := "res://content/look/character_models.json"
const DUST := Color("#b39a76")
const OIL := Color("#1d1611")

var N := 2048
var pos := PackedFloat32Array()      ## 3 floats a texel: its place on the body (0 where nothing maps)
var hit := PackedByteArray()         ## 1 where a texel maps onto the body
var lo := Vector3.INF
var hi := -Vector3.INF


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	var cfg: Dictionary = all.get("kit", {}).get("wear", {}).get(str(args.get("id", "local_worn")), {})
	if cfg.is_empty():
		push_error("wear: no kit.wear.%s in %s" % [args.get("id", "local_worn"), CFG_PATH])
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var model: Node = (load(str(all.kit.fit.get("out", "res://assets/characters/kit/parts.glb"))) as PackedScene).instantiate()
	for name in cfg.meshes:
		var mi := model.find_child(str(name), true, false) as MeshInstance3D
		if mi == null:
			push_error("wear: no mesh " + str(name))
			continue
		_raster(mi.mesh)
	model.free()
	_dilate(4)
	print("wear: body map ", Time.get_ticks_msec() - t0, " ms")
	var src := str(cfg.source)
	var cloth_a := _rgb(src % str(cfg.cloth[0]))
	var cloth_b := _rgb(src % str(cfg.cloth[1]))
	var nrm := _rgb(str(cfg.normal))
	var w := _masks(cfg, cloth_a, cloth_b, nrm)
	print("wear: masks ", Time.get_ticks_msec() - t0, " ms")
	if not args.has("only"):
		_orm(cfg, w)
	for name in cfg.colors:
		if args.has("only") and str(name) != str(args.only):
			continue
		var from := str(cfg.colors[name])
		var img := _rgb(str(cfg.base) if from == "" else src % from)
		_albedo(img, w)
		var out := ProjectSettings.globalize_path(str(cfg.out) % name)
		img.save_png(out)
		print("wear: wrote ", out, " (", Time.get_ticks_msec() - t0, " ms)")
	quit()


static func _rgb(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.decompress()
	img.convert(Image.FORMAT_RGB8)
	return img


# ------------------------------------------------------------------ the body map

## Every triangle of the mesh into the texture: each texel it covers gets its
## place on the rest pose.
func _raster(mesh: Mesh) -> void:
	if pos.is_empty():
		pos.resize(N * N * 3)
		hit.resize(N * N)
	var a := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	for p in v:
		lo = lo.min(p)
		hi = hi.max(p)
	var fn := float(N)
	for t in range(0, idx.size(), 3):
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		var a0 := uv[i0] * fn
		var a1 := uv[i1] * fn
		var a2 := uv[i2] * fn
		var area := (a1.x - a0.x) * (a2.y - a0.y) - (a2.x - a0.x) * (a1.y - a0.y)
		if absf(area) < 1e-9:
			continue
		var x0 := maxi(0, int(floor(minf(a0.x, minf(a1.x, a2.x)))))
		var x1 := mini(N - 1, int(ceil(maxf(a0.x, maxf(a1.x, a2.x)))))
		var y0 := maxi(0, int(floor(minf(a0.y, minf(a1.y, a2.y)))))
		var y1 := mini(N - 1, int(ceil(maxf(a0.y, maxf(a1.y, a2.y)))))
		var p0 := v[i0]
		var p1 := v[i1]
		var p2 := v[i2]
		for y in range(y0, y1 + 1):
			var cy := y + 0.5
			for x in range(x0, x1 + 1):
				var cx := x + 0.5
				var w0 := ((a1.x - cx) * (a2.y - cy) - (a2.x - cx) * (a1.y - cy)) / area
				var w1 := ((a2.x - cx) * (a0.y - cy) - (a0.x - cx) * (a2.y - cy)) / area
				var w2 := 1.0 - w0 - w1
				if w0 < -0.02 or w1 < -0.02 or w2 < -0.02:
					continue
				var p := p0 * w0 + p1 * w1 + p2 * w2
				var k := y * N + x
				hit[k] = 1
				pos[k * 3] = p.x
				pos[k * 3 + 1] = p.y
				pos[k * 3 + 2] = p.z


## Spread the map a few texels past each island's edge (mipmaps and filtering
## read there).
func _dilate(passes: int) -> void:
	for _p in passes:
		var add := PackedInt32Array()
		var from := PackedInt32Array()
		for y in range(1, N - 1):
			for x in range(1, N - 1):
				var k := y * N + x
				if hit[k] != 0:
					continue
				for o in [-1, 1, -N, N]:
					if hit[k + o] != 0:
						add.append(k)
						from.append(k + o)
						break
		for i in add.size():
			var k := add[i]
			var f := from[i]
			hit[k] = 1
			pos[k * 3] = pos[f * 3]
			pos[k * 3 + 1] = pos[f * 3 + 1]
			pos[k * 3 + 2] = pos[f * 3 + 2]


# ------------------------------------------------------------------ the wear

## Per texel (0..1 each): cloth, fade, dust, grease, cavity (folds), edge (ridges),
## scratch, grain (signed).
func _masks(cfg: Dictionary, ca: Image, cb: Image, nrm: Image) -> Dictionary:
	var seed := int(cfg.get("seed", 611))
	var big := _noise(seed, 2.2, 3)
	var mid := _noise(seed + 1, 5.0, 4)
	var spot := _noise(seed + 2, 18.0, 2)
	var fine := _noise(seed + 3, 38.0, 1)
	var weave := _noise(seed + 4, 140.0, 1)    ## the cloth's grain: smooth, so the PNG stays small
	var grease_k := float(cfg.get("grease", 1.0))
	var dust_k := float(cfg.get("dust", 1.0))
	var fade_k := float(cfg.get("fade", 1.0))
	var da := ca.get_data()
	var db := cb.get_data()
	var dn := nrm.get_data()
	var hy := hi.y - lo.y
	var half_w := maxf(absf(lo.x), absf(hi.x))
	var out := {}
	for key in ["cloth", "fade", "dust", "grease", "cavity", "edge", "scratch", "grain"]:
		var arr := PackedFloat32Array()
		arr.resize(N * N)
		out[key] = arr
	var cloth: PackedFloat32Array = out.cloth
	var fade: PackedFloat32Array = out.fade
	var dust: PackedFloat32Array = out.dust
	var grease: PackedFloat32Array = out.grease
	var cavity: PackedFloat32Array = out.cavity
	var edge: PackedFloat32Array = out.edge
	var scratch: PackedFloat32Array = out.scratch
	var grain: PackedFloat32Array = out.grain
	for y in N:
		for x in N:
			var k := y * N + x
			var j := k * 3
			# Cloth: where the two recolours differ.
			var d := absf(da[j] - db[j]) + absf(da[j + 1] - db[j + 1]) + absf(da[j + 2] - db[j + 2])
			cloth[k] = clampf((d - 18.0) / 40.0, 0.0, 1.0)
			# Folds and ridges from the normal map (its slope across the texel).
			var xl := maxi(x - 2, 0)
			var xr := mini(x + 2, N - 1)
			var yu := maxi(y - 2, 0)
			var yd := mini(y + 2, N - 1)
			var curv := (float(dn[(y * N + xr) * 3]) - float(dn[(y * N + xl) * 3])) \
				- (float(dn[(yd * N + x) * 3 + 1]) - float(dn[(yu * N + x) * 3 + 1]))
			curv /= 255.0
			cavity[k] = clampf(-curv * 2.2, 0.0, 1.0)
			edge[k] = clampf(curv * 2.2, 0.0, 1.0)
			if hit[k] == 0:
				continue
			var p := Vector3(pos[j], pos[j + 1], pos[j + 2])
			grain[k] = clampf(weave.get_noise_3dv(p) * 1.6, -1.0, 1.0)
			var h := (p.y - lo.y) / hy                      # 0 at the soles, 1 at the crown
			var n_big := big.get_noise_3dv(p)
			var n_mid := mid.get_noise_3dv(p)
			var n_spot := spot.get_noise_3dv(p)
			fade[k] = clampf(0.5 + n_big * 1.4, 0.0, 1.0) * fade_k
			# Dust: thick on the boots and hems, thinning to the knees, a film above.
			var low := clampf((0.42 - h) / 0.38, 0.0, 1.0)
			dust[k] = clampf((low * low * 0.85 + 0.12) * (0.65 + n_mid * 0.7), 0.0, 1.0) * dust_k
			# Grease: blotches where hands wipe (the thighs and belly) and at the cuffs,
			# a few drips anywhere.
			var wipe := _bump(h, 0.47, 0.13) * 0.55 + _bump(h, 0.6, 0.06) * 0.25
			var cuff := clampf((absf(p.x) / half_w - 0.62) / 0.2, 0.0, 1.0) * _bump(h, 0.55, 0.12)
			var g := smoothstep(0.66, 0.9, n_mid * 0.45 + n_big * 0.2 + 0.32 + (wipe + cuff * 0.7) * 0.7)
			var drip := smoothstep(0.62, 0.8, n_spot) * 0.45
			grease[k] = clampf(maxf(g, drip) * grease_k, 0.0, 1.0)
			# Scratches on leather and metal: thin bright lines where a fine noise crosses zero.
			scratch[k] = clampf(1.0 - absf(fine.get_noise_3dv(p * Vector3(1.0, 3.0, 1.0))) / 0.035, 0.0, 1.0) \
				* (1.0 - cloth[k])
	return out


func _noise(seed: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	return n


static func _bump(x: float, at: float, width: float) -> float:
	var t := (x - at) / width
	return exp(-t * t)


## The worn albedo, in place.
func _albedo(img: Image, w: Dictionary) -> void:
	var data := img.get_data()
	var cloth: PackedFloat32Array = w.cloth
	var fade: PackedFloat32Array = w.fade
	var dust: PackedFloat32Array = w.dust
	var grease: PackedFloat32Array = w.grease
	var cavity: PackedFloat32Array = w.cavity
	var edge: PackedFloat32Array = w.edge
	var scratch: PackedFloat32Array = w.scratch
	var grain: PackedFloat32Array = w.grain
	for k in N * N:
		var j := k * 3
		var c := Color(data[j] / 255.0, data[j + 1] / 255.0, data[j + 2] / 255.0)
		var cl := cloth[k]
		# Sun fade: the cloth bleaches toward a pale, greyer version of itself.
		var l := c.get_luminance()
		var bleached := Color(l, l, l).lerp(c, 0.55).lightened(0.18)
		c = c.lerp(bleached, fade[k] * 0.55 * cl)
		# Cloth grain and leather mottling.
		c = c * (1.0 + grain[k] * (0.05 * cl + 0.03))
		# Grime in the folds; rubbed-pale ridges and scuffed edges.
		c = c * (1.0 - cavity[k] * 0.45)
		c = c.lerp(c.lightened(0.35), edge[k] * (0.3 + 0.3 * (1.0 - cl)))
		c = c.lerp(c.lightened(0.5), scratch[k] * 0.55)
		# Dust, then grease over it (grease darkens and soaks in).
		c = c.lerp(DUST, dust[k] * 0.55)
		c = c.lerp(c * OIL * 3.2, grease[k] * 0.7)
		data[j] = clampi(int(c.r * 255.0), 0, 255)
		data[j + 1] = clampi(int(c.g * 255.0), 0, 255)
		data[j + 2] = clampi(int(c.b * 255.0), 0, 255)
	img.set_data(N, N, false, Image.FORMAT_RGB8, data)


## The worn ORM (R occlusion, G roughness, B metal), one for every colour.
func _orm(cfg: Dictionary, w: Dictionary) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(str(cfg.orm)))
	img.decompress()
	img.convert(Image.FORMAT_RGB8)
	var base := _rgb(str(cfg.base))
	var bd := base.get_data()
	var data := img.get_data()
	var cloth: PackedFloat32Array = w.cloth
	var dust: PackedFloat32Array = w.dust
	var grease: PackedFloat32Array = w.grease
	var cavity: PackedFloat32Array = w.cavity
	var scratch: PackedFloat32Array = w.scratch
	for k in N * N:
		var j := k * 3
		var ao := data[j] / 255.0 * (1.0 - cavity[k] * 0.35)
		var rough := data[j + 1] / 255.0
		var metal := data[j + 2] / 255.0
		var cl := cloth[k]
		var bc := Color(bd[j] / 255.0, bd[j + 1] / 255.0, bd[j + 2] / 255.0)
		# Not cloth, pale and grey: a buckle, a rivet, a goggle rim.
		var is_metal := (1.0 - cl) * smoothstep(0.32, 0.5, bc.get_luminance()) * (1.0 - smoothstep(0.08, 0.2, bc.s))
		metal = maxf(metal, is_metal * 0.85)
		rough = lerpf(rough, 0.97, cl * 0.8)                   # cloth: matte
		rough = lerpf(rough, 0.62, (1.0 - cl) * 0.5)           # leather: a dull sheen
		rough = lerpf(rough, 0.38, is_metal)
		rough = lerpf(rough, 1.0, dust[k] * 0.6)
		rough = lerpf(rough, 0.32, grease[k] * 0.85)           # grease shines
		rough = lerpf(rough, 0.3, scratch[k] * is_metal)
		data[j] = clampi(int(ao * 255.0), 0, 255)
		data[j + 1] = clampi(int(rough * 255.0), 0, 255)
		data[j + 2] = clampi(int(metal * 255.0), 0, 255)
	img.set_data(N, N, false, Image.FORMAT_RGB8, data)
	var out := ProjectSettings.globalize_path(str(cfg.orm_out))
	img.save_png(out)
	print("wear: wrote ", out)
