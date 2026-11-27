class_name SpeederStall
extends Node3D
## A speeder mechanic's stall at a race crew's hangout: Dorrin's shop where the
## racers hang out, kept by one of his cousins (Torrin by the basin crew, Jorrin
## by the salt crew). Same shop as Dorrin's (SpeederShop: paint, looks,
## performance, race gear, the Grav Lifter, scrap, and buying a new speeder that
## waits in the row outside the town's back gate); only the name, words and look
## differ (content/core/vehicles/speeder_upgrades.json "shops").
##
##   [E] beside him  -- the shop menu.
##
## He works on a speeder of yours parked on the lift pad beside his stall (within
## the shop's bay_radius of the "bay" point).
##
## A crew file's "shop" block places it (content/core/racing/crews/): "id" (the
## shop), "at" ([x, z] in the hangout's frame) and "yaw_deg". RaceCrew builds it.
## The layout is one location file for every stall
## (content/core/locations/speeder_stall.json), the colours are
## content/look/speeder_stall.json. Colliders (the counter, the rack) are built
## with the look off too; the look layer only dresses them (one MultiMesh per
## mesh and material, through the building kit).

const TownBuildings := preload("res://src/systems/world/town_buildings.gd")
const LOCATION := "speeder_stall"
const LOOK_PATH := "res://content/look/speeder_stall.json"

static var _bulbs := {}               ## "<LookMaterials id>/<kind>" -> the stalls' shared glows (bulb, neon, screen)
static var _tori := {}                ## "<inner>_<outer>" -> a TorusMesh shared by every stall

var demo                              ## town_demo.gd
var ground: WorldGround
var gear: GearController              ## its HUD (prompt, toast) and its focus (E is shared)
var player: CharacterBody3D
var shop_id := ""
var cfg: Dictionary = {}              ## SpeederUpgrades.shop(shop_id)
var shop: SpeederShop
var menu: DroidMenu                   ## the shop's
var mechanic: MerchantNPC
var xf := Transform3D()               ## the stall's frame: +x toward the customer
var points: Dictionary = {}
var in_reach := false
var _to_ground: Callable              ## (Vector3) -> Vector3: a point dropped onto the sand


## `frame`: the stall's frame in the world (origin on the sand); `to_ground`
## drops a world point onto the sand (RaceCourse.to_world_near).
func setup(town_demo, world_ground: WorldGround, frame: Transform3D, id: String, to_ground: Callable) -> void:
	demo = town_demo
	ground = world_ground
	xf = frame
	shop_id = id
	_to_ground = to_ground
	gear = demo.gear if demo != null and "gear" in demo else null
	player = demo._player if demo != null and "_player" in demo else null
	name = "SpeederStall_" + id


func _ready() -> void:
	cfg = SpeederUpgrades.shop(shop_id)
	if cfg.is_empty():
		push_error("SpeederStall: no shop " + shop_id + " in speeder_upgrades.json")
		return
	shop = SpeederShop.new()
	shop.setup(demo, gear, cfg, func(): return world_point("bay"))
	add_child(shop)
	menu = shop.menu
	var loc: Dictionary = demo._content().get_location(LOCATION)
	for k in loc.get("points", {}):
		points[k] = WorldGround._v3(loc.points[k])
	_build_solids(loc)
	if demo.use_look:
		_dress(loc)
	_build_mechanic()


func npc_name() -> String:
	return shop.npc_name() if shop != null else str(cfg.get("name", "the mechanic"))


## A point from the location file, in the world, on the sand.
func world_point(id: String) -> Vector3:
	var lp: Vector3 = points.get(id, Vector3.ZERO)
	var p: Vector3 = xf * Vector3(lp.x, 0.0, lp.z)
	return _to_ground.call(p) if _to_ground.is_valid() else p


## Your speeder parked on his pad, or null.
func speeder_in_bay() -> SpeederNode:
	return shop.speeder_in_bay() if shop != null else null


# ------------------------------------------------------------------ frame

func _physics_process(_dt: float) -> void:
	if shop == null or player == null or mechanic == null or shop.busy():
		return
	var p := player.global_position
	var at := mechanic.global_position
	in_reach = not player.piloting and Vector2(p.x - at.x, p.z - at.z).length() <= float(cfg.get("reach", 3.8)) \
		and absf(p.y - at.y) <= 2.0 and (gear == null or gear.focus.is_empty())
	if not in_reach:
		return
	if gear != null and gear.hud != null:
		gear.hud.set_prompt(shop.label("talk") % npc_name())
	if not player.locked and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		talk()


## [E] beside him: the shop menu (SpeederShop.talk).
func talk() -> void:
	shop.talk()


# ------------------------------------------------------------------ him

func _build_mechanic() -> void:
	if demo.use_look:
		mechanic = MerchantNPC.new(CharacterKit.new(demo._flat_mats(), 0.0), "local", cfg.get("outfit", {}))
	else:
		mechanic = MerchantNPC.new(null)
	mechanic.name = "Mechanic"
	add_child(mechanic)
	# Behind his counter, facing where you stand; he turns to you as you come near.
	mechanic.plant(xf.basis, world_point("mechanic"), 0.0, player)
	mechanic.rest_yaw = mechanic.yaw_to(world_point("customer"))
	mechanic.face_yaw = mechanic.rest_yaw
	mechanic.look_at_target = player
	shop.speaker = mechanic


