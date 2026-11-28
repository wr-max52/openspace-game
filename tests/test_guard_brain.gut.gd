extends GutTest
## One guard's brain (guard_brain.gd, pure): it walks its loop and looks around,
## turns to a noise, attends a challenge, opens fire then runs for cover, hides,
## winds up and fires a burst only with the target in sight, fights in the open
## when there is no cover, searches on a leash, and goes home. Plus the cover
## picker and the player's health.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const DT := 1.0 / 60.0

var prof: Dictionary


func before_each() -> void:
	var cc = CoreScript.new()
	cc.load_from()
	prof = cc.get_soldier("gate_guard")


func _brain() -> GuardBrain:
	var b := GuardBrain.new(prof, 3)
	b.patrol_points = [Vector3(95, 0, 9), Vector3(88, 0, 9), Vector3(88, 0, 11.5)]
	b.pos = Vector3(95, 0, 9)
	return b


## Run the brain, moving `pos` toward go_to at walking pace like a body would.
func _run(b: GuardBrain, seconds: float, speed: float = 3.2) -> void:
	for i in int(seconds * 60.0):
		b.update(DT)
		if b.go_to != Vector3.INF:
			var to := Vector3(b.go_to.x - b.pos.x, 0, b.go_to.z - b.pos.z)
			var step := minf(to.length(), (6.2 if b.sprint else speed) * DT)
			if to.length() > 0.001:
				b.pos += to.normalized() * step
		b.arrived = b.go_to == Vector3.INF or b.pos.distance_to(b.go_to) < 0.6
		if b.fire:
			b.on_shot()


func test_walks_the_loop_and_looks_around() -> void:
	var b := _brain()
	var visited := {}
	var faced := 0
	for i in 60 * 40:
		_run(b, DT)
		for j in b.patrol_points.size():
			if b.pos.distance_to(b.patrol_points[j]) < 1.0:
				visited[j] = true
		if b.go_to == Vector3.INF and b.face != Vector3.INF:
			faced += 1
	assert_eq(visited.size(), 3, "every point on the loop")
	assert_gt(faced, 60, "looks around while paused")
	assert_eq(b.state, GuardBrain.State.PATROL)


func test_turns_to_a_noise() -> void:
	var b := _brain()
	b.investigate(Vector3(100, 0, 20))
	_run(b, 0.5)
	assert_eq(b.face, Vector3(100, 0, 20))
	assert_eq(b.go_to, Vector3.INF, "stops to look")


func test_attends_a_challenge() -> void:
	var b := _brain()
	b.target_pos = Vector3(93, 0, 0)
	b.attend()
	_run(b, 0.2)
	assert_eq(b.state, GuardBrain.State.ATTEND)
	assert_eq(b.face, Vector3(93, 0, 0))
	assert_false(b.fire)
	b.patrol()
	_run(b, 0.2)
	assert_ne(b.state, GuardBrain.State.ATTEND)


func test_lead_walks_up_to_ask() -> void:
	var b := _brain()
	b.target_pos = Vector3(93, 0, 0)
	b.attend()
	b.walk_up = 2.2
	_run(b, 5.0)
	var d := Vector2(b.pos.x - 93.0, b.pos.z).length()
	assert_between(d, 1.5, 2.3, "stops a couple of metres off, not on top of you")
	assert_eq(b.go_to, Vector3.INF)
	assert_eq(b.face, Vector3(93, 0, 0))
	# A half step back: it stays put.
	b.target_pos = Vector3(93, 0, -0.5)
	_run(b, 0.5)
	assert_eq(b.go_to, Vector3.INF)


func test_opens_fire_then_runs_for_cover() -> void:
	var b := _brain()
	b.visible = true
	b.target_pos = Vector3(104, 0, 1)
	b.engage()
	var fired_first := false
	var asked := false
	for i in 60 * 3:
		_run(b, DT)
		if b.fire and not asked:
			fired_first = true
		if b.want_cover:
			asked = true
			b.want_cover = false
			b.cover = Vector3(88.5, 0, 4.8)
	assert_true(fired_first, "the opening burst comes before cover")
	assert_true(asked, "then asks for cover")
	assert_lt(b.pos.distance_to(Vector3(88.5, 0, 4.8)), 1.0, "and gets there")
	assert_true(b.fight == GuardBrain.Fight.HIDE or b.fight == GuardBrain.Fight.WINDUP or b.fight == GuardBrain.Fight.BURST)


