class_name MechanicYard
extends Node3D
## Issue #95: Dorrin Vask's speeder yard, out in the desert about a 30 second
## drive from the back gate (the "mechanic_yard" landmark in
## content/core/worlds/port_desert.json). This node dresses it (garage, bench,
## lift, scrap heap; issue #100: an awning and string lights over his counter, a
## tool bench and pegboard, canisters lying about, cargo droids driving round the
## yard and an unarmed assassin droid minding the garage), stands Dorrin at his
## bench and runs his shop:
##
##   [E] beside him  -- the menu: paint, looks, performance, the Grav Lifter,
##                      selling the speeder for scrap, and buying a new one: he
##                      sells every model Skrugs does, at Skrugs's prices
##                      (SpeederShop.buy_speeder). It waits in the row outside
##                      the town's back gate, like every new speeder.
##
## He only works on a speeder of yours parked in his bay (within bay_radius of the
## lift, inside his garage: issue #295 made it wall pieces you can drive into).
## Issue #295: the shop itself is SpeederShop, shared with Skrugs's garage bench in
## free roam; this node is Dorrin, his yard and his [E]. Words, prices and parts:
## content/core/vehicles/speeder_upgrades.json.
##
## The headless test calls talk(), buy(), scrap() and the menu's choose() directly:
## the same code paths as the keys.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownBuildings := preload("res://src/systems/world/town_buildings.gd")
const OUTFIT := { "head": "local:worn_darker", "torso": "local:worn_blue", "legs": "local:worn_blue" }   ## worn: tools/look/wear_outfit.gd

var demo                              ## town_demo.gd
var ground: WorldGround
var player: CharacterBody3D
var gear: GearController              ## for its HUD (prompt, toast) and its focus (E is shared)
var cfg: Dictionary = {}              ## the "mechanic" block
var shop: SpeederShop                 ## issue #295: his menu, parts and scrap (shared with Skrugs)
var menu: DroidMenu                   ## the shop's
var mechanic: Node3D                  ## Dorrin's body
var xf := Transform3D()               ## the yard's frame (on the ball: along the ground's up)
var points: Dictionary = {}
var found := false                    ## the world has the landmark
var in_reach := false
var droids: Array = []                ## issue #100: { look: Node3D, center, rx, rz, speed, a } (cargo droids on their loops)
var guard_droid: Node3D               ## issue #100: the assassin droid with no weapon


func setup(town_demo, world_ground: WorldGround, p_gear: GearController) -> void:
	demo = town_demo
	ground = world_ground
	gear = p_gear
	player = demo._player if demo != null else null
	name = "MechanicYard"


func _ready() -> void:
	cfg = SpeederUpgrades.mechanic()
	shop = SpeederShop.new()
	shop.setup(demo, gear, cfg, func(): return world_point("bay") if found else Vector3.INF)
	add_child(shop)
	menu = shop.menu
	var cc: CoreContent = CoreContent.shared()
	var world: Dictionary = demo.world if "world" in demo and not demo.world.is_empty() else cc.world_for_town("port_town")
	var id := str(cfg.get("location", "mechanic_yard"))
	for lm in world.get("landmarks", []):
		if str(lm.get("location", "")) != id:
			continue
		var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
		var origin := Vector3(at.x, ground.terrain.height_at(at.x, at.z), at.z)
		var sp := ground.sphere()
		if sp != null:
			origin = sp.surface_at(at.x, at.z)
		xf = Transform3D(PlanetSphere.tilt_to(ground.up_at(origin)) * Basis(Vector3.UP, deg_to_rad(float(lm.get("yaw_deg", 0.0)))), origin)
		found = true
	if not found:
		return
	var loc: Dictionary = cc.get_location(id)
	for k in loc.get("points", {}):
		points[k] = WorldGround._v3(loc.points[k])
	if demo.use_look:
		_dress(loc)
	_build_droids()                      # issue #543: there with the look off too, only undressed
	_build_mechanic()


func npc_name() -> String:
	return str(cfg.get("name", "the mechanic"))


## A point from the location file, in the world, on the sand.
func world_point(id: String) -> Vector3:
	var lp: Vector3 = points.get(id, Vector3.ZERO)
	var p: Vector3 = xf * Vector3(lp.x, 0.0, lp.z)
	var sp := ground.sphere()
	if sp != null:
		var dir := (p - sp.center).normalized()
		return sp.center + dir * (sp.radius + sp.elevation(dir))
	p.y = ground.terrain.height_at(p.x, p.z)
	return p


# ------------------------------------------------------------------ the bay

## Your speeder parked in the bay (the nearest one to the lift), or null.
func speeder_in_bay() -> SpeederNode:
	return shop.speeder_in_bay() if shop != null else null


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	_drive_droids(dt)
	if not found or player == null or mechanic == null:
		return
	_tick_focus()                        # he turns to you himself (MerchantNPC.plant)


