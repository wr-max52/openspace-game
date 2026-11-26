class_name GlobeMap
extends RefCounted
## The F11 Map page's places and the waypoint it sets. Pure and static, like
## Objective: it reads the world's data and WorldState, and the page (GlobeView)
## draws it.
##
## Only what stays put: the port, the world's landmarks (outposts, droid relays,
## traders, wrecks), the planet's native camps and, zoomed in, the port's own
## stops (the cantina, the ship dealer, the stalls). Each pin is
## { id, kind, label, map: Vector2, arrive, town }: map coordinates, metres along
## the ground from the port (PlanetSphere), so a pin sits exactly where the
## landmark is built.
##
## Who holds a place (Territory): the Remnant's outposts and the port's barracks
## also carry { owner, short, hold, status }. The globe draws what the locals hold
## green (yellow-green and "Resupply needed" while their supplies run short), a
## ring round a held outpost for the time left (`hold`, 0..1, -1 = none; issue
## #425: the Remnant's too once the cruiser has fallen, orange while they run
## short and you could resupply them), and
## `status` joins the name on hover. Read when the pins are built, which the page
## does each time it opens.
##
## Off planet: every planet you can fly to from here (SpaceTravel's bodies),
## every Remnant cruiser in the system and every space station, as { id, kind,
## label, target }.
##
## A space station (StationHull) shows as its own pin on its planet's globe
## (kind "station", in place of the port where the planet's town is the station's
## bay) and as a badge on the system chart; either opens its side view
## (StationMapView: orbital_pins), where a floor or the bay is a waypoint
## ("station:<place>").
##
## The waypoint lives in WorldState.map_waypoint (saved): { id, label, target,
## planet, arrive }. One pointer at a time: setting it turns any quest's waypoint
## off, and switching a quest's on clears it (Quests.toggle_waypoint). Its target
## is a word ObjectiveHud.where understands: map:<x>,<z>, planet:<id>, cruiser,
## station:<place>.
##
## The page can also show somewhere you are not (GlobeMap.other_planet: another
## planet's ball, from its data; CruiserMapView: the Remnant cruiser's side view,
## cruiser_pins). A waypoint set there keeps its own planet: until you are on it
## the pointer leads to that planet ("planet:<id>"), then to the place itself.
##
## Every line and label: content/core/flow/map.json.

const PATH := "res://content/core/flow/map.json"
const LOOK_PATH := "res://content/look/map.json"
const LOCATION_DIR := "res://content/core/locations"
const VENDOR_DIR := "res://content/core/vendors"
const ITEMS_LOOK_PATH := "res://content/look/items.json"
const CoreContent := preload("res://src/systems/dataload/core_content.gd")

static var _cfg: Dictionary = {}
static var _look: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = _read(PATH)
	return _cfg


static func look() -> Dictionary:
	if _look.is_empty():
		_look = _read(LOOK_PATH)
	return _look


static func line(key: String) -> String:
	return str(cfg().get("lines", {}).get(key, ""))


static func kind_cfg(kind: String) -> Dictionary:
	return cfg().get("kinds", {}).get(kind, {})


# ------------------------------------------------------------------ pins

## Every pin on this planet's surface. `world` is the scene's world (landmarks
## already laid out for its town), `planet` the planet (its native packs),
## `town` the port's own stops (town_pins).
static func pins(world: Dictionary, planet: Dictionary, town: Array = []) -> Array:
	var front := Territory.front_for_planet(str(planet.get("id", world.get("planet", ""))))
	var out: Array = []
	# A space station's pin where it hangs (orbital_pins: click it to open its side
	# view). Where the planet's town is the station's bay (the ringed giant's
	# "station_town"), the station stands in for the port.
	var station_town := str(planet.get("town", {}).get("station_town", ""))
	for lm in StationHull.landmarks(world):
		if not lm.has("at"):
			continue
		var at: Array = lm.at
		var sp := _pin("station_" + str(lm.get("id", "")), "station", station_label({ "id": str(lm.get("id", "")), "station": str(lm.get("station", "")) }),
			Vector2(float(at[0]), float(at[2])))
		sp["view"] = "station:" + str(planet.get("id", world.get("planet", "")))
		out.append(sp)
	if station_town == "" or out.is_empty():
		var port := _pin("port", "port", _kind_label("port"), Vector2.ZERO)
		_stamp_owner(port, Territory.barracks_of(front))
		out.push_front(port)
	out.append_array(station_pins(planet, front))
	var skip: Array = cfg().get("skip", [])
	for lm in world.get("landmarks", []):
		var id := str(lm.get("id", ""))
		if id in skip or not lm.has("at"):
			continue
		var kind := str(lm.get("kind", ""))
		var label := ""
		if kind == "location":
			var loc := _location(str(lm.get("location", id)))
			kind = str(loc.get("kind", "post"))
			label = str(loc.get("label", ""))
		if kind_cfg(kind).is_empty() or kind in ["cruiser", "planet", "port", "station"]:
			continue             # the cruiser is off planet, the station has its own pin; anything unnamed is not a place
		label = str(cfg().get("labels", {}).get(id, label if label != "" else _kind_label(kind)))
		var at: Array = lm.at
		var pin := _pin(id, kind, _cap(label), Vector2(float(at[0]), float(at[2])))
		if Territory.outposts(front).has(id):
			_stamp_owner(pin, id)
		out.append(pin)
	for pack in planet.get("natives", {}).get("packs", []):
		var camp = pack.get("camp", null)
		var at = camp.get("at", null) if camp is Dictionary else null
		if not (at is Array or at is Vector2):
			continue
		var p := _pin("camp_" + str(pack.id), "camp", str(cfg().get("camp_label", "%s")) % str(pack.get("label", pack.id)),
			at if at is Vector2 else Vector2(float(at[0]), float(at[1])))
		p["hostile"] = str(pack.get("attitude", "")) == "hostile"
		out.append(p)
	out.append_array(race_pins(str(world.get("id", "")), world))
	out.append_array(place_pins(world))
	for t in town:
		out.append(t)
	return out


## Issue #615: the speeder races you have heard of, where the crew's leader stands
## (you talk to them to race; the start line stays empty until you do). Map
## coordinates: plateau x,z like the landmarks. Without `world` (or the crew's
## hangout in it), the course's start line.
static func race_pins(world_id: String, world: Dictionary = {}) -> Array:
	var out: Array = []
	if kind_cfg("race").is_empty():
		return out
	for c in RaceCrew.crews_for(world_id):
		if not RaceCrew.heard_of(c):
			continue
		var course := RaceCourse.load_course(str(c.get("course", "")))
		var at := crew_spot(c, world)
		if at == Vector2.INF:
			var gates: Array = course.get("gates", [])
			if gates.is_empty():
				continue
			at = Vector2(float(gates[0].at[0]), float(gates[0].at[1]))
		out.append(_pin("race_" + str(c.id), "race", _cap(str(course.get("label", c.id))), at))
	return out


