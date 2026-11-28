class_name GuardBrain
extends RefCounted
## One guard's behavior. Pure and headless-testable, the fighter pattern on foot:
## the director fills in the situation each frame, update() picks an action, and
## the outputs say where to walk, where to face, whether to crouch, where to aim
## and whether to pull the trigger. The body (NpcBody) carries them out with the
## player's own movement code and a real rifle.
##
## What a guard is doing is decided at two levels. The checkpoint (checkpoint.gd)
## decides for the whole gate: calm, attending a challenge, or a fight. The
## director passes that down as patrol() / attend() / engage() / calm(). This
## brain decides how: walk the loop and look around, face the person at the
## gate, or fight from cover in bursts.
##
## States:
##   PATROL   walk the loop, pause and look around at each point
##   ATTEND   stand, face the player, rifle at the ready (a challenge is on);
##            with walk_up set, walk up to the player first
##   COMBAT   cover, hide, wind up, burst, back down; in the open if no cover.
##            Nobody in sight for hunt_after_s (plus up to hunt_stagger_s, rolled
##            for each guard each fight, so a squad comes out of cover one by
##            one): hunt (rifle up, sweeping, walking search points round where
##            the player was), so a trooper on the alarm is always plainly
##            looking for you, even one that never saw you. A hunter who spots
##            you (or is shot) pops out shooting and then chases: he fights in
##            the open and runs at where you were whenever you break sight,
##            rather than going back to cover, until he loses you for his hunt
##            delay and hunts again
##   SEARCH   walk to where the player was last seen or heard and look around
##   RETURN   back to the loop
##
## Every number comes from the soldier profile's "combat" and "patrol" blocks.

enum State { PATROL, ATTEND, COMBAT, SEARCH, RETURN }
enum Fight { TO_COVER, HIDE, WINDUP, BURST, OPEN }

var profile: Dictionary = {}
var state := State.PATROL
var fight := Fight.TO_COVER

## Situation, filled in by the director each frame.
var pos := Vector3.ZERO
var hp_frac := 1.0
var arrived := true
var visible := false              ## the guard can see the player right now
var target_pos := Vector3.INF     ## the player's feet
var target_vel := Vector3.ZERO
var target_chest := 1.25
var last_seen := Vector3.INF
var heard_pos := Vector3.INF
var cover := Vector3.INF          ## the cover spot the director gave us (INF = none)
var reloading := false
var alarm_pos := Vector3.INF      ## M15: where the town alarm last placed the player (shared)
var facing := 0.0                 ## the body's current yaw (radians)
var tilt := Basis.IDENTITY        ## the ground's frame (the body's tilt): facing turns about its up
var post_facing := 0.0            ## the yaw it was posted with
var walk_up := 0.0                ## ATTEND: walk to this far from the player (0 = stand at the post)

## Outputs, read after update().
var go_to := Vector3.INF
var sprint := false
var crouch := false
var face := Vector3.INF
var aim := Vector3.INF
var fire := false
var want_cover := false           ## ask the director for a (new) cover spot
var bark := ""                    ## a line to say this frame ("" = nothing)

## The loop: points to walk, the first is the post.
var patrol_points: Array = []
var _patrol_i := 0
var _pause_left := 0.0
var _look_left := 0.0
var _look_yaw := 0.0

var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _burst_left := 0
var _bursts := 0
var _no_sight := 0.0
var _strafe_left := 0.0
var _strafe_to := Vector3.INF
var _search_left := 0.0
var _hit_pending := false
var _bark_cd := 0.0
var _queued := ""
var _cover_ask_left := 0.0
var _opening := false
var _investigate_left := 0.0
var _investigate_at := Vector3.INF
var _look_base := 0.0
var _walking_up := false
var _hunting := false
var _hunt_after := -1.0           ## this fight's hunt delay (hunt_after_s + its share of hunt_stagger_s)
var _chase := false               ## a hunter who found them: in the open, after them
var _hunt_to := Vector3.INF
var _hunt_wait := 0.0
var _hunt_center := Vector3.INF
var _call_left := 0.0
var _sweep_left := 0.0
var _sweep_yaw := 0.0
var _sweep_base := 0.0