func _tick_focus() -> void:
	if shop.busy():
		return
	var p := player.global_position
	var at := mechanic.global_position
	in_reach = not player.piloting and Vector2(p.x - at.x, p.z - at.z).length() <= float(cfg.get("reach", 3.4)) \
		and absf(p.y - at.y) <= 2.0 and (gear == null or gear.focus.is_empty())
	if not in_reach:
		return
	var pot := WorldState.count("race_winnings")
	if gear != null and gear.hud != null:
		gear.hud.set_prompt(RaceCrew.rule_text("collect") % pot if pot > 0 else shop.label("talk") % npc_name())
	if not player.locked and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		if pot > 0:
			collect_winnings()
		else:
			talk()


## Issue #611: he holds the pot for the speeder races; you collect it here.
## Returns the credits paid.
func collect_winnings() -> int:
	var paid := WorldState.collect_race_winnings()
	if paid > 0:
		Sound.play("coin_gain")
		if gear != null and gear.hud != null:
			gear.hud.toast(RaceCrew.rule_text("collected") % paid, 3.5)
	return paid


# ------------------------------------------------------------------ the shop (SpeederShop)

## [E] beside him: the top menu, or "bring one round" with no speeder in the bay.
func talk() -> void:
	shop.talk()


func top_options() -> Array:
	return shop.top_options()


func group_options(group: String) -> Array:
	return shop.group_options(group)


## Buy part `id` for the speeder in the bay and fit it now (SpeederShop.buy).
func buy(id: String) -> String:
	return shop.buy(id)


## Sell the speeder in the bay for scrap. Returns the credits paid (0 = none there).
func scrap() -> int:
	return shop.scrap()


# ------------------------------------------------------------------ Dorrin

func _build_mechanic() -> void:
	if demo.use_look:
		mechanic = MerchantNPC.new(CharacterKit.new(demo._flat_mats(), 0.0), "local", OUTFIT)
	else:
		mechanic = MerchantNPC.new(null)
	mechanic.name = "Mechanic"
	add_child(mechanic)
	# Behind his counter, facing where you stand to talk; he turns to you in the
	# yard's own frame (the old turn set a world yaw from a yard angle: he stood
	# side-on to his counter and leaned).
	mechanic.plant(xf.basis, world_point("mechanic"), 0.0, player)
	mechanic.rest_yaw = mechanic.yaw_to(world_point("customer"))
	mechanic.face_yaw = mechanic.rest_yaw
	mechanic.look_at_target = player
	shop.speaker = mechanic


# ------------------------------------------------------------------ the look

## The garage (open toward the town, the lift inside), the counter under its
## awning, the tool bench and the scrap heap. Issue #295: the garage is drawn from
## the same boxes it collides with. Everything is the speeder stalls' set
## (SpeederStall.look_mats: the favela's painted metal, the market's planks and
## canvas), so the cousins' stalls and Dorrin's yard read as one family business:
## scrap-sheet walls, a ribbed rusty roof, Dorrin's counter dressed like theirs, a
## ceiling hoist over the lift, a fuel pump and a generator out front. One mesh a
## material (TownBuildings.flush_merged).
func _dress(loc: Dictionary) -> void:
	var mats: LookMaterials = demo._flat_mats()
	var look := _look()
	var m := SpeederStall.look_mats(mats, look)
	var kit := TownBuildings.new(mats, look)
	kit._xf = xf
	for b in loc.get("buildings", []):
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var c := WorldGround._v3(b.get("position", [0, 0, 0]))
		match str(b.id):
			"garage_back":
				SpeederStall.scrap_wall(kit, m, c, s, Vector3.BACK, Vector3.LEFT, 951, -0.1, 0.0)
			"garage_side_a":
				SpeederStall.scrap_wall(kit, m, c, s, Vector3.RIGHT, Vector3.FORWARD, 952, -0.1, 0.0)
			"garage_side_b":
				SpeederStall.scrap_wall(kit, m, c, s, Vector3.RIGHT, Vector3.BACK, 953, -0.1, 0.0)
			"garage_roof":
				_dress_roof(kit, m, c, s)
			"bench":
				SpeederStall.dress_counter(kit, m, c, s, -0.05)
			"scrap_heap":
				_dress_heap(kit, m, c)
	_dress_garage(kit, m, loc)
	_dress_lift(kit, m)
	_dress_shop(kit, m, mats, look)
	_dress_front(kit, m)
	var parts := Node3D.new()
	parts.name = "YardLook"
	parts.top_level = true               # the parts are laid out in the world (xf), whatever the yard node is under
	add_child(parts)
	kit.flush_merged(parts, xf)


