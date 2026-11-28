extends Node
## Optional ElevenLabs NPC speech. Text/gameplay are authoritative: missing keys,
## failed requests, and uncached audio are all silent and never block a turn.
## The player supplies their own key in the existing settings panel. Keys are kept
## in user://llm/keys.cfg; generated MP3s stay in user://npc_voice_cache/.
## Scripted (non-AI) lines are recorded into res://assets/audio/voice/ and play
## first, key or no key.
## Issue #164: a profile name is a key in voice_library.json ("man_goofy",
## "robot_male"), a voice picked by description; voice_profiles.json says who uses which.

const LLMConfigScript := preload("res://src/systems/llm/llm_config.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const PROFILES_PATH := "res://content/core/npcs/voice_profiles.json"
const LIBRARY_PATH := "res://content/core/npcs/voice_library.json"
const SETTINGS_PATH := "user://npc_voice_settings.cfg"
const CACHE_DIR := "user://npc_voice_cache"
const BUNDLE_DIR := "res://assets/audio/voice"
const KEY_ID := "elevenlabs"
const API_URL := "https://api.elevenlabs.io/v1/text-to-speech/"
const FALLBACK_MODEL := "eleven_v4"
## Speeder racer comms: what a line over the radio sounds like (the "comms" block).
const SOUNDS_PATH := "res://content/look/npc_sounds.json"
const COMMS_VOICE := "CommsVoicePlayer"
const COMMS_HISS := "CommsHiss"
const COMMS_CLICK := "CommsClick"

var _profiles: Dictionary = {}
var _library: Dictionary = {}      ## voice_library.json "voices": key -> voice
var _speed := 1.0
var _tokens: Dictionary = {}       ## target instance id -> latest utterance token
var _requests: Dictionary = {}     ## target instance id -> HTTPRequest
var _comms: Dictionary = {}        ## npc_sounds.json "comms"
var _comms_hiss: AudioStreamWAV    ## the static under a comms line (made once, looped)
var _comms_click: AudioStreamWAV   ## the squelch at each end of one


func _ready() -> void:
	_load_profiles()
	_load_settings()
	_load_comms()


## This autoload, found at run time. Scripts reach it through here (a preload of
## this file) instead of naming the NpcVoice autoload, so they still compile when
## a headless `-s` trace loads them before the autoloads exist (issue #545: that
## broke every NPC in the CI traces).
static func get_singleton() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"NpcVoice") if tree != null else null


func _load_profiles() -> void:
	_profiles = CoreContent.read_json(PROFILES_PATH)
	_library = CoreContent.read_json(LIBRARY_PATH).get("voices", {})


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_speed = clampf(float(cfg.get_value("voice", "speed", 1.0)), 0.7, 1.2)


func speed() -> float:
	return _speed


func set_speed(value: float) -> bool:
	_speed = clampf(value, 0.7, 1.2)
	var cfg := ConfigFile.new()
	cfg.set_value("voice", "speed", _speed)
	return cfg.save(SETTINGS_PATH) == OK


func api_key() -> String:
	var cfg = LLMConfigScript.new()
	return cfg.api_key(KEY_ID)


func set_api_key(key: String) -> bool:
	var cfg = LLMConfigScript.new()
	return cfg.set_api_key(KEY_ID, key.strip_edges())


## Resolve a stable voice profile for a soldier or dialogue NPC. A supplied
## `voice_profile` always wins; role variants are assigned deterministically.
## `voice_role` picks a pool without giving the NPC a gameplay role (the Odas
## on other planets use "planet_owner").
func profile_for_npc(npc_id: String, npc_data: Dictionary) -> String:
	var explicit := str(npc_data.get("voice_profile", ""))
	if explicit != "":
		return explicit
	var named: Dictionary = _profiles.get("npc_profiles", {})
	if named.has(npc_id):
		return str(named[npc_id])
	var role := str(npc_data.get("voice_role", npc_data.get("role", "")))
	if role == "" and str(npc_data.get("faction", "")) == "imperial_remnant":
		role = "guard"
	var choices: Array = _profiles.get("role_profiles", {}).get(role, [])
	if choices.is_empty():
		return str(_profiles.get("default", "man_casual"))
	return str(choices[posmod(hash(npc_id), choices.size())])


