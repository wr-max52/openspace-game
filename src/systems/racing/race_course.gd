class_name RaceCourse
extends Node3D
## Issue #610: a race course from a file (content/core/racing/courses/<id>.json):
## a start/finish line and checkpoint gates round a loop, the grid behind the
## line and the racing line NPC racers follow (#609). One node builds any course;
## nothing about a course is in code.
##
## Every gate is two relay antennas (RelayAntenna, the droid relays' array) with a
## knee-high glowing strip between them that flashes when a racer goes through
## (green for you). The antennas' masts are solid (WorldGround columns) so you
## bump them like any pole; the strip you drive through.
##
## Render rules: gates and markers are built only while the player is within the
## course's draw_m of its middle and dropped once they are well past it, like the
## ranches. Gates share one material per colour and step; no real lights. The
## lap counting (RaceLaps) and the gates' places work with nothing drawn.
##
## The race (#611) gives each racer a key and calls step_racer() with where they
## were and are; the gates flash for it and RaceLaps says what they crossed.

const DIR := "res://content/core/racing/courses/"
const LOOK_PATH := "res://content/look/race_gates.json"
const CHECK_S := 0.5                  ## how often the draw distance is looked at

var demo                              ## town_demo.gd (the player), may be null (tests)
var ground: WorldGround
var course: Dictionary = {}
var id := ""
var gates: Array = []                 ## RaceLaps gates: { id, pos, fwd, right, up, half }
var line: Array = []                  ## the racing line, world points on the ground
var center := Vector3.ZERO
var radius := 0.0
var built := false                    ## gates and markers drawn
var flashes := 0                      ## gate flashes started (tests, traces)

var _gate_roots: Array = []           ## one Node3D per gate (while built)
var _gate_parts: Array = []           ## per gate: { lamps: Array, strip: MeshInstance3D }
var _flash: Dictionary = {}           ## gate index -> { t, you }
var record_label: Label3D             ## issue #618: your best lap here, on the start line's antenna
var _check := 0.0
static var _look: Dictionary = {}
static var _mats: Dictionary = {}


# ------------------------------------------------------------------ data

## Every course file's id.
static func ids() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		var name := f.trim_suffix(".remap")
		if name.ends_with(".json"):
			out.append(name.trim_suffix(".json"))
	out.sort()
	return out