## The roof: rusty sheet with ribs across it, a dark fascia over the open door and
## two scrap patches on top.
func _dress_roof(kit: TownBuildings, m: Dictionary, c: Vector3, s: Vector3) -> void:
	kit.part(kit.box(s.x, s.y, s.z), m.rust, c + Vector3(0, s.y * 0.5, 0))
	var rib := kit.box(s.x, 0.05, 0.08)
	var n := int(s.z / 0.45)
	for k in n + 1:
		kit.part(rib, m.rust, c + Vector3(0, s.y + 0.025, -s.z * 0.5 + 0.05 + k * (s.z - 0.1) / n))
	kit.part(kit.box(0.12, 0.45, s.z + 0.1), m.dark, c + Vector3(s.x * 0.5 + 0.06, s.y - 0.2, 0))
	kit.part(kit.box(s.x + 0.1, 0.12, 0.12), m.dark, c + Vector3(0, s.y * 0.5, -s.z * 0.5 - 0.06))
	kit.part(kit.box(s.x + 0.1, 0.12, 0.12), m.dark, c + Vector3(0, s.y * 0.5, s.z * 0.5 + 0.06))
	var scrap: Array = m.scrap
	kit.part(kit.box(2.4, 0.04, 1.8), scrap[0], c + Vector3(-3.0, s.y + 0.07, 1.6), Basis(Vector3.UP, 0.08))
	kit.part(kit.box(1.6, 0.04, 2.2), scrap[3 % scrap.size()], c + Vector3(2.2, s.y + 0.07, -2.0), Basis(Vector3.UP, -0.05))


## Inside the garage: its dark floor with a hazard threshold at the door, strip
## lights under the roof, a neon gear on the back wall, a parts shelf and a tool
## cart, and over the door a rusty sign board with a glow tube (sized from its
## wall pieces).
func _dress_garage(kit: TownBuildings, m: Dictionary, loc: Dictionary) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for b in loc.get("buildings", []):
		if not str(b.id).begins_with("garage_") or str(b.id) == "garage_roof":
			continue
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var c := WorldGround._v3(b.get("position", [0, 0, 0]))
		lo = lo.min(c - s * Vector3(0.5, 0, 0.5))
		hi = hi.max(c + s * Vector3(0.5, 1, 0.5))
	if lo.x == INF:
		return
	var mid := (lo + hi) * 0.5
	var inner := hi.z - lo.z - 1.0
	kit.part(kit.box(hi.x - lo.x - 1.0, 0.05, inner), m.dark, Vector3(mid.x, 0.03, mid.z))
	kit.part(kit.box(0.35, 0.06, inner), m.hazard, Vector3(hi.x - 0.8, 0.04, mid.z))
	var chevron := kit.box(0.05, 0.065, 0.42)
	for k in 11:
		kit.part(chevron, m.dark, Vector3(hi.x - 0.8, 0.045, lo.z + 0.9 + k * (inner - 0.8) / 10.0), Basis(Vector3.UP, 0.7))
	# The sign over the door: a rusty board, a glow tube and the neon gear beside it.
	kit.part(kit.box(0.2, 0.9, 4.0), m.rust, Vector3(hi.x + 0.3, hi.y - 0.4, mid.z))
	kit.part(kit.box(0.1, 0.12, 3.4), m.neon, Vector3(hi.x + 0.42, hi.y - 0.4, mid.z))
	for dz in [-1.95, 1.95]:
		kit.part(kit.box(0.08, 0.95, 0.08), m.dark, Vector3(hi.x + 0.38, hi.y - 0.4, mid.z + dz))
	# Strip lights under the roof, in dark housings.
	for x in [lo.x + 3.0, mid.x + 1.5]:
		kit.part(kit.box(0.3, 0.08, 3.0), m.dark, Vector3(x, hi.y - 0.06, mid.z))
		kit.part(kit.box(0.16, 0.03, 2.8), m.bulb, Vector3(x, hi.y - 0.115, mid.z))
		for dz in [-1.2, 1.2]:
			kit.part(kit.cyl(0.008, 0.008, 0.1, 4), m.dark, Vector3(x, hi.y - 0.0, mid.z + dz))
	SpeederStall.neon_gear(kit, m, Vector3(lo.x + 0.45, 3.2, mid.z))
	SpeederStall.neon_gear(kit, m, Vector3(lo.x + 0.45, 3.2, mid.z + 2.4))
	# A parts shelf along the far wall (two shelves of cans, power cells and coils).
	var sh := Vector3(lo.x + 3.5, 0, hi.z - 0.75)
	for dx in [-1.0, 1.0]:
		for dz in [-0.2, 0.2]:
			kit.part(kit.box(0.05, 2.0, 0.05), m.dark, sh + Vector3(dx, 1.0, dz))
	var can := kit.cyl(0.07, 0.07, 0.2, 8)
	var colours: Array = [m.fuel, m.coolant, m.hazard, m.fuel, m.steel, m.coolant]
	for y in [0.35, 1.05, 1.75]:
		kit.part(kit.box(2.1, 0.04, 0.45), m.steel, sh + Vector3(0, y, 0))
		for k in 6:
			if (k + int(y * 10.0)) % 4 == 0:
				continue
			kit.part(can, colours[(k + int(y * 3.0)) % colours.size()], sh + Vector3(-0.85 + k * 0.34, y + 0.12, -0.05 + (k % 2) * 0.1))
	kit.part(SpeederStall._torus(0.08, 0.16), m.dark, sh + Vector3(0.5, 1.82, 0.05))
	kit.part(kit.cyl(0.1, 0.1, 0.5, 10), m.coolant, sh + Vector3(-0.4, 1.17, 0), TownBuildings.AXIS_X)
	# A red tool cart by the lift: drawers, a handle and casters.
	var cart := Vector3(mid.x - 2.6, 0, lo.z + 1.3)
	kit.part(kit.box(0.9, 0.8, 0.5), m.fuel, cart + Vector3(0, 0.52, 0))
	kit.part(kit.box(0.94, 0.04, 0.54), m.dark, cart + Vector3(0, 0.94, 0))
	for k in 4:
		kit.part(kit.box(0.84, 0.015, 0.02), m.dark, cart + Vector3(0, 0.3 + k * 0.17, 0.255))
		kit.part(kit.box(0.2, 0.025, 0.03), m.steel, cart + Vector3(0, 0.38 + k * 0.17, 0.27))
	kit.part(kit.cyl(0.015, 0.015, 0.5, 6), m.steel, cart + Vector3(0.52, 0.85, 0), TownBuildings.AXIS_Z)
	for dx in [-0.38, 0.38]:
		for dz in [-0.18, 0.18]:
			kit.part(kit.cyl(0.05, 0.05, 0.04, 8), m.dark, cart + Vector3(dx, 0.06, dz), TownBuildings.AXIS_Z)
	kit.part(kit.box(0.3, 0.12, 0.2), m.dark, cart + Vector3(-0.2, 1.02, 0))


