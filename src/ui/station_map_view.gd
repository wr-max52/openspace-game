class_name StationMapView
extends Control
## The F11 Map page's view of a space station, in two parts.
##
## The side view: the station seen from the side (its own frame's +z toward you,
## the bay on the left), drawn from its data (StationHull: the towers' floors, the
## tunnels between them, the landing bay, the elevator shafts), stretched up
## (`stretch`) so a 14 m floor is something you can click. Each floor is named,
## with a line under it saying who holds its rooms (GlobeMap.orbital_pins
## `summary`), and a band along its deck in the owners' colours, room by room, for
## the rooms on the side facing you. A click on the bay sets the waypoint there; a
## click on a floor opens its plan.
##
## A floor's plan (`level`): the floor from above, its rooms round the outside in
## the colour of whoever holds them (GlobeMap.room_pins: named, the owner under the
## name), the walkway, the shield over the gap, the elevator and its bridges, where
## each tunnel leaves and where it goes, and on an open floor its stall rings and
## named stalls. A click on a room sets the waypoint in it; on the walkway, on the
## floor. "< All floors" goes back.
##
## You show when you are aboard (on the plan, when you are on that floor); the
## waypoint's place flashes. Nothing is rendered: rects, lines, and the plan's
## rooms batched into one triangle list, drawn only when something changes.
## Colours: content/look/map.json "station_view".

signal place_clicked(pin: Dictionary)

const PAD := Vector2(24.0, 30.0)        ## px round the station
const HEAD := 46.0                      ## px over a plan for its name and line
const ARC_SEGS := 10                    ## segments along a room's outer wall on the plan

var hull: StationHull                   ## the station shown (null = nothing to draw)
var pins: Array = []                    ## GlobeMap.orbital_pins
var selected := ""                      ## the waypoint's pin id ("" = none)
var player := Vector3.INF               ## you, in the station's frame (INF = not aboard)
var hover := -1                         ## side view: the pin under the mouse
var level := ""                         ## the floor's pin id whose plan shows ("" = the side view)
var hover_room := ""                    ## plan: the room's (or the floor's, on the walkway) pin id under the mouse

var _bounds := Rect2()                  ## the station's (x, y) extent, metres
var _back: Button


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(240, 180)
	_back = Button.new()
	_back.name = "AllFloors"
	_back.text = GlobeMap.line("station_back")
	_back.focus_mode = Control.FOCUS_NONE
	_back.position = Vector2(8, 8)
	_back.visible = false
	_back.pressed.connect(func(): open_level(""))
	add_child(_back)


func _cfg() -> Dictionary:
	return GlobeMap.look().get("station_view", {})


func stretch() -> float:
	return float(_cfg().get("stretch", 1.6))


## Show station `h` (StationHull) and its places. A floor's plan stays open while
## that floor is still one of them.
func show_station(h: StationHull, places: Array) -> void:
	hull = h
	pins = places
	_bounds = Rect2()
	if level != "" and _pin(level).is_empty():
		open_level("")
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


## Open floor pin `id`'s plan ("" = back to the side view).
func open_level(id: String) -> void:
	level = id
	hover = -1
	hover_room = ""
	_back.visible = level != ""
	queue_redraw()


func _pin(id: String) -> Dictionary:
	for p in pins:
		if str(p.id) == id:
			return p
	return {}


func _process(_dt: float) -> void:
	if is_visible_in_tree() and (selected != "" or player != Vector3.INF):
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and (hover != -1 or hover_room != ""):
		hover = -1
		hover_room = ""
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


## The plan's middle on screen and its pixels per metre, for floor pin `f`.
func plan_frame(f: Dictionary) -> Array:
	var t := hull.tower(str(f.tower))
	var r := float(t.floors[int(f.floor)].r) if not t.is_empty() else 50.0
	var c := Vector2(size.x * 0.5, HEAD + (size.y - HEAD) * 0.5)
	var s := maxf(0.01, (minf(size.x, size.y - HEAD) * 0.5 - 30.0) / r)
	return [c, s]


## Screen point of station-frame (x, z) on floor `f`'s plan: +x right, +z down.
func plan_px(f: Dictionary, xz: Vector2) -> Vector2:
	var fr := plan_frame(f)
	var t := hull.tower(str(f.tower))
	return (fr[0] as Vector2) + (xz - (t.c as Vector2)) * float(fr[1])