## Where crew `c`'s leader stands, in map coordinates (RaceCrew._find_hangout's
## frame: the landmark turned by its yaw_deg), or Vector2.INF if `world` has no
## such landmark.
static func crew_spot(c: Dictionary, world: Dictionary) -> Vector2:
	var near := str(c.get("hangout", {}).get("near", ""))
	for lm in world.get("landmarks", []):
		if near == "" or (str(lm.get("location", "")) != near and str(lm.get("id", "")) != near) or not lm.has("at"):
			continue
		var racers: Array = c.get("racers", [])
		var stand := RaceCrew._v2(racers[0].get("stand", [0, 0])) if not racers.is_empty() else Vector2.ZERO
		for rc in racers:
			if bool(rc.get("leader", false)):
				stand = RaceCrew._v2(rc.get("stand", [0, 0]))
				break
		var local := Basis(Vector3.UP, deg_to_rad(float(lm.get("yaw_deg", 0.0)))) * Vector3(stand.x, 0.0, stand.y)
		return Vector2(float(lm.at[0]) + local.x, float(lm.at[2]) + local.z)
	return Vector2.INF


## A sealed station's places past its first dome (the moon's): the landing pit and
## each dome off it ("Barracks", "Homes"), at their middles. The barracks' pin says
## who holds it. Town coordinates are map coordinates on the station's plateau.
static func station_pins(planet: Dictionary, front: String = Territory.HOME) -> Array:
	var out: Array = []
	var st: Dictionary = planet.get("town", {}).get("station", {})
	if st.is_empty() or (st.get("domes", []) as Array).is_empty():
		return out
	var pc: Array = st.get("pit", {}).get("center", [0, 0, 0])
	out.append(_pin("station_bay", "bay", _kind_label("bay"), Vector2(float(pc[0]), float(pc[2]))))
	for d in st.get("domes", []):
		var kind := str(d.get("fill", "dome"))
		if kind_cfg(kind).is_empty():
			kind = "dome"
		var c: Array = d.get("center", [0, 0, 0])
		var pin := _pin("station_" + str(d.id), kind, _kind_label(kind), Vector2(float(c[0]), float(c[2])))
		if kind == "barracks":
			_stamp_owner(pin, Territory.barracks_of(front))
		out.append(pin)
	return out


## The station's outline for the globe to draw under its pins: each dome as a
## circle and each tunnel as a band, in map metres:
## [{ kind: "dome", map, r }, { kind: "tunnel", a, b, w }].
static func station_shapes(planet: Dictionary) -> Array:
	var out: Array = []
	var st: Dictionary = planet.get("town", {}).get("station", {})
	if st.is_empty():
		return out
	var rc: Array = st.get("center", [0, 0, 0])
	var c0 := Vector2(float(rc[0]), float(rc[2]))
	out.append({ "kind": "dome", "map": c0, "r": float(st.get("radius", 36.0)) })
	var pc: Array = st.get("pit", {}).get("center", [0, 0, 0])
	var pit := Vector2(float(pc[0]), float(pc[2]))
	var pr := float(st.get("pit", {}).get("radius", 28.0))
	out.append({ "kind": "pit", "map": pit, "r": pr })
	var hall: Dictionary = st.get("hall", {})
	if not hall.is_empty():
		out.append({ "kind": "tunnel", "a": Vector2(float(hall.x0), c0.y), "b": Vector2(float(hall.rim), c0.y), "w": float(hall.half) * 2.0 })
	for d in st.get("domes", []):
		var c: Array = d.get("center", [0, 0, 0])
		var dm := Vector2(float(c[0]), float(c[2]))
		var hb: Dictionary = d.get("hall", {})
		var dir := Vector2(float(hb.dir[0]), float(hb.dir[1]))
		out.append({ "kind": "dome", "map": dm, "r": float(d.get("radius", 36.0)) })
		out.append({ "kind": "tunnel", "a": pit + dir * float(hb.rim), "b": pit + dir * float(hb.far), "w": float(hb.half) * 2.0 })
	return out


## The port's own stops in a built town: the data's markers (the cantina, its
## owner, the ship dealer, the droid merchant), the barracks, this town's vendors
## (each an icon for what it sells: content/look/items.json "stalls"), and every
## free market stall a player can make a keeper for: "Build an NPC", or the name of
## the keeper made for it (merged, else your draft's). `to_map` turns a world
## position into map (x, z).
static func town_pins(town, town_id: String, to_map: Callable, planet_id: String = "") -> Array:
	var out: Array = []
	if town == null:
		return out
	if planet_id == "":
		planet_id = GameFlow.current_planet_id()
	var front := Territory.front_for_planet(planet_id)
	var stops: Array = cfg().get("town", []).duplicate()
	for v in _vendors():
		if str(v.get("location", "")) == town_id:
			stops.append({ "marker": str(v.get("marker", "")), "kind": vendor_kind(str(v.get("id", ""))), "label": str(v.get("label", "")) })
	var seen := {}
	for s in stops:
		if s.has("zone"):
			var c = _zone_middle(town, str(s.zone), to_map)
			if c == null:
				continue
			var zp := _pin("town_" + str(s.zone), str(s.get("kind", "barracks")), str(s.get("label", s.zone)), c)
			zp["town"] = true
			if zp.kind == "barracks":
				_stamp_owner(zp, Territory.barracks_of(front))
			out.append(zp)
			continue
		var m := str(s.get("marker", ""))
		if m == "" or seen.has(m) or town.get_marker(m).is_empty():
			continue
		seen[m] = true
		var label := str(s.get("label", m))
		if str(s.get("kind", "")) == "cantina_owner":
			label = cantina_owner_label(planet_id)
		var p := _pin("town_" + m, str(s.get("kind", "vendor")), label, to_map.call(town.marker_pos(m)))
		p["town"] = true
		out.append(p)
	for fs in free_stall_pins(town, town_id, to_map):
		if not seen.has(str(fs.id).trim_prefix("town_")):
			out.append(fs)
	# Issue #617: the row outside the back gate where your speeders wait, once you own one.
	if WorldState.count("speeders_owned") > 0 and not kind_cfg("speeders").is_empty() and town.has_method("markers_with_role"):
		var row: Array = town.markers_with_role("speeder_spot")
		if not row.is_empty():
			row.sort_custom(func(a, b): return str(a.id).naturalnocasecmp_to(str(b.id)) < 0)
			var sp := _pin("town_speeders", "speeders", _kind_label("speeders"), to_map.call(town.marker_pos(str(row[0].id))))
			sp["town"] = true
			out.append(sp)
	return out


