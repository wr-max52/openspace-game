class_name StarcruiserWreck
extends RefCounted
## Issue #93, wreck only. A 600 m transport, bow (-Z) driven into the sand,
## stern (+Z) raised. The shell is plates, NOT one closed collision box: the
## town-facing breach opens onto a continuous deck with a fallen-plate approach.
## All geometry below feeds both WorldGround and WorldScenery's physics/visuals.
## No random placement or imported assets.
##
## Issue #148: the crash site is a place to ride and fight in.
##   - A bent hull plate propped on a brace beside the boarding plate is a speeder
##     kicker: ride up it and off the end.
##   - The hold climbs (34 degrees) to a level interior deck high in the stern. Its
##     floors are level with the horizon, not the hull: "level" coordinates are
##     (x, v, w) in the wreck's own unpitched frame, v up and w toward the stern.
##   - A ramp climbs from the interior deck out through a tear in the dorsal plating
##     to the bridge platform; another drops to the stern end of the upper gallery.
##     Broken railings line the open edges.
##   - Everything is a wreck plate, so it all wears the wreck's metal (WorldScenery).
## Wreck cleanup: the hold floor is the speeder ramp, open from the breach right
## up to the stern bulkhead. The interior is decks hung off the port and starboard
## plating in three tiers, catwalks across the hold between them and ramps along
## the walls; nothing comes within six metres of the middle of the floor. A ramp
## drops from the top of the floor along the starboard plating to the upper tier.
## Walkways wear decking, catwalks grating, ramps cleats and the bridge platform
## landing-pad paint (finishes "deck", "grate", "ramp", "pad").
## The Remnant droids that patrol it, and the cargo droid in the deep hold, are
## data (content/core/droids/droids.json, "wreck"); site_point() turns their
## routes into world points.
## Wreck field: more of the same class lie out east under the Remnant's cruiser,
## each its own landmark (worlds/port_desert.json). A landmark's "variant" makes
## each one barely unique (see VARIANT_KEYS); none leaves the original.
## Wreck poses: the field is spread round the whole ball, and each wreck lies its
## own way: "pitch_deg" (the bow's dive: the original's 34, down to nearly flat),
## "roll_deg" (a list onto one flank) and "bury_height" (how far its middle stands
## above the sand: low enough and most of the hull is under it). The interior is one
## rigid design (Pose): at any pitch its bridge platform keeps its place on the
## dorsal plating, the decks stay level, and what joins them to the hold is worked
## out from where they now lie: the stern ramp moves aft to wherever the floor meets
## the starboard deck, a climb ramp runs up the starboard side to the low balcony
## where the floor no longer rises to them, the gallery ramp only where it can climb,
## and the dorsal hatch, the radiators and the bridge struts follow the platform.

const HALF_LENGTH := 300.0
const DECK_Y := -24.0
const ENTRY := Vector3(30, DECK_Y, -35)
const PITCH_DEG := -34.0
const HATCH_SECTION := 16          ## the dorsal plates torn away over the bridge ramp
const HULL_RX := 48.0              ## the hull's half-width aft of the bow taper
const HULL_RY := 38.0
const INTERIOR_V := 136.0          ## the upper tier: wall decks and the bridge catwalk (level frame)
const MID_V := 126.0               ## the mid tier: wall ledges and a second catwalk
const LOW_V := 119.0               ## the low tier: balconies under the upper decks
const BRIDGE_V := 146.0            ## the bridge platform's floor (level frame)
const STERN_RAMP_W := 250.0        ## where the starboard ramp leaves the top of the hold floor
const CLEAR_X := 19.0              ## the hold floor is open this far either side of the keel
## The speeder kicker, level frame on the sand: start, end, and how high its lip is.
const KICKER_X := 120.0
const KICKER_W := Vector2(20.0, 55.0)
const KICKER_LIP := 8.0
## What a landmark's "variant" can change: "skip" (part id prefixes left out: a
## fallen deck, a missing radiator, the kicker), "ramp_width" (ramp id -> metres),
## "stern_ramp_w" (where the stern ramp leaves the hold floor), "rail_gaps"
## (railing id -> the panels knocked out), "shard_turn" (degrees the torn plating
## is twisted) and "salvage" (how many boxes lie at the boarding plate).
## Wreck poses: "deck_drop" lowers the interior (decks, ramps and bridge) that many
## metres in the hull, for a wreck that lies flat enough to have room above it.
## Issue #317: "smooth_spine" leaves the dorsal ribs off (a wreck you walk along the top of);
## "open_pad" tears the dorsal plates away over the bridge platform (open to the sky).
const VARIANT_KEYS := ["skip", "ramp_width", "stern_ramp_w", "rail_gaps", "shard_turn", "salvage", "deck_drop", "smooth_spine", "open_pad"]
const MAX_RAMP_DEG := 26.0         ## the steepest ramp a pose's connectors may make
const CLIMB_DEG := 24.0            ## the climb ramp's slope (hold floor -> starboard balcony)
const CLIMB_X := 25.0              ## the climb ramp's middle, clear of the hold floor's open lane
const FLOOR_END_Z := 294.0         ## the furthest aft (hull z) a ramp may leave the hold floor


## Wreck poses: how one wreck lies, and where the rigid interior sits in it. The
## interior is laid out in design coordinates (x, v, w): the original's level
## frame. `shift` moves that design into this wreck's level frame so the bridge
## platform's stern edge, where the bridge ramp comes up through the hull, stays on
## the same spot of the dorsal plating at any pitch, `drop` metres lower.
class Pose:
	var pitch_deg: float
	var a: float                   ## -pitch in radians: level -> hull turns a about +x
	var to_hull: Basis
	var shift: Vector2             ## design (v, w) -> level (v + shift.x, w + shift.y)

	func _init(pitch: float = -34.0, drop: float = 0.0) -> void:
		pitch_deg = pitch
		a = deg_to_rad(-pitch)
		to_hull = Basis(Vector3.RIGHT, a)
		if not (is_equal_approx(pitch, PITCH_DEG) and is_zero_approx(drop)):
			var anchor := Vector3(0, BRIDGE_V, 150.0)
			var at := Basis(Vector3.RIGHT, deg_to_rad(-PITCH_DEG)) * anchor
			var level := to_hull.inverse() * at
			shift = Vector2(level.y - anchor.y - drop, level.z - anchor.z)

	## A design point in the hull frame.
	func hull(p: Vector3) -> Vector3:
		return to_hull * (p + Vector3(0, shift.x, shift.y))

	## A hull-frame point in design coordinates.
	func design(h: Vector3) -> Vector3:
		return to_hull.inverse() * h - Vector3(0, shift.x, shift.y)

	## The design height where the hull frame's height is y, at design w.
	func v_at(y: float, w: float) -> float:
		return (y + (w + shift.y) * sin(a)) / cos(a) - shift.x

	## The hull-frame height of design (v, w).
	func hull_y(v: float, w: float) -> float:
		return (v + shift.x) * cos(a) - (w + shift.y) * sin(a)


