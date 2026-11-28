class_name PlanetGen
extends RefCounted
## The planet generator (issue #45). A planet is one small file,
## content/core/planets/<id>.json (name, type, town_size, style, where it hangs in
## a neighbour's sky); this turns it into everything the town scene builds:
##
##   town      -- the layout (TownGen at its town_size, or an authored town: a saved
##                layout from content/core/towns/ named by town_layout, issue #237)
##   world     -- the world dict ShipPilot, the sky and the detail tiers read
##                (an authored world, or one made from the planet's type)
##   type_cfg  -- content/core/planets/types.json for its type: ground (terrain,
##                platform or sphere), sand and rock colours, the sea / lava / gas / rock under
##                a platform, sky colours, atmosphere, how it looks from space
##   style     -- the town style (TownStyle spec: a preset or words)
##   sky       -- values laid over every time-of-day preset
##   neighbours-- other planets in its sky you can fly to: { id, at, offset, radius, color... },
##                all placed from one system frame (issue #573: system_centre)
##   cantina   -- who runs the cantina { card, look }
##   natives   -- issue #96: its native packs and wild animals (NativesData.resolve)
##   beast     -- its beast, if it has one: the "beast" block of its file ({} if none;
##                PlanetBeast.config lays it over content/core/hazards/beast.json)
##   harmful_surface -- issue #298: you can't breathe on its surface without
##                armour ({} = fine): the planet's own block, else its type's
##   barge     -- issue #269: its party barge, if it has one: the "barge" block of its
##                file ({} if none; PartyBarge.config lays it over
##                content/core/barges/party_barge.json)
##
## Pure and cheap: no nodes. Town scenes ask for the current planet
## (GameFlow.planet()); tests can build any planet without a scene.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TYPES_PATH := "res://content/core/planets/types.json"

static var _types: Dictionary = {}
static var _cache: Dictionary = {}       ## planet id -> built planet (built once per run)
static var layout_override: Dictionary = {}   ## issue #237: planet id -> town layout picked in F11 (this run only)


static func types() -> Dictionary:
	if _types.is_empty():
		_types = TownGen._read(TYPES_PATH)
		var all: Dictionary = _types.get("types", {})
		for id in all.keys():
			all[id] = _with_base(all, str(id), [])
	return _types


## Issue #272: a type may name a "base" type and give only what differs (the lava
## moon is the asteroid with other rock, lava and sky). Dictionaries merge key by
## key, all the way down; anything else (numbers, arrays) replaces.
static func _with_base(all: Dictionary, id: String, seen: Array) -> Dictionary:
	var t: Dictionary = all.get(id, {})
	var base := str(t.get("base", ""))
	if base == "" or seen.has(id) or not all.has(base):
		return t
	var merged := _deep_merge(_with_base(all, base, seen + [id]), t)
	merged.erase("base")
	merged["base_type"] = base
	return merged


static func _deep_merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		if out.get(k) is Dictionary and b[k] is Dictionary:
			out[k] = _deep_merge(out[k], b[k])
		else:
			out[k] = b[k] if not (b[k] is Dictionary or b[k] is Array) else b[k].duplicate(true)
	return out


static func home_id() -> String:
	return str(types().get("home", "port_desert"))


## Every planet id in the manifest.
static func ids(content = null) -> Array:
	var cc = content if content != null else _content()
	return cc.planets.keys()


## A planet, built (cached: the same planet is the same dictionary all run).
static func build(planet_id: String, content = null) -> Dictionary:
	# Issue #874: open space is a different place in each system (its planets).
	var key := planet_id + "@" + current_system() if is_open_space(planet_id) else planet_id
	if _cache.has(key):
		return _cache[key]
	var cc = content if content != null else _content()
	var cfg: Dictionary = cc.planets.get(planet_id, {})
	if cfg.is_empty():
		push_warning("PlanetGen: unknown planet " + planet_id)
		return {}
	var p := make(cfg, cc)
	_cache[key] = p
	return p


## Issue #237: the saved town layouts a planet with an authored town can pick.
static func layouts(content = null) -> Array:
	var cc = content if content != null else _content()
	return cc.towns.keys()


## Issue #237: build `planet_id`'s town to `layout` for the rest of this run
## (F11). "" goes back to the layout its file names.
static func set_layout(planet_id: String, layout: String) -> void:
	if layout == "":
		layout_override.erase(planet_id)
	else:
		layout_override[planet_id] = layout
	_cache.erase(planet_id)


