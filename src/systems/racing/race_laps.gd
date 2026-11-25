class_name RaceLaps
extends RefCounted
## Issue #610: how a lap is counted. Pure: a course's gates (gate 0 is the
## start/finish line, 1..n the checkpoints in order) and each racer's last two
## positions; step() says what they crossed.
##
## A lap counts only through every checkpoint in order and then back over the
## start/finish the right way. The first crossing of the line (off the grid) starts
## lap 1. Crossing a gate backwards counts nothing; a gate out of order counts
## nothing either (the pointer keeps sending you back to the one you missed).
##
## Events: { type, key, gate, off } with type
##   "start"   -- over the line off the grid: lap 1 is on
##   "gate"    -- through the next checkpoint
##   "lap"     -- a lap done (also carries lap: the number done)
##   "finish"  -- the last lap done (after its "lap")
##   "missed"  -- over the line with a checkpoint still to go: no lap
##   "pass"    -- through any gate the right way (the gate flashes for it), even
##                out of order
## `off` is how far off the gate's centre they crossed: 0 dead centre, 1 the edge.

## [{ id, pos, fwd, right, up, half }]: world position, the way through, across, up, half its width.
var gates: Array = []
var laps_total := 2
var racers: Dictionary = {}          ## key -> { next, lap, started, finished }


func _init(course_gates: Array = [], laps: int = 2) -> void:
	gates = course_gates
	laps_total = laps


func add_racer(key) -> void:
	racers[key] = { "next": 0, "lap": 0, "started": false, "finished": false }


func has_racer(key) -> bool:
	return racers.has(key)


## The gate this racer must go through next (0 = the line).
func next_gate(key) -> int:
	return int(racers.get(key, {}).get("next", 0))


func lap(key) -> int:
	return int(racers.get(key, {}).get("lap", 0))


func finished(key) -> bool:
	return bool(racers.get(key, {}).get("finished", false))


## Progress for placings: laps done, then checkpoints passed this lap.
func progress(key) -> int:
	var r: Dictionary = racers.get(key, {})
	if r.is_empty() or not bool(r.started):
		return -1
	var n := int(r.next)
	var through := (gates.size() - 1) if n == 0 else n - 1
	return int(r.lap) * gates.size() + through


## The racer moved from `from` to `to` this frame.
func step(key, from: Vector3, to: Vector3) -> Array:
	var out: Array = []
	if not racers.has(key):
		add_racer(key)
	var r: Dictionary = racers[key]
	if bool(r.finished):
		return out
	for i in gates.size():
		var c := crossing(gates[i], from, to)
		if c.is_empty() or int(c.dir) < 0:
			continue
		out.append({ "type": "pass", "key": key, "gate": i, "off": c.off })
		if i == 0:
			if not bool(r.started):
				r.started = true
				r.next = 1 if gates.size() > 1 else 0
				out.append({ "type": "start", "key": key, "gate": 0, "off": c.off })
			elif int(r.next) == 0:
				r.lap = int(r.lap) + 1
				r.next = 1 if gates.size() > 1 else 0
				out.append({ "type": "lap", "key": key, "gate": 0, "off": c.off, "lap": r.lap })
				if int(r.lap) >= laps_total:
					r.finished = true
					out.append({ "type": "finish", "key": key, "gate": 0, "off": c.off })
			else:
				out.append({ "type": "missed", "key": key, "gate": int(r.next), "off": c.off })
		elif bool(r.started) and i == int(r.next):
			r.next = i + 1 if i + 1 < gates.size() else 0
			out.append({ "type": "gate", "key": key, "gate": i, "off": c.off })
	return out


## Did the segment from -> to cross `gate`? {} if not; else { dir (1 the right
## way, -1 backwards), off (0..1 from the centre) }.
static func crossing(gate: Dictionary, from: Vector3, to: Vector3) -> Dictionary:
	var pos: Vector3 = gate.pos
	var fwd: Vector3 = gate.fwd
	var da := (from - pos).dot(fwd)
	var db := (to - pos).dot(fwd)
	var dir := 0
	if da < 0.0 and db >= 0.0:
		dir = 1
	elif da >= 0.0 and db < 0.0:
		dir = -1
	else:
		return {}
	var t := da / (da - db) if absf(da - db) > 0.00001 else 0.0
	var hit := from + (to - from) * t
	var rel := hit - pos
	var lat := rel.dot(gate.right)
	var h := rel.dot(gate.up)
	var half := float(gate.half)
	if absf(lat) > half or h < -4.0 or h > 10.0:
		return {}
	return { "dir": dir, "off": clampf(absf(lat) / maxf(half, 0.01), 0.0, 1.0) }
