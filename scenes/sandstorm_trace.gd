extends SceneTree
## Issue #175 trace (headless, the real town scene with its look): the home
## planet's sandstorm. It starts clear with the next storm a while off; the F11
## button starts one; it builds, holds about a minute at full strength and fades
## back to clear, saying each change on its signal; the light, fog, dust and the
## sand's blowing sheets move with it and come back; a new time of day keeps the
## storm on top; it fades out as you fly up and mostly under a roof; and only the
## sand planet types get storms.
## Writes test_results/sandstorm_trace.txt for tests/test_sandstorm_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/sandstorm_trace.gd

const OUT := "res://test_results/sandstorm_trace.txt"
const DT := 0.25               ## seconds of storm clock a step

var demo
var storm      ## Sandstorm (untyped: the scene's classes need the autoloads)
var lines := PackedStringArray()
var states: Array = []


func _initialize() -> void:
	WorldState.reset()
	GameFlow.reset()
	GameFlow.change_scene = func(_p: String) -> void: pass
	_run()


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])
	print("  ", k, "=", v)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


## What the storm leans on now: the numbers the trace watches.
func fx() -> Dictionary:
	var look = demo.look
	var d := {
		"fog": look.env.fog_density, "sun": look.sun.light_energy, "ambient": look.env.ambient_light_energy,
		"sky_affect": look.env.fog_sky_affect, "exposure": look.env.tonemap_exposure,
		"ambient_sky": look.env.ambient_light_sky_contribution,
		"drift": 1.0, "dust": 0.0, "dust_on": false,
	}
	if storm.sand != null:
		d.drift = float(storm.sand.get_shader_parameter("drift_boost"))
	if demo.dust != null:
		d.dust = demo.dust.storm
		d.dust_on = demo.dust.storm_grains != null and demo.dust.storm_grains.emitting
	return d


## Run the storm's clock until it reaches `want` (or `limit` seconds); the seconds taken.
func run_until(want: String, limit: float) -> float:
	var t := 0.0
	while storm.state != want and t < limit:
		storm.step(DT)
		t += DT
	return t