# ------------------------------------------------------------------ colliders

## One body, a box per building in the location file (the counter, the rack):
## the sand's collider only follows the player, these stand on their own.
func _build_solids(loc: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "StallSolids"
	for b in loc.get("buildings", []):
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var c := WorldGround._v3(b.get("position", [0, 0, 0]))
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = s
		col.shape = box
		col.transform = Transform3D(Basis.IDENTITY, c + Vector3(0, s.y * 0.5, 0))
		body.add_child(col)
	add_child(body)
	body.global_transform = xf


# ------------------------------------------------------------------ the look

const AWNING_X0 := -3.0               ## the awning's back and front edges (x), and its height over the counter
const AWNING_X1 := 2.0
const AWNING_Y := 3.0
const AWNING_TILT := 0.1              ## radians it slopes down toward the customer

## The counter and rack (from their boxes), two walls of patched scrap sheet, a
## striped awning on four braced poles with a valance, a string of bulbs and a
## hanging lamp, a neon gear on the back wall, crates, canisters and a generator,
## and the lift pad with its gantry, bollards, control post and a spare engine on
## a stand. Every metal is the favela's painted metal (LookMaterials.painted, the
## same textures as its shacks), the wood the market's planks, the awning its
## canvas. All of it is one mesh a material (TownBuildings.flush_merged).
func _dress(loc: Dictionary) -> void:
	var mats: LookMaterials = demo._flat_mats()
	var look: LookEnvironment = demo.get("look") as LookEnvironment
	var m := look_mats(mats, look)
	var kit := TownBuildings.new(mats, look)
	kit._xf = xf
	for b in loc.get("buildings", []):
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var p := WorldGround._v3(b.get("position", [0, 0, 0]))
		match str(b.get("id", "")):
			"counter":
				dress_counter(kit, m, p, s, _sand_floor(p, s))
			"rack":
				_dress_rack(kit, m, p, s)
			"back_wall":
				scrap_wall(kit, m, p, s, Vector3.BACK, Vector3.LEFT, 911, _sand_floor(p, s))
				neon_gear(kit, m, p + Vector3(s.x * 0.5 + 0.02, 2.25, 0.15))
			"side_wall":
				scrap_wall(kit, m, p, s, Vector3.RIGHT, Vector3.FORWARD, 912, _sand_floor(p, s))
				_dress_side_wall_bits(kit, m, p, s)
	_dress_awning(kit, m)
	_dress_yard(kit, m)
	_dress_bay(kit, m)
	var parts := Node3D.new()
	parts.name = "StallLook"
	add_child(parts)
	kit.flush_merged(parts, xf)
	# A real lamp over the counter, like Dorrin's and Skrugs's.
	HangingLamp.build(self, xf, Vector3(0.2, 2.3, 0.0), mats, look, "CounterLamp", 3.2, 6.0, 0.7, 0.45)


## The stall's materials by name, from content/look/speeder_stall.json (Dorrin's
## yard colours: MechanicYard dresses with the same set). Every metal is the
## favela's painted metal, the wood the market's planks, the awning its canvas;
## "scrap" is a list of sheet colours, the glows are shared and on the lamp clock.
static func look_mats(mats: LookMaterials, look: LookEnvironment) -> Dictionary:
	var col: Dictionary = ItemKit._read_json(LOOK_PATH)
	var c := func(k: String) -> Color: return Color(str(col.get(k, "#808080")))
	var m := {
		"steel": mats.painted(c.call("steel"), 0.5, 0.55),
		"rust": mats.painted(c.call("rust"), 0.8, 0.3),
		"dark": mats.painted(c.call("dark"), 0.7, 0.4),
		"hazard": mats.painted(c.call("hazard"), 0.6, 0.3),
		"fuel": mats.painted(c.call("fuel"), 0.6, 0.3),
		"coolant": mats.painted(c.call("coolant"), 0.6, 0.3),
		"board": mats.wood(c.call("board")),
		"crate": mats.wood(c.call("crate")),
		"canvas": mats.canvas(c.call("canvas")),
		"stripe": mats.canvas(c.call("stripe")),
		"bulb": _glow(mats, look, "bulb", c.call("bulb")),
		"neon": _glow(mats, look, "neon", c.call("neon")),
		"screen": _glow(mats, look, "screen", c.call("screen")),
	}
	var scrap: Array = []
	for sc in col.get("scrap", ["#55606a"]):
		scrap.append(mats.painted(Color(str(sc)), 0.75, 0.35))
	m["scrap"] = scrap
	return m


## A glow shared by every stall (one a LookMaterials and kind), on the lamp clock.
static func _glow(mats: LookMaterials, look: LookEnvironment, kind: String, color: Color) -> StandardMaterial3D:
	var key := "%d/%s" % [mats.get_instance_id(), kind]
	if not _bulbs.has(key):
		_bulbs[key] = mats.glow(color)
		HangingLamp.track_glow(_bulbs[key], look)
	return _bulbs[key]


## The awning's underside height at `x` (it slopes down toward the customer).
static func _awning_y(x: float) -> float:
	return AWNING_Y - (x - (AWNING_X0 + AWNING_X1) * 0.5) * tan(AWNING_TILT) - 0.03


## The steel counter down to the sand, angle-iron corners, patch plates and a
## chevron kick band on the customer's side (+x), and on its rusty top a toolbox,
## a vice, a tray of nuts, a thruster nozzle he is working on and a diagnostic
## screen. `cb`: where its body starts (the sand under it). Dorrin's counter too.
static func dress_counter(kit: TownBuildings, m: Dictionary, p: Vector3, s: Vector3, cb: float) -> void:
	var h := s.y - cb
	var mid := p + Vector3(0, (s.y + cb) * 0.5, 0)
	var top := s.y + 0.06
	var fx := p.x + s.x * 0.5               # the customer's face
	kit.part(kit.box(s.x, h, s.z), m.steel, mid)
	kit.part(kit.box(s.x + 0.1, 0.06, s.z + 0.1), m.rust, p + Vector3(0, s.y + 0.03, 0))
	for dx in [-0.5, 0.5]:
		for dz in [-0.5, 0.5]:
			kit.part(kit.box(0.07, h, 0.07), m.dark, Vector3(p.x + s.x * dx, mid.y, p.z + s.z * dz))
	kit.part(kit.box(0.02, 0.5, 1.1), m.scrap[1 % m.scrap.size()], Vector3(fx + 0.01, 0.62, p.z - 0.66))
	kit.part(kit.box(0.02, 0.42, 0.9), m.scrap[2 % m.scrap.size()], Vector3(fx + 0.012, 0.58, p.z + 0.6), Basis(Vector3.RIGHT, 0.03))
	kit.part(kit.box(0.02, 0.22, s.z - 0.1), m.hazard, Vector3(fx + 0.01, 0.16, p.z))
	for k in 7:
		kit.part(kit.box(0.025, 0.05, 0.3), m.dark, Vector3(fx + 0.015, 0.16, p.z - 1.1 + k * 0.367), Basis(Vector3.RIGHT, 0.7))
	# The toolbox (was a plain yellow box): red, a dark lid line, a steel handle.
	var tb := p + Vector3(0, top, -0.85)
	kit.part(kit.box(0.42, 0.22, 0.3), m.fuel, tb + Vector3(0, 0.11, 0))
	kit.part(kit.box(0.44, 0.03, 0.32), m.dark, tb + Vector3(0, 0.2, 0))
	for dx in [-0.12, 0.12]:
		kit.part(kit.box(0.025, 0.07, 0.025), m.steel, tb + Vector3(dx, 0.25, 0))
	kit.part(kit.box(0.27, 0.025, 0.035), m.steel, tb + Vector3(0, 0.29, 0))
	# A tray of nuts and bolts.
	kit.part(kit.box(0.5, 0.08, 0.3), m.dark, p + Vector3(0, top + 0.04, 0.7))
	var nut := kit.cyl(0.03, 0.03, 0.025, 6)
	for k in 5:
		kit.part(nut, m.steel, p + Vector3(-0.16 + k * 0.08, top + 0.09, 0.66 + (k % 2) * 0.08))
	# The vice on his side of the counter.
	var v := p + Vector3(-0.3, top, 0.22)
	kit.part(kit.box(0.2, 0.08, 0.16), m.dark, v + Vector3(0, 0.04, 0))
	for dz in [-0.05, 0.05]:
		kit.part(kit.box(0.16, 0.12, 0.04), m.steel, v + Vector3(0, 0.14, dz))
	kit.part(kit.cyl(0.014, 0.014, 0.34, 6), m.steel, v + Vector3(0, 0.12, 0), TownBuildings.AXIS_Z)
	kit.part(kit.cyl(0.012, 0.012, 0.2, 6), m.steel, v + Vector3(0, 0.12, 0.17), TownBuildings.AXIS_X)
	# A thruster nozzle lying on its side: the cone, a dark lip and a hazard band.
	var nz := p + Vector3(0.18, top + 0.2, 0.05)
	kit.part(kit.cyl(0.13, 0.2, 0.38, 12), m.steel, nz, TownBuildings.AXIS_Z)
	kit.part(kit.cyl(0.205, 0.205, 0.04, 12), m.dark, nz + Vector3(0, 0, -0.19), TownBuildings.AXIS_Z)
	kit.part(kit.cyl(0.165, 0.165, 0.05, 12), m.hazard, nz + Vector3(0, 0, 0.06), TownBuildings.AXIS_Z)
	# A diagnostic screen on a stand, turned to the customer.
	var sc := p + Vector3(-0.28, top, -0.3)
	kit.part(kit.box(0.14, 0.03, 0.18), m.dark, sc + Vector3(0, 0.015, 0))
	kit.part(kit.box(0.03, 0.14, 0.03), m.dark, sc + Vector3(0, 0.09, 0))
	var tilt := Basis(Vector3.BACK, 0.25)
	kit.part(kit.box(0.06, 0.24, 0.36), m.dark, sc + Vector3(0, 0.27, 0), tilt)
	kit.part(kit.box(0.01, 0.19, 0.3), m.screen, sc + Vector3(0, 0.27, 0) + tilt * Vector3(0.031, 0, 0), tilt)


## The parts rack: a rusty drawer cabinet (drawer lines and handles) with a dark
## worktop and a power cell on it, the pegboard behind in a dark frame with his
## tools, and a shelf along its top with cans and a coil of cable.
func _dress_rack(kit: TownBuildings, m: Dictionary, p: Vector3, s: Vector3) -> void:
	var rb := _sand_floor(p, s)
	var fx := p.x + s.x * 0.5               # the cabinet's front, toward him
	kit.part(kit.box(s.x, 0.9 - rb, s.z), m.rust, p + Vector3(0, (0.9 + rb) * 0.5, 0))
	kit.part(kit.box(s.x + 0.06, 0.04, s.z + 0.06), m.dark, p + Vector3(0, 0.92, 0))
	for y in [0.33, 0.62]:
		kit.part(kit.box(0.02, 0.025, s.z - 0.08), m.dark, Vector3(fx + 0.01, y, p.z))
	for dz in [-0.37, 0.37]:
		kit.part(kit.box(0.02, 0.82, 0.025), m.dark, Vector3(fx + 0.01, 0.48, p.z + dz))
	var handle := kit.box(0.03, 0.025, 0.14)
	for y in [0.2, 0.48, 0.77]:
		for dz in [-0.73, 0.0, 0.73]:
			kit.part(handle, m.steel, Vector3(fx + 0.025, y, p.z + dz))
	var cell := p + Vector3(0.05, 1.03, 0.55)
	kit.part(kit.cyl(0.09, 0.09, 0.36, 10), m.coolant, cell, TownBuildings.AXIS_Z)
	for dz in [-0.19, 0.19]:
		kit.part(kit.cyl(0.07, 0.07, 0.03, 10), m.hazard, cell + Vector3(0, 0, dz), TownBuildings.AXIS_Z)
	# The pegboard and its frame.
	var bx := p.x - s.x * 0.5 + 0.04
	kit.part(kit.box(0.08, s.y - 0.9, s.z), m.board, Vector3(bx, 0.9 + (s.y - 0.9) * 0.5, p.z))
	kit.part(kit.box(0.1, 0.05, s.z + 0.06), m.dark, Vector3(bx, s.y, p.z))
	for dz in [-0.5, 0.5]:
		kit.part(kit.box(0.1, s.y - 0.9, 0.05), m.dark, Vector3(bx, 0.9 + (s.y - 0.9) * 0.5, p.z + s.z * dz))
	var rng := RandomNumberGenerator.new()
	rng.seed = 611
	for k in 7:
		var t: BoxMesh = kit.box(0.04, rng.randf_range(0.3, 0.55), 0.06)
		kit.part(t, m.steel if k % 3 else m.hazard, p + Vector3(-s.x * 0.5 + 0.12, 1.35 + rng.randf_range(-0.15, 0.15),
			-s.z * 0.5 + 0.25 + k * (s.z - 0.5) / 6.0), Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4)))
	# The shelf along the pegboard's top, with cans and a coil of cable.
	var sy := s.y - 0.12
	kit.part(kit.box(0.26, 0.03, s.z - 0.1), m.steel, Vector3(bx + 0.15, sy, p.z))
	for dz in [-0.8, 0.8]:
		kit.part(kit.box(0.2, 0.03, 0.03), m.dark, Vector3(bx + 0.12, sy - 0.06, p.z + dz), Basis(Vector3.BACK, -0.6))
	var can := kit.cyl(0.055, 0.055, 0.15, 8)
	var cans: Array = [m.fuel, m.coolant, m.hazard, m.coolant]
	for k in cans.size():
		kit.part(can, cans[k], Vector3(bx + 0.15, sy + 0.09, p.z - 0.9 + k * 0.17))
	kit.part(_torus(0.06, 0.12), m.dark, Vector3(bx + 0.15, sy + 0.04, p.z + 0.55))
	kit.part(_torus(0.06, 0.12), m.dark, Vector3(bx + 0.15, sy + 0.08, p.z + 0.58), Basis(Vector3.RIGHT, 0.15))