static var _boxes_kept := {}           ## issue #693: landmark + ball -> the boxes it added (a session's)


static func add_to_ground(ground: WorldGround, landmark: Dictionary) -> void:
	# Issue #693: on a ball the boxes depend only on the landmark and the ball, so
	# each wreck is worked out once a session (~23 ms each) and copied after that.
	var sp0 := ground.sphere()
	var key := ""
	if sp0 != null:
		key = "%d|%s|%s" % [hash(landmark), str(sp0.radius), str(sp0.center)]
		if _boxes_kept.has(key):
			for b in _boxes_kept[key]:
				ground.boxes.append((b as Dictionary).duplicate())
			return
	var n0 := ground.boxes.size()
	_add_to_ground(ground, landmark)
	if key != "":
		_boxes_kept[key] = ground.boxes.slice(n0).map(func(b): return (b as Dictionary).duplicate())


## Issue #714: each wreck's parts (~15-20 ms of geometry apiece), worked out on a
## worker thread while the ship is still in open space (SpaceTravel._prepare), so
## the four wrecks coming in on the way down only register their boxes.
static var _parts_task := -1
static var _parts_keys: Array = []
static var _parts_out: Array = []


static func prepare(planet: Dictionary) -> bool:
	if _parts_task >= 0:
		return false
	var keys: Array = []
	var jobs: Array = []
	for lm in planet.get("world", {}).get("landmarks", []):
		if str(lm.get("kind", "")) != "wreck":
			continue
		var pitch := float(lm.get("pitch_deg", PITCH_DEG))
		var variant: Dictionary = (lm.get("variant", {}) as Dictionary).duplicate(true)
		var key := _parts_key(pitch, variant)
		if not keys.has(key) and not _parts_keys.has(key):
			keys.append(key)
			jobs.append([pitch, variant])
	if jobs.is_empty():
		return false
	_parts_keys = keys
	_parts_out = []
	_parts_out.resize(jobs.size())
	_parts_task = WorkerThreadPool.add_group_task(func(i: int): _parts_out[i] = parts(float(jobs[i][0]), jobs[i][1]),
		jobs.size(), -1, false, "wreck parts")
	return true


## parts(), from prepare()'s worker when it made them (waiting for it if it is
## still going), else now.
static func _parts_for(pitch: float, variant: Dictionary) -> Array:
	if _parts_task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_parts_task)
		_parts_task = -1
	var i := _parts_keys.find(_parts_key(pitch, variant))
	if i >= 0 and _parts_out[i] is Array:
		return _parts_out[i]
	return parts(pitch, variant)


static func _parts_key(pitch: float, variant: Dictionary) -> String:
	return "%s|%d" % [pitch, hash(variant)]


static func _add_to_ground(ground: WorldGround, landmark: Dictionary) -> void:
	var at := WorldGround._v3(landmark.get("at", [1350, 0, -120]))
	var sp := ground.sphere()
	var base := sp.surface_at(at.x, at.z) if sp != null else Vector3(at.x, ground.terrain.height_at(at.x, at.z), at.z)
	var up := ground.up_at(base)
	var tangent := PlanetSphere.tilt_to(up) * Basis(Vector3.UP, deg_to_rad(float(landmark.get("yaw_deg", -175.0))))
	# Wreck poses: a list onto one flank turns the whole ship, decks and all, about its keel.
	tangent = tangent * Basis(Vector3.BACK, deg_to_rad(float(landmark.get("roll_deg", 0.0))))
	var pitch := float(landmark.get("pitch_deg", PITCH_DEG))
	var xf := Transform3D(tangent * Basis(Vector3.RIGHT, deg_to_rad(pitch)),
		base + up * float(landmark.get("bury_height", 58.0)))
	# Issue #317: a wreck adrift (the belt under a station, BeltWrecks) is posed by
	# its own frame, the hull's, and has no sand: no boarding plate, salvage or kicker.
	var adrift := bool(landmark.get("adrift", false))
	if landmark.get("frame") is Transform3D:
		xf = landmark.frame
		tangent = xf.basis * Basis(Vector3.RIGHT, deg_to_rad(-pitch))
		base = xf.origin
	var level := Transform3D(tangent, xf.origin)
	var prefix := str(landmark.get("id", "starcruiser_wreck")) + "/"
	var variant: Dictionary = landmark.get("variant", {})
	var pose := Pose.new(pitch, float(variant.get("deck_drop", 0.0)))
	var n0 := ground.boxes.size()
	for p in _parts_for(pitch, variant):
		_register(ground, prefix + str(p.id), p.size, xf * p.xf, str(p.finish), base.y,
			"floor" if bool(p.get("floor", false)) else "solid")
		if bool(p.get("shard", false)):
			ground.boxes[-1]["wreck_shard"] = true
	if adrift:
		_tag_frames(ground, prefix, xf, level, pose)
		for b in ground.boxes:
			if str(b.id).begins_with(prefix):
				b["wreck_adrift"] = true
		return

	# A fallen ten-metre-wide plate joins actual sand to the breach's deck.
	# Project the outer end onto the planet rather than assuming a flat desert.
	# Issue #148: it meets the deck's top at the deck's edge, so a speeder rides
	# straight on rather than catching the edge (the old end, ENTRY, was 3 m in).
	# Wreck poses: where the sand has buried the breach's deck you walk in on the
	# sand, and there is no plate.
	var end := xf * Vector3(33.0, DECK_Y, ENTRY.z)
	var start := _on_sand(ground, xf * Vector3(145, DECK_Y, -35))
	start += ground.up_at(start) * 0.08
	var z := (end - start).normalized()
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	if not _buried(ground, end):
		var ramp := Transform3D(Basis(x, y, z), (start + end) * 0.5 - y * 0.6)
		_register(ground, prefix + "fallen_boarding_plate", Vector3(10, 1.2, start.distance_to(end) + 1.0),
			ramp, "hull", base.y, "floor")
	# Familiar, human-scale salvage boxes at the approach make its size legible.
	for i in int(variant.get("salvage", 3)):
		var pos := _on_sand(ground, start + x * (9.0 + i * 3.0))
		var box_up := ground.up_at(pos)
		_register(ground, prefix + "salvage_%d" % i, Vector3(1.6, 1.4, 2.0),
			Transform3D(PlanetSphere.tilt_to(box_up), pos + box_up * 0.7), "scorch", base.y)
	if not _skipped("speeder_kicker", variant):
		_add_kicker(ground, prefix, level, base.y)
	_tag_frames(ground, prefix, xf, level, pose)