func _run() -> void:
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false
	demo.with_npcs = false
	demo.with_bar = false
	get_root().add_child(demo)
	await frames(30)
	storm = demo.storm
	out("STORM_BUILT", storm != null)
	if storm == null:
		_write()
		return
	out("PLANET_TYPE", str(demo.planet.get("type", "")))
	out("HOOK_IS_THIS", Sandstorm.current == storm)
	out("STATE_START", storm.state)
	var first: Array = storm.cfg.get("first_s", [0, 0])
	out("FIRST_IN_RANGE", storm.next_s >= float(first[0]) and storm.next_s <= float(first[1]))
	out("HAS_LOOK", storm.look != null)
	out("HAS_DUST", storm.dust != null)
	out("HAS_SAND", storm.sand != null)
	storm.set_process(false)          # the trace runs its clock
	storm.state_changed.connect(func(s): states.append(s))
	var clear := fx()
	out("DUST_LAYERS_CLEAR", demo.dust.storm_grains == null if demo.dust != null else true)

	# ------------------------------------------------------ the F11 button
	var pressed := false
	if demo.dev_settings != null:
		demo.dev_settings._build_tabs()       # the pages are built the first time F11 opens
		demo.dev_settings.refresh()
		for b in demo.dev_settings.find_children("*", "Button", true, false):
			if (b as Button).text == "Start a sandstorm now":
				(b as Button).pressed.emit()
				pressed = true
				break
	if not pressed:
		storm.start_now()
	out("F11_BUTTON", pressed)
	out("STATE_AFTER_BUTTON", storm.state)
	out("HOOK_STATE", Sandstorm.state_now())

	# ------------------------------------------------------------- build-up
	var build_t := run_until("full", 0.0 + float(storm.cfg.get("build_s", 50.0)) * 0.5)
	var mid := fx()
	out("MID_FOG_BETWEEN", mid.fog > clear.fog and mid.fog < float(storm.cfg.look.fog_density))
	out("MID_SUN_DIMMER", mid.sun < clear.sun)
	build_t += run_until("full", 300.0)
	out("BUILD_S", snappedf(build_t, 0.25))
	var full := fx()
	out("FULL_LEVEL", snappedf(storm.level, 0.01))
	out("FULL_FOG", full.fog)
	out("FULL_FOG_THICK", full.fog >= float(storm.cfg.look.fog_density) * 0.99)
	out("FULL_SUN_RATIO", snappedf(full.sun / clear.sun, 0.01))
	out("FULL_AMBIENT_LOWER", full.ambient < clear.ambient)
	out("FULL_SKY_BROWN", full.sky_affect > clear.sky_affect and full.ambient_sky < clear.ambient_sky)
	out("FULL_EXPOSURE_LOWER", full.exposure < clear.exposure)
	out("FULL_DRIFT", snappedf(full.drift, 0.01))
	out("FULL_DUST", snappedf(full.dust, 0.01))
	out("FULL_DUST_ON", full.dust_on)
	out("FULL_GUST_HELD", demo.dust != null and demo.dust.storm > 0.99)

	# A new time of day mid-storm: the storm stays on top of it.
	demo.set_preset("noon")
	out("PRESET_KEEPS_STORM", demo.look.env.fog_density >= float(storm.cfg.look.fog_density) * 0.99)
	demo.set_preset("golden")

	# Flying up: gone by altitude_gone_m; back on the ground: back.
	demo.look.set_view_altitude(float(storm.cfg.get("altitude_gone_m", 450.0)) + 50.0)
	storm.step(DT)
	out("HIGH_SEEN", snappedf(storm.seen, 0.01))
	out("HIGH_FOG_CLEAR", absf(demo.look.env.fog_density - clear.fog) < 0.0001)
	out("HIGH_DUST", snappedf(demo.dust.storm if demo.dust != null else 0.0, 0.01))
	demo.look.set_view_altitude(0.0)
	storm.step(DT)
	out("GROUND_SEEN", snappedf(storm.seen, 0.01))

	# Under a roof: mostly gone, settling over shelter_s.
	var roof: Callable = storm.shelter
	storm.shelter = func() -> bool: return true
	for i in int(ceil(float(storm.cfg.get("shelter_s", 1.5)) / DT)) + 2:
		storm.step(DT)
	out("INDOORS_SEEN", snappedf(storm.seen, 0.01))
	storm.shelter = func() -> bool: return false
	for i in int(ceil(float(storm.cfg.get("shelter_s", 1.5)) / DT)) + 2:
		storm.step(DT)
	out("OUTDOORS_SEEN", snappedf(storm.seen, 0.01))
	storm.shelter = roof
	out("HOOK_FULL", Sandstorm.state_now() == "full" and Sandstorm.level_now() > 0.99)

	# --------------------------------------------------------- full, then fade
	var held: float = storm.in_state_s + run_until("fading", 300.0)
	out("FULL_S", snappedf(held, 0.25))
	var fade_t := run_until("clear", 300.0)
	out("FADE_S", snappedf(fade_t, 0.25))
	var after := fx()
	out("CLEAR_FOG_BACK", absf(after.fog - clear.fog) < 0.00001)
	out("CLEAR_SUN_BACK", absf(after.sun - clear.sun) < 0.001)
	out("CLEAR_AMBIENT_BACK", absf(after.ambient - clear.ambient) < 0.001)
	out("CLEAR_DRIFT_BACK", absf(after.drift - clear.drift) < 0.001)
	out("CLEAR_DUST_OFF", not after.dust_on)
	var every: Array = storm.cfg.get("every_s", [0, 0])
	out("NEXT_IN_RANGE", storm.next_s >= float(every[0]) and storm.next_s <= float(every[1]))
	out("STATES", ",".join(PackedStringArray(states.map(func(s): return str(s)))))
	out("CHANGES", storm.changes)

	# On its own clock: the next storm comes by itself.
	var wait := run_until("building", float(every[1]) + 10.0)
	out("NEXT_CAME_BY_ITSELF", storm.state == "building" and wait > 0.0)

	# ---------------------------------------------------------- planet types
	var types: Dictionary = preload("res://src/systems/dataload/core_content.gd").read_json("res://content/core/planets/types.json").get("types", {})
	var with_storms: Array = []
	for id in types:
		if not Sandstorm.config_for(str(id), types[id]).is_empty():
			with_storms.append(str(id))
	with_storms.sort()
	out("TYPES_WITH_STORMS", ",".join(PackedStringArray(with_storms)))
	_write()


func _write() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("sandstorm_trace: wrote ", OUT)
	quit()
