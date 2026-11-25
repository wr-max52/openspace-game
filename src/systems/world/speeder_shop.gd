class_name SpeederShop
extends Node
## Issue #295: a speeder parts shop, the one Dorrin Vask ran alone (issue #95),
## now shared: Dorrin at his yard in the desert (MechanicYard) and, in free roam,
## Skrugs at his garage bench (SpeederPost). One menu, one price list.
##
##   talk()  -- [E] at the counter or bench: the menu (paint, looks, performance,
##              the Grav Lifter, selling the speeder for scrap), or "bring one
##              round" with no speeder in the bay.
##
## A shop with "sells_speeders" (Dorrin's, not Skrugs's bench) also sells every
## model Skrugs does, at his prices, one of each to a customer whoever sold it
## ("Buy a speeder", there with or without a speeder in the bay; buy_speeder).
## The new one waits in the row outside the town's back gate, like all new ones.
##
## It only works on a speeder of yours parked in its bay (within bay_radius of the
## bay point). Parts are paid for here and fitted at once (SpeederPost.refit
## rebuilds the speeder where it stands). The fit is saved per speeder
## (WorldState.speeder_fits). Words, prices and parts:
## content/core/vehicles/speeder_upgrades.json (SpeederUpgrades.shop).
##
## The headless tests call talk(), buy(), scrap() and the menu's choose() directly:
## the same code paths as the keys.

const NpcVoiceT := preload("res://src/systems/voice/npc_voice.gd")


## The NpcVoice autoload (issue #545: named through a preload, see get_singleton).
static func _voice() -> NpcVoiceT:
	return NpcVoiceT.get_singleton()


var demo                              ## town_demo.gd (its speeder_post owns the speeders)
var gear: GearController              ## for its HUD (toasts)
var player: CharacterBody3D
var cfg: Dictionary = {}              ## SpeederUpgrades.shop(id): name, bay_radius, voice, lines, labels
var bay: Callable                     ## () -> Vector3: the bay, in the world
var speaker: Node3D                   ## who says the lines (his voice comes from there), may be null
var speeders_sold := 0                ## speeders sold here this session (tests, traces)
var menu: DroidMenu
var said := ""                        ## the last line, for tests
var fitted := 0                       ## parts sold this session (tests, traces)
var _was_locked := false


func setup(p_demo, p_gear: GearController, p_cfg: Dictionary, p_bay: Callable) -> void:
	demo = p_demo
	gear = p_gear
	cfg = p_cfg
	bay = p_bay
	player = demo._player if demo != null and "_player" in demo else null
	name = "SpeederShop"
	menu = DroidMenu.new()
	add_child(menu)
	menu.option_selected.connect(_on_option_selected)


func npc_name() -> String:
	return str(cfg.get("name", "the mechanic"))


## Issue #615: the name of race crew `crew`'s leader (the name engine's), for
## "beat <leader> of the basin crew".
func crew_leader(crew: String) -> String:
	if demo != null and "race_crews" in demo:
		for rc in demo.race_crews:
			if is_instance_valid(rc) and rc.id == crew:
				return rc.leader_name()
	return label("crew_leader_unknown")


func label(key: String) -> String:
	return str(cfg.get("labels", {}).get(key, key))


func _line(key: String) -> String:
	return str(cfg.get("lines", {}).get(key, ""))


## True while the menu is up. Once it closes, the player it locked is let go.
func busy() -> bool:
	if menu.is_open():
		return true
	if _was_locked and player != null:
		player.locked = false
		_was_locked = false
	return false


# ------------------------------------------------------------------ the bay

## Your speeder parked in the bay (the nearest one to it), or null.
func speeder_in_bay() -> SpeederNode:
	var post: SpeederPost = demo.speeder_post if demo != null and "speeder_post" in demo else null
	if post == null or not bay.is_valid():
		return null
	var at: Vector3 = bay.call()
	var best: SpeederNode = null
	var best_d := float(cfg.get("bay_radius", 16.0))
	for s in post.speeders:
		if not is_instance_valid(s) or s.riding:
			continue
		var d: float = s.model.position.distance_to(at)
		if d <= best_d:
			best = s
			best_d = d
	return best


func _fit(s: SpeederNode) -> Dictionary:
	return demo.speeder_post.fit_for(int(s.get_meta("slot", 0)))