func _init(soldier: Dictionary = {}, rng_seed: int = 1) -> void:
	profile = soldier
	_rng.seed = rng_seed


func c(key: String, fallback: float) -> float:
	return float(profile.get("combat", {}).get(key, fallback))


func pt(key: String, fallback: float) -> float:
	return float(profile.get("patrol", {}).get(key, fallback))


func state_name() -> String:
	if state == State.COMBAT:
		if _hunting:
			return "COMBAT/HUNT"
		return ("COMBAT/CHASE/" if _chase else "COMBAT/") + Fight.keys()[fight]
	return State.keys()[state]


# ------------------------------------------------------------------ orders (from the director)

func patrol() -> void:
	if state == State.PATROL or state == State.RETURN:
		return
	state = State.RETURN


func attend() -> void:
	if state != State.COMBAT:
		state = State.ATTEND


func engage() -> void:
	if state == State.COMBAT:
		return
	state = State.COMBAT
	_bursts = 0
	# Open fire first if they are in sight (the warning was the warning), then run
	# for cover; otherwise straight to cover.
	if visible:
		fight = Fight.WINDUP
		_timer = c("windup_s", 0.35)
		_opening = true
	else:
		fight = Fight.TO_COVER
		want_cover = true
	_no_sight = 0.0
	_hunting = false
	_chase = false
	_hunt_after = c("hunt_after_s", 6.0) + _rng.randf() * c("hunt_stagger_s", 0.0)
	_hunt_to = Vector3.INF
	_sweep_base = facing          # with nowhere to look, it looks round the way it faced (fixed: turning must not drag it round)
	_say("contact", 0.0)


## Hunting: on the alarm, nobody in sight for a while (rifle up, looking).
func hunting() -> bool:
	return state == State.COMBAT and _hunting


## Chasing: a hunter who found them, after them in the open.
func chasing() -> bool:
	return state == State.COMBAT and _chase and not _hunting


## This fight's hunt delay: hunt_after_s plus this guard's share of hunt_stagger_s.
func hunt_delay() -> float:
	if _hunt_after < 0.0:
		_hunt_after = c("hunt_after_s", 6.0) + _rng.randf() * c("hunt_stagger_s", 0.0)
	return _hunt_after


## The fight is over for now: go and look, then go back.
func calm() -> void:
	if state != State.COMBAT and state != State.ATTEND:
		return
	state = State.SEARCH
	_search_left = c("search_s", 10.0)
	_look_base = facing
	_say("lost", 0.0)


## Post it facing `yaw`, and glance around that way while it stands there (a
## merchant at a stall; a fixed post otherwise glances around world +Z).
func set_post_facing(yaw: float) -> void:
	post_facing = yaw
	_look_base = yaw


## Straight back to the loop, no searching (the player was dragged off).
func stand_down() -> void:
	state = State.RETURN
	_say("give_up", 0.0)


func notify_hit() -> void:
	_hit_pending = true


## Something worth a look (footsteps, a shot): a calm guard stops and turns to it.
func investigate(at: Vector3, seconds: float = 2.5) -> void:
	if state != State.PATROL and state != State.RETURN:
		return
	_investigate_at = at
	_investigate_left = seconds


## `p`, pulled back to within `leash` metres of home (the first patrol point).
func _leashed(p: Vector3, leash: float) -> Vector3:
	if patrol_points.is_empty() or leash <= 0.0:
		return p
	var home: Vector3 = patrol_points[0]
	var off := Vector3(p.x - home.x, 0.0, p.z - home.z)
	if off.length() <= leash:
		return p
	var q := home + off.normalized() * leash
	return Vector3(q.x, p.y, q.z)


func _near(p: Vector3, r: float) -> bool:
	return p != Vector3.INF and Vector2(pos.x - p.x, pos.z - p.z).length() <= r


# ------------------------------------------------------------------ per frame