## A wall of scrap sheets (the favela's painted metal, a few colours) over the
## building box `p`, `s`, laid along `along` (BACK: across z, RIGHT: across x),
## its outside toward `out`: overlapping sheets, each its own height (up to
## `ragged` short of the top) and a little out of true, battens across the outside
## every 1.4 m, patches riveted on, and one inside up high. `lo`: where the sheets
## start (the sand under them). Dorrin's garage walls are the same, ragged 0.
static func scrap_wall(kit: TownBuildings, m: Dictionary, p: Vector3, s: Vector3, along: Vector3, out: Vector3,
		seed_value: int, lo: float, ragged: float = 0.35) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var scrap: Array = m.scrap
	var x_wall := along == Vector3.BACK
	var length := s.z if x_wall else s.x
	var thick := s.x if x_wall else s.z
	var sheet := thick * 0.5 if thick < 0.2 else thick - 0.04
	var n := 3 if length < 3.0 else maxi(4, ceili(length / 1.3))
	var w := length / n
	for k in n:
		var hgt := s.y - rng.randf_range(0.0, ragged)
		var at := p + along * (-length * 0.5 + w * (k + 0.5)) + out * (0.012 if k % 2 else -0.012)
		at.y = (hgt + lo) * 0.5
		var size := Vector3(sheet, hgt - lo, w + 0.08) if x_wall else Vector3(w + 0.08, hgt - lo, sheet)
		var lean := Basis(along, rng.randf_range(-1.0, 1.0) * (0.004 + ragged * 0.045))
		kit.part(kit.box(size.x, size.y, size.z), scrap[(k + seed_value) % scrap.size()], at, lean)
	var face := thick * 0.5
	var y := 0.55
	while y < s.y - 0.3:
		var bat := Vector3(0.05, 0.07, length) if x_wall else Vector3(length, 0.07, 0.05)
		kit.part(kit.box(bat.x, bat.y, bat.z), m.dark, p + out * (face + 0.03) + Vector3(0, y, 0))
		y += 1.4
	for k in maxi(2, n / 2):
		var pw := rng.randf_range(0.4, 0.65)
		var ph := rng.randf_range(0.35, 0.55)
		var off := along * rng.randf_range(-length * 0.4, length * 0.4)
		var py := rng.randf_range(0.8, maxf(1.6, s.y - 1.0))
		var ps := Vector3(0.02, ph, pw) if x_wall else Vector3(pw, ph, 0.02)
		kit.part(kit.box(ps.x, ps.y, ps.z), scrap[(k + 2 + seed_value) % scrap.size()],
			p + off + out * (face + 0.02) + Vector3(0, py, 0), Basis(out, rng.randf_range(-0.12, 0.12)))
	var ins := Vector3(0.02, 0.4, 0.7) if x_wall else Vector3(0.7, 0.4, 0.02)
	kit.part(kit.box(ins.x, ins.y, ins.z), scrap[(seed_value + 1) % scrap.size()],
		p - out * (face + 0.015) + along * (length * 0.28) + Vector3(0, minf(2.05, s.y - 0.5), 0), Basis(out, 0.08))