## Every box of one wreck carries its two frames (site_point, the plates' shader).
## The "level" frame is the interior's: its design coordinates, wherever the pose
## put them (the original's own level frame).
static func _tag_frames(ground: WorldGround, prefix: String, xf: Transform3D, level: Transform3D, pose: Pose) -> void:
	var interior := level * Transform3D(Basis.IDENTITY, Vector3(0, pose.shift.x, pose.shift.y))
	for i in range(n0, ground.boxes.size()):           # this wreck's, all added just now
		var b: Dictionary = ground.boxes[i]
		if str(b.id).begins_with(prefix):
			b["wreck_frame"] = xf
			b["wreck_level"] = interior


## Issue #148: a torn hull plate bent up off the sand, its lip held KICKER_LIP
## metres up by a brace. A speeder rides up it toward the stern and leaves the
## lip ballistic (HoverModel launches when the ground drops away).
static func _add_kicker(ground: WorldGround, prefix: String, level: Transform3D, sand_y: float) -> void:
	var start := _on_sand(ground, level * Vector3(KICKER_X, 0, KICKER_W.x))
	var foot := _on_sand(ground, level * Vector3(KICKER_X, 0, KICKER_W.y))
	var up := ground.up_at(foot)
	var lip := foot + up * KICKER_LIP
	start += ground.up_at(start) * 0.08
	var z := (lip - start).normalized()
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	_register(ground, prefix + "speeder_kicker", Vector3(9, 1.2, start.distance_to(lip)),
		Transform3D(Basis(x, y, z), (start + lip) * 0.5 - y * 0.6), "hull", sand_y, "floor")
	# The brace stands under the lip, its top below the plate, so it never trips
	# a speeder on the way up or a landing one from above.
	var brace_h := KICKER_LIP - 1.4
	var tilt := PlanetSphere.tilt_to(up)
	var fwd := (z - up * z.dot(up)).normalized()
	for side in [-1, 1]:
		var at: Vector3 = foot - fwd * 1.5 + x * (3.2 * float(side))
		_register(ground, prefix + "kicker_brace_%d" % (0 if side < 0 else 1), Vector3(1.4, brace_h, 1.4),
			Transform3D(tilt, at + up * (brace_h * 0.5)), "rib", sand_y)


## The sand under a world point (along the planet's up on the ball).
static func _on_sand(ground: WorldGround, p: Vector3) -> Vector3:
	var sp := ground.sphere()
	if sp != null:
		var map := sp.world_to_map(p)
		return sp.surface_at(map.x, map.y)
	return Vector3(p.x, ground.terrain.height_at(p.x, p.z), p.z)


## Issue #317: whether wreck `id` is adrift (the belt under a station): nothing of
## it is ever under the sand, whatever the ball's surface under it says.
static func is_adrift(ground: WorldGround, id: String) -> bool:
	for b in ground.boxes:
		if b.has("wreck_frame") and str(b.id).begins_with(id + "/"):
			return bool(b.get("wreck_adrift", false))
	return false


## Wreck poses: whether a world point is under the sand.
static func _buried(ground: WorldGround, p: Vector3) -> bool:
	var sp := ground.sphere()
	if sp != null:
		return sp.height_above_ground(p) < 0.0
	return p.y < ground.terrain.height_at(p.x, p.z)


## The wreck's two frames from its boxes: "hull" (pitched with the ship: parts()
## coordinates) or "level" (unpitched: x, v up, w toward the stern; wreck poses:
## the interior's design coordinates, the same on every wreck). Identity when the
## wreck is not in this ground.
static func frame(ground: WorldGround, id: String = "starcruiser_wreck", kind: String = "level") -> Transform3D:
	var key := "wreck_level" if kind == "level" else "wreck_frame"
	for b in ground.boxes:
		if b.has(key) and str(b.id).begins_with(id + "/"):
			return b[key]
	return Transform3D.IDENTITY


static func has_wreck(ground: WorldGround, id: String = "starcruiser_wreck") -> bool:
	return ground != null and frame(ground, id) != Transform3D.IDENTITY


## A point given in one of the wreck's frames, in the world.
static func site_point(ground: WorldGround, p: Vector3, kind: String = "level", id: String = "starcruiser_wreck") -> Vector3:
	return frame(ground, id, kind) * p


## Issue #148: what you ride or walk on (decks, plates, ramps) is kind "floor":
## ground for height_above, never an obstacle to WorldGround.hit, like the town's
## floors. A speeder easing up to its hover height on a climb would otherwise catch
## the very plate it rides on.
static func _register(ground: WorldGround, id: String, size: Vector3, xf: Transform3D,
		finish: String, sand_y: float, kind: String = "solid") -> void:
	ground.add_box(id, kind, -size * 0.5, size * 0.5, "", false, xf)
	ground.boxes[-1]["wreck_finish"] = finish
	ground.boxes[-1]["sand_y"] = sand_y


