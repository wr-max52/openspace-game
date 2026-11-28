class_name FieldWorld
extends Node3D
## Issue #880: an asteroid field at play (the field type; its rocks: FieldRocks).
## Added by the town scene on a field, it runs what the rocks themselves do not:
##
##   - low gravity everywhere on foot (the field's "gravity", m/s/s, as the cruiser's
##     outside), and a jetpack that refuels in the air ("jet_recharge"); your feet
##     stick to the rock under you and you fall toward the nearest big one in
##     reach (the ball's gravity bodies: PlanetSphere.nearest_body)
##   - the drift: clear of every rock's reach and every zone (the deck, a wreck, an
##     outpost) for drift_s seconds, or drift_m metres below the deck, and your
##     ship reels you in: you are put beside it (or by the landing bay if it is not
##     parked out here), with the field's "pulled_back" line
##   - the field jobs on the bar board (content/core/board/bar_board.json, kind
##     "field", its "field_job"): a salvage run (power cells lying in a wreck, carried
##     back to your ship one at a time or all at once), a lost crate (drifting out
##     past the rocks, jetpack to it and carry it to your ship), a stranded pilot
##     (on a far rock, their air running out: reach them, bring them to your ship,
##     fly them home to the dock) and clearing a rock (take any of the field's
##     outposts: Territory front "field"). Each finishes through WorldState.
##     on_field_job and goes back on the board.
##
## What it puts out (cells, the crate, the pilot) is only seen with the look; the
## rules run headless the same (the traces). FieldWorld.goal (static) is the
## pointer's place for the job on (Objective "field").

signal pulled_back                     ## a drifter was reeled in to their ship
signal job_step(job: String, step: String)

const DELIVER_M := 14.0                ## from your ship's middle: close enough to hand it over
const GRAB_M := 3.0                    ## close enough to take a cell, the crate, the pilot

static var goal := {}                  ## { text, at } for the pointer, or {}

var demo
var cfg: Dictionary = {}
var L: Dictionary = {}
var gravity := 4.0
var jet_recharge := 0.9
var jump_m := 3.0                      ## a jump rises this high out here (the same push as at home: 0.6 m in 20 m/s/s)
var drift_s := 7.0
var drift_m := 260.0
var leap_m := 8.0                      ## in the air, the rock you left counts this much further off (PlanetSphere.body_bias)
var stood_on := -1                     ## the rock under your feet when last on one (its gravity body), or -1
var adrift_t := 0.0                    ## seconds clear of every rock and zone
var pulls := 0                         ## times reeled in (traces, tests)
var lines: Dictionary = {}

## The jobs out here: id -> state. salvage { wreck, cells: [{ at, node, taken }], carried, delivered },
## crate { at, node, carried, t }, pilot { at, node, found, aboard, air }, clear { held }.
var jobs := {}
var _small: Array = []                 ## the small rocks' MultiMeshes (tumbling)
var _spin_t := 0.0
var _floated := false


func setup(town_scene) -> void:
	demo = town_scene
	name = "FieldWorld"
	var ground: WorldGround = demo.pilot.ground if demo.pilot != null else null
	if ground == null:
		return
	L = FieldRocks.for_ground(ground)
	cfg = L.get("cfg", {})
	gravity = float(cfg.get("gravity", gravity))
	jet_recharge = float(cfg.get("jet_recharge", jet_recharge))
	jump_m = float(cfg.get("jump_m", jump_m))
	drift_s = float(cfg.get("drift_s", drift_s))
	drift_m = float(cfg.get("drift_m", drift_m))
	leap_m = float(cfg.get("leap_m", leap_m))
	lines = cfg.get("lines", {})


## The rocks drawn (with the look only).
func dress(mats: LookMaterials) -> void:
	if L.is_empty():
		return
	FieldRocks.build_look(self, L, mats, _small)