## The lift in the bay: a steel pad with hazard edges and skid rails, two lift
## columns with folded arms and a control box, and a hoist on a rail under the
## roof with its hook block hung clear of a parked speeder.
func _dress_lift(kit: TownBuildings, m: Dictionary) -> void:
	var bay: Vector3 = points.get("bay", Vector3.ZERO)
	kit.part(kit.box(7.0, 0.12, 4.0), m.steel, bay + Vector3(0, 0.06, 0))
	for dz in [-2.05, 2.05]:
		kit.part(kit.box(7.0, 0.14, 0.12), m.hazard, bay + Vector3(0, 0.07, dz))
	for dz in [-0.9, 0.9]:
		kit.part(kit.box(6.0, 0.05, 0.22), m.dark, bay + Vector3(0, 0.145, dz))
	for dz in [-2.75, 2.75]:
		var col := bay + Vector3(0, 0, dz)
		kit.part(kit.box(0.6, 0.05, 0.6), m.dark, col + Vector3(0, 0.03, 0))
		kit.part(kit.box(0.34, 2.6, 0.34), m.hazard, col + Vector3(0, 1.3, 0))
		kit.part(kit.box(0.1, 2.4, 0.06), m.dark, col + Vector3(0.17, 1.3, -signf(dz) * 0.1))
		for dx in [-0.7, 0.7]:
			kit.part(kit.box(1.3, 0.1, 0.14), m.dark, col + Vector3(dx, 0.3, -signf(dz) * 0.25), Basis(Vector3.UP, signf(dx) * signf(dz) * 0.25))
		kit.part(kit.box(0.4, 0.06, 0.4), m.steel, col + Vector3(0, 2.63, 0))
	var cb := bay + Vector3(0.24, 1.25, 2.75)
	kit.part(kit.box(0.14, 0.4, 0.3), m.dark, cb)
	for k in 2:
		kit.part(kit.box(0.015, 0.06, 0.06), m.screen, cb + Vector3(0.075, 0.08 - k * 0.12, 0.05))
	kit.part(kit.cyl(0.035, 0.035, 0.03, 8), m.fuel, cb + Vector3(0.08, -0.02, -0.07), TownBuildings.AXIS_X)
	# The hoist rail under the roof, the trolley over the bay.
	var ry := 4.65
	kit.part(kit.box(10.5, 0.2, 0.12), m.dark, Vector3(bay.x - 2.0, ry, bay.z))
	kit.part(kit.box(10.5, 0.03, 0.3), m.dark, Vector3(bay.x - 2.0, ry - 0.1, bay.z))
	for x in [bay.x - 6.5, bay.x - 2.0, bay.x + 2.5]:
		kit.part(kit.box(0.06, 0.25, 0.06), m.dark, Vector3(x, ry + 0.2, bay.z))
	var hx := bay.x + 0.8
	kit.part(kit.box(0.4, 0.3, 0.3), m.fuel, Vector3(hx, ry - 0.3, bay.z))
	kit.part(kit.cyl(0.1, 0.1, 0.34, 10), m.dark, Vector3(hx, ry - 0.3, bay.z), TownBuildings.AXIS_Z)
	var block_y := ry - 1.4
	for dx in [-0.06, 0.06]:
		kit.part(kit.box(0.015, ry - 0.45 - block_y, 0.015), m.dark, Vector3(hx + dx, (ry - 0.45 + block_y) * 0.5, bay.z))
	kit.part(kit.box(0.22, 0.26, 0.14), m.hazard, Vector3(hx, block_y - 0.1, bay.z))
	kit.part(kit.cyl(0.06, 0.06, 0.16, 8), m.dark, Vector3(hx, block_y, bay.z), TownBuildings.AXIS_Z)
	kit.part(kit.box(0.05, 0.16, 0.05), m.steel, Vector3(hx, block_y - 0.3, bay.z))
	kit.part(kit.box(0.16, 0.05, 0.05), m.steel, Vector3(hx + 0.055, block_y - 0.36, bay.z))
	kit.part(kit.box(0.05, 0.1, 0.05), m.steel, Vector3(hx + 0.115, block_y - 0.31, bay.z))