## Build from a config dictionary (also for configs not in the manifest: tests,
## a contributor trying one out).
static func make(cfg: Dictionary, cc = null) -> Dictionary:
	if cc == null:
		cc = _content()
	var id := str(cfg.get("id", "planet"))
	var type := str(cfg.get("type", "sand"))
	var tcfg: Dictionary = types().get("types", {}).get(type, {})
	if tcfg.is_empty():
		push_warning("PlanetGen: unknown planet type %s (%s); using sand" % [type, id])
		type = "sand"
		tcfg = types().types.sand
	if str(tcfg.get("ground", "")) == "none":
		return _make_open_space(id, cfg, type, tcfg, cc)
	var size := clampi(int(cfg.get("town_size", 50)), 1, 100)
	var town_id := str(cfg.get("town", ""))
	var town: Dictionary = {}
	var layout := str(layout_override.get(id, cfg.get("town_layout", "")))
	if town_id != "" and layout != "":
		# Issue #237: an authored town built to a saved layout (content/core/towns/).
		town = cc.town_from_layout(layout, town_id)
		var lsize := int(town.get("size", size))
		if lsize != size and not layout_override.has(id):
			push_warning("PlanetGen: %s wants town_size %d but layout %s is size %d" % [id, size, layout, lsize])
		size = lsize
	elif town_id != "":
		town = cc.get_location(town_id)            # authored
	elif cfg.has("station_town"):
		# The planet's town is a space station's bay (the ringed giant): its
		# "station" landmark named here; no deck, no wall, no cantina.
		town_id = id + "_town"
		var slm: Dictionary = {}
		for lm in cfg.get("landmarks", []):
			if str(lm.get("id", "")) == str(cfg.station_town):
				slm = lm
		var sr := float(tcfg.get("surface", {}).get("radius", tcfg.get("body", {}).get("radius", 1500.0)))
		town = StationHull.town_for(town_id, slm, PlanetSphere.new(sr), { "planet": id })
		if town.is_empty():
			push_warning("PlanetGen: %s has no station landmark %s" % [id, str(cfg.station_town)])
	else:
		town_id = id + "_town"
		var opts := {}
		var co: Dictionary = cfg.get("cantina_owner", {})
		if co.has("card"):
			opts["cantina_card"] = str(co.card)
		if co.has("look"):
			opts["cantina_look"] = str(co.look)
		if not co.has("card"):
			opts["cantina_planet"] = id          # issue #75: her own Oda (PlanetOwner)
		if str(tcfg.get("landing_bay", "")) == "pit":
			opts["bay"] = "pit"
		if bool(tcfg.get("enclosed", false)):
			opts["ring"] = tcfg.get("station", {})      # issue #99: a sealed, round station
		if bool(cfg.get("stage_dancer", false)):
			opts["stage_dancer"] = true
		if cfg.has("club_dome"):
			opts["club_dome"] = cfg.club_dome      # issue #261: the whole dome is the club
		if cfg.has("domes"):
			opts["domes"] = cfg.domes              # a sealed station's other domes, off its landing pit
		town = TownGen.generate(town_id, size, int(cfg.get("seed", NameEngine.fnv(id) % 100000)), opts, _town_kit(cfg))
		_swap_locals(town, cfg.get("locals", {}))
		if cfg.has("speeder_pad"):
			add_speeder_pad(town, cfg.speeder_pad)    # issue #879: the tide world's pad out front
	var world: Dictionary = {}
	if cfg.has("world"):
		world = CoreContent.resolve_layout(cc.get_world(str(cfg.world)), layout)    # issue #295: landmarks per layout
	else:
		world = _world_for(id, town_id, tcfg, cfg)
	if cfg.has("landmarks"):
		# A planet config's own landmarks join its world's (a space station over the
		# moon: content/core/stations/). Moving one to another planet is moving the block.
		world = world.duplicate()
		world["landmarks"] = (world.get("landmarks", []) as Array) + (cfg.landmarks as Array)
	world["ground"] = str(tcfg.get("ground", "terrain"))
	world["planet"] = id
	if world.ground != "none" and not (world.get("detail", {}) as Dictionary).has("sight"):
		world["detail"] = with_sight(world.get("detail", {}), tcfg, cfg)
	var style := str(cfg.get("style", tcfg.get("default_style", "desert")))
	# Issue #96: its native people and wild animals, from its own config or its type.
	var bd: Dictionary = town.get("bounds", {})
	var trect := Rect2()
	if not bd.is_empty():
		trect = Rect2(float(bd.min[0]), float(bd.min[1]), float(bd.max[0]) - float(bd.min[0]), float(bd.max[1]) - float(bd.min[1]))
	var natives := NativesData.resolve(id, cfg, tcfg, int(cfg.get("seed", NameEngine.fnv(id) % 100000)), trect)
	var near := neighbours(id, cc, cfg)
	return {
		"id": id,
		"cfg": cfg,
		"type": type,
		"type_cfg": tcfg,
		"ground": str(tcfg.get("ground", "terrain")),
		"deck": bool(tcfg.get("deck", false)) and not cfg.has("station_town"),   # a town on a floating deck
		"size": size,
		"town_id": town_id,
		"town": town,
		"world": world,
		"style": style,
		"sky": tcfg.get("sky", {}),
		"features": cfg.get("features", []),
		"cantina": cfg.get("cantina_owner", {}),
		"encounter": cfg.get("encounter", null),
		"name": str(cfg.get("name", "")),
		"town_name": str(cfg.get("town_name", "")),
		"neighbours": near,
		"sky_painting": sky_painting(cfg, near),
		"natives": natives,
		"beast": cfg.get("beast", {}),
		"barge": cfg.get("barge", {}),
		"harmful_surface": cfg.get("harmful_surface", tcfg.get("harmful_surface", {})),
	}