# ------------------------------------------------------------------ the menu

## [E]: the top menu, or "bring one round" with no speeder in the bay (a shop
## that sells speeders opens its menu all the same, with only that in it).
func talk() -> void:
	var s := speeder_in_bay()
	if s == null and not sells_speeders():
		_say(_line("no_speeder"))
		return
	_open(_line("hello") if s != null else _line("no_speeder"), top_options(), _on_top)


## This shop sells speeders too (Dorrin's), and there is a post to sell them from.
func sells_speeders() -> bool:
	return bool(cfg.get("sells_speeders", false)) and _post() != null


func _post() -> SpeederPost:
	return demo.speeder_post if demo != null and "speeder_post" in demo else null


func top_options() -> Array:
	var s := speeder_in_bay()
	if s == null:
		return [{ "id": "speeders", "text": label("menu_speeders") }] if sells_speeders() else []
	var fit := _fit(s)
	# Issue #627: only the groups this model takes (the racer and the box truck: paint).
	var model := SpeederUpgrades.model_of(fit)
	var groups := SpeederUpgrades.groups_for(model)
	var opts := []
	for g in ["paint", "looks", "performance", "race"]:   # issue #616: race gear
		if groups.has(g):
			opts.append({ "id": "group:" + g, "text": label("menu_" + g) })
	for p in SpeederUpgrades.in_group_for("lifter", model):
		opts.append(_row(fit, p))
	opts.append({ "id": "scrap", "text": label("menu_scrap") % SpeederUpgrades.scrap_value(fit) })
	if sells_speeders():
		opts.append({ "id": "speeders", "text": label("menu_speeders") })
	return opts


func group_options(group: String) -> Array:
	var s := speeder_in_bay()
	if s == null:
		return []
	var fit := _fit(s)
	var out: Array = []
	for p in SpeederUpgrades.in_group_for(group, SpeederUpgrades.model_of(fit)):
		out.append(_row(fit, p))
	if out.is_empty():
		out.append({ "id": "back", "text": label("menu_nothing") })    # issue #627: none made for her yet
	out.append({ "id": "back", "text": label("back") })
	return out


func _row(fit: Dictionary, p: Dictionary) -> Dictionary:
	var id := str(p.get("id", ""))
	var why := SpeederUpgrades.why_not(fit, id)
	var text := label("buy") % [str(p.get("label", id)), int(p.get("price", 0))]
	var crew := SpeederUpgrades.locked_by(id)
	if crew != "" and why != "owned":
		text = label("crew_locked") % [str(p.get("label", id)), int(p.get("price", 0)), crew_leader(crew),
			str(RaceCrew.load_crew(crew).get("label", crew))]
	elif why == "owned":
		text = label("owned") % str(p.get("label", id))
	elif why.begins_with("needs:"):
		text = label("locked") % [str(p.get("label", id)), int(p.get("price", 0)),
			str(SpeederUpgrades.part(why.substr(6)).get("label", why.substr(6)))]
	return { "id": "buy:" + id, "text": text }


func _on_top(id: String) -> void:
	if id == "speeders":
		_open(_line("speeders_hello"), speeder_options(), _on_speeders)
	elif id.begins_with("group:"):
		var g := id.substr(6)
		_open(_line("hello"), group_options(g), _on_group.bind(g))
	elif id.begins_with("buy:"):
		buy(id.substr(4))
		_reopen(top_options(), _on_top)
	elif id == "scrap":
		var s := speeder_in_bay()
		if s != null:
			_open(label("confirm_scrap") % SpeederUpgrades.scrap_value(_fit(s)),
				[{ "id": "yes", "text": label("yes_scrap") }, { "id": "no", "text": label("no_scrap") }], _on_scrap)


func _on_group(id: String, group: String) -> void:
	if id == "back":
		talk()
	elif id.begins_with("buy:"):
		buy(id.substr(4))
		_reopen(group_options(group), _on_group.bind(group))


## After a buy: the same menu again, with what was said and the new prices, the
## cursor where it was. Esc walks away.
func _reopen(opts: Array, pick: Callable) -> void:
	if speeder_in_bay() != null:
		menu.open(label("menu_title") % [npc_name(), WorldState.credits], opts, pick, said, true)


# ------------------------------------------------------------------ selling speeders

