extends SceneTree
## Turns a raw Hyper3D vehicle (issue #43) into a game model: turned to face -Z,
## scaled to its length in metres, centred on its middle, written as a .glb that
## ShipKit (a ship look's "scene") or SpeederNode (a vehicle look's "scene") loads.
##
##   godot --headless --path . -s res://tools/look/prep_vehicle.gd -- id=interceptor
##   godot --headless --path . -s res://tools/look/prep_vehicle.gd            # every entry
##
## Reads content/look/vehicle_models.json:
##   { id: { source, out, yaw_deg (turns the raw model so its nose faces -Z),
##           length (metres, nose to tail), max_span (metres; shrinks it further if
##           wider), max_height, paint ({ body, trim, glow, glow_energy,
##           metallic, roughness }: a paint job on the albedo, a lit core and
##           the finish; see _paint) } }
## Hyper3D models come out about 2 units long, facing any way; the numbers here are
## the only fix-up, so a re-generation is one source path and one yaw.

const CFG_PATH := "res://content/look/vehicle_models.json"


func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("id="):
			only = a.substr(3)
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	for id in all:
		if not (all[id] is Dictionary and all[id].has("source")) or (only != "" and id != only):
			continue
		_prep(id, all[id])
	quit()


func _prep(id: String, c: Dictionary) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(str(c.source)), state) != OK:
		push_error("prep_vehicle: cannot read " + str(c.source))
		return
	var model := doc.generate_scene(state) as Node3D
	var root := Node3D.new()
	root.name = id.to_pascal_case()
	var turn := Node3D.new()
	turn.name = "Model"
	root.add_child(turn)
	turn.add_child(model)
	turn.rotation.y = deg_to_rad(float(c.get("yaw_deg", 0.0)))
	var box := _aabb(root)
	var k := float(c.length) / maxf(box.size.z, 0.001)
	if c.has("max_span"):
		k = minf(k, float(c.max_span) / maxf(box.size.x, 0.001))
	if c.has("max_height"):
		k = minf(k, float(c.max_height) / maxf(box.size.y, 0.001))
	turn.scale = Vector3.ONE * k
	box = _aabb(root)
	turn.position = -box.get_center()
	box = _aabb(root)
	if c.has("cut_below"):
		_cut(root, box.position.y + float(c.cut_below), c.get("cut_plate", []))
		box = _aabb(root)
		turn.position.y -= box.get_center().y
		box = _aabb(root)
	if c.has("emission"):
		_emit(root, str(c.emission), float(c.get("emission_energy", 2.0)))
	if c.has("paint"):
		_paint(root, c.paint)
	if c.has("weather"):
		_weather(root, c.weather, box)
	_own(root, root)
	var out_doc := GLTFDocument.new()
	var out_state := GLTFState.new()
	out_doc.append_from_scene(root, out_state)
	var out := ProjectSettings.globalize_path(str(c.out))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	if out_doc.write_to_filesystem(out_state, out) != OK:
		push_error("prep_vehicle: cannot write " + out)
		return
	var tris := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			tris += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	print("prep_vehicle: %s  %.2f x %.2f x %.2f m (span x height x length), %d triangles -> %s" % [
		id, box.size.x, box.size.y, box.size.z, tris, out])
	root.free()


