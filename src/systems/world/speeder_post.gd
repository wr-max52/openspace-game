class_name SpeederPost
extends Node3D
## Skrugs's speeder post (issue #42). Issue #295: a different place per town
## layout: in the round port his yard inside the wall right behind the cantina, in
## the square port out in the sand past the back gate. Its footprint is world data
## (the "skrugs_post" landmark in content/core/worlds/port_desert.json, resolved per
## layout, and its location: content/core/locations/skrugs_post*.json), so the ship
## and speeders already collide with it and the player walks on it. This node adds:
##   - the look: a small house in the town's style, the stall, the display pad, his
##     garage (wall pieces you drive into) and its bench, and the sand ramp out past
##     the back gate (the "skrugs_ramp" landmark, with its sloped collider: a box
##     would be a wall),
##     string lights and fuel canisters in and around the garage (issue #435), and
##     issue #458: hanging lamps over his counter and his house door, a work light
##     in the garage, a lamp over his bench and a sign over the garage mouth, all
##     real lights on the look's lamp
##     clock (on by day, full at dusk and night), and his bench dressed as a
##     workbench like Dorrin's (a vise, a pegboard of tools),
##   - Skrugs: an all-red local behind the counter, a TalkSpot on the town's
##     ConversationHost, run by the same NpcBrain as the Cantina Owner from his
##     own card (content/core/npcs/skrugs_card.json),
##   - his own two speeders, never for sale (stock): the display speeder on its
##     pad and a racer that always stands in his garage. Both can be ridden, and
##     climbing on either is theft: he is furious (wrath, his card's "wrath"): the
##     locals hate you as if you had killed one of them (Townsfolk.outrage: the
##     same standing hit, their alarm up), he will not talk, and he lobs grenades
##     at you while you are in range, until you wake in the pit. A stolen one is a
##     loose speeder: not yours, not saved; both are back next time the town is
##     built,
##   - buying: Skrugs proposes (offer_speeder), the chat box shows the price, and
##     only the player's click pays. 100 credits off, a speeder parked in your
##     spot in the row outside the back gate (line_spot), his mood warm. Dorrin
##     sells the same models at the same prices (sell_speeder, SpeederShop), one
##     of each to a customer whoever sold it, and his wait in the same row. Speeders you own are saved
##     (WorldState counter "speeders_owned"); next time, and whenever you respawn
##     (ShipPilot.woke), yours waits in the row outside the back gate (the town's
##     speeder_spot markers, one spot per LAN player: line_up). Nothing else
##     brings one back: left in the desert, it stays there. A destroyed one is
##     gone, and he sells you another.
##     One to a customer (his card's sale.max_owned): every parked speeder runs its
##     hover each physics tick, and a yard of seven cost the town its frame rate.
##     Once you own one he does not offer another, and a save with more keeps
##     the first.
##   - issue #627: he sells three models (his card's sale.models: the Sand-boxer,
##     the racer, the box truck), one of each to a customer (max_owned is per
##     model). Each fit in WorldState.speeder_fits says its model (none = the
##     Sand-boxer), and a speeder is built from its own vehicle file. Parked
##     speeders sleep while you are far off (SpeederNode._sleeps), so three cost
##     what one did.
##   - issue #295, free roam only: [E] at his garage bench is Dorrin's parts menu
##     (SpeederShop) for the speeder in his garage,
##   - issue #295: he buys ships. One of yours landed within ship_buy's radius
##     (100 m) of his stall (a stolen outpost ship, for stolen_rate times its list
##     price, or the one T-89 sold you, at T-89's buy-back price): his chat offers
##     it (offer_ship_buy), and only the player's click sells. A stolen one he
##     offers for the moment you talk to him (the spot's opener).
##   - issue #368: turn down his price for a stolen ship and he offers to clean it
##     up instead, for keep_rate times its list price: only your click pays, and
##     it is yours (Fleet: no longer hunted, T-89 upgrades it, it stays where you
##     leave it). He buys your kept ships back at T-89's buy-back price.

const LANDMARK := "skrugs_post"         ## its location differs per layout (issue #295)
const RAMP := "skrugs_ramp"
const CARD_PATH := "res://content/core/npcs/skrugs_card.json"
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const RED := { "head": "local:red", "torso": "local:red", "legs": "local:red" }
## Issue #458: his lamps (HangingLamp). LAMP_DAY: the fraction of each lamp's
## energy it keeps at the presets that turn the town's lamps off (golden, noon);
## full at dusk and night. Energies and reach in metres.
const LAMP_DAY := 0.7
const STALL_LAMP := { "energy": 3.7, "reach": 7.0 }
const GARAGE_LIGHT := { "energy": 3.2, "reach": 9.0 }
const DOOR_LAMP := { "energy": 2.4, "reach": 5.0 }
const BENCH_LAMP := { "energy": 2.6, "reach": 4.5 }

var demo                              ## town_demo.gd
var ground: WorldGround
var host: ConversationHost
var spot: TalkSpot                    ## Skrugs's
var skrugs: Node3D                    ## his body
var display: SpeederNode              ## his own, on the display pad (stock)
var racer: SpeederNode                ## his own, always in his garage (stock)
var stock: Array = []                 ## his two speeders: climbing on one is theft (wrath)
var furious := false                  ## one of them was stolen: grenades, and no talking, until you wake in the pit
var thefts := 0                       ## his speeders stolen this session (tests, traces)
var throws := 0                       ## grenades he threw (tests, traces)
var last_grenade: Grenade             ## the last one (tests)
var _throw_left := 0.0
var _barks := 0
var _grenade_cfg: Dictionary = {}     ## content/core/weapons/grenade.json, read on his first throw
var speeders: Array = []              ## SpeederNode the player owns, here in the world
var origin := Vector3.ZERO            ## the landmark's anchor (base height included)
var yaw := 0.0
var points: Dictionary = {}           ## local name -> Vector3 (see the location file)
var parking: Array = []               ## issue #295: [{ at, nose }] where bought speeders wait
var location := ""                    ## the location this layout's post is built from
var card: Dictionary = {}             ## his card (the ship_buy block, his lines)
var shop: SpeederShop                 ## issue #295: his garage bench, free roam only (null in story)
var bench_in_reach := false
var ramp_at := Vector3.INF            ## the ramp's middle and its run-up spot (the trace rides it)
var ramp_start := Vector3.INF
var sales := 0                        ## speeders sold this session (tests, traces)
var ships_bought := 0                 ## issue #295: ships he bought this session (tests, traces)
var ships_kept := 0                   ## issue #368: stolen ships he cleaned up for you this session (tests, traces)
var _offered: Dictionary = {}         ## the item on the card right now
var _paint_scenes: Dictionary = {}    ## issue #82: path -> the paint's model, loaded in the background


func setup(town_demo, world_ground: WorldGround) -> void:
	demo = town_demo
	ground = world_ground
	name = "SpeederPost"


var build_later := false              ## issue #693: build() runs over frames (a handoff), not in _ready


func _ready() -> void:
	if not build_later:
		build(null)


