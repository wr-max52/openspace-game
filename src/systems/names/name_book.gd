class_name NameBook
extends RefCounted
## Every name given out in this game (issue #15). Lives in WorldState, so it is
## saved with the game and survives scene changes.
##
## Things are named by a stable key ("npc:port_town/trooper_gate_n",
## "pilot:orbital_skirmish/w0/2", "planet:port_desert"). Asking again for the same
## key gives the same name back. A new key gets a fresh name from NameEngine,
## seeded from (world seed, kind, key), checked against every name already in the
## book (and the authored ones, reserved at start), and only then written in. On a
## clash it tries the next seed, so the result is still the same every time the
## same things are named in the same order.
##
## Issue #834: two seeds. Places and gear (config `fixed_kinds`: towns, planets,
## moons, stars, equipment, makers) use `world_seed`, the same in every game and on
## every machine. Everything else (people, callsigns, vessels) uses `game_seed`,
## rolled fresh for each new game (`fresh()`) and saved with it. A fixed name only
## yields to other fixed or authored names: if a person already holds the name a
## place wants, the place keeps it and the person is named again, so a place's name
## never depends on who was named first.

const NAMES_DIR := "res://content/core/names"
const MANIFEST := "res://content/core/manifest.json"
const IP_LIST := "res://content/core/llm/ip_blocklist.json"

static var _shared_engine: NameEngine

var world_seed := 0
var game_seed := 0                ## issue #834: people, callsigns and vessels; new each game
var fixed_kinds: Dictionary = {}  ## kind -> true: named from world_seed (config "fixed_kinds")
var by_key: Dictionary = {}       ## key -> name
var owner: Dictionary = {}        ## normalized name -> key
var kinds_of: Dictionary = {}     ## key -> kind (what it was named as)
var rolls: Dictionary = {}        ## key -> times the player rolled the dice on it (issue #835)
var labels: Dictionary = {}       ## key -> how it is shown, with a title ("Corporal Varo Kesh"); see NameHooks
var engine: NameEngine
var clashes := 0                  ## names thrown back because they were taken (tests read it)


func _init(eng: NameEngine = null) -> void:
	engine = eng if eng != null else shared_engine()
	world_seed = int(engine.config.get("world_seed", 1))
	game_seed = world_seed            # until a new game rolls one (fresh) or a save says
	for k in engine.config.get("fixed_kinds", []):
		fixed_kinds[str(k)] = true
	for r in engine.config.get("reserved", []):
		reserve(str(r.name), str(r.key))


## A book for a new game: the same places, new people (issue #834).
static func fresh(eng: NameEngine = null) -> NameBook:
	var b := NameBook.new(eng)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	b.game_seed = rng.randi_range(1, 999999)
	return b


## Is `kind` named the same in every game (a place, gear, an authored name)?
func is_fixed(kind: String) -> bool:
	return kind == "authored" or fixed_kinds.has(kind)


## The seed `kind` is named from.
func seed_for(kind: String) -> int:
	return world_seed if is_fixed(kind) else game_seed


## The library, loaded once per run (it never changes while playing).
static func shared_engine() -> NameEngine:
	if _shared_engine == null:
		_shared_engine = load_engine()
	return _shared_engine


static func load_engine(dir: String = NAMES_DIR) -> NameEngine:
	var e := NameEngine.new()
	var banks := {}
	var m = _read(MANIFEST)
	for id in (m.get("names", []) if m is Dictionary else []):
		var b = _read("%s/%s.json" % [dir, id])
		if b is Dictionary:
			banks[str(id)] = b
		else:
			push_warning("NameBook: name bank missing: " + str(id))
	var ip = _read(IP_LIST)
	var ip_d: Dictionary = ip if ip is Dictionary else {}
	e.setup(banks, ip_d.get("terms", []), ip_d.get("name_terms", []))
	return e


# ------------------------------------------------------------------ use

## The name of the thing with this key, giving it one if it has none yet.
## `kind` picks the grammar (content/core/names/kinds.json); `ctx` fills %(key)
## slots in it. Returns "" only if the kind cannot make a free name at all.
func name_for(kind: String, key: String, ctx: Dictionary = {}) -> String:
	if by_key.has(key):
		return by_key[key]
	var max_attempts := int(engine.config.get("max_attempts", 64))
	var fixed := is_fixed(kind)
	for attempt in max_attempts:
		var seed := NameEngine.fnv("%d|%s|%s|%d" % [seed_for(kind), kind, key, attempt])
		var n := engine.generate(kind, seed, ctx)
		if n == "":
			continue
		if _blocks(n, fixed):
			clashes += 1
			continue
		var holder := str(owner.get(NameEngine.normalize(n), ""))
		if holder != "":
			release(holder)           # a person had a place's name: the place wins (#834)
		_write(n, key, kind)
		return n
	push_warning("NameBook: no free %s name for %s" % [kind, key])
	return ""