func test_hides_low_and_only_fires_with_sight() -> void:
	var b := _brain()
	b.visible = false
	b.target_pos = Vector3(104, 0, 1)
	b.last_seen = Vector3(104, 0, 1)
	b.engage()
	b.want_cover = false
	b.cover = b.pos
	var crouched := false
	var fired := false
	for i in 60 * 4:
		_run(b, DT)
		crouched = crouched or b.crouch
		fired = fired or b.fire
	assert_true(crouched, "ducks behind cover")
	assert_false(fired, "never fires at what it cannot see")
	b.visible = true
	var shots := 0
	for i in 60 * 6:
		_run(b, DT)
		if b.fire:
			shots += 1
	assert_gt(shots, 0, "fires once the target shows")


func test_aim_misses_more_at_range_and_on_the_move() -> void:
	var b := _brain()
	b.pos = Vector3.ZERO
	var spread := func(at: Vector3, vel: Vector3) -> float:
		b.target_vel = vel
		var total := 0.0
		for i in 200:
			var a: Vector3 = b._aim_at(at)
			total += a.distance_to(at + Vector3(0, b.target_chest, 0))
		return total / 200.0
	var near: float = spread.call(Vector3(0, 0, 8), Vector3.ZERO)
	var far: float = spread.call(Vector3(0, 0, 30), Vector3.ZERO)
	var moving: float = spread.call(Vector3(0, 0, 30), Vector3(5, 0, 0))
	assert_gt(far, near, "worse at range")
	assert_gt(moving, far, "worse at a moving target")


func test_no_cover_fights_in_the_open() -> void:
	var b := _brain()
	b.visible = false
	b.target_pos = Vector3(104, 0, 1)
	b.last_seen = Vector3(104, 0, 1)
	b.engage()
	b.want_cover = false
	b.cover = Vector3.INF
	_run(b, 0.2)
	assert_eq(b.fight, GuardBrain.Fight.OPEN)
	b.visible = true
	var fired := false
	for i in 60 * 3:
		_run(b, DT)
		fired = fired or b.fire
	assert_true(fired)


func test_fight_with_nothing_to_go_on_stands_ready() -> void:
	var b := _brain()
	b.engage()
	_run(b, 1.0)
	assert_eq(b.go_to, Vector3.INF)
	assert_false(b.fire)
	assert_ne(b.aim, Vector3.INF, "rifle up, not idling: it is on the alarm")
	var faces := {}
	var start := b.facing
	var widest := 0.0
	for i in 60 * 12:
		_run(b, DT)
		var want := atan2(b.face.x - b.pos.x, b.face.z - b.pos.z)
		b.facing = want               # the body turns to it (worst case: at once)
		faces[snappedf(want, 0.1)] = true
		widest = maxf(widest, absf(angle_difference(start, want)))
	assert_gt(faces.size(), 2, "and looks round for them")
	assert_lt(widest, PI * 0.95, "looking round, not spinning on the spot")


## On the alarm with the player out of sight: after hunt_after_s it hunts (rifle
## up, sweeping, walking search spots round the last sighting, on its leash), and
## the moment it sees them again it is back to the fight.
func test_hunts_when_nobody_is_in_sight() -> void:
	var b := _brain()
	b.visible = false
	b.alarm_pos = Vector3(110, 0, 4)
	b.engage()
	b.want_cover = false
	b.cover = Vector3.INF
	_run(b, b.c("hunt_after_s", 6.0) - 1.0)
	assert_false(b.hunting(), "not straight away")
	var said: Array = []
	var aimed := 0
	var spots := {}
	var farthest := 0.0
	for i in 60 * 25:
		b.want_cover = false
		_run(b, DT)
		if b.bark != "":
			said.append(b.bark)
		if b.aim != Vector3.INF:
			aimed += 1
		if b.go_to != Vector3.INF:
			spots[Vector2i(roundi(b.go_to.x), roundi(b.go_to.z))] = true
		farthest = maxf(farthest, b.pos.distance_to(b.patrol_points[0]))
		assert_false(b.fire, "never fires at nothing")
	assert_true(b.hunting(), "then hunts")
	assert_has(said, "hunt", "and calls it out")
	assert_gt(aimed, 60 * 10, "rifle up most of the time")
	assert_gt(spots.size(), 2, "walking more than one spot")
	assert_lte(farthest, b.c("chase_leash", 30.0) + 0.5, "on its leash")
	b.visible = true
	b.target_pos = b.pos + Vector3(8, 0, 0)
	_run(b, 0.1)
	assert_false(b.hunting(), "seen again: back to the fight")
	var fired := false
	for i in 60 * 2:
		_run(b, DT)
		fired = fired or b.fire
	assert_true(fired)