## One row per model Skrugs sells (his card's sale.models): its name and price,
## or "you have one" once they own one; then Back.
func speeder_options() -> Array:
	var post := _post()
	if post == null:
		return []
	var out: Array = []
	for m in post.models():
		var mid := str(m.get("id", ""))
		var name := str(HoverModel.load_config(mid).get("label", m.get("name", mid)))
		if post.at_limit(mid):
			out.append({ "id": "have:" + mid, "text": label("speeder_owned") % name })
		else:
			out.append({ "id": "speeder:" + mid, "text": label("buy") % [name, int(m.get("price", 0))] })
	out.append({ "id": "back", "text": label("back") })
	return out


func _on_speeders(id: String) -> void:
	if id == "back":
		talk()
		return
	if id.begins_with("speeder:"):
		buy_speeder(id.substr(8))
	elif id.begins_with("have:"):
		_say(_line("have_one"))
	menu.open(label("menu_title") % [npc_name(), WorldState.credits], speeder_options(), _on_speeders, said, true)


## Sell them a new speeder of `model` at Skrugs's price; it waits in the row
## outside the back gate (SpeederPost.sell_speeder).
## Returns "bought", "owned", "cant_afford" or "unknown".
func buy_speeder(model: String) -> String:
	var post := _post()
	if not sells_speeders() or post.model_sale(model).is_empty():
		return "unknown"
	if post.at_limit(model):
		_say(_line("have_one"))
		return "owned"
	if WorldState.credits < int(post.model_sale(model).get("price", 0)):
		_say(_line("too_poor"))
		return "cant_afford"
	if post.sell_speeder(model, label("event_sold_speeder")) == null:
		return "unknown"
	speeders_sold += 1
	_say(_line("sold_speeder"))
	return "bought"


func _on_scrap(id: String) -> void:
	if id == "yes":
		scrap()
	else:
		talk()


# ------------------------------------------------------------------ trade

## Buy part `id` for the speeder in the bay and fit it now. Returns "bought",
## "cant_afford", "no_speeder", "owned", "needs:<part>" or "unknown".
func buy(id: String) -> String:
	var s := speeder_in_bay()
	if s == null:
		_say(_line("no_speeder"))
		return "no_speeder"
	var fit := _fit(s)
	var why := SpeederUpgrades.why_not(fit, id)
	if why != "":
		return why
	var crew := SpeederUpgrades.locked_by(id)
	if crew != "":
		_say(label("crew_locked_say") % [crew_leader(crew), str(RaceCrew.load_crew(crew).get("label", crew))])
		return "crew:" + crew
	var p := SpeederUpgrades.part(id)
	var price := int(p.get("price", 0))
	if WorldState.credits < price:
		_say(_line("too_poor"))
		return "cant_afford"
	WorldState.credits -= price
	SpeederUpgrades.fit_part(fit, id)
	fitted += 1
	WorldState.log_event(label("event_bought") % str(p.get("label", id)).to_lower())
	demo.speeder_post.refit(s)
	_say(_line("bought"))
	return "bought"


## Sell the speeder in the bay for scrap. Returns the credits paid (0 = none there).
func scrap() -> int:
	var s := speeder_in_bay()
	if s == null:
		_say(_line("no_speeder"))
		return 0
	var pay := SpeederUpgrades.scrap_value(_fit(s))
	WorldState.credits += pay
	demo.speeder_post.remove(s)
	WorldState.log_event(label("event_scrapped"))
	_say(_line("scrapped"))
	return pay


# ------------------------------------------------------------------ talking

func _open(text: String, opts: Array, pick: Callable) -> void:
	said = text
	menu.open(label("menu_title") % [npc_name(), WorldState.credits], opts, pick, text)
	_speak(text)
	if player != null and not player.locked:
		player.locked = true
		_was_locked = true


func _say(text: String) -> void:
	said = text
	if gear != null and gear.hud != null and text != "":
		gear.hud.toast("%s: %s" % [npc_name(), text], 4.5)
	_speak(text)


func _speak(text: String) -> void:
	if speaker != null and is_instance_valid(speaker):
		_voice().speak(text, _voice().profile_for_npc(str(cfg.get("voice", "mechanic")), {}), "warm", speaker)


func _on_option_selected(_id: String) -> void:
	if speaker != null and is_instance_valid(speaker):
		_voice().stop(speaker)