## Skrugs, his stall, the stock and the speeders. `st` (a StagedBuild, may be null)
## puts each part on its own piece; the post only ticks once it is whole.
func build(st: StagedBuild = null) -> void:
	set_process(false)
	set_physics_process(false)
	var cc: CoreContent = CoreContent.shared()
	var world: Dictionary = demo.world if "world" in demo and not demo.world.is_empty() else cc.world_for_town("port_town")
	card = NpcBrain._read(CARD_PATH)
	for lm in world.get("landmarks", []):
		var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
		if str(lm.get("id", "")) == LANDMARK:
			origin = Vector3(at.x, ground.terrain.height_at(at.x, at.z), at.z)
			yaw = deg_to_rad(float(lm.get("yaw_deg", 0.0)))
			location = str(lm.get("location", LANDMARK))
		elif str(lm.get("id", "")) == RAMP:
			var ry := deg_to_rad(float(lm.get("yaw_deg", 0.0)))
			var run: Vector3 = WorldGround._v3(cc.get_location(str(lm.get("location", RAMP))).get("points", {}).get("run_up", [0, 0, 0]))
			ramp_at = Vector3(at.x, ground.terrain.height_at(at.x, at.z), at.z)
			ramp_start = ramp_at + run.rotated(Vector3.UP, ry)
			ramp_start.y = ground.terrain.height_at(ramp_start.x, ramp_start.z)
	var loc: Dictionary = cc.get_location(location if location != "" else LANDMARK)
	for k in loc.get("points", {}):
		points[k] = WorldGround._v3(loc.points[k])
	parking = loc.get("parking", [])
	_build_ramp_collider()
	if demo.use_look:
		await StagedBuild.slice_of(st)
		_dress(loc)
	await StagedBuild.slice_of(st)
	_build_skrugs()
	await StagedBuild.slice_of(st)
	_build_shop()
	await StagedBuild.slice_of(st)
	_build_stock()
	await StagedBuild.slice_of(st)
	_trim_owned()
	for i in WorldState.count("speeders_owned"):
		await StagedBuild.slice_of(st)
		_spawn(i)
	await StagedBuild.slice_of(st)
	line_up()
	if "pilot" in demo and demo.pilot != null:
		demo.pilot.woke.connect(line_up)
		demo.pilot.woke.connect(forgive)
	# Issue #82: each speeder sold is a new paint job, an 8 MB model; load them
	# now, off the main thread, so buying one does not hitch. Held here so they
	# stay cached.
	for m in models():                     # issue #627: every model he sells
		var look: Dictionary = HoverModel.load_config(str(m.get("id", "speeder"))).get("look", {})
		for id in look.get("sold_paints", []):
			var path := str(look.get("paints", {}).get(id, look.get("scene", "") if str(id) == "" else ""))
			if path != "" and ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path) == OK:
				_paint_scenes[path] = null
	set_process(true)
	set_physics_process(true)


func _process(_dt: float) -> void:
	var waiting := false
	for path in _paint_scenes:
		if _paint_scenes[path] != null:
			continue
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			waiting = true
		elif st == ResourceLoader.THREAD_LOAD_LOADED:
			_paint_scenes[path] = ResourceLoader.load_threaded_get(path)
		else:
			_paint_scenes[path] = false
	set_process(waiting)


## A point from the location file, in the world.
func world_point(id: String) -> Vector3:
	return _world(points.get(id, Vector3.ZERO))


func _world(lp: Vector3) -> Vector3:
	return origin + lp.rotated(Vector3.UP, yaw)


## The post's frame (HangingLamp places things in it).
func _xf() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), origin)


## The scene's look, for its lamp clock; null in a bare dressing (tests, lookdev).
func _look() -> LookEnvironment:
	return demo.get("look") as LookEnvironment if demo != null else null


## Issue #295: where to start a straight run at the ramp, and the way up it
## (flat). INF / zero when this world has no ramp.
func ramp_run_up() -> Vector3:
	return ramp_start


func ramp_dir() -> Vector3:
	if ramp_at == Vector3.INF:
		return Vector3.ZERO
	var d := ramp_at - ramp_start
	d.y = 0.0
	return d.normalized()


## Hand Skrugs to the town's conversation host (when it has one: the look is on,
## or a test built it). Safe to call twice.
func attach_host(h: ConversationHost) -> void:
	if h == null or host == h:
		return
	host = h
	var brain := NpcBrain.new(null, CARD_PATH)
	spot = TalkSpot.new(brain, skrugs, world_point("customer"))
	spot.radius = 2.2
	spot.face_height = 1.55
	host.add_spot(spot)
	brain.ship_offer = func(): return _offer_card(ship_offer())
	brain.sale_open = func(): return not at_limit()
	brain.sale_models = func(): return open_models().map(func(m): return str(m.get("id", "")))
	spot.opener = _opener
	spot.available = func(): return not furious     # he won't talk to a thief
	spot.shortcuts = shortcuts
	spot.on_shortcut = _on_shortcut
	brain.extra_brief = brief
	brain.sale_offered.connect(_on_offer)
	brain.ship_buy_offered.connect(_on_ship_offer)
	host.panel.sale_answered.connect(_on_answer)


## Issue #295: his own facts each turn: where his post is in this town, and what
## his garage does (free roam: the bench fits parts).
func brief() -> Array:
	var out: Array = []
	var where := str(card.get("where", {}).get(location, ""))
	if where != "":
		out.append(where)
	var g := str(card.get("garage", {}).get("free" if shop != null else "story", ""))
	if g != "":
		out.append(g)
	return out


# ------------------------------------------------------------------ buying

## Issue #305: the keyword row over his chat box: his speeder's price card, and
## (with a ship of yours by his post) what he would pay for it.
func shortcuts() -> Array:
	var k: Dictionary = card.get("shortcuts", {})
	var out := []
	# Issue #627: a button per model they don't own yet.
	for m in open_models():
		var mid := str(m.get("id", ""))
		out.append({ "id": "go_speeder:" + mid, "label": str(k.get("models", {}).get(mid, k.get("speeder", "Buy a speeder"))) })
	if not ship_offer().is_empty():
		out.append({ "id": "go_sell_ship", "label": str(k.get("sell_ship", "Sell my ship")) })
	return out


func _on_shortcut(id: String) -> void:
	if id == "go_sell_ship":
		_on_ship_offer({ "id": str(ship_offer().get("id", "")) })
		return
	var m := model_sale(id.trim_prefix("go_speeder").trim_prefix(":"))
	if m.is_empty():
		var opened := open_models()
		m = opened[0] if not opened.is_empty() else {}
	_on_offer({ "id": str(m.get("id", "")), "name": str(m.get("name", "")), "price": int(m.get("price", 0)) })


func _on_offer(item: Dictionary) -> void:
	if host == null or host.active != spot:
		return
	var m := model_sale(str(item.get("id", "")))     # issue #627: the game's model, price and words
	if m.is_empty() or at_limit(str(m.get("id", ""))):
		return
	_offered = { "id": str(m.get("id", "")), "name": str(m.get("name", "")), "price": int(m.get("price", 0)),
		"text": str(m.get("text", "")) }
	host.panel.show_sale(_offered, WorldState.credits)


func _on_answer(id: String, accepted: bool) -> void:
	if host == null or host.active != spot or id != str(_offered.get("id", "")):
		return
	if not accepted:
		if bool(_offered.get("selling", false)) and bool(_offered.get("stolen", false)):
			_offered = {}
			_offer_keep()                  # issue #368: not selling? he cleans her up instead
		return
	if bool(_offered.get("keeping", false)):
		_offered = {}
		keep_ship()
		return
	if bool(_offered.get("selling", false)):
		_offered = {}
		buy_ship()
		return
	buy(str(_offered.get("id", "speeder")))


## Pay for a new speeder of `model` (issue #627: speeder, racer or hauler) and park
## it in the row outside the back gate. False (and nothing charged) if he does not sell
## it, the player cannot afford it, or already owns one.
func buy(model: String = "speeder") -> bool:
	var sale := model_sale(model)
	if sale.is_empty():
		return false
	if sell_speeder(model, "Someone bought a %s from Skrugs." % str(sale.get("name", "speeder")), "back_gate") == null:
		return false
	sales += 1
	if spot != null:
		var rel := spot.brain.rel
		rel.mood = "warm"
		rel.add_trust(3, "bought a speeder")
		rel.remember("bought a speeder")
		if host != null and host.active == spot:
			var lines: Array = spot.brain.card.get("canned", {}).get("sold", ["She's in the garage."])
			_answer_line(str(lines[0]))
	return true


## Pay for a new speeder of `model` at his price and park it: every new speeder,
## his or Dorrin's (SpeederShop.buy_speeder), waits in your spot in the row
## outside the back gate (line_spot; his parking out back when the town has no
## row). `event` is the log line (%s: the model's name). Returns the new speeder,
## or null (and nothing charged): not one he sells, too dear, or they own one.
func sell_speeder(model: String, event: String = "", where: String = "") -> SpeederNode:
	var sale := model_sale(model)
	if sale.is_empty():
		return null
	var price := int(sale.get("price", 100))
	if WorldState.credits < price or at_limit(model):
		return null
	WorldState.credits -= price
	var i := WorldState.count("speeders_owned")
	while WorldState.speeder_fits.size() < i:
		fit_for(WorldState.speeder_fits.size())        # an old save's speeders get their fits first
	WorldState.speeder_fits.resize(i)
	WorldState.speeder_fits.append(SpeederUpgrades.new_fit(_next_paint(model), model))
	WorldState.bump("speeders_owned")
	WorldState.set_flag("bought_speeder")
	if event != "":
		WorldState.log_event(event.replace("%s", str(sale.get("name", "speeder"))), where)
	return _park(i)


