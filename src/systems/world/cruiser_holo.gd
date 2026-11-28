class_name CruiserHolo
extends Node3D
## The bridge's holo table: the home planet as the cruiser sees it, floating over
## the table. A ball of light with the port, every crash site (the world's wreck
## landmarks) and the cruiser itself where they really are on it, the cruiser's
## orbit, and the moon (the planet's child neighbour) in its real direction. All of
## it is turned to the world, not the ship (north and east as on the ground), and
## spins slowly about the planet's up, so the map stays true as it turns.
##
## Issue #325: the port and the seven Remnant outposts are coloured by who holds
## them (Territory: the barracks for the port), and recoloured live while you
## watch (every refresh_s); an outpost's pin flashes for a few seconds when it
## changes hands. The outposts' pins have no names: they sit too close round the
## port for labels to read.
##
## Heights over the ball are squeezed (holo.squeeze) so the 7 km orbit fits over a
## five metre table; the moon keeps its true direction at a set distance. Numbers, colours and lines: the cruiser data's
## "holo" block (content/core/cruiser/remnant_cruiser.json).
##
## Issue #321: the barracks office's holo table shows the same map (BarracksLook),
## smaller, with "here_on": "town" (the port is "here", the cruiser just named);
## its parent is in the world's frame, so `cruiser_frame` is only where the cruiser is.
##
## Issue #327: a cruiser over another planet's system (the belt cruiser over the
## ringed giant, holo.kind "system") shows that whole system (setup_system): the
## giant with its ring, and on their orbits round it the space station (a small
## model of it), the cruiser and the moon, with the moon's outposts and barracks
## pinned on it. The station's barracks (its Remnant deck), the cruiser, and the
## moon's outposts and barracks each say who holds them, by colour and by name.
##
## Issue #838: a station that is an outpost of a front (the belt's three skimmer
## outposts over the giant, Territory "station_<landmark id>") is pinned on the
## ball where it really is, coloured by who holds it, like the moon's outposts, not
## drawn as a station of its own; the station that is that front's barracks says
## under its name how many of them each side holds. The table holo (setup) on such
## a planet pins them too, and its town pin is that station's deck. Each outpost is
## named, with the F11 map's own line under it (GlobeMap.owner_status: "Held by the
## Remnant, 72:10 left"), its clock running down live.

const SHADER := preload("res://src/systems/look/shaders/holo.gdshader")

static var _noise: Texture2D

var spec: Dictionary = {}
var sphere: PlanetSphere
var radius := 1.1
var _spin := 0.0
var _turn: Node3D                      ## everything that spins, centred on the ball
var _to_world := Basis.IDENTITY        ## the parent's frame back to the world's axes
## Issue #325: place id (an outpost, or Territory.BARRACKS for the port) ->
## { owner, short, mats, label, flash }: the pin's materials to recolour.
var places: Dictionary = {}
var _refresh := 0.0
## The cruiser's taken flag when it is not the home one (setup_system): Remnant
## until it is set, then empty. "" for the home cruiser (RemnantCruiser.home_holder).
var cruiser_flag := ""
## Labels whose text says who holds something: { label, text: Callable }.
var _texts: Array = []
## Issue #838: labels with a hold clock in them, written again every refresh_s.
var _clocks: Array = []
## Issue #838: outpost labels shown only while their pin is on the camera's side of
## the ball, so the far ones do not pile onto the near ones: { label, dir }.
var _facing: Array = []
## Labels kept apart on screen (declutter): { label, k }, the lowest k first; a
## label that would cover one placed before it slides down the screen until clear.
var _clutter: Array = []