## Issue #100: the shop dressed up. An awning over Dorrin's counter (poles cut to
## its slope, rails and braces, a valance with the string of bulbs under it, a
## scrap patch on top), a tool bench with drawers, a vice, a grinder and a framed
## pegboard of tools, banded crates, and fuel and coolant canisters lying about
## (some knocked over), all seeded so the yard looks the same every visit.
func _dress_shop(kit: TownBuildings, m: Dictionary, mats: LookMaterials, look: LookEnvironment) -> void:
	var bench: Vector3 = Vector3(-1.5, 0, 7)
	var x0 := bench.x - 1.6                       # the awning's back and front edges
	var x1 := bench.x + 1.8
	var xc := (x0 + x1) * 0.5
	var tilt_a := 0.12
	var tilt := Basis(Vector3.BACK, -tilt_a)
	var ay := func(x: float) -> float: return 3.05 - (x - xc) * tan(tilt_a) - 0.03
	for x in [bench.x - 1.4, bench.x + 1.6]:
		var top: float = ay.call(x)
		for dz in [-2.2, 2.2]:
			var z: float = bench.z + dz
			kit.part(kit.cyl(0.06, 0.06, top + 0.3, 8), m.steel, Vector3(x, (top - 0.3) * 0.5, z))
			kit.part(kit.cyl(0.09, 0.09, 0.06, 8), m.dark, Vector3(x, 0.02, z))
			var sz := signf(dz)
			kit.part(kit.cyl(0.025, 0.025, 0.6, 6), m.steel, Vector3(x, top - 0.08 - 0.212, z - sz * 0.212), Basis(Vector3.RIGHT, -sz * PI * 0.25))
		kit.part(kit.cyl(0.035, 0.035, 4.5, 8), m.steel, Vector3(x, top - 0.06, bench.z), TownBuildings.AXIS_Z)
	for dz in [-2.2, 2.2]:
		kit.part(kit.cyl(0.035, 0.035, 3.0 / cos(tilt_a), 8), m.steel, Vector3(bench.x + 0.1, 3.05 - (bench.x + 0.1 - xc) * tan(tilt_a) - 0.09, bench.z + dz), tilt * TownBuildings.AXIS_X)
	for k in 6:
		kit.part(kit.box(x1 - x0, 0.05, 0.8), m.canvas if k % 2 == 0 else m.stripe, Vector3(xc, 3.05, bench.z - 2.0 + k * 0.8), tilt)
	var fx := xc + (x1 - x0) * 0.5 * cos(tilt_a)
	var fy := 3.05 - (x1 - x0) * 0.5 * sin(tilt_a)
	for k in 6:
		kit.part(kit.box(0.02, 0.26, 0.8), m.canvas if k % 2 == 0 else m.stripe, Vector3(fx, fy - 0.13, bench.z - 2.0 + k * 0.8))
	kit.part(kit.box(1.1, 0.03, 1.5), m.scrap[3 % m.scrap.size()], Vector3(xc - 0.3, 3.05 - (-0.3) * tan(tilt_a) + 0.045, bench.z + 0.3), tilt * Basis(Vector3.UP, 0.2))     # rust-ochre, off the corner: no flag
	# String lights under the valance (issue #458: on the lamp clock, never off, like Skrugs's).
	var bulb: SphereMesh = kit.ball(0.07, 0.14, false, 8)
	var wire := kit.cyl(0.006, 0.006, 0.1, 4)
	for k in 9:
		var z := bench.z - 2.2 + k * 0.55
		var y := fy - 0.36 - 0.1 * sin(float(k) / 8.0 * PI)
		kit.part(bulb, m.bulb, Vector3(fx - 0.02, y, z))
		kit.part(wire, m.dark, Vector3(fx - 0.02, y + 0.11, z))
	# A lamp hanging from the awning over the counter (issue #458: a real light, the same lamp as Skrugs's).
	HangingLamp.build(self, xf, bench + Vector3(0.3, 2.35, 0.2), mats, look, "CounterLamp", 3.2, 6.0, 0.7, 0.5)
	# The tool bench: a rusty cabinet with drawers toward you, a steel top, a vice
	# and a grinder on it, and the framed pegboard of tools behind.
	var tb := Vector3(-4.6, 0, 9.4)
	kit.part(kit.box(3.2, 0.9, 1.0), m.rust, tb + Vector3(0, 0.45, 0))
	kit.part(kit.box(3.3, 0.08, 1.1), m.steel, tb + Vector3(0, 0.94, 0))
	for k in 4:
		var dx := -1.2 + k * 0.8
		if k < 3:
			kit.part(kit.box(0.02, 0.8, 0.02), m.dark, tb + Vector3(dx + 0.4, 0.45, -0.51))
		for y in [0.25, 0.6]:
			kit.part(kit.box(0.22, 0.03, 0.03), m.steel, tb + Vector3(dx, y, -0.52))
	kit.part(kit.box(3.1, 0.02, 0.02), m.dark, tb + Vector3(0, 0.43, -0.51))
	var v := tb + Vector3(1.2, 0.98, -0.25)
	kit.part(kit.box(0.24, 0.08, 0.18), m.dark, v + Vector3(0, 0.04, 0))
	for dx in [-0.06, 0.06]:
		kit.part(kit.box(0.05, 0.14, 0.2), m.steel, v + Vector3(dx, 0.15, 0))
	kit.part(kit.cyl(0.015, 0.015, 0.36, 6), m.steel, v + Vector3(0, 0.13, 0), TownBuildings.AXIS_X)
	kit.part(kit.cyl(0.012, 0.012, 0.22, 6), m.steel, v + Vector3(-0.2, 0.13, 0), TownBuildings.AXIS_Z)
	var gr := tb + Vector3(-0.9, 0.98, -0.15)
	kit.part(kit.box(0.2, 0.06, 0.16), m.dark, gr + Vector3(0, 0.03, 0))
	kit.part(kit.cyl(0.07, 0.07, 0.26, 10), m.coolant, gr + Vector3(0, 0.14, 0), TownBuildings.AXIS_X)
	for dx in [-0.18, 0.18]:
		kit.part(kit.cyl(0.1, 0.1, 0.03, 12), m.steel, gr + Vector3(dx, 0.14, 0), TownBuildings.AXIS_X)
		kit.part(kit.cyl(0.11, 0.11, 0.04, 12), m.dark, gr + Vector3(dx * 1.12, 0.17, 0), TownBuildings.AXIS_X)
	kit.part(kit.box(3.2, 1.6, 0.08), m.board, tb + Vector3(0, 1.9, 0.55))
	kit.part(kit.box(3.3, 0.06, 0.1), m.dark, tb + Vector3(0, 2.72, 0.55))
	for dx in [-1.62, 1.62]:
		kit.part(kit.box(0.06, 1.7, 0.1), m.dark, tb + Vector3(dx, 1.9, 0.55))
	var rng := RandomNumberGenerator.new()
	rng.seed = 100
	for k in 9:
		var t: BoxMesh = kit.box(0.06, rng.randf_range(0.3, 0.6), 0.04)
		var tool_at := tb + Vector3(-1.3 + k * 0.32, 1.95 + rng.randf_range(-0.3, 0.3), 0.5)
		kit.part(t, m.steel if k % 3 else m.hazard, tool_at, Basis(Vector3.BACK, rng.randf_range(-0.4, 0.4)))
	kit.part(kit.box(2.9, 0.03, 0.22), m.steel, tb + Vector3(0, 2.55, 0.42))
	for k in 5:
		kit.part(kit.cyl(0.055, 0.055, 0.15, 8), [m.fuel, m.coolant, m.hazard][k % 3], tb + Vector3(-1.1 + k * 0.5, 2.645, 0.42))
	kit.part(SpeederStall._torus(0.12, 0.18), m.dark, tb + Vector3(1.75, 1.6, 0.5), Basis(Vector3.RIGHT, PI * 0.5))
	# Crates by the garage door (issue #295: beside it, not in it), banded.
	var band := kit.box(0.93, 0.07, 0.93)
	for c in [Vector3(-2.4, 0.45, -5.4), Vector3(-2.2, 1.3, -5.2), Vector3(-1.2, 0.45, -5.6)]:
		var turn := Basis(Vector3.UP, c.x * 0.4)
		kit.part(kit.box(0.9, 0.9, 0.9), m.crate, c, turn)
		for dy in [-0.3, 0.3]:
			kit.part(band, m.dark, c + Vector3(0, dy, 0), turn)
	# Canisters lying about: fuel red, coolant teal, some on their sides.
	var paints: Array = [m.fuel, m.coolant, m.hazard, m.steel]
	var ring := kit.cyl(0.29, 0.29, 0.05, 10)
	for k in 16:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, 15.0)
		var at := Vector3(2.0 + cos(a) * r, 0.0, sin(a) * r)
		if (at.x > -3.0 and at.x < 12.0 and absf(at.z) < 3.0) or (at.x < -2.5 and absf(at.z) < 5.5) or Vector2(at.x + 1.5, at.z - 7.0).length() < 2.5:
			continue                 # not on the way into the garage, in it or at the counter
		var tall := snappedf(rng.randf_range(0.6, 1.0), 0.1)
		var body := kit.cyl(0.28, 0.28, tall, 10)
		if k % 3 == 0:
			var lie := Basis.from_euler(Vector3(PI * 0.5, rng.randf() * TAU, 0))
			kit.part(body, paints[k % paints.size()], at + Vector3(0, 0.28, 0), lie)
			for d in [-0.3, 0.3]:
				kit.part(ring, m.dark, at + Vector3(0, 0.28, 0) + lie * Vector3(0, tall * d, 0), lie)
		else:
			var turn := Basis(Vector3.UP, rng.randf() * TAU)
			kit.part(body, paints[k % paints.size()], at + Vector3(0, tall * 0.5, 0), turn)
			for d in [0.25, 0.75]:
				kit.part(ring, m.dark, at + Vector3(0, tall * d, 0), turn)