## The most speeders of one model a player owns (his card's sale.max_owned).
func max_owned() -> int:
	return int(card.get("sale", {}).get("max_owned", 1))


## Issue #627: the models he sells (his card's sale.models; a card with none sells
## its one sale as the Sand-boxer).
func models() -> Array:
	var sale: Dictionary = card.get("sale", {})
	var ms: Array = sale.get("models", [])
	if not ms.is_empty():
		return ms
	return [{ "id": "speeder", "name": str(sale.get("name", "speeder")), "price": int(sale.get("price", 100)),
		"text": str(sale.get("text", "")) }]


## His sale card for one model ({} if he does not sell it).
func model_sale(model: String) -> Dictionary:
	for m in models():
		if str(m.get("id", "")) == model:
			return m
	return {}


## How many of `model` they bought from him or Dorrin (fits without a model are
## Sand-boxers). Issue #617: speeders won on pink slips ("won") or kept after the
## gate chase ("stolen") are not his sales, so they never use up his one of each.
func owned_of(model: String) -> int:
	var n := 0
	for i in mini(WorldState.count("speeders_owned"), WorldState.speeder_fits.size()):
		var f: Dictionary = WorldState.speeder_fits[i]
		if bool(f.get("won", false)) or bool(f.get("stolen", false)):
			continue
		if SpeederUpgrades.model_of(f) == model:
			n += 1
	# An old save may count speeders it has no fit for yet: those are Sand-boxers.
	if model == "speeder":
		n += maxi(0, WorldState.count("speeders_owned") - WorldState.speeder_fits.size())
	return n


## The models still for sale to them.
func open_models() -> Array:
	return models().filter(func(m): return owned_of(str(m.get("id", ""))) < max_owned())


## They own as many of `model` as he sells to one customer; with no model, of
## every model.
func at_limit(model: String = "") -> bool:
	if model == "":
		return open_models().is_empty()
	return owned_of(model) >= max_owned()


## The most speeders one player can own: one of each (issue #627).
func max_total() -> int:
	return max_owned() * models().size()


## Issue #617: the most speeders you can own at all (won on pink slips or kept
## after a chase): the row outside the back gate's spots (racing rules owned_cap).
## Skrugs still sells only one of each model (max_total).
func owned_cap() -> int:
	var town = demo.get("town") if demo != null else null
	var row: Array = town.markers_with_role("speeder_spot") if town != null else []
	return maxi(max_total(), mini(int(RaceCrew.rule("owned_cap", 5.0)), maxi(row.size(), 1)))


## Issue #617: a speeder that is now yours (won on pink slips) with `fit` (paint
## and parts), parked in the row outside the back gate. null if you own all you can.
func add_owned(fit: Dictionary) -> SpeederNode:
	if WorldState.count("speeders_owned") >= owned_cap():
		return null
	var i := WorldState.count("speeders_owned")
	WorldState.bump("speeders_owned")
	while WorldState.speeder_fits.size() < i:
		fit_for(WorldState.speeder_fits.size())
	var won := fit.duplicate(true)
	won["won"] = true                    # not one he sold: kept past the one-of-each rule
	if WorldState.speeder_fits.size() > i:
		WorldState.speeder_fits[i] = won
	else:
		WorldState.speeder_fits.append(won)
	var s := _spawn(i)
	var spot_at := line_spot(i)
	s.place(spot_at[0], spot_at[1])
	return s


## Issue #613: speeder `s` (the gate speeder you got away on) is yours now, as it
## stands: with `fit`, counted, saved, in the row next visit. False if you own all
## you can.
func adopt(s: SpeederNode, fit: Dictionary) -> bool:
	if s == null or speeders.has(s) or WorldState.count("speeders_owned") >= owned_cap():
		return false
	var i := WorldState.count("speeders_owned")
	WorldState.bump("speeders_owned")
	while WorldState.speeder_fits.size() < i:
		fit_for(WorldState.speeder_fits.size())
	if WorldState.speeder_fits.size() > i:
		WorldState.speeder_fits[i] = fit.duplicate(true)
	else:
		WorldState.speeder_fits.append(fit.duplicate(true))
	s.set_meta("slot", i)
	s.destroyed.connect(func(_at): _lost(s))
	speeders.append(s)
	return true


## Issue #613: a stolen speeder you own is one Skrugs buys: it is gone, you are
## paid. Returns the credits paid (0 = not a stolen one of yours).
func sell_stolen(s: SpeederNode, price: int) -> int:
	if s == null or not speeders.has(s):
		return 0
	if not bool(fit_for(int(s.get_meta("slot", 0))).get("stolen", false)):
		return 0
	if s.riding:
		s.dismount()
	remove(s)
	WorldState.credits += price
	WorldState.log_event("Skrugs bought a speeder with no questions asked.", "back_gate")
	return price


## Whether `s` is a stolen speeder of yours.
func is_stolen(s: SpeederNode) -> bool:
	return s != null and speeders.has(s) and bool(fit_for(int(s.get_meta("slot", 0))).get("stolen", false))


## A save from before the one-speeder rule keeps its first speeder of each model
## (and their fits); the rest are gone. Issue #617: speeders won on pink slips or
## kept after a chase ("won" / "stolen" fits) are not his to limit: they stay, up to
## owned_cap in all.
func _trim_owned() -> void:
	var n := WorldState.count("speeders_owned")
	while WorldState.speeder_fits.size() < mini(n, max_total() * 4):
		WorldState.speeder_fits.append(SpeederUpgrades.new_fit(_next_paint("speeder")))
	var kept: Array = []
	var per: Dictionary = {}
	for i in mini(n, WorldState.speeder_fits.size()):
		var f: Dictionary = WorldState.speeder_fits[i]
		if kept.size() >= owned_cap():
			break
		if bool(f.get("won", false)) or bool(f.get("stolen", false)):
			kept.append(f)
			continue
		var m := SpeederUpgrades.model_of(f)
		if int(per.get(m, 0)) < max_owned() and (not model_sale(m).is_empty() or m == "speeder"):
			per[m] = int(per.get(m, 0)) + 1
			kept.append(f)
	WorldState.speeder_fits.assign(kept)
	WorldState.counters["speeders_owned"] = kept.size()


## His line in the chat box after a deal, with the new money.
func _answer_line(text: String) -> void:
	host.panel.commit_line()
	host.panel.set_line(text)
	host.panel.set_mood(spot.brain.rel.mood)
	host.panel.set_money(WorldState.credits, spot.brain.rel.tab)
	spot.speak_pulse()


## Speeder number `i`, new: in its spot in the row outside the back gate (line_spot).
func _park(i: int) -> SpeederNode:
	var s := _spawn(i)
	var spot_at := line_spot(i)
	s.place(spot_at[0], spot_at[1])
	return s


## The location's "parking" spot `i` (out back behind his house): [position, yaw].
## Only where speeders wait when the town has no row (line_spot).
func parking_spot(i: int) -> Array:
	return _spot(parking[i % parking.size()] if not parking.is_empty() else {})


## A { at, nose } from the location file: [position on the sand, yaw].
func _spot(spot_cfg: Dictionary) -> Array:
	var at := _world(WorldGround._v3(spot_cfg.get("at", [0, 0, 0])))
	at.y = ground.terrain.height_at(at.x, at.z)
	var axis := { "+x": Vector3.RIGHT, "-x": Vector3.LEFT, "+z": Vector3.BACK, "-z": Vector3.FORWARD }
	var nose: Vector3 = (axis.get(str(spot_cfg.get("nose", "-x")), Vector3.LEFT) as Vector3).rotated(Vector3.UP, yaw)
	return [at, atan2(-nose.x, -nose.z)]