## `cruiser_frame` is the cruiser's frame in the world (the parent's), `anchor` the
## ball's centre in it; `world` the planet's world data (its landmarks), `moons`
## the planet's neighbours ({ id, at, radius, child }), `names` labels by key
## ("town", "cruiser", and each moon's id).
func setup(cfg: Dictionary, sp: PlanetSphere, cruiser_frame: Transform3D, anchor: Vector3, world: Dictionary,
		moons: Array, names: Dictionary) -> void:
	spec = cfg
	sphere = sp
	name = "HoloMap"
	radius = float(spec.get("radius", 1.1))
	position = anchor
	_to_world = cruiser_frame.basis.orthonormalized().inverse()
	basis = _to_world
	_turn = Node3D.new()
	_turn.name = "Turn"
	add_child(_turn)
	var col := Color(str(spec.get("color", "#3fc8ff")))
	# The ball, a fainter shell of grid over it, and the projector's beam under it.
	var ball := _sphere(radius, _mat(col, 0.8, 0.06, 1.0, 0.0, 0.3))
	_turn.add_child(ball)
	_turn.add_child(_sphere(radius * 1.004, _mat(col, 0.7, 0.0, 0.25, 9.0, 0.0)))
	_projector(col, radius * 0.95, radius * 0.6)
	# The port, at the top of the ball (the map's origin), and the Remnant's
	# outposts, each coloured by who holds it.
	var here_line := str(spec.get("lines", {}).get("here", "%s"))
	var here_town := str(spec.get("here_on", "cruiser")) == "town"
	var town_name := str(names.get("town", ""))
	if here_town and town_name != "":
		town_name = here_line % town_name
	# Issue #838: on a planet whose station is a front's barracks (the ringed
	# giant's), the town pin is that deck, and the front's station outposts are
	# pinned where they really are.
	var town_id := Territory.BARRACKS
	for lm in StationHull.landmarks(world):
		var sid := Territory.STATION + str(lm.get("id", ""))
		var f := Territory.front_of(sid)
		if f == Territory.HOME:
			continue
		if Territory.barracks_of(f) == sid:
			town_id = sid
		elif (Territory.outposts(f) as Array).has(sid):
			var sat := WorldGround._v3(lm.get("at", [0, 0, 0]))
			_outpost_pin(sid, sphere.map_dir(sat.x, sat.z), GlobeMap.station_label({ "id": str(lm.get("id", "")), "station": str(lm.get("station", "")) }))
	var town_pin := _pin(sphere.map_dir(0.0, 0.0), owner_color(town_id), 0.28, town_name, true)
	_place(town_id, town_pin)
	_keep_apart(town_pin.label, 0)
	for lm in world.get("landmarks", []):
		var id := str(lm.get("id", ""))
		if Story.OUTPOSTS.has(id):
			var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
			_place(id, _pin(sphere.map_dir(at.x, at.z), owner_color(id), float(spec.get("outpost_stalk", 0.12)), "", false))
	# Every crash site on the world's map.
	var wreck_col := Color(str(spec.get("wreck_color", "#ff4a2a")))
	for lm in world.get("landmarks", []):
		if str(lm.get("kind", "")) != "wreck":
			continue
		var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
		_pin(sphere.map_dir(at.x, at.z), wreck_col, 0.16, str(spec.get("lines", {}).get("wreck", "")), false)
	# The cruiser in its orbit, and the orbit itself (issue #321: not on a planet with none).
	if not bool(spec.get("no_cruiser", false)):
		var ship_name := str(names.get("cruiser", ""))
		_orbiting_cruiser(cruiser_frame, ship_name if here_town else here_line % ship_name)
	# The moon (any child neighbour): its real direction, its distance squeezed.
	for m in moons:
		if bool(m.get("child", true)):
			_moon(m, str(names.get(str(m.get("id", "")), "")))


## The cruiser over the ball where it really is (heights squeezed), its bow along
## the ground, on its orbit, coloured by who holds it (issue #497), and its label
## (`text`). Returns the label.
func _orbiting_cruiser(cruiser_frame: Transform3D, text: String) -> Label3D:
	var here := cruiser_frame.origin - sphere.center
	var ccol := owner_color(CRUISER)
	var ship := MeshInstance3D.new()
	ship.name = "Cruiser"
	var wedge := PrismMesh.new()
	wedge.size = Vector3(0.09, 0.26, 0.04)
	ship.mesh = wedge
	ship.material_override = _mat(ccol, 3.0, 1.0, 0.6, 0.0, 0.0)
	ship.position = here.normalized() * squeezed(here.length())
	_turn.add_child(ship)
	ship.look_at_from_position(ship.position, ship.position + _tangent(here), here.normalized())
	ship.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	var orbit := _ring(here, squeezed(here.length()), ccol, 0.5)
	_turn.add_child(orbit)
	var ship_label := _label(ship.position + here.normalized() * 0.2, text, ccol)
	_turn.add_child(ship_label)
	_keep_apart(ship_label, 1)
	_place(CRUISER, { "mats": [ship.material_override, orbit.material_override], "label": ship_label })
	return ship_label