## A faceted, rounded hull, not a wedge. Shell sections taper only at the bow.
## The +X flank loses 180 m of plating, with broken ribs above/below the opening.
## Issue #148: one stern section's dorsal plates (facets 1 and 2) are torn away
## where the bridge ramp comes up through the hull.
## Wreck field: `variant` (a landmark's, VARIANT_KEYS) makes one barely different.
## Wreck poses: the interior is laid out first, at this pitch; the dorsal plates
## (and their ribs) it would run into are the torn hatch, and the radiators it
## would stand in are gone (the original: HATCH_SECTION and radiator 3).
static func parts(pitch_deg: float = PITCH_DEG, variant: Dictionary = {}) -> Array:
	var out: Array = []
	var pose := Pose.new(pitch_deg, float(variant.get("deck_drop", 0.0)))
	var inner: Array = []
	_interior(inner, pose, variant)
	var bridge := _bridge_samples(inner)
	var pad_z := _open_pad_z(inner) if bool(variant.get("open_pad", false)) else Vector2.INF
	var turn := deg_to_rad(float(variant.get("shard_turn", 0.0)))
	for section in 20:
		var z := -285.0 + section * 30.0
		var width := lerpf(28.0, 48.0, clampf((z + 285.0) / 120.0, 0.0, 1.0))
		for facet in 8:
			if z >= -90.0 and z <= 90.0 and facet in [0, 7]:
				continue
			var plate: Array = []
			_facet(plate, "plate_%d_%d" % [section, facet], width, 38.0,
				facet, z, 29.8, 2.0, "hull")
			if facet in [1, 2] and _meets(plate[0], bridge):
				continue
			if facet in [1, 2] and z + 15.0 > pad_z.x and z - 15.0 < pad_z.y:
				continue               # issue #317: open_pad, torn away over the landing pad
			out.append(plate[0])
		# Regular, heavier frames give the exposed hull its whale-rib silhouette.
		# Issue #317: "smooth_spine" leaves the dorsal ones off (facets 1 and 2), so the
		# spine is plating you can walk end to end (the belt's wrecks), not a wall
		# 2 m high every 30 m.
		for facet in 8:
			if z >= -90.0 and z <= 90.0 and facet in [0, 7]:
				continue
			if facet in [1, 2] and bool(variant.get("smooth_spine", false)):
				continue
			var rib: Array = []
			_facet(rib, "rib_%d_%d" % [section, facet], width + 1.4, 39.4,
				facet, z - 13.0, 2.4, 3.6, "rib")
			if facet in [1, 2] and _meets(rib[0], bridge):
				continue
			out.append(rib[0])

	# The entire lower deck is traversable; no invisible box across the breach.
	_part_box(out, "lower_deck", Vector3(66, 2, 570), Vector3(0, DECK_Y - 1.0, 0), "rib")
	out[-1]["floor"] = true
	# Wreck cleanup: the floor runs on to the stern bulkhead, no pit at the top of the ramp.
	_part_box(out, "lower_deck_stern", Vector3(66, 2, 12.6), Vector3(0, DECK_Y - 1.0, 291.2), "rib")
	out[-1]["floor"] = true
	# An upper gallery only on the intact flank leaves the breach a tall atrium.
	_part_box(out, "upper_gallery", Vector3(17, 1.4, 270), Vector3(-22, -4, 100), "rib")
	out[-1]["floor"] = true
	for z in [-100.0, -40.0, 20.0, 80.0, 140.0, 200.0, 260.0]:
		# Wreck poses: a stanchion stops short of any deck or ramp the pose hangs across it.
		var top := _column_top(inner, Vector2(-29, z), 0.7, -23.5, 23.5)
		_part_box(out, "stanchion_%d" % int(z), Vector3(1.4, top + 23.5, 1.4), Vector3(-29, (top - 23.5) * 0.5, z), "rib")
		# 2.2 m high, 1.1 m wide door frames (open, not painted doors).
		for x in [-1.1, 1.1]:
			_part_box(out, "door_%d_%s" % [int(z), str(x)], Vector3(0.18, 2.2, 0.22),
				Vector3(-18 + x, DECK_Y + 1.1, z), "marking")
		_part_box(out, "lintel_%d" % int(z), Vector3(2.4, 0.18, 0.22),
			Vector3(-18, DECK_Y + 2.3, z), "marking")

	# Peeled, pointed fragments make an irregular fracture rather than a cut-out.
	# All lips stay above head height, below the deck or at the ends of the tear:
	# the original boarding plate and walkable route remain completely unchanged.
	for i in 9:
		var roll := deg_to_rad(-28.0 + float((i * 37) % 81))
		_shard(out, "torn_upper_%d" % i, Vector3(12 + i % 3 * 4, 1.2, 17 + i % 4 * 3),
			Vector3(40 + i % 3 * 2, 27 + i % 2 * 3, -92 + i * 23), "rib",
			Basis(Vector3.BACK, roll) * Basis(Vector3.UP, deg_to_rad(-21.0 + i * 5.0) + turn))
	for i in 7:
		_shard(out, "torn_lower_%d" % i, Vector3(8 + i % 3 * 3, 1.0, 15 + i % 2 * 8),
			Vector3(39 + i % 2 * 4, -31, -85 + i * 28), "scorch",
			Basis(Vector3.BACK, deg_to_rad(-18.0 - i * 4.0) - turn))
	for end in [-1, 1]:
		for i in 3:
			_shard(out, "torn_end_%d_%d" % [end, i], Vector3(14, 1.3, 19 + i * 4),
				Vector3(44, -10 + i * 14, end * (99 - i * 3)), "rib",
				Basis(Vector3.BACK, deg_to_rad(72.0 + i * 19)) * Basis(Vector3.UP, end * 0.38))
	# A raised stern bridge and radiator comb make the distant profile distinct.
	# Issue #148: the bridge stands level on struts, over the torn dorsal plates.
	out.append_array(inner)
	var standing := out.filter(func(q): return str(q.id).begins_with("plate_")).map(func(q): return str(q.id))
	for i in 6:
		var h := 18.0 + sin(float(i) / 5.0 * PI) * 12.0
		var radiator: Array = []
		var rz := 104.0 + i * 29.0
		_part_box(radiator, "radiator_%d" % i, Vector3(3, h, 11), Vector3(0, 39.0 + h * 0.5, rz), "rib")
		# Issue #148: the bridge platform stands where one was; wreck poses: and
		# none stands over the torn hatch, where its plates are gone.
		var section := int(round((rz + 285.0) / 30.0))
		if _meets(radiator[0], bridge, 1.0) or not ("plate_%d_1" % section in standing and "plate_%d_2" % section in standing):
			continue
		out.append(radiator[0])
	# Oxblood identification bands, kept to a few large, quiet accents.
	for z in [-150.0, 135.0, 255.0]:
		_part_box(out, "hull_band_%d" % int(z), Vector3(2.4, 17, 7),
			Vector3(-47, 0, z), "marking")
	# Keep the same four engine positions and overall stern; detail only the bells.
	# Layered housings, flared lips, recessed black throats and mechanical braces.
	# There is deliberately no glow, exhaust, flame, light or powered animation.
	_part_box(out, "buried_bow", Vector3(38, 50, 3), Vector3(0, 0, -299), "scorch")
	_part_box(out, "stern_bulkhead", Vector3(68, 52, 3), Vector3(0, 0, 299), "hull")
	for engine in 4:
		var center := Vector3(-22 if engine % 2 == 0 else 22, -16 if engine < 2 else 16, 315)
		var prefix := "engine_%d_" % engine
		_engine_ring(out, prefix + "root", center + Vector3(0, 0, -10), 12.8, 1.8, 10, "hull")
		_engine_ring(out, prefix + "gasket", center + Vector3(0, 0, -3), 13, 1.6, 1.2, "nozzle")
		_engine_ring(out, prefix + "housing", center + Vector3(0, 0, 1), 13.6, 1.7, 8, "hull")
		_engine_ring(out, prefix + "flared_collar", center + Vector3(0, 0, 9), 14.7, 2.0, 7, "rib")
		_engine_ring(out, prefix + "rim", center + Vector3(0, 0, 14), 15.2, 2.0, 2.4, "rib")
		_engine_ring(out, prefix + "inner_lip", center + Vector3(0, 0, 11), 11.6, 0.9, 3, "nozzle")
		_engine_ring(out, prefix + "throat", center + Vector3(0, 0, -1), 9.1, 1.6, 20, "nozzle")
		_part_box(out, prefix + "dark_back", Vector3(17, 17, 1), center + Vector3(0, 0, -12), "nozzle")
		for i in 12:
			var a := TAU * i / 12.0
			var radial := Vector3(cos(a), sin(a), 0)
			var rot := Basis(Vector3.BACK, a)
			_part_box(out, prefix + "brace_%d" % i, Vector3(1.1, 1.4, 19),
				center + radial * 14.0 + Vector3(0, 0, 2), "rib", rot)
			_part_box(out, prefix + "vent_%d" % i, Vector3(0.7, 2.8, 4.8),
				center + radial * 12.5 + Vector3(0, 0, -6), "nozzle", rot)
			_part_box(out, prefix + "vane_%d" % i, Vector3(4.3, 0.6, 0.9),
				center + radial * 5.3 + Vector3(0, 0, -10), "rib", Basis(Vector3.BACK, a + 0.3))
	if variant.has("skip"):
		return out.filter(func(p): return not _skipped(str(p.id), variant))
	return out