## Issue #147's free market stalls (CommunityNpc.free_stalls) as pins: "Build an
## NPC" where nobody keeps it yet, else the keeper's name (a merged keeper's, or
## the one you gave the draft you are making for that stall).
static func free_stall_pins(town, town_id: String, to_map: Callable) -> Array:
	var out: Array = []
	if town == null or not town.has_method("markers") or kind_cfg("free_stall").is_empty():
		return out
	var stalls := CommunityNpc.free_stalls(town, town_id, CoreContent.shared())
	var keepers := CommunityNpc.assign(CommunityNpc.in_town(town_id), stalls)
	for m in stalls:
		var label := line("build_npc")
		var kind := "free_stall"
		if keepers.has(m):
			label = CommunityNpc.display_name(keepers[m])
			kind = "keeper"
		else:
			var d := CommunityNpc.load_draft(town_id, str(m))
			if str(d.get("name", "")).strip_edges() != "":
				label = str(d.name).strip_edges()
				kind = "keeper"
		var p := _pin("town_" + str(m), kind, label, to_map.call(town.marker_pos(str(m))))
		p["town"] = true
		out.append(p)
	return out


## The pin kind for a vendor: what its stall shows (content/look/items.json
## "stalls": food, gear, contraband, droids), as map.json "wares_kinds" names it.
static func vendor_kind(vendor_id: String) -> String:
	var named: Dictionary = cfg().get("vendor_kinds", {})
	if named.has(vendor_id):
		return str(named[vendor_id])
	var wares := str(_stall_looks().get(vendor_id, {}).get("wares", ""))
	return str(cfg().get("wares_kinds", {}).get(wares, "vendor"))


## The cantina owner's pin name: their name once this save has given them one
## (the port's Oda, or a planet's own owner: PlanetOwner).
static func cantina_owner_label(planet_id: String) -> String:
	var key := "npc:cantina_owner" if planet_id == PlanetGen.home_id() else "npc:" + PlanetOwner.card_id(planet_id)
	var n := str(WorldState.names.by_key.get(key, "")) if WorldState.names != null else ""
	return line("owner_named") % n if n != "" else _kind_label("cantina_owner")


## The middle of the biggest solid block in a town zone (the barracks' hall), as
## map (x, z); null when the town has no such zone.
static func _zone_middle(town, zone: String, to_map: Callable):
	var best := {}
	var best_a := -1.0
	for b in town.boxes():
		if str(b.get("zone", "")) != zone or str(b.get("kind", "")) != "solid":
			continue
		var a := absf((float(b.max[0]) - float(b.min[0])) * (float(b.max[2]) - float(b.min[2])))
		if a > best_a:
			best_a = a
			best = b
	if best.is_empty():
		for z in town.zones():
			if str(z.get("id", "")) == zone:
				return to_map.call(Vector3((float(z.min[0]) + float(z.max[0])) * 0.5, 0.0, (float(z.min[1]) + float(z.max[1])) * 0.5))
		return null
	return to_map.call(Vector3((float(best.min[0]) + float(best.max[0])) * 0.5, 0.0, (float(best.min[2]) + float(best.max[2])) * 0.5))


# ------------------------------------------------------------------ details

## A place's insides for the map zoomed in: { id, center (map), extent (m, its
## half width), tris (map-space triangles of its buildings' footprints), cols,
## walls: [PackedVector2Array] (map-space lines) }. The globe fills the tris flat
## once the place is big enough on screen (map.json "details").
static func _place(id: String, center: Vector2, extent: float) -> Dictionary:
	return { "id": id, "center": center, "extent": extent, "tris": PackedVector2Array(), "cols": PackedColorArray(), "walls": [] }


## The town's buildings, seen from above: every box but floors and lamps as its
## real footprint (turned boxes turned, round ones round), the barracks tinted by
## who holds them, and the town wall as a line with its gates open. `to_map` as
## town_pins.
static func town_details(town, to_map: Callable, front: String = Territory.HOME) -> Dictionary:
	if town == null or not town.has_method("boxes"):
		return {}
	var d: Dictionary = look().get("details", {})
	var bounds: Dictionary = town.data.get("bounds", {}) if town.get("data") is Dictionary else {}
	var lo := Vector2(-150, -150)
	var hi := Vector2(150, 150)
	if bounds.has("min"):
		lo = Vector2(float(bounds.min[0]), float(bounds.min[1]))
		hi = Vector2(float(bounds.max[0]), float(bounds.max[1]))
	var mid := (lo + hi) * 0.5
	var c: Vector2 = to_map.call(Vector3(mid.x, 0.0, mid.y))
	var out := _place("town", c, maxf(hi.x - lo.x, hi.y - lo.y) * 0.5)
	var barracks := Color(str(d.get("barracks", "#8a3a2a")))
	if Territory.owner(Territory.barracks_of(front)) == Territory.LOCALS:
		barracks = Color(str(look().get("owners", {}).get("locals", "#5fd35f"))).darkened(0.35)
	var skip_k: Array = d.get("skip_kinds", [])
	var skip_l: Array = d.get("skip_looks", [])
	var boxes: Array = town.boxes().duplicate()
	boxes.sort_custom(func(a, b): return _layer(a) < _layer(b))
	for b in boxes:
		var kind := str(b.get("kind", ""))
		var lk := str(b.get("look", ""))
		if kind in skip_k or lk in skip_l:
			continue
		var mn := Vector2(float(b.min[0]), float(b.min[2]))
		var mx := Vector2(float(b.max[0]), float(b.max[2]))
		if kind == "ring" and bool(b.get("hollow", false)):
			_ring_wall(out, b, mn, mx, to_map)
			continue
		var col := _box_color(b, d, barracks)
		var ring: PackedVector2Array
		var ctr := (mn + mx) * 0.5
		if str(b.get("shape", "")) == "round" or kind in ["ring", "bowl"]:
			ring = _ellipse(ctr, (mx - mn) * 0.5, 16)
		elif b.has("turn_deg") and b.has("fit"):
			ring = _turned_rect(ctr, Vector2(float(b.fit[0]), float(b.fit[1])) * 0.5, float(b.turn_deg))
		else:
			ring = PackedVector2Array([mn, Vector2(mx.x, mn.y), mx, Vector2(mn.x, mx.y)])
		var on_map := PackedVector2Array()
		for q in ring:
			on_map.append(to_map.call(Vector3(q.x, 0.0, q.y)))
		_fill(out, on_map, col)
	return out


