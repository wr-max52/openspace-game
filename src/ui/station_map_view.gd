class_name StationMapView
extends Control
## The F11 Map page's view of a space station: the station seen from the side
## (its own frame's +z toward you, the bay on the left), drawn from its data
## (StationHull: the towers' floors, the tunnels between them, the landing bay,
## the elevator shafts), stretched up (`stretch`) so a 14 m floor is something you
## can click. Nothing is rendered: a few dozen rects and lines, drawn only when
## something changes.
##
## Over it, the places you can set a waypoint on (GlobeMap.orbital_pins: the bay
## and every floor of every tower) are marked with corner brackets and named
## inside. Hover lights a place; a click sets the waypoint there (`place_clicked`).
## You show when you are aboard; the waypoint's place flashes.
## Colours: content/look/map.json "station_view".

signal place_clicked(pin: Dictionary)

const PAD := Vector2(24.0, 30.0)        ## px round the station

var hull: StationHull                   ## the station shown (null = nothing to draw)
var pins: Array = []                    ## GlobeMap.orbital_pins
var selected := ""                      ## the waypoint's pin id ("" = none)
var player := Vector3.INF               ## you, in the station's frame (INF = not aboard)
var hover := -1

var _bounds := Rect2()                  ## the station's (x, y) extent, metres


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(240, 180)


func _cfg() -> Dictionary:
	return GlobeMap.look().get("station_view", {})


func stretch() -> float:
	return float(_cfg().get("stretch", 1.6))


## Show station `h` (StationHull) and its places.
func show_station(h: StationHull, places: Array) -> void:
	hull = h
	pins = places
	_bounds = Rect2()
	if hull == null:
		return
	var first := true
	for p in pins:
		var r: Rect2 = p.rect
		_bounds = r if first else _bounds.merge(r)
		first = false
	for tn in hull.tunnels:
		var a: Vector3 = (tn.xf as Transform3D).origin
		_bounds = _bounds.expand(Vector2(a.x, a.y))
	_bounds = _bounds.grow_individual(0.0, 0.0, 0.0, hull.plate * 2.0)
	queue_redraw()


func _process(_dt: float) -> void:
	if is_visible_in_tree() and (selected != "" or player != Vector3.INF):
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover != -1:
		hover = -1
		queue_redraw()


# ------------------------------------------------------------------ placing

## Pixels per metre across the station, fitted to the control.
func scale_px() -> float:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return 1.0
	return maxf(0.01, minf((size.x - PAD.x * 2.0) / _bounds.size.x, (size.y - PAD.y * 2.0) / (_bounds.size.y * stretch())))


## Screen point of (x, y) in the station's frame: +x to the right, up up.
func to_px(x: float, y: float) -> Vector2:
	var s := scale_px()
	var c := _bounds.get_center()
	return size * 0.5 + Vector2(x - c.x, -(y - c.y) * stretch()) * s


## An (x, y) rect on screen.
func rect_px(r: Rect2) -> Rect2:
	var a := to_px(r.position.x, r.position.y)
	var b := to_px(r.end.x, r.end.y)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


## The pin index under screen point `p`, or -1 (the smallest rect wins: a floor
## over the bay's wide box).
func place_at(p: Vector2) -> int:
	var best := -1
	var best_a := INF
	for i in pins.size():
		var r := rect_px(pins[i].rect)
		if r.grow(3.0).has_point(p) and r.get_area() < best_a:
			best_a = r.get_area()
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := place_at((event as InputEventMouseMotion).position)
		if h != hover:
			hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var i := place_at(mb.position)
			if i >= 0:
				place_clicked.emit(pins[i])
		accept_event()


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var lk := _cfg()
	draw_rect(Rect2(Vector2.ZERO, size), Color(str(lk.get("space", "#07080c"))))
	if hull == null:
		return
	var ink := GlobeView.ink_color()
	var glass := Color(str(lk.get("glass", "#5fa8d8")))
	_draw_shafts(Color(glass, 0.55))
	_draw_tunnels(Color(str(lk.get("tunnel", "#4a5560"))), glass)
	_draw_bay(lk, ink)
	_draw_floors(lk, ink, glass)
	_draw_places(ink)
	if player != Vector3.INF:
		var t := GlobeView.pulse()
		var at := to_px(player.x, player.y + 1.0)
		var you := Color(str(GlobeMap.look().get("player", {}).get("color", "#4dff88")))
		draw_circle(at, 10.0 + 3.0 * t, Color(you, 0.15 + 0.15 * t))
		GlobeView.draw_shape(self, at, "you", you, 6.0)