## The library entry for a profile name ({} when it is not in the library).
func voice_for(profile_name: String) -> Dictionary:
	return _library.get(profile_name, {})


static func mood_tags_for(profile: Dictionary, mood: String, shout: bool = false) -> PackedStringArray:
	var tags := PackedStringArray()
	var fixed := str(profile.get("style_tag", ""))
	if fixed != "":
		tags.append(fixed)
	var mood_tags: Dictionary = profile.get("mood_tags", {})
	var tag := str(mood_tags.get(mood.to_lower(), ""))
	if shout:
		tag = "[shouts]"
	if tag != "":
		tags.append(tag)
	return tags


static func speech_text(text: String, tags: PackedStringArray) -> String:
	var parts := PackedStringArray()
	for tag in tags:
		if tag != "":
			parts.append(tag)
	if text.strip_edges() != "":
		parts.append(text.strip_edges())
	return " ".join(parts)


## Keys are written as the HUD writes them: "[E]", "[Shift]", "[LMB]" (T-89's
## tutorial, his welder gift). Said aloud they are the bare key ("E", "Shift"),
## the mouse buttons as words ("left mouse", capital at a sentence's start), so
## the brackets are never sent as an audio tag and the recorded clips, keyed by
## the line as said, still match. Audio tags ("[scared]") are lower case: kept.
## tools/audio/make_voice_lines.py does the same (said()).
static var _keycap: RegEx

static func spoken_keys(text: String) -> String:
	if not text.contains("["):
		return text
	if _keycap == null:
		_keycap = RegEx.create_from_string("\\[(LMB|RMB|Shift|Space|Tab|Enter|Esc|Backspace|F\\d{1,2}|[A-Z0-9])\\]")
	var out := ""
	var at := 0
	for m in _keycap.search_all(text):
		out += text.substr(at, m.get_start() - at)
		var k := m.get_string(1)
		if k == "LMB" or k == "RMB":
			k = ("left" if k == "LMB" else "right") + " mouse"
			var before := out.strip_edges(false, true)
			if before == "" or before.ends_with(".") or before.ends_with("!") or before.ends_with("?"):
				k = k.left(1).to_upper() + k.substr(1)
		out += k
		at = m.get_end()
	return out + text.substr(at)


static func cache_key(text: String, voice_id: String, model_id: String, speed_value: float,
		stability_value: float = 0.55) -> String:
	return "%s|%s|%s|%.2f|%.2f" % [
		text, voice_id, model_id, clampf(speed_value, 0.7, 1.2), clampf(stability_value, 0.0, 1.0)
	]


static func build_payload(text: String, voice: Dictionary, model_id: String,
		speed_value: float, mood_map: Dictionary, mood: String, shout: bool = false) -> Dictionary:
	var tags := mood_tags_for({
		"style_tag": voice.get("style_tag", ""),
		"mood_tags": mood_map
	}, mood, shout)
	return {
		"text": speech_text(text, tags),
		"model_id": model_id,
		"voice_settings": {
			"speed": clampf(speed_value, 0.7, 1.2),
			"stability": clampf(float(voice.get("stability", 0.55)), 0.0, 1.0),
			"similarity_boost": 0.75
		}
	}


## The scripted line recorded into the repo for this voice (tools/audio/
## make_voice_lines.py), so non-AI lines are voiced with no key. It may not exist:
## lines with a runtime fill are never recorded ahead.
static func bundled_path(text: String, voice_id: String) -> String:
	return BUNDLE_DIR.path_join(("%s|%s" % [text.strip_edges(), voice_id]).sha256_text().left(16) + ".mp3")