## Every location's buildings (the ranches' houses, walls and stands, the
## outposts' blocks, the droid relays' huts, Skrugs's yard) round each landmark,
## turned by its yaw: [place]. Landmark coordinates are map coordinates.
static func place_details(world: Dictionary) -> Array:
	var out: Array = []
	var d: Dictionary = look().get("details", {})
	for lm in world.get("landmarks", []):
		if str(lm.get("kind", "")) != "location" or not lm.has("at"):
			continue
		var loc := _location(str(lm.get("location", lm.get("id", ""))))
		var blds: Array = loc.get("buildings", [])
		if blds.is_empty():
			continue
		var at := Vector2(float(lm.at[0]), float(lm.at[2]))
		var yaw := float(lm.get("yaw_deg", 0.0))
		var p := _place(str(lm.get("id", "")), at, 10.0)
		var reach := 6.0
		for b in blds:
			if str(b.get("shape", "box")) != "box" or not b.has("size") or not b.has("position"):
				continue
			var sz := Vector2(float(b.size[0]), float(b.size[2]))
			var pos := Vector2(float(b.position[0]), float(b.position[2]))
			var ring := _turned_rect(pos, sz * 0.5, float(b.get("yaw_deg", 0.0)))
			var on_map := PackedVector2Array()
			for q in ring:
				reach = maxf(reach, q.length())
				on_map.append(at + _turn(q, yaw))
			_fill(p, on_map, _box_color({ "look": str(b.get("look", "")), "kind": "solid" }, d, Color(str(d.get("barracks", "#8a3a2a")))))
		p.extent = reach
		out.append(p)
	return out


## The stands in every ranch (location "stalls"), each where its stand is built,
## named and drawn for what it sells: pins that show once the ranch is zoomed
## into (`detail`: the landmark id).
static func place_pins(world: Dictionary) -> Array:
	var out: Array = []
	for lm in world.get("landmarks", []):
		if str(lm.get("kind", "")) != "location" or not lm.has("at"):
			continue
		var loc := _location(str(lm.get("location", lm.get("id", ""))))
		var stalls: Dictionary = loc.get("stalls", {})
		if stalls.is_empty():
			continue
		var at := Vector2(float(lm.at[0]), float(lm.at[2]))
		var yaw := float(lm.get("yaw_deg", 0.0))
		var where := {}
		for b in loc.get("buildings", []):
			where[str(b.get("id", ""))] = Vector2(float(b.position[0]), float(b.position[2])) if b.has("position") else Vector2.ZERO
		for sid in stalls:
			var s: Dictionary = stalls[sid]
			var kind := "droids" if bool(s.get("droid", false)) else vendor_kind(str(s.get("vendor", "")))
			var label := str(s.get("label", ""))
			if label == "":
				label = str(_vendor(str(s.get("vendor", ""))).get("label", _kind_label(kind)))
			var p := _pin(str(lm.id) + "_" + str(sid), kind, label, at + _turn(where.get(str(sid), Vector2.ZERO), yaw))
			p["detail"] = str(lm.id)
			out.append(p)
	return out


## Mountains, spires and boulders where DesertLandforms puts them on this planet
## (its own spots, so each mark is the rock you can walk to): [{ kind, map, size
## (m) }]. Boulders only on the planet you are on (`boulders`: map positions and
## sizes, from the built scene).
static func terrain_marks(planet: Dictionary, sphere: PlanetSphere, boulders: Array = []) -> Array:
	var out: Array = []
	if sphere == null:
		return out
	var id := str(planet.get("id", ""))
	if "landforms" in planet.get("features", []):
		var data := DesertLandforms.load_data()
		if DesertLandforms.mesa_planet == id and not DesertLandforms.mesa_spots.is_empty():
			for m in DesertLandforms.mesa_spots:
				out.append({ "kind": "mountain", "map": m.map, "size": float(m.radius) })
		else:
			for m in DesertLandforms.mountain_spots(data, sphere):
				out.append({ "kind": "mountain", "map": m.map, "size": float(m.get("plan", {}).get("radius", 60.0)) })
		for s in DesertLandforms.spire_spots(data, sphere):
			out.append({ "kind": "spire", "map": s.map, "size": float(s.radius) })
		for s in DesertLandforms.short_spots(data, sphere):
			out.append({ "kind": "spire", "map": s.map, "size": float(s.radius) })
	for b in boulders:
		out.append({ "kind": "boulder", "map": b.map, "size": float(b.get("size", 2.0)) })
	return out


static func _layer(b: Dictionary) -> int:
	match str(b.get("kind", "")):
		"bowl":
			return 0
		"pad", "ring", "ramp":
			return 1
		"ship":
			return 3
	return 2


static func _box_color(b: Dictionary, d: Dictionary, barracks: Color) -> Color:
	var lk := str(b.get("look", ""))
	var kind := str(b.get("kind", ""))
	var zone := str(b.get("zone", ""))
	var c: Color
	if zone == "barracks" and kind == "solid" or lk == "watchtower":
		c = barracks
	elif zone == "cantina" and kind != "counter":
		c = Color(str(d.get("cantina", "#b8a070")))
	elif d.get("by_look", {}).has(lk):
		c = Color(str(d.by_look[lk]))
	elif d.get("by_kind", {}).has(kind):
		c = Color(str(d.by_kind[kind]))
	else:
		c = Color(str(d.get("default", "#7a6a52")))
	c.a = float(d.get("alpha", 0.92))
	return c


## A hollow ring (the round town's wall) as lines round its middle, open at its
## gaps (ring_wall.gd: 0 deg is +X, +deg toward +Z, "half" metres either side).
static func _ring_wall(out: Dictionary, b: Dictionary, mn: Vector2, mx: Vector2, to_map: Callable) -> void:
	var ctr := (mn + mx) * 0.5
	var rm := (mx.x - mn.x) * 0.5 - float(b.get("thickness", 2.0)) * 0.5
	var gaps: Array = []
	for g in b.get("gaps", []):
		gaps.append([deg_to_rad(float(g.get("deg", 0.0))), asin(clampf(float(g.get("half", 1.0)) / rm, 0.0, 1.0))])
	var run := PackedVector2Array()
	var n := 96
	for k in n + 1:
		var a := TAU * k / n
		var open := false
		for g in gaps:
			if absf(wrapf(a - float(g[0]), -PI, PI)) < float(g[1]):
				open = true
		if open:
			if run.size() > 1:
				out.walls.append(run)
			run = PackedVector2Array()
			continue
		run.append(to_map.call(Vector3(ctr.x + cos(a) * rm, 0.0, ctr.y + sin(a) * rm)))
	if run.size() > 1:
		out.walls.append(run)


