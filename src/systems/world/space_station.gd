class_name SpaceStation
extends Node3D
## A space station in this planet's sky (StationHull: its shape; one config file
## per station in content/core/stations/). Its boxes are already in the ship's
## ground and the walkers' colliders (the "station" landmark put them there); this
## node adds what moves and what you see:
##   - the look: every part merged by finish, the cruiser's metal, glass, glow
##   - the energy shield across the bay's mouth (ships and bolts through, not you),
##     the shields in the tunnels' roofs and in every floor's ceiling, round the
##     gaps between floors and across each floor's gap (you through, not the air)
##   - an elevator in each tower: a platform riding its shaft floor to floor, and the
##     shaft's doors, open only where it has stopped
##   - Z docking: the same calls the cruiser answers (can_dock, dock_path, dock_yaw,
##     dock_cfg, line), so ShipPilot flies you into its bay the same way
##   - the label naming it in the sky while you fly, interior lights, and a pull back
##     aboard if you fall out
##   - issue #315: what is in its floors (StationFill) and the people aboard
##     (StationCrowd); issue #314: the Remnant's deck and who holds it
##     (StationRemnant)
##   - open to the air where the planet's air is breathable (no harmful_surface:
##     the ringed giant): the bay's shield lets you walk out, you roam outside on
##     the jetpack, and you are pulled back only if you drop toward a gas ball's
##     clouds (open_air)
##   - issue #317: the wrecks adrift in the belt under it (BeltWrecks; their boxes
##     are in the ground with the station's), down through the engine deck's drop
##     hatch; over them no pull back, but fall off one and the belt has you
## Nothing here is about one planet: SpaceStation is built for every "station"
## landmark of the world it is in (town_demo._build_stations).

const SHADER := preload("res://src/systems/look/shaders/cruiser_metal.gdshader")
const FINISHES := { "hull": 0, "trim": 1, "deck": 2, "wall": 3, "grate": 4, "cargo": 6, "console": 7, "rail": 8,
	"bridge": 9, "pad": 10, "beacon": 11, "screen": 12,
	# The rooms' finishes (StationFill._t: tinted, in the room's own frame).
	"carpet": 14, "rug": 15, "tile": 16, "plate": 17, "rubber": 18, "marble": 19, "velvet": 20, "cloth": 21,
	"brass": 22, "veneer": 23, "woodfloor": 24, "locker": 25, "books": 26, "foliage": 27, "water": 28,
	"hazard": 29, "barrel": 30, "art": 31, "pavers": 32 }
const StationFill := preload("res://src/systems/world/station_fill.gd")
const TownBuildings := preload("res://src/systems/world/town_buildings.gd")
const StationCrowd := preload("res://src/systems/world/station_crowd.gd")
const StationRemnant := preload("res://src/systems/world/station_remnant.gd")
const CharBody := preload("res://src/systems/player/character_body.gd")
const Ladders := preload("res://src/systems/world/ladders.gd")

var demo                               ## town_demo.gd
var ground: WorldGround
var hull: StationHull
var cfg: Dictionary = {}
var landmark: Dictionary = {}
var id := ""
var frame := Transform3D.IDENTITY
var inv := Transform3D.IDENTITY
var vessel_name := ""
var cars: Array = []                   ## per tower: { tower, c, stops, body, look, at, prev, tick, i, dir, wait, moving, doors: [[floor, CollisionShape3D, Node3D]] }
var falls := 0                         ## times you were pulled back aboard (traces, tests)
var rides := 0                         ## elevator stops reached with you aboard the car (traces)
var fill: StationFill                  ## issue #315: what is in the floors (with the look layer only)
var fill_floors: Array = []            ## { tower, i, c, y, r, node, built }: one per dressed floor
var _fill_ladders := 0                 ## fill.ladders already noted in the Ladders registry
var fill_ms := 0.0                     ## the longest tick spent building the fill, ms (review)
var crowd: StationCrowd                ## issue #315: the people aboard (the config's "crowd")
var remnant: StationRemnant            ## issue #314: the Remnant's deck and who holds it (the config's "remnant")
var open_air := false                  ## the planet's air is breathable: you may go outside (setup)
var belt: Array = []                   ## issue #317: the wrecks adrift under it (BeltWrecks.layout), station frame
var belt_falls := 0                    ## times the belt had you (traces, tests)
var refineries: Array = []             ## issue #838: QuantoniumRefinery on the skimmer gantry (StationHull.skimmer_units)

var _root: Node3D
var _inside: Node3D
var _layer: CanvasLayer
var _label: Label
var _was_aboard := false
var _warned := false                   ## issue #702: warned of the pull on this drop
var _shadow_capped := false
var _fill_tick := 0
var _fade: ColorRect                   ## issue #317: black over the screen as the belt takes you
var _fade_tw: Tween

static var _meshes: Dictionary = {}    ## "<station>/<finish>" -> ArrayMesh, built once a session