## Issue #317: the hull-frame z the bridge platform spans (variant "open_pad"
## tears the dorsal plates away over all of it, so it is open to the sky at a
## shallow dive, where they would otherwise roof it over).
static func _open_pad_z(inner: Array) -> Vector2:
	for q in inner:
		if str(q.id) != "bridge_platform":
			continue
		var xf: Transform3D = q.xf
		var h: Vector3 = (q.size as Vector3) * 0.5
		var span := Vector2(INF, -INF)
		for k in 8:
			var c := xf * Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z)
			span = Vector2(minf(span.x, c.z), maxf(span.y, c.z))
		return span
	return Vector2.INF


## Wreck poses: points (hull frame) the bridge takes up: the platform and the
## bridge house through and through, and the bridge ramp's middle with head room
## over it. The dorsal plating, ribs and radiators they reach are torn away.
static func _bridge_samples(inner: Array) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for q in inner:
		var id := str(q.id)
		var xf: Transform3D = q.xf
		var h: Vector3 = (q.size as Vector3) * 0.5
		if id in ["bridge_platform", "bridge"]:
			var n := Vector3i(maxi(2, ceili(h.x / 2.0) + 1), 3, maxi(2, ceili(h.z / 2.0) + 1))
			for i in n.x:
				for j in n.y:
					for k in n.z:
						pts.append(xf * Vector3(lerpf(-h.x, h.x, float(i) / (n.x - 1)),
							lerpf(-h.y, h.y, float(j) / (n.y - 1)), lerpf(-h.z, h.z, float(k) / (n.z - 1))))
		elif id == "bridge_ramp":
			var steps := ceili(h.z / 0.75)
			for k in steps + 1:
				for x in [-2.5, 0.0, 2.5]:
					for lift in [0.0, 1.0, 2.0]:
						pts.append(xf * Vector3(x, h.y + lift, lerpf(-h.z, h.z, float(k) / steps)))
	return pts


## Wreck poses: how high a square column (hull frame, centre xz, half-width
## `half`) can rise from `bottom` toward `top` before it meets one of the
## interior's floors: half a metre under the lowest it would meet, or `top`.
static func _column_top(inner: Array, xz: Vector2, half: float, bottom: float, top: float) -> float:
	var pts := PackedVector3Array()
	var y := bottom
	while y <= top:
		for dx in [-half, 0.0, half]:
			for dz in [-half, 0.0, half]:
				pts.append(Vector3(xz.x + dx, y, xz.y + dz))
		y += 0.5
	var lowest := top
	for q in inner:
		if not bool(q.get("floor", false)):
			continue
		var inv := (q.xf as Transform3D).affine_inverse()
		var h: Vector3 = (q.size as Vector3) * 0.5 + Vector3.ONE * 0.2
		for p in pts:
			if p.y >= lowest:
				continue
			var l := inv * p
			if absf(l.x) <= h.x and absf(l.y) <= h.y and absf(l.z) <= h.z:
				lowest = p.y
	return top if lowest >= top else lowest - 0.5


## Whether any of `pts` (hull frame) is inside part `q`, grown by `margin`.
static func _meets(q: Dictionary, pts: PackedVector3Array, margin: float = 0.3) -> bool:
	var inv := (q.xf as Transform3D).affine_inverse()
	var h: Vector3 = (q.size as Vector3) * 0.5 + Vector3.ONE * margin
	for p in pts:
		var l := inv * p
		if absf(l.x) <= h.x and absf(l.y) <= h.y and absf(l.z) <= h.z:
			return true
	return false


## Whether part `id` is one this variant leaves out (its "skip" prefixes).
static func _skipped(id: String, variant: Dictionary) -> bool:
	for s in variant.get("skip", []):
		if id.begins_with(str(s)):
			return true
	return false