## Issue #875: the town kit a planet's town is built from: the shared kit
## (content/core/planets/town_kit.json) with the planet file's own `town_kit`
## laid over it key by key (taller towers, more of them). Empty: the shared kit.
static func _town_kit(cfg: Dictionary) -> Dictionary:
	var own: Dictionary = cfg.get("town_kit", {})
	if own.is_empty():
		return {}
	var kit: Dictionary = TownGen.new().kit.duplicate(true)
	for k in own:
		if k != "note":
			kit[k] = own[k]
	return kit


## Issue #875: a planet's own people in its town: `locals` maps a soldier
## profile the town generator places to the one this planet uses instead (its
## locals' look: "local_resident": "red_local_resident").
## Issue #879: a speeder pad out front of a deck town (a planet's "speeder_pad"):
## a level pad `length` metres out past the deck's front edge (the gate's side,
## +x) and `width` across, centred on the gate. Writes town.speeder_pad
## ({ rect: Rect2 on the map, y, ramp }: PlanetTerrain.speeder_pad_site stands it
## up out of the sea), five speeder_spot markers in a row across it (where the
## speeders you own wait: SpeederPost.line_spot) and, with "loaner", a
## sea_loaner marker further out, the town's own speeder anyone may take.
static func add_speeder_pad(town: Dictionary, pad: Dictionary) -> void:
	var front := -INF
	for b in town.get("boxes", []):
		if str(b.get("kind", "")) == "floor":
			front = maxf(front, float(b.max[0]))
	if not is_finite(front):
		return
	var gz := 0.0
	for b in town.get("boxes", []):
		if str(b.get("id", "")) == "gate_lintel":
			gz = (float(b.min[2]) + float(b.max[2])) * 0.5
	var length := float(pad.get("length", 34.0))
	var width := float(pad.get("width", 40.0))
	var x0 := front - 1.0                     # tucked a metre under the deck's edge: no gap
	town["speeder_pad"] = { "rect": Rect2(x0, gz - width * 0.5, length + 1.0, width), "y": 0.0,
		"ramp": float(pad.get("ramp_m", 16.0)) }
	# A painted plate under it, data only (hidden, nothing to trip on: the pontoon
	# itself is the sea ball's ground), so the markers on it stand on something.
	var zone := "outside"
	for b in town.get("boxes", []):
		if str(b.get("id", "")) == "gate_lintel":
			zone = str(b.get("zone", zone))
	var boxes: Array = town.get("boxes", [])
	boxes.append({ "id": "speeder_pad_plate", "zone": zone, "kind": "pad", "standable": true, "hidden": true,
		"min": [front, -0.2, gz - width * 0.5], "max": [front + length, 0.0, gz + width * 0.5] })
	town["boxes"] = boxes
	var markers: Array = town.get("markers", [])
	var n := 5
	for i in n:
		var z := gz + (float(i) - (n - 1) * 0.5) * minf(8.0, (width - 6.0) / n)
		markers.append({ "id": "speeder_spot_%d" % (i + 1), "role": "speeder_spot", "yaw_deg": -90,
			"pos": [snappedf(front + length * 0.3, 0.1), 0, snappedf(z, 0.1)] })
	if bool(pad.get("loaner", false)):
		markers.append({ "id": "sea_loaner", "role": "sea_loaner", "yaw_deg": -90,
			"pos": [snappedf(front + length * 0.72, 0.1), 0, snappedf(gz, 0.1)] })
	town["markers"] = markers