func setup(town_demo, world_ground: WorldGround, lm: Dictionary) -> void:
	demo = town_demo
	ground = world_ground
	landmark = lm
	hull = StationHull.for_id(str(lm.get("station", "")))
	cfg = hull.cfg if hull != null else {}
	id = str(lm.get("id", hull.id if hull != null else "station"))
	frame = StationHull.frame(ground, id)
	inv = frame.affine_inverse()
	name = "SpaceStation_" + id
	vessel_name = NameHooks.vessel(cfg, "station:" + id)
	var pl = demo.get("planet") if demo != null else null
	open_air = pl is Dictionary and not (pl as Dictionary).is_empty() and HarmfulSurface.config(pl).is_empty()
	if hull != null:
		belt = BeltWrecks.layout(hull)


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "Frame"
	add_child(_root)
	_root.transform = frame
	if hull == null:
		return
	if demo != null and demo.use_look:
		_build_look()
		_lights()
	for l in hull.ladders:               # the roof's and the gantry's ladders: climbable (PlayerClimber)
		Ladders.add(_root, l)
	_plan_fill()                         # issue #543: the floors' colliders with the look off too (solids only)
	_build_shield()
	_build_hatches()
	_build_tubes()
	_build_gap_shields()
	_build_elevators()
	_build_label()
	if not (cfg.get("crowd", {}) as Dictionary).is_empty():
		crowd = StationCrowd.new()
		crowd.setup(self, demo, hull)
		_root.add_child(crowd)
	if not StationRemnant.deck(hull).is_empty():
		remnant = StationRemnant.new()
		remnant.setup(self, demo, hull)
		add_child(remnant)
	_build_skimmer()


# ------------------------------------------------------------------ queries

func to_world(local: Vector3) -> Vector3:
	return frame * local


func aboard(p: Vector3) -> bool:
	return hull != null and hull.aboard(inv * p)


## A world point in the station's own frame (the F11 map's side view).
func to_local_point(p: Vector3) -> Vector3:
	return inv * p


## Where the pointer goes for "station:<part>" (ObjectiveHud.where): one of its map
## places (StationHull.map_places: the bay, a floor), or the bay with no part.
func objective_point(part: String = "") -> Vector3:
	if hull == null:
		return Vector3.INF
	var at := hull.map_place(part if part != "" else "bay")
	return frame * at if at != Vector3.INF else Vector3.INF


func label() -> String:
	var l := str(cfg.get("label", "station"))
	return str(cfg.get("name_fmt", "%s")) % vessel_name if vessel_name != "" else l


func distance(p: Vector3) -> float:
	return p.distance_to(frame.origin)


func can_dock(p: Vector3) -> bool:
	return hull != null and distance(p) <= float(dock_cfg().get("radius", 2500.0)) and not aboard(p)


func dock_path(p: Vector3) -> Array:
	return hull.dock_path(inv * p).map(func(l): return frame * (l as Vector3))


## The dock pad's heading (a yaw about world up, for a station level with the port).
func dock_yaw() -> float:
	return (frame.basis * Basis(Vector3.UP, float(hull.dock_pad().get("yaw", 0.0)))).get_euler().y


## Issue #838: the station's up (its frame's y). Not world up for one stood level
## with the ball far round it (StationHull.ball_basis): ShipPilot then turns round
## to dock_basis() and sinks along this.
func dock_up() -> Vector3:
	return frame.basis.y.normalized()


## A ship set down on the dock pad, nose out to space: the whole turn, not only its yaw.
func dock_basis() -> Basis:
	return (frame.basis * Basis(Vector3.UP, float(hull.dock_pad().get("yaw", 0.0)))).orthonormalized()


func dock_cfg() -> Dictionary:
	return cfg.get("dock", {})


func line(key: String) -> String:
	return str(cfg.get("lines", {}).get(key, ""))


## The dock pad, in the world.
func dock_point() -> Vector3:
	return frame * (hull.dock_pad().get("at", Vector3.ZERO) as Vector3)


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	if hull == null:
		return
	var p: Node3D = demo._player if demo != null and "_player" in demo else null
	var at := inv * p.global_position if p != null and is_instance_valid(p) else Vector3.INF
	for car in cars:
		_step_car(car, dt, at)
	_step_fill()
	if p == null or not is_instance_valid(p):
		return
	if _inside != null:
		_inside.visible = distance(p.global_position) < float(cfg.get("lights_within", 3000.0))
	_fall_guard(p)
	_tick_skimmer(p)
	var here := hull.aboard(at)
	if demo.look != null and here != _shadow_capped:
		_shadow_capped = here
		demo.look.set_shadow_cap(float(cfg.get("aboard_shadow_distance", 0.0)) if here else 0.0)


## Issue #838: the skimmer's quantonium tanks on its gantry (QuantoniumRefinery: the
## outposts' numbers, hit body always, look when dressed), upright on the gantry in
## the station's frame, each other's partners (one going up sets off the other).
## They wear the station's hull and its Remnant deck's mark (repainted with it).
func _build_skimmer() -> void:
	var units := hull.skimmer_units()
	if units.is_empty():
		return
	var mats: LookMaterials = demo._flat_mats() if demo != null and demo.use_look and demo.has_method("_flat_mats") else null
	var wall: Material = null
	var red: Material = null
	if mats != null:
		wall = mats.flat(Dressing.c("outpost", "steel", "#5d6168"), 0.35, 0.75)
		red = mats.faction_flat("mark", remnant.group if remnant != null else "station:" + id, 0.6, 0.2)
	for u in units:
		var ref := QuantoniumRefinery.new()
		ref.name = "Refinery_%s_%s" % [id, str(u.style)]
		ref.label = label()
		ref.host = demo
		add_child(ref)
		ref.global_transform = frame * (u.xf as Transform3D)
		ref.build(str(u.style), mats, wall, red, 0.0, "%s/%s" % [id, str(u.style)])
		refineries.append(ref)
	for ref in refineries:
		ref.partners = refineries.filter(func(x): return x != ref)
	refineries[0].blown.connect(func(): _toast(Territory.line("refinery_blown") % label(), 5.0))