## Where speeder `i` waits after you respawn: [position, yaw]. Your own spot in
## the row outside the back gate (the town's speeder_spot markers, in order; a LAN
## player's is NetSession.my_slot, so everyone has one), the next one on for each
## more you own. His garage when the town has no row.
func line_spot(i: int = 0) -> Array:
	var town = demo.get("town")
	var row: Array = town.markers_with_role("speeder_spot") if town != null else []
	if row.is_empty():
		return parking_spot(i)
	row.sort_custom(func(a, b): return str(a.id).naturalnocasecmp_to(str(b.id)) < 0)
	# Issue #627: each player has max_total spots of their own, so two LAN players'
	# speeders never share one.
	var m: Dictionary = row[(NetSession.my_slot() * max_total() + i) % row.size()]
	var at: Vector3 = town.marker_pos(str(m.id))
	at.y = ground.terrain.height_at(at.x, at.z)
	return [at, deg_to_rad(float(m.get("yaw_deg", 0.0)))]


## The player respawned (ShipPilot.woke), or the town was just built: every
## speeder they own goes to its spot in the row (line_spot), wherever it was. A
## destroyed one is not brought back (it is no longer theirs: buy another).
func line_up() -> void:
	for s in speeders:
		if not is_instance_valid(s) or s.riding:
			continue
		var spot_at := line_spot(int(s.get_meta("slot", 0)))
		s.place(spot_at[0], spot_at[1])


## Issue #95: speeder `i` with its fit (paint and parts) from WorldState.speeder_fits.
## A speeder from before upgrades gets a fit here (a Sand-boxer), its old paint
## job included.
func fit_for(i: int) -> Dictionary:
	while WorldState.speeder_fits.size() <= i:
		WorldState.speeder_fits.append(SpeederUpgrades.new_fit(_next_paint("speeder")))
	return WorldState.speeder_fits[i]


## Issue #82: each speeder of a model a different paint job, round its sold_paints.
func _next_paint(model: String) -> String:
	var paints: Array = HoverModel.load_config(model).get("look", {}).get("sold_paints", [""])
	if paints.is_empty():
		return ""
	var n := WorldState.speeder_fits.filter(func(f): return SpeederUpgrades.model_of(f) == model).size()
	if model == "speeder":
		n = WorldState.speeder_fits.size()      # as before: the Sand-boxer's paint rolls with the count
	return str(paints[n % paints.size()])


func _spawn(i: int) -> SpeederNode:
	var s := SpeederNode.new()
	var fit := fit_for(i)
	var model := SpeederUpgrades.model_of(fit)       # issue #627: built from its own vehicle file
	s.setup(demo, ground, SpeederUpgrades.apply(HoverModel.load_config(model), fit), true, str(fit.get("paint", "")))
	s.set_meta("slot", i)
	demo.add_child(s)
	s.destroyed.connect(func(_at): _lost(s))
	speeders.append(s)
	return s


## Issue #95: rebuild speeder `s` with its fit as it is now (after the mechanic
## changed it), where it stands. Returns the new node.
func refit(s: SpeederNode) -> SpeederNode:
	var i := int(s.get_meta("slot", 0))
	var at := s.model.position
	var heading := s.model.yaw
	speeders.erase(s)
	s.queue_free()
	var n := _spawn(i)
	n.place(at, heading)
	return n


## Issue #95: speeder `s` is gone for good (sold for scrap): no burn-out in the log.
func remove(s: SpeederNode) -> void:
	_forget(s)
	s.queue_free()


func _lost(s: SpeederNode) -> void:
	_forget(s)
	WorldState.log_event("A speeder burned out in the sand.")


func _forget(s: SpeederNode) -> void:
	speeders.erase(s)
	WorldState.counters["speeders_owned"] = maxi(0, WorldState.count("speeders_owned") - 1)
	# Its fit goes with it; the ones parked after it move up a slot.
	var i := int(s.get_meta("slot", -1))
	if i >= 0 and i < WorldState.speeder_fits.size():
		WorldState.speeder_fits.remove_at(i)
		for o in speeders:
			if int(o.get_meta("slot", 0)) > i:
				o.set_meta("slot", int(o.get_meta("slot", 0)) - 1)


# ------------------------------------------------------------------ his bench (issue #295)

## Free roam only: [E] at his garage bench is the mechanic's parts menu, on the
## speeder in his garage. In a story save Dorrin stays the only mechanic.
func _build_shop() -> void:
	if WorldState.story_mode() or not points.has("bay"):
		return
	shop = SpeederShop.new()
	shop.setup(demo, demo.gear if "gear" in demo else null, SpeederUpgrades.shop("skrugs"), func(): return world_point("bay"))
	shop.speaker = skrugs
	add_child(shop)


func _physics_process(dt: float) -> void:
	tick_wrath(dt)
	var p: CharacterBody3D = demo._player if demo != null and "_player" in demo else null
	if shop == null or p == null or shop.busy():
		return
	var gear: GearController = shop.gear
	var at := world_point("bench")
	bench_in_reach = not p.piloting and Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() \
		<= float(shop.cfg.get("reach", 2.6)) and absf(p.global_position.y - at.y) <= 2.0 and (gear == null or gear.focus.is_empty())
	if not bench_in_reach:
		return
	if gear != null and gear.hud != null:
		gear.hud.set_prompt(shop.label("talk") % shop.npc_name())
	if not p.locked and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		shop.talk()


# ------------------------------------------------------------------ his own speeders (wrath)

## His two speeders, never for sale: the display one on its pad (a Sand-boxer in
## its display paint) and the racer in his garage (his card's wrath.racer, at the
## location's "racer" point, nose out). Both rideable; climbing on is theft.
func _build_stock() -> void:
	display = SpeederNode.new()
	display.setup(demo, ground, HoverModel.load_config("speeder"), true,
		str(HoverModel.load_config("speeder").get("look", {}).get("display_paint", "")))
	add_child(display)
	display.name = "DisplaySpeeder"
	display.place(world_point("display"), yaw + PI * 0.5)
	stock = [display]
	if points.has("racer"):
		var model := str(wrath_cfg().get("racer", "racer"))
		racer = SpeederNode.new()
		racer.setup(demo, ground, HoverModel.load_config(model), true, "")
		add_child(racer)
		racer.name = "SkrugsRacer"
		var at := _spot({ "at": [points.racer.x, 0, points.racer.z], "nose": "+x" })
		racer.place(at[0], at[1])
		stock.append(racer)
	for s in stock:
		s.set_meta("skrugs_stock", true)
		s.mounted.connect(_on_stock_mounted.bind(s))


## His card's "wrath" block.
func wrath_cfg() -> Dictionary:
	return card.get("wrath", {})


func _wrath_line(key: String) -> String:
	return str(wrath_cfg().get("lines", {}).get(key, ""))


func _on_stock_mounted(s: SpeederNode) -> void:
	if s.has_meta("stolen_from_skrugs"):
		return                                 # already stolen: riding it again changes nothing
	s.set_meta("stolen_from_skrugs", true)
	stock.erase(s)
	steal(s)


## Speeder `s` of his was stolen: the locals hate you as if you had killed one of
## them (the same standing hit, their alarm up), and he is furious: grenades and
## no talking until you wake in the pit.
func steal(_s: SpeederNode = null) -> void:
	thefts += 1
	var tf = demo.get("townsfolk") if demo != null else null
	if tf != null and is_instance_valid(tf):
		tf.outrage(_wrath_line("standing"))
	else:                                      # no locals running (npc brains off): the hit all the same
		var town = demo.get("town") if demo != null else null
		var locals: Dictionary = town.data.get("locals", {}) if town != null and town.data is Dictionary else {}
		WorldState.change_standing("locals", int(locals.get("alarm", {}).get("killed_standing", -8)), _wrath_line("standing"))
	WorldState.log_event(_wrath_line("event"), "back_gate")
	if host != null and host.active == spot:
		host.end_talk()
	if spot != null:
		var rel := spot.brain.rel
		rel.mood = "angry"
		rel.add_trust(-30, "stole one of my speeders")
	if not furious:
		furious = true
		_throw_left = float(wrath_cfg().get("first_s", 0.8))
	_toast(_wrath_line("stolen"))


## You woke in the pit: he lets it go (as the locals do: Townsfolk.forgive_player).
func forgive() -> void:
	furious = false


