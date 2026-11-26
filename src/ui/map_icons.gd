extends RefCounted
## The F11 Map page's icons: small silhouettes (content/look/map_icons.json) that
## say what a place is, in its role's colour with a dark edge. Each icon is
## triangulated once a session (its pieces, their edges grown by Geometry2D, and
## its cut-outs) into unit triangles; drawing one is a transform of those and an
## append to a batch, and the whole batch goes to the renderer in one
## canvas_item_add_triangle_array call (a draw_colored_polygon is ~0.3 ms here).
##
##   var b := MapIcons.Batch.new()
##   MapIcons.add(b, "mug", at, 9.0, col)
##   ...
##   b.flush(self)
##
## Preloaded, not a class_name (headless runs only learn new class names after an
## import).

const PATH := "res://content/look/map_icons.json"
const EDGE := Color(0, 0, 0, 0.85)
const ARC_SEGS := 14                    ## a full circle's sides (a half has half)

static var _data: Dictionary = {}
static var _icons: Dictionary = {}      ## name -> { edge, fill, cut: PackedVector2Array of unit triangles }


## Triangles and their colours, sent in one call.
class Batch:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()

	## Append triangles (`tris`, already on screen) in one colour.
	func tris(t: PackedVector2Array, col: Color) -> void:
		if t.is_empty():
			return
		var n := pts.size()
		pts.append_array(t)
		cols.resize(n + t.size())
		for i in range(n, n + t.size()):
			cols[i] = col

	## Append triangles with their own colours.
	func tris_colored(t: PackedVector2Array, c: PackedColorArray) -> void:
		pts.append_array(t)
		cols.append_array(c)

	func is_empty() -> bool:
		return pts.is_empty()

	## Draw everything on `ci` (in the order added) and start again.
	func flush(ci: CanvasItem) -> void:
		if pts.size() >= 3:
			RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(), pts, cols)
		pts = PackedVector2Array()
		cols = PackedColorArray()


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_data = d if d is Dictionary else { "icons": {} }
	return _data


static func has(name: String) -> bool:
	return data().get("icons", {}).has(name)


static func names() -> Array:
	return data().get("icons", {}).keys()


## Add icon `name` at `at`, `r` pixels from its middle to the edge of its box, in
## `col`. False when there is no such icon.
static func add(b: Batch, name: String, at: Vector2, r: float, col: Color, edge := EDGE) -> bool:
	var ic := _icon(name)
	if ic.is_empty():
		return false
	var xf := Transform2D(0.0, Vector2(r, r), 0.0, at)
	b.tris(xf * (ic.edge as PackedVector2Array), edge)
	b.tris(xf * (ic.fill as PackedVector2Array), col)
	b.tris(xf * (ic.cut as PackedVector2Array), edge)
	return true


## One icon straight onto `ci` (the legend: a few a paint).
static func draw(ci: CanvasItem, name: String, at: Vector2, r: float, col: Color) -> bool:
	var b := Batch.new()
	if not add(b, name, at, r, col):
		return false
	b.flush(ci)
	return true


static func _icon(name: String) -> Dictionary:
	if _icons.has(name):
		return _icons[name]
	var pieces = data().get("icons", {}).get(name, null)
	if not (pieces is Array):
		return {}
	var grow := float(data().get("edge", 0.16))
	var edge := PackedVector2Array()
	var fill := PackedVector2Array()
	var cut := PackedVector2Array()
	for p in pieces:
		var poly := _piece(p)
		if poly.size() < 3:
			continue
		if bool(p.get("cut", false)):
			cut.append_array(_tris(poly))
			continue
		fill.append_array(_tris(poly))
		for g in Geometry2D.offset_polygon(poly, grow, Geometry2D.JOIN_ROUND):
			edge.append_array(_tris(g))
	_icons[name] = { "edge": edge, "fill": fill, "cut": cut }
	return _icons[name]


## A piece's outline in unit space.
static func _piece(p: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	if p.has("poly"):
		for q in p.poly:
			out.append(Vector2(float(q[0]), float(q[1])))
	elif p.has("rect"):
		var r: Array = p.rect
		out = PackedVector2Array([Vector2(r[0], r[1]), Vector2(r[2], r[1]), Vector2(r[2], r[3]), Vector2(r[0], r[3])])
	elif p.has("circle"):
		var c: Array = p.circle
		for k in ARC_SEGS:
			var a := TAU * k / ARC_SEGS
			out.append(Vector2(float(c[0]), float(c[1])) + Vector2(cos(a), sin(a)) * float(c[2]))
	elif p.has("semi"):
		var c: Array = p.semi
		var flip := -1.0 if bool(p.get("flip", false)) else 1.0
		var half := ARC_SEGS / 2
		for k in half + 1:
			var a := PI + PI * k / half
			out.append(Vector2(float(c[0]), float(c[1])) + Vector2(cos(a), sin(a) * flip) * float(c[2]))
	if p.has("rot") and out.size() > 0:
		out = Transform2D(deg_to_rad(float(p.rot)), Vector2.ZERO) * out
	return out


## A polygon as a flat list of triangle corners.
static func _tris(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		idx = Geometry2D.triangulate_polygon(_reversed(poly))
	for i in idx:
		out.append(poly[i])
	return out


static func _reversed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.reverse()
	return out