func line(key: String, fallback: String = "") -> String:
	return str(lines.get(key, fallback))


func _player() -> CharacterBody3D:
	var p = demo._player if demo != null else null
	return p as CharacterBody3D if p != null and is_instance_valid(p) else null


func _sphere() -> PlanetSphere:
	var g: WorldGround = demo.pilot.ground if demo != null and demo.pilot != null else null
	return g.sphere() if g != null else null


func _physics_process(dt: float) -> void:
	var p = _player()
	if p == null or L.is_empty():
		return
	var flying := bool(p.get("piloting"))
	_float(p, not flying)
	_leap(p, flying)
	if not flying and not bool(p.get("is_downed")):
		_drift(p, dt)
	else:
		adrift_t = 0.0
	_run_jobs(p, dt)


## Off a rock's face and in the air, the next rock in reach takes you: the one you
## left counts leap_m further off round you (PlanetSphere.body_bias), so a jump off
## its edge drifts you over to its neighbour instead of curling you back under it.
func _leap(p, flying: bool) -> void:
	var sp := _sphere()
	if sp == null:
		return
	var at: Vector3 = p.global_position
	if flying or p.is_on_floor():
		sp.body_bias = {}
		stood_on = int(sp.nearest_body(at).get("index", -1)) if not flying else -1
		return
	if stood_on >= 0:
		sp.body_bias = { "index": stood_on, "add": leap_m, "at": at, "within": 6.0 }


## Low gravity on foot (and the jetpack refuelling in the air); back to normal
## in the seat, so nothing else out here is changed.
func _float(p, on: bool) -> void:
	if on == _floated and (not on or is_equal_approx(p.space_gravity, gravity)):
		return
	_floated = on
	p.space_gravity = gravity if on else -1.0
	p.space_recharge = jet_recharge if on else -1.0
	p.space_jump = jump_m if on else -1.0


## Is the drifter held by anything: a rock's pull, the deck, a wreck, an outpost?
func held(at: Vector3) -> bool:
	var sp := _sphere()
	if sp == null:
		return true
	return sp.in_zone(at) or not sp.nearest_body(at).is_empty()


func _drift(p, dt: float) -> void:
	var at: Vector3 = p.global_position
	if held(at) and at.y > -drift_m:
		adrift_t = 0.0
		return
	adrift_t += dt
	if adrift_t >= drift_s or at.y <= -drift_m:
		reel_in(p)


## Your ship reels you in: beside it if it is parked out here, else by the bay.
func reel_in(p) -> void:
	adrift_t = 0.0
	stood_on = -1
	if _sphere() != null:
		_sphere().body_bias = {}
	pulls += 1
	var to: Vector3 = demo.town.spawn_pos() + Vector3(0, 0.05, 0)
	var ship := ship_pos()
	if ship != Vector3.INF:
		var sp := _sphere()
		var up := sp.up_at(ship) if sp != null else Vector3.UP
		var side := up.cross(Vector3.FORWARD)
		if side.length() < 0.1:
			side = up.cross(Vector3.RIGHT)
		to = ship + side.normalized() * 7.0 + up * 1.5
	p.global_position = to
	p.align_to_ground(true)
	WorldState.bump("field_reeled_in")
	_toast(line("pulled_back", "You drifted out past the rocks. Your ship reeled you back in."))
	pulled_back.emit()


## Your ship's middle while it is parked out here, or INF (in the seat, or gone).
func ship_pos() -> Vector3:
	var pl: ShipPilot = demo.pilot if demo != null else null
	if pl == null or pl.atmo == null or pl.atmo.state != AtmoFlight.State.PARKED:
		return Vector3.INF
	return pl.atmo.position()


func _toast(text: String) -> void:
	if text == "":
		return
	if demo != null and not demo.pads.is_empty() and demo.pads[0].has_method("toast"):
		demo.pads[0].toast(text, 4.0)
	WorldState.log_event(text)