## Blown tanks come back once the outposts' respawn time has passed and you are
## well away (QuantoniumRefinery's back_away_m, and never while you are aboard or on
## its gantry), as at the ground outposts; and with the deck when it changes hands.
func _tick_skimmer(p: Node3D) -> void:
	if refineries.is_empty() or Engine.get_physics_frames() % 30 != 0:
		return
	var away_m := maxf(float(QuantoniumRefinery.game_cfg().get("back_away_m", 120.0)), 600.0)
	if distance(p.global_position) < away_m:
		return
	for ref in refineries:
		if is_instance_valid(ref) and ref.due():
			ref.rebuild()


## The deck changed hands: the tanks are built again for the new holders.
func rebuild_skimmer() -> void:
	for ref in refineries:
		if is_instance_valid(ref):
			ref.rebuild()


func _exit_tree() -> void:
	if _shadow_capped and demo != null and demo.look != null:
		demo.look.set_shadow_cap(0.0)


## Fallen out of the station (off a tunnel's roof, out past the shield): back
## aboard beside the dock pad. In open air going outside is fine: over a gas ball
## (WorldGround.lethal_below) you are pulled back only once you drop the station's
## outside.drop_below metres under its lowest floor, toward the clouds; over solid
## ground, never (you land).
func _fall_guard(p: Node3D) -> void:
	if p.get("piloting") == true:
		_was_aboard = false
		return
	if open_air:
		if ground == null or ground.lethal_below == -INF or aboard(p.global_position):
			_guard_fade(0.0)
			return
		if _belt_guard(p, inv * p.global_position):
			return
		if _another_holds(p.global_position):
			_warned = false
			return                         # issue #317: another station (its belt, or nearer) has this one
		var outside: Dictionary = cfg.get("outside", {})
		var drop := float(outside.get("drop_below", 40.0))
		var below := hull.bottom_y() - (inv * p.global_position).y
		if below <= drop - float(outside.get("warn_before", 15.0)) or distance(p.global_position) > 3000.0:
			_warned = false
			return
		if below <= drop:
			if not _warned:
				_warned = true            # issue #702: once on the way down, before the pull
				_toast(line("fell_clouds_warn"), 3.0)
			return
		_warned = false
		_pull_back(p, line("fell_clouds"))
		return
	if aboard(p.global_position):
		_was_aboard = true
		return
	if _was_aboard and hull.on_roof(inv * p.global_position):
		return                         # out on a tunnel's roof walk, through its hatch
	if not _was_aboard:
		return
	if distance(p.global_position) > 1000.0:
		_was_aboard = false            # moved away (woken in the pit, towed home), not fallen
		return
	_pull_back(p, line("fell"))


## Issue #317: over the belt (within its margin_m of a wreck, across) the pull back
## toward the clouds is off: you may go down the wrecks as far as they go. Down in
## the clouds (clouds_y), or out of every hull and fall_m under the lowest pad, the
## belt has you: the screen fades over the last fade_m and you wake in the bay.
## True while over it.
func _belt_guard(p: Node3D, l: Vector3) -> bool:
	if belt.is_empty():
		return false
	var bc := BeltWrecks.cfg_of(hull)
	if not BeltWrecks.over_belt(belt, l, float(bc.get("margin_m", 40.0))):
		_guard_fade(0.0)
		return false
	_warned = false
	if BeltWrecks.lost(belt, bc, l):
		_lost_to_belt(p, bc)
		return true
	# The last fade_m before the clouds, or (out of every hull) before fall_m under
	# the lowest pad: the screen goes dark.
	var fade := maxf(0.1, float(bc.get("fade_m", 10.0)))
	var line := float(bc.get("clouds_y", -300.0))
	if not BeltWrecks.in_wreck(belt, l):
		line = maxf(line, BeltWrecks.lost_below(belt, float(bc.get("fall_m", 25.0))))
	_guard_fade(clampf((line + fade - l.y) / fade, 0.0, 1.0))
	return true


## Issue #317: with more than one station in this sky (the ring station and the
## skimmer outposts over the giant), only the one you are nearest, or whose belt
## you are over, guards your fall: never a far one pulling you off another's
## wrecks.
func _another_holds(at: Vector3) -> bool:
	var list = demo.get("stations") if demo != null else null
	if not (list is Array):
		return false
	var mine := distance(at)
	for s in list:
		if s == self or not is_instance_valid(s):
			continue
		var o: SpaceStation = s
		if not o.belt.is_empty() and BeltWrecks.over_belt(o.belt, o.inv * at,
				float(BeltWrecks.cfg_of(o.hull).get("margin_m", 40.0))):
			return true
		if o.distance(at) < mine:
			return true
	return false