## Issue #82: one Hyper3D model, several paint jobs. The albedo's light panels
## take `body`, its mid greys (pads, frame, trim) take `trim`, near-black (glass,
## underside) stays as it is. The blue plasma core is lit by an emission map made
## from its own pixels, recoloured to `glow` when there is one; glow_energy 0
## leaves the blue unlit (the Lanner's blue bands are paint, not a core). `bands` [trim from,
## trim to, body from, body to] moves the luminance split, and `refs` [body, trim] the
## luminance each colour is matched at, for a darker albedo (the frigate's: mostly
## 0.2 to 0.3, all of it "trim" on the defaults). `metallic` / `roughness` replace the
## model's own finish (Hyper3D's de-lit textures come out chalky: the Lanner's were
## metallic 0.01, roughness 0.86).
static func _paint(root: Node, paint: Dictionary) -> void:
	var body := Color(str(paint.get("body", "#0000")))      # alpha 0 = leave it
	var trim := Color(str(paint.get("trim", "#0000")))
	var glow := Color(str(paint.get("glow", "#0000")))
	var bands: Array = paint.get("bands", [0.08, 0.2, 0.32, 0.5])
	var refs: Array = paint.get("refs", [0.8, 0.28])
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var img := mat.albedo_texture.get_image()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var em := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
			# Issue #628: a model with its own glow map (the newer Rodin ones) keeps
			# its glow: those texels are the glow, however pale their albedo is.
			var own: Image = null
			if mat.emission_enabled and mat.emission_texture != null:
				own = mat.emission_texture.get_image()
				if own.is_compressed():
					own.decompress()
				own.convert(Image.FORMAT_RGBA8)
				own.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_BILINEAR)
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					var lit := own != null and own.get_pixel(x, y).get_luminance() > 0.12
					if lit or (c.s > 0.35 and c.v > 0.3 and c.h > 0.5 and c.h < 0.72):
						var src := own.get_pixel(x, y) if lit else c
						var g := Color.from_hsv(glow.h, glow.s, maxf(c.v, src.v)) if glow.a > 0.0 else src
						img.set_pixel(x, y, g if glow.a > 0.0 or not lit else c)
						em.set_pixel(x, y, g)
						continue
					var l := c.get_luminance()
					var out := c
					var wb := smoothstep(float(bands[2]), float(bands[3]), l) if body.a > 0.0 else 0.0
					var wt := smoothstep(float(bands[0]), float(bands[1]), l) * (1.0 - wb) if trim.a > 0.0 else 0.0
					if wb > 0.0:
						out = out.lerp(body * clampf(l / float(refs[0]), 0.6, 1.15), wb)
					if wt > 0.0:
						out = out.lerp(trim * clampf(l / float(refs[1]), 0.45, 1.3), wt)
					out.a = c.a
					img.set_pixel(x, y, out)
			mat = mat.duplicate() as BaseMaterial3D
			mat.albedo_texture = ImageTexture.create_from_image(img)
			if float(paint.get("glow_energy", 3.0)) > 0.0:
				mat.emission_enabled = true
				mat.emission = Color.WHITE
				mat.emission_texture = ImageTexture.create_from_image(em)
				mat.emission_energy_multiplier = float(paint.get("glow_energy", 3.0))
			if paint.has("metallic"):
				mat.metallic_texture = null
				mat.metallic = float(paint.metallic)
			if paint.has("roughness"):
				mat.roughness_texture = null
				mat.roughness = float(paint.roughness)
			mi.mesh.surface_set_material(s, mat)


## Issue #628: Rodin hands the glow map over as its own file (texture_emissive.png
## beside the .glb), not inside it. `emission` is that file in source/; it lights
## the model's glow, and _paint leaves those texels alone when it recolours.
static func _emit(root: Node3D, path: String, energy: float) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		push_error("prep_vehicle: cannot read " + path)
		return
	var tex := ImageTexture.create_from_image(img)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			mat = mat.duplicate() as BaseMaterial3D
			mat.emission_enabled = true
			mat.emission = Color.WHITE
			mat.emission_texture = tex
			mat.emission_energy_multiplier = energy
			mi.mesh.surface_set_material(s, mat)