## Issue #148: the level interior (all positions in the level frame, x, v, w).
## Wreck cleanup: decks hang off the hull's port and starboard plating in three
## tiers and catwalks cross the hold between them, all well clear of the hold
## floor's middle (|x| < CLEAR_X), which stays an open speeder ramp to the stern.
##   - Upper tier (INTERIOR_V): the starboard deck, reached by the stern ramp from
##     the top of the hold floor; the port decks, round the gallery ramp's opening;
##     the upper catwalk between them, where the bridge ramp climbs out through the
##     torn dorsal plates to the bridge platform (the landing pad).
##   - Mid tier (MID_V): stairs drop bow-ward from the upper catwalk along both
##     sides to the mid catwalk and the wall ledges off it.
##   - Low tier (LOW_V): from each ledge's stern end a ramp drops back aft under
##     the upper decks to a balcony on the plating.
## Wreck poses: the positions are design coordinates (Pose), the same on every
## wreck. What joins the design to the hull is worked out per pose (_connectors):
## the stern ramp, the climb ramp, the gallery ramp and how far out the drops run.
static func _interior(out: Array, pose: Pose, variant: Dictionary = {}) -> void:
	var u := INTERIOR_V
	var m := MID_V
	var l := LOW_V
	# Decks: id, x from-to (+-INF: out to that side's plating), w from-to, floor v, finish.
	for d in [
		["starboard_deck", Vector2(22, INF), Vector2(186, 232), u, "deck"],
		["upper_catwalk", Vector2(-INF, INF), Vector2(178, 186), u, "grate"],
		["port_deck_bow", Vector2(-INF, -12), Vector2(186, 196), u, "deck"],
		["port_deck_outer", Vector2(-INF, -26), Vector2(196, 218.5), u, "deck"],
		["port_deck_stern", Vector2(-INF, -12), Vector2(218.5, 228), u, "deck"],
		["mid_catwalk", Vector2(-INF, INF), Vector2(150, 154), m, "grate"],
		["starboard_ledge", Vector2(27, INF), Vector2(154, 176), m, "deck"],
		["port_ledge", Vector2(-INF, -27), Vector2(154, 176), m, "deck"],
		["starboard_balcony", Vector2(20, INF), Vector2(199.5, 207), l, "deck"],
		["port_balcony", Vector2(-INF, -31), Vector2(199.5, 207), l, "deck"],
	]:
		_deck(out, str(d[0]), d[1], d[2], float(d[3]), str(d[4]), pose)
	var c := _connectors(pose, variant)
	var drop_hi: float = c.drop_hi
	var drop_lo: float = c.drop_lo
	# Ramps: id, from, to (their tops, level frame), width, rails ([toward x, t from, t to]).
	var ramps: Array = [
		["bridge_ramp", Vector3(0, u, 180), Vector3(0, BRIDGE_V, 150), 10.0, [[-1, 0.05, 0.8], [1, 0.05, 0.8]]],
		["starboard_stair", Vector3(23, u, 178), Vector3(23, m, 154), 8.0, [[-1, 0.0, 1.0], [1, 0.0, 0.6]]],
		["port_stair", Vector3(-23, u, 178), Vector3(-23, m, 154), 8.0, [[1, 0.0, 1.0], [-1, 0.0, 0.6]]],
		["starboard_drop", Vector3(drop_hi, m, 176), Vector3(drop_lo, l, 200), 8.0, [[-1, 0.0, 1.0]]],
		["port_drop", Vector3(-drop_hi, m, 176), Vector3(-drop_lo, l, 200), 8.0, [[1, 0.0, 1.0]]],
	]
	if c.has("stern"):
		ramps.push_front(["stern_ramp", c.stern, Vector3(33, u, 232), 8.0, [[-1, 0.4, 1.0]]])
	if c.has("gallery"):
		ramps.insert(1 if c.has("stern") else 0, ["gallery_ramp", c.gallery, Vector3(-20, u, 218.5), 10.0, [[1, 0.0, 1.0]]])
	if c.has("climb"):
		ramps.append(["climb_ramp", c.climb, Vector3(CLIMB_X, l, 199.5), 8.0, [[-1, 0.35, 1.0]]])
	var widths: Dictionary = variant.get("ramp_width", {})
	for r in ramps:
		if _skipped(str(r[0]), variant):
			continue
		var width := float(widths.get(str(r[0]), r[3]))
		_ramp(out, str(r[0]), r[1], r[2], width, pose)
		for rail in r[4]:
			var a: Vector3 = r[1]
			var b: Vector3 = r[2]
			var side := _ramp_side(a, b, float(rail[0])) * (width * 0.5 - 0.2)
			_railing(out, "%s_rail_%s" % [r[0], "s" if float(rail[0]) > 0 else "p"],
				a.lerp(b, float(rail[1])) + side, a.lerp(b, float(rail[2])) + side, [], pose)
	_slab(out, "bridge_platform", Vector2(-14, 14), Vector2(112, 151), BRIDGE_V, pose, "pad")
	_level(out, "bridge", Vector3(26, 10, 12), Vector3(0, BRIDGE_V + 5.0, 118), "hull", pose)
	_level(out, "bridge_windows", Vector3(26.4, 2, 9), Vector3(0, BRIDGE_V + 7.0, 118), "scorch", pose)
	# Struts from the platform's bow corners down onto the hull (none where the
	# pose has set the platform down on the plating).
	for sx in [-11.0, 11.0]:
		var strut_top := BRIDGE_V - 1.0
		var foot := pose.v_at(34.0, 116.0)
		if strut_top - foot < 1.5:
			continue
		_level(out, "bridge_strut_%d" % int(sx), Vector3(1.6, strut_top - foot, 1.6),
			Vector3(sx, (strut_top + foot) * 0.5, 116), "rib", pose)
	# Broken railings: runs of 6 m panels along the open edges, some missing,
	# some sagging. Each entry: id, from, to (x, floor v, w; x +-INF stops at that
	# side's plating), gaps (panel indexes knocked out).
	var rails: Array = [
		["starboard_deck_rail", Vector3(22, u, 186), Vector3(22, u, 232), [3, 6]],
		["starboard_deck_stern_rail", Vector3(22, u, 232), Vector3(29, u, 232), []],
		["upper_catwalk_bow_rail_s", Vector3(27, u, 178), Vector3(INF, u, 178), [1]],
		["upper_catwalk_bow_rail_sc", Vector3(5, u, 178), Vector3(19, u, 178), []],
		["upper_catwalk_bow_rail_pc", Vector3(-19, u, 178), Vector3(-5, u, 178), [0]],
		["upper_catwalk_bow_rail_p", Vector3(-INF, u, 178), Vector3(-27, u, 178), []],
		["upper_catwalk_stern_rail", Vector3(-12, u, 186), Vector3(22, u, 186), [3]],
		["port_deck_bow_rail", Vector3(-12, u, 186), Vector3(-12, u, 196), []],
		["port_deck_hole_rail", Vector3(-26, u, 196), Vector3(-12, u, 196), [1]],
		["port_deck_outer_rail", Vector3(-26, u, 196), Vector3(-26, u, 218.5), [2]],
		["port_deck_stern_rail", Vector3(-12, u, 218.5), Vector3(-12, u, 228), []],
		["port_deck_stern_end_rail", Vector3(-INF, u, 228), Vector3(-12, u, 228), [2]],
		["mid_catwalk_bow_rail", Vector3(-INF, m, 150), Vector3(INF, m, 150), [3, 8]],
		["mid_catwalk_stern_rail", Vector3(-19, m, 154), Vector3(19, m, 154), [4]],
		["starboard_ledge_rail", Vector3(27, m, 162), Vector3(27, m, 176), []],
		["starboard_ledge_stern_rail", Vector3(27, m, 176), Vector3(drop_hi - 4.0, m, 176), []],
		["port_ledge_rail", Vector3(-27, m, 162), Vector3(-27, m, 176), []],
		["port_ledge_stern_rail", Vector3(-drop_hi + 4.0, m, 176), Vector3(-27, m, 176), []],
		["starboard_balcony_rail", Vector3(20, l, 199.5), Vector3(20, l, 207), []],
		["starboard_balcony_bow_rail", Vector3(20, l, 199.5), Vector3(drop_lo - 4.0, l, 199.5), []],
		["starboard_balcony_stern_rail", Vector3(20, l, 207), Vector3(INF, l, 207), [1]],
		["port_balcony_rail", Vector3(-31, l, 199.5), Vector3(-31, l, 207), []],
		["port_balcony_stern_rail", Vector3(-INF, l, 207), Vector3(-31, l, 207), []],
		["bridge_port_rail", Vector3(-14, BRIDGE_V, 124), Vector3(-14, BRIDGE_V, 151), [2]],
		["bridge_starboard_rail", Vector3(14, BRIDGE_V, 124), Vector3(14, BRIDGE_V, 151), [1, 3]],
		["bridge_stern_rail_a", Vector3(-14, BRIDGE_V, 151), Vector3(-6, BRIDGE_V, 151), []],
		["bridge_stern_rail_b", Vector3(6, BRIDGE_V, 151), Vector3(14, BRIDGE_V, 151), [0]],
	]
	if c.has("climb"):
		# The climb ramp comes up onto the balcony's bow edge: its rail starts past it.
		rails[19][1] = Vector3(CLIMB_X + 4.0, l, 199.5)
	for r in rails:
		var from: Vector3 = r[1]
		var to: Vector3 = r[2]
		if not is_inf(from.x) and not is_inf(to.x) and from.distance_to(to) < 1.0:
			continue
		var gaps: Array = variant.get("rail_gaps", {}).get(str(r[0]), r[3])
		_railing(out, str(r[0]), from, to, gaps.map(func(i): return int(i)), pose)