## The neon over the rack on the back wall, facing him and the customer: a gear
## (a ring and eight teeth) with a wrench across it, on the favela's neon, facing
## +x. Dorrin's garage has one too.
static func neon_gear(kit: TownBuildings, m: Dictionary, at: Vector3) -> void:
	var face := Basis(Vector3.BACK, PI * 0.5)        # a torus's axis is y: turned to x
	kit.part(kit.box(0.02, 0.62, 0.62), m.dark, at + Vector3(-0.01, 0, 0))
	kit.part(_torus(0.15, 0.19), m.neon, at + Vector3(0.01, 0, 0), face)
	var tooth := kit.box(0.025, 0.07, 0.05)
	for k in 8:
		var a := TAU * k / 8.0
		kit.part(tooth, m.neon, at + Vector3(0.01, sin(a) * 0.22, cos(a) * 0.22), Basis(Vector3.RIGHT, -a))
	var tilt := Basis(Vector3.RIGHT, 0.75)
	kit.part(kit.box(0.025, 0.04, 0.56), m.neon, at + Vector3(0.02, 0, 0), tilt)
	for e in [-1.0, 1.0]:
		var end: Vector3 = at + Vector3(0.02, 0, 0) + tilt * Vector3(0, 0, 0.3 * e)
		for side in [-1.0, 1.0]:
			kit.part(kit.box(0.025, 0.035, 0.09), m.neon, end + tilt * Vector3(0, 0.04 * side, 0.04 * e), tilt * Basis(Vector3.RIGHT, 0.5 * side * e))