func test_a_sentry_hunts_from_its_rim() -> void:
	var cc = CoreScript.new()
	cc.load_from()
	var b := GuardBrain.new(cc.get_soldier("tower_sentry"), 5)
	b.patrol_points = [Vector3(91, 12, 16)]
	b.pos = b.patrol_points[0]
	b.visible = false
	b.alarm_pos = Vector3(60, 0, -20)
	b.engage()
	var yaws := {}
	for i in 60 * 16:
		_run(b, DT)
		yaws[snappedf(atan2(b.face.x - b.pos.x, b.face.z - b.pos.z), 0.1)] = true
		assert_lt(Vector2(b.pos.x - 91, b.pos.z - 16).length(), b.c("hold_radius", 2.3) + 0.2, "never leaves the rim")
	assert_true(b.hunting())
	assert_ne(b.aim, Vector3.INF, "rifle up")
	assert_gt(yaws.size(), 2, "sweeping round")


func test_searches_on_a_leash_then_goes_home() -> void:
	var b := _brain()
	b.target_pos = Vector3(104, 0, 1)
	b.engage()
	b.last_seen = Vector3(200, 0, 0)
	b.calm()
	assert_eq(b.state, GuardBrain.State.SEARCH)
	var farthest := 0.0
	for i in 60 * 30:
		_run(b, DT)
		farthest = maxf(farthest, b.pos.distance_to(b.patrol_points[0]))
	assert_lte(farthest, b.c("search_leash", 22.0) + 1.0, "does not chase into the desert")
	assert_eq(b.state, GuardBrain.State.PATROL, "back on the loop")


func test_barks_from_orders_are_not_lost() -> void:
	var b := _brain()
	b.visible = true
	b.engage()
	b.update(DT)
	assert_eq(b.bark, "contact", "the line asked for by engage() comes out on the next update")
	b.update(DT)
	assert_eq(b.bark, "", "once")


# ------------------------------------------------------------------ cover picker

func test_cover_spots_hide_from_the_threat() -> void:
	var boxes := [
		{ "id": "crate", "kind": "cover", "min": [0, 0, 0], "max": [2, 1.1, 2] },
		{ "id": "low", "kind": "cover", "min": [10, 0, 0], "max": [12, 0.5, 2] },
	]
	var spots := CoverPicker.candidates(boxes, Vector3(1, 0, 1), 20.0)
	assert_gt(spots.size(), 4)
	for s in spots:
		assert_eq(s.box, "crate", "a 0.5 m box hides nobody")
	var threat := Vector3(20, 0, 1)
	var i := CoverPicker.pick(Vector3(-5, 0, 1), threat, spots, [], 2.0, 40.0)
	assert_gte(i, 0)
	var p: Vector3 = spots[i].pos
	assert_lt(p.x, 0.0, "the spot is on the far side of the crate from the threat")
	assert_true(CoverPicker.covers(spots[i], threat))
	var j := CoverPicker.pick(Vector3(-5, 0, 1), threat, spots, [p], 2.0, 40.0)
	assert_true(j < 0 or (spots[j].pos as Vector3).distance_to(p) >= 1.2, "a claimed spot is not handed out twice")


func test_segment_rect() -> void:
	var r := [0.0, 0.0, 2.0, 2.0]
	assert_true(CoverPicker.segment_hits_rect(Vector2(-1, 1), Vector2(3, 1), r))
	assert_false(CoverPicker.segment_hits_rect(Vector2(-1, 3), Vector2(3, 3), r))
	assert_true(CoverPicker.segment_hits_rect(Vector2(-1, -1), Vector2(3, 3), r))
	assert_false(CoverPicker.segment_hits_rect(Vector2(-3, 0), Vector2(-1, 0), r))


func test_town_has_cover_at_the_gate() -> void:
	# Issue #237: in both ports, measured from the gate.
	for layout in ["port_square", "port_round"]:
		var t = preload("res://src/systems/world/town_layout.gd").new()
		t.load_town("port_town", layout)
		var gate: Vector3 = t.marker_pos("gate")
		var spots := CoverPicker.candidates(t.boxes(), gate, 28.0)
		var outside := gate + Vector3(11, 0, 0)
		var hiding := 0
		for s in spots:
			if (s.pos as Vector3).x < gate.x - 1.0 and CoverPicker.covers(s, outside):
				hiding += 1
		assert_gte(hiding, 4, "%s: the barricades and walls give the guards somewhere to hide from the desert side" % layout)