static func _swap_locals(town: Dictionary, locals: Dictionary) -> void:
	if locals.is_empty():
		return
	for m in town.get("markers", []):
		var s := str(m.get("soldier", ""))
		if locals.has(s):
			m["soldier"] = str(locals[s])


## Issue #573: open space, a place with no planet (ground "none"). Its town is
## only the ship's pad and a spot to stand (hidden: the flight never leaves the
## seat out here), so the ship, pilot and HUD build as anywhere else; no natives,
## no people. Its world has no terrain and its atmosphere is all space.
static func _make_open_space(id: String, cfg: Dictionary, type: String, tcfg: Dictionary, cc) -> Dictionary:
	var town_id := id + "_town"
	var town := {
		"id": town_id,
		"boxes": [
			{ "id": "spawn_plate", "kind": "floor", "zone": "ground", "min": [-2.0, -0.2, -2.0], "max": [2.0, 0.0, 2.0], "hidden": true },
			{ "id": "ship", "kind": "ship", "zone": "ground", "min": [6.0, 0.0, -9.0], "max": [24.0, 5.0, 9.0], "hidden": true },
		],
		"markers": [ { "id": "player_spawn", "role": "spawn", "pos": [0.0, 0.0, 0.0] } ],
		"zones": [],
	}
	var world := {
		"id": id,
		"label": str(tcfg.get("label", id)),
		"town": town_id,
		"naming": { "town": "town", "planet": "planet" },
		"terrain": {},
		"landmarks": [],
		"atmosphere": tcfg.get("atmosphere", {}),
		"detail": types().get("detail", {}),
		"ground": "none",
		"planet": id,
	}
	var near := neighbours(id, cc)
	# WorldGround: altitude and up out here ([centre, radius, flat_radius, up_blend,
	# bubble], as each ball's own up; bubble: where its scene lets go, from its centre).
	world["void_bodies"] = near.map(func(n):
		var surf: Dictionary = types().get("types", {}).get(str(n.type), {}).get("surface", {})
		var ball := str(types().get("types", {}).get(str(n.type), {}).get("ground", "")) == "ball"
		var bubble := bubble_radius(str(n.id), true, cc)
		return [n.at, float(n.radius), float(surf.get("flat_radius", 130.0 if ball else 350.0)),
			float(surf.get("up_blend", 160.0 if ball else 450.0)), bubble if bubble > 0.0 else float(n.radius)])
	return {
		"id": id, "cfg": cfg, "type": type, "type_cfg": tcfg, "ground": "none", "deck": false,
		"size": 1, "town_id": town_id, "town": town, "world": world, "style": str(tcfg.get("default_style", "metallic")),
		"sky": tcfg.get("sky", {}), "features": [], "cantina": {}, "encounter": null,
		"name": str(cfg.get("name", "")), "town_name": "", "neighbours": near, "sky_painting": sky_painting(cfg, near),
		"natives": {}, "beast": {}, "barge": {}, "harmful_surface": {},
	}


# ------------------------------------------------------------------ the system frame (issue #573)

## Issue #573: the type data's "space" block (open space's id, hysteresis, margins).
static func space_cfg() -> Dictionary:
	return types().get("space", {})


## Open space's planet id.
static func open_space_id() -> String:
	return str(space_cfg().get("open_space", "open_space"))


static func is_open_space(id: String) -> bool:
	return id != "" and id == open_space_id()


## True for a place you can fly to and be on: not open space (ground "none").
static func is_planet(id: String, cc = null) -> bool:
	if cc == null:
		cc = _content()
	var cfg: Dictionary = cc.planets.get(id, {})
	return not cfg.is_empty() and str(types().get("types", {}).get(str(cfg.get("type", "")), {}).get("ground", "")) != "none"