static func _fill(out: Dictionary, ring: PackedVector2Array, col: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(ring)
	if idx.is_empty():
		return
	var t: PackedVector2Array = out.tris
	var c: PackedColorArray = out.cols
	for i in idx:
		t.append(ring[i])
		c.append(col)
	out.tris = t
	out.cols = c


static func _ellipse(c: Vector2, half: Vector2, segs: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in segs:
		var a := TAU * k / segs
		out.append(c + Vector2(cos(a) * half.x, sin(a) * half.y))
	return out


## A box `half` wide either way round `c`, turned like Basis(UP, deg) turns it.
static func _turned_rect(c: Vector2, half: Vector2, deg: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		out.append(c + _turn(q, deg))
	return out


## (x, z) turned by Basis(Vector3.UP, deg), as a landmark's yaw_deg turns its pieces.
static func _turn(v: Vector2, deg: float) -> Vector2:
	var w := Basis(Vector3.UP, deg_to_rad(deg)) * Vector3(v.x, 0.0, v.y)
	return Vector2(w.x, w.z)


# ------------------------------------------------------------------ vehicles

## The vehicle kinds, in the legend's order: your ships and speeders, then the
## enemy's (the Remnant's).
const VEHICLE_KINDS := ["ship_yours", "speeder_yours", "ship_enemy", "speeder_enemy"]


## Every vehicle in this scene the map shows, wherever it is now: [{ id, kind,
## label, pos (world) }]. Yours: the ships you own (Fleet, ShipPilot's berths with
## a key: parked, flown, or flying itself to you on a call) and the speeders you
## own (SpeederPost.speeders). The enemy's: the Remnant interceptor (AtmoFighter,
## unless shot down), the ships parked at the Remnant's outposts (not the one you
## stole), and, while the Remnant hold the town, the gate speeders and the chase
## speeder (GateChase). Ids stay the same while the scene lives, so a waypoint on
## one follows it (target "vehicle:<id>", vehicle_pos).
static func vehicles(demo) -> Array:
	var out: Array = []
	if demo == null or not is_instance_valid(demo):
		return out
	var pilot = demo.get("pilot")
	var f = demo.get("interceptor")
	var fighter: AtmoFighter = f if f is AtmoFighter and is_instance_valid(f) and f.atmo != null else null
	var seen := {}
	if pilot != null and is_instance_valid(pilot):
		for i in pilot.berths.size():
			var b: Dictionary = pilot.berths[i]
			if fighter != null and i == fighter.berth:
				continue             # the interceptor on its pad: listed below, under one id wherever it is
			if bool(b.get("destroyed", false)) or b.has("hijacked_by") or not (b.get("visual") is Node3D) or not is_instance_valid(b.visual):
				continue
			var label := str(b.get("cfg", {}).get("label", str(b.get("ship_id", "")).capitalize()))
			var key := str(b.get("key", ""))
			if key != "":
				out.append({ "id": "ship_" + key, "kind": "ship_yours", "label": line("your_vehicle") % label, "pos": (b.visual as Node3D).global_position })
			elif b.has("outpost") and not bool(b.get("stolen", false)) and not bool(b.get("borrowed", false)):
				# a place with more than one (the cruiser's bay): the second is "<place>_2"
				var id := "outship_" + str(b.outpost)
				seen[id] = int(seen.get(id, 0)) + 1
				if int(seen[id]) > 1:
					id += "_%d" % int(seen[id])
				out.append({ "id": id, "kind": "ship_enemy", "label": label, "pos": (b.visual as Node3D).global_position })
	if fighter != null and fighter.mode != AtmoFighter.Mode.DOWN and not (fighter.berth >= 0 and bool(pilot.berths[fighter.berth].get("destroyed", false))):
		out.append({ "id": "fighter", "kind": "ship_enemy", "label": str(fighter.cfg.get("label", "")), "pos": fighter.position() })
	var mine: Array = []
	var post = demo.get("speeder_post")
	if post != null and is_instance_valid(post):
		for s in post.speeders:
			if s is SpeederNode and is_instance_valid(s) and not s.is_queued_for_deletion():
				mine.append(s)
				out.append({ "id": "speeder_%d" % s.get_instance_id(), "kind": "speeder_yours",
					"label": line("your_vehicle") % str(s.cfg.get("label", "")), "pos": s.global_position })
	if GateChase.holder() == Territory.REMNANT:
		var theirs: Array = []
		var gate = demo.get("gate_speeders")
		if gate is Array:
			theirs.append_array(gate)
		var gc = demo.get("gate_chase")
		if gc != null and is_instance_valid(gc) and gc.chaser != null:
			theirs.append(gc.chaser)
		for s in theirs:
			if not (s is SpeederNode) or not is_instance_valid(s) or s.is_queued_for_deletion() or s in mine or s.riding \
					or (gc != null and is_instance_valid(gc) and s == gc.stolen):     # the one you took: not theirs any more
				continue
			out.append({ "id": "speeder_%d" % s.get_instance_id(), "kind": "speeder_enemy",
				"label": line("enemy_vehicle") % str(s.cfg.get("label", "")), "pos": s.global_position })
	return out


## The vehicles as map pins (vehicles), at map (x, z) by `to_map`; each a waypoint
## that follows it ("vehicle:<id>").
static func vehicle_pins(demo, to_map: Callable) -> Array:
	var out: Array = []
	for v in vehicles(demo):
		var p := _pin("veh_" + str(v.id), str(v.kind), str(v.label), to_map.call(v.pos))
		p["target"] = "vehicle:" + str(v.id)
		p["vehicle"] = true
		out.append(p)
	return out


## Where vehicle `id` (vehicles) is now, or INF once it is gone.
static func vehicle_pos(demo, id: String) -> Vector3:
	for v in vehicles(demo):
		if str(v.id) == id:
			return v.pos
	return Vector3.INF


## A spot the player clicked on bare ground.
static func spot_pin(map: Vector2) -> Dictionary:
	return _pin("spot", "spot", line("marked"), map)


## The places off this planet: [{ id, kind, label, target }]. `bodies` are
## SpaceTravel's ({ id, name }). Then every cruiser in the system (`cruisers`,
## system_cruisers), each with the planet it hangs over and who holds it (issue
## #497: coloured by that, the locals' green once they do).
static func off_planet(bodies: Array, cruisers: Array = system_cruisers(), stations: Array = system_stations()) -> Array:
	var out: Array = []
	for b in bodies:
		var label := str(b.get("name", ""))
		out.append({ "id": "planet_" + str(b.id), "kind": "planet",
			"label": label if label != "" else str(b.id).capitalize(), "target": "planet:" + str(b.id) })
	for c in cruisers:
		out.append({ "id": str(c.id), "kind": "cruiser", "label": line("cruiser_over") % planet_name(str(c.planet)),
			"target": "cruiser", "planet": str(c.planet), "cfg": str(c.cfg), "owner": cruiser_owner(c) })
	for s in stations:
		out.append({ "id": str(s.id), "kind": "station", "label": line("station_over") % planet_name(str(s.planet)),
			"target": "station", "planet": str(s.planet), "station": str(s.station) })
	return out


## Unit direction from the planet's centre for map (x, z) on a ball of `radius`
## (PlanetSphere.map_dir: the port is +Y).
static func dir(map: Vector2, radius: float) -> Vector3:
	var d := map.length()
	if d < 0.0001:
		return Vector3.UP
	var th := d / radius
	var s := sin(th) / d
	return Vector3(map.x * s, cos(th), map.y * s)


## Map (x, z) for a unit direction from the centre (PlanetSphere.dir_map).
static func dir_map(d: Vector3, radius: float) -> Vector2:
	var h := Vector2(d.x, d.z)
	var hl := h.length()
	if hl < 0.0000001:
		return Vector2.ZERO if d.y > 0.0 else Vector2(PI * radius, 0.0)
	return h / hl * atan2(hl, d.y) * radius


# ------------------------------------------------------------------ the waypoint

## Point the HUD at `pin` (a surface pin, or an off_planet entry) on `planet_id`.
static func set_waypoint(pin: Dictionary, planet_id: String) -> void:
	var target := str(pin.get("target", ""))
	if target == "":
		var m: Vector2 = pin.map
		target = "map:%.1f,%.1f" % [m.x, m.y]
	WorldState.map_waypoint = { "id": str(pin.id), "label": str(pin.label), "target": target,
		"planet": planet_id, "arrive": float(pin.get("arrive", kind_cfg(str(pin.get("kind", ""))).get("arrive", 30.0))) }
	for k in WorldState.quests:
		WorldState.quests[k].waypoint = false
	WorldState.objective_pin = ""


static func clear_waypoint() -> void:
	WorldState.map_waypoint = {}


## The waypoint's pin id, or "".
static func waypoint_id() -> String:
	return str(WorldState.map_waypoint.get("id", ""))


## { text, target, arrive, map } for the pointer, or {} when there is none.
## A planet's shows anywhere but that planet, and clears itself once you are there.
## A surface or cruiser waypoint on another planet leads to that planet first (and
## never clears itself on the way: arrive -1), then to the place once you land.
static func waypoint() -> Dictionary:
	var w := WorldState.map_waypoint
	if w.is_empty():
		return {}
	var here := GameFlow.current_planet_id()
	var target := str(w.get("target", ""))
	if target.begins_with("planet:"):
		if target.get_slice(":", 1) == here:
			clear_waypoint()
			return {}
	elif str(w.get("planet", "")) != here:
		var there := str(w.get("planet", ""))
		if there == "":
			return {}
		return { "text": line("waypoint_there") % [str(w.get("label", "")), planet_name(there)],
			"target": "planet:" + there, "arrive": -1.0, "map": true }
	return { "text": line("waypoint") % str(w.get("label", "")), "target": target,
		"arrive": float(w.get("arrive", 30.0)), "map": true }


# ------------------------------------------------------------------ elsewhere

static var _others := {}                ## planet id -> { planet, sphere }


## Another planet's map, from its data (the page shows it without going there):
## { planet: PlanetGen.build, sphere: its ball seated on its town as its scene
## seats it (PlanetTerrain.for_planet) }, or {} when it is not a ball. Once a session.
static func other_planet(id: String) -> Dictionary:
	if _others.has(id):
		return _others[id]
	var planet := PlanetGen.build(id)
	var out := {}
	var pt := PlanetTerrain.for_planet(planet)
	if pt != null:
		out = { "planet": planet, "sphere": pt.sphere }
		pt.free()
	_others[id] = out
	return out


## How a planet's ground is tinted on its globe: content/look/map.json "terrain",
## with its type's "terrain_types" entry laid over it (the type's base's when
## it has none of its own: the lava moon's is its own, the asteroid's grey rock
## otherwise). On the lava moon "rock" is the lava (GlobeTerrain).
static func terrain_look(planet: Dictionary) -> Dictionary:
	var out: Dictionary = look().get("terrain", {}).duplicate()
	var by_type: Dictionary = look().get("terrain_types", {})
	var t := str(planet.get("type", ""))
	var base := str(PlanetGen.types().get("types", {}).get(t, {}).get("base", ""))
	var over = by_type.get(t, by_type.get(base, {}))
	if over is Dictionary:
		out.merge(over, true)
	return out


# ------------------------------------------------------------------ the system

static var _system: Array = []


## Every planet you can get to, where it hangs in one frame for them all: the
## home planet's scene (its port the origin; PlanetGen.neighbours: every
## planet's scene is that space shifted to its own port, never turned). For the
## Map page's system view (SystemView): [{ id, label, kind, centre, port, radius,
## cloud_radius, color, dark, bands, ring, near }], centre and port in metres;
## the home planet first, the rest by how far out they hang. Once a session.
static func system() -> Array:
	if not _system.is_empty():
		return _system
	var cc = PlanetGen._content()
	var cfgs: Dictionary = cc.planets
	var out: Array = []
	for id in cfgs:
		var c = PlanetGen.system_centre(str(id), cc)     # issue #573: null for open space too
		if c == null:
			continue
		var cfg: Dictionary = cfgs[id]
		var n := PlanetGen._neighbour(cfg, c, cc)
		var built := PlanetGen.build(str(id), cc)
		out.append({ "id": str(id), "label": planet_name(str(id)),
			"kind": str(built.get("type_cfg", {}).get("label", "")),
			"centre": c, "port": c + Vector3(0, float(n.radius), 0), "radius": float(n.radius),
			"cloud_radius": float(n.cloud_radius), "color": n.color, "dark": n.dark,
			"bands": float(n.bands), "ring": n.ring, "near": str(cfg.get("near", "")) })
	var home := PlanetGen.home_id()
	out.sort_custom(func(a, b):
		if str(a.id) == home or str(b.id) == home:
			return str(a.id) == home
		return (a.centre as Vector3).length() < (b.centre as Vector3).length())
	_system = out
	return _system


## One planet of system(), or {}.
static func system_body(id: String) -> Dictionary:
	for b in system():
		if str(b.id) == id:
			return b
	return {}


## Where planet `id`'s port is in planet `here`'s scene (INF when either is not
## in the system): what SpaceTravel calls a neighbour's offset, for any two
## planets, so a pointer on a moon can lead to its sister moon too.
static func port_from(id: String, here: String) -> Vector3:
	var a := _port(id)
	var b := _port(here)
	if a == Vector3.INF or b == Vector3.INF:
		return Vector3.INF
	return a - b


## A point in place `here`'s scene, in the system frame (INF when it is not in it).
## Issue #576: open space's scene is the system frame shifted to the sun.
static func to_system(p: Vector3, here: String) -> Vector3:
	var b := _port(here)
	return b + p if b != Vector3.INF else Vector3.INF


## A place's origin in the system frame: a planet's port, open space's origin.
static func _port(id: String) -> Vector3:
	if PlanetGen.is_open_space(id):
		return PlanetGen.system_port(id)        # issue #576: the sun
	var b := system_body(id)
	return b.port if not b.is_empty() else Vector3.INF


## The first Remnant cruiser in the system frame (system_cruisers), or INF when
## there is none.
static func system_cruiser() -> Vector3:
	var all := system_cruisers()
	return all[0].pos if not all.is_empty() else Vector3.INF


static var _cruisers: Array = []


## Every Remnant cruiser in the system (each planet's "cruiser" landmarks: the home
## one over the port's planet, issue #327's by the ringed giant's station), the
## home planet's first: [{ id (its landmark), cfg (content/core/cruiser/<cfg>.json),
## planet, pos (system frame) }]. Once a session; its name and who holds it change
## with the save: cruiser_label, cruiser_owner. A planet has at most one, so the
## Map page names a cruiser by the planet it hangs over ("cruiser:<planet>").
static func system_cruisers() -> Array:
	if not _cruisers.is_empty():
		return _cruisers
	for b in system():
		var world: Dictionary = PlanetGen.build(str(b.id)).get("world", {})
		for lm in CruiserHull.landmarks(world):
			if not lm.has("at"):
				continue
			var at: Array = lm.at
			var r := float(b.radius)
			var pos := (b.centre as Vector3) + dir(Vector2(float(at[0]), float(at[2])), r) * (r + float(lm.get("altitude", 0.0)))
			_cruisers.append({ "id": str(lm.get("id", "")), "cfg": CruiserHull.config_id(lm), "planet": str(b.id), "pos": pos })
			break                                # one a planet
	return _cruisers


## The cruiser over planet `planet` (system_cruisers), or {}.
static func cruiser_on(planet: String) -> Dictionary:
	for c in system_cruisers():
		if str(c.planet) == planet:
			return c
	return {}


## A cruiser's name, as RemnantCruiser.label gives it: its config's label and the
## name this save gave the ship.
static func cruiser_label(c: Dictionary) -> String:
	var cfg := CruiserHull.data_for(str(c.get("cfg", "")))
	var l := str(cfg.get("label", _kind_label("cruiser")))
	var n := NameHooks.vessel(cfg, "vessel:" + str(cfg.get("id", c.get("cfg", ""))))
	return "%s %s" % [l, n] if n != "" else l


## Who holds a cruiser now: the home one by RemnantCruiser.home_holder (issue
## #497: the Remnant, the locals, "" while the dark master is aboard); any other
## the Remnant's until its general dies (its config's flag), then nobody's ("").
static func cruiser_owner(c: Dictionary) -> String:
	var cfg_id := str(c.get("cfg", ""))
	if cfg_id == "" or cfg_id == CruiserHull.HOME_ID:
		return CruiserHolo.owner_of(CruiserHolo.CRUISER)
	return "" if WorldState.has_flag(str(CruiserHull.data_for(cfg_id).get("flag", ""))) else Territory.REMNANT


## The hover line for who holds a cruiser.
static func cruiser_status(c: Dictionary) -> String:
	match cruiser_owner(c):
		Territory.REMNANT:
			return line("cruiser_remnant")
		Territory.LOCALS:
			return line("cruiser_locals")
	return line("cruiser_empty")


## A cruiser's icon colour: the pin's red while the Remnant hold it, the locals'
## green, the owners' "empty" grey once nobody does.
static func cruiser_color(c: Dictionary) -> Color:
	var lk := look()
	var ow: Dictionary = lk.get("owners", {})
	match cruiser_owner(c):
		Territory.REMNANT:
			return Color(str(lk.get("pins", {}).get("cruiser", {}).get("color", "#e0573a")))
		Territory.LOCALS:
			return Color(str(ow.get("locals", "#5fd35f")))
	return Color(str(ow.get("empty", "#a89a80")))


static var _stations: Array = []


## Every space station in the system (each planet's "station" landmarks:
## StationHull, today the ringed giant's over its top): [{ id (its landmark),
## station (content/core/stations/<station>.json), planet, pos (system frame) }].
## Once a session. Like the cruisers, one a planet: the Map page names a station by
## the planet it hangs over ("station:<planet>").
static func system_stations() -> Array:
	if not _stations.is_empty():
		return _stations
	for b in system():
		var world: Dictionary = PlanetGen.build(str(b.id)).get("world", {})
		for lm in StationHull.landmarks(world):
			if not lm.has("at"):
				continue
			var at: Array = lm.at
			var r := float(b.radius)
			var pos := (b.centre as Vector3) + dir(Vector2(float(at[0]), float(at[2])), r) * (r + float(lm.get("altitude", 0.0)))
			_stations.append({ "id": str(lm.get("id", "")), "station": str(lm.get("station", "")), "planet": str(b.id), "pos": pos })
			break                                # one a planet
	return _stations


## The station over planet `planet` (system_stations), or {}.
static func station_on(planet: String) -> Dictionary:
	for s in system_stations():
		if str(s.planet) == planet:
			return s
	return {}


## A station's name, as SpaceStation.label gives it: the name this save gave it in
## its config's name_fmt, or its config's label.
static func station_label(s: Dictionary) -> String:
	var hull := StationHull.for_id(str(s.get("station", "")))
	var cfg: Dictionary = hull.cfg if hull != null else {}
	var n := NameHooks.vessel(cfg, "station:" + str(s.get("id", "")))
	var l := str(cfg.get("label", _kind_label("station")))
	return _cap(str(cfg.get("name_fmt", "%s")) % n if n != "" else l)


## The station's places for its side view (StationHull.map_places), as pins:
## { id, kind, label, target, rect, tower, arrive }, and on each floor what is on
## it for its plan: `floor` (its index in its tower), `rooms` (room_pins), `owner`
## (an open floor's, from the station's "map" floors), `what` and `summary` (one
## line: who holds how many rooms, or what the open floor is). `s` is a
## system_stations entry.
static func orbital_pins(s: Dictionary) -> Array:
	var out: Array = []
	var hull := StationHull.for_id(str(s.get("station", "")))
	if hull == null:
		return out
	var names: Dictionary = cfg().get("station_places", {})
	var floors: Dictionary = hull.cfg.get("map", {}).get("floors", {})
	for p in hull.map_places():
		var pin := { "id": "station_" + str(p.id), "kind": "station_place", "label": str(names.get(str(p.id), str(p.id).capitalize())),
			"target": "station:" + str(p.id), "rect": p.rect, "tower": str(p.tower),
			"arrive": float(kind_cfg("station_place").get("arrive", 12.0)), "rooms": [], "owner": "", "what": "", "summary": "" }
		var t := hull.tower(str(p.tower))
		if not t.is_empty():
			for i in (t.floors as Array).size():
				if str(t.floors[i].id) == str(p.id):
					pin["floor"] = i
					pin["rooms"] = room_pins(s, hull, t, i)
			var fc: Dictionary = floors.get(str(p.id), {})
			pin["owner"] = station_owner(s, str(fc.get("owner", "")))
			pin["what"] = str(fc.get("what", ""))
			pin["summary"] = _floor_summary(pin)
		out.append(pin)
	return out


## The rooms of floor `i` of tower `t` (StationHull.floor_rooms) as pins you can set
## a waypoint on ("station:<floor>.<k>"): { id, kind, label, use, owner, owner_label,
## target, arrive, a, half, r0, r1, open }.
static func room_pins(s: Dictionary, hull: StationHull, t: Dictionary, i: int) -> Array:
	var out: Array = []
	var fid := str(t.floors[i].id)
	var names: Dictionary = cfg().get("station_rooms", {})
	var owners: Dictionary = hull.cfg.get("map", {}).get("owners", {})
	for rm in hull.floor_rooms(t, i):
		var use := str(rm.use)
		var who := station_owner(s, str(owners.get(use, "")))
		out.append({ "id": "station_%s.%d" % [fid, int(rm.k)], "kind": "station_place", "label": str(names.get(use, use.capitalize())),
			"use": use, "owner": who, "owner_label": owner_label(who), "target": "station:%s.%d" % [fid, int(rm.k)],
			"arrive": float(kind_cfg("station_place").get("arrive", 12.0)) * 0.5,
			"a": float(rm.a), "half": float(rm.half), "r0": float(rm.r0), "r1": float(rm.r1), "open": bool(rm.open) })
	return out


## Who holds a part of station `s` now: its data's owner, except that the Remnant's
## parts are the locals' once you have taken the station's Remnant deck (Territory
## "station_<landmark id>").
static func station_owner(s: Dictionary, data_owner: String) -> String:
	if data_owner == Territory.REMNANT and Territory.owner(Territory.STATION + str(s.get("id", ""))) == Territory.LOCALS:
		return Territory.LOCALS
	return data_owner


## An owner's name on the map ("" for nobody's).
static func owner_label(who: String) -> String:
	return str(cfg().get("station_owners", {}).get(who, who.capitalize())) if who != "" else ""


## An owner's colour on the station's map (content/look/map.json "station_view").
static func owner_color(who: String) -> Color:
	return Color(str(look().get("station_view", {}).get("owners", {}).get(who, "#a89a80")))


## A floor's line under its name: each owner and how many rooms they hold (the
## most first), or what an open floor is and who runs it.
static func _floor_summary(pin: Dictionary) -> String:
	var rooms: Array = pin.get("rooms", [])
	if rooms.is_empty():
		var what := str(cfg().get("station_floor_kinds", {}).get(str(pin.get("what", "")), ""))
		var who := owner_label(str(pin.get("owner", "")))
		if what != "" and who != "":
			return line("station_floor_open") % [what, who]
		return what
	var count := {}
	for r in rooms:
		var who := str(r.owner)
		count[who] = int(count.get(who, 0)) + 1
	var keys := count.keys()
	keys.sort_custom(func(a, b): return int(count[a]) > int(count[b]))
	var parts: Array = []
	for k in keys:
		parts.append("%s %d" % [owner_label(str(k)) if str(k) != "" else line("station_nobody"), int(count[k])])
	return "  \u00b7  ".join(parts)


## A planet's name for the map's title and its lines.
static func planet_name(id: String) -> String:
	var n := PlanetGen.display_name(PlanetGen.build(id))
	return n if n != "" else id.capitalize()


## The cruiser's places for its side view (CruiserHull.map_places), as pins:
## { id, kind, label, target, rect, arrive }.
static func cruiser_pins() -> Array:
	var out: Array = []
	var names: Dictionary = cfg().get("cruiser_places", {})
	for p in CruiserHull.map_places():
		out.append({ "id": "cruiser_" + str(p.id), "kind": "cruiser_place", "label": str(names.get(str(p.id), str(p.id).capitalize())),
			"target": "cruiser:" + str(p.id), "rect": p.rect, "arrive": float(kind_cfg("cruiser_place").get("arrive", 10.0)) })
	return out


# ------------------------------------------------------------------ helpers

## Who holds `place` (an outpost id, or a front's barracks for its port): owner,
## whether the locals' supplies there are short (shown only once you have taken
## Oda's supply run: Territory.supplier), and the hover line for it.
static func _stamp_owner(pin: Dictionary, place: String) -> void:
	var who := Territory.owner(place)
	var is_short := Territory.short_shown(place)
	pin["owner"] = who
	pin["short"] = is_short
	pin["hold"] = Territory.hold_frac(place)
	pin["status"] = ""
	if who != Territory.LOCALS:
		if float(pin.hold) >= 0.0:         # issue #425: the Remnant cut off, on a clock
			var rleft := int(maxf(0.0, Territory.hold_left(place)))
			pin["status"] = (line("short") if is_short else line("remnant_held_for")) % [rleft / 60, rleft % 60]
		return
	var f := Territory.front_of(place)
	if place == Territory.barracks_of(f) or Territory.driven_off(f) or Territory.hold_frac(place) < 0.0:
		pin["status"] = line("held")
		return
	var left := int(maxf(0.0, Territory.hold_left(place)))
	pin["status"] = (line("short") if is_short else line("held_for")) % [left / 60, left % 60]


static func _pin(id: String, kind: String, label: String, map: Vector2) -> Dictionary:
	return { "id": id, "kind": kind, "label": label, "map": map,
		"arrive": float(kind_cfg(kind).get("arrive", 30.0)), "town": false }


static func _kind_label(kind: String) -> String:
	return str(kind_cfg(kind).get("label", kind.capitalize()))


## "the deep dunes outpost" -> "The deep dunes outpost"
static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s


static func _location(id: String) -> Dictionary:
	return _read("%s/%s.json" % [LOCATION_DIR, id])


static var _vendor_list: Array = []


static func _vendors() -> Array:
	if _vendor_list.is_empty():
		var da := DirAccess.open(VENDOR_DIR)
		if da != null:
			for f in da.get_files():
				if f.ends_with(".json"):
					var d := _read(VENDOR_DIR + "/" + f)
					if not d.is_empty():
						_vendor_list.append(d)
	return _vendor_list


static func _vendor(id: String) -> Dictionary:
	for v in _vendors():
		if str(v.get("id", "")) == id:
			return v
	return {}


static var _stalls_look: Dictionary = {}


## content/look/items.json "stalls" "vendors": what each trader's stall shows.
static func _stall_looks() -> Dictionary:
	if _stalls_look.is_empty():
		_stalls_look = _read(ITEMS_LOOK_PATH).get("stalls", {}).get("vendors", {})
		if _stalls_look.is_empty():
			_stalls_look = { "_": {} }
	return _stalls_look


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}