## Issue #628: wear on a clean Rodin texture, so a model sits beside the grimier
## ones (the racer, the cargo sled) as one family. Runs after the paint, on the
## painted albedo. Where each texel sits on the hull, which way it faces and how
## near it is to a crease are baked from the mesh (`_bake_place`), so the wear
## follows the model, not the UV islands: the paint dulls a little, grime builds up
## low on the body and runs down the sides in streaks, broad tarnish patches spread
## over the panels, dust settles on what faces up, inner creases fill with dark
## grime, the paint is chipped back to black along the outer edges with wind
## streaks trailing back from them (worst on what faces forward), and bare-metal
## chips and dark pits speckle it. `weather` { amount (0..1.5, all of it), grime,
## dust, rust, stripped (colours), edges (0..1.5, the edge wear alone), seed }.
static func _weather(root: Node3D, w: Dictionary, box: AABB) -> void:
	var amt := float(w.get("amount", 1.0))
	var edge_amt := float(w.get("edges", 1.0)) * amt
	var grime := Color(str(w.get("grime", "#2f251b")))
	var dust := Color(str(w.get("dust", "#b39468")))
	var rust := Color(str(w.get("rust", "#6e3d1e")))
	var stripped := Color(str(w.get("stripped", "#141312")))
	var shade := Color("#1b1510")
	var chip := Color("#8d8a84")
	var seed := int(w.get("seed", 7))
	var patches := _noise(seed, 0.7, 4)       # world-space, in metres
	var streaks := _noise(seed + 5, 1.0, 2)
	var breakup := _noise(seed + 9, 7.0, 3)
	var wind := _noise(seed + 13, 1.0, 2)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var img := mat.albedo_texture.get_image()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var size := img.get_size()
			var baked := _bake_place(mi, s, root, box, 1024)
			var place: Image = baked[0]
			var edges: Image = baked[1]
			place.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
			edges.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
			var speck := _noise_img(size, seed + 23, 0.09, 1)
			for y in size.y:
				for x in size.x:
					var c := img.get_pixel(x, y)
					if c.s > 0.35 and c.v > 0.3 and c.h > 0.5 and c.h < 0.72:
						continue                      # the glow stays clean
					var pl := place.get_pixel(x, y)  # rgb: where on the box (0..1), a: facing up (0 = not baked)
					if pl.a < 0.05:
						continue                      # a gutter between UV islands
					var ed := edges.get_pixel(x, y)  # r: outer edge, g: inner crease, b: near an edge, a: facing forward
					var wp := box.position + Vector3(pl.r, pl.g, pl.b) * box.size
					var h := pl.g
					var up := (pl.a - 0.1) / 0.9
					var pn := 0.5 + 0.5 * patches.get_noise_3dv(wp)
					var sn := 0.5 + 0.5 * streaks.get_noise_3d(wp.x * 9.0, wp.y * 0.6, wp.z * 9.0)
					var bn := 0.5 + 0.5 * breakup.get_noise_3dv(wp)
					var wn := 0.5 + 0.5 * wind.get_noise_3d(wp.x * 14.0, wp.y * 14.0, wp.z * 0.5)
					var k := speck.get_pixel(x, y).r
					var out := c.lerp(c * Color(0.9, 0.86, 0.8), 0.6 * amt)          # the paint has seen sun and sand
					var low := smoothstep(0.6, 0.05, h)
					out = out.lerp(grime, clampf(low * (0.45 + 0.55 * pn) * 0.9 * amt, 0.0, 0.92))
					var streak := smoothstep(0.58, 0.85, sn) * smoothstep(0.95, 0.35, h) * smoothstep(0.85, 0.3, up)
					out = out.lerp(grime, clampf(streak * 0.45 * amt, 0.0, 0.6))
					var tarnish := smoothstep(0.58, 0.78, pn) * (0.5 + 0.5 * low)
					out = out.lerp(rust, clampf(tarnish * 0.42 * amt, 0.0, 0.6))
					var settle := smoothstep(0.6, 0.95, up) * smoothstep(0.35, 0.7, 1.0 - pn)
					out = out.lerp(dust, clampf(settle * 0.45 * amt, 0.0, 0.6))
					out = out.lerp(shade, clampf(smoothstep(0.15, 0.6, ed.g) * (0.6 + 0.4 * pn) * 0.75 * edge_amt, 0.0, 0.8))
					var front := ed.a
					var chipped := smoothstep(0.4, 0.7, ed.r + (bn - 0.5) * 0.6 + 0.1 * front)
					var blown := smoothstep(0.1, 0.45, ed.b) * smoothstep(0.55, 0.82, wn) * (0.4 + 0.6 * front) * (0.6 + 0.4 * bn)
					out = out.lerp(stripped, clampf(maxf(chipped, blown * 0.85) * edge_amt, 0.0, 0.95))
					if k > 1.0 - 0.05 * amt:
						out = out.lerp(chip, 0.65)
					elif k < 0.04 * amt:
						out = out.lerp(grime.darkened(0.3), 0.55)
					out.a = c.a
					img.set_pixel(x, y, out)
			mat = mat.duplicate() as BaseMaterial3D
			mat.albedo_texture = ImageTexture.create_from_image(img)
			mi.mesh.surface_set_material(s, mat)


