class_name Sandstorm
extends Node
## Planet-wide sandstorms (issue #175). Now and then a storm builds slowly (the
## wind picks up, the sky dims and browns, the air thickens), blows at full
## strength for about a minute, then dies down. It covers the whole planet: the
## look follows the camera wherever it is on the ground, so the player is in it
## anywhere. It is a ground thing: it fades out as you fly up, like the dust's
## weather tier, and mostly under a roof.
##
## Cheap on purpose: no new geometry or pass. It leans on what is there:
##   LookEnvironment.set_storm   sun, ambient, fog and grade (no sky radiance rebuild)
##   DustWind.set_storm          gusts held up, plus its storm grains and puffs
##   the sand shader's drift_boost   the blowing sheets on the ground turned up
##
## Hooks for later (the native packs hiding, #96): `state_changed`, `state`,
## `level`, and the static Sandstorm.state_now() / level_now() for anyone without
## the node. States: "clear", "building", "full", "fading".
##
## Numbers: content/look/world.json "storm"; a planet type may change any of it in
## types.json (types.<type>.storm). Only the types in on_types get storms.

signal state_changed(state: String)

const CoreContent := preload("res://src/systems/dataload/core_content.gd")

const LOOK_PATH := "res://content/look/world.json"
const CLEAR := "clear"
const BUILDING := "building"
const FULL := "full"
const FADING := "fading"

static var current: Sandstorm = null    ## the storm system of the planet you are on, or null

var cfg: Dictionary = {}
var state := CLEAR
var ramp := 0.0              ## 0..1, linear through building and fading
var level := 0.0             ## 0..1, the storm's strength over time (eased ramp; read by other systems)
var seen := 0.0              ## level after height and shelter: what is drawn now
var in_state_s := 0.0        ## seconds in this state
var next_s := 0.0            ## seconds until the next storm starts (while clear)
var changes := 0             ## state changes so far (traces)
var look: LookEnvironment
var dust: DustWind
var sand: ShaderMaterial
var shelter: Callable = Callable()   ## () -> bool: under a roof (town_demo.indoors)
var _sheltered := 0.0        ## 0..1, eased toward 1 under a roof
var _shelter_poll := 0.0
var _shelter_want := 0.0
var _drawn := -1.0           ## the `seen` last pushed to the look
var _sand_base := 1.0
var _rng := RandomNumberGenerator.new()


## The storm settings for a planet type (world.json "storm" with the type's own
## "storm" laid over it), or {} when that type gets no storms.
static func config_for(type_id: String, type_cfg: Dictionary = {}) -> Dictionary:
	var base: Dictionary = CoreContent.read_json(LOOK_PATH).get("storm", {}).duplicate(true)
	var over: Dictionary = type_cfg.get("storm", {})
	for k in over:
		if base.get(k) is Dictionary and over[k] is Dictionary:
			var merged: Dictionary = base[k].duplicate(true)
			merged.merge(over[k], true)
			base[k] = merged
		else:
			base[k] = over[k]
	if base.is_empty() or not bool(base.get("enabled", true)):
		return {}
	if not (base.get("on_types", []) as Array).has(type_id) and not over.has("enabled"):
		return {}
	return base


static func state_now() -> String:
	return current.state if current != null and is_instance_valid(current) else CLEAR


static func level_now() -> float:
	return current.level if current != null and is_instance_valid(current) else 0.0


func _init() -> void:
	name = "Sandstorm"


func setup(c: Dictionary, seed_value: int = 0) -> void:
	cfg = c
	_rng.seed = seed_value if seed_value != 0 else int(Time.get_ticks_usec())
	next_s = _pick("first_s", 300.0)


## What the storm draws on (any may be null): the look, the dust, the ground's sand.
func attach(look_env: LookEnvironment, dust_wind: DustWind, sand_mat: ShaderMaterial) -> void:
	look = look_env
	dust = dust_wind
	sand = sand_mat
	if sand != null:
		var b = sand.get_shader_parameter("drift_boost")
		_sand_base = float(b) if b != null else 1.0
	_drawn = -1.0
	_draw()


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null
	if look != null and is_instance_valid(look):
		look.set_storm(0.0, {})


## Start a storm now (F11 > Game), from wherever it is: clear builds from nothing,
## a fading storm builds back up from where it got to, a storm already up carries on.
func start_now() -> void:
	if state == CLEAR or state == FADING:
		_set_state(BUILDING)


## End it now: fade out from wherever it is.
func stop_now() -> void:
	if state == BUILDING or state == FULL:
		_set_state(FADING)


func _process(dt: float) -> void:
	step(dt)


## One tick of the storm's clock (game seconds). Public so a trace can run it fast.
func step(dt: float) -> void:
	in_state_s += dt
	match state:
		CLEAR:
			next_s -= dt
			if next_s <= 0.0:
				_set_state(BUILDING)
		BUILDING:
			ramp = minf(1.0, ramp + dt / maxf(0.1, float(cfg.get("build_s", 50.0))))
			if ramp >= 1.0:
				_set_state(FULL)
		FULL:
			if in_state_s >= float(cfg.get("full_s", 60.0)):
				_set_state(FADING)
		FADING:
			ramp = maxf(0.0, ramp - dt / maxf(0.1, float(cfg.get("fade_s", 40.0))))
			if ramp <= 0.0:
				next_s = _pick("every_s", 1200.0)
				_set_state(CLEAR)
	level = smoothstep(0.0, 1.0, ramp)
	_step_shelter(dt)
	seen = level * height_share() * (1.0 - _sheltered * (1.0 - float(cfg.get("indoors", 0.15))))
	_draw()


## 1 on the ground, 0 once flown up past altitude_gone_m (or on the way to space).
func height_share() -> float:
	if look == null or not is_instance_valid(look):
		return 1.0
	var alt := look.view_altitude
	var k := 1.0 - smoothstep(float(cfg.get("altitude_full_m", 120.0)), float(cfg.get("altitude_gone_m", 450.0)), alt)
	return k * (1.0 - look.space_level)


func _step_shelter(dt: float) -> void:
	_shelter_poll -= dt
	var want := 0.0
	if shelter.is_valid() and level > 0.0:
		if _shelter_poll <= 0.0:
			_shelter_poll = 0.25           # town_demo's indoors check, four times a second
			_shelter_want = 1.0 if bool(shelter.call()) else 0.0
		want = _shelter_want
	_sheltered = move_toward(_sheltered, want, dt / maxf(0.05, float(cfg.get("shelter_s", 1.5))))



func _draw() -> void:
	# Pushed only when it moves enough to see: the build-up is ~50 s, so this is a
	# few hundred small writes a storm, and none at all in clear weather.
	if absf(seen - _drawn) < 0.002 and not (seen == 0.0 and _drawn != 0.0):
		return
	_drawn = seen
	if look != null and is_instance_valid(look):
		look.set_storm(seen, cfg.get("look", {}))
	if dust != null and is_instance_valid(dust):
		dust.set_storm(seen, cfg.get("dust", {}))
	if sand != null:
		sand.set_shader_parameter("drift_boost", lerpf(_sand_base, _sand_base * float(cfg.get("sand", {}).get("drift_boost", 1.0)), seen))


func _set_state(s: String) -> void:
	if s == state:
		return
	state = s
	in_state_s = 0.0
	changes += 1
	state_changed.emit(s)


func _pick(key: String, fallback: float) -> float:
	var v = cfg.get(key, fallback)
	if v is Array and (v as Array).size() >= 2:
		return _rng.randf_range(float(v[0]), float(v[1]))
	return float(v)
