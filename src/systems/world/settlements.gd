class_name Settlements
extends Node3D
## Issue #877: the mountain country's towns, each on a flat-topped peak of its
## own (the planet's `settlements` block, content/core/planets/port_red.json).
## DesertLandforms already stands the peaks (settlement_buttes: one rock each,
## with a collider and the ship's ground); SettlementGen lays each town out; this
## node puts the town on its peak and gets you up there:
##   - the ground: every town box in the ship's ground (WorldGround, so a speeder
##     and a ship know its roofs and walls) and the way up (a lift's bridge, a
##     road's every piece), from the start, so you can land on a roof or ride the
##     road before you could see it;
##   - by sight (as the ranches, issue #717): its colliders, its lift (Lift: the
##     station's elevator in a glass tube, from the sand by the peak's foot to a
##     bridge onto the town's apron) or its road (HillRamp: a lit road curling up
##     round the peak, speeder wide, on piers), its look (the town's building kit
##     in the place's palette, content/look/settlements.json), its people (its own
##     folk, its barkeep and its stall keeper selling what the port's do) and
##     their own Townsfolk.
##
## A place's people carry the "ranch" meta (its id), so the town's own director
## leaves them to theirs, as the ranch villages'. Render rules: everything here
## is drawn to `draw_m` (one merged mesh per material a town), people sleep past
## `wake_m`, and the lamps are glow, not lights (a fire and the cantina's one each).

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownMarket := preload("res://src/systems/world/town_market.gd")
const RingWall := preload("res://src/systems/world/ring_wall.gd")
const Greybox := preload("res://src/systems/world/greybox.gd")
const LOOK_PATH := "res://content/look/settlements.json"
const DRAW_FADE := 150.0
const KEEPER_BACK := 1.3
const DECK_W := 4.0                ## the lift's bridge
const RAIL_H := 1.1
const SLAB := 0.5                  ## a road piece's and a bridge's thickness

## The town's building kit in a place's own paint: its shader's band and dirt go
## by world height, which means nothing on a peak half round the ball.
class SettleKit extends "res://src/systems/world/town_buildings.gd":
	var walls := Color("#d8c08e")
	var band := Color("#b9925a")

	func _init(m: LookMaterials, l: LookEnvironment) -> void:
		super(m, l)

	func _plaster(b: Dictionary, _band_y: float) -> Material:
		var i := absi(hash(str(b.id)))
		return mats.plaster(-1.0e7, -1.0e7, band, walls.lerp(Color.WHITE, float(i % 5) * 0.03))


var demo                           ## town_demo.gd
var ground: WorldGround
var planet: Dictionary = {}
var cfg: Dictionary = {}           ## the planet's settlements block
var look_cfg: Dictionary = {}
var places: Array = []             ## { id, label, place, lay, xf (the town's frame), rock (the peak's), root, height, lift?, ramp? }
var people: Array = []
var vendors: Array = []            ## { cfg, pos } as GearController.vendors; handed over once
var _vendors_given := 0
var folks: Dictionary = {}         ## place id -> its Townsfolk
var lifts: Array = []              ## Lift
var _cc: CoreContent
var _queue: Array = []
var _pending: Array = []           ## places not in sight yet
var _started := false
var _whole := false
var late := false
var _late_ids: Array = []
var _wake := 360.0
var _draw := 1600.0
static var _glass_mat: StandardMaterial3D


func setup(town_demo, world_ground: WorldGround, planet_cfg: Dictionary) -> void:
	demo = town_demo
	ground = world_ground
	planet = planet_cfg
	cfg = planet.get("cfg", {}).get("settlements", {})
	name = "Settlements"
	_wake = float(cfg.get("wake_m", 360.0))
	_draw = float(cfg.get("draw_m", 1600.0))


## Every place now (a staged handoff calls build_step once a frame instead).
func build() -> void:
	_whole = true
	while not build_step():
		pass


## The next piece: one place's colliders, way up, look or one person. True once
## what can be seen is built.
func build_step() -> bool:
	if not _started:
		_start()
	_take_in_sight()
	if _queue.is_empty():
		return true
	(_queue.pop_front() as Callable).call()
	return _queue.is_empty()


## After the town's first build: the next piece of a place that has come into sight.
func late_step() -> bool:
	if not _started:
		return false
	_take_in_sight()
	if _queue.is_empty():
		_start_late()
		return false
	(_queue.pop_front() as Callable).call()
	if _queue.is_empty():
		_start_late()
	return true