## On the side wall, inside: a fuse box with a cable up to the awning and a coil
## of hose hung on a hook.
func _dress_side_wall_bits(kit: TownBuildings, m: Dictionary, p: Vector3, s: Vector3) -> void:
	var z := p.z + s.z * 0.5 + 0.06
	var fb := Vector3(p.x - 0.55, 1.45, z)
	kit.part(kit.box(0.32, 0.42, 0.1), m.dark, fb)
	kit.part(kit.box(0.3, 0.06, 0.012), m.hazard, fb + Vector3(0, 0.13, 0.055))
	kit.part(kit.box(0.04, 0.04, 0.015), m.screen, fb + Vector3(0.09, -0.08, 0.055))
	var top := _awning_y(fb.x)
	kit.part(kit.cyl(0.012, 0.012, top - fb.y - 0.21, 6), m.dark, Vector3(fb.x + 0.1, (top + fb.y + 0.21) * 0.5, z - 0.02))
	var hose := Vector3(p.x + 0.45, 1.35, z - 0.01)
	kit.part(kit.box(0.04, 0.04, 0.08), m.steel, hose + Vector3(0, 0.2, -0.02))
	kit.part(_torus(0.14, 0.2), m.dark, hose, Basis(Vector3.RIGHT, PI * 0.5))
	kit.part(_torus(0.13, 0.19), m.coolant, hose + Vector3(0.02, -0.02, 0.03), Basis(Vector3.RIGHT, PI * 0.5))