func update(dt: float) -> int:
	fire = false
	want_cover = false if state != State.COMBAT else want_cover
	_bark_cd = maxf(0.0, _bark_cd - dt)
	var hit := _hit_pending
	_hit_pending = false
	match state:
		State.PATROL:
			_patrol(dt)
		State.RETURN:
			crouch = false
			sprint = false
			aim = Vector3.INF
			face = Vector3.INF
			go_to = _patrol_point(0) if patrol_points.size() > 0 else go_to
			if _near(go_to, 1.0):
				state = State.PATROL
				_patrol_i = 0
				_pause_left = pt("pause_s", 4.0)
		State.ATTEND:
			go_to = Vector3.INF
			crouch = false
			sprint = false
			face = target_pos
			aim = Vector3.INF
			# The one asking for papers comes up to you. A little slack before it
			# starts again, so a half step back is not a shuffle.
			if walk_up > 0.0 and target_pos != Vector3.INF:
				_walking_up = not _near(target_pos, walk_up if _walking_up else walk_up + 1.0)
				if _walking_up:
					go_to = _leashed(target_pos, c("attend_leash", 16.0))
			else:
				_walking_up = false
		State.SEARCH:
			_search(dt)
		State.COMBAT:
			_combat(dt, hit)
	# A trooper fights near its post: it will not chase you out across the desert.
	if state == State.COMBAT and go_to != Vector3.INF:
		go_to = _leashed(go_to, c("hold_radius", 0.0) + 0.1 if holds_ground() else c("chase_leash", 30.0))
	# Lines asked for by orders (engage, calm) or this frame, said once.
	bark = _queued
	_queued = ""
	return state


func _patrol(dt: float) -> void:
	crouch = false
	sprint = false
	aim = Vector3.INF
	if _investigate_left > 0.0:
		_investigate_left -= dt
		go_to = Vector3.INF
		face = _investigate_at
		return
	if patrol_points.size() < 2:
		go_to = Vector3.INF
		_look_around(dt)
		return
	if _pause_left > 0.0:
		_pause_left -= dt
		go_to = Vector3.INF
		_look_around(dt)
		if _pause_left <= 0.0:
			_patrol_i = (_patrol_i + 1) % patrol_points.size()
			face = Vector3.INF
		return
	go_to = _patrol_point(_patrol_i)
	face = Vector3.INF
	if _near(go_to, 0.9):
		_pause_left = pt("pause_s", 4.0) * (1.0 if _patrol_i == 0 else 0.5)
		_look_left = 0.0
		_look_base = post_facing if _patrol_i == 0 else facing


func _patrol_point(i: int) -> Vector3:
	return patrol_points[clampi(i, 0, patrol_points.size() - 1)]


## Glance left and right while paused (a still guard reads as a statue).
func _look_around(dt: float) -> void:
	_look_left -= dt
	if _look_left <= 0.0:
		_look_left = pt("look_every_s", 2.5) * _rng.randf_range(0.7, 1.3)
		_look_yaw = deg_to_rad(_rng.randf_range(-1.0, 1.0) * pt("look_around_deg", 55.0))
	var y := _look_base + _look_yaw
	face = pos + Vector3(sin(y), 0.0, cos(y)) * 5.0


func _search(dt: float) -> void:
	crouch = false
	sprint = false
	aim = Vector3.INF
	if holds_ground():
		go_to = Vector3.INF
		_look_around(dt)
		_search_left -= dt
		if _search_left <= 0.0:
			state = State.PATROL
		return
	var where := last_seen if last_seen != Vector3.INF else heard_pos
	# On a leash: look around near the post, do not chase into the desert.
	if where != Vector3.INF and patrol_points.size() > 0:
		var home: Vector3 = patrol_points[0]
		var leash := c("search_leash", 22.0)
		var off := Vector3(where.x - home.x, 0, where.z - home.z)
		if off.length() > leash:
			where = home + off.normalized() * leash
	if visible:
		# Found them again: the director decides whether that is a fight.
		face = target_pos
	if where != Vector3.INF and Vector2(pos.x - where.x, pos.z - where.z).length() > 2.0 and _search_left > c("search_s", 10.0) * 0.4:
		go_to = where
		face = Vector3.INF
	else:
		go_to = Vector3.INF
		_look_around(dt)
	_search_left -= dt
	if _search_left <= 0.0:
		_say("give_up", 0.0)
		state = State.RETURN


