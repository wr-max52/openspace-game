class_name StagedBuild
extends Node
## An ordered build plan run over several frames (issue #121). A scene lists its
## build as named steps; this runs them in order, a few per frame, inside a
## main-thread budget, so a big scene can appear without one long frozen frame.
##
## Two kinds of step:
##   add(name, call)       -- runs once, start to finish. `call` returns true when
##                            it went well; anything else stops the build (failed).
##                            A step is never cut short, so one that alone takes far
##                            longer than the budget should be split into smaller ones.
##   add_poll(name, call)  -- called once a frame with the ms left in this frame's
##                            budget until it returns true (waiting on a worker
##                            thread, or swapping in finished meshes a few at a time).
##   add_sliced(name, call) -- issue #574: one big build cut into pieces. `call`
##                            gets this StagedBuild and is a coroutine that calls
##                            `await staged.slice()` between its pieces; slice()
##                            waits for the next frame only once this frame's
##                            budget is spent. Under run_all() it never waits, so
##                            the same code builds everything at once.
##
## The first step of a frame always runs, so the build always moves on; the next
## one runs only while the frame is under `budget_ms`. run_all() runs every step
## now instead (a normal arrival: same order, same result, all on one frame).
##
## Issue #693: any step can be given a `when` (hold_until): a Callable that says
## whether its moment has come (the ship could see the outpost, has come down
## to where people are drawn). Reached before then, the step is set aside and
## the build goes on without it; once the rest is done (`done`), the steps set
## aside run, in order, as their moment comes. `settled` is true once nothing is
## left. Nothing after a held step may rely on it. run_all() and release_held()
## never wait for a moment.
##
## Freed with its scene: a build cut off mid-way simply stops. Nothing here knows
## about towns or planets.

signal step_done(step_name: String, ms: float)
signal finished
signal settled_now                    ## issue #693: the steps held for their moment have all run
signal failed(step_name: String)
signal _resume                        ## issue #574: wakes a sliced step for this frame

var budget_ms := 5.0                  ## main-thread ms a frame may spend on steps
var steps: Array = []                 ## { name, call: Callable, poll: bool }
var index := 0                        ## the next step to run
var current := ""                     ## the step running (or polled) now
var done := false
var settled := false                  ## issue #693: done, and no held step is left
var held: Array = []                  ## issue #693: steps set aside till their moment ({ name, call, poll, when })
var trickles: Array = []              ## issue #693: { name, call } builders of places that come into sight later
var _trickle_at := 0
var failed_step := ""                 ## "" = nothing failed
var history: Array = []               ## { name, ms, frame } per finished step, in order
var step_ms := {}                     ## step name -> ms it took (polls: summed over frames)
var frames_used := 0                  ## frames that ran at least one step
var worst_frame_ms := 0.0             ## the most step time spent on one frame
var total_ms := 0.0                   ## step time over the whole build
var shell_ms := 0.0                   ## step time run_now() spent before start()
var started_usec := 0                 ## when start() was called
var finished_usec := 0                ## when the last step finished
var _frame_usec := 0                  ## issue #574: when this frame's step time began
var last_frame_ms := 0.0              ## issue #693: step time spent on the last frame that ran steps
var piece_watch_ms := 0.0             ## issue #693: > 0 (probes): note pieces of sliced steps longer than this
var slow_pieces: Array = []           ## { step, ms, at } the pieces over piece_watch_ms, `at` where they ended
var _piece_usec := 0
var _slicing := false                 ## a sliced step runs under the budget (not run_all)
var _sliced_started := false
var _sliced_done := false


func _init() -> void:
	name = "StagedBuild"
	set_process(false)


func add(step_name: String, fn: Callable) -> void:
	steps.append({ "name": step_name, "call": fn, "poll": false })


func add_poll(step_name: String, fn: Callable) -> void:
	steps.append({ "name": step_name, "call": fn, "poll": true })


func add_sliced(step_name: String, fn: Callable) -> void:
	steps.append({ "name": step_name, "call": fn, "poll": true, "sliced": true })


## Issue #574: between the pieces of a sliced step. Waits for the next frame once
## this frame's budget is spent; otherwise (or outside a staged build) goes on.
func slice() -> void:
	if piece_watch_ms > 0.0 and _slicing:
		_note_piece()
	if not _slicing or (Time.get_ticks_usec() - _frame_usec) / 1000.0 < budget_ms:
		return
	await _resume
	_piece_usec = Time.get_ticks_usec()