## Furious: a grenade at the player every every_s while they are within throw_m.
func tick_wrath(dt: float) -> void:
	if not furious or skrugs == null:
		return
	var p: CharacterBody3D = demo._player if demo != null and "_player" in demo else null
	if p == null or not is_instance_valid(p) or p.get("is_downed") == true:
		return
	var target := _wrath_target(p)
	if target.distance_to(skrugs.global_position) > float(wrath_cfg().get("throw_m", 45.0)):
		_throw_left = maxf(_throw_left, float(wrath_cfg().get("first_s", 0.8)))
		return
	_throw_left -= dt
	if _throw_left > 0.0:
		return
	_throw_left = float(wrath_cfg().get("every_s", 2.4))
	throw_at(p)


## Where the player is (their speeder's middle when riding).
func _wrath_target(p: CharacterBody3D) -> Vector3:
	if p.piloting and p.vehicle is SpeederNode and is_instance_valid(p.vehicle):
		return (p.vehicle as SpeederNode).model.position
	return p.global_position


## Lob one grenade at the player: from his hand, landing where they will be after
## the flight (a quick one up close, longer far off), led by their speeder's speed.
func throw_at(p: CharacterBody3D) -> Grenade:
	if _grenade_cfg.is_empty():
		_grenade_cfg = CharacterKit._read_json(Grenade.CFG_PATH)
	var cfg := _grenade_cfg
	var w := wrath_cfg()
	var up := Vector3.UP
	var hand := skrugs.global_position + up * float(w.get("hand_m", 1.9))
	var target := _wrath_target(p)
	var vel := Vector3.ZERO
	if p.piloting and p.vehicle is SpeederNode and is_instance_valid(p.vehicle):
		var v: SpeederNode = p.vehicle
		vel = v.model.forward() * v.model.speed
	var span: Array = w.get("flight_s", [0.8, 1.9])
	var reach := float(w.get("throw_m", 45.0))
	var t: float = lerpf(float(span[0]), float(span[1]), clampf(hand.distance_to(target) / maxf(reach, 1.0), 0.0, 1.0))
	var g := float(cfg.get("gravity", 20.0))
	var land := target + vel * t
	var launch := (land - hand) / t + up * (0.5 * g * t)
	# Out of his hand toward them, so the first step clears his own counter.
	var flat := Vector3(land.x - hand.x, 0.0, land.z - hand.z)
	if flat.length() > 0.01:
		hand += flat.normalized() * 0.6
	var gr := Grenade.new()
	gr.setup(cfg, hand, launch, skrugs)
	gr.player = p
	gr.host = demo
	demo.add_child(gr)
	gr.global_position = hand
	throws += 1
	last_grenade = gr
	var barks: Array = w.get("lines", {}).get("barks", [])
	if not barks.is_empty():
		_toast("%s: %s" % [str(card.get("name", "Skrugs")), str(barks[_barks % barks.size()])], 1.8)
		_barks += 1
	return gr


func _toast(text: String, secs := 3.5) -> void:
	var gear: GearController = demo.gear if demo != null and "gear" in demo else null
	if text != "" and gear != null and gear.hud != null:
		gear.hud.toast(text, secs)


# ------------------------------------------------------------------ buying ships (issue #295)

## The ship he would buy right now, or {}: one of yours landed within ship_buy's
## radius of his stall (the "merchant" spot) and not under you; the nearest. A stolen outpost ship pays
## stolen_rate times its list price (t89.json); the ship T-89 sold you, his
## buy-back price. Never the pit pad's ship (berth 0) or the port's free-roam
## ships: free keys are not free money.
## { id, name, price, berth, kind ("stolen" or "owned") }
func ship_offer() -> Dictionary:
	var pilot = demo.pilot if demo != null and "pilot" in demo else null
	if pilot == null or not points.has("merchant"):
		return {}
	var sb: Dictionary = card.get("ship_buy", {})
	var here := world_point("merchant")
	var best := {}
	var best_d := float(sb.get("radius", 30.0))
	for i in range(1, pilot.berths.size()):
		var b: Dictionary = pilot.berths[i]
		if bool(b.get("destroyed", false)) or not is_instance_valid(b.visual) or (pilot.piloting and pilot.berth == i):
			continue
		var kind := _berth_kind(b)
		if kind == "":
			continue
		var v: Vector3 = (b.visual as Node3D).global_position
		var d := Vector2(v.x - here.x, v.z - here.z).length()
		if d > best_d:
			continue
		var sid := str(b.ship_id)
		var price := ShipSalesman.resale_price(sid) if kind == "owned" \
			else int(round(ShipSalesman.list_price(sid) * float(sb.get("stolen_rate", 1.25))))
		best = { "id": "ship:%d" % i, "name": ShipUpgrades.ship_label(sid), "price": price, "berth": i, "kind": kind }
		best_d = d
	return best


## "stolen", "owned" (T-89's sale, or issue #368: one he cleaned up for you) or ""
## (he won't touch it).
func _berth_kind(b: Dictionary) -> String:
	if bool(b.get("stolen", false)):
		return "stolen"
	var key := str(b.get("key", ""))
	if key == Fleet.T89 or key.begins_with("kept_"):
		return "owned"
	return ""


## What the model is told and may offer: the offer without the game's bookkeeping.
static func _offer_card(o: Dictionary) -> Dictionary:
	if o.is_empty():
		return {}
	return { "id": o.id, "name": o.name, "price": o.price, "stolen": str(o.kind) == "stolen" }


## His offer_ship_buy: the chat box shows what he pays, if the ship is still there.
func _on_ship_offer(item: Dictionary) -> void:
	if host == null or host.active != spot:
		return
	var o := ship_offer()
	if o.is_empty() or str(o.id) != str(item.get("id", "")):
		return
	_offered = _ship_card(o)
	host.panel.show_sale(_offered, WorldState.credits)


## The chat box's card for selling him ship offer `o`.
func _ship_card(o: Dictionary) -> Dictionary:
	return { "id": o.id, "name": o.name, "price": o.price, "selling": true, "stolen": str(o.kind) == "stolen",
		"text": str(card.get("ship_buy", {}).get("lines", {}).get("card", "%s")) % str(o.name) }


## Issue #368: what he asks to clean up stolen ship `ship_id`: keep_rate times its list price.
func keep_price(ship_id: String) -> int:
	return int(round(ShipSalesman.list_price(ship_id) * float(card.get("ship_buy", {}).get("keep_rate", 0.5))))


## Issue #368: you turned his price down for a stolen ship: the chat box offers to
## clean it up instead, if it is still there.
func _offer_keep() -> void:
	var o := ship_offer()
	if o.is_empty() or str(o.kind) != "stolen" or host == null or host.active != spot:
		return
	var lines: Dictionary = card.get("ship_buy", {}).get("lines", {})
	var price := keep_price(str(demo.pilot.berths[int(o.berth)].ship_id))
	_offered = { "id": "keep:%d" % int(o.berth), "name": o.name, "price": price, "keeping": true,
		"text": str(lines.get("keep_card", "%s")) % str(o.name) }
	_answer_line(str(lines.get("keep_offer", "%s, %d credits.")) % [str(o.name), price])
	host.panel.show_sale(_offered, WorldState.credits)


## Issue #368: pay him to clean up the stolen ship by his post. It is yours from
## now on (ShipPilot.keep_berth). Returns the credits paid, or -1 (nothing there,
## or you cannot pay).
func keep_ship() -> int:
	var o := ship_offer()
	if o.is_empty() or str(o.kind) != "stolen":
		return -1
	var pilot = demo.pilot
	var i := int(o.berth)
	var price := keep_price(str(pilot.berths[i].ship_id))
	var lines: Dictionary = card.get("ship_buy", {}).get("lines", {})
	if WorldState.credits < price:
		if host != null and host.active == spot:
			_answer_line(str(lines.get("keep_short", "%d credits, friend.")) % price)
		return -1
	if not pilot.keep_berth(i):
		return -1
	WorldState.credits -= price
	WorldState.log_event(str(lines.get("event_kept", "Skrugs cleaned up a %s for someone.")) % str(o.name), "back_gate")
	ships_kept += 1
	if spot != null:
		var rel := spot.brain.rel
		rel.mood = "warm"
		rel.add_trust(2, "cleaned up a ship for you")
		rel.remember("cleaned up a " + str(o.name).to_lower() + " for you")
		if host != null and host.active == spot:
			_answer_line(str(lines.get("kept", "She's yours. %d credits.")) % price)
	return price