## The awning: four poles cut to its slope (the back two used to stop short of it,
## the front two poked through), rails along its edges with knee braces, five
## canvas stripes, a valance along the front with the bulbs under it, and two
## scrap-sheet patches on the roof the favela way.
func _dress_awning(kit: TownBuildings, m: Dictionary) -> void:
	var x0 := AWNING_X0
	var x1 := AWNING_X1
	var tilt := Basis(Vector3.BACK, -AWNING_TILT)
	var xc := (x0 + x1) * 0.5
	for x in [x0 + 0.1, x1 - 0.1]:
		var top := _awning_y(x)
		for z in [-1.8, 1.8]:
			var foot := _sand_y(x, z) - 0.3     # planted in the sand, whatever the slope
			kit.part(kit.cyl(0.06, 0.06, top - foot, 8), m.steel, Vector3(x, (top + foot) * 0.5, z))
			kit.part(kit.cyl(0.09, 0.09, 0.06, 8), m.dark, Vector3(x, _sand_y(x, z) + 0.02, z))
			var sz: float = signf(z)
			kit.part(kit.cyl(0.025, 0.025, 0.6, 6), m.steel, Vector3(x, top - 0.08 - 0.212, z - sz * 0.212), Basis(Vector3.RIGHT, -sz * PI * 0.25))
		kit.part(kit.cyl(0.035, 0.035, 3.7, 8), m.steel, Vector3(x, top - 0.06, 0), TownBuildings.AXIS_Z)
	for z in [-1.8, 1.8]:
		kit.part(kit.cyl(0.035, 0.035, (x1 - x0 - 0.2) / cos(AWNING_TILT), 8), m.steel, Vector3(xc, AWNING_Y - 0.09, z), tilt * TownBuildings.AXIS_X)
	for k in 5:
		kit.part(kit.box(x1 - x0 + 0.2, 0.05, 0.8), m.canvas if k % 2 == 0 else m.stripe,
			Vector3(xc, AWNING_Y, -1.6 + k * 0.8), tilt)
	# The valance: a flap of each stripe hanging off the front edge.
	var fx := xc + (x1 - x0 + 0.2) * 0.5 * cos(AWNING_TILT)
	var fy := AWNING_Y - (x1 - x0 + 0.2) * 0.5 * sin(AWNING_TILT)
	for k in 5:
		kit.part(kit.box(0.02, 0.26, 0.8), m.canvas if k % 2 == 0 else m.stripe, Vector3(fx, fy - 0.13, -1.6 + k * 0.8))
	# Bulbs along the front under the valance: one glow for every stall, on the lamp clock.
	var bulb: SphereMesh = kit.ball(0.07, 0.14, false, 8)
	var wire := kit.cyl(0.006, 0.006, 0.1, 4)
	for k in 8:
		var z := -1.8 + k * (3.6 / 7.0)
		var y := fy - 0.36 - 0.08 * sin(float(k) / 7.0 * PI)
		kit.part(bulb, m.bulb, Vector3(fx - 0.02, y, z))
		kit.part(wire, m.dark, Vector3(fx - 0.02, y + 0.11, z))
	# Scrap sheet laid over the canvas at the back, over the rack.
	var patches := [[-2.0, -0.85, 1.5, 1.4, 0], [-1.15, 1.05, 0.95, 0.8, 3]]
	for pa in patches:
		var px: float = pa[0]
		kit.part(kit.box(pa[2], 0.03, pa[3]), m.scrap[int(pa[4]) % m.scrap.size()],
			Vector3(px, AWNING_Y - (px - xc) * tan(AWNING_TILT) + 0.045, pa[1]), tilt * Basis(Vector3.UP, 0.06))


## Crates by the rack (banded, the top one on the two below), a scrap sheet
## leaning on them, the canisters by the pad (banded, lidded), and a generator
## with a cable run to the counter: each on the sand under it.
func _dress_yard(kit: TownBuildings, m: Dictionary) -> void:
	var c0 := _sand_y(-2.3, 2.3) - 0.05
	var c1 := _sand_y(-1.5, 2.5) - 0.05
	var band := kit.box(0.83, 0.07, 0.83)
	for cr in [[Vector3(-2.3, 0.4, 2.3), c0], [Vector3(-1.5, 0.4, 2.5), c1], [Vector3(-1.9, 1.2, 2.4), maxf(c0, c1)]]:
		var at: Vector3 = cr[0] + Vector3(0, float(cr[1]), 0)
		var turn := Basis(Vector3.UP, (cr[0] as Vector3).x * 0.7)
		kit.part(kit.box(0.8, 0.8, 0.8), m.crate, at, turn)
		for dy in [-0.28, 0.28]:
			kit.part(band, m.dark, at + Vector3(0, dy, 0), turn)
	var ls := Vector3(-2.95, _sand_y(-2.95, 3.0), 3.05)
	kit.part(kit.box(0.04, 1.3, 1.1), m.scrap[2 % m.scrap.size()], ls + Vector3(0.18, 0.62, 0), Basis(Vector3.BACK, -0.28))
	var bay: Vector3 = points.get("bay", Vector3.ZERO)
	var ring := kit.cyl(0.29, 0.29, 0.05, 10)
	var lid := kit.cyl(0.07, 0.07, 0.04, 8)
	for k in 4:
		var at := bay + Vector3(-4.4 + (k % 2) * 0.6, 0.4, -1.4 + k * 0.7)
		at.y += _sand_y(at.x, at.z) - 0.06
		kit.part(kit.cyl(0.28, 0.28, 0.8, 10), m.fuel if k % 2 == 0 else m.coolant, at)
		for dy in [-0.22, 0.22]:
			kit.part(ring, m.dark, at + Vector3(0, dy, 0))
		kit.part(lid, m.steel, at + Vector3(0.12, 0.42, 0.05))
	# The generator: a yellow body, grille, a fuel tank on top and an exhaust stack.
	var g := Vector3(-2.2, 0, 4.3)
	var gy := _sand_floor(g, Vector3(0.9, 0, 0.6)) + 0.05
	var gt := gy + 0.6
	kit.part(kit.box(0.9, gt - gy + 0.05, 0.6), m.hazard, Vector3(g.x, (gt + gy - 0.05) * 0.5, g.z))
	kit.part(kit.box(0.94, 0.04, 0.64), m.dark, Vector3(g.x, gt, g.z))
	for k in 6:
		kit.part(kit.box(0.02, 0.4, 0.03), m.dark, Vector3(g.x + 0.46, gy + 0.3, g.z - 0.2 + k * 0.08))
	kit.part(kit.cyl(0.13, 0.13, 0.55, 10), m.fuel, Vector3(g.x - 0.05, gt + 0.15, g.z), TownBuildings.AXIS_X)
	kit.part(kit.cyl(0.03, 0.03, 0.45, 6), m.steel, Vector3(g.x - 0.38, gt + 0.22, g.z + 0.2))
	kit.part(kit.cyl(0.045, 0.045, 0.06, 6), m.dark, Vector3(g.x - 0.38, gt + 0.46, g.z + 0.2))
	# The cable from it to the counter, lying on the sand.
	var path := [Vector3(g.x + 0.46, 0, g.z - 0.2), Vector3(-1.0, 0, 3.15), Vector3(-0.6, 0, 1.9), Vector3(-0.35, 0, 1.25)]
	for k in path.size() - 1:
		var a: Vector3 = path[k]
		var b: Vector3 = path[k + 1]
		a.y = _sand_y(a.x, a.z) + 0.02
		b.y = _sand_y(b.x, b.z) + 0.02
		var d := b - a
		kit.part(kit.box(0.035, 0.035, d.length() + 0.03), m.dark, (a + b) * 0.5, Basis.looking_at(d.normalized(), Vector3.UP))