## Metres past a bubble before leaving it (so the edge does not flip-flop).
static func hysteresis() -> float:
	return float(space_cfg().get("hysteresis", 300.0))


## A planet's bubble (from its centre, metres): its radius plus its handoff; 0
## for a planet with none. `leaving` adds the hysteresis.
static func bubble_radius(id: String, leaving := false, cc = null) -> float:
	if cc == null:
		cc = _content()
	var cfg: Dictionary = cc.planets.get(id, {})
	var h := handoff_altitude(str(cfg.get("type", "")))
	if cfg.is_empty() or h <= 0.0:
		return 0.0
	return ball_radius(cfg, cc) + h + (hysteresis() if leaving else 0.0)


## A planet's ball centre in the system frame, or null when it is not in it. The
## system frame is the home planet's scene: its port is the origin, so its centre
## is straight under it; every other planet's centre is its "at" from the port of
## the planet it is "near", to any depth. Every scene is this frame shifted to its
## own port (never turned), so the sun and stars agree in all of them.
## Issue #576: "near" may name the sun (space.sun): "at" is then from the sun's
## centre, which sits wherever the home planet's own "at" puts it.
static func system_centre(id: String, cc = null, depth := 0):
	if cc == null:
		cc = _content()
	var cfgs: Dictionary = cc.planets
	var cfg: Dictionary = cfgs.get(id, {})
	if cfg.is_empty() or not is_planet(id, cc):
		return null
	if id == home_id():
		return Vector3(0, -ball_radius(cfg, cc), 0)
	var near := str(cfg.get("near", ""))
	if not cfg.has("at"):
		return null
	var sun_sys := system_of_sun(near)
	if sun_sys != "":
		var sun := system_sun(cc, sun_sys)
		return sun + GameFlow.vec(cfg.at) if sun.is_finite() else null
	if depth >= 8 or not cfgs.has(near):
		return null
	var pc = system_centre(near, cc, depth + 1)
	if pc == null:
		return null
	return (pc as Vector3) + Vector3(0, ball_radius(cfgs[near], cc), 0) + GameFlow.vec(cfg.at)


## Issue #576: the sun's id, a name planets can be "near" (not a place).
## Issue #874: each system has its own sun (types.json space.systems); with no
## system named, the current one's.
static func sun_id(system := "") -> String:
	var sys := system if system != "" else current_system()
	return str(systems().get(sys, {}).get("sun", space_cfg().get("sun", "sun") if sys == HOME_SYSTEM else sys + "_sun"))


## Issue #874: the system whose sun is called `sun`, or "" when no sun has that name.
static func system_of_sun(sun: String) -> String:
	for sys in system_ids():
		if sun_id(sys) == sun:
			return sys
	return ""


## Issue #576: the sun's centre in the system frame (the home planet's centre less
## its "at"), INF when the home planet is not near the sun.
## Issue #874: another system's frame is its own (systems never share a scene):
## its sun is at that system's "sun_at" (the origin unless it says).
static func system_sun(cc = null, system := "") -> Vector3:
	var sys := system if system != "" else current_system()
	if cc == null:
		var key := "_sun/" + sys
		if not _cache.has(key):
			_cache[key] = system_sun(_content(), sys)
		return _cache[key]
	if sys != HOME_SYSTEM:
		return GameFlow.vec(systems().get(sys, {}).get("sun_at", [0.0, 0.0, 0.0]))
	var home: Dictionary = cc.planets.get(home_id(), {})
	if str(home.get("near", "")) != sun_id(HOME_SYSTEM) or not home.has("at"):
		return Vector3.INF
	return Vector3(0, -ball_radius(home, cc), 0) - GameFlow.vec(home.at)


# ------------------------------------------------------------------ star systems (issue #874)

const HOME_SYSTEM := "home"


## Issue #874: the star systems (types.json space.systems): id -> { label, sun,
## main, sun_at?, star? }. One "home" system when the data names none.
static func systems() -> Dictionary:
	if _cache.has("_systems"):
		return _cache["_systems"]
	var out := {}
	var s = space_cfg().get("systems", {})
	if s is Dictionary:
		for k in s:
			if s[k] is Dictionary:          # not its "note"
				out[str(k)] = s[k]
	if out.is_empty():
		out = { HOME_SYSTEM: { "sun": str(space_cfg().get("sun", "sun")), "main": home_id() } }
	_cache["_systems"] = out
	return out