## On floor `f`'s plan, the room pin (or the floor pin itself, on the walkway or
## over the gap) under screen point `p`, or {}.
func plan_place_at(f: Dictionary, p: Vector2) -> Dictionary:
	var fr := plan_frame(f)
	var v := (p - (fr[0] as Vector2)) / float(fr[1])
	var d := v.length()
	var outer := float(hull.tower(str(f.tower)).floors[int(f.floor)].r)
	if d > outer:
		return {}
	var a := v.angle()
	for rm in f.get("rooms", []):
		if d >= float(rm.r0) - 0.6 and absf(wrapf(a - float(rm.a), -PI, PI)) <= float(rm.half):
			return rm
	return f if d < hull.gap_r + hull.walk + 0.4 or (f.get("rooms", []) as Array).is_empty() else {}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var at := (event as InputEventMouseMotion).position
		if level != "":
			var f := _pin(level)
			var h := str(plan_place_at(f, at).get("id", "")) if not f.is_empty() else ""
			if h != hover_room:
				hover_room = h
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
				queue_redraw()
		else:
			var h := place_at(at)
			if h != hover:
				hover = h
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
				queue_redraw()
		accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if level != "":
				var f := _pin(level)
				var hit := plan_place_at(f, mb.position) if not f.is_empty() else {}
				if not hit.is_empty():
					place_clicked.emit(hit)
			else:
				var i := place_at(mb.position)
				if i >= 0:
					if str(pins[i].get("tower", "")) != "":
						open_level(str(pins[i].id))       # a floor: its plan
					else:
						place_clicked.emit(pins[i])       # the bay: the waypoint
		accept_event()


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var lk := _cfg()
	draw_rect(Rect2(Vector2.ZERO, size), Color(str(lk.get("space", "#07080c"))))
	if hull == null:
		return
	var f := _pin(level) if level != "" else {}
	if not f.is_empty():
		_draw_level(f, lk)
		return
	var ink := GlobeView.ink_color()
	var glass := Color(str(lk.get("glass", "#5fa8d8")))
	_draw_shafts(Color(glass, 0.55))
	_draw_tunnels(Color(str(lk.get("tunnel", "#4a5560"))), glass)
	_draw_bay(lk, ink)
	_draw_floors(lk, ink, glass)
	_draw_owner_bands(lk)
	_draw_places(ink)
	if player != Vector3.INF:
		_draw_you(to_px(player.x, player.y + 1.0))


func _draw_you(at: Vector2) -> void:
	var t := GlobeView.pulse()
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


## Along each floor's deck, the rooms on the side facing you, each a stretch of
## band in its owner's colour where it really is; an open floor's whole width in
## its owner's colour.
func _draw_owner_bands(lk: Dictionary) -> void:
	var band_h := 2.4
	for p in pins:
		var t := hull.tower(str(p.get("tower", "")))
		if t.is_empty() or not p.has("floor"):
			continue
		var f: Dictionary = t.floors[int(p.floor)]
		var c: Vector2 = t.c
		var r := float(f.r)
		var y := float(f.y)
		var rooms: Array = p.get("rooms", [])
		if rooms.is_empty():
			if str(p.get("owner", "")) != "":
				draw_rect(rect_px(Rect2(c.x - r, y, r * 2.0, band_h)), Color(GlobeMap.owner_color(str(p.owner)), 0.55))
			continue
		for rm in rooms:
			# The near half of the ring faces you (+z): angles 0..PI.
			var a0 := clampf(float(rm.a) - float(rm.half), 0.0, PI)
			var a1 := clampf(float(rm.a) + float(rm.half), 0.0, PI)
			if a1 - a0 < 0.01:
				continue
			var x0 := c.x + r * cos(a1)
			var x1 := c.x + r * cos(a0)
			var b := rect_px(Rect2(x0, y, x1 - x0, band_h))
			draw_rect(b.grow_individual(-0.5, 0, -0.5, 0), Color(GlobeMap.owner_color(str(rm.owner)), 0.85))