## A sentry on a tower never leaves it (profile combat.hold_ground).
func holds_ground() -> bool:
	return bool(profile.get("combat", {}).get("hold_ground", false))


func _combat(dt: float, hit: bool) -> void:
	var threat := target_pos if visible else last_seen
	# The alarm's shared sighting is newer than our own when someone else has eyes on.
	if not visible and alarm_pos != Vector3.INF:
		threat = alarm_pos
	if threat == Vector3.INF:
		threat = heard_pos
	if threat == Vector3.INF:
		# Told to fight with nothing to go on: stand ready where we are, rifle up,
		# looking round for them.
		go_to = Vector3.INF
		crouch = false
		sprint = false
		_sweep(dt, Vector3.INF)
		return
	face = threat
	_no_sight = 0.0 if visible else _no_sight + dt
	if hit and _rng.randf() < 0.5:
		_say("hit", 3.0)
	if _hunting and (visible or hit):
		# There they are: pop out shooting, then after them (not back to cover).
		_hunting = false
		_chase = not holds_ground()
		_hunt_to = Vector3.INF
		_no_sight = 0.0
		fight = Fight.WINDUP
		_timer = c("windup_s", 0.35)
		_opening = true
	elif not _hunting and not visible and _no_sight >= hunt_delay() and not reloading:
		_hunting = true
		_chase = false
		_hunt_to = Vector3.INF
		_hunt_center = Vector3.INF
		_hunt_wait = 0.0
		_call_left = 0.0           # the first call as the hunt starts
	if _hunting:
		_hunt(dt, threat)
		return
	if holds_ground():
		_hold_ground(dt, threat, hit)
		return
	match fight:
		Fight.TO_COVER:
			crouch = false
			aim = Vector3.INF
			if cover == Vector3.INF:
				if not want_cover:
					fight = Fight.OPEN
					_strafe_left = 0.0
				return
			want_cover = false
			go_to = cover
			sprint = true
			face = Vector3.INF if Vector2(pos.x - cover.x, pos.z - cover.z).length() > 2.0 else threat
			if _near(cover, 0.9):
				_hide()
		Fight.HIDE:
			go_to = Vector3.INF
			sprint = false
			crouch = true
			aim = Vector3.INF
			_timer -= dt
			if _timer <= 0.0 and not reloading:
				fight = Fight.WINDUP
				_timer = c("windup_s", 0.35)
		Fight.WINDUP:
			crouch = false
			aim = _aim_at(threat)
			_timer -= dt
			if hit and not _opening:
				_hide()
			elif _timer <= 0.0:
				if visible:
					fight = Fight.BURST
					_burst_left = _rng.randi_range(int(c("burst_min", 3)), int(c("burst_max", 5)))
				elif _no_sight >= c("no_sight_reposition_s", 3.0):
					if _chase:
						# Chasing: after them, not into cover.
						fight = Fight.OPEN
						_strafe_left = 0.0
					else:
						# Nothing to shoot from here: find a spot that covers us from where they were.
						want_cover = true
						fight = Fight.TO_COVER
				elif _opening:
					_after_burst()
				else:
					_hide()
		Fight.BURST:
			crouch = false
			if hit or reloading or not visible:
				_bursts += 1
				_after_burst()
				return
			aim = _aim_at(target_pos)
			fire = true
		Fight.OPEN:
			# No cover to be had: stand, shoot in bursts, sidestep between them.
			crouch = false
			sprint = false
			aim = _aim_at(threat)
			_strafe_left -= dt
			if _strafe_left <= 0.0:
				_strafe_left = c("open_fire_strafe_s", 1.5) * _rng.randf_range(0.8, 1.4)
				var to := (threat - pos)
				to.y = 0.0
				var side := Vector3(-to.z, 0, to.x).normalized() * (2.0 if _rng.randf() < 0.5 else -2.0)
				_strafe_to = pos + side
				_burst_left = _rng.randi_range(int(c("burst_min", 3)), int(c("burst_max", 5)))
			go_to = _strafe_to
			if _chase and visible:
				# After them: far off, close in as it shoots (a step toward them each burst).
				var gap := Vector3(target_pos.x - pos.x, 0.0, target_pos.z - pos.z)
				if gap.length() > c("chase_close_m", 12.0):
					go_to = pos + gap.normalized() * 3.0 + (_strafe_to - pos) * 0.5
			fire = visible and _burst_left > 0 and not reloading
			if not visible and _no_sight > (c("chase_lost_s", 0.8) if _chase else c("no_sight_reposition_s", 3.0)):
				# Close in on where they were (ours, or the alarm's), running.
				go_to = threat
				sprint = true
			if _chase:
				return                     # after them: no stopping for cover
			# Keep asking for cover as we close in: a spot in range may turn up.
			_cover_ask_left -= dt
			if _cover_ask_left <= 0.0:
				_cover_ask_left = 2.0
				want_cover = true
			if cover != Vector3.INF:
				fight = Fight.TO_COVER


