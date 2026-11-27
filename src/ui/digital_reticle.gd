extends Control
## The sniper rifle's scope reticle, drawn on screen (its 3D scope has none:
## hand_weapons scope "digital"). Aimed in, the screen centre is the scope's centre
## line, so this lands where the scope's own reticle would. A display, not etched
## glass: dashed arms in hard pixels with range ticks, corner brackets round a
## centre dot, and readouts for the range to the target and the zoom. No logic:
## PlayerWeapons sets the numbers each frame.

var color := Color("#ff3a1e")
var reach := 120.0                  ## pixels from the centre to the end of an arm
var meters := -1.0                  ## range to what is under the centre; < 0 = nothing
var mag := 2.5
## The seeker launcher's panel sight (scope "panel"): its glass's half size on
## screen, pixels (0 = the sniper's round scope, no panel drawn), and the panel's
## line colour. The glass itself is the 3D panel's; this adds a display on it:
## scan lines, an edge frame with corner marks, rulers down the sides and along
## the bottom, a few status strips along the top.
var panel_half := 0.0
var panel_color := Color("#7cc4ff")
var _font: SystemFont


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE


## An axis-aligned bar snapped to whole pixels, with a soft glow round it.
func _bar(r: Rect2) -> void:
	r = Rect2(r.position.round(), r.size.round().max(Vector2.ONE))
	draw_rect(r.grow(1.5), Color(color, 0.18))
	draw_rect(r, color)


## A bar along axis `d` (a unit axis vector) from `from` to `from + length` past
## `at`, `t` thick across it.
func _segment(at: Vector2, d: Vector2, from: float, length: float, t: float) -> void:
	var a := at + d * from
	var b := at + d * (from + length)
	var lo := a.min(b)
	if absf(d.x) > 0.5:
		_bar(Rect2(lo.x, lo.y - t * 0.5, absf(b.x - a.x), t))
	else:
		_bar(Rect2(lo.x - t * 0.5, lo.y, t, absf(b.y - a.y)))


## The panel's display round the reticle (panel_half > 0).
func _draw_panel(mid: Vector2) -> void:
	var h := panel_half
	var box := Rect2(mid - Vector2(h, h), Vector2(h, h) * 2.0)
	var c := panel_color
	draw_rect(box, Color(c, 0.05))
	# Scan lines across the glass.
	var y := box.position.y + 2.0
	while y < box.end.y:
		draw_line(Vector2(box.position.x, round(y)), Vector2(box.end.x, round(y)), Color(c, 0.06), 1.0)
		y += 4.0
	# The display's edge, inset from the frame, and corner marks inside it.
	var inset := box.grow(-h * 0.04)
	draw_rect(inset, Color(c, 0.35), false, 1.0)
	var arm := h * 0.16
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var k := mid + Vector2(sx, sy) * (h * 0.9)
			draw_line(k, k - Vector2(sx * arm, 0.0), Color(c, 0.9), 2.0)
			draw_line(k, k - Vector2(0.0, sy * arm), Color(c, 0.9), 2.0)
	# Rulers: ticks down both sides and along the bottom, every tenth of the panel.
	for i in range(-8, 9):
		var f := float(i) / 10.0
		var long := 0.07 if i % 4 == 0 else 0.035
		for sx in [-1.0, 1.0]:
			var x: float = mid.x + sx * h * 0.84
			var ty := mid.y + f * h
			draw_line(Vector2(x, ty), Vector2(x - sx * h * long, ty), Color(c, 0.55), 1.0)
		var bx := mid.x + f * h
		var by := mid.y + h * 0.84
		draw_line(Vector2(bx, by), Vector2(bx, by - h * long), Color(c, 0.55), 1.0)
	# Status strips along the top: a label, then a row of cells, then a short bar.
	var size_px := int(clampf(h * 0.075, 11.0, 22.0))
	var top := mid.y - h * 0.8
	draw_string(_font, Vector2(mid.x - h * 0.8, top + size_px), "SKR", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(c, 0.9))
	for i in 6:
		var cell := Rect2(mid.x - h * 0.45 + i * h * 0.09, top + 2.0, h * 0.065, size_px * 0.7)
		draw_rect(cell, Color(c, 0.75 if i < 4 else 0.22))
	draw_rect(Rect2(mid.x + h * 0.25, top + size_px * 0.3, h * 0.5, 2.0), Color(c, 0.5))
	draw_rect(Rect2(mid.x + h * 0.25, top + size_px * 0.3 + 6.0, h * 0.3, 2.0), Color(c, 0.5))


func _draw() -> void:
	var mid := (get_viewport_rect().size * 0.5).round()
	if panel_half > 0.0:
		_draw_panel(mid)
	var t := maxf(2.0, round(reach / 70.0))         # line thickness
	var gap := reach * 0.16
	var dash := maxf(4.0, reach * 0.07)
	# Arms: dashes from the gap out to the reach, a tick across every quarter of it.
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var along := gap
		while along < reach:
			_segment(mid, d, along, minf(dash, reach - along), t)
			along += dash * 1.6
		for k in range(1, 5):
			var p: Vector2 = mid + d * lerpf(gap, reach, k / 4.0)
			var tick := reach * (0.07 if k % 2 == 0 else 0.04)
			_segment(p, Vector2(d.y, d.x), -tick, tick * 2.0, t)
	# Corner brackets round the centre and the dot in it.
	var bx := gap * 0.7
	var arm := gap * 0.32
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := mid + Vector2(sx, sy) * bx
			_bar(Rect2(Vector2(minf(c.x, c.x - sx * arm), c.y - t * 0.5), Vector2(arm, t)))
			_bar(Rect2(Vector2(c.x - t * 0.5, minf(c.y, c.y - sy * arm)), Vector2(t, arm)))
	_bar(Rect2(mid - Vector2(t, t), Vector2(t, t) * 2.0))
	# Readouts: the range under the lower right bracket, the zoom under the left.
	var size_px := int(clampf(reach * 0.13, 14.0, 34.0))
	var range_text := "---- M" if meters < 0.0 else "%04d M" % int(round(meters))
	var at := mid + Vector2(bx + arm * 0.2, bx + size_px * 1.4)
	draw_string_outline(_font, at, range_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, Color(0, 0, 0, 0.55))
	draw_string(_font, at, range_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
	var zoom_text := "%.1fX" % mag
	var w := _font.get_string_size(zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var zat := mid + Vector2(-bx - arm * 0.2 - w, bx + size_px * 1.4)
	draw_string_outline(_font, zat, zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, Color(0, 0, 0, 0.55))
	draw_string(_font, zat, zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(color, 0.8))