## Lay every place out on its peak and put it in the ship's ground.
func _start() -> void:
	_started = true
	_cc = CoreContent.shared()
	look_cfg = CoreContent.read_json(LOOK_PATH)
	var sp := ground.sphere()
	if sp == null or cfg.is_empty():
		return
	var data: Dictionary = demo.landforms.data if demo != null and demo.get("landforms") != null \
		and not (demo.landforms.data as Dictionary).is_empty() else DesertLandforms.load_for(planet)
	var spots := {}
	for m in DesertLandforms.mountain_spots(data, sp):
		spots[str(m.id)] = m
	for place in cfg.get("places", []):
		var m: Dictionary = spots.get("butte_" + str(place.id), {})
		if m.is_empty():
			continue
		var s := site(place, cfg, sp, m)
		_ground_boxes(s)
		places.append(s)
		_pending.append(s)


## A place on its peak: its layout, the peak's frame (`rock`: RockMountain's mesh
## frame, y up, the top at `height`) and the town's (`xf`: the layout's own, y 0 on
## the top, its floors' middle over the peak's), and its way up.
static func site(place: Dictionary, st: Dictionary, sp: PlanetSphere, m: Dictionary) -> Dictionary:
	var lay := SettlementGen.layout(place, st)
	var p: Dictionary = m.plan
	var pl := RockMountain.placement(sp, m.map, p)
	var g: Transform3D = pl.frame
	var rock := Transform3D(g.basis * Basis(Vector3.UP, float(pl.yaw)), g.origin - g.basis.y * float(pl.sink))
	var h := float(p.height)
	var c := SettlementGen.centre(lay)
	var s := { "id": str(place.id), "label": str(place.get("name", place.id)), "place": place, "lay": lay,
		"rock": rock, "xf": rock * Transform3D(Basis.IDENTITY, Vector3(-c.x, h, -c.y)), "height": h,
		"plan": p, "centre": c, "map": m.map }
	var tiers: Array = p.tiers
	var top_edge := RockMountain.wall(tiers[-1], 0.0, h)
	var apron := float(lay.bounds.max[0]) - c.x          # the town's gate side, in the peak's frame
	var inv := rock.affine_inverse()
	var sand := func(a: float, r: float) -> float:
		var w := rock * Vector3(cos(a) * r, 0.0, sin(a) * r)
		var mm := sp.world_to_map(w)
		return (inv * sp.surface_at(mm.x, mm.y)).y
	if place.has("lift") and bool(place.lift):
		var lc: Dictionary = st.get("lift", {})
		var rr := float(lc.get("car_radius", 2.6))
		var x := RockMountain._lobed(tiers[0], 0.0) + float(lc.get("out_m", 6.0)) + rr
		s["lift"] = { "x": x, "bottom": float(sand.call(0.0, x)), "top": h,
			"deck": [minf(apron, top_edge) - 0.5, x - rr - 0.35] }
	if place.has("ramp") and bool(place.ramp):
		var rc: Dictionary = st.get("ramp", {})
		var r := float(p.radius) + float(rc.get("out_m", 16.0)) + float(rc.get("width_m", 10.0)) * 0.5
		s["kerb_h"] = float(rc.get("kerb_h", 0.8))
		s["ramp"] = HillRamp.plan(rc, float(p.radius), h, minf(apron, top_edge),
			func(a: float) -> float: return float(sand.call(a, r)))
	return s


# ------------------------------------------------------------------ ground

## Every town box in the ship's ground in the town's frame (a round wall as its
## pieces), and the way up in the peak's.
func _ground_boxes(s: Dictionary) -> void:
	var xf: Transform3D = s.xf
	for b in s.lay.boxes:
		var id := "%s/%s" % [s.id, b.id]
		if str(b.kind) == "ring":
			var k := 0
			for p in RingWall.pieces(b):
				var hh: Vector3 = p.size * 0.5
				ground.add_box("%s_%d" % [id, k], "wall", -hh, hh, "", false, xf * Transform3D(p.basis, p.center))
				k += 1
			continue
		ground.add_box(id, str(b.kind), WorldGround._v3(b.min), WorldGround._v3(b.max), str(b.get("rise_toward", "")), false, xf)
	var rock: Transform3D = s.rock
	for p in way_up(s):
		ground.add_box("%s/%s" % [s.id, p.id], str(p.kind), p.min, p.max, str(p.get("rise", "")), false, rock * p.xf)
	ground.invalidate_index()