static func _noise(seed: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	return n


## Where each texel of a surface's UV map sits on the model, as two `res` square
## images the caller scales to the texture. The first: rgb its place in the box
## (0..1 on each axis), a how far it faces up (0.1 down to 1.0 up; 0 where no
## triangle covers it). The second, from how sharply the mesh folds at each corner
## (`_vertex_creases`), blended across each face: r near an outer edge, g near an
## inner crease, b near any edge (where wind streaks start), a how far it faces
## forward (-Z).
static func _bake_place(mi: MeshInstance3D, s: int, root: Node3D, box: AABB, res: int) -> Array:
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 0.0))
	var eimg := Image.create(res, res, false, Image.FORMAT_RGBA8)
	eimg.fill(Color(0, 0, 0, 0.5))
	var xf := _xf_to(mi, root)
	var a := mi.mesh.surface_get_arrays(s)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	if uvs.is_empty():
		return [img, eimg]
	if idx.is_empty():
		idx = PackedInt32Array(range(verts.size()))
	var tri_n := _tri_normals(verts, idx, xf)
	var crease := _vertex_creases(verts, idx, xf, tri_n)
	var inv_size := Vector3.ONE / box.size.max(Vector3.ONE * 0.001)
	for t in range(0, idx.size(), 3):
		var p := [xf * verts[idx[t]], xf * verts[idx[t + 1]], xf * verts[idx[t + 2]]]
		var q := [uvs[idx[t]] * res, uvs[idx[t + 1]] * res, uvs[idx[t + 2]] * res]
		var n: Vector3 = tri_n[t / 3]
		var up := 0.1 + 0.9 * (0.5 + 0.5 * n.y)
		var fwd := 0.5 - 0.5 * n.z
		var cv := [crease[idx[t]], crease[idx[t + 1]], crease[idx[t + 2]]]
		var lo: Vector2 = (q[0] as Vector2).min(q[1]).min(q[2]).floor()
		var hi: Vector2 = (q[0] as Vector2).max(q[1]).max(q[2]).ceil()
		var d := ((q[1] - q[0]) as Vector2).cross(q[2] - q[0])
		if absf(d) < 1e-9:
			continue
		for py in range(maxi(int(lo.y) - 1, 0), mini(int(hi.y) + 1, res)):
			for px in range(maxi(int(lo.x) - 1, 0), mini(int(hi.x) + 1, res)):
				var c := Vector2(px + 0.5, py + 0.5)
				var w1 := ((c - q[0]) as Vector2).cross(q[2] - q[0]) / d
				var w2 := ((q[1] - q[0]) as Vector2).cross(c - q[0]) / d
				var w0 := 1.0 - w1 - w2
				if w0 < -0.15 or w1 < -0.15 or w2 < -0.15:
					continue                      # a little past the edge, so seams fill
				var wp: Vector3 = (p[0] as Vector3) * w0 + (p[1] as Vector3) * w1 + (p[2] as Vector3) * w2
				var u := ((wp - box.position) * inv_size).clamp(Vector3.ZERO, Vector3.ONE)
				img.set_pixel(px, py, Color(u.x, u.y, u.z, up))
				var cr: Vector3 = (cv[0] as Vector3) * w0 + (cv[1] as Vector3) * w1 + (cv[2] as Vector3) * w2
				var outer := clampf(cr.x, 0.0, 1.0)
				var inner := clampf(cr.y, 0.0, 1.0)
				var near := clampf(cr.z, 0.0, 1.0)
				eimg.set_pixel(px, py, Color(outer, inner, near, fwd))
	return [img, eimg]