## The belt had you: back in the bay, nothing taken (the fall did this, as off a
## platform world's edge), and the screen comes back up from black.
func _lost_to_belt(p: Node3D, bc: Dictionary) -> void:
	belt_falls += 1
	WorldState.bump("falls")
	var text := str(bc.get("lines", {}).get("fell", ""))
	if text != "":
		WorldState.log_event(text)
	_pull_back(p, (text + "  " if text != "" else "") + GameFlow.label("fall_wake"))
	_set_fade(1.0)
	if is_inside_tree():
		_fade_tw = create_tween()
		_fade_tw.tween_method(_set_fade, 1.0, 0.0, 0.8)


## The guard's fade, unless the screen is still coming back up after a fall.
func _guard_fade(a: float) -> void:
	if _fade_tw != null and _fade_tw.is_running():
		return
	_set_fade(a)


func _set_fade(a: float) -> void:
	if _fade == null:
		if a <= 0.0:
			return
		var layer := CanvasLayer.new()
		layer.layer = 20
		add_child(layer)
		_fade = ColorRect.new()
		_fade.color = Color(0, 0, 0, 0)
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_fade)
	_fade.color.a = a


func _pull_back(p: Node3D, text: String) -> void:
	p.global_position = frame * hull.spawn_point()
	if p is CharacterBody3D:
		(p as CharacterBody3D).velocity = Vector3.ZERO
	if p.has_method("align_to_ground"):
		p.call("align_to_ground", true)
	falls += 1
	_toast(text, 3.0)


# ------------------------------------------------------------------ the floors' fill

## Issue #315: every floor with a "use" in the config's "fill" block gets its
## furniture (StationFill), built a couple of milliseconds a physics tick so the
## scene does not hitch,
## each under a node of its own that is only shown near the camera (_show_fill).
func _plan_fill() -> void:
	if demo == null or (cfg.get("fill", {}) as Dictionary).is_empty():
		return
	var mats: LookMaterials = demo.decor.mats if demo.get("decor") != null and demo.decor.mats != null else LookMaterials.new()
	var kit := TownBuildings.new(mats, demo.look)
	fill = StationFill.new(kit, hull, _mat)
	fill.solids_only = not demo.use_look
	fill.faction_mats("station:" + id)        # issue #314: the Remnant deck's red, repainted when it is taken
	for t in hull.towers:
		for i in (t.floors as Array).size():
			var f: Dictionary = t.floors[i]
			if fill.floor_cfg(str(f.id)).is_empty():
				continue
			var node := Node3D.new()
			node.name = "Fill_%s_%s" % [str(t.id), str(f.id)]
			node.visible = false
			_root.add_child(node)
			fill_floors.append({ "tower": t, "i": i, "c": t.c, "y": float(f.y), "r": float(f.r), "node": node, "built": false })