## Out front: a fuel pump by the garage's corner (body, screen, hose and nozzle,
## two bollards) and a generator against the garage's side with its cable up the
## wall.
func _dress_front(kit: TownBuildings, m: Dictionary) -> void:
	var fp := Vector3(-1.2, 0, -4.4)
	kit.part(kit.box(0.7, 0.12, 0.55), m.dark, fp + Vector3(0, 0.06, 0))
	kit.part(kit.box(0.55, 1.5, 0.4), m.fuel, fp + Vector3(0, 0.87, 0))
	kit.part(kit.box(0.6, 0.12, 0.45), m.dark, fp + Vector3(0, 1.68, 0))
	kit.part(kit.box(0.6, 0.1, 0.45), m.hazard, fp + Vector3(0, 0.4, 0))
	kit.part(kit.box(0.02, 0.26, 0.3), m.dark, fp + Vector3(0.28, 1.3, 0))
	kit.part(kit.box(0.01, 0.2, 0.24), m.screen, fp + Vector3(0.292, 1.3, 0))
	kit.part(kit.box(0.08, 0.14, 0.06), m.dark, fp + Vector3(0.3, 0.95, 0.12))
	kit.part(kit.box(0.04, 0.04, 0.2), m.steel, fp + Vector3(0.34, 0.9, 0.12), Basis(Vector3.RIGHT, 0.5))
	kit.part(SpeederStall._torus(0.13, 0.17), m.dark, fp + Vector3(0.0, 0.85, 0.22), Basis(Vector3.RIGHT, PI * 0.5))
	for dz in [-0.6, 0.6]:
		kit.part(kit.cyl(0.08, 0.08, 0.8, 8), m.hazard, fp + Vector3(0.6, 0.4, dz))
		kit.part(kit.cyl(0.085, 0.085, 0.12, 8), m.dark, fp + Vector3(0.6, 0.55, dz))
	var g := Vector3(-9.0, 0, -5.0)
	kit.part(kit.box(1.2, 0.75, 0.7), m.hazard, g + Vector3(0, 0.4, 0))
	kit.part(kit.box(1.24, 0.05, 0.74), m.dark, g + Vector3(0, 0.8, 0))
	for k in 7:
		kit.part(kit.box(0.03, 0.5, 0.02), m.dark, g + Vector3(-0.45 + k * 0.15, 0.42, -0.36))
	kit.part(kit.cyl(0.15, 0.15, 0.7, 10), m.fuel, g + Vector3(-0.05, 0.97, 0), TownBuildings.AXIS_X)
	kit.part(kit.cyl(0.035, 0.035, 0.55, 6), m.steel, g + Vector3(0.48, 1.1, 0.2))
	kit.part(kit.cyl(0.05, 0.05, 0.06, 6), m.dark, g + Vector3(0.48, 1.38, 0.2))
	kit.part(kit.cyl(0.02, 0.02, 3.9, 6), m.dark, g + Vector3(-0.5, 2.75, 0.3))
	kit.part(kit.box(0.2, 0.25, 0.08), m.dark, g + Vector3(-0.5, 4.6, 0.31))