## His spot's opener: a stolen ship within reach, and he names his price before
## anything else, the card already up. {} = he greets as usual.
func _opener() -> Dictionary:
	var o := ship_offer()
	if o.is_empty() or str(o.kind) != "stolen":
		return {}
	_offered = _ship_card(o)
	var line := str(card.get("ship_buy", {}).get("lines", {}).get("opener", "%s, %d credits."))
	return { "say": line % [str(o.name), int(o.price)], "sale": _offered }


## Sell him the ship by his post. It goes for good the way a lost stolen ship does
## (ShipPilot.sell_berth), but you stay where you are; a stolen one's chase ends
## with it. Returns the credits paid, or -1 (nothing there, or you sit in it).
func buy_ship() -> int:
	var o := ship_offer()
	if o.is_empty():
		return -1
	var pilot = demo.pilot
	var i := int(o.berth)
	var sid := str(pilot.berths[i].ship_id)
	if not pilot.sell_berth(i):
		return -1
	var paid := int(o.price)
	var lines: Dictionary = card.get("ship_buy", {}).get("lines", {})
	if str(o.kind) == "owned":
		ShipSalesman.settle_sale(sid, paid)
		WorldState.log_event(str(lines.get("event_owned", "Someone sold a %s to Skrugs.")) % str(o.name), "back_gate")
	else:
		WorldState.credits += paid
		WorldState.log_event(str(lines.get("event_stolen", "Someone sold a Remnant ship to Skrugs.")), "back_gate")
	ships_bought += 1
	if spot != null:
		var rel := spot.brain.rel
		rel.mood = "warm"
		rel.add_trust(3, "sold you a ship")
		rel.remember("sold you a " + str(o.name).to_lower())
		if host != null and host.active == spot:
			_answer_line(str(lines.get("bought", "Pleasure, friend.")) % paid)
	return paid


# ------------------------------------------------------------------ Skrugs

func _build_skrugs() -> void:
	var at := world_point("merchant")
	var face := world_point("customer")
	if demo.use_look:
		var kit := CharacterKit.new(demo._flat_mats(), 0.0)
		skrugs = MerchantNPC.new(kit, "local", RED)
	else:
		skrugs = MerchantNPC.new(null)
	skrugs.name = "Skrugs"
	add_child(skrugs)
	skrugs.global_position = at
	skrugs.rotation.y = atan2(face.x - at.x, face.z - at.z)
	skrugs.look_at_target = demo._player


# ------------------------------------------------------------------ the look

## A wedge collider for the ramp, matching WorldGround's sloped top, so the player
## can walk up it too.
func _build_ramp_collider() -> void:
	for b in ground.boxes:
		if not (str(b.id).begins_with(RAMP + "/") or str(b.id).begins_with(LANDMARK + "/")) or str(b.get("rise", "")) == "":
			continue
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		var pts := PackedVector3Array()
		# Six corners: the low edge, the high edge up top, and the base.
		match str(b.rise):
			"-z":
				pts = [Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mn.z),
					Vector3(mx.x, mn.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z)]
			"+z":
				pts = [Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mn.x, mn.y, mx.z),
					Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z)]
			"-x":
				pts = [Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mn.z),
					Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mx.y, mn.z), Vector3(mn.x, mx.y, mx.z)]
			_:
				pts = [Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mn.z),
					Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z)]
		var body := StaticBody3D.new()
		body.name = "RampCollider"
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
		# Issue #77: on the ball the box is in its landmark's own frame.
		body.global_transform = WorldGround.box_xf(b)
		if demo.use_look:
			var mi := MeshInstance3D.new()
			mi.name = "Ramp"
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_smooth_group(-1)      # flat faces: hard rock edges, and the rock's
			                             # wall/top projection does not smear up the sides
			# Sloped top, two sides, the high end (the low end is flush with the sand).
			# The rock shader culls back faces, so each triangle is wound to face out
			# (Godot's clockwise front, against the wedge's own middle: the box's
			# middle sits on the slope); the corners, and so the shape, are unchanged.
			var mid := Vector3.ZERO
			for p in pts:
				mid += p / 6.0
			var tris := [[0, 4, 1], [1, 4, 5], [0, 2, 4], [1, 5, 3], [2, 3, 4], [3, 5, 4]]
			for t in tris:
				var a: Vector3 = pts[t[0]]
				var bb: Vector3 = pts[t[1]]
				var c: Vector3 = pts[t[2]]
				if (a - c).cross(a - bb).dot((a + bb + c) / 3.0 - mid) < 0.0:
					t = [t[0], t[2], t[1]]
				for k in t:
					st.add_vertex(pts[k])
			st.generate_normals()
			mi.mesh = st.commit()
			# A boulder, not a sand pile: the desert boulders' own rock (strata, pitted
			# grain, dust on the slope), set to the ball's "up" as the landforms are.
			var rock: ShaderMaterial = demo._flat_mats().rock(0.0, 1.2).duplicate()
			var sp := ground.sphere()
			if sp != null:
				rock.set_shader_parameter("planet_center", sp.center)
				rock.set_shader_parameter("planet_radius", sp.radius)
				rock.set_shader_parameter("dusk_strength", 0.35)
			mi.material_override = rock
			# Both sides in the shadow pass, as the old double-sided sand cast (the
			# wedge has no bottom face, so front faces alone could leak light).
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
			add_child(mi)
			mi.global_transform = body.global_transform


## The house, the stall, the display pad, the garage and its bench, in the town's
## palette. Shapes from the location file (the garage piece by piece, the boxes it
## collides with); colours from docs/ART_DIRECTION.md (plaster, madder red).
## Issue #355: planks, red canvas and painted metal (StallTextures), and speeder
## parts on his counter.
func _dress(loc: Dictionary) -> void:
	var mats: LookMaterials = demo._flat_mats()
	var plaster := mats.plaster(origin.y, origin.y + 3.2, Color("#8e3a26"), Color("#d8c2a0"))
	var red := mats.painted(Color("#a8322a"), 0.7, 0.3)
	var red_cloth := mats.canvas(Color("#a8322a"))
	var wood := mats.wood(Color("#5a3a24"), 0.75)
	var metal := mats.painted(Color("#4a4c52"), 0.45, 0.6)
	for b in loc.get("buildings", []):
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var c := WorldGround._v3(b.get("position", [0, 0, 0]))     # local; _mesh turns it into the world
		match str(b.id):
			"house":
				_mesh(_box(s + Vector3(0, 1.0, 0)), plaster, c + Vector3(0, s.y * 0.5 - 0.5, 0))
				# A domed roof, a door toward the stall and a red awning over it.
				var dr := minf(s.x, s.z) * 0.42
				_mesh(_dome(dr), plaster, c + Vector3(0, s.y, 0))
				_dome_collider(c + Vector3(0, s.y, 0), dr)
				_mesh(_box(Vector3(0.12, 2.1, 1.3)), wood, c + Vector3(s.x * 0.5 + 0.02, 1.05, 2.2))
				_mesh(_box(Vector3(1.6, 0.08, 2.4)), red_cloth, c + Vector3(s.x * 0.5 + 0.8, 2.5, 2.2), Vector3(0, 0, -14))
				# Issue #458: a lamp under the awning, over the door.
				HangingLamp.build(self, _xf(), c + Vector3(s.x * 0.5 + 0.5, 2.15, 2.2), mats, _look(), "DoorLamp",
					float(DOOR_LAMP.energy), float(DOOR_LAMP.reach), LAMP_DAY, 0.2)
			"stall":
				_mesh(_box(s), wood, c + Vector3(0, s.y * 0.5, 0))
				_mesh(_box(Vector3(s.x + 0.3, 0.08, s.z + 0.3)), red, c + Vector3(0, s.y + 0.04, 0))
				# Posts and a red canopy over the counter and Skrugs.
				for dz in [-s.z * 0.5, s.z * 0.5]:
					_mesh(_cyl(0.06, 2.6), wood, c + Vector3(-1.2, 1.3, dz))
					_mesh(_cyl(0.06, 2.6), wood, c + Vector3(0.45, 1.3, dz))
				_mesh(_box(Vector3(2.2, 0.06, s.z + 0.6)), red_cloth, c + Vector3(-0.4, 2.62, 0), Vector3(0, 0, -8))
				_counter_wares(mats, c + Vector3(0, s.y + 0.08, 0), s, red, metal)
			"display_pad":
				_mesh(_box(s), metal, c + Vector3(0, s.y * 0.5, 0))
			"bench":
				_workbench(mats, c, s, wood, metal, red)
			_:
				if str(b.id).begins_with("garage_"):
					# Issue #295: back wall, two side walls and a red roof; one side stands open.
					_mesh(_box(s), red if str(b.id) == "garage_roof" else plaster, c + Vector3(0, s.y * 0.5, 0))
	_dress_garage(mats, loc, metal)