func _step_fill() -> void:
	if fill_floors.is_empty():
		return
	while _fill_ladders < fill.ladders.size():   # the shacks', containers' and catwalks' ladders, as they are built
		Ladders.add(_root, fill.ladders[_fill_ladders])
		_fill_ladders += 1
	for ff in fill_floors:
		if bool(ff.built):
			continue
		var t0 := Time.get_ticks_usec()
		if not bool(ff.get("begun", false)):
			ff.begun = true
			ff.built = not fill.begin(ff.node, ff.tower, int(ff.i))
		elif fill.step(float(cfg.get("fill", {}).get("budget_ms", 2.0))):
			ff.built = true
			ff.draws = fill.draws
		fill_ms = maxf(fill_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		return                             # a little of one floor a tick
	_fill_tick += 1
	if _fill_tick % 6 == 0:
		_show_fill()


## A floor's fill is drawn only while the camera is within show_dy metres of its
## height band and show_m of its glass: the floor you are on and the ones just
## above and below it. Seen from further (another floor, outside, the flight in)
## the rooms are empty glass, which nobody can tell apart at that range.
func _show_fill() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var l := inv * cam.global_position
	var fc: Dictionary = cfg.get("fill", {})
	var max_dy := float(fc.get("show_dy", 30.0))
	var max_dh := float(fc.get("show_m", 120.0))
	for ff in fill_floors:
		var y0 := float(ff.y)
		var dy := maxf(0.0, maxf(y0 - l.y, l.y - (y0 + hull.floor_h)))
		var dh := maxf(0.0, Vector2(l.x - (ff.c as Vector2).x, l.z - (ff.c as Vector2).y).length() - float(ff.r))
		(ff.node as Node3D).visible = dy <= max_dy and dh <= max_dh


# ------------------------------------------------------------------ the elevators

## A platform in each tower's shaft (an AnimatableBody3D, so whoever stands on it
## rides it with their normal movement), and the shaft's doors on every floor.
func _build_elevators() -> void:
	var el: Dictionary = cfg.get("elevator", {})
	var r := float(el.get("car_radius", 4.5))
	for e in hull.elevators():
		var c: Vector2 = e.c
		var body := AnimatableBody3D.new()
		body.name = "Elevator_" + str(e.tower)
		body.sync_to_physics = true
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = 0.5
		cs.shape = shape
		cs.position = Vector3(0, -0.25, 0)
		body.add_child(cs)
		_root.add_child(body)
		var y0: float = e.stops[0]
		body.position = Vector3(c.x, y0, c.y)
		var look: Node3D = null
		if demo != null and demo.use_look:
			look = Node3D.new()
			look.name = "Look"
			body.add_child(look)
			_dress_car(look, r)
		var car := { "tower": str(e.tower), "c": c, "stops": e.stops, "body": body, "look": look, "at": y0,
			"prev": y0, "tick": 0, "i": 0, "dir": 1,
			"wait": float(el.get("wait", 3.5)), "moving": false, "target": 0, "doors": [], "rider": false }
		for d in hull.doors:
			if str(d.tower) != str(e.tower):
				continue
			var db := StaticBody3D.new()
			db.name = "ShaftDoor_%s_%d" % [str(e.tower), int(d.floor)]
			var dcs := CollisionShape3D.new()
			var ds := BoxShape3D.new()
			ds.size = d.size
			dcs.shape = ds
			db.add_child(dcs)
			_root.add_child(db)
			db.transform = d.xf
			var door_look: Node3D = null
			if demo != null and demo.use_look:
				door_look = _mesh_box(d.size, _door_mat(), d.xf)
			car.doors.append([int(d.floor), dcs, door_look])
		cars.append(car)
		_set_doors(car)


## One frame of a car: wait at its stop (its doors open), then move on to the next
## stop: on along its way with you aboard, to your floor when you stand by its
## shaft elsewhere, else on round its floors.
func _step_car(car: Dictionary, dt: float, player: Vector3) -> void:
	var el: Dictionary = cfg.get("elevator", {})
	var stops: Array = car.stops
	var c: Vector2 = car.c
	var body: AnimatableBody3D = car.body
	var on_car := Vector2(player.x - c.x, player.z - c.y).length() <= float(el.get("car_radius", 4.5)) + 0.3 \
		and absf(player.y - float(car.at)) < 2.5
	var n := stops.size()
	car.prev = float(car.at)                 # issue #604: where it was last tick (draw_y)
	car.tick = Engine.get_physics_frames()
	if bool(car.moving):
		var ty := float(stops[int(car.target)])
		car.at = move_toward(float(car.at), ty, float(el.get("speed", 4.0)) * dt)
		body.position = Vector3(c.x, float(car.at), c.y)
		if absf(float(car.at) - ty) < 0.001:
			car.moving = false
			car.i = int(car.target)
			car.wait = float(el.get("wait", 3.5))
			if on_car:
				rides += 1
			_set_doors(car)
		return
	car.wait = float(car.wait) - dt
	if float(car.wait) > 0.0:
		return
	var next := -1
	if on_car:
		if int(car.i) + int(car.dir) < 0 or int(car.i) + int(car.dir) >= n:
			car.dir = -int(car.dir)
		next = int(car.i) + int(car.dir)
	else:
		var called := _called_floor(car, player)
		if called == int(car.i):
			car.wait = 0.5             # you are at its door: it waits for you
			return
		if called >= 0:
			next = called
			car.dir = 1 if called > int(car.i) else -1
		else:
			if int(car.i) + int(car.dir) < 0 or int(car.i) + int(car.dir) >= n:
				car.dir = -int(car.dir)
			next = int(car.i) + int(car.dir)
	car.target = clampi(next, 0, n - 1)
	car.moving = true
	_set_doors(car)


## The floor whose bridges (or the gap round the shaft) you stand on in this car's
## tower, or -1.
func _called_floor(car: Dictionary, player: Vector3) -> int:
	if player == Vector3.INF:
		return -1
	var c: Vector2 = car.c
	if Vector2(player.x - c.x, player.z - c.y).length() > hull.gap_r + 2.0:
		return -1
	var stops: Array = car.stops
	for k in stops.size():
		if player.y >= float(stops[k]) - 0.5 and player.y <= float(stops[k]) + 3.0:
			return k
	return -1


## Issue #604: the car's height to draw this frame (the station's frame). The car
## moves on the physics tick; the player and the camera are drawn between ticks
## (CharacterBody.render_origin), so a car drawn at its tick height steps against
## them and its riders shake. Its look and the crowd's riders (StationCrowd) are
## drawn here instead: the point between last tick and this one, like the player.
static func draw_y(car: Dictionary) -> float:
	var at := float(car.at)
	if not CharBody.smoothing_active() or Engine.get_physics_frames() - int(car.get("tick", 0)) > 1:
		return at
	return lerpf(float(car.get("prev", at)), at, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))


## Each frame: the cars' looks at their drawn height (draw_y).
func _smooth_cars() -> void:
	for car in cars:
		var look = car.get("look")
		if look == null:
			continue
		var off := draw_y(car) - float(car.at)
		if (look as Node3D).position.y != off:
			(look as Node3D).position.y = off


## Open the doors of the floor the car has stopped at; close the rest.
func _set_doors(car: Dictionary) -> void:
	for d in car.doors:
		var open: bool = not bool(car.moving) and int(d[0]) == int(car.i)
		(d[1] as CollisionShape3D).set_deferred("disabled", open)
		if d[2] != null:
			(d[2] as Node3D).visible = not open