## The scrap heap: slabs of rust, steel and scrap sheet tumbled together, a
## stripped speeder hull on top, an old engine half in the sand, sheets leaning on
## it. Seeded: the same heap every visit.
func _dress_heap(kit: TownBuildings, m: Dictionary, c: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 95
	var scrap: Array = m.scrap
	for i in 9:
		var sz := Vector3(snappedf(rng.randf_range(0.8, 2.2), 0.1), snappedf(rng.randf_range(0.4, 1.4), 0.1), snappedf(rng.randf_range(0.8, 2.4), 0.1))
		var at := c + Vector3(rng.randf_range(-1.6, 1.6), sz.y * 0.4 + (i / 3) * 0.5, rng.randf_range(-1.6, 1.6))
		var rot := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0, TAU), rng.randf_range(-0.3, 0.3)))
		var mat: Material = m.steel if i % 3 == 0 else (m.rust if i % 3 == 1 else scrap[i % scrap.size()])
		kit.part(kit.box(sz.x, sz.y, sz.z), mat, at, rot)
	# A speeder's stripped hull, nose down on the heap.
	var hull := c + Vector3(0.4, 2.0, 0.3)
	var hb := Basis(Vector3.UP, 0.6) * Basis(Vector3.BACK, 0.22) * Basis(Vector3.RIGHT, 0.1)
	kit.part(kit.box(2.8, 0.5, 1.3), scrap[1 % scrap.size()], hull, hb)
	kit.part(kit.box(1.2, 0.35, 1.1), m.dark, hull + hb * Vector3(-0.4, 0.4, 0), hb)
	kit.part(kit.cyl(0.0, 0.5, 0.9, 10), scrap[1 % scrap.size()], hull + hb * Vector3(1.85, 0, 0), hb * Basis(Vector3.BACK, -PI * 0.5))
	kit.part(kit.box(0.6, 0.5, 0.06), m.hazard, hull + hb * Vector3(-1.3, 0.45, 0), hb)
	# An old engine half in the sand, and sheets leaning on the heap.
	var en := c + Vector3(-2.4, 0.25, 2.2)
	kit.part(kit.cyl(0.42, 0.42, 1.4, 12), m.rust, en, Basis(Vector3.UP, 0.8) * TownBuildings.AXIS_Z)
	kit.part(kit.cyl(0.46, 0.46, 0.1, 12), m.dark, en + Basis(Vector3.UP, 0.8) * Vector3(0, 0, -0.7), Basis(Vector3.UP, 0.8) * TownBuildings.AXIS_Z)
	for k in 3:
		var lean := Basis(Vector3.UP, 1.9 + k * 0.5) * Basis(Vector3.RIGHT, -0.35)
		kit.part(kit.box(1.3, 1.6, 0.04), scrap[(k + 2) % scrap.size()], c + Vector3(2.4 - k * 0.5, 0.72, -1.2 + k * 1.2) , lean)