## The way up as boxes in the peak's frame: { id, kind, min, max, rise?, xf }. A
## lift's bridge and rails; a road's pieces, kerbs and its bridge in.
static func way_up(s: Dictionary) -> Array:
	var out: Array = []
	var h := float(s.height)
	if s.has("lift"):
		var l: Dictionary = s.lift
		var x0 := float(l.deck[0])
		var x1 := float(l.deck[1])
		var mid := Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, 0, 0))
		var hl := (x1 - x0) * 0.5
		out.append({ "id": "lift_deck", "kind": "floor", "min": Vector3(-hl, h - SLAB, -DECK_W * 0.5),
			"max": Vector3(hl, h, DECK_W * 0.5), "xf": mid })
		for sgn in [-1.0, 1.0]:
			out.append({ "id": "lift_rail_%s" % ("n" if sgn > 0 else "s"), "kind": "wall",
				"min": Vector3(-hl, h, sgn * DECK_W * 0.5 - (0.15 if sgn > 0 else -0.0)),
				"max": Vector3(hl, h + RAIL_H, sgn * DECK_W * 0.5 + (0.0 if sgn > 0 else 0.15)), "xf": mid })
	if s.has("ramp"):
		var rp: Dictionary = s.ramp
		var w := float(rp.width)
		var kerb := float(s.get("kerb_h", 0.8))
		var segs: Array = rp.segments
		for i in segs.size():
			var sg: Dictionary = segs[i]
			var hl := float(sg.len) * 0.5
			out.append({ "id": "road_%02d" % i, "kind": "floor", "rise": "+x", "min": Vector3(-hl, float(sg.y0), -w * 0.5),
				"max": Vector3(hl, float(sg.y1), w * 0.5), "xf": sg.xf })
			# Kerbs: the outer side the whole way, the inner side except where the
			# bridge turns in at the top.
			out.append({ "id": "road_%02d_kerb_o" % i, "kind": "wall", "min": Vector3(-hl, float(sg.y0), -w * 0.5),
				"max": Vector3(hl, float(sg.y1) + kerb, -w * 0.5 + 0.4), "xf": sg.xf })
			if not bool(sg.get("mouth", false)):
				out.append({ "id": "road_%02d_kerb_i" % i, "kind": "wall", "min": Vector3(-hl, float(sg.y0), w * 0.5 - 0.4),
					"max": Vector3(hl, float(sg.y1) + kerb, w * 0.5), "xf": sg.xf })
		var bx: Dictionary = rp.bridge
		var x0 := float(bx.x0)
		var x1 := float(bx.x1)
		var mid := Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, 0, 0))
		var hl := (x1 - x0) * 0.5
		out.append({ "id": "road_bridge", "kind": "floor", "min": Vector3(-hl, h - SLAB, -w * 0.5), "max": Vector3(hl, h, w * 0.5), "xf": mid })
		var r := float(rp.radius)
		out.append({ "id": "road_bridge_kerb_n", "kind": "wall", "min": Vector3(-hl, h, w * 0.5 - 0.4), "max": Vector3(hl, h + kerb, w * 0.5), "xf": mid })
		var sx := r - w * 0.5 - (x0 + x1) * 0.5
		out.append({ "id": "road_bridge_kerb_s", "kind": "wall", "min": Vector3(-hl, h, -w * 0.5), "max": Vector3(sx, h + kerb, -w * 0.5 + 0.4), "xf": mid })
		out.append({ "id": "road_bridge_end", "kind": "wall", "min": Vector3(hl - 0.4, h, -w * 0.5), "max": Vector3(hl, h + kerb, w * 0.5), "xf": mid })
	return out


# ------------------------------------------------------------------ by sight

func _take_in_sight() -> void:
	for s in _pending.duplicate():
		var at: Vector3 = (s.xf as Transform3D).origin
		if _whole or demo == null or not demo.has_method("could_see") or demo.could_see(at, float(s.height) + 15.0):
			_pending.erase(s)
			_queue.append(_place.bind(s))
			if late:
				_late_ids.append(str(s.id))


func _place(s: Dictionary) -> void:
	var root := Node3D.new()
	root.name = str(s.id).to_pascal_case()
	add_child(root)
	root.global_transform = s.xf
	var rock := Node3D.new()
	rock.name = "Peak"
	add_child(rock)
	rock.global_transform = s.rock
	s["root"] = root
	s["rock_node"] = rock
	var parts: Array = [_colliders.bind(s)]
	if s.has("lift"):
		parts.append(_lift.bind(s))
	if demo != null and bool(demo.get("use_look")):
		parts.append(_dress.bind(s))
		if s.has("ramp") or s.has("lift"):
			parts.append(_dress_way.bind(s))
	if demo == null or demo.get("with_npcs") != false:
		for m in s.lay.markers:
			if m.has("soldier"):
				parts.append(_add_person.bind(s, m))
	_queue = parts + _queue