static func system_ids() -> Array:
	return systems().keys()


## Issue #874: the system planet `id` is in: its file's "system", else the system
## of the sun it is near, else the system of the planet it is near, else home.
## Open space is in the current system.
static func system_of(id: String, cc = null, depth := 0) -> String:
	if is_open_space(id):
		return current_system()
	if cc == null:
		var key := "_sys/" + id
		if not _cache.has(key):
			_cache[key] = system_of(id, _content())
		return _cache[key]
	var cfg: Dictionary = cc.planets.get(id, {})
	if cfg.has("system"):
		return str(cfg.system)
	var near := str(cfg.get("near", ""))
	var by_sun := system_of_sun(near) if near != "" else ""
	if by_sun != "":
		return by_sun
	if near != "" and cc.planets.has(near) and depth < 8:
		return system_of(near, cc, depth + 1)
	return HOME_SYSTEM


## Issue #874: the system you are in: the current planet's, or in open space the
## one the warp drive last took you to (WorldState.system).
static func current_system() -> String:
	var here := GameFlow.current_planet_id()
	if here != "" and not is_open_space(here):
		var cfg_sys := _planet_system_quick(here)
		if cfg_sys != "":
			return cfg_sys
	var ws := str(WorldState.system)
	return ws if systems().has(ws) else HOME_SYSTEM


## The system of a planet without building content when it is cached.
static func _planet_system_quick(id: String) -> String:
	var key := "_sys/" + id
	if _cache.has(key):
		return _cache[key]
	return system_of(id)


## Issue #874: the system's main planet (where a warp points you, and whose ball
## frames the sky out there): its "main", the home planet for home.
static func main_planet(system := "") -> String:
	var sys := system if system != "" else current_system()
	var m := str(systems().get(sys, {}).get("main", ""))
	return m if m != "" else (home_id() if sys == HOME_SYSTEM else "")


## Issue #874: the system's name for the picker and the chart.
static func system_label(system: String) -> String:
	return str(systems().get(system, {}).get("label", system))


## Where a place's own origin (a planet's port, on top of its ball) is in the
## system frame: open space's is the sun (issue #576: the middle of the system,
## so a ship out there is never far from its origin), else the system frame's own
## origin. INF when the place is not in the system.
static func system_port(id: String, cc = null) -> Vector3:
	if is_open_space(id):
		var sun := system_sun(cc)        # issue #874: the current system's sun
		return sun if sun.is_finite() else Vector3.ZERO
	if cc == null:
		# Asked on every switch (SpaceTravel): a full content read is ~13 ms, and
		# where a planet sits never changes in a run.
		var key := "_port/" + id
		if not _cache.has(key):
			_cache[key] = system_port(id, _content())
		return _cache[key]
	var c = system_centre(id, cc)
	if c == null:
		return Vector3.INF
	return (c as Vector3) + Vector3(0, ball_radius(cc.planets.get(id, {}), cc), 0)


## The system-frame port of a planet config that is not in the manifest (a test,
## a contributor trying one out): its "at" from the planet it is near.
static func _cfg_port(cfg: Dictionary, cc) -> Vector3:
	var near := str(cfg.get("near", ""))
	var pc = system_centre(near, cc)
	if pc == null or not cfg.has("at"):
		return Vector3.INF
	var r := ball_radius(cfg, cc)
	return (pc as Vector3) + Vector3(0, ball_radius(cc.planets[near], cc), 0) + GameFlow.vec(cfg.at) + Vector3(0, r, 0)


## Issue #717: a world's "detail" with build by sight: the types' default
## "sight" block, then the type's own ("sight" in types.json) and the planet
## file's over it, key by key ("hold" replaced whole). A copy.
static func with_sight(detail: Dictionary, tcfg: Dictionary, cfg: Dictionary) -> Dictionary:
	var out := detail.duplicate(true)
	var sight: Dictionary = (types().get("detail", {}).get("sight", {}) as Dictionary).duplicate(true)
	for over in [tcfg.get("sight", {}), cfg.get("sight", {})]:
		if over is Dictionary:
			sight.merge(over, true)
	if not sight.is_empty():
		out["sight"] = sight
	return out