## The places: corner brackets, the waypoint's flashing, and each one's name and
## line inside it (over the bay's roof for the bay).
func _draw_places(ink: Color) -> void:
	var goal := Color(str(GlobeMap.look().get("goal", {}).get("color", "#ffd84a")))
	var t := GlobeView.pulse()
	var font := get_theme_default_font()
	for i in pins.size():
		var pin: Dictionary = pins[i]
		var r := rect_px(pin.rect)
		var hot := i == hover
		# The waypoint in one of this floor's rooms flashes the floor too.
		var on := str(pin.id) == selected or (selected.begins_with(str(pin.id) + ".") and pin.has("floor"))
		var col := goal.lerp(Color.WHITE, t * 0.4) if on else (Color.WHITE if hot else Color(ink, 0.8))
		if on or hot:
			draw_rect(r, Color(col, (0.12 + 0.12 * t) if on else 0.1))
			CruiserMapView.brackets(self, r, col, 2.0)
		if font == null:
			continue
		var fs := clampi(int(r.size.y * 0.28), 10, 14)
		var text := str(pin.label).to_upper()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := r.get_center().x - w * 0.5
		var sub := str(pin.get("summary", ""))
		var sfs := maxi(fs - 3, 9)
		var y := r.get_center().y + fs * 0.35 - (sfs * 0.6 if sub != "" else 0.0)
		if str(pin.get("tower", "")) == "":
			y = r.position.y - 6.0              # the bay: over its roof
		var tag := Rect2(x - 4.0, y - fs - 1.0, w + 8.0, fs + 5.0)
		draw_rect(tag, Color(0, 0, 0, 0.55 if not (on or hot) else 0.75))
		if on or hot:
			draw_rect(tag, Color(col, 0.6), false, 1.0)
		draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if sub != "":
			var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
			if sw <= r.size.x - 8.0:
				var sp := Vector2(r.get_center().x - sw * 0.5, y + sfs + 4.0)
				draw_string_outline(font, sp, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, 3, Color(0, 0, 0, 0.8))
				draw_string(font, sp, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color(0.92, 0.9, 0.84, 0.9))


# ------------------------------------------------------------------ a floor's plan

## Floor pin `f` from above: its name and line over it, its rooms in their owners'
## colours, the walkway, the gap and the elevator, the tunnels' exits, an open
## floor's stalls, the waypoint and you.
func _draw_level(f: Dictionary, lk: Dictionary) -> void:
	var t := hull.tower(str(f.tower))
	if t.is_empty():
		return
	var i := int(f.floor)
	var fl: Dictionary = t.floors[i]
	var fr := plan_frame(f)
	var c: Vector2 = fr[0]
	var s := float(fr[1])
	var r := float(fl.r)
	var rr := hull.gap_r + hull.walk
	var ink := GlobeView.ink_color()
	var glass := Color(str(lk.get("glass", "#5fa8d8")))
	var shield := Color(str(lk.get("shield", "#7cc4ff")))
	var goal := Color(str(GlobeMap.look().get("goal", {}).get("color", "#ffd84a")))
	var pulse := GlobeView.pulse()
	var font := get_theme_default_font()
	# The floor's plate, and an open floor's owner washed over it.
	draw_circle(c, r * s, Color(str(lk.get("room", "#2a3038")), 0.7))
	var rooms: Array = f.get("rooms", [])
	if rooms.is_empty() and str(f.get("owner", "")) != "":
		draw_circle(c, r * s, Color(GlobeMap.owner_color(str(f.owner)), 0.1))
	_draw_rooms(f, c, s, goal, pulse, lk)
	# The walkway (the floor's own waypoint), the gap's shield, the shaft, its bridges.
	var walk_on := str(f.id) == selected
	var walk_hot := str(f.id) == hover_room
	var wcol := Color(str(lk.get("walkway", "#cfc9bd")))
	if walk_on:
		wcol = goal.lerp(Color.WHITE, pulse * 0.4)
	draw_arc(c, (hull.gap_r + rr) * 0.5 * s, 0.0, TAU, 64, Color(wcol, 0.35 if walk_on or walk_hot else 0.18), hull.walk * s, true)
	draw_circle(c, hull.gap_r * s, Color(shield, 0.12))
	draw_arc(c, hull.gap_r * s, 0.0, TAU, 48, Color(shield, 0.7), 1.0, true)
	draw_circle(c, hull.shaft_r * s, Color(glass, 0.25))
	draw_arc(c, hull.shaft_r * s, 0.0, TAU, 32, glass, 1.5, true)
	for a: float in StationHull.bridge_angles(i):
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * hull.shaft_r * s, c + d * hull.gap_r * s, Color(wcol, 0.8), maxf(2.0, 2.4 * s), true)
	# Each tunnel's corridor through the rooms, walkway to glass.
	for ex in hull.floor_exits(t, i):
		var d := Vector2(cos(float(ex.a)), sin(float(ex.a)))
		var from := rr if not rooms.is_empty() else (hull.gap_r + rr) * 0.5
		draw_line(c + d * from * s, c + d * r * s, Color(wcol, 0.3), (hull.tunnel_w + 0.8) * s, false)
	draw_arc(c, r * s, 0.0, TAU, 96, Color(glass, 0.9), 2.0, true)
	# An open floor: its stall rings and its named stalls.
	if rooms.is_empty():
		_draw_stalls(f, c, s, lk, font)
	# The tunnels' exits: a gap in the glass, an arrow out and where it goes.
	var towers: Dictionary = GlobeMap.cfg().get("station_towers", {})
	for ex in hull.floor_exits(t, i):
		var d := Vector2(cos(float(ex.a)), sin(float(ex.a)))
		var a0 := c + d * r * s
		var a1 := c + d * (r * s + 22.0)
		draw_line(a0, a1, Color(ink, 0.9), 2.0, true)
		var side := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([a1 + d * 7.0, a1 + side * 5.0, a1 - side * 5.0]), Color(ink, 0.9))
		if font != null:
			var text := GlobeMap.line("station_exit") % str(towers.get(str(ex.to), str(ex.to)))
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var at := a1 + d * 14.0
			var p := Vector2(clampf(at.x - w * 0.5 + d.x * w * 0.5, 4.0, size.x - w - 4.0), clampf(at.y + 4.0 + d.y * 6.0, HEAD + 12.0, size.y - 4.0))
			draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.85))
			draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
	# The room labels last, over everything.
	if font != null:
		_draw_room_labels(f, c, s, font, goal, pulse)
		var title := "%s  ·  %s" % [str(f.label).to_upper(), str(towers.get(str(f.tower), str(f.tower)))]
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, Vector2(size.x * 0.5 - tw * 0.5, 22.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.96, 0.92, 0.84))
		var sub := str(f.get("summary", ""))
		var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, Vector2(size.x * 0.5 - sw * 0.5, 40.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 0.9, 0.84, 0.8))
	# You, when you are on this floor.
	if player != Vector3.INF and player.y >= float(fl.y) - 1.0 and player.y < float(fl.y) + hull.floor_h:
		_draw_you(plan_px(f, Vector2(player.x, player.z)))