# ------------------------------------------------------------------ the jobs

## The field jobs taken and not done: board id -> its "field_job" kind.
static func active_jobs() -> Dictionary:
	var out := {}
	for id in WorldState.jobs_taken:
		if str(WorldState.jobs_taken[id]) != "active":
			continue
		var j := WorldState.job(str(id))
		if str(j.get("kind", "")) == "field":
			out[str(id)] = str(j.get("field_job", ""))
	return out


func _run_jobs(p, dt: float) -> void:
	var on := active_jobs()
	for id in jobs.keys():
		if not on.has(id):
			_clear_job(id)
	var g := {}
	for id in on:
		if not jobs.has(id):
			_start_job(id, on[id])
		var st: Dictionary = jobs.get(id, {})
		if st.is_empty():
			continue
		match str(st.kind):
			"salvage":
				_salvage(id, st, p)
			"crate":
				_crate(id, st, p, dt)
			"pilot":
				_pilot(id, st, p, dt)
			"clear":
				_clear_rock(id, st)
		if g.is_empty() and st.has("goal"):
			g = st.goal
	goal = g
	if _small.size() > 0:
		_tumble(dt)


func _start_job(id: String, kind: String) -> void:
	var st := { "kind": kind }
	match kind:
		"salvage":
			if L.wrecks.is_empty():
				return
			var n := WorldState.count("field_salvage_runs")
			var w: Dictionary = L.wrecks[posmod(n, L.wrecks.size())]
			st["wreck"] = str(w.id)
			st["wreck_label"] = str(cfg.get("wreck_names", {}).get(str(w.id), "a wreck"))
			st["cells"] = []
			for c in cfg.get("cells", [[-34, 136, 182], [34, 136, 182]]):
				var at: Vector3 = (w.level as Transform3D) * FieldRocks._v3(c) + (w.level as Transform3D).basis.y * 0.9
				st.cells.append({ "at": at, "node": _thing("cell", at), "taken": false })
			st["carried"] = 0
			st["delivered"] = 0
		"crate":
			var at: Vector3 = L.sites.get("crate", Vector3(300, 30, -300))
			st["home"] = at
			st["at"] = at
			st["node"] = _thing("crate", at)
			st["carried"] = false
			st["t"] = 0.0
		"pilot":
			var at: Vector3 = L.sites.get("pilot", Vector3(1000, 60, -500))
			st["at"] = at
			st["node"] = _thing("pilot", at)
			st["found"] = false
			st["aboard"] = false
			st["air"] = float(cfg.get("pilot_air_s", 300.0))
		"clear":
			st["held"] = Territory.held("field").size()
	jobs[id] = st
	job_step.emit(kind, "start")


func _clear_job(id: String) -> void:
	var st: Dictionary = jobs.get(id, {})
	for k in ["node"]:
		if is_instance_valid(st.get(k)) and st.get(k) is Node:
			(st[k] as Node).queue_free()
	for c in st.get("cells", []):
		if is_instance_valid(c.get("node")) and c.get("node") is Node:
			(c.node as Node).queue_free()
	jobs.erase(id)