# ------------------------------------------------------------------ droids (issue #100)

## Cargo droids driving loops round the yard, and an assassin droid with no
## weapon standing by the garage door. Looks only: nobody owns them.
## Issue #543: with the look layer off they are there all the same (bare nodes on
## the same loops and spot), only not dressed.
func _build_droids() -> void:
	var dressed: bool = demo.use_look
	var mats: LookMaterials = demo._flat_mats() if dressed else null
	var variants := ["tan", "olive", "blue"]
	var loops := [[Vector3(9, 0, 0), 9.0, 11.0, 2.4], [Vector3(10, 0, -1), 7.0, 13.0, -2.0], [Vector3(10, 0, 1), 9.0, 8.0, 2.9]]
	for i in loops.size():
		var L: Array = loops[i]
		var look: Node3D = DroidKit.build("cargo", DroidRoster.variant_cfg("cargo", variants[i % variants.size()]), mats,
			DroidRoster.kind_cfg("cargo").get("look", {})) if dressed else Node3D.new()
		look.name = "YardCargo%d" % (i + 1)
		add_child(look)
		if dressed:
			DroidKit.set_awake(look, true)
		droids.append({ "look": look, "center": L[0], "rx": float(L[1]), "rz": float(L[2]), "speed": float(L[3]), "a": TAU * i / 3.0 })
	if dressed:
		guard_droid = DroidKit.build("assassin", DroidRoster.variant_cfg("assassin", "gunmetal"), mats, ShipSalesman.model_look({ "kind": "assassin" }))
		ShipSalesman._disarm(guard_droid)
	else:
		guard_droid = Node3D.new()
	guard_droid.name = "YardAssassin"
	add_child(guard_droid)
	if dressed:
		DroidKit.set_awake(guard_droid, true)
		DroidKit.play_anim(guard_droid, "idle")
	guard_droid.global_transform = Transform3D(xf.basis * Basis(Vector3.UP, -PI * 0.5), _ground(Vector3(-2.0, 0, 5.6)))     # issue #295: beside the door, not in it
	_drive_droids(0.0)


## A point in the yard's frame, on the ground.
func _ground(local: Vector3) -> Vector3:
	var p: Vector3 = xf * Vector3(local.x, 0.0, local.z)
	var sp := ground.sphere()
	if sp != null:
		var dir := (p - sp.center).normalized()
		return sp.center + dir * (sp.radius + sp.elevation(dir))
	p.y = ground.terrain.height_at(p.x, p.z)
	return p


func _drive_droids(dt: float) -> void:
	for d in droids:
		var look: Node3D = d.look
		if not is_instance_valid(look):
			continue
		var rx: float = d.rx
		var rz: float = d.rz
		# Even speed round an ellipse: step the angle by speed over the local radius.
		var a: float = d.a
		var rl := Vector2(rx * sin(a), rz * cos(a)).length()
		a += float(d.speed) * dt / maxf(rl, 0.5)
		d.a = a
		var c: Vector3 = d.center
		var local := c + Vector3(cos(a) * rx, 0, sin(a) * rz)
		var tangent := Vector3(-sin(a) * rx, 0, cos(a) * rz).normalized() * signf(float(d.speed))
		var yaw := atan2(-tangent.x, -tangent.z)
		look.global_transform = Transform3D(xf.basis * Basis(Vector3.UP, yaw), _ground(local))


## The scene's look, for its lamp clock; null in a bare dressing (tests, lookdev).
func _look() -> LookEnvironment:
	return demo.get("look") as LookEnvironment if demo != null else null