## A moon (a child neighbour { id, at, radius }): a ball in its real direction at
## holo.moon_at times the ball's radius, its orbit, and its label (`text`) over it.
## Returns the ball, its label in its "label" meta.
func _moon(m: Dictionary, text: String) -> MeshInstance3D:
	var mcol := Color(str(spec.get("moon_color", "#a9b8ff")))
	var rel: Vector3 = (m.at as Vector3) - sphere.center
	var r := clampf(float(m.get("radius", 0.0)) / sphere.radius * radius, float(spec.get("moon_min_radius", 0.16)),
		float(spec.get("moon_max_radius", 0.24)))
	var moon := _sphere(r, _mat(mcol, 1.0, 0.2, 1.0, 5.0, 0.4))
	moon.name = "Moon_" + str(m.get("id", ""))
	moon.position = rel.normalized() * radius * float(spec.get("moon_at", 2.3))
	_turn.add_child(moon)
	_turn.add_child(_ring(rel, moon.position.length(), mcol, 0.3))
	var label := _label(moon.position + Vector3(0, r + 0.08, 0), text, mcol)
	_turn.add_child(label)
	moon.set_meta("label", label)
	_keep_apart(label, 2)
	return moon


## The projector under the map: a cone of light from the table top up to `under`
## metres below its middle, `top` wide there, and its lamp.
func _projector(col: Color, top: float, under: float) -> void:
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cone := CylinderMesh.new()
	cone.top_radius = top
	cone.bottom_radius = top * 0.58
	cone.height = maxf(float(spec.get("lift", 1.75)) - under, 0.1)
	cone.cap_top = false
	cone.cap_bottom = false
	beam.mesh = cone
	beam.material_override = _mat(col, 0.35, 0.05, 0.6, 0.0, 0.0)
	beam.position = Vector3(0, -under - cone.height * 0.5, 0)     # from the table top up to the map
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var lamp := OmniLight3D.new()
	lamp.light_color = col
	lamp.light_energy = 1.6
	lamp.omni_range = 7.0
	add_child(lamp)


# ------------------------------------------------------------------ the whole system

## The map of a planet's whole system for a cruiser holding station over it (the
## belt cruiser over the ringed giant, holo.kind "system"): the planet's ball with
## its ring (`body`: the planet's look from space, its "ring" in planet radii), and
## everything that goes round it, each on its orbit: every space station
## (`stations`: { id (its Territory place, "station_<landmark id>"), hull, frame,
## name }), this cruiser, and every moon of it (`moons`, the child ones), its
## outposts and its barracks pinned on it where they really are. Each says who
## holds it, by colour and by name, and changes live (refresh_owners). `flag` is
## this cruiser's taken flag (it is empty once taken); `names` labels by key
## ("cruiser").
func setup_system(cfg: Dictionary, sp: PlanetSphere, body: Dictionary, cruiser_frame: Transform3D, anchor: Vector3,
		stations: Array, moons: Array, names: Dictionary, flag: String) -> void:
	spec = cfg
	sphere = sp
	cruiser_flag = flag
	name = "HoloMap"
	radius = float(spec.get("radius", 0.7))
	position = anchor
	_to_world = cruiser_frame.basis.orthonormalized().inverse()
	basis = _to_world
	_turn = Node3D.new()
	_turn.name = "Turn"
	add_child(_turn)
	var col := Color(str(spec.get("color", "#3fc8ff")))
	var ball := _sphere(radius, _mat(col, 0.8, 0.06, 1.0, 0.0, 0.0))
	ball.name = "Planet"
	_turn.add_child(ball)
	_turn.add_child(_sphere(radius * 1.004, _mat(col, 0.7, 0.0, 0.25, float(spec.get("bands", 14.0)), 0.0)))
	var ring: Dictionary = body.get("ring", {})
	if not ring.is_empty():
		_planet_ring(ring)
	for st in stations:
		if station_front(str(st.id)) != "":
			_system_outpost(st)
		else:
			_system_station(st)
	if not bool(spec.get("no_cruiser", false)):
		var ship_name := str(spec.get("lines", {}).get("here", "%s")) % str(names.get("cruiser", ""))
		var label := _orbiting_cruiser(cruiser_frame, "")
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_texts.append({ "label": label, "text": func() -> String: return _owned(ship_name, CRUISER) })
	for m in moons:
		if bool(m.get("child", true)):
			_system_moon(m)
	_projector(col, radius * 0.95, radius * 0.6)
	_relabel()