## Issue #693: a piece longer than piece_watch_ms, with the line it ended on.
func _note_piece() -> void:
	var now := Time.get_ticks_usec()
	var from := maxi(_piece_usec, _frame_usec)
	var ms := (now - from) / 1000.0
	_piece_usec = now
	if ms < piece_watch_ms:
		return
	var at := ""
	for f in get_stack():
		if not str(f.source).ends_with("staged_build.gd"):
			at = "%s:%d" % [str(f.source).get_file(), int(f.line)]
			break
	slow_pieces.append({ "step": current, "ms": ms, "at": at })


## Issue #714: a sliced step runs under the budget now (slice() can wait a
## frame); false under run_all(), where a step must finish on this frame.
func slicing() -> bool:
	return _slicing


## Issue #574: `sb` may be null (a build outside any staged plan): then never waits.
static func slice_of(sb: StagedBuild) -> void:
	if sb != null:
		await sb.slice()


## Issue #693: the step `step_name` (already added) waits for `when` to say true.
func hold_until(step_name: String, when: Callable) -> void:
	for s in steps:
		if str(s.name) == step_name:
			s["when"] = when


## Issue #693: every held step now, whatever its moment (tests; leaving a planet).
func release_held() -> void:
	for s in held:
		s.erase("when")
	steps.append_array(held)
	held.clear()
	while index < steps.size() and failed_step == "":
		_run_step(INF)
	if done:
		_settle()


## Issue #693: a builder that keeps going after the plan: places that come into
## sight later (an outpost over the horizon). `fn` builds at most one piece and
## returns true when it did. Called once the plan is done, one a frame in turn,
## only while the frame's budget has room; run_all() never calls it (the owner
## builds everything itself on a normal arrival).
func add_trickle(step_name: String, fn: Callable) -> void:
	trickles.append({ "name": step_name, "call": fn })
	if is_inside_tree() and done:
		set_process(true)


## Issue #693: one trickle piece, if the frame has room. True when one was built.
func _run_trickle(budget_left: float) -> bool:
	if trickles.is_empty() or budget_left <= 0.0:
		return false
	for k in trickles.size():
		var t: Dictionary = trickles[(_trickle_at + k) % trickles.size()]
		var fn: Callable = t.call
		if not fn.is_valid():
			continue
		var t0 := Time.get_ticks_usec()
		if bool(fn.call()):
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			history.append({ "name": str(t.name), "ms": ms, "frame": frames_used })
			_trickle_at = (_trickle_at + k + 1) % trickles.size()
			return true
	return false


func remaining() -> int:
	return steps.size() - index


func names() -> PackedStringArray:
	var out := PackedStringArray()
	for s in steps:
		out.append(str(s.name))
	return out


## Run one step right now, outside the plan (the part of a scene that has to be
## there on its first frame), timed like the others. True when it went well.
func run_now(step_name: String, fn: Callable) -> bool:
	var t0 := Time.get_ticks_usec()
	var ok = fn.call() if fn.is_valid() else false
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	shell_ms += ms
	step_ms[step_name] = ms
	history.append({ "name": step_name, "ms": ms, "frame": -1 })
	return ok is bool and ok


## Run the steps across frames from now on (needs to be in the tree).
func start() -> void:
	started_usec = Time.get_ticks_usec()
	done = false
	if index >= steps.size():
		_finish()
		return
	set_process(true)


## Every step now, in order, on this frame (polls are called until they finish:
## only for steps that do finish on their own, like a worker-thread wait).
func run_all() -> void:
	started_usec = Time.get_ticks_usec()
	var t0 := Time.get_ticks_usec()
	while index < steps.size() and failed_step == "":
		_run_step(INF)
	_account_frame((Time.get_ticks_usec() - t0) / 1000.0)
	if failed_step == "":
		_finish()


func _process(_dt: float) -> void:
	run_frame()