## The lift pad (a steel plate with hazard edges and two skid rails, on the sand's
## plane), bollards at its corners, a gantry over it with a hook on a chain, the
## lift's control post, and a spare engine on a stand past its far edge.
func _dress_bay(kit: TownBuildings, m: Dictionary) -> void:
	var bay: Vector3 = points.get("bay", Vector3.ZERO)
	# The plate is deep enough that a dune's curve under it never shows an edge in the air.
	var pad := _sand_plane(bay, 3.5, 2.0)
	var pb: Basis = pad.basis
	var depth := 0.6
	kit.part(kit.box(7.0, depth, 4.0), m.steel, pad.origin + pb.y * (0.08 - depth * 0.5), pb)
	for dz in [-2.05, 2.05]:
		kit.part(kit.box(7.0, depth, 0.12), m.hazard, pad.origin + pb * Vector3(0, 0.1 - depth * 0.5, dz), pb)
	for dz in [-0.9, 0.9]:
		kit.part(kit.box(6.0, 0.05, 0.22), m.dark, pad.origin + pb * Vector3(0, 0.105, dz), pb)
	var post := kit.cyl(0.09, 0.09, 0.75, 8)
	var post_band := kit.cyl(0.095, 0.095, 0.12, 8)
	for dx in [-3.75, 3.75]:
		for dz in [-2.3, 2.3]:
			var at := Vector3(bay.x + dx, 0, bay.z + dz)
			at.y = _sand_y(at.x, at.z) + 0.3
			kit.part(post, m.hazard, at)
			kit.part(post_band, m.dark, at + Vector3(0, 0.2, 0))
	# The gantry straddles the pad across its middle, high enough for any speeder.
	var za := bay.z - 2.45
	var zb := bay.z + 2.45
	var ga := _sand_y(bay.x, za)
	var gb := _sand_y(bay.x, zb)
	var gtop := maxf(ga, gb) + 3.8
	for e in [[za, ga], [zb, gb]]:
		var z: float = e[0]
		var foot: float = e[1] - 0.2
		kit.part(kit.box(0.18, gtop - foot, 0.18), m.steel, Vector3(bay.x, (gtop + foot) * 0.5, z))
		kit.part(kit.box(0.6, 0.05, 0.6), m.dark, Vector3(bay.x, float(e[1]) + 0.02, z))
		var inward: float = signf(bay.z - z)
		kit.part(kit.box(0.08, 0.08, 0.7), m.steel, Vector3(bay.x, gtop - 0.3, z + inward * 0.3), Basis(Vector3.RIGHT, -inward * 0.8))
	kit.part(kit.box(0.24, 0.26, zb - za + 0.4), m.hazard, Vector3(bay.x, gtop + 0.13, bay.z))
	# The hoist on its trolley: a red motor, twin cables and a chunky yellow hook
	# block with a steel hook, hung high enough to clear a speeder on the pad.
	var hz := bay.z + 0.4
	kit.part(kit.box(0.36, 0.1, 0.4), m.dark, Vector3(bay.x, gtop - 0.05, hz))
	kit.part(kit.box(0.3, 0.3, 0.42), m.fuel, Vector3(bay.x, gtop - 0.25, hz))
	kit.part(kit.cyl(0.1, 0.1, 0.46, 10), m.dark, Vector3(bay.x, gtop - 0.25, hz), TownBuildings.AXIS_Z)
	var block_y := gtop - 0.95
	for dz in [-0.06, 0.06]:
		kit.part(kit.box(0.015, gtop - 0.4 - block_y, 0.015), m.dark, Vector3(bay.x, (gtop - 0.4 + block_y) * 0.5, hz + dz))
	kit.part(kit.box(0.14, 0.26, 0.22), m.hazard, Vector3(bay.x, block_y - 0.1, hz))
	kit.part(kit.cyl(0.06, 0.06, 0.16, 8), m.dark, Vector3(bay.x, block_y, hz), TownBuildings.AXIS_X)
	kit.part(kit.box(0.05, 0.16, 0.05), m.steel, Vector3(bay.x, block_y - 0.3, hz))
	kit.part(kit.box(0.05, 0.05, 0.16), m.steel, Vector3(bay.x, block_y - 0.36, hz + 0.055))
	kit.part(kit.box(0.05, 0.1, 0.05), m.steel, Vector3(bay.x, block_y - 0.31, hz + 0.115))
	# The lift's control post by the pad's near corner.
	var cp := Vector3(bay.x - 2.7, 0, bay.z - 2.75)
	var cy := _sand_y(cp.x, cp.z) - 0.1
	kit.part(kit.box(0.22, 1.1 - cy, 0.22), m.dark, Vector3(cp.x, (1.1 + cy) * 0.5, cp.z))
	var desk := Basis(Vector3.BACK, 0.35)
	kit.part(kit.box(0.34, 0.06, 0.3), m.hazard, cp + Vector3(0, 1.12, 0), desk)
	for k in 2:
		kit.part(kit.box(0.06, 0.03, 0.06), m.screen, cp + Vector3(0, 1.15, -0.07 + k * 0.14) + desk * Vector3(0.04, 0, 0), desk)
	kit.part(kit.cyl(0.04, 0.04, 0.04, 8), m.fuel, cp + Vector3(-0.07, 1.17, 0), desk)
	# The spare engine on its stand past the pad's far edge.
	var en := Vector3(bay.x + 4.7, 0, bay.z - 0.9)
	var ey := _sand_y(en.x, en.z)
	var ec := Vector3(en.x, ey + 0.95, en.z)
	for dz in [-0.4, 0.4]:
		for side in [-1.0, 1.0]:
			kit.part(kit.box(0.08, 0.95, 0.08), m.dark, Vector3(en.x + side * 0.17, ey + 0.42, en.z + dz), Basis(Vector3.BACK, side * 0.38))
		kit.part(kit.box(0.7, 0.06, 0.12), m.steel, Vector3(en.x, ey + 0.58, en.z + dz))
	kit.part(kit.cyl(0.38, 0.38, 1.2, 14), m.steel, ec, TownBuildings.AXIS_Z)
	kit.part(kit.cyl(0.42, 0.42, 0.1, 14), m.dark, ec + Vector3(0, 0, -0.62), TownBuildings.AXIS_Z)
	kit.part(kit.cyl(0.3, 0.3, 0.02, 14), m.dark, ec + Vector3(0, 0, -0.68), TownBuildings.AXIS_Z)
	kit.part(kit.cyl(0.395, 0.395, 0.08, 14), m.hazard, ec + Vector3(0, 0, -0.15), TownBuildings.AXIS_Z)
	kit.part(kit.cyl(0.36, 0.3, 0.35, 14), m.steel, ec + Vector3(0, 0, 0.77), TownBuildings.AXIS_Z)
	kit.part(kit.cyl(0.33, 0.33, 0.02, 14), m.dark, ec + Vector3(0, 0, 0.95), TownBuildings.AXIS_Z)
	for dx in [-0.13, 0.13]:
		kit.part(kit.cyl(0.035, 0.035, 0.95, 6), m.rust, ec + Vector3(dx, 0.4, 0.05), TownBuildings.AXIS_Z)