## The planet's ring: a faint flat band from ring.inner to ring.outer planet radii
## square to ring.normal, and holo.rocks rocks scattered through it.
func _planet_ring(ring: Dictionary) -> void:
	var n := WorldGround._v3(ring.get("normal", [0, 1, 0])).normalized()
	var r0 := float(ring.get("inner", 1.4)) * radius
	var r1 := float(ring.get("outer", 2.4)) * radius
	var band := MeshInstance3D.new()
	band.name = "Ring"
	var t := TorusMesh.new()
	t.inner_radius = r0
	t.outer_radius = r1
	t.rings = 96
	t.ring_segments = 6
	band.mesh = t
	band.material_override = _mat(Color(str(spec.get("rock_color", "#86c4e0"))), 0.5, 0.25, 0.0, 0.0, 0.0)
	band.basis = PlanetSphere.tilt_to(n) * Basis.from_scale(Vector3(1.0, 0.03 / maxf(r1 - r0, 0.01), 1.0))
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_turn.add_child(band)
	_rocks(r0, r1, n)


## Rocks scattered from holo.seed between `r0` and `r1` round the ball's centre in
## the plane square to `n`: one MultiMesh of faceted lumps.
func _rocks(r0: float, r1: float, n: Vector3) -> void:
	var count := int(spec.get("rocks", 160))
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 327))
	var lump := SphereMesh.new()
	lump.radius = 0.5
	lump.height = 1.0
	lump.radial_segments = 6
	lump.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = lump
	mm.instance_count = count
	var thick := float(spec.get("ring_thick", 0.04))
	var s0 := float(spec.get("rock_min", 0.008))
	var s1 := float(spec.get("rock_max", 0.03))
	var tilt := PlanetSphere.tilt_to(n)
	for i in count:
		var a := rng.randf() * TAU
		var r := lerpf(r0, r1, sqrt(rng.randf()))
		var y := (rng.randf() + rng.randf() - 1.0) * thick * 0.5
		var size := lerpf(s0, s1, pow(rng.randf(), 2.0))
		var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		b = b.scaled(Vector3(size * rng.randf_range(0.7, 1.3), size * rng.randf_range(0.6, 1.0), size * rng.randf_range(0.8, 1.4)))
		mm.set_instance_transform(i, Transform3D(tilt * b, tilt * Vector3(cos(a) * r, y, sin(a) * r)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rocks"
	mmi.multimesh = mm
	mmi.material_override = _mat(Color(str(spec.get("rock_color", "#86c4e0"))), 1.3, 0.5, 0.9, 0.0, 0.0)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_turn.add_child(mmi)


## A space station on the system's map: a small model of it (its towers, the bay
## and the tunnels, turned as the real one is) holo.station_width long, over the
## ball where it really is (at least holo.station_over metres off the ball), on its
## orbit, with a bead over it and its name coloured by who holds its Remnant deck
## (the barracks).
func _system_station(st: Dictionary) -> void:
	var hull: StationHull = st.hull
	var frame: Transform3D = st.frame
	var col := Color(str(spec.get("color", "#3fc8ff")))
	var rel := frame.origin - sphere.center
	var r := maxf(squeezed(rel.length()), radius + float(spec.get("station_over", 0.14)))
	var at := rel.normalized() * r
	var model := _station_model(hull, float(spec.get("station_width", 0.3)), col)
	model.name = "Station_" + str(st.id)
	model.basis = frame.basis.orthonormalized()
	model.position = at
	_turn.add_child(model)
	_turn.add_child(_ring(rel, r, col, 0.3))
	var id := str(st.id)
	var bead := _sphere(0.035, _mat(owner_color(id), 3.0, 1.0, 0.6, 0.0, 0.0))
	bead.position = at + rel.normalized() * float(spec.get("station_bead", 0.12))
	_turn.add_child(bead)
	var label := _label(bead.position + Vector3(0, 0.06, 0), "", owner_color(id))
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_turn.add_child(label)
	_keep_apart(label, 0)
	var station_name := str(spec.get("lines", {}).get("station", "%s")) % str(st.get("name", ""))
	_place(id, { "mats": [bead.material_override], "label": label })
	var f := barracks_front(id)
	if f != "":
		_texts.append({ "label": label, "text": func() -> String: return _moon_line(station_name, f) })
	else:
		_texts.append({ "label": label, "text": func() -> String: return _barracks_line(station_name, id) })


## Issue #838: the front whose outpost station `id` ("station_<landmark id>") is,
## or "" (the station city, or a station of no front).
static func station_front(id: String) -> String:
	var f := Territory.front_of(id)
	return f if f != Territory.HOME and (Territory.outposts(f) as Array).has(id) else ""


## Issue #838: the front whose barracks station `id` is, if that front has
## outposts to count, or "".
static func barracks_front(id: String) -> String:
	var f := Territory.front_of(id)
	return f if f != Territory.HOME and Territory.barracks_of(f) == id and not (Territory.outposts(f) as Array).is_empty() else ""


## Issue #838: an outpost station on the system's map: a pin on the ball under
## where it really is, coloured by who holds it (no name: the station's label
## counts them), like the moon's outposts.
func _system_outpost(st: Dictionary) -> void:
	var frame: Transform3D = st.frame
	var id := str(st.id)
	var lm_id := id.trim_prefix(Territory.STATION)
	var outpost_name := str(st.get("name", ""))
	if outpost_name == "":
		var hull: StationHull = st.get("hull")
		outpost_name = GlobeMap.station_label({ "id": lm_id, "station": hull.id if hull != null else "" })
	_outpost_pin(id, frame.origin - sphere.center, outpost_name)


## Issue #838: an outpost station's pin on the ball at `dir`, coloured by who holds
## it, named, and under the name the F11 map's line for it (outpost_line), kept
## running live.
func _outpost_pin(id: String, dir: Vector3, outpost_name: String) -> void:
	var pin := _pin(dir, owner_color(id), float(spec.get("outpost_stalk", 0.12)), " ", false)
	var label := pin.label as Label3D
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.font_size = int(spec.get("outpost_font", 32))
	_facing.append({ "label": label, "dir": dir.normalized() })
	_keep_apart(label, 3)
	_place(id, pin)
	var entry := { "label": label, "text": func() -> String: return outpost_line(outpost_name, id) }
	_texts.append(entry)
	_clocks.append(entry)


## Issue #838: keep `label` clear of the labels with a lower `k` (declutter).
func _keep_apart(label: Label3D, k: int) -> void:
	if label == null:
		return
	_clutter.append({ "label": label, "k": k })
	_clutter.sort_custom(func(a, b): return int(a.k) < int(b.k))


## Issue #838: the labels kept apart on screen. Each frame every one goes back to
## its own place over what it names; then, in order (the station's or the town's
## first, the cruiser's, the moons', the outposts'), one that would cover a label
## already placed slides down the screen until it is clear (at most
## holo.declutter_tries steps). A few labels, a projection each: cheap.
func declutter() -> void:
	if _clutter.is_empty() or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var vp_h := get_viewport().get_visible_rect().size.y
	var tan_half := tan(deg_to_rad(cam.fov) * 0.5)
	var gap := float(spec.get("declutter_gap_px", 4.0))
	var placed: Array = []
	for c in _clutter:
		var l := c.label as Label3D
		if not l.has_meta("declutter_base"):
			l.set_meta("declutter_base", l.position)
		l.position = l.get_meta("declutter_base")
		if not l.is_visible_in_tree() or l.text.strip_edges() == "":
			continue
		var wp := l.global_position
		if cam.is_position_behind(wp):
			continue
		var ppm := vp_h / (2.0 * maxf(cam.global_position.distance_to(wp), 0.01) * tan_half)
		var font: Font = l.font if l.font != null else ThemeDB.fallback_font
		var sz := font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, -1, l.font_size) \
			* l.pixel_size * l.global_transform.basis.get_scale().x * ppm
		var at := cam.unproject_position(wp)
		var top := at.y - sz.y
		if l.vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
			top = at.y - sz.y * 0.5
		elif l.vertical_alignment == VERTICAL_ALIGNMENT_TOP:
			top = at.y
		var rect := Rect2(at.x - sz.x * 0.5, top, sz.x, sz.y).grow(gap * 0.5)
		var shift := 0.0
		for _try in int(spec.get("declutter_tries", 6)):
			var hit := false
			for r: Rect2 in placed:
				if rect.intersects(r):
					var dy := r.end.y - rect.position.y + 1.0
					rect.position.y += dy
					shift += dy
					hit = true
			if not hit:
				break
		if shift > 0.0:
			l.global_position = wp - cam.global_transform.basis.y * (shift / ppm)
		placed.append(rect)


## Issue #838: show an outpost's label only while its pin faces the camera.
func face_labels() -> void:
	if _facing.is_empty() or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for f in _facing:
		var l := f.label as Label3D
		var n := (_turn.global_transform.basis * (f.dir as Vector3)).normalized()
		l.visible = n.dot((cam.global_position - l.global_position).normalized()) > float(spec.get("outpost_face", -0.3))


## Issue #838: an outpost's name and, under it, what the F11 map says of it
## (GlobeMap.owner_status: who holds it and how long it has left), or just who
## holds it where the map says nothing (the Remnant's, on no clock).
func outpost_line(what: String, id: String) -> String:
	var status := str(GlobeMap.owner_status(id).get("status", ""))
	return "%s\n%s" % [what, status if status != "" else owner_name(id)]


## A station as a few drums of light: each tower from its lowest floor to its top
## as wide as its widest floor, the bay, and the tunnels; `width` metres long.
func _station_model(hull: StationHull, width: float, col: Color) -> Node3D:
	var root := Node3D.new()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for t in hull.towers:
		var r := 0.0
		for f in t.floors:
			r = maxf(r, float(f.r))
		lo = lo.min((t.c as Vector2) - Vector2(r, r))
		hi = hi.max((t.c as Vector2) + Vector2(r, r))
	if not hull.bay.is_empty():
		var br := Vector2(float(hull.bay.r), float(hull.bay.r))
		lo = lo.min((hull.bay.c as Vector2) - br)
		hi = hi.max((hull.bay.c as Vector2) + br)
	var y0 := hull.bottom_y()
	var y1 := hull.top_y()
	var mid := Vector3((lo.x + hi.x) * 0.5, (y0 + y1) * 0.5, (lo.y + hi.y) * 0.5)
	var k := width / maxf(maxf(hi.x - lo.x, hi.y - lo.y), 1.0)
	var shell := _mat(col, 1.4, 0.25, 1.1, 0.0, 0.0)
	var glass := _mat(col.lightened(0.35), 1.8, 0.3, 0.8, 0.0, 0.0)
	for t in hull.towers:
		var fl: Array = t.floors
		if fl.is_empty():
			continue
		var r := 0.0
		for f in fl:
			r = maxf(r, float(f.r))
		var b := float(fl[0].y)
		var top := float(fl[-1].y) + hull.floor_h
		var c: Vector2 = t.c
		root.add_child(_drum(r * k, (top - b) * k, shell, (Vector3(c.x, (b + top) * 0.5, c.y) - mid) * k, true))
	for tn in hull.tunnels:
		var xf: Transform3D = tn.xf
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(float(tn.length), hull.tunnel_h, hull.tunnel_w) * k
		mi.mesh = bm
		mi.material_override = glass
		mi.basis = xf.basis
		mi.position = (xf * Vector3(float(tn.length) * 0.5, hull.tunnel_h * 0.5, 0.0) - mid) * k
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	if not hull.bay.is_empty():
		var bc: Vector2 = hull.bay.c
		var bh := float(hull.bay.height)
		root.add_child(_drum(float(hull.bay.r) * k, bh * k, shell, (Vector3(bc.x, bh * 0.5, bc.y) - mid) * k, true))
	return root


## A moon on the system's map (_moon), with its barracks pinned on top (where its
## station is) and its outposts where they really are on it, each coloured by who
## holds it, and under its name how many outposts each side holds and who holds
## the barracks. A moon with no front of its own (Territory) is just the ball.
func _system_moon(m: Dictionary) -> void:
	var id := str(m.get("id", ""))
	var moon := _moon(m, "")
	var f := Territory.front_for_planet(id)
	var moon_name := str(m.get("name", ""))
	if f == Territory.HOME:
		(moon.get_meta("label") as Label3D).text = moon_name
		return
	var r := float((moon.mesh as SphereMesh).radius)
	var label := moon.get_meta("label") as Label3D
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.position = moon.position + Vector3(0, r + float(spec.get("outpost_stalk", 0.12)) + 0.06, 0)
	var mr := maxf(float(m.get("radius", 0.0)), 1.0)
	var pk := float(spec.get("moon_pin_scale", 0.6))
	var barracks := Territory.barracks_of(f)
	_place(barracks, _pin(Vector3.UP, owner_color(barracks), float(spec.get("outpost_stalk", 0.12)) * 0.8, "", true, moon, r, pk))
	var outposts: Array = Territory.outposts(f)
	for lm in PlanetGen.build(id).get("cfg", {}).get("landmarks", []):
		var oid := str(lm.get("id", ""))
		if outposts.has(oid):
			var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
			_place(oid, _pin(_ball_dir(at.x, at.z, mr), owner_color(oid), float(spec.get("outpost_stalk", 0.12)) * 0.6, "", false, moon, r, pk))
	_texts.append({ "label": moon.get_meta("label"), "text": func() -> String: return _moon_line(moon_name, f) })


## Unit direction from a ball's centre (`r` metres) for its map point (x, z): as
## PlanetSphere.map_dir, for a ball we have no sphere of.
static func _ball_dir(x: float, z: float, r: float) -> Vector3:
	var d := sqrt(x * x + z * z)
	if d < 0.0001:
		return Vector3.UP
	var th := d / r
	var s := sin(th) / d
	return Vector3(x * s, cos(th), z * s)


## Who holds place `id` as a word (holo.lines.owners: remnant, locals, empty).
func owner_name(id: String) -> String:
	var who := _owner(id)
	var key := who if who != "" else "empty"
	return str(spec.get("lines", {}).get("owners", {}).get(key, key.capitalize()))


func _owned(what: String, id: String) -> String:
	return str(spec.get("lines", {}).get("owned", "%s\n%s")) % [what, owner_name(id)]


func _barracks_line(what: String, id: String) -> String:
	return str(spec.get("lines", {}).get("barracks", "%s\nbarracks: %s")) % [what, owner_name(id)]


func _moon_line(what: String, f: String) -> String:
	var held := 0
	var outposts: Array = Territory.outposts(f)
	for o in outposts:
		if Territory.owner(str(o)) == Territory.LOCALS:
			held += 1
	var fmt := str(spec.get("lines", {}).get("moon", "%s\noutposts: %d Remnant, %d Locals\nbarracks: %s"))
	return fmt % [what, outposts.size() - held, held, owner_name(Territory.barracks_of(f))]


## Write every owner line again (holo.lines), after a place changes hands.
func _relabel() -> void:
	for t in _texts:
		(t.label as Label3D).text = (t.text as Callable).call()


## A round drum of light `r` wide and `h` tall centred at `at` (caps or open).
func _drum(r: float, h: float, mat: Material, at: Vector3, caps: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 40
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	mi.mesh = c
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The ball's size for a distance from the planet's centre (metres): the surface
## at `radius`, heights over it squeezed by holo.squeeze.
func squeezed(d: float) -> float:
	var over := maxf(0.0, d / sphere.radius - 1.0)
	return radius * (1.0 + over * float(spec.get("squeeze", 0.3)))


func _process(dt: float) -> void:
	_spin = wrapf(_spin + deg_to_rad(float(spec.get("spin_deg_s", 5.0))) * dt, 0.0, TAU)
	_turn.basis = Basis(Vector3.UP, _spin)
	_refresh -= dt
	if _refresh <= 0.0:
		_refresh = float(spec.get("refresh_s", 0.5))
		refresh_owners()
		for c in _clocks:
			(c.label as Label3D).text = (c.text as Callable).call()
	face_labels()
	declutter()
	for id in places:
		var p: Dictionary = places[id]
		if float(p.flash) > 0.0:
			p.flash = maxf(0.0, float(p.flash) - dt)
			var t := 0.5 + 0.5 * sin(float(p.flash) * TAU * 2.0) if float(p.flash) > 0.0 else 0.0
			_paint(p, owner_color(str(id)).lerp(Color.WHITE, t * 0.7))


## Who holds `id` (an outpost, or Territory.BARRACKS for the port) as the holo's
## colour: the Remnant's, the locals', or either side running short (issue #425:
## the Remnant once the cruiser has fallen).
## Issue #497: the cruiser's own place in `places`: its colour is who holds it.
const CRUISER := "cruiser"


## Who holds a place: Territory's owner, or for the cruiser RemnantCruiser's holder
## (the Remnant's colour while nobody holds it: the dark master aboard).
static func owner_of(id: String) -> String:
	if id == CRUISER:
		var h := RemnantCruiser.home_holder()
		return h if h != "" else Territory.REMNANT
	return Territory.owner(id)


## This map's holder of a place: owner_of, but a cruiser that is not the home one
## (cruiser_flag) is the Remnant's until taken and then nobody's ("").
func _owner(id: String) -> String:
	if id == CRUISER and cruiser_flag != "":
		return "" if WorldState.has_flag(cruiser_flag) else Territory.REMNANT
	return owner_of(id)


func owner_color(id: String) -> Color:
	var cols: Dictionary = spec.get("owner_colors", {})
	if id == CRUISER:
		var who := _owner(id)
		if who == Territory.LOCALS:
			return Color(str(cols.get(who, spec.get("cruiser_color", "#ff3030"))))
		if who == "":
			return Color(str(cols.get("empty", spec.get("cruiser_color", "#ff3030"))))
		return Color(str(spec.get("cruiser_color", "#ff3030")))
	var key := Territory.owner(id)
	if key == Territory.LOCALS and Territory.short_shown(id):
		key = "short"
	elif key == Territory.REMNANT and Territory.short_shown(id):
		key = "remnant_short"
	return Color(str(cols.get(key, spec.get("town_color", "#ffc23a"))))


## Recolour every place whose owner (or shortage) changed since the last look;
## an outpost that changed hands flashes for holo.flash_s.
func refresh_owners() -> void:
	var changed := false
	for id in places:
		var p: Dictionary = places[id]
		var who := _owner(str(id))
		var is_short := Territory.short_shown(str(id)) if str(id) != CRUISER else false
		if who == p.owner and is_short == p.short:
			continue
		if who != p.owner:
			p.flash = float(spec.get("flash_s", 3.0))
			changed = true
		p.owner = who
		p.short = is_short
		_paint(p, owner_color(str(id)))
	if changed:
		_relabel()


func _place(id: String, pin: Dictionary) -> void:
	pin["owner"] = _owner(id)
	pin["short"] = Territory.short_shown(id) if id != CRUISER else false
	pin["flash"] = 0.0
	places[id] = pin


func _paint(p: Dictionary, col: Color) -> void:
	for m in p.mats:
		(m as ShaderMaterial).set_shader_parameter("color", col)
	if p.label != null:
		(p.label as Label3D).modulate = col.lightened(0.3)


## A marker on the ball at `dir`: a stalk of light out of the surface with a bead
## on top, and its name over it. Returns { mats, label } to recolour it by. On
## another ball (a moon on the system's map): `parent` is that ball, `ball` its
## radius, `k` the pin's size.
func _pin(dir: Vector3, col: Color, tall: float, text: String, big: bool, parent: Node3D = null, ball := -1.0,
		k := 1.0) -> Dictionary:
	if parent == null:
		parent = _turn
	if ball < 0.0:
		ball = radius
	var out := { "mats": [], "label": null }
	var stalk := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.01 * k
	c.bottom_radius = 0.02 * k
	c.height = tall
	c.radial_segments = 8
	stalk.mesh = c
	stalk.material_override = _mat(col, 2.0, 0.8, 0.5, 0.0, 0.0)
	var up := dir.normalized()
	stalk.basis = PlanetSphere.tilt_to(up)
	stalk.position = up * (ball + tall * 0.5)
	parent.add_child(stalk)
	var bead := _sphere((0.05 if big else 0.04) * k, _mat(col, 3.0, 1.0, 0.6, 0.0, 0.0))
	bead.position = up * (ball + tall)
	parent.add_child(bead)
	out.mats.append(stalk.material_override)
	out.mats.append(bead.material_override)
	if big:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.1 * k
		t.outer_radius = 0.125 * k
		ring.mesh = t
		ring.material_override = _mat(col, 2.0, 0.8, 0.3, 0.0, 0.0)
		ring.basis = PlanetSphere.tilt_to(up)
		ring.position = up * (ball + 0.005)
		parent.add_child(ring)
		out.mats.append(ring.material_override)
	if text != "":
		out.label = _label(up * (ball + tall + 0.07), text, col)
		parent.add_child(out.label)
	return out


## A thin ring round the ball's centre through `dir` at `r`: an orbit.
func _ring(dir: Vector3, r: float, col: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = r - 0.004
	t.outer_radius = r + 0.004
	t.rings = 96
	t.ring_segments = 4
	mi.mesh = t
	mi.material_override = _mat(col, energy, 1.0, 0.0, 0.0, 0.0)
	# The torus lies in its own xz plane: turn its up square to `dir`.
	var n := dir.normalized().cross(_tangent(dir)).normalized()
	mi.basis = PlanetSphere.tilt_to(n)
	return mi


## A direction along the ground at `dir`, toward the world's +x where it can.
func _tangent(dir: Vector3) -> Vector3:
	var u := dir.normalized()
	var t := Vector3.RIGHT - u * u.dot(Vector3.RIGHT)
	if t.length() < 0.01:
		t = Vector3.FORWARD - u * u.dot(Vector3.FORWARD)
	return t.normalized()


func _label(at: Vector3, text: String, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.0028
	l.font_size = 40
	l.outline_size = 6
	l.modulate = col.lightened(0.3)
	l.outline_modulate = Color(0, 0.05, 0.1, 0.8)
	l.shaded = false
	l.double_sided = true
	return l


func _sphere(r: float, mat: Material) -> MeshInstance3D:
	var mi := LookMeshKit.mi(null, LookMeshKit.ball(r, 48, 24), mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _mat(col: Color, energy: float, fill: float, rim: float, grid: float, land: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("fill", fill)
	m.set_shader_parameter("rim", rim)
	m.set_shader_parameter("grid", grid)
	m.set_shader_parameter("land", land)
	m.set_shader_parameter("bands", 1.0 if grid > 0.0 or land > 0.0 else 0.0)
	if _noise == null:
		_noise = LookEnvironment.make_noise_texture(256, 3, 0.02)
	m.set_shader_parameter("noise_tex", _noise)
	return m