## The rooms as wedges between the walkway's wall and the window, each in its
## owner's colour (brighter hovered, the waypoint's flashing), batched into one
## triangle list; their walls in one line list.
func _draw_rooms(f: Dictionary, c: Vector2, s: float, goal: Color, pulse: float, lk: Dictionary) -> void:
	var rooms: Array = f.get("rooms", [])
	if rooms.is_empty():
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var walls := PackedVector2Array()
	var alpha := float(lk.get("room_alpha", 0.32))
	for rm in rooms:
		var col := GlobeMap.owner_color(str(rm.owner))
		var on := str(rm.id) == selected
		if on:
			col = Color(goal.lerp(Color.WHITE, pulse * 0.4), 0.35 + 0.25 * pulse)
		elif str(rm.id) == hover_room:
			col = Color(col.lightened(0.15), alpha + 0.25)
		else:
			col = Color(col, alpha if bool(rm.open) else alpha * 0.5)
		var a0 := float(rm.a) - float(rm.half)
		var a1 := float(rm.a) + float(rm.half)
		var r0 := float(rm.r0) - 0.4
		var r1 := float(rm.r1)
		var base := pts.size()
		for k in ARC_SEGS + 1:
			var a := lerpf(a0, a1, float(k) / ARC_SEGS)
			var d := Vector2(cos(a), sin(a))
			pts.append(c + d * r0 * s)
			pts.append(c + d * r1 * s)
			cols.append(col)
			cols.append(col)
			if k > 0:
				var j := base + k * 2
				idx.append_array([j - 2, j - 1, j, j, j - 1, j + 1])
		for a: float in [a0, a1]:
			var d := Vector2(cos(a), sin(a))
			walls.append(c + d * r0 * s)
			walls.append(c + d * r1 * s)
		# A shut door: a short bar across it on the walkway's wall.
		if not bool(rm.open):
			var d := Vector2(cos(float(rm.a)), sin(float(rm.a)))
			var side := Vector2(-d.y, d.x)
			walls.append(c + d * r0 * s - side * 5.0)
			walls.append(c + d * r0 * s + side * 5.0)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)
	draw_multiline(walls, Color(GlobeView.ink_color(), 0.55), 1.0)
	draw_arc(c, (float(rooms[0].r0) - 0.4) * s, 0.0, TAU, 96, Color(GlobeView.ink_color(), 0.55), 1.0, true)


