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

static var _bulbs := {}               ## LookMaterials instance id -> the stalls' shared bulb glow

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

## The counter and rack (from their boxes), a striped awning on four poles with a
## string of bulbs and a hanging lamp, crates and canisters, and the lift pad.
func _dress(loc: Dictionary) -> void:
	var mats: LookMaterials = demo._flat_mats()
	var look: LookEnvironment = demo.get("look") as LookEnvironment
	var col: Dictionary = ItemKit._read_json(LOOK_PATH)
	var c := func(k: String) -> Color: return Color(str(col.get(k, "#808080")))
	var steel := mats.flat(c.call("steel"), 0.45, 0.6)
	var rust := mats.flat(c.call("rust"), 0.85)
	var dark := mats.flat(c.call("dark"), 0.9)
	var hazard := mats.flat(c.call("hazard"), 0.7)
	var board := mats.flat(c.call("board"), 0.9)
	var crate := mats.flat(c.call("crate"), 0.9)
	var canvas := mats.cloth(c.call("canvas"))
	var stripe := mats.cloth(c.call("stripe"))
	var fuel := mats.flat(c.call("fuel"), 0.6, 0.2)
	var coolant := mats.flat(c.call("coolant"), 0.6, 0.2)
	var kit := TownBuildings.new(mats, look)
	kit._xf = xf
	for b in loc.get("buildings", []):
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var p := WorldGround._v3(b.get("position", [0, 0, 0]))
		match str(b.get("id", "")):
			"counter":
				# Down to the sand under its lowest corner (the collider stays on the frame).
				var cb := _sand_floor(p, s)
				kit.part(kit.box(s.x, s.y - cb, s.z), steel, p + Vector3(0, (s.y + cb) * 0.5, 0))
				kit.part(kit.box(s.x + 0.1, 0.06, s.z + 0.1), rust, p + Vector3(0, s.y + 0.03, 0))
				kit.part(kit.box(0.4, 0.3, 0.35), hazard, p + Vector3(0, s.y + 0.21, -0.8))
				kit.part(kit.box(0.5, 0.08, 0.3), dark, p + Vector3(0, s.y + 0.1, 0.7))
			"rack":
				var rb := _sand_floor(p, s)
				kit.part(kit.box(s.x, 0.9 - rb, s.z), rust, p + Vector3(0, (0.9 + rb) * 0.5, 0))
				kit.part(kit.box(0.08, s.y - 0.9, s.z), board, p + Vector3(-s.x * 0.5 + 0.04, 0.9 + (s.y - 0.9) * 0.5, 0))
				var rng := RandomNumberGenerator.new()
				rng.seed = 611
				for k in 7:
					var t: BoxMesh = kit.box(0.04, rng.randf_range(0.3, 0.55), 0.06)
					kit.part(t, steel if k % 3 else hazard, p + Vector3(-s.x * 0.5 + 0.12, 1.35 + rng.randf_range(-0.15, 0.15),
						-s.z * 0.5 + 0.25 + k * (s.z - 0.5) / 6.0), Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4)))
	# The awning: four poles and a striped canvas over the counter and the rack,
	# sloping down toward the customer.
	var x0 := -3.0
	var x1 := 2.0
	for x in [x0 + 0.1, x1 - 0.1]:
		for z in [-1.8, 1.8]:
			var foot := _sand_y(x, z) - 0.3     # planted in the sand, whatever the slope
			kit.part(kit.cyl(0.06, 0.06, 3.0 - foot, 8), steel, Vector3(x, (3.0 + foot) * 0.5, z))
	for k in 5:
		kit.part(kit.box(x1 - x0 + 0.2, 0.05, 0.8), canvas if k % 2 == 0 else stripe,
			Vector3((x0 + x1) * 0.5, 3.0, -1.6 + k * 0.8), Basis(Vector3.BACK, -0.1))
	# Bulbs along the awning's front edge: one glow for every stall, on the lamp clock.
	var key := mats.get_instance_id()
	if not _bulbs.has(key):
		_bulbs[key] = mats.glow(c.call("bulb"))
		HangingLamp.track_glow(_bulbs[key], look)
	var bulb: SphereMesh = kit.ball(0.07, 0.14, false, 8)
	for k in 8:
		var z := -1.8 + k * (3.6 / 7.0)
		kit.part(bulb, _bulbs[key], Vector3(x1 + 0.05, 2.62 - 0.1 * sin(float(k) / 7.0 * PI), z))
	# Crates by the rack (the top one on the two below), canisters by the pad: each
	# on the sand under it.
	var c0 := _sand_y(-2.3, 2.3) - 0.05
	var c1 := _sand_y(-1.5, 2.5) - 0.05
	for cr in [[Vector3(-2.3, 0.4, 2.3), c0], [Vector3(-1.5, 0.4, 2.5), c1], [Vector3(-1.9, 1.2, 2.4), maxf(c0, c1)]]:
		var at: Vector3 = cr[0]
		kit.part(kit.box(0.8, 0.8, 0.8), crate, at + Vector3(0, float(cr[1]), 0), Basis(Vector3.UP, at.x * 0.7))
	var bay: Vector3 = points.get("bay", Vector3.ZERO)
	for k in 4:
		var at := bay + Vector3(-4.4 + (k % 2) * 0.6, 0.4, -1.4 + k * 0.7)
		kit.part(kit.cyl(0.28, 0.28, 0.8, 10), fuel if k % 2 == 0 else coolant, at + Vector3(0, _sand_y(at.x, at.z) - 0.06, 0))
	# The lift pad: a steel plate with yellow and black edges, laid on the sand (the
	# plane through the sand at its corners) and deep enough that a dune's curve
	# under it never shows an edge in the air.
	var pad := _sand_plane(bay, 3.5, 2.0)
	var pb: Basis = pad.basis
	var depth := 0.6
	kit.part(kit.box(7.0, depth, 4.0), steel, pad.origin + pb.y * (0.08 - depth * 0.5), pb)
	for dz in [-2.05, 2.05]:
		kit.part(kit.box(7.0, depth, 0.12), hazard, pad.origin + pb * Vector3(0, 0.1 - depth * 0.5, dz), pb)
	var parts := Node3D.new()
	parts.name = "StallLook"
	add_child(parts)
	kit.flush(parts)
	# A real lamp over the counter, like Dorrin's and Skrugs's.
	HangingLamp.build(self, xf, Vector3(0.2, 2.3, 0.0), mats, look, "CounterLamp", 3.2, 6.0, 0.7, 0.45)


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