## Wreck poses: what joins the rigid interior to this wreck's hull (design coordinates).
##   - "stern": the stern ramp's head on the hold floor. The original's leaves the
##     floor at stern_w and drops to the starboard deck; flatter, the floor at the
##     stern is lower than the deck, so the head moves aft until the ramp is no
##     steeper than MAX_RAMP_DEG (as far as FLOOR_END_Z). None where it never is.
##   - "climb": with no stern ramp, a ramp up the starboard side from the hold floor
##     to the low balcony's bow edge, at CLIMB_DEG; only where the floor is flat
##     enough for it to start aft of the breach.
##   - "gallery": the upper gallery's stern end, when the gallery ramp from it to
##     the port deck is no steeper than MAX_RAMP_DEG (else it has fallen).
##   - "drop_hi"/"drop_lo": the drops' x at the ledge and the balcony, pulled in from
##     the plating where the hull is narrower at those heights.
static func _connectors(pose: Pose, variant: Dictionary) -> Dictionary:
	var u := INTERIOR_V
	var out := {}
	var deck_end := Vector2(33, 232)
	var w := float(variant.get("stern_ramp_w", STERN_RAMP_W))
	while true:
		var head := Vector3(31, pose.v_at(DECK_Y, w), w)
		if pose.hull(head).z > FLOOR_END_Z:
			break
		var run := Vector2(head.x, head.z).distance_to(deck_end)
		if rad_to_deg(atan2(absf(head.y - u), run)) <= MAX_RAMP_DEG:
			out["stern"] = head
			break
		w += 1.0
	if not out.has("stern"):
		var top := Vector3(CLIMB_X, LOW_V, 199.5)
		var rise := top.y - pose.v_at(DECK_Y, top.z)
		var gain := tan(deg_to_rad(CLIMB_DEG)) - tan(pose.a)
		if rise > 0.0 and gain > 0.05:
			var foot_w := top.z - rise / gain
			var foot := Vector3(CLIMB_X, pose.v_at(DECK_Y, foot_w), foot_w)
			if pose.hull(foot).z > 100.0:
				out["climb"] = foot
	var g := pose.design(Vector3(-20, -3.3, 235))      # the upper gallery's stern end
	g.x = -20
	var to := Vector3(-20, u, 218.5)
	if rad_to_deg(atan2(absf(to.y - g.y), absf(to.z - g.z))) <= MAX_RAMP_DEG:
		out["gallery"] = g
	out["drop_hi"] = minf(39.0, _wall_x(MID_V + 1.7, 176, pose) - 5.0)
	out["drop_lo"] = minf(36.0, _wall_x(LOW_V + 1.7, 200, pose) - 5.0)
	return out


## The level frame's height and stern-ward distance of a hull-frame point
## (`w_override` keeps w and asks for the level v of hull-frame height y at x).
## Wreck poses: in the design coordinates of the pose's interior.
static func _level_v(hull: Vector3, pose: Pose, w_override: float = NAN) -> float:
	if not is_nan(w_override):
		return pose.v_at(hull.y, w_override)
	return pose.design(hull).y


static func _level_w(hull: Vector3, pose: Pose) -> float:
	return pose.design(hull).z


## The level height of the hold floor's top (hull height DECK_Y) at stern-ward
## distance w; wreck poses: in a wreck lying at pitch_deg with its decks dropped `drop`.
static func floor_v(w: float, pitch_deg: float = PITCH_DEG, drop: float = 0.0) -> float:
	return Pose.new(pitch_deg, drop).v_at(DECK_Y, w)


## How far out the hull plating's mid-line is at level height v, stern-ward w:
## the octagon's flank facets, then the steep dorsal/ventral ones.
static func _wall_x(v: float, w: float, pose: Pose) -> float:
	var y := absf(pose.hull_y(v, w))
	var corner := Vector2(cos(PI / 4.0) * HULL_RX, sin(PI / 4.0) * HULL_RY)
	if y <= corner.y:
		return HULL_RX - (HULL_RX - corner.x) * y / corner.y
	return corner.x * maxf(0.0, HULL_RY - y) / (HULL_RY - corner.y)


## A box placed in the level frame (center (x, v, w), its own `basis` in that
## frame), stored in the hull frame like every other part.
static func _level(out: Array, id: String, size: Vector3, center: Vector3, finish: String,
		pose: Pose, basis: Basis = Basis.IDENTITY) -> void:
	_part_box(out, id, size, pose.hull(center), finish, pose.to_hull * basis)


## A level floor `thick` metres thick with its top at v.
static func _slab(out: Array, id: String, xs: Vector2, ws: Vector2, v: float, pose: Pose,
		finish: String = "deck", thick: float = 1.0) -> void:
	_level(out, id, Vector3(xs.y - xs.x, thick, ws.y - ws.x),
		Vector3((xs.x + xs.y) * 0.5, v - thick * 0.5, (ws.x + ws.y) * 0.5), finish, pose)
	out[-1]["floor"] = true