## Each room's name in its middle, its owner under it in their colour.
func _draw_room_labels(f: Dictionary, c: Vector2, s: float, font: Font, goal: Color, pulse: float) -> void:
	for rm in f.get("rooms", []):
		var d := Vector2(cos(float(rm.a)), sin(float(rm.a)))
		var at := c + d * (float(rm.r0) + float(rm.r1)) * 0.5 * s
		var on := str(rm.id) == selected
		var hot := str(rm.id) == hover_room
		var nm := str(rm.label).to_upper()
		var fs := 12 if (float(rm.r1) - float(rm.r0)) * s > 70.0 else 10
		var col := goal.lerp(Color.WHITE, pulse * 0.4) if on else (Color.WHITE if hot else Color(0.96, 0.92, 0.84))
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := at + Vector2(-w * 0.5, -1.0)
		draw_string_outline(font, p, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.85))
		draw_string(font, p, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		var who := str(rm.get("owner_label", ""))
		if who != "":
			var ofs := fs - 1
			var ow := font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, ofs).x
			var op := at + Vector2(-ow * 0.5, ofs + 2.0)
			draw_string_outline(font, op, who, HORIZONTAL_ALIGNMENT_LEFT, -1, ofs, 3, Color(0, 0, 0, 0.85))
			draw_string(font, op, who, HORIZONTAL_ALIGNMENT_LEFT, -1, ofs, GlobeMap.owner_color(str(rm.owner)).lightened(0.55))


## An open floor's stalls: each of its fill block's rings as a row of little
## stalls (a market's every every_m metres, the favela's lines_per_ring homes),
## batched into one triangle list, and its named stalls (StationHull.favela_vendors)
## as squares with their names.
func _draw_stalls(f: Dictionary, c: Vector2, s: float, lk: Dictionary, font: Font) -> void:
	var t := hull.tower(str(f.tower))
	var fc: Dictionary = hull.cfg.get("fill", {}).get("floors", {}).get(str(t.floors[int(f.floor)].id), {})
	var ring_col := Color(GlobeMap.owner_color(str(f.get("owner", ""))).lightened(0.2), 0.7)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var exits: Array = hull.floor_exits(t, int(f.floor)).map(func(e): return float(e.a))
	for rg in fc.get("rings", []):
		var r := float(rg.get("r", 0.0))
		var every := float(rg.get("every_m", 0.0))
		var n := int(r * TAU / every) if every > 0.0 else int(fc.get("lines_per_ring", 20))
		var dep: Array = rg.get("depth", [2.8, 3.2])
		var half := Vector2(maxf(1.6, float(dep[0]) * 0.5), minf(r * TAU / maxf(n, 1) * 0.35, 2.2)) * s
		for k in n:
			var a := TAU * (k + 0.5) / n
			var clear := true
			for ea: float in exits:
				clear = clear and absf(wrapf(a - ea, -PI, PI)) * r > hull.tunnel_w
			if not clear:
				continue
			var d := Vector2(cos(a), sin(a))
			var side := Vector2(-d.y, d.x)
			var m := c + d * r * s
			var base := pts.size()
			pts.append_array([m - d * half.x - side * half.y, m + d * half.x - side * half.y, m + d * half.x + side * half.y, m - d * half.x + side * half.y])
			cols.append_array([ring_col, ring_col, ring_col, ring_col])
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if not idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)
	var names: Dictionary = GlobeMap.cfg().get("station_vendors", {})
	var vcol := Color(str(lk.get("vendor", "#e8c050")))
	for v in hull.favela_vendors():
		var at: Vector3 = v.at
		if absf(at.y - float(t.floors[int(f.floor)].y)) > 1.0 or (t.c as Vector2).distance_to(Vector2(at.x, at.z)) > float(t.floors[int(f.floor)].r):
			continue
		var p := plan_px(f, Vector2(at.x, at.z))
		GlobeView.draw_shape(self, p, "square", vcol, 6.0)
		if font != null:
			var text := str(names.get(str(v.kind), str(v.kind).capitalize()))
			draw_string_outline(font, p + Vector2(9, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.85))
			draw_string(font, p + Vector2(9, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, vcol)