# ------------------------------------------------------------------ player health

func test_player_health_regens_and_downs() -> void:
	var body = preload("res://src/systems/player/character_body.gd").new()
	add_child_autofree(body)
	var downs := [0]
	body.downed.connect(func(): downs[0] += 1)
	body.apply_damage(30.0)
	assert_eq(body.health.hp, 70)
	for i in int(60 * 2):
		body._tick_health(DT)
	assert_eq(body.health.hp, 70, "no regen right after a hit")
	for i in int(60 * 6):
		body._tick_health(DT)
	assert_gt(body.health.hp, 90, "comes back after a few quiet seconds")
	body.apply_damage(200.0)
	assert_true(body.is_downed)
	assert_eq(downs[0], 1)
	body.apply_damage(10.0)
	assert_eq(downs[0], 1, "downed once")
	body.revive(2.0)
	assert_false(body.is_downed)
	assert_eq(body.health.hp, body.max_health)
	body.apply_damage(50.0)
	assert_eq(body.health.hp, body.max_health, "a grace period after waking up")


## A squad on the same alarm leaves its cover to hunt one by one: each guard's
## delay is hunt_after_s plus its own share of hunt_stagger_s.
func test_a_squad_comes_out_to_hunt_staggered() -> void:
	var starts: Array = []
	var lo := 0.0
	var hi := 0.0
	for k in 6:
		var b := GuardBrain.new(prof, 11 + k * 7)
		b.patrol_points = [Vector3(95, 0, 9)]
		b.pos = Vector3(95, 0, 9)
		b.visible = false
		b.alarm_pos = Vector3(110, 0, 4)
		b.engage()
		lo = b.c("hunt_after_s", 6.0)
		hi = lo + b.c("hunt_stagger_s", 0.0)
		var t := 0.0
		while t < hi + 2.0 and not b.hunting():
			b.want_cover = false
			b.cover = Vector3.INF
			_run(b, DT)
			t += DT
		assert_true(b.hunting(), "guard %d hunts in the end" % k)
		starts.append(t)
	assert_gt(hi, lo, "the profile staggers them")
	for t in starts:
		assert_between(t, lo - 0.1, hi + 0.1, "between hunt_after_s and that plus hunt_stagger_s")
	assert_gt(starts.max() - starts.min(), 1.5, "not all at once (%s)" % [starts])


## A hunter who spots them pops out shooting, then chases: once they break sight
## it runs at where they were, never back to cover.
func test_a_hunter_who_finds_you_shoots_then_chases() -> void:
	var b := _brain()
	b.visible = false
	b.alarm_pos = Vector3(110, 0, 4)
	b.engage()
	for i in 60 * 30:
		b.want_cover = false
		b.cover = Vector3.INF
		_run(b, DT)
		if b.hunting():
			break
	assert_true(b.hunting(), "hunting first")
	b.visible = true
	b.target_pos = b.pos + Vector3(10, 0, 4)
	var fired := false
	for i in 60 * 2:
		_run(b, DT)
		fired = fired or b.fire
	assert_true(fired, "pops out shooting")
	assert_true(b.chasing(), "and is after them")
	var seen_at: Vector3 = b.target_pos
	b.last_seen = seen_at
	b.alarm_pos = seen_at          # the garrison shares the newest sighting
	b.visible = false
	var asked_cover := false
	var ran := false
	var start := b.pos
	for i in 60 * 3:
		_run(b, DT)
		asked_cover = asked_cover or b.want_cover
		if b.go_to != Vector3.INF and b.sprint and Vector2(b.go_to.x - seen_at.x, b.go_to.z - seen_at.z).length() < 1.0:
			ran = true
	assert_false(asked_cover, "no going back to cover")
	assert_true(ran, "runs at where they were")
	assert_lt(b.pos.distance_to(seen_at), start.distance_to(seen_at) - 2.0, "and closes on it")


## A guard who never hunted (in cover when they appear) still fights from cover:
## the chase is a hunter's.
func test_from_cover_it_still_goes_to_cover() -> void:
	var b := _brain()
	b.visible = true
	b.target_pos = b.pos + Vector3(12, 0, 0)
	b.engage()
	var asked := false
	for i in 60 * 2:
		_run(b, DT)
		asked = asked or b.want_cover
	assert_false(b.chasing())
	assert_true(asked, "after its opening burst it wants cover")