## Each tower's elevator: its glass tube up the middle, bottom floor to top ceiling.
func _draw_shafts(col: Color) -> void:
	for t in hull.towers:
		var fl: Array = t.floors
		if fl.is_empty():
			continue
		var c: Vector2 = t.c
		var y0 := float(fl[0].y) - hull.plate
		var y1 := float(fl[fl.size() - 1].y) + hull.floor_h + hull.plate
		var a := to_px(c.x - hull.shaft_r, y1)
		var b := to_px(c.x + hull.shaft_r, y0)
		draw_rect(Rect2(a, b - a), Color(col, col.a * 0.25))
		draw_line(Vector2(a.x, a.y), Vector2(a.x, b.y), col, 1.0, true)
		draw_line(Vector2(b.x, a.y), Vector2(b.x, b.y), col, 1.0, true)


## The glass-walled tunnels between the towers and out to the bay.
func _draw_tunnels(col: Color, glass: Color) -> void:
	for tn in hull.tunnels:
		var xf: Transform3D = tn.xf
		var x0 := xf.origin.x
		var x1 := x0 + xf.basis.x.x * float(tn.length)
		var y := float(tn.y)
		var r := rect_px(Rect2(minf(x0, x1), y, absf(x1 - x0), hull.tunnel_h))
		draw_rect(r, Color(col, 0.55))
		draw_line(r.position, Vector2(r.end.x, r.position.y), Color(glass, 0.7), 1.0, true)
		draw_line(Vector2(r.position.x, r.end.y), r.end, Color(col.lightened(0.3), 0.9), 1.5, true)


## The covered landing bay: its deck, its curved roof, and the shield across its
## mouth on the side facing away from its tower.
func _draw_bay(lk: Dictionary, ink: Color) -> void:
	var bay: Dictionary = hull.bay
	if bay.is_empty():
		return
	var bc: Vector2 = bay.c
	var br := float(bay.r)
	var h := float(bay.height)
	var col := Color(str(lk.get("bay", "#8a96a2")))
	var deck := rect_px(Rect2(bc.x - br, -hull.plate, br * 2.0, hull.plate))
	draw_rect(deck, col)
	# The roof: a flattened arc over the deck, bay.height at its middle.
	var roof := PackedVector2Array()
	for k in 25:
		var u := -1.0 + 2.0 * k / 24.0
		roof.append(to_px(bc.x + u * br, h * sqrt(maxf(0.0, 1.0 - u * u * 0.75))))
	var inside := roof.duplicate()
	inside.append(to_px(bc.x + br, 0.0))
	inside.append(to_px(bc.x - br, 0.0))
	draw_colored_polygon(inside, Color(col, 0.08))
	draw_polyline(roof, Color(ink, 0.85), 1.5, true)
	# The walls: solid on the tower's side, the shield (dashed glow) across the mouth.
	var out := -1.0 if (bay.dir as Vector2).x > 0.0 else 1.0
	var mouth_x := bc.x - out * br
	var back_x := bc.x + out * br
	draw_line(to_px(back_x, 0.0), roof[24 if out > 0.0 else 0], Color(ink, 0.85), 1.5, true)
	var shield := Color(str(lk.get("shield", "#7cc4ff")))
	draw_dashed_line(to_px(mouth_x, 0.0), roof[0 if out > 0.0 else 24], Color(shield, 0.9), 2.0, 5.0, true)
	# The pads on its deck.
	for p in hull.pads():
		var at: Vector3 = p.at
		var pr := float(p.radius) * 0.8
		var a := to_px(at.x - pr, 0.0)
		var b := to_px(at.x + pr, 0.0)
		draw_line(a + Vector2(0, -2), b + Vector2(0, -2), Color(str(lk.get("pad", "#e8c050")), 0.8), 2.0)