## Nobody in sight: look for them. Rifle up and sweeping round where they were;
## a trooper that can move walks search points round that spot (on its leash,
## running to far ones), a sentry steps to its rim facing it. Now and then one
## calls out.
func _hunt(dt: float, threat: Vector3) -> void:
	crouch = false
	sprint = false
	fire = false
	_call_left -= dt
	if _call_left <= 0.0:
		_call_left = c("hunt_call_s", 8.0) * _rng.randf_range(0.8, 1.6)
		_say("hunt", 0.0)
	if holds_ground():
		go_to = Vector3.INF
		var rim := c("hold_radius", 0.0)
		if rim > 0.0 and patrol_points.size() > 0:
			var home: Vector3 = patrol_points[0]
			var to := Vector3(threat.x - home.x, 0.0, threat.z - home.z)
			if to.length() > 0.5:
				var spot := home + to.normalized() * rim
				if not _near(spot, 0.6):
					go_to = spot
		_sweep(dt, threat)
		return
	var radius := c("hunt_radius", 10.0)
	# A fresh sighting somewhere else (someone else has eyes on): search there instead.
	if _hunt_center == Vector3.INF or Vector2(threat.x - _hunt_center.x, threat.z - _hunt_center.z).length() > radius * 1.5:
		_hunt_center = threat
		_hunt_to = Vector3.INF
		_hunt_wait = 0.0
	if _hunt_to == Vector3.INF or (_near(_hunt_to, 1.2) and _hunt_wait <= 0.0):
		if _hunt_to != Vector3.INF:
			# Got there: stand and look a moment before the next spot.
			_hunt_wait = c("hunt_pause_s", 2.0) * _rng.randf_range(0.7, 1.4)
		var ang := _rng.randf() * TAU
		var r := radius * sqrt(_rng.randf())
		_hunt_to = _leashed(_hunt_center + Vector3(cos(ang), 0.0, sin(ang)) * r, c("chase_leash", 30.0))
		if _near(_hunt_to, 1.2):
			_hunt_wait = maxf(_hunt_wait, c("hunt_pause_s", 2.0))   # the end of its leash: look from here
	if _hunt_wait > 0.0:
		_hunt_wait -= dt
		go_to = Vector3.INF
		_sweep(dt, _hunt_center)
	else:
		go_to = _hunt_to
		sprint = not _near(_hunt_to, 15.0)
		if sprint:
			face = Vector3.INF          # running there: rifle at the hip, eyes ahead
			aim = Vector3.INF
		else:
			_sweep(dt, _hunt_to)