## One body for the town (its boxes, a round wall's pieces) and one for its way up.
func _colliders(s: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "Solid"
	for b in s.lay.boxes:
		if str(b.kind) == "ring":
			for p in RingWall.pieces(b):
				_shape(body, Transform3D(p.basis, p.center), p.size)
			continue
		var cs := Greybox.center_size(b)
		var tb := Greybox.turned(b)
		_shape(body, Transform3D(tb.get("basis", Basis.IDENTITY), cs[0]), tb.get("size", cs[1]),
			str(b.get("shape", "")) == "round")
	(s.root as Node3D).add_child(body)
	var way := StaticBody3D.new()
	way.name = "WayUp"
	for p in way_up(s):
		var xf: Transform3D = p.xf
		var mn: Vector3 = p.min
		var mx: Vector3 = p.max
		if str(p.get("rise", "")) == "+x":
			var len := mx.x - mn.x
			var sl := HillRamp.slab(len, mn.y, mx.y, SLAB)
			_shape(way, xf * Transform3D(sl.basis, sl.origin + Vector3(0, 0, (mn.z + mx.z) * 0.5)),
				Vector3(sqrt(len * len + pow(mx.y - mn.y, 2.0)), SLAB, mx.z - mn.z))
		elif str(p.id).contains("_kerb_") and str(p.id).begins_with("road_") and not str(p.id).begins_with("road_bridge"):
			# A kerb on a sloped piece: the slab's slope, standing on it.
			var len := mx.x - mn.x
			var y0 := mn.y
			var y1 := mx.y - float(s.get("kerb_h", 0.8))
			var kerb := mx.y - y1
			var sl := HillRamp.slab(len, y0, y1, -kerb)
			_shape(way, xf * Transform3D(sl.basis, sl.origin + Vector3(0, 0, (mn.z + mx.z) * 0.5)),
				Vector3(sqrt(len * len + pow(y1 - y0, 2.0)), kerb, mx.z - mn.z))
		else:
			_shape(way, xf * Transform3D(Basis.IDENTITY, (mn + mx) * 0.5), mx - mn)
	if way.get_child_count() > 0:
		(s.rock_node as Node3D).add_child(way)
	else:
		way.free()


static func _shape(body: StaticBody3D, at: Transform3D, size: Vector3, round := false) -> void:
	var cs := CollisionShape3D.new()
	if round:
		var c := CylinderShape3D.new()
		c.radius = minf(size.x, size.z) * 0.5
		c.height = size.y
		cs.shape = c
	else:
		var b := BoxShape3D.new()
		b.size = size.abs()
		cs.shape = b
	cs.transform = at
	body.add_child(cs)


## The lift: its car, its tube's panels, its look's moving part.
func _lift(s: Dictionary) -> void:
	var l: Dictionary = s.lift
	var lift := Lift.new()
	var who := func() -> Vector3:
		var p: Node3D = demo._player if demo != null else null
		return p.global_position if p != null and is_instance_valid(p) and p.is_inside_tree() else Vector3.INF
	lift.setup(cfg.get("lift", {}), Vector2(float(l.x), 0.0), float(l.bottom), float(l.top), who)
	(s.rock_node as Node3D).add_child(lift)
	lift.walls(int(look_cfg.get("lift", {}).get("panels", 10)), float(look_cfg.get("lift", {}).get("tube_height_extra_m", 3.0)))
	s["lift_node"] = lift
	lifts.append(lift)


# ------------------------------------------------------------------ people

func _add_person(s: Dictionary, m: Dictionary) -> NpcBody:
	var xf: Transform3D = s.xf
	var here := xf * (WorldGround._v3(m.pos) + Vector3(0, 0.05, 0))
	var face_l: Vector3 = WorldGround._v3(m.face) if m.has("face") else Vector3(SettlementGen.centre(s.lay).x, 0, SettlementGen.centre(s.lay).y)
	var face := xf * face_l
	var post := "%s/%s" % [s.id, m.id]
	var up := xf.basis.y.normalized()
	var fw := face - here
	fw -= up * fw.dot(up)
	var g: NpcBody = demo.make_soldier(str(m.soldier), here, atan2(fw.x, fw.z), post, "npc:" + post)
	if g == null:
		return null
	g.set_meta("ranch", str(s.id))
	if m.has("patrol"):
		g.set_meta("settle_patrol", route_points(s, str(m.patrol)))
	people.append(g)
	_trade_for(s, m, post)
	return g


## A stall keeper's and the barkeep's trade: the port's vendors, at the counter.
func _trade_for(s: Dictionary, m: Dictionary, post: String) -> void:
	var trade: Dictionary = cfg.get("trade", {})
	var id := str(m.id)
	var vid := ""
	var at := Vector3.INF
	if id.begins_with("vendor_"):
		vid = str(s.place.get("stall", trade.get(str(s.place.get("kind", "town")), "")))
		at = _nearest_stall(s, WorldGround._v3(m.pos))
	elif str(m.get("soldier", "")).ends_with("_barkeep"):
		vid = str(trade.get("bar", ""))
		at = _box_middle(s, "bar_counter")
	if vid == "" or at == Vector3.INF:
		return
	var v := _cc.get_vendor(vid)
	if v.is_empty():
		return
	v = v.duplicate(true)
	v["marker"] = post
	vendors.append({ "cfg": v, "pos": (s.xf as Transform3D) * at })


## The counter top of the stall nearest a keeper (TownGen's square names its
## stalls by side, a ring's and a ledge's are stall_1).
func _nearest_stall(s: Dictionary, p: Vector3) -> Vector3:
	var best := Vector3.INF
	for b in s.lay.boxes:
		if str(b.get("look", "")) != "stall":
			continue
		var c := _box_middle(s, str(b.id))
		if best == Vector3.INF or Vector2(c.x - p.x, c.z - p.z).length() < Vector2(best.x - p.x, best.z - p.z).length():
			best = c
	return best


func _box_middle(s: Dictionary, id: String) -> Vector3:
	for b in s.lay.boxes:
		if str(b.id) == id:
			var cs := Greybox.center_size(b)
			return Vector3((cs[0] as Vector3).x, float(b.max[1]), (cs[0] as Vector3).z)
	return Vector3.INF


## A route's points in the world (on the town's floor).
static func route_points(s: Dictionary, rid: String) -> Array:
	for r in s.lay.routes:
		if str(r.id) == rid:
			return (r.points as Array).map(func(q): return (s.xf as Transform3D) * Vector3(float(q[0]), 0.05, float(q[1])))
	return []


func start_brains() -> void:
	for s in places:
		_brains_for(s)
	_give_vendors()
	var gear = demo.get("gear")
	if gear == null:
		return
	var town_open: Callable = gear.vendor_open
	var town_line: Callable = gear.closed_line
	gear.vendor_open = func(marker: String) -> bool:
		if _folk_for(marker) != null:
			return vendor_open(marker)
		return not town_open.is_valid() or bool(town_open.call(marker))
	gear.closed_line = func(marker: String) -> String:
		var f = _folk_for(marker)
		if f != null:
			return f.closed_line(marker)
		return str(town_line.call(marker)) if town_line.is_valid() else ""


func _brains_for(s: Dictionary) -> void:
	if folks.has(str(s.id)) or not demo.npc_brains:
		return
	var mine: Array = people.filter(func(g): return is_instance_valid(g) and str(g.get_meta("ranch", "")) == str(s.id))
	if mine.is_empty():
		return
	var f = demo.make_townsfolk("Settlement_" + str(s.id), mine, str(s.label))
	folks[str(s.id)] = f
	for g in mine:
		if g.has_meta("settle_patrol") and f.brains.has(g):
			var pts: Array = g.get_meta("settle_patrol")
			if pts.size() >= 2:
				f.brains[g].patrol_points = pts


func _start_late() -> void:
	if _late_ids.is_empty():
		return
	for s in places:
		if _late_ids.has(str(s.id)):
			_brains_for(s)
	_late_ids.clear()
	_give_vendors()


func vendor_open(post: String) -> bool:
	var f = _folk_for(post)
	return f == null or bool(f.vendor_open(post))


func _folk_for(post: String):
	return folks.get(post.get_slice("/", 0), null) if post.contains("/") else null


func _give_vendors() -> void:
	var gear = demo.get("gear") if demo != null else null
	if gear == null or _vendors_given >= vendors.size():
		return
	for i in range(_vendors_given, vendors.size()):
		gear.vendors.append(vendors[i])
	_vendors_given = vendors.size()


func _physics_process(_dt: float) -> void:
	_give_vendors()
	var p: Node3D = demo._player if demo != null else null
	if p == null:
		return
	for g in people:
		if is_instance_valid(g) and not g.dead:
			var far: bool = g.global_position.distance_to(p.global_position) > _wake
			g.process_mode = Node.PROCESS_MODE_DISABLED if far else Node.PROCESS_MODE_INHERIT
	people = people.filter(func(g): return is_instance_valid(g))


func place_by_id(id: String) -> Dictionary:
	for s in places:
		if str(s.id) == id:
			return s
	return {}


## A place's marker in the world.
static func marker_point(s: Dictionary, id: String) -> Vector3:
	for m in s.lay.markers:
		if str(m.id) == id:
			return (s.xf as Transform3D) * WorldGround._v3(m.pos)
	return Vector3.INF


# ------------------------------------------------------------------ the look

func _palette(s: Dictionary) -> Dictionary:
	return look_cfg.get("palettes", {}).get(str(s.place.get("palette", "pilgrim")), {})


func _mats() -> LookMaterials:
	var d = demo.get("decor")
	return d.mats if d != null and d.get("mats") != null else demo._flat_mats()


## The town in its palette: houses and towers in the building kit, walls, roofs
## and lintels in plaster, the paving over the rock, the stall in the market kit,
## the stage, the shrine, the fire, the cantina's glow. One merged mesh a material.
func _dress(s: Dictionary) -> void:
	var mats := _mats()
	var pal := _palette(s)
	var kit := SettleKit.new(mats, demo.look)
	kit.walls = Color(str(pal.get("walls", "#d8c08e")))
	kit.band = Color(str(pal.get("band", "#b9925a")))
	var market := TownMarket.new(kit)
	var looks: Dictionary = CoreContent.read_json(ItemKit.LOOKS_PATH).get("stalls", {}).get("vendors", {})
	var wall := mats.plaster(-1.0e7, -1.0e7, kit.band, kit.walls)
	var roof := mats.flat(Color(str(pal.get("roof", "#c9ae7e"))), 0.9)
	var paving := mats.flat(Color(str(pal.get("paving", "#bfa77c"))), 0.95)
	var trim := mats.flat(Color(str(pal.get("trim", "#8a6a44"))), 0.8)
	var root: Node3D = s.root
	var stalls: Array = []
	var backs := {}
	var trades := {}
	var trade: Dictionary = cfg.get("trade", {})
	for b in s.lay.boxes:
		var cs := Greybox.center_size(b)
		var c: Vector3 = cs[0]
		var size: Vector3 = cs[1]
		var lk := str(b.get("look", ""))
		kit._xf = Transform3D.IDENTITY
		match str(b.kind):
			"floor":
				kit.part(kit.box(size.x, 0.12, size.z), paving, Vector3(c.x, float(b.max[1]) - 0.04, c.z))
				continue
			"ring":
				for p in RingWall.pieces(b):
					var ps: Vector3 = p.size
					kit.part(kit.box(ps.x, ps.y + 0.4, ps.z), wall, (p.center as Vector3) - Vector3(0, 0.2, 0), p.basis)
					kit.part(kit.box(ps.x + 0.2, 0.18, ps.z + 0.25), trim, (p.center as Vector3) + Vector3(0, ps.y * 0.5 + 0.09, 0), p.basis)
				continue
		if lk == "stall":
			var box: Dictionary = (b as Dictionary).duplicate()
			box.id = "%s_%s" % [s.id, b.id]
			stalls.append(box)
			var vid := str(s.place.get("stall", trade.get(str(s.place.get("kind", "town")), "")))
			if looks.has(vid):
				trades[box.id] = looks[vid]
			continue
		if lk == "stall_back":
			backs["%s_%s" % [s.id, b.id]] = b
			continue
		if lk == "shrine":
			_shrine(kit, mats, pal, c, size, float(b.min[1]))
			continue
		if lk != "" and kit.build(b):
			continue
		kit._xf = Transform3D.IDENTITY
		match str(b.kind):
			"roof":
				kit.part(kit.box(size.x + 0.4, size.y, size.z + 0.4), roof, c)
			"counter":
				kit.part(kit.box(size.x, size.y, size.z), kit.crate_woods[0], c)
				kit.part(kit.box(size.x + 0.15, 0.08, size.z + 0.15), trim, Vector3(c.x, float(b.max[1]) + 0.04, c.z))
			_:
				kit.part(kit.box(size.x, size.y, size.z), wall, c)
	market.dress(root, stalls, backs, trades)
	_fire(s, kit, mats, pal)
	_cantina_glow(s, kit, mats)
	kit.flush_merged(root, Transform3D.IDENTITY)
	_draw_range(root)


## A low stone plinth with a stone on it and two candles: the ledges' shrines.
func _shrine(kit, mats: LookMaterials, pal: Dictionary, c: Vector3, size: Vector3, y0: float) -> void:
	var stone := mats.flat(Color("#8a7f72"), 0.95)
	kit.part(kit.box(size.x, 0.5, size.z), stone, Vector3(c.x, y0 + 0.25, c.z))
	kit.part(kit.box(size.x * 0.45, 1.3, size.z * 0.3), stone, Vector3(c.x, y0 + 1.15, c.z), Basis(Vector3.UP, 0.2))
	var flame := mats.glow(Color(str(pal.get("fire", "#ffb35c"))))
	for k in [-1.0, 1.0]:
		kit.part(kit.cyl(0.06, 0.06, 0.3, 6), flame, Vector3(c.x + k * size.x * 0.3, y0 + 0.65, c.z + size.z * 0.3))


## The fire (a ring or a ledge's has one at its "fire" marker), its crates and its light.
func _fire(s: Dictionary, kit, mats: LookMaterials, pal: Dictionary) -> void:
	var at := Vector3.INF
	for m in s.lay.markers:
		if str(m.id) == "fire":
			at = WorldGround._v3(m.pos)
	if at == Vector3.INF:
		return
	kit._xf = Transform3D.IDENTITY
	var stone := mats.flat(Color("#6f655b"), 0.95)
	var ember := mats.glow(Color(str(pal.get("fire", "#ff7a2a"))))
	kit.part(kit.ring(0.7, 1.05, -0.1, 0.35), stone, at)
	kit.part(kit.cyl(0.65, 0.65, 0.12, 12), ember, at + Vector3(0, 0.08, 0))
	var was: bool = kit.solid
	kit.solid = true
	for i in 4:
		var a := TAU * (float(i) + 0.35) / 4.0
		kit.part(kit.box(0.7, 0.45, 0.6), kit.crate_woods[i % kit.crate_woods.size()],
			at + Vector3(cos(a), 0, sin(a)) * 2.6 + Vector3(0, 0.22, 0), Basis(Vector3.UP, a + 0.4))
	kit.solid = was
	_light(s.root, at + Vector3(0, 1.0, 0), Color(str(pal.get("fire", "#ff9a4a"))), 1.6, 9.0)


## A warm strip of light under the cantina's roof and one real light inside.
func _cantina_glow(s: Dictionary, kit, mats: LookMaterials) -> void:
	for b in s.lay.boxes:
		if str(b.id) != "cantina_roof":
			continue
		var cs := Greybox.center_size(b)
		var c: Vector3 = cs[0]
		var size: Vector3 = cs[1]
		kit._xf = Transform3D.IDENTITY
		kit.part(kit.box(size.x * 0.6, 0.08, 0.25), kit.window_glow, Vector3(c.x, float(b.min[1]) - 0.1, c.z))
		_light(s.root, Vector3(c.x, float(b.min[1]) - 1.0, c.z), Color("#ffb46a"), 1.2, maxf(size.x, size.z) * 0.6)


func _light(parent: Node3D, at: Vector3, color: Color, energy: float, rng: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = rng
	light.distance_fade_enabled = true
	light.distance_fade_begin = 120.0
	light.distance_fade_length = 30.0
	light.position = at
	parent.add_child(light)


## The way up: a lift's glass tube, its car and its bridge; a road's deck on its
## piers, its kerbs and its lamps. In the peak's frame.
func _dress_way(s: Dictionary) -> void:
	var mats := _mats()
	var pal := _palette(s)
	var kit := SettleKit.new(mats, demo.look)
	var lk: Dictionary = look_cfg.get("lift", {})
	var lamp: Dictionary = look_cfg.get("lamp", {})
	var frame := mats.flat(Color(str(lk.get("frame", "#3b3f44"))), 0.5, 0.6)
	var deck := mats.flat(Color(str(pal.get("paving", "#bfa77c"))), 0.95)
	var trim := mats.flat(Color(str(pal.get("trim", "#8a6a44"))), 0.8)
	var post := mats.flat(Color(str(lamp.get("post", "#3b3631"))), 0.7, 0.3)
	var head := _glow(mats, Color(str(lamp.get("glow", "#ffc46a"))), float(lamp.get("energy", 3.0)))
	var rock: Node3D = s.rock_node
	kit._xf = Transform3D.IDENTITY
	for p in way_up(s):
		var xf: Transform3D = p.xf
		var mn: Vector3 = p.min
		var mx: Vector3 = p.max
		var mat: Material = deck if str(p.kind) == "floor" else trim
		if str(p.get("rise", "")) == "+x":
			var len := mx.x - mn.x
			var sl := HillRamp.slab(len, mn.y, mx.y, SLAB)
			kit.part(kit.box(sqrt(len * len + pow(mx.y - mn.y, 2.0)), SLAB, mx.z - mn.z), deck, (xf * sl).origin, xf.basis * sl.basis)
			# A pier under its middle, down to the sand (or the shelf below).
			var under := (mn.y + mx.y) * 0.5 - SLAB
			var foot := _sand_y(s, xf.origin) - 1.0
			if under - foot > 0.5:
				kit.part(kit.box(1.4, under - foot, 2.2), trim, xf * Vector3(0, (under + foot) * 0.5, 0), xf.basis)
			continue
		if str(p.id).begins_with("road_") and str(p.id).contains("_kerb_") and not str(p.id).begins_with("road_bridge"):
			var len := mx.x - mn.x
			var y1 := mx.y - float(s.get("kerb_h", 0.8))
			var kh := mx.y - y1
			var sl := HillRamp.slab(len, mn.y, y1, -kh)
			kit.part(kit.box(sqrt(len * len + pow(y1 - mn.y, 2.0)), kh, mx.z - mn.z), trim,
				(xf * Transform3D(sl.basis, sl.origin + Vector3(0, 0, (mn.z + mx.z) * 0.5))).origin, xf.basis * sl.basis)
			continue
		kit.part(kit.box(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z), mat, xf * ((mn + mx) * 0.5), xf.basis)
	var lamps: Array = (s.ramp.lamps as Array).duplicate() if s.has("ramp") else []
	if s.has("lift"):
		var l: Dictionary = s.lift
		var x := float(l.deck[0]) + 1.0
		while x < float(l.deck[1]) - 1.0:
			lamps.append(Vector3(x, float(s.height), DECK_W * 0.5 - 0.2))
			lamps.append(Vector3(x, float(s.height), -DECK_W * 0.5 + 0.2))
			x += 9.0
		lamps.append(Vector3(float(l.x) + 4.0, float(l.bottom), 3.0))
		lamps.append(Vector3(float(l.x) + 4.0, float(l.bottom), -3.0))
		_tube(s, kit, mats, lk, frame)
	var lh := float(lamp.get("height_m", 4.5))
	for q in lamps:
		var at: Vector3 = q
		kit.part(kit.box(0.18, lh, 0.18), post, at + Vector3(0, lh * 0.5, 0))
		kit.part(kit.box(0.5, 0.25, 0.5), head, at + Vector3(0, lh + 0.1, 0))
	kit.flush_merged(rock, Transform3D.IDENTITY)
	_draw_range(rock)


## The glass tube: a glass cylinder, posts at its panels' seams, a ring every few
## metres and a glowing band at each door; the car's disc follows the car.
func _tube(s: Dictionary, kit, mats: LookMaterials, lk: Dictionary, frame: Material) -> void:
	var l: Dictionary = s.lift
	var lift: Lift = s.get("lift_node")
	var r := (lift.radius if lift != null else 2.6) + 0.35
	var b := float(l.bottom)
	var t := float(l.top) + float(lk.get("tube_height_extra_m", 3.0))
	var c := Vector3(float(l.x), 0, 0)
	var glass := _glass(mats)
	kit.part(kit.cyl(r, r, t - b, 24), glass, c + Vector3(0, (t + b) * 0.5, 0))
	var n := int(lk.get("panels", 10))
	for k in n:
		var a := TAU * float(k) / float(n)
		kit.part(kit.box(0.14, t - b, 0.14), frame, c + Vector3(cos(a) * r, (t + b) * 0.5, sin(a) * r))
	var y := b
	while y <= t:
		kit.part(kit.ring(r - 0.05, r + 0.12, -0.06, 0.12), frame, c + Vector3(0, y, 0))
		y += 6.0
	kit.part(kit.cyl(r + 0.3, r + 0.3, 0.4, 24), frame, c + Vector3(0, t + 0.2, 0))
	var glow := _glow(mats, Color(str(lk.get("glow", "#9fe3ff"))), 2.5)
	kit.part(kit.box(0.2, 0.2, 3.2), glow, c + Vector3(r + 0.1, b + 3.3, 0))
	kit.part(kit.box(0.2, 0.2, 3.2), glow, c + Vector3(-r - 0.1, float(l.top) + 3.3, 0))
	if lift != null:
		var car := MeshInstance3D.new()
		car.name = "CarLook"
		var cm := CylinderMesh.new()
		cm.top_radius = lift.radius
		cm.bottom_radius = lift.radius
		cm.height = Lift.CAR_H
		car.mesh = cm
		car.material_override = mats.flat(Color(str(lk.get("car", "#c9c2b4"))), 0.6, 0.3)
		var rim := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = lift.radius - 0.1
		rm.outer_radius = lift.radius + 0.05
		rim.mesh = rm
		rim.material_override = glow
		rim.position = Vector3(0, Lift.CAR_H * 0.5, 0)
		car.add_child(rim)
		car.position = Vector3(float(l.x), b, 0)
		lift.car_look = car
		lift.add_child(car)
		for mi in [car, rim]:
			mi.visibility_range_end = _draw
			mi.visibility_range_end_margin = DRAW_FADE
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _sand_y(s: Dictionary, p: Vector3) -> float:
	var sp := ground.sphere()
	var w := (s.rock as Transform3D) * p
	var m := sp.world_to_map(w)
	return ((s.rock as Transform3D).affine_inverse() * sp.surface_at(m.x, m.y)).y


## The glass: one material for every tube (the look file's colour).
func _glass(_mats_unused: LookMaterials) -> StandardMaterial3D:
	if _glass_mat == null:
		var g: Dictionary = look_cfg.get("glass", {})
		var c := Color(str(g.get("colour", "#9fd6e8")))
		c.a = float(g.get("alpha", 0.28))
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.albedo_color = c
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.metallic = 0.6
		_glass_mat.roughness = float(g.get("rough", 0.05))
		_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass_mat


## A glow, cached by colour (LookMaterials.glow makes a new one each call).
static var _glows := {}
func _glow(mats: LookMaterials, c: Color, energy: float) -> StandardMaterial3D:
	var key := "%s/%s" % [c.to_html(), energy]
	if not _glows.has(key) or not is_instance_valid(_glows[key]):
		var m := mats.glow(c)
		m.emission_energy_multiplier = energy
		_glows[key] = m
	return _glows[key]


func _draw_range(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.visibility_range_end <= 0.0:
			gi.visibility_range_end = _draw
			gi.visibility_range_end_margin = DRAW_FADE
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