## `live_line`: a fresh LLM line, spoken at the player's speed setting. Canned
## lines (barks, menus, the tutorial) always render at normal speed so their
## cached clips survive a change of the speed slider and are generated once.
## `near`: heard at full volume however far off the speaker is (still from
## their side), as if the player stood beside them.
## `radio`: over the comms (the speeder racers once a race is on): heard flat at
## full volume wherever they are, band-passed and crunched on the comms bus, with
## static under it and a squelch at each end (npc_sounds.json "comms").
func speak(text: String, profile_name: String, mood: String, target: Node3D, shout: bool = false,
		live_line: bool = false, near: bool = false, radio: bool = false) -> void:
	text = spoken_keys(text)
	if text.strip_edges() == "" or target == null or not is_instance_valid(target):
		return
	# Avoid accidental web requests from headless tests and server processes.
	if DisplayServer.get_name() == "headless":
		return
	var v := voice_for(profile_name)
	var voice_id := str(v.get("voice_id", ""))
	if voice_id == "":
		return
	var bundled := bundled_path(text, voice_id)
	if ResourceLoader.exists(bundled):
		stop(target)
		_play_stream(target, load(bundled) as AudioStream, near, radio)
		return

	var mood_map: Dictionary = _profiles.get("mood_tags", {})
	var model_id := str(_profiles.get("model_id", FALLBACK_MODEL))
	var speed_value := _speed if live_line else 1.0
	var payload := build_payload(text, v, model_id, speed_value, mood_map, mood, shout)
	var spoken_text := str(payload.text)
	var key := cache_key(spoken_text, voice_id, model_id, speed_value, float(v.get("stability", 0.55)))
	var cache_path := CACHE_DIR.path_join(key.sha256_text() + ".mp3")
	var target_id := target.get_instance_id()
	stop(target)
	var token := int(_tokens.get(target_id, 0))

	if FileAccess.file_exists(cache_path):
		_play_bytes(target, FileAccess.get_file_as_bytes(cache_path), near, radio)
		return
	var key_value := api_key()
	if key_value == "":
		return

	var request := HTTPRequest.new()
	request.timeout = 45.0
	add_child(request)
	_requests[target_id] = request
	request.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			_request_finished(target, target_id, token, cache_path, request, result, response_code, body, near, radio)
	)
	var headers := PackedStringArray([
		"xi-api-key: " + key_value,
		"Content-Type: application/json"
	])
	var url := API_URL + voice_id + "?output_format=mp3_44100_128"
	if request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload)) != OK:
		_requests.erase(target_id)
		request.queue_free()