static func _tri_normals(verts: PackedVector3Array, idx: PackedInt32Array, xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for t in range(0, idx.size(), 3):
		var a := xf * verts[idx[t]]
		var n := (xf * verts[idx[t + 1]] - a).cross(xf * verts[idx[t + 2]] - a)
		out.append(n.normalized() if n.length() > 0.0 else Vector3.UP)
	return out


## For each vertex, Vector3(outer, inner, sharp): how sharply the faces round it
## fold (sharp: 0 for a flat or gently curved surface, 1 at a right-angled edge),
## and whether they fall away from it (an outer edge or corner) or rise round it
## (an inner crease). Vertices at one place are merged, so a UV seam is not an
## edge; Rodin's small triangle folds on curved panels stay under the threshold.
static func _vertex_creases(verts: PackedVector3Array, idx: PackedInt32Array, xf: Transform3D, tri_n: PackedVector3Array) -> PackedVector3Array:
	var slot := {}                                   # merged position -> slot
	var of := PackedInt32Array()
	of.resize(verts.size())
	for v in verts.size():
		var k := Vector3i((xf * verts[v] * 2000.0).round())
		if not slot.has(k):
			slot[k] = slot.size()
		of[v] = slot[k]
	var n_slots := slot.size()
	var avg := PackedVector3Array()
	avg.resize(n_slots)
	var pos := PackedVector3Array()
	pos.resize(n_slots)
	var faces := []
	faces.resize(n_slots)
	for i in n_slots:
		faces[i] = []
	for t in range(0, idx.size(), 3):
		var area := (xf * verts[idx[t + 1]] - xf * verts[idx[t]]).cross(xf * verts[idx[t + 2]] - xf * verts[idx[t]]).length()
		for i in 3:
			var sl := of[idx[t + i]]
			avg[sl] += tri_n[t / 3] * area
			pos[sl] = xf * verts[idx[t + i]]
			(faces[sl] as Array).append(t / 3)
	var per_slot := PackedVector3Array()
	per_slot.resize(n_slots)
	for sl in n_slots:
		var n := avg[sl].normalized() if avg[sl].length() > 0.0 else Vector3.UP
		var min_dot := 1.0
		var lean := 0.0
		var reach := 0.0
		for f: int in faces[sl]:
			min_dot = minf(min_dot, n.dot(tri_n[f]))
			var o := f * 3
			var cen := (xf * verts[idx[o]] + xf * verts[idx[o + 1]] + xf * verts[idx[o + 2]]) / 3.0
			lean += (cen - pos[sl]).dot(n)
			reach += (cen - pos[sl]).length()
		var sharp := smoothstep(0.09, 0.3, 1.0 - min_dot)
		var side := lean / maxf(reach, 0.0001)        # < 0: the faces fall away (outer)
		per_slot[sl] = Vector3(sharp * smoothstep(0.0, -0.12, side), sharp * smoothstep(0.0, 0.12, side), sharp)
	var out := PackedVector3Array()
	out.resize(verts.size())
	for v in verts.size():
		out[v] = per_slot[of[v]]
	return out


static func _noise_img(size: Vector2i, seed: int, freq: float, octaves: int) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	return n.get_image(size.x, size.y, false, false, true)


## Issue #628: `cut_below` (metres above the model's bottom) drops every triangle
## that dips under that height, for a base Rodin added that the game doesn't want
## (the cargo sled's display slab). The hull above is hollow, so a thin dark-iron
## plate just above the cut closes it off: `cut_plate` [width, length] in metres,
## centred under the hull (default: the bounds of what is left just above the cut,
## which take in anything that sticks out there).
static func _cut(root: Node3D, cut_y: float, plate_size: Array) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xf := _xf_to(mi, root)
		var src := mi.mesh
		var mesh := ArrayMesh.new()
		for s in src.get_surface_count():
			var arrays := src.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx = PackedInt32Array(range(verts.size()))
			var keep := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var a := xf * verts[idx[t]]
				var b := xf * verts[idx[t + 1]]
				var d := xf * verts[idx[t + 2]]
				if minf(a.y, minf(b.y, d.y)) < cut_y:
					continue
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
				for p in [a, b, d]:
					if p.y < cut_y + 0.35:
						lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
						hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
			var out := _compact(arrays, keep)
			if out.is_empty():
				continue
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
			mesh.surface_set_material(mesh.get_surface_count() - 1, src.surface_get_material(s))
		mi.mesh = mesh
	if lo.x == INF:
		return
	var plate := MeshInstance3D.new()
	plate.name = "Underplate"
	var bm := BoxMesh.new()
	bm.size = Vector3(hi.x - lo.x - 0.08, 0.06, hi.y - lo.y - 0.08)
	if plate_size.size() >= 2:
		bm.size = Vector3(float(plate_size[0]), 0.06, float(plate_size[1]))
	plate.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#2e2b27")
	m.metallic = 0.5
	m.roughness = 0.75
	bm.material = m
	plate.position = Vector3(0.0 if plate_size.size() >= 2 else (lo.x + hi.x) * 0.5, cut_y + 0.03, (lo.y + hi.y) * 0.5)
	root.add_child(plate)


## The surface arrays cut down to the vertices `keep` uses, reindexed.
static func _compact(arrays: Array, keep: PackedInt32Array) -> Array:
	if keep.is_empty():
		return []
	var remap := {}
	var order := PackedInt32Array()
	var idx := PackedInt32Array()
	for i in keep:
		if not remap.has(i):
			remap[i] = order.size()
			order.append(i)
		idx.append(remap[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in Mesh.ARRAY_MAX:
		var a = arrays[k]
		if a == null or k == Mesh.ARRAY_INDEX:
			continue
		if k == Mesh.ARRAY_TANGENT:
			var t := PackedFloat32Array()
			for i in order:
				t.append_array([a[i * 4], a[i * 4 + 1], a[i * 4 + 2], a[i * 4 + 3]])
			out[k] = t
		elif a is PackedVector3Array or a is PackedVector2Array or a is PackedColorArray:
			var b = a.duplicate()
			b.resize(order.size())
			for j in order.size():
				b[j] = a[order[j]]
			out[k] = b
	out[Mesh.ARRAY_INDEX] = idx
	return out


static func _xf_to(n: Node3D, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != top:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


static func _own(n: Node, owner: Node) -> void:
	for ch in n.get_children():
		ch.owner = owner
		_own(ch, owner)


static func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != n:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b: AABB = xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