## Every floor: its plate, its glass walls, its ceiling, and the room between
## lightly filled; the top one with a beacon on its roof.
func _draw_floors(lk: Dictionary, ink: Color, glass: Color) -> void:
	var deck := Color(str(lk.get("floor", "#9a8f82")))
	var room := Color(str(lk.get("room", "#2a3038")))
	for t in hull.towers:
		var c: Vector2 = t.c
		var fl: Array = t.floors
		for i in fl.size():
			var f: Dictionary = fl[i]
			var r := float(f.r)
			var y := float(f.y)
			var inner := rect_px(Rect2(c.x - r, y, r * 2.0, hull.floor_h))
			draw_rect(inner, Color(room, 0.55))
			draw_rect(rect_px(Rect2(c.x - r, y - hull.plate, r * 2.0, hull.plate)), deck)
			draw_rect(rect_px(Rect2(c.x - r, y + hull.floor_h, r * 2.0, hull.plate)), Color(ink, 0.5))
			draw_line(Vector2(inner.position.x, inner.position.y), Vector2(inner.position.x, inner.end.y), Color(glass, 0.8), 1.5, true)
			draw_line(Vector2(inner.end.x, inner.position.y), inner.end, Color(glass, 0.8), 1.5, true)
			# The gap round the shaft: a shield you drop through, not floor.
			var gap := rect_px(Rect2(c.x - hull.gap_r, y - hull.plate, hull.gap_r * 2.0, hull.plate))
			draw_rect(gap, Color(str(lk.get("shield", "#7cc4ff")), 0.6))
			if i == fl.size() - 1:
				var top := to_px(c.x, y + hull.floor_h + hull.plate)
				draw_line(top, top + Vector2(0, -8), Color(ink, 0.7), 1.0, true)
				draw_circle(top + Vector2(0, -9), 2.0, Color(str(lk.get("beacon", "#ff3030"))))


## The places: corner brackets, the waypoint's flashing, and each one's name
## inside it (above the bay's roof for the bay).
func _draw_places(ink: Color) -> void:
	var goal := Color(str(GlobeMap.look().get("goal", {}).get("color", "#ffd84a")))
	var t := GlobeView.pulse()
	var font := get_theme_default_font()
	for i in pins.size():
		var pin: Dictionary = pins[i]
		var r := rect_px(pin.rect)
		var hot := i == hover
		var on := str(pin.id) == selected
		var col := goal.lerp(Color.WHITE, t * 0.4) if on else (Color.WHITE if hot else Color(ink, 0.8))
		if on or hot:
			draw_rect(r, Color(col, (0.12 + 0.12 * t) if on else 0.1))
		if on or hot:
			CruiserMapView.brackets(self, r, col, 2.0)
		if font == null:
			continue
		var fs := clampi(int(r.size.y * 0.32), 10, 14)
		var text := str(pin.label).to_upper()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := r.get_center().x - w * 0.5
		var y := r.get_center().y + fs * 0.35
		if str(pin.get("tower", "")) == "":
			y = r.position.y - 6.0              # the bay: over its roof
		var tag := Rect2(x - 4.0, y - fs - 1.0, w + 8.0, fs + 5.0)
		draw_rect(tag, Color(0, 0, 0, 0.55 if not (on or hot) else 0.75))
		if on or hot:
			draw_rect(tag, Color(col, 0.6), false, 1.0)
		draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