func _dress_car(body: Node3D, r: float) -> void:
	var deck := CylinderMesh.new()
	deck.top_radius = r
	deck.bottom_radius = r
	deck.height = 0.5
	deck.radial_segments = 32
	_mesh(deck, _mat("grate"), Transform3D(Basis.IDENTITY, Vector3(0, -0.25, 0)), body)
	var rim := TorusMesh.new()
	rim.inner_radius = r - 0.12
	rim.outer_radius = r + 0.05
	rim.rings = 40
	rim.ring_segments = 6
	_mesh(rim, _glow(Color("#7fd4ff"), 3.0), Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)), body)
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5           # between the bridges, out of the way
		var post := BoxMesh.new()
		post.size = Vector3(0.18, 3.4, 0.18)
		_mesh(post, _mat("trim"), Transform3D(Basis.IDENTITY, Vector3(cos(a) * (r - 0.3), 1.7, sin(a) * (r - 0.3))), body)
	var crown := TorusMesh.new()
	crown.inner_radius = r - 0.4
	crown.outer_radius = r - 0.2
	crown.rings = 40
	crown.ring_segments = 6
	_mesh(crown, _mat("trim"), Transform3D(Basis.IDENTITY, Vector3(0, 3.4, 0)), body)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#cfeaff")
	lamp.light_energy = 2.0
	lamp.omni_range = 9.0
	lamp.position = Vector3(0, 3.0, 0)
	body.add_child(lamp)


# ------------------------------------------------------------------ the shield

## Across the bay's mouth: you cannot walk out into space, a ship flies straight
## through, and so do bolts both ways. In open air (breathable) it only keeps the
## weather out: you walk through it too.
func _build_shield() -> void:
	var sh := hull.shield()
	if sh.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "BayShield"
	body.set_meta("bolts_pass", true)
	for pc in ([] if open_air else sh.pieces):
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = (pc.size as Vector3) + Vector3(1.6, 0, 0)
		cs.shape = shape
		cs.transform = pc.xf
		body.add_child(cs)
	_root.add_child(body)
	if demo == null or not demo.use_look:
		return
	var mi := MeshInstance3D.new()
	mi.name = "ShieldLook"
	mi.mesh = _curved_shield(sh)
	mi.material_override = LookMaterials.energy_shield(sh.size, Vector3(0, 3, 6))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
	mi.transform = sh.xf


## The shields in the tunnels' roofs and in every floor's ceiling over the walkway
## (StationHull.floor_hatches): no collider (you jump up through one onto the roof
## walk or the floor's roof, and drop back in), only the look. Hatches of one size
## share one mesh and one material (render rules: share materials).
func _build_hatches() -> void:
	if demo == null or not demo.use_look:
		return
	var meshes := {}
	var mats := {}
	var list: Array = []
	for hc in hull.hatches:
		list.append(["Hatch_" + str(hc.tunnel), hc])
	for hc in hull.floor_hatches:
		list.append(["FloorHatch_%s_%d_%d" % [str(hc.tower), int(hc.floor), int(rad_to_deg(float(hc.a)))], hc])
	if not hull.drop_shield.is_empty():
		list.append(["Hatch_drop", hull.drop_shield])   # issue #317: the engine deck's drop hatch, down to the belt
	for e in list:
		var hc: Dictionary = e[1]
		var size: Vector3 = hc.size
		var key := "%.2f/%.2f/%.2f" % [size.x, size.y, size.z]
		if not meshes.has(key):
			var bm := BoxMesh.new()
			bm.size = size
			meshes[key] = bm
			mats[key] = LookMaterials.energy_shield(size, Vector3(0.8, 0, 0.8), Vector3.RIGHT)
		var mi := MeshInstance3D.new()
		mi.name = str(e[0])
		mi.mesh = meshes[key]
		mi.material_override = mats[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mi)
		mi.transform = hc.xf