## Something out here to fetch: a marker node (a glowing cell, a crate, the pilot
## in an orange suit), seen only with the look.
func _thing(kind: String, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "Field_" + kind
	add_child(n)
	n.global_position = at
	if not bool(demo.get("use_look")):
		return n
	var mats := LookMaterials.new()
	match kind:
		"cell":
			var m := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.22
			c.bottom_radius = 0.22
			c.height = 0.7
			m.mesh = c
			m.material_override = mats.glow(Color(str(cfg.get("look", {}).get("cell", "#7fe0ff"))))
			n.add_child(m)
			var light := OmniLight3D.new()
			light.light_color = Color(str(cfg.get("look", {}).get("cell", "#7fe0ff")))
			light.omni_range = 6.0
			light.light_energy = 1.4
			n.add_child(light)
		"crate":
			var m := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(1.4, 1.0, 1.0)
			m.mesh = b
			m.material_override = mats.painted(Color(str(cfg.get("look", {}).get("crate", "#8a6a3a"))), 0.7, 0.3)
			n.add_child(m)
			var beacon := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.12
			s.height = 0.24
			beacon.mesh = s
			beacon.position = Vector3(0, 0.6, 0)
			beacon.material_override = mats.glow(Color("#ff9a3a"))
			n.add_child(beacon)
			var light := OmniLight3D.new()
			light.light_color = Color("#ff9a3a")
			light.omni_range = 10.0
			light.position = Vector3(0, 0.8, 0)
			n.add_child(light)
		"pilot":
			var body := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.32
			cap.height = 1.75
			body.mesh = cap
			body.position = Vector3(0, 0.9, 0)
			body.material_override = mats.cloth(Color(str(cfg.get("look", {}).get("pilot", "#d8682a"))))
			n.add_child(body)
			var visor := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.2
			s.height = 0.3
			visor.mesh = s
			visor.position = Vector3(0, 1.55, -0.18)
			visor.material_override = mats.glow(Color("#9fd8ff"))
			n.add_child(visor)
			var light := OmniLight3D.new()
			light.light_color = Color("#ffb070")
			light.omni_range = 8.0
			light.position = Vector3(0, 2.2, 0)
			n.add_child(light)
	return n


func _near_ship(p) -> bool:
	var s := ship_pos()
	return s != Vector3.INF and p.global_position.distance_to(s) <= DELIVER_M


func _salvage(id: String, st: Dictionary, p) -> void:
	var at: Vector3 = p.global_position
	var left := 0
	for c in st.cells:
		if c.taken:
			continue
		left += 1
		if at.distance_to(c.at) <= GRAB_M:
			c.taken = true
			st.carried += 1
			left -= 1
			if is_instance_valid(c.node) and c.node is Node:
				(c.node as Node).queue_free()
			_toast(line("cell_taken", "Power cell: %d of %d.") % [int(st.delivered) + int(st.carried), st.cells.size()])
			job_step.emit("salvage", "cell")
	if int(st.carried) > 0 and _near_ship(p):
		st.delivered += st.carried
		st.carried = 0
		job_step.emit("salvage", "aboard")
		if int(st.delivered) >= st.cells.size():
			WorldState.bump("field_salvage_runs")
			_finish(id, "field_salvage", line("salvage_done", "The power cells are stowed in your hold."))
			return
		_toast(line("cells_aboard", "Cells stowed: %d of %d.") % [int(st.delivered), st.cells.size()])
	if left > 0:
		var near: Vector3 = Vector3.INF
		for c in st.cells:
			if not c.taken and (near == Vector3.INF or at.distance_to(c.at) < at.distance_to(near)):
				near = c.at
		st["goal"] = { "text": line("salvage_go", "Salvage: power cells in %s") % str(st.wreck_label), "at": near }
	else:
		st["goal"] = { "text": line("to_ship", "Carry it to your ship"), "at": ship_pos() }


func _crate(id: String, st: Dictionary, p, dt: float) -> void:
	st.t += dt
	if not st.carried:
		# It drifts: a slow loop round where it was lost.
		var h: Vector3 = st.home
		st.at = h + Vector3(sin(st.t * 0.07) * 9.0, sin(st.t * 0.11) * 3.0, cos(st.t * 0.05) * 9.0)
		if is_instance_valid(st.node) and st.node is Node3D:
			(st.node as Node3D).global_position = st.at
			(st.node as Node3D).rotation = Vector3(st.t * 0.2, st.t * 0.13, 0.0)
		if p.global_position.distance_to(st.at) <= GRAB_M:
			st.carried = true
			if is_instance_valid(st.node) and st.node is Node:
				(st.node as Node).queue_free()
			_toast(line("crate_grabbed", "You have the crate. Get it to your ship."))
			job_step.emit("crate", "grabbed")
		st["goal"] = { "text": line("crate_go", "Find the lost crate drifting past the rocks"), "at": st.at }
		return
	if _near_ship(p):
		_finish(id, "field_crate", line("crate_done", "The crate is stowed in your hold."))
		return
	st["goal"] = { "text": line("to_ship", "Carry it to your ship"), "at": ship_pos() }


func _pilot(id: String, st: Dictionary, p, dt: float) -> void:
	if not st.aboard:
		st.air -= dt
		if st.air <= 0.0:
			_fail(id, line("pilot_lost", "The stranded pilot's air ran out."))
			return
	if not st.found:
		if p.global_position.distance_to(st.at) <= GRAB_M + 1.0:
			st.found = true
			if is_instance_valid(st.node) and st.node is Node3D:
				(st.node as Node3D).visible = false
			_toast(line("pilot_found", "The pilot clips onto your tether: %d seconds of air.") % int(st.air))
			job_step.emit("pilot", "found")
		st["goal"] = { "text": line("pilot_go", "Reach the stranded pilot (%d s of air)") % int(st.air), "at": st.at }
		return
	if not st.aboard:
		if _near_ship(p):
			st.aboard = true
			_toast(line("pilot_aboard", "The pilot is aboard. Fly them home to the dock."))
			job_step.emit("pilot", "aboard")
		else:
			st["goal"] = { "text": line("pilot_back", "Get the pilot to your ship (%d s of air)") % int(st.air), "at": ship_pos() }
			return
	# Aboard: home is the ship parked at the dock again.
	var pl: ShipPilot = demo.pilot
	var home := Vector3(pl.home.x, 0.0, pl.home.z)
	var parked := pl.atmo != null and pl.atmo.state == AtmoFlight.State.PARKED
	if parked and pl.atmo.position().distance_to(home) < float(cfg.get("dock_m", 120.0)) and not bool(p.get("piloting")):
		_finish(id, "field_pilot", line("pilot_done", "The pilot is home on the dock."))
		return
	st["goal"] = { "text": line("pilot_home", "Fly the pilot home to the dock"), "at": demo.town.spawn_pos() }


func _clear_rock(id: String, st: Dictionary) -> void:
	if Territory.held("field").size() > int(st.held):
		_finish(id, "field_rock_taken", line("clear_done", "One of the field's rocks is the locals' now."))
		return
	st.held = mini(int(st.held), Territory.held("field").size())
	var best := Vector3.INF
	var p = _player()
	for r in L.rocks:
		if str(r.role) == "outpost" and Territory.owner("station_" + str(r.get("outpost", ""))) != Territory.LOCALS:
			var t := FieldRocks.top_of(r)
			if p != null and (best == Vector3.INF or p.global_position.distance_to(t) < p.global_position.distance_to(best)):
				best = t
	st["goal"] = { "text": line("clear_go", "Take one of the Remnant's outposts in the field"), "at": best }


func _finish(id: String, trigger: String, text: String) -> void:
	_toast(text)
	_clear_job(id)
	WorldState.on_field_job(trigger)


func _fail(id: String, text: String) -> void:
	_toast(text)
	_clear_job(id)
	WorldState.drop_field_job(id)


## The small rocks turn slowly, each about its own axis.
func _tumble(dt: float) -> void:
	_spin_t += dt
	if Engine.get_physics_frames() % 2 != 0:
		return
	for s in _small:
		var mm: MultiMesh = s.mm
		var list: Array = s.list
		for i in list.size():
			var r: Dictionary = list[i]
			var b: Basis = (r.basis as Basis).rotated(r.axis, _spin_t * float(r.spin))
			mm.set_instance_transform(i, Transform3D(b * Basis.from_scale(Vector3.ONE * float(r.r)), r.c))