func stop(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_id := target.get_instance_id()
	_tokens[target_id] = int(_tokens.get(target_id, 0)) + 1
	var request: HTTPRequest = _requests.get(target_id)
	if request != null and is_instance_valid(request):
		request.cancel_request()
		request.queue_free()
	_requests.erase(target_id)
	var player := target.get_node_or_null("ElevenLabsVoicePlayer") as AudioStreamPlayer3D
	if player != null:
		player.stop()
	for n in [COMMS_VOICE, COMMS_HISS]:
		var p := target.get_node_or_null(NodePath(n)) as AudioStreamPlayer
		if p != null:
			p.stop()


func _request_finished(target: Node3D, target_id: int, token: int, cache_path: String,
		request: HTTPRequest, result: int, response_code: int, body: PackedByteArray, near: bool = false,
		radio: bool = false) -> void:
	if _requests.get(target_id) == request:
		_requests.erase(target_id)
	if is_instance_valid(request):
		request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or body.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var file := FileAccess.open(cache_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(body)
	file.close()
	if not is_instance_valid(target) or int(_tokens.get(target_id, 0)) != token:
		return
	_play_bytes(target, body, near, radio)


func _play_bytes(target: Node3D, bytes: PackedByteArray, near: bool = false, radio: bool = false) -> void:
	if bytes.is_empty() or target == null or not is_instance_valid(target):
		return
	_play_stream(target, AudioStreamMP3.load_from_buffer(bytes), near, radio)


func _play_stream(target: Node3D, stream: AudioStream, near: bool = false, radio: bool = false) -> void:
	if stream == null or target == null or not is_instance_valid(target):
		return
	if radio:
		_play_comms(target, stream)
		return
	var player := target.get_node_or_null("ElevenLabsVoicePlayer") as AudioStreamPlayer3D
	if player == null:
		player = AudioStreamPlayer3D.new()
		player.name = "ElevenLabsVoicePlayer"
		player.position = Vector3(0.0, 1.4, 0.0)
		player.volume_db = -3.0
		player.unit_size = 8.0
		player.bus = "SFX"
		target.add_child(player)
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED if near else AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.max_distance = 0.0 if near else 55.0
	player.stream = stream
	player.play()


# ------------------------------------------------------------------ comms

func _load_comms() -> void:
	_comms = CoreContent.read_json(SOUNDS_PATH).get("comms", {})
	ensure_comms_bus(_comms)
	var sr := int(_comms.get("mix_rate", 22050))
	_comms_hiss = noise_wav(float(_comms.get("hiss_s", 1.5)), sr, float(_comms.get("crackle", 6.0)), 0.0, 1)
	_comms_click = noise_wav(float(_comms.get("click_s", 0.12)), sr, 0.0, float(_comms.get("click_decay", 30.0)), 2)


## The comms bus (made once, if the bus layout does not have it): cut below
## high_pass_hz, overdriven, cut above low_pass_hz, so a voice reads as a cheap
## helmet radio. Sends to the SFX bus so the SFX slider covers it.
static func ensure_comms_bus(cfg: Dictionary) -> int:
	var bus := str(cfg.get("bus", "Comms"))
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		return i
	AudioServer.add_bus()
	i = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus)
	AudioServer.set_bus_send(i, str(cfg.get("send", "SFX")))
	AudioServer.set_bus_volume_db(i, float(cfg.get("bus_db", 0.0)))
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = float(cfg.get("high_pass_hz", 450.0))
	hp.db = AudioEffectFilter.FILTER_24DB
	AudioServer.add_bus_effect(i, hp)
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
	dist.drive = clampf(float(cfg.get("drive", 0.5)), 0.0, 1.0)
	dist.pre_gain = float(cfg.get("pre_gain_db", 6.0))
	dist.post_gain = float(cfg.get("post_gain_db", -6.0))
	AudioServer.add_bus_effect(i, dist)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = float(cfg.get("low_pass_hz", 3000.0))
	lp.db = AudioEffectFilter.FILTER_24DB
	AudioServer.add_bus_effect(i, lp)
	return i


## Noise as a 16-bit mono clip: `crackle` pops a second over a hiss, looped
## (decay 0), or a burst that dies away at `decay` per second (the squelch).
static func noise_wav(seconds: float, mix_rate: int, crackle: float, decay: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := maxi(1, int(seconds * mix_rate))
	var data := PackedByteArray()
	data.resize(n * 2)
	var pop := 0.0
	for k in n:
		var t := float(k) / mix_rate
		var v := rng.randf_range(-1.0, 1.0) * (0.35 if decay <= 0.0 else exp(-t * decay))
		if crackle > 0.0 and rng.randf() < crackle / mix_rate:
			pop = rng.randf_range(0.5, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		v += pop
		pop *= 0.82
		data.encode_s16(k * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = mix_rate
	w.stereo = false
	w.data = data
	if decay <= 0.0:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = n
	return w


## A line over the comms: a squelch, the voice with static under it, a squelch.
func _play_comms(target: Node3D, stream: AudioStream) -> void:
	var bus := str(_comms.get("bus", "Comms"))
	var voice := _comms_player(target, COMMS_VOICE, bus, float(_comms.get("voice_db", 0.0)))
	var hiss := _comms_player(target, COMMS_HISS, bus, float(_comms.get("hiss_db", -24.0)))
	var click := _comms_player(target, COMMS_CLICK, bus, float(_comms.get("click_db", -10.0)))
	if not voice.finished.is_connected(_comms_done):
		voice.finished.connect(_comms_done.bind(hiss, click))
	voice.stream = stream
	hiss.stream = _comms_hiss
	click.stream = _comms_click
	click.play()
	hiss.play()
	voice.play()


func _comms_done(hiss: AudioStreamPlayer, click: AudioStreamPlayer) -> void:
	if is_instance_valid(hiss):
		hiss.stop()
	if is_instance_valid(click):
		click.play()


func _comms_player(target: Node3D, node_name: String, bus: String, volume: float) -> AudioStreamPlayer:
	var p := target.get_node_or_null(NodePath(node_name)) as AudioStreamPlayer
	if p == null:
		p = AudioStreamPlayer.new()
		p.name = node_name
		target.add_child(p)
	p.bus = bus
	p.volume_db = volume
	return p