## Issue #458: his bench (the "bench" box, outside his garage in both layouts),
## dressed like Dorrin's: planks on painted metal, a vise at one end, the toolbox
## and coil it had (issue #295), a pegboard of tools standing behind it, on the
## far side from the `bench` point where the player stands, and a lamp on an arm
## off the pegboard over the bench. Look only.
func _workbench(mats: LookMaterials, c: Vector3, s: Vector3, wood: Material, metal: Material, red: Material) -> void:
	var dark := mats.painted(Color("#2b2c30"), 0.5, 0.6)
	var d: Vector3 = points.get("bench", c + Vector3(1, 0, 0)) - c
	var along_x := absf(d.x) >= absf(d.z)       # the player stands off the bench's x side (square port) or z side (round)
	var toward := Vector3(1.0 if d.x >= 0.0 else -1.0, 0, 0) if along_x else Vector3(0, 0, 1.0 if d.z >= 0.0 else -1.0)
	var across := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var depth := s.x if along_x else s.z        # the bench toward the player
	var width := s.z if along_x else s.x        # ... and along the pegboard
	_mesh(_box(s), metal, c + Vector3(0, s.y * 0.5, 0))
	_mesh(_box(Vector3(s.x + 0.1, 0.06, s.z + 0.1)), wood, c + Vector3(0, s.y + 0.03, 0))
	var top := c + Vector3(0, s.y + 0.06, 0)
	# The toolbox and the coil (#295), and a vise at the near end, its screw toward the player.
	_mesh(_box(Vector3(0.4, 0.3, 0.4)), red, top + Vector3(0, 0.15, 0))
	_mesh(_cyl(0.12, 0.3), metal, top + across * 0.6 + Vector3(0, 0.15, 0))
	var vise := top - across * (width * 0.5 - 0.35)
	_mesh(_box(Vector3(0.3, 0.25, 0.3)), dark, vise + Vector3(0, 0.125, 0))
	_mesh(_box(Vector3(0.34, 0.1, 0.34)), metal, vise + Vector3(0, 0.3, 0))
	var lay := Vector3(0, 0, 90) if along_x else Vector3(90, 0, 0)      # a cylinder laid along `toward`
	var bar := Vector3(90, 0, 0) if along_x else Vector3(0, 0, 90)      # ... and along `across`
	_mesh(_cyl(0.03, 0.4), metal, vise + toward * 0.25 + Vector3(0, 0.14, 0), lay)
	_mesh(_cyl(0.015, 0.22), metal, vise + toward * 0.44 + Vector3(0, 0.14, 0), bar)
	# The pegboard on two posts, and its tools.
	var board := c - toward * (depth * 0.5 + 0.12) + Vector3(0, s.y + 0.9, 0)
	var panel := _mesh(_box(Vector3(0.08, 1.6, width + 0.2) if along_x else Vector3(width + 0.2, 1.6, 0.08)),
		mats.wood(Color("#4a3a2a"), 0.9), board)
	panel.set_meta("decor", "workbench")
	for side: float in [-1.0, 1.0]:
		var post: Vector3 = Vector3(board.x, c.y + (s.y + 1.75) * 0.5, board.z) - toward * 0.06 + across * side * (width * 0.5 + 0.08)
		_mesh(_cyl(0.05, s.y + 1.75), wood, post)
	var rng := RandomNumberGenerator.new()
	rng.seed = 458
	var n := 9 if width > 2.0 else 5
	var step := (width - 0.3) / float(n - 1)
	for k in n:
		var h := rng.randf_range(0.3, 0.6)
		var tool := _mesh(_box(Vector3(0.04, h, 0.06) if along_x else Vector3(0.06, h, 0.04)), metal if k % 3 else red,
			board + toward * 0.06 + across * (-(width - 0.3) * 0.5 + k * step) + Vector3(0, 0.05 + rng.randf_range(-0.3, 0.3), 0),
			(Vector3(rng.randf_range(-23.0, 23.0), 0, 0) if along_x else Vector3(0, 0, rng.randf_range(-23.0, 23.0))))
		tool.set_meta("decor", "tool")
	# The lamp: an arm from the pegboard's top out over the bench, the lamp hanging from its end.
	var arm_y := c.y + s.y + 1.95
	var reach := depth * 0.5 + 0.12
	_mesh(_cyl(0.025, reach), metal, Vector3(board.x, arm_y, board.z) + toward * reach * 0.5, lay)
	HangingLamp.build(self, _xf(), Vector3(c.x, arm_y - 0.37, c.z), mats, _look(), "BenchLamp",
		float(BENCH_LAMP.energy), float(BENCH_LAMP.reach), LAMP_DAY, 0.2)