## A world dict for a generated planet: the same shape as content/core/worlds.
static func _world_for(id: String, town_id: String, tcfg: Dictionary, cfg: Dictionary = {}) -> Dictionary:
	var platform := str(tcfg.get("ground", "terrain")) in ["platform", "sphere"]
	var surface: Dictionary = tcfg.get("surface", {})
	if str(tcfg.get("ground", "terrain")) == "terrain" and float(cfg.get("sphere_radius", 0.0)) > 0.0:
		# Issue #874: a generated dune world that is a whole ball, as the home world's
		# own world file makes it (terrain.sphere_radius, src/systems/planets/planet_sphere.gd).
		var r := float(cfg.sphere_radius)
		return {
			"id": id,
			"label": str(tcfg.get("label", id)),
			"town": town_id,
			"naming": { "town": str(tcfg.get("town_naming", "town")), "planet": "planet" },
			"terrain": { "sphere_radius": r, "extent": 6000.0, "skirt_height": 4.0, "planet_radius": r, "curve_from": 6000.0 },
			"landmarks": [],
			"atmosphere": tcfg.get("atmosphere", {}),
			"detail": types().get("detail", {}),
		}
	if str(tcfg.get("ground", "")) == "ball":
		# Issue #99: a real ball like the home planet (WorldTerrain asks the sphere).
		var w := {
			"id": id,
			"label": str(tcfg.get("label", id)),
			"town": town_id,
			"naming": { "town": str(tcfg.get("town_naming", "town")), "planet": "planet" },
			"terrain": { "sphere_radius": float(surface.get("radius", 1500.0)) },
			"landmarks": [],
			"atmosphere": tcfg.get("atmosphere", {}),
			"detail": types().get("detail", {}),
		}
		if str(surface.get("kind", "")) == "gas":
			# A gas ball: this far below the deck's level a ship is in the clouds, lost.
			w["lethal_below"] = -float(surface.get("lethal_depth", 60.0))
		return w
	return {
		"id": id,
		"label": str(tcfg.get("label", id)),
		"town": town_id,
		"naming": { "town": str(tcfg.get("town_naming", "town")), "planet": "planet" },
		"terrain": {
			"extent": 0.0 if platform else 6000.0,
			"skirt_height": -float(surface.get("depth", 160.0)) if platform else 4.0,
			"flat_height": -float(surface.get("depth", 160.0)) if platform else 0.0,
			"planet_radius": 60000.0,
			"curve_from": 6000.0,
		},
		"landmarks": [],
		"atmosphere": tcfg.get("atmosphere", {}),
		"detail": types().get("detail", {}),
	}


## The planets you can fly to from place `id`: every other planet, where it hangs
## in this place's sky: "at" is the centre of its ball and "offset" its port, in
## metres from this place's own origin (its port; open space's is the system
## frame's origin).
##
## Issue #99: one map. Every place's scene is the same space, only shifted so its
## own origin is the origin (no turn, so the sun and the stars are the same in all
## of them): a point p here is p - offset in that planet's scene. Issue #573: all
## of it read from one system frame (system_centre, system_port), so a moon sees its
## sister moon and its grandparent the same way it sees its parent; "child" is a
## planet that is near this one, "parent" the one this one is near. Open space is
## never a neighbour.
static func neighbours(id: String, cc = null, own_cfg: Dictionary = {}) -> Array:
	if cc == null:
		cc = _content()
	var out: Array = []
	var all: Dictionary = cc.planets
	var mine: Dictionary = all.get(id, own_cfg)
	var here := system_port(id, cc) if all.has(id) or is_open_space(id) else _cfg_port(mine, cc)
	if here == Vector3.INF:
		return out
	var sys := system_of(id, cc) if all.has(id) or is_open_space(id) else str(mine.get("system", HOME_SYSTEM))
	for other in all:
		if other == id:
			continue
		if system_of(str(other), cc) != sys:
			continue        # issue #874: another star system is never in this sky
		var c = system_centre(str(other), cc)
		if c == null:
			continue
		var o: Dictionary = all[other]
		var n := _neighbour(o, (c as Vector3) - here, cc)
		n["offset"] = system_port(str(other), cc) - here
		n["child"] = str(o.get("near", "")) == id
		n["parent"] = str(mine.get("near", "")) == str(other)
		out.append(n)
	return out