## The shields round the gaps between floors (StationHull.tubes): no collider (jump
## the railing, jetpack up and step out through one onto the floor's roof), only
## the look: an open cylinder, its rims where it meets the ceiling and the floor
## above.
func _build_tubes() -> void:
	if demo == null or not demo.use_look:
		return
	for tb in hull.tubes:
		var h := float(tb.y1) - float(tb.y0)
		var r := float(tb.r)
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = h
		cm.radial_segments = 48
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.name = "GapShield_%s_%d" % [str(tb.tower), int(tb.floor)]
		mi.mesh = cm
		mi.material_override = LookMaterials.energy_shield(Vector3(r * 2.0, h, r * 2.0), Vector3(0, 0.6, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var c: Vector2 = tb.c
		mi.position = Vector3(c.x, (float(tb.y0) + float(tb.y1)) * 0.5, c.y)
		_root.add_child(mi)


## Issue #603: the shields across the gap round the shaft (StationHull.gap_shields):
## no collider (jump the railing and you drop through, floor after floor; jetpack up
## through the top one onto the roof), only the look, as the tunnels' hatches. Flat
## rings with the moon pit shield's round rim at the railing; every one shares one
## mesh and one material (render rules: share materials).
func _build_gap_shields() -> void:
	if demo == null or not demo.use_look:
		return
	var meshes := {}
	var mats := {}
	for gs in hull.gap_shields:
		var r0 := float(gs.r0)
		var r1 := float(gs.r1)
		var key := "%.2f/%.2f" % [r0, r1]
		if not meshes.has(key):
			meshes[key] = _flat_ring(r0, r1, 48)
			var rim := minf(3.0, r1 * 0.1)
			mats[key] = LookMaterials.energy_shield(Vector3(r1 * 2.0, 0.1, r1 * 2.0), Vector3(rim, 0, rim), Vector3.RIGHT, true)
		var mi := MeshInstance3D.new()
		mi.name = "GapFloorShield_%s_%d_%d" % [str(gs.tower), int(gs.floor), int(float(gs.y))]
		mi.mesh = meshes[key]
		mi.material_override = mats[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var c: Vector2 = gs.c
		mi.position = Vector3(c.x, float(gs.y), c.y)
		_root.add_child(mi)


## A flat ring from r0 to r1 in the x/z plane, facing up (the shield's shader draws
## both faces).
static func _flat_ring(r0: float, r1: float, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n:
		var t0 := TAU * k / n
		var t1 := TAU * (k + 1) / n
		var a0 := Vector3(cos(t0), 0, sin(t0))
		var a1 := Vector3(cos(t1), 0, sin(t1))
		for v: Vector3 in [a0 * r0, a1 * r1, a0 * r1, a0 * r0, a1 * r0, a1 * r1]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v.x, v.z) / (r1 * 2.0) + Vector2(0.5, 0.5))
			st.add_vertex(v)
	return st.commit()


## The shield's curve as a mesh in its own frame (StationHull.shield): the wall's arc
## across the mouth, full height, so the shader's rims sit on its top, bottom and ends.
static func _curved_shield(sh: Dictionary) -> ArrayMesh:
	var r := float(sh.r)
	var half := float(sh.half)
	var size: Vector3 = sh.size
	var mid := r * (1.0 + cos(half)) * 0.5
	var hy := size.y * 0.5
	var n := 32
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n:
		var t0 := -half + 2.0 * half * k / n
		var t1 := -half + 2.0 * half * (k + 1) / n
		var a0 := Vector3(r * cos(t0) - mid, -hy, r * sin(t0))
		var a1 := Vector3(r * cos(t1) - mid, -hy, r * sin(t1))
		var b0 := a0 + Vector3(0, 2.0 * hy, 0)
		var b1 := a1 + Vector3(0, 2.0 * hy, 0)
		var n0 := Vector3(cos(t0), 0, sin(t0))
		var n1 := Vector3(cos(t1), 0, sin(t1))
		for v in [[a0, n0, 0.0], [b0, n0, 1.0], [b1, n1, 1.0], [a0, n0, 0.0], [b1, n1, 1.0], [a1, n1, 0.0]]:
			st.set_normal(v[1])
			st.set_uv(Vector2(float(k) / n, v[2]))
			st.add_vertex(v[0])
	return st.commit()


# ------------------------------------------------------------------ the look

var _mats: Dictionary = {}


func _build_look() -> void:
	var groups := {}
	for p in hull.parts:
		var f := str(p.finish)
		if f == "pad":
			_pad(p)
			continue
		if not groups.has(f):
			groups[f] = []
		groups[f].append(p)
	for f in groups:
		var mi := MeshInstance3D.new()
		mi.name = "Station_" + str(f)
		mi.mesh = _merged(hull.id + "/" + str(f), groups[f])
		mi.material_override = _mat(str(f))
		if f in ["glass", "glass_floor", "glow", "beacon", "lock"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 50.0
		_root.add_child(mi)


func _mat(finish: String) -> Material:
	if _mats.has(finish):
		return _mats[finish]
	var m: Material
	match finish:
		"glass":
			m = RemnantCruiser._glass()
		"glass_floor":
			var g := RemnantCruiser._glass()
			g.albedo_color = Color(0.5, 0.7, 0.85, 0.28)
			g.roughness = 0.12
			m = g
		"glow":
			m = _glow(Color(str(cfg.get("look", {}).get("glow", "#9fdcff"))), 3.0)
		"beacon":
			m = _glow(Color(str(cfg.get("look", {}).get("beacon", "#ff5a3a"))), 6.0)
		"lock":
			m = _glow(Color("#ffb04a"), 2.5)
		_:
			var sm := ShaderMaterial.new()
			sm.shader = SHADER
			sm.set_shader_parameter("finish", FINISHES.get(finish, 0))
			var noise = demo._flat_mats().noise if demo != null and demo.has_method("_flat_mats") else null
			if noise != null:
				sm.set_shader_parameter("noise_tex", noise)
			_tone(sm)
			m = sm
	_mats[finish] = m
	return m


## Issue #876: the station's own "look" block laid over the metal shader's colours
## (hull_color, trim_color, deck_color, wall_color, accent, window_light,
## strip_light, paint as "#rrggbb"; window_energy, screen_energy as numbers): the
## same metal and the same finishes, a sister station's own shade of them. No new
## shader; a station with no look block keeps the shader's own colours.
const LOOK_COLORS := ["hull_color", "trim_color", "deck_color", "wall_color", "accent", "window_light", "strip_light", "paint"]
const LOOK_NUMBERS := ["window_energy", "screen_energy"]


func _tone(sm: ShaderMaterial) -> void:
	var look: Dictionary = cfg.get("look", {})
	for k in LOOK_COLORS:
		if look.has(k):
			sm.set_shader_parameter(k, Color(str(look[k])))
	for k in LOOK_NUMBERS:
		if look.has(k):
			sm.set_shader_parameter(k, float(look[k]))


static func _glow(c: Color, energy: float) -> StandardMaterial3D:
	return RemnantCruiser._emissive(c, energy)


func _door_mat() -> Material:
	if not _mats.has("door"):
		var g := RemnantCruiser._glass()
		g.albedo_color = Color(0.55, 0.85, 1.0, 0.35)
		g.emission_enabled = true
		g.emission = Color("#5fc8ff")
		g.emission_energy_multiplier = 0.6
		_mats["door"] = g
	return _mats["door"]


static func _merged(key: String, list: Array) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var batch := PrimBatch.new()          # issue #693: nothing read back from the GPU
	for p in list:
		batch.add_box(p.size, p.xf)
	var mesh := batch.commit()
	_meshes[key] = mesh
	return mesh


func _pad(p: Dictionary) -> void:
	var m := _mat("pad").duplicate() as ShaderMaterial
	m.set_shader_parameter("plate_half", (p.size as Vector3) * 0.5)
	var mi := _mesh_box(p.size, m, p.xf)
	mi.name = "Station_" + str(p.id)


func _mesh_box(size: Vector3, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _mesh(bm, mat, xf)


func _mesh(mesh: Mesh, mat: Material, xf: Transform3D, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = xf
	(parent if parent != null else _root).add_child(mi)
	return mi


## Lamps round every floor and over its gap, along the tunnels and over the bay's
## deck; off from far away.
func _lights() -> void:
	_inside = Node3D.new()
	_inside.name = "InteriorLights"
	_root.add_child(_inside)
	var list: Array = []
	for t in hull.towers:
		var c: Vector2 = t.c
		for f in t.floors:
			var y := float(f.y)
			var r := float(f.r)
			var rr := hull.gap_r + hull.walk + (r - hull.gap_r - hull.walk) * 0.5
			var n := 6 if r > 50.0 else 5
			# Issue #643: a floor's fill may light it its own way (the favela: dimmer, cooler).
			var lc: Dictionary = (cfg.get("fill", {}).get("floors", {}).get(str(f.id), {}) as Dictionary).get("light", {})
			for k in n:
				var a := TAU * (k + 0.25) / n
				list.append([Vector3(c.x + cos(a) * rr, y + hull.floor_h - 2.5, c.y + sin(a) * rr), str(lc.get("color", "#ffe2b8")),
					float(lc.get("energy", 4.0)), r * 0.7])
			list.append([Vector3(c.x, y + hull.floor_h - 1.5, c.y), "#cfeaff", 3.0, 22.0])
	for tn in hull.tunnels:
		var l := float(tn.length)
		var x := 6.0
		while x < l:
			list.append([(tn.xf as Transform3D) * Vector3(x, hull.tunnel_h - 0.8, 0), "#dbe9ff", 2.0, 12.0])
			x += 16.0
	if not hull.bay.is_empty():
		var bx: Transform3D = hull.bay.xf
		var r := float(hull.bay.r)
		list.append([bx * Vector3(0, float(hull.bay.height) - 4.0, 0), "#e4edff", 9.0, 60.0])
		for k in 4:
			var a := PI * 0.25 + k * PI * 0.5
			list.append([bx * Vector3(cos(a) * r * 0.55, float(hull.bay.height) - 4.0, sin(a) * r * 0.55), "#e4edff", 7.0, 50.0])
	for l in list:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.light_color = Color(str(l[1]))
		o.light_energy = float(l[2])
		o.omni_range = float(l[3])
		o.omni_attenuation = 0.8
		_inside.add_child(o)


# ------------------------------------------------------------------ the label and toasts

func _build_label() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 4
	add_child(_layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color("#9fe8ff"))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	_layer.add_child(_label)


func _process(_dt: float) -> void:
	_smooth_cars()
	if _label == null or demo == null:
		return
	var pilot = demo.get("pilot")
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var flying: bool = pilot != null and pilot.piloting and pilot.atmo.state in [AtmoFlight.State.FLYING, AtmoFlight.State.LIFTOFF]
	var at: Vector3 = frame.origin
	if cam == null or not flying or cam.is_position_behind(at) or aboard(pilot.atmo.position()):
		_label.visible = false
		return
	var d := distance(pilot.atmo.position())
	var text := line("label") % label()
	if can_dock(pilot.atmo.position()):
		text = line("dock_hint") % [text, d / 1000.0]
	else:
		text += "  %.1f km" % (d / 1000.0)
	_label.text = text
	_label.position = cam.unproject_position(at) + Vector2(14, -10)
	_label.visible = true


func _toast(text: String, secs: float) -> void:
	if text == "" or demo == null:
		return
	var gear = demo.get("gear")
	if gear != null and gear.hud != null:
		gear.hud.toast(text, secs)