## A torus (a coil, a ring), shared by every stall.
static func _torus(inner: float, outer: float) -> TorusMesh:
	var k := "%s_%s" % [inner, outer]
	if not _tori.has(k):
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 16
		t.ring_segments = 6
		_tori[k] = t
	return _tori[k]


# ------------------------------------------------------------------ the sand

## The sand's height under (x, z) of the stall's frame, in that frame: the frame
## is flat at its origin, a dune is not, so what stands away from the counter
## (the pad 7 m off, the canisters, the poles) is dropped onto it.
func _sand_y(x: float, z: float) -> float:
	if not _to_ground.is_valid():
		return 0.0
	return (xf.affine_inverse() * (_to_ground.call(xf * Vector3(x, 0.0, z)) as Vector3)).y


## The lowest sand under a box's footprint (its centre `p`, size `s`), a little
## below it, never above the frame: where a box's look starts so it never floats.
func _sand_floor(p: Vector3, s: Vector3) -> float:
	var lo := 0.0
	for dx in [-0.5, 0.5]:
		for dz in [-0.5, 0.5]:
			lo = minf(lo, _sand_y(p.x + s.x * dx, p.z + s.z * dz))
	return lo - 0.05


## The plane through the sand under a rectangle (centre `c`, half sizes `hx`, `hz`)
## in the stall's frame: its origin on the sand at the centre (the corners'
## average), its basis tilted to the slope along x and along z.
func _sand_plane(c: Vector3, hx: float, hz: float) -> Transform3D:
	var h00 := _sand_y(c.x - hx, c.z - hz)
	var h10 := _sand_y(c.x + hx, c.z - hz)
	var h01 := _sand_y(c.x - hx, c.z + hz)
	var h11 := _sand_y(c.x + hx, c.z + hz)
	var sx := ((h10 + h11) - (h00 + h01)) / (4.0 * hx)
	var sz := ((h01 + h11) - (h00 + h10)) / (4.0 * hz)
	var n := Vector3(-sx, 1.0, -sz).normalized()
	var mid := (h00 + h10 + h01 + h11) * 0.25
	return Transform3D(Basis(Quaternion(Vector3.UP, n)), Vector3(c.x, mid, c.z))