static func load_course(course_id: String) -> Dictionary:
	var f := FileAccess.open(DIR + course_id + ".json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}


## The courses on a world (its "world" id: port_desert).
static func courses_for(world_id: String) -> Array:
	var out: Array = []
	for cid in ids():
		var c := load_course(cid)
		if str(c.get("world", "")) == world_id:
			out.append(c)
	return out


## Where the desert's boulders must keep off: along every racing line and round
## every gate of the world's courses ([Vector2 centre, radius], plateau x,z: the
## DesertLandforms clear circles).
static func clear_circles(world_id: String) -> Array:
	var out: Array = []
	for c in courses_for(world_id):
		var r := float(c.get("clear_m", 14.0))
		for p in c.get("line", []):
			out.append([Vector2(float(p[0]), float(p[1])), r])
		for g in c.get("gates", []):
			out.append([Vector2(float(g.at[0]), float(g.at[1])), float(c.get("gate_width", 26.0)) * 0.5 + r])
	return out


static func look() -> Dictionary:
	if _look.is_empty():
		var f := FileAccess.open(LOOK_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_look = d if d is Dictionary else {}
	return _look


# ------------------------------------------------------------------ setup

func setup(town_demo, world_ground: WorldGround, course_data: Dictionary) -> void:
	demo = town_demo
	ground = world_ground
	course = course_data
	id = str(course.get("id", "course"))
	name = "RaceCourse_" + id
	_place()


## World points, gates and the masts' colliders (no drawing yet).
func _place() -> void:
	line.clear()
	for p in course.get("line", []):
		line.append(to_world(float(p[0]), float(p[1])))
	center = Vector3.ZERO
	for p in line:
		center += p
	if not line.is_empty():
		center /= float(line.size())
	radius = 0.0
	for p in line:
		radius = maxf(radius, p.distance_to(center))
	gates.clear()
	var half := float(course.get("gate_width", 26.0)) * 0.5
	for g in course.get("gates", []):
		var pos := to_world(float(g.at[0]), float(g.at[1]))
		var up := _up(pos)
		var fwd := _flat(_line_dir(pos), up).normalized()
		var right := fwd.cross(up).normalized()
		gates.append({ "id": str(g.get("id", "")), "pos": pos, "fwd": fwd, "right": right, "up": up, "half": half })
	_add_masts()


## A plateau x,z on the ground (on the ball, the sphere's surface there).
func to_world(x: float, z: float) -> Vector3:
	if ground != null:
		var sp := ground.sphere()
		if sp != null:
			return sp.surface_at(x, z)
		if ground.terrain != null:
			return Vector3(x, ground.terrain.height_at(x, z), z)
	return Vector3(x, 0.0, z)


func _up(at: Vector3) -> Vector3:
	return ground.up_at(at) if ground != null and ground.sphere() != null else Vector3.UP


func _flat(v: Vector3, up: Vector3) -> Vector3:
	return v - up * v.dot(up)


## The way the racing line runs past `at`: from the line point before the nearest
## one to the point after it.
func _line_dir(at: Vector3) -> Vector3:
	if line.size() < 2:
		return Vector3.FORWARD
	var best := 0
	var best_d := INF
	for i in line.size():
		var d: float = (line[i] as Vector3).distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = i
	var a: Vector3 = line[(best - 1 + line.size()) % line.size()]
	var b: Vector3 = line[(best + 1) % line.size()]
	return b - a


## Each antenna's mast is a column speeders and ships bump (WorldGround.hit).
func _add_masts() -> void:
	if ground == null:
		return
	var h := float(course.get("antenna_height", 7.0)) + 0.7
	for gi in gates.size():
		var g: Dictionary = gates[gi]
		for side: float in [-1.0, 1.0]:
			var at: Vector3 = (g.pos as Vector3) + (g.right as Vector3) * side * float(g.half)
			at = to_world_near(at)
			var col := { "id": "race_%s_%s_%s" % [id, g.id, "l" if side < 0.0 else "r"], "kind": "race_mast",
				"center": at, "radius": 0.8, "top": at.y + h }
			if ground.sphere() != null:
				col["up"] = _up(at)
				col["h"] = h
			ground.columns.append(col)


## `p` set down on the sand right under it (the terrain itself, not the tops of
## columns or boxes: a mast's own column must not lift it).
func to_world_near(p: Vector3) -> Vector3:
	if ground != null:
		var sp := ground.sphere()
		if sp != null:
			var dir := (p - sp.center).normalized()
			return sp.center + dir * (sp.radius + sp.elevation(dir))
		if ground.terrain != null:
			return Vector3(p.x, ground.terrain.height_at(p.x, p.z), p.z)
	return Vector3(p.x, 0.0, p.z)


# ------------------------------------------------------------------ the race's questions

## A fresh lap counter for a race on this course.
func new_laps() -> RaceLaps:
	return RaceLaps.new(gates, int(course.get("laps", 2)))


func laps_total() -> int:
	return int(course.get("laps", 2))


func label() -> String:
	return str(course.get("label", id))


func gate_pos(i: int) -> Vector3:
	return gates[i].pos if i >= 0 and i < gates.size() else Vector3.INF


## Grid slot `i` (0 is the front left): { pos, yaw } (HoverModel yaw, facing the
## way through the line).
func grid_slot(i: int) -> Dictionary:
	if gates.is_empty():
		return {}
	var gcfg: Dictionary = course.get("grid", {})
	var g: Dictionary = gates[0]
	var row := i / 2
	var side := -1.0 if i % 2 == 0 else 1.0
	var p: Vector3 = (g.pos as Vector3) - (g.fwd as Vector3) * (float(gcfg.get("back_m", 10.0)) + row * float(gcfg.get("row_m", 9.0))) \
		+ (g.right as Vector3) * side * float(gcfg.get("side_m", 4.5))
	return { "pos": to_world_near(p), "yaw": yaw_of(g.fwd, g.up) }


func grid_slots() -> int:
	return int(course.get("grid", {}).get("slots", 4))


## HoverModel's yaw for heading `f` on ground whose up is `up`.
static func yaw_of(f: Vector3, up: Vector3) -> float:
	var local := PlanetSphere.tilt_to(up).inverse() * f
	return atan2(-local.x, -local.z)


## A racer moved from `from` to `to`: what they crossed (RaceLaps events), and
## the gates they went through flash (green for the player).
func step_racer(laps: RaceLaps, key, from: Vector3, to: Vector3, is_player: bool = false) -> Array:
	var ev := laps.step(key, from, to)
	for e in ev:
		if str(e.type) == "pass":
			flash(int(e.gate), is_player)
	return ev


# ------------------------------------------------------------------ flashing

## Gate `i` lights up: `you` green, anyone else bright, then fades back to rest.
func flash(i: int, you: bool = false) -> void:
	if i < 0 or i >= gates.size():
		return
	flashes += 1
	_flash[i] = { "t": 0.0, "you": you }
	_paint(i, "you" if you else "pass", "flash_energy")


## What gate `i` shows now: "rest", "pass", "you" (tests).
func gate_state(i: int) -> String:
	if not _flash.has(i):
		return "rest"
	return "you" if bool(_flash[i].you) else "pass"


func _process(dt: float) -> void:
	_check -= dt
	if _check <= 0.0:
		_check = CHECK_S
		_check_draw()
	if _flash.is_empty():
		return
	var lk := look()
	for i in _flash.keys():
		var f: Dictionary = _flash[i]
		var was := float(f.t)
		f.t = was + dt
		var mid := float(lk.get("mid_s", 0.3))
		if was < mid and float(f.t) >= mid:
			_paint(i, "you" if bool(f.you) else "pass", "mid_energy")
		if float(f.t) >= float(lk.get("flash_s", 1.0)):
			_flash.erase(i)
			_paint(i, "start" if i == 0 else "checkpoint", "rest_energy")


func _paint(i: int, colour: String, energy: String) -> void:
	if not built or i >= _gate_parts.size():
		return
	var parts: Dictionary = _gate_parts[i]
	var lamp := _mat(colour, energy, false)
	for l: MeshInstance3D in parts.lamps:
		l.material_override = lamp
	var strip := _mat(colour, energy, true)
	for st: MeshInstance3D in parts.strips:
		st.material_override = strip


## One material per colour, step and kind for every gate in the world.
static func _mat(colour: String, energy: String, strip: bool) -> StandardMaterial3D:
	var key := "%s/%s/%s" % [colour, energy, strip]
	if _mats.has(key):
		return _mats[key]
	var lk := look()
	var c := Color(str(lk.get(colour, "#ffffff")))
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = float(lk.get(energy, 2.0))
	if strip:
		# Solid glow: a see-through strip vanished into the red sand at dusk. You
		# still drive straight through it (it has no collider).
		m.albedo_color = c.lightened(0.15)
		m.emission_energy_multiplier = float(lk.get(energy, 2.0)) * float(lk.get("strip_glow", 1.4))
	_mats[key] = m
	return m


static func _plain(colour: String) -> StandardMaterial3D:
	var key := "plain/" + colour
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(look().get(colour, "#555555")))
		m.roughness = 0.6
		m.metallic = 0.4 if colour == "steel" else 0.0
		_mats[key] = m
	return _mats[key]


# ------------------------------------------------------------------ drawing

## Built while the player is near the course, dropped once well past it.
func _check_draw() -> void:
	var p := _viewer()
	if p == Vector3.INF:
		return
	var d := p.distance_to(center) - radius
	var draw := float(course.get("draw_m", 1500.0))
	if not built and d < draw:
		build_gates()
	elif built and d > draw + 200.0:
		drop_gates()


func _viewer() -> Vector3:
	if demo != null and "_player" in demo and demo._player != null and is_instance_valid(demo._player):
		return (demo._player as Node3D).global_position
	return Vector3.INF


func build_gates() -> void:
	if built:
		return
	built = true
	var lk := look()
	var h := float(course.get("antenna_height", 7.0))
	for gi in gates.size():
		var g: Dictionary = gates[gi]
		var root := Node3D.new()
		root.name = "Gate_" + str(g.id)
		add_child(root)
		var up: Vector3 = g.up
		var right: Vector3 = g.right
		var fwd := up.cross(right).normalized()
		root.global_transform = Transform3D(Basis(right, up, -fwd), g.pos)
		var rest := "start" if gi == 0 else "checkpoint"
		var mats := { "steel": _plain("steel"), "dark": _plain("dark"), "trim": _plain("trim"),
			"glow": _mat(rest, "rest_energy", false), "beacon": _mat(rest, "rest_energy", false) }
		var lamps: Array = []
		for side: float in [-1.0, 1.0]:
			var x := side * float(g.half)
			lamps.append_array(RelayAntenna.build(root, h, "narrow", mats, Vector3(x, _sand_y(g, x), 0.0), false))
		var strips: Array = [_strip(root, g, _mat(rest, "rest_energy", true))]
		_gate_roots.append(root)
		_gate_parts.append({ "lamps": lamps, "strips": strips })
	for i in _flash:
		_paint(i, "you" if bool(_flash[i].you) else "pass", "flash_energy")
	_build_record()


## Issue #618: a small panel on the start line's left antenna: your best lap.
func _build_record() -> void:
	if _gate_roots.is_empty():
		return
	record_label = Label3D.new()
	record_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	record_label.font_size = 64
	record_label.pixel_size = 0.01
	record_label.outline_size = 12
	record_label.modulate = Color(str(look().get("start", "#ff3b30"))).lightened(0.5)
	var g: Dictionary = gates[0]
	record_label.position = Vector3(-float(g.half), float(course.get("antenna_height", 7.0)) * 0.55, 0.6)
	(_gate_roots[0] as Node3D).add_child(record_label)
	refresh_record()


## The panel shows your best lap now (after a record).
func refresh_record() -> void:
	if record_label == null or not is_instance_valid(record_label):
		return
	var best := float(WorldState.counters.get("race_best_" + id, 0)) / 1000.0
	record_label.text = "%s\nBEST LAP %s" % [label().to_upper(), RaceCrew.clock(best)]


## The beam across a gate: one straight bar from one mast's foot to the other's,
## tilted with the slope between them. Where the sand between rises over that
## line, the whole bar lifts just enough to clear it (it never steps).
func _strip(root: Node3D, g: Dictionary, mat: Material) -> MeshInstance3D:
	var lk := look()
	var sh := float(lk.get("strip_height", 0.45))
	var xl := -float(g.half) + 0.7
	var xr := float(g.half) - 0.7
	var yl := _sand_y(g, xl)
	var yr := _sand_y(g, xr)
	var bulge := 0.0
	var samples := int(lk.get("strip_samples", 12))
	for k in range(1, samples):
		var t := float(k) / float(samples)
		bulge = maxf(bulge, _sand_y(g, lerpf(xl, xr, t)) - lerpf(yl, yr, t))
	var lift := float(lk.get("strip_lift", 0.35)) + bulge
	var dx := xr - xl
	var dy := yr - yl
	var st := RelayAntenna.part(root, RelayAntenna.box(Vector3(sqrt(dx * dx + dy * dy), sh, 0.12)), mat,
		Vector3((xl + xr) * 0.5, (yl + yr) * 0.5 + sh * 0.5 + lift, 0.0), Basis(Vector3(0, 0, 1), atan2(dy, dx)))
	st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return st


## The sand's height `x` metres across gate `g`, in the gate's frame.
func _sand_y(g: Dictionary, x: float) -> float:
	var at: Vector3 = (g.pos as Vector3) + (g.right as Vector3) * x
	return (to_world_near(at) - (g.pos as Vector3)).dot(g.up)


func drop_gates() -> void:
	for r in _gate_roots:
		if is_instance_valid(r):
			r.queue_free()
	_gate_roots.clear()
	_gate_parts.clear()
	record_label = null
	built = false