## Wreck cleanup: a deck hung in the hull. An infinite x edge runs out to that
## side's plating: the slab stops where the plating is narrowest along it (into the
## plate, never through it), 3 m filler strips carry it on to the plating where the
## hull bulges, and diagonal braces under it bear on the wall.
static func _deck(out: Array, id: String, xs: Vector2, ws: Vector2, v: float, finish: String,
		pose: Pose) -> void:
	var thick := 0.5 if finish == "grate" else 1.0
	var reach := func(a: float, b: float) -> float:
		return minf(minf(_wall_x(v, a, pose), _wall_x(v, b, pose)),
			minf(_wall_x(v - thick, a, pose), _wall_x(v - thick, b, pose))) - 0.2
	var lo: float = -reach.call(ws.x, ws.y) if is_inf(xs.x) else xs.x
	var hi: float = reach.call(ws.x, ws.y) if is_inf(xs.y) else xs.y
	_slab(out, id, Vector2(lo, hi), ws, v, pose, finish, thick)
	var strips := ceili((ws.y - ws.x) / 3.0)
	for side in [-1, 1]:
		if not is_inf(xs.x if side < 0 else xs.y):
			continue
		var edge := absf(lo if side < 0 else hi)
		for i in strips:
			var a := lerpf(ws.x, ws.y, float(i) / strips)
			var b := lerpf(ws.x, ws.y, float(i + 1) / strips)
			var out_to: float = reach.call(a, b)
			if out_to - edge > 0.3:
				var span := Vector2(edge, out_to) if side > 0 else Vector2(-out_to, -edge)
				_slab(out, "%s_fill_%s%d" % [id, "s" if side > 0 else "p", i], span, Vector2(a, b), v, pose, finish, thick)
		if xs.x == -INF and xs.y == INF:
			continue                 # a catwalk spans wall to wall; it needs no braces
		var length := ws.y - ws.x
		for f: float in ([0.5] if length < 12.0 else [0.25, 0.75]):
			var w := ws.x + length * f
			var drop := 5.5
			var head := Vector3(side * (edge - 6.0), v - thick, w)
			var foot := Vector3(side * (_wall_x(v - drop, w, pose) - 0.6), v - drop, w)
			var run := foot - head
			_level(out, "%s_brace_%d" % [id, int(f * 100)], Vector3(run.length(), 0.7, 0.9),
				(head + foot) * 0.5, "rib", pose, Basis(Vector3.BACK, atan2(run.y, run.x)))


## A straight ramp whose top runs from a to b (level frame), `width` wide.
static func _ramp(out: Array, id: String, a: Vector3, b: Vector3, width: float, pose: Pose) -> void:
	if b.z < a.z:
		var t := a
		a = b
		b = t
	var run := b - a
	var flat := Vector2(run.x, run.z).length()
	var basis := Basis(Vector3.UP, atan2(run.x, run.z)) * Basis(Vector3.RIGHT, -atan2(run.y, flat))
	_level(out, id, Vector3(width, 1.0, run.length() + 0.6),
		(a + b) * 0.5 - basis.y * 0.5, "ramp", pose, basis)
	out[-1]["floor"] = true


## The level-plane unit vector across a ramp from a to b, on its edge toward x sign `toward`.
static func _ramp_side(a: Vector3, b: Vector3, toward: float) -> Vector3:
	var across := Vector3.UP.cross(Vector3(b.x - a.x, 0, b.z - a.z)).normalized()
	return across if across.x * toward > 0.0 else -across


## A railing along a floor edge from `from` to `to` (x, floor v, w; level frame;
## an infinite x stops short of that side's plating), a top rail and a post per
## 6 m panel, 1.1 m high. It follows a ramp's slope when the two v differ.
## Knocked-out panels leave a gap; every third standing one sags outward.
static func _railing(out: Array, id: String, from: Vector3, to: Vector3, gaps: Array,
		pose: Pose) -> void:
	if is_inf(from.x):
		from.x = signf(from.x) * (_wall_x(from.y + 1.0, from.z, pose) - 1.6)
	if is_inf(to.x):
		to.x = signf(to.x) * (_wall_x(to.y + 1.0, to.z, pose) - 1.6)
	var span := to - from
	var panels := maxi(1, int(round(span.length() / 6.0)))
	var along := span.normalized()
	var across := Vector3.UP.cross(along).normalized()
	var rail_basis := Basis(across, along.cross(across), along)
	for i in panels:
		if i in gaps:
			continue
		var a := from + span * (float(i) / panels)
		var b := from + span * (float(i + 1) / panels)
		var sag := Basis(along, deg_to_rad(18.0)) if i % 3 == 2 else Basis.IDENTITY
		_level(out, "%s_%d" % [id, i], Vector3(0.16, 0.12, (b - a).length()), (a + b) * 0.5 + Vector3(0, 1.05, 0),
			"marking", pose, sag * rail_basis)
		_level(out, "%s_post_%d" % [id, i], Vector3(0.16, 1.1, 0.16), a + Vector3(0, 0.55, 0),
			"rib", pose)


static func _facet(out: Array, id: String, rx: float, ry: float, facet: int,
		z: float, length: float, thickness: float, finish: String) -> void:
	var a := TAU * facet / 8.0
	var b := TAU * (facet + 1) / 8.0
	var p := Vector3(cos(a) * rx, sin(a) * ry, z)
	var q := Vector3(cos(b) * rx, sin(b) * ry, z)
	var edge := q - p
	_part_box(out, id, Vector3(edge.length() + 0.5, thickness, length), (p + q) * 0.5,
		finish, Basis(Vector3.BACK, atan2(edge.y, edge.x)))


static func _part_box(out: Array, id: String, size: Vector3, center: Vector3,
		finish: String, basis: Basis = Basis.IDENTITY) -> void:
	out.append({ "id": id, "size": size, "xf": Transform3D(basis, center), "finish": finish })


static func _engine_ring(out: Array, id: String, center: Vector3, radius: float,
		thickness: float, length: float, finish: String) -> void:
	for i in 16:
		var a := TAU * i / 16.0
		var b := TAU * (i + 1) / 16.0
		var p := Vector3(cos(a), sin(a), 0) * radius
		var q := Vector3(cos(b), sin(b), 0) * radius
		var edge := q - p
		_part_box(out, id + "_%d" % i, Vector3(edge.length() + 0.12, thickness, length),
			center + (p + q) * 0.5, finish, Basis(Vector3.BACK, atan2(edge.y, edge.x)))


static func _shard(out: Array, id: String, size: Vector3, center: Vector3,
		finish: String, basis: Basis) -> void:
	_part_box(out, id, size, center, finish, basis)
	out[-1]["shard"] = true


## A chisel-pointed plate, shared by the visible mesh and its convex foot collider.
## WorldGround retains its small conservative oriented bounds for flight hits.
static func shard_vertices(size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	var points := PackedVector3Array()
	for y in [-h.y, h.y]:
		for p in [Vector3(-h.x, y, -h.z), Vector3(h.x, y, -h.z),
				Vector3(h.x, y, -0.1 * h.z), Vector3(-0.3 * h.x, y, h.z)]:
			points.append(p)
	return points


static func shard_mesh(size: Vector3) -> ArrayMesh:
	var points := shard_vertices(size)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
			[1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(points[face[i]])
	st.generate_normals()
	return st.commit()