## Claim an authored name (the cantina owner's, a town written by hand) so nothing
## generated can ever take it. False if it already belongs to something else.
func reserve(name: String, key: String) -> bool:
	var n := NameEngine.normalize(name)
	if owner.has(n) and owner[n] != key:
		return false
	_write(name, key, "authored")
	return true


## Issue #835: the player names this thing `name` (their ship, a speeder). "" when
## it took; otherwise why not, as a label key in content/core/story/main.json:
## "name_bad" (too short or long, a rude or franchise word) or "name_taken"
## (something else in the game has it). A refused name changes nothing.
func rename(key: String, name: String) -> String:
	var n := name.strip_edges()
	var kind := str(kinds_of.get(key, ""))
	if not engine.acceptable(n, engine.kinds.get(kind, {})):
		return "name_bad"
	var holder = owner.get(NameEngine.normalize(n))
	if holder != null and str(holder) != key:
		return "name_taken"
	_write(n, key, kind)
	labels.erase(key)
	return ""


## Issue #835: the dice. A new generated name of the same kind, free and never the
## one it had; the count is saved, so the next roll after a load is new too.
## Returns the name the thing has after (the old one if nothing free came up).
func reroll(key: String, ctx: Dictionary = {}) -> String:
	var kind := str(kinds_of.get(key, ""))
	if kind == "" or kind == "authored":
		return str(by_key.get(key, ""))
	rolls[key] = int(rolls.get(key, 0)) + 1
	var max_attempts := int(engine.config.get("max_attempts", 64))
	for attempt in max_attempts:
		var seed := NameEngine.fnv("%d|%s|%s#%d|%d" % [seed_for(kind), kind, key, int(rolls[key]), attempt])
		var n := engine.generate(kind, seed, ctx)
		if n == "" or is_taken(n):
			continue
		_write(n, key, kind)
		labels.erase(key)
		return n
	return str(by_key.get(key, ""))


func has(key: String) -> bool:
	return by_key.has(key)


func is_taken(name: String) -> bool:
	return owner.has(NameEngine.normalize(name))


## Is `name` unavailable to a new fixed (or, if not `fixed`, any) name? A fixed name
## is only held back by another fixed or authored one (issue #834).
func _blocks(name: String, fixed: bool) -> bool:
	var holder = owner.get(NameEngine.normalize(name))
	if holder == null:
		return false
	return not fixed or is_fixed(str(kinds_of.get(holder, "")))


## Let a name go (the thing is gone for good and its name may be reused).
func release(key: String) -> void:
	if by_key.has(key):
		owner.erase(NameEngine.normalize(by_key[key]))
		by_key.erase(key)
		kinds_of.erase(key)
		labels.erase(key)


## A deterministic pick from a list for this key (a rank, a title): the same key
## always gets the same one, without spending a name.
func pick(key: String, options: Array, salt: String = "pick") -> String:
	if options.is_empty():
		return ""
	var h := NameEngine.fnv("%d|%s|%s" % [game_seed, salt, key])
	return str(options[h % options.size()])


func size() -> int:
	return by_key.size()


func _write(name: String, key: String, kind: String) -> void:
	if by_key.has(key):
		owner.erase(NameEngine.normalize(by_key[key]))
	by_key[key] = name
	owner[NameEngine.normalize(name)] = key
	kinds_of[key] = kind


# ------------------------------------------------------------------ save

func to_save() -> Dictionary:
	return { "world_seed": world_seed, "game_seed": game_seed, "names": by_key.duplicate(), "kinds": kinds_of.duplicate(),
		"labels": labels.duplicate(), "rolls": rolls.duplicate() }


func from_save(d: Dictionary) -> void:
	world_seed = int(d.get("world_seed", world_seed))
	game_seed = int(d.get("game_seed", world_seed))   # a save from before #834 keeps its names
	var names: Dictionary = d.get("names", {})
	var kinds: Dictionary = d.get("kinds", {})
	for key in names:
		_write(str(names[key]), str(key), str(kinds.get(key, "")))
	labels = d.get("labels", {}).duplicate()
	rolls = d.get("rolls", {}).duplicate()


static func _read(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())