## One frame's worth of steps. Returns the ms spent.
func run_frame() -> float:
	if failed_step != "" or (settled and trickles.is_empty()):
		set_process(false)
		return 0.0
	var t0 := Time.get_ticks_usec()
	_frame_usec = t0
	var ran := 0
	if done and index >= steps.size():
		_take_ready_held()
	while index < steps.size() and failed_step == "":
		var used := (Time.get_ticks_usec() - t0) / 1000.0
		if ran > 0 and used >= budget_ms:
			break
		var s: Dictionary = steps[index]
		if _waits(s):
			held.append(s)                # issue #693: not its moment: the rest goes on
			steps.remove_at(index)
			continue
		var finished_step := _run_step(maxf(budget_ms - used, 0.0))
		ran += 1
		if s.poll and not finished_step:
			break                         # still waiting: try again next frame
	if done and index >= steps.size() and failed_step == "":
		var used := (Time.get_ticks_usec() - t0) / 1000.0
		if (ran == 0 or used < budget_ms) and _run_trickle(budget_ms - used if ran > 0 else budget_ms):
			ran += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if ran > 0:
		last_frame_ms = ms
		_account_frame(ms)
	if failed_step != "":
		set_process(false)
	elif index >= steps.size():
		_finish()
	return ms


## Issue #693: a step with a `when` that is not its moment yet (only once that
## step's sliced run has not started: a started one always finishes).
func _waits(s: Dictionary) -> bool:
	if not s.has("when") or (s.get("sliced", false) and _sliced_started):
		return false
	var w: Callable = s.when
	return w.is_valid() and not bool(w.call())


## Issue #693: the first held step whose moment has come goes back in the plan.
func _take_ready_held() -> void:
	for i in held.size():
		var s: Dictionary = held[i]
		var w: Callable = s.get("when", Callable())
		if not w.is_valid() or bool(w.call()):
			s.erase("when")
			held.remove_at(i)
			steps.append(s)
			return


## Runs (or polls once) the step at `index`. True when it is finished.
func _run_step(budget_left: float) -> bool:
	var s: Dictionary = steps[index]
	current = str(s.name)
	var t0 := Time.get_ticks_usec()
	var fn: Callable = s.call
	var ok = false
	if s.get("sliced", false):
		ok = _run_sliced(fn, budget_left)
	elif fn.is_valid():
		ok = fn.call(budget_left) if s.poll else fn.call()
	if s.poll and budget_left == INF and not s.get("sliced", false):
		while _is_false(ok) and fn.is_valid():
			OS.delay_usec(200)        # run_all: wait it out
			ok = fn.call(INF)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	step_ms[current] = float(step_ms.get(current, 0.0)) + ms
	if s.poll and _is_false(ok):
		return false
	if not (ok is bool and ok):
		failed_step = current
		push_warning("StagedBuild: step %s failed; the rest is skipped" % current)
		failed.emit(current)
		return false
	history.append({ "name": current, "ms": float(step_ms[current]), "frame": frames_used })
	index += 1
	step_done.emit(current, float(step_ms[current]))
	return true


## Issue #574: starts the sliced step (it runs until its first wait), or wakes it
## for this frame. True once it has run to the end.
func _run_sliced(fn: Callable, budget_left: float) -> bool:
	if not _sliced_started:
		_sliced_started = true
		_sliced_done = false
		_slicing = budget_left != INF
		if budget_left == INF:
			_frame_usec = Time.get_ticks_usec()
		_drive(fn)
	elif not _sliced_done:
		_resume.emit()
	if _sliced_done:
		_sliced_started = false
		_slicing = false
		return true
	return false


func _drive(fn: Callable) -> void:
	if fn.is_valid():
		await fn.call(self)
	_sliced_done = true


static func _is_false(v) -> bool:
	return v is bool and not v


func _account_frame(ms: float) -> void:
	frames_used += 1
	total_ms += ms
	worst_frame_ms = maxf(worst_frame_ms, ms)


func _finish() -> void:
	current = ""
	if not done:
		done = true
		finished_usec = Time.get_ticks_usec()
		finished.emit()
	if held.is_empty():
		_settle()


func _settle() -> void:
	if trickles.is_empty():
		set_process(false)
	if settled or not held.is_empty():
		return
	settled = true
	settled_now.emit()


## Wall time from start() to the last step (ms), or -1 while running.
func wall_ms() -> float:
	return (finished_usec - started_usec) / 1000.0 if done else -1.0