## String lights and fuel canisters in and around his garage (issue #435), and
## issue #458: a work light under the roof, a sign over the mouth and the hanging
## lamp over his counter, on the look's lamp clock. Placed from the garage and
## stall boxes, so it fits both layouts: the garage opens toward +x, its side
## walls run along x. Look only: no colliders, nothing on the way into the bay or
## behind the counter.
func _dress_garage(mats: LookMaterials, loc: Dictionary, metal: Material) -> void:
	var box := {}
	for b in loc.get("buildings", []):
		box[str(b.id)] = { "c": WorldGround._v3(b.get("position", [0, 0, 0])), "s": WorldGround._v3(b.get("size", [1, 1, 1])) }
	if not (box.has("garage_back") and box.has("garage_side_a") and box.has("garage_side_b") and box.has("garage_roof") and box.has("stall")):
		return
	var back: float = box.garage_back.c.x + box.garage_back.s.x * 0.5          # inside face of the back wall
	var mouth: float = box.garage_side_a.c.x + box.garage_side_a.s.x * 0.5     # the open end
	var za: float = box.garage_side_a.c.z
	var zb: float = box.garage_side_b.c.z
	var wall: float = box.garage_side_a.s.z * 0.5
	var lo := minf(za, zb) + wall                                               # inside faces of the side walls
	var hi := maxf(za, zb) - wall
	var roof: float = box.garage_roof.c.y
	var stall: Vector3 = box.stall.c
	var ss: Vector3 = box.stall.s
	# The side wall nearer the stall, and which way its outside faces.
	var near_z := za if absf(stall.z - za) < absf(stall.z - zb) else zb
	var out := signf(stall.z - near_z)
	var out_face := near_z + out * wall

	var strands: Array = [
		# Inside: two runs under the roof, back wall to mouth, and one across the mouth.
		[Vector3(back + 0.3, roof - 0.25, lo + 0.6), Vector3(mouth - 0.3, roof - 0.25, lo + 0.6), 0.3],
		[Vector3(back + 0.3, roof - 0.25, hi - 0.6), Vector3(mouth - 0.3, roof - 0.25, hi - 0.6), 0.3],
		[Vector3(mouth - 0.2, roof - 0.15, lo + 0.1), Vector3(mouth - 0.2, roof - 0.15, hi - 0.1), 0.35],
		# Outside: along the mouth's lip, from its corner out to the stall's canopy,
		# and along the canopy's low front edge over the customer.
		[Vector3(mouth + 0.05, roof - 0.05, lo - 0.2), Vector3(mouth + 0.05, roof - 0.05, hi + 0.2), 0.45],
		[Vector3(mouth + 0.05, roof - 0.05, out_face), stall + Vector3(0.45, 2.5, -out * ss.z * 0.5), 0.6],
		[stall + Vector3(0.7, 2.42, -ss.z * 0.5 - 0.3), stall + Vector3(0.7, 2.42, ss.z * 0.5 + 0.3), 0.15],
	]
	var cable := mats.flat(Color("#2b2522"), 0.7)
	var bulbs: Array[Vector3] = []
	for st in strands:
		var a: Vector3 = st[0]
		var b: Vector3 = st[1]
		var n := maxi(4, int(a.distance_to(b) / 0.6))
		var pts := LookMeshKit.catenary(a, b, float(st[2]), n)
		_mesh(LookMeshKit.tube(pts, 0.015, 4), cable, Vector3.ZERO)
		for k in range(1, pts.size() - 1):
			bulbs.append(pts[k] + Vector3(0, -0.08, 0))
	var bulb := mats.glow(Color("#ffd27a"))
	HangingLamp.track_glow(bulb, _look(), LAMP_DAY)      # on by day, full at dusk
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _ball(0.07)
	mm.instance_count = bulbs.size()
	for i in bulbs.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, bulbs[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GarageBulbs"
	mmi.multimesh = mm
	mmi.material_override = bulb
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	mmi.global_position = origin
	mmi.rotation.y = yaw

	# Canisters: along the back wall and the side walls' back halves inside (the
	# bay's speeder stays clear), a stack by the mouth outside the wall nearer the
	# stall, and two behind Skrugs. Seeded, so the yard looks the same every visit.
	var paints := [CampTextures.canister(Color("#a8322a"), Color("#d8c2a0")), CampTextures.canister(Color("#3a8a8a"), Color("#d8c2a0")),
		CampTextures.canister(Color("#c8a040"), Color("#2b2c30")), metal]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var spots: Array[Vector3] = []
	for k in 5:
		spots.append(Vector3(back + 0.4 + rng.randf_range(0.0, 0.25), 0, lerpf(lo + 0.7, hi - 0.7, k / 4.0)))
	for z in [lo + 0.4, hi - 0.4]:
		for k in 2:
			spots.append(Vector3(back + 1.3 + k * 0.7, 0, z))
	for k in 4:
		spots.append(Vector3(mouth - 0.4 - k * 0.6, 0, out_face + out * (0.4 + (k % 2) * 0.35)))
	for dz in [-ss.z * 0.5 + 0.2, ss.z * 0.5 - 0.2]:
		spots.append(stall + Vector3(-1.6, 0, dz))
	for i in spots.size():
		var tall := rng.randf_range(0.55, 0.9)
		var r := 0.22 if tall > 0.7 else 0.18
		var can := _cyl(r, tall)
		can.radial_segments = 12
		var m := _mesh(can, paints[i % paints.size()], spots[i] + Vector3(0, tall * 0.5, 0))
		m.rotation.y += rng.randf() * TAU
		_mesh(_cyl(0.05, 0.08), metal, spots[i] + Vector3(r * 0.4, tall + 0.04, 0))     # the cap
	# One knocked over by the outside stack.
	var down := spots[spots.size() - 3] + Vector3(-0.9, 0.2, out * 0.2)
	_mesh(_cyl(0.2, 0.7), paints[0], down, Vector3(90, 0, 0))

	# The lamp hanging from the canopy over the counter, between Skrugs and the
	# customer (issue #435; #458: on the lamp clock, never off).
	HangingLamp.build(self, _xf(), stall + Vector3(0.1, 2.25, 0), mats, _look(), "StallLamp",
		float(STALL_LAMP.energy), float(STALL_LAMP.reach), LAMP_DAY)

	# Issue #458: the work light, a strip fixture under the roof over the bay, so
	# the speeder inside (and the bench, by the wall) is lit.
	var fixture := mats.painted(Color("#2b2c30"), 0.5, 0.6)
	var mid := Vector3((back + mouth) * 0.5, roof - 0.12, (lo + hi) * 0.5)
	_mesh(_box(Vector3(1.2, 0.1, 0.3)), fixture, mid)
	var strip := mats.glow(Color("#fff0d0"))
	_mesh(_box(Vector3(1.1, 0.03, 0.22)), strip, mid + Vector3(0, -0.06, 0))
	HangingLamp.light(self, _xf(), mid + Vector3(0, -0.5, 0), _look(), "GarageLight",
		float(GARAGE_LIGHT.energy), float(GARAGE_LIGHT.reach), LAMP_DAY, strip)
	# The sign over the mouth: a teal glow tube on a dark backing, like Dorrin's.
	var w := (hi - lo) * 0.55
	_mesh(_box(Vector3(0.2, 0.5, w + 0.3)), fixture, Vector3(mouth + 0.12, roof - 0.5, (lo + hi) * 0.5))
	var tube := mats.glow(Color("#7fe0d0"))
	HangingLamp.track_glow(tube, _look(), LAMP_DAY)
	_mesh(_box(Vector3(0.1, 0.12, w)), tube, Vector3(mouth + 0.25, roof - 0.5, (lo + hi) * 0.5))


## Issue #355: what Skrugs deals in, on his counter (`top`: the middle of its top,
## post frame; the customer is +x): a thruster nozzle, two fuel canisters, a red
## toolbox and a coil, and his items (content/look/items.json "stalls" > "skrugs")
## at the far end.
func _counter_wares(mats: LookMaterials, top: Vector3, s: Vector3, red: Material, metal: Material) -> void:
	var dark := mats.painted(Color("#2b2c30"), 0.5, 0.6)
	var nozzle := CylinderMesh.new()
	nozzle.top_radius = 0.09
	nozzle.bottom_radius = 0.17
	nozzle.height = 0.5
	nozzle.radial_segments = 12
	_mesh(nozzle, dark, top + Vector3(-0.05, 0.17, -s.z * 0.5 + 0.45), Vector3(90, 0, 0))
	_mesh(_cyl(0.13, 0.06), metal, top + Vector3(-0.05, 0.17, -s.z * 0.5 + 0.72), Vector3(90, 0, 0))
	for k in 2:
		var can := _cyl(0.1, 0.34)
		_mesh(can, CampTextures.canister(Color("#a8322a"), Color("#d8c2a0")), top + Vector3(-0.15 + k * 0.08, 0.17, -0.35 + k * 0.24))
	_mesh(_box(Vector3(0.28, 0.2, 0.5)), red, top + Vector3(-0.12, 0.1, 0.45))
	_mesh(_box(Vector3(0.3, 0.03, 0.06)), dark, top + Vector3(-0.12, 0.22, 0.45))
	var coil := TorusMesh.new()
	coil.inner_radius = 0.05
	coil.outer_radius = 0.08
	for k in 4:
		_mesh(coil, metal, top + Vector3(0.18, 0.015 + k * 0.03, 0.05))
	var kit := ItemKit.new(mats)
	var z := s.z * 0.5 - 0.15
	for l in ItemKit._read_json(ItemKit.LOOKS_PATH).get("stalls", {}).get("skrugs", {}).get("items", []):
		if not kit.has_look(str(l)):
			continue
		var item := kit.build(str(l))
		var turn := Basis(Vector3.UP, -PI * 0.5)    # a case's latch (-Z) to the customer (+x)
		var b := ItemKit.bounds(item, Transform3D(turn, Vector3.ZERO))
		if z - b.size.z < 0.8:
			item.free()
			break
		var local := top + Vector3(-b.get_center().x, -b.position.y, z - b.end.z)
		add_child(item)
		item.global_transform = Transform3D(Basis(Vector3.UP, yaw) * turn, origin + local.rotated(Vector3.UP, yaw))
		item.set_meta("decor", "stall_item")
		z -= b.size.z + 0.08


## A mesh at a point in the post's own frame (turned and placed into the world).
func _mesh(mesh: Mesh, mat: Material, local: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.global_position = origin + local.rotated(Vector3.UP, yaw)
	mi.rotation_degrees = rot_deg + Vector3(0, rad_to_deg(yaw), 0)
	return mi


func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	return s


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c


## A cylinder collider under the dome cap, at the house's roof height. `cap` is
## the dome's base, in the post's own frame (turned into the world like `_mesh`).
func _dome_collider(cap: Vector3, r: float) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = r
	cs.shape = shape
	cs.transform = Transform3D(Basis.IDENTITY, Vector3(0, r * 0.5, 0))
	body.add_child(cs)
	add_child(body)
	# The cylinder is symmetric about its axis, so only its position matters; place
	# it where the dome cap sits in the world.
	body.global_position = origin + cap.rotated(Vector3.UP, yaw)


func _dome(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r
	s.is_hemisphere = true
	s.radial_segments = 20
	s.rings = 8
	return s