## A planet's radius: its ball's (the world's sphere_radius, or a ball type's
## surface radius), else how big it looks from a neighbour's sky (body.radius).
static func ball_radius(o: Dictionary, cc = null) -> float:
	var t: Dictionary = types().get("types", {}).get(str(o.get("type", "sand")), {})
	if float(o.get("sphere_radius", 0.0)) > 0.0:
		return float(o.sphere_radius)       # issue #874: a generated ball world
	if o.has("world") and cc != null:
		var r := float(cc.get_world(str(o.world)).get("terrain", {}).get("sphere_radius", 0.0))
		if r > 0.0:
			return r
	if str(t.get("ground", "")) == "ball":
		return float(t.get("surface", {}).get("radius", 1500.0))
	var ob: Dictionary = o.get("body", {})
	return float(o.get("body_radius", ob.get("radius", t.get("body", {}).get("radius", 1000.0))))


## How close to a planet's surface its own scene takes over (issue #99), or 0 when
## it never hands over seamlessly (its parent's scene fades to it, as before).
static func handoff_altitude(type: String) -> float:
	return float(types().get("types", {}).get(type, {}).get("space", {}).get("handoff", 0.0))


static func _neighbour(o: Dictionary, at: Vector3, cc) -> Dictionary:
	var t: Dictionary = types().get("types", {}).get(str(o.get("type", "sand")), {})
	var body: Dictionary = t.get("body", {}).duplicate()
	body.merge(o.get("body", {}), true)          # the planet's own look from space wins
	# Issue #77: a planet that is a real ball (its world's terrain.sphere_radius)
	# looks its true size from a neighbour's sky. Issue #99: so does a ball type.
	var r := ball_radius(o, cc)
	var ball := str(t.get("ground", "")) == "ball" or float(o.get("sphere_radius", 0.0)) > 0.0
	if o.has("world") and cc != null:
		ball = ball or float(cc.get_world(str(o.world)).get("terrain", {}).get("sphere_radius", 0.0)) > 0.0
	return {
		"id": str(o.get("id", "")),
		"type": str(o.get("type", "sand")),
		"at": at,
		"ball": ball,
		"radius": r,
		"color": Color(str(body.get("color", "#a08060"))),
		"dark": Color(str(body.get("dark", "#504030"))),
		"bands": float(body.get("bands", 0.0)),          # > 0: banded like the sky painting
		"ring": body.get("ring", {}),                     # { inner, outer, color, normal }, radii
		"haze": body.get("haze", {}),                     # a gas ball's air: SpaceTravel.make_haze
		"relief": str(body.get("relief", "")),            # its dunes as a flat print (a cubemap), or ""
		"paint": str(body.get("paint", "")),              # a moon baked as paint on a smooth ball (a cubemap), or ""
		"relief_tilt": float(body.get("relief_tilt", 1.0)),
		"relief_crest": float(body.get("relief_crest", 0.12)),
		"sky_giant": bool(o.get("replaces_sky_painting", false)),
		# A gas ball's cloud tops, below its deck's level (radius): what you see of it.
		"cloud_radius": r - float(t.get("surface", {}).get("depth", 0.0)) if ball and str(t.get("surface", {}).get("kind", "")) == "gas" else r,
	}


## False when the painted ringed giant must not show in this planet's sky: the
## planet is the real giant, or the real one hangs in its sky (a neighbour with
## replaces_sky_painting).
static func sky_painting(cfg: Dictionary, near: Array) -> bool:
	if bool(cfg.get("replaces_sky_painting", false)):
		return false
	for n in near:
		if bool(n.get("sky_giant", false)):
			return false
	return true


## Generated names: the planet's (and its town's) own "name" in the config wins,
## reserved in the name book so nothing else gets it; otherwise the name engine.
static func reserve_names(p: Dictionary, book: NameBook = null) -> void:
	var b := book if book != null else WorldState.names
	var world: Dictionary = p.get("world", {})
	if str(p.get("name", "")) != "":
		b.reserve(str(p.name), "planet:" + str(world.get("id", p.id)))
	if str(p.get("town_name", "")) != "":
		b.reserve(str(p.town_name), "town:" + str(world.get("town", p.town_id)))


## The planet's display name (generated or reserved).
static func display_name(p: Dictionary, book: NameBook = null) -> String:
	reserve_names(p, book)
	return NameHooks.planet(p.get("world", {}), book)


static func clear_cache() -> void:
	_cache = {}
	_types = {}


static func _content():
	var cc := CoreContent.new()
	cc.load_from()
	return cc