## Rifle up at chest height, sweeping left and right of `toward` (or of the way
## it faces): plainly on the lookout.
func _sweep(dt: float, toward: Vector3) -> void:
	_sweep_left -= dt
	if _sweep_left <= 0.0:
		_sweep_left = c("sweep_every_s", 1.4) * _rng.randf_range(0.7, 1.3)
		_sweep_yaw = deg_to_rad(_rng.randf_range(-1.0, 1.0) * c("sweep_deg", 60.0))
	# Issue #838: round the ground's up, so on a tilted deck the sweep stays level
	# with it, not 12 m into the floor or the sky.
	var base := _sweep_base
	var tw := tilt.inverse() * (toward - pos) if toward != Vector3.INF else Vector3.ZERO
	if toward != Vector3.INF and Vector2(tw.x, tw.z).length() > 0.5:
		base = atan2(tw.x, tw.z)
	var y := base + _sweep_yaw
	var p := pos + tilt * (Vector3(sin(y), 0.0, cos(y)) * 12.0)
	face = p
	aim = p + tilt.y * target_chest


## A sentry fights where it stands: duck (if it can), stand, wind up, burst, repeat.
func _hold_ground(dt: float, threat: Vector3, hit: bool) -> void:
	go_to = Vector3.INF
	# Step to the rim facing the threat (profile combat.hold_radius): from the
	# middle of a tower top the roof edge hides the street, both ways.
	var rim := c("hold_radius", 0.0)
	if rim > 0.0 and patrol_points.size() > 0:
		var home: Vector3 = patrol_points[0]
		var to := Vector3(threat.x - home.x, 0.0, threat.z - home.z)
		if to.length() > 0.5:
			var spot := home + to.normalized() * rim
			if not _near(spot, 0.6):
				go_to = spot
	sprint = false
	want_cover = false
	match fight:
		Fight.HIDE:
			crouch = true
			aim = Vector3.INF
			_timer -= dt
			if _timer <= 0.0 and not reloading:
				fight = Fight.WINDUP
				_timer = c("windup_s", 0.35)
		Fight.WINDUP:
			crouch = false
			aim = _aim_at(threat)
			_timer -= dt
			if _timer <= 0.0:
				if visible:
					fight = Fight.BURST
					_burst_left = _rng.randi_range(int(c("burst_min", 3)), int(c("burst_max", 5)))
				else:
					_opening = false
					_hide()
		Fight.BURST:
			crouch = false
			if hit or reloading or not visible:
				_bursts += 1
				_opening = false
				_hide()
				return
			aim = _aim_at(target_pos)
			fire = true
		_:
			# TO_COVER / OPEN make no sense up here.
			fight = Fight.WINDUP
			_timer = c("windup_s", 0.35)


## The body reports each bolt that actually left the rifle.
func on_shot() -> void:
	if _burst_left > 0:
		_burst_left -= 1
	if fight == Fight.BURST and _burst_left <= 0:
		_bursts += 1
		_after_burst()


func _after_burst() -> void:
	if holds_ground():
		_opening = false
		_hide()
		return
	if _chase:
		# Found them while hunting: keep after them in the open, shooting.
		_opening = false
		fight = Fight.OPEN
		_strafe_left = 0.0
	elif _opening:
		_opening = false
		fight = Fight.TO_COVER
		want_cover = true
	else:
		_hide()


func _hide() -> void:
	fight = Fight.HIDE
	var t := _rng.randf_range(c("hide_min_s", 1.2), c("hide_max_s", 2.4))
	if hp_frac < c("low_hp_frac", 0.35):
		t *= c("hide_low_hp_mult", 1.8)
	_timer = t
	if reloading:
		_say("reload", 4.0)


## Where to point the rifle: the target's chest plus a random miss that grows
## with range, with how fast they move, and on the first burst.
func _aim_at(at: Vector3) -> Vector3:
	if at == Vector3.INF:
		return Vector3.INF
	var chest := at + tilt.y * target_chest
	var d := Vector2(chest.x - pos.x, chest.z - pos.z).length()
	var err := deg_to_rad(c("aim_error_deg", 2.2))
	if Vector2(target_vel.x, target_vel.z).length() > 1.0:
		err *= c("aim_error_moving_mult", 1.8)
	if _bursts == 0:
		err *= c("aim_error_first_burst_mult", 1.6)
	var r := tan(err) * d
	var off := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-1.0, 1.0)) * r
	return chest + off


func _say(key: String, cooldown: float) -> void:
	if _bark_cd > 0.0 and cooldown > 0.0:
		return
	_queued = key
	_bark_cd = cooldown
