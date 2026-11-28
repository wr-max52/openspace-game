class_name DevSettingsPanel
extends CanvasLayer
## F11 in the town: the game's settings. Opening it pauses the game and frees
## the mouse; closing it resumes and saves (when the bar saves). Six pages:
##   Map       a globe of the planet with every place that stays put, you and the
##             waypoint, click one for a waypoint; the places off planet beside it
##             (GlobeMap; M opens it)
##   Ledger    what you own on the left, the story and your jobs on the right, each
##             with a waypoint button (InventoryPanel; I opens it)
##   Game      respawn (back where you started), the main story's chapter (issue
##             #64), time of day, a sandstorm now (#175), game speed, credits, the space fight switch, the
##             home town's layout, new game
##   Player    the outfit from the kit pieces (CharacterBuilder, issue #48), then
##             god mode, heal, jetpack, teleport and guard debug
##   Standing  faction standing, each individual's trust / mood / tab, and every
##             world flag the content reads
##   Options   the HUD's colour (issue #52) and text size (issue #71), volume
##             (issue #16), indirect light, the AI characters' brain (issue #80)
##             and every key
##
## Everything writes to the same places the game does (WorldState, the npc's
## Relationship, the look), so the cantina owner, rumors and checkpoint react as if
## it had happened in play.
##
## A story save earns what free roam hands out: there the controls that would give
## it (credits, the space fight switch, standing and trust, god mode, heal, the
## jetpack, endless fuel, teleport, guard senses, flags) are greyed out, each page
## saying why. Game speed, the look, HUD, sound, the AI brain and the smuggler's
## own outfit stay the player's. A stuck player may still skip ahead a chapter,
## after a warning that points them at the characters first.

const MOODS := ["wary", "warm", "amused", "irritated"]
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]
const TownLayoutScript := preload("res://src/systems/world/town_layout.gd")

var demo                              ## town_demo.gd
var _panel: PanelContainer
var tabs: TabContainer               ## issue #80: open_tab() picks one by title
var _was_mouse := Input.MOUSE_MODE_VISIBLE
var _refreshers: Array[Callable] = []  ## each puts the live value back into its control
var _hour: HSlider
var _hour_label: Label
var _flags_box: VBoxContainer
var _flag_new: LineEdit
var builder: CharacterBuilder
var _make_builder: Callable    ## issue #696: builds the Player page's preview
var _builder_in := -1          ## frames until it is built (-1: not waiting)
var _god := false
var _endless_fuel := false
var _cheats: Array[Control] = []       ## greyed out in a story save (_lock_for_story)
var _story_notes: Array[Control] = []  ## shown only in a story save
var skip_confirm: ConfirmationDialog   ## a story save asks before skipping a chapter
var _skip_to := ""
var _anchors: Dictionary = {}          ## a name open_tab knows -> the section label it scrolls to
var globe: GlobeView                   ## the Map page's globe
var cruiser_view: CruiserMapView       ## the Map page's side view of the cruiser
var station_view: StationMapView       ## the Map page's side view of a space station
var system_view: SystemView            ## the Map page's chart of the star system
var _map_view := ""                    ## what the Map page shows: "" here, a planet id, "cruiser:<planet>", "station:<planet>" or "system"
var _details: Array = []               ## the globe's footprints (_map_details), kept while _details_key holds
var _details_key := ""
var _map_auto_zoomed := false          ## the page zoomed in on the town itself when it opened there
var _map_title: Label
var _map_back: Button
var _map_you: Button
var _map_home: Button
var _off_planet: Array = []            ## GlobeMap.off_planet, last refresh
var _off_box: VBoxContainer
var _map_note: Label
var _no_globe: Label
var _map_page: Control
## The cruiser's row flashes when it changes hands, like its pin on the holo:
## who held it when the Map page last looked ("?" = not looked yet), whether it
## changed since (the flash waits for the page to be open), and when the flash ends.
var _cruiser_seen := "?"
var _cruiser_changed := false
var _cruiser_flash_end := 0
var _cruiser_icon: Control
var _cruiser_poll := 0.0
var _static_pins: Array = []           ## the globe's pins that stay put (GlobeMap.pins), last refresh; the vehicles go on top
var _legend: Array = []                ## the legend's rows: [{ button, text, kind | test | special }]
var _veh_left := 0.0                   ## seconds before the Map page moves the vehicles again (vehicle_refresh_s)
var inventory: InventoryPanel          ## the Ledger page

const STUCK_WARNING := "If you are stuck, ask the interactive NPCs for advice, they may have a hint.\n\nAre you sure?"


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_fit()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.06, 0.96)
	sb.border_color = Color("#b08e50")
	sb.set_border_width_all(1)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 14)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var title := Label.new()
	title.text = "Settings  [F11]"
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	var h := HBoxContainer.new()
	v.add_child(h)
	for b in [["Save now", _save], ["Close", close]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		h.add_child(btn)
	visible = false


## The pages themselves, made the first time the panel opens (issue #121: they cost
## about a second to build, on every arrival, for a panel most visits never open).
var tabs_built := false


func _build_tabs() -> void:
	if tabs_built:
		return
	tabs_built = true
	tabs.add_child(_map_tab())
	tabs.add_child(_inventory_tab())
	var game := _tab("Game")
	_respawn_page(game)
	_lan_page(game)
	_saves_page(game)
	_story_page(game)
	_world_page(game)
	_new_game_page(game)
	tabs.add_child(game.get_parent())
	var player := _tab("Player")
	_character_page(player)
	_player_page(player)
	tabs.add_child(player.get_parent())
	var standing := _tab("Standing")
	_standing_page(standing)
	_flags_page(standing)
	tabs.add_child(standing.get_parent())
	var options := _tab("Options")
	_hud_page(options)
	_sound_page(options)
	_graphics_page(options)
	_llm_page(options)
	_keys_page(options)
	tabs.add_child(options.get_parent())


## _input, not _unhandled_input: a focused slider or text field must not swallow F11.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			close()
			get_viewport().set_input_as_handled()


## M opens the Map page, I (the inventory action) the Ledger page; the same key
## again shuts the panel, the other one swaps pages. Unhandled: typing an M or an I
## in a text box is not this.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var page := ""
	if event.keycode == KEY_M:
		page = "Map"
	elif event.is_action_pressed("inventory"):
		page = "Ledger"
	if page == "":
		return
	if visible and tabs.get_tab_title(tabs.current_tab) == page:
		close()
	else:
		open_tab(page)
	get_viewport().set_input_as_handled()


## Issue #80: the cursor shows on every page while the settings are open, whatever
## else (a click in the world, a tab's own controls) tried to capture it.
func _process(_dt: float) -> void:
	if visible and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if visible and _lan_refresh.is_valid():
		_lan_refresh.call()          # players come and go while the panel is open
	_watch_cruiser(_dt)
	_watch_vehicles(_dt)
	_tick_builder()


## While the Map page shows the planet you are on, the vehicles (and you) move on
## it every vehicle_refresh_s seconds: a ship flying itself to you, a speeder, the
## Remnant's interceptor.
func _watch_vehicles(dt: float) -> void:
	if not _map_open() or _map_view != "":
		_veh_left = 0.0
		return
	_veh_left -= dt
	if _veh_left <= 0.0:
		_veh_left = float(GlobeMap.cfg().get("vehicle_refresh_s", 2.0))
		_refresh_vehicles()


## Who holds the cruiser, checked every owners.refresh_s (as the holo does). A
## change marks the Map page's cruiser row to flash for owners.flash_s, starting
## when the page is open: straight away if it is, else the next time it opens.
func _watch_cruiser(dt: float) -> void:
	_cruiser_poll -= dt
	if _cruiser_poll <= 0.0:
		var ow: Dictionary = GlobeMap.look().get("owners", {})
		_cruiser_poll = float(ow.get("refresh_s", 0.5))
		var who := CruiserHolo.owner_of(CruiserHolo.CRUISER)
		if _cruiser_seen == "?":
			_cruiser_seen = who
		elif who != _cruiser_seen:
			_cruiser_seen = who
			_cruiser_changed = true
			if _map_open():
				_refresh_map()
	if _cruiser_icon != null and is_instance_valid(_cruiser_icon) and cruiser_flash() > 0.0:
		_cruiser_icon.queue_redraw()


func _map_open() -> bool:
	return visible and tabs != null and _map_page != null and tabs.get_current_tab_control() == _map_page


## How white the cruiser's row is right now (0 = its own colour), pulsing twice a
## second while it flashes, as the holo's pin does.
func cruiser_flash() -> float:
	var left := (_cruiser_flash_end - Time.get_ticks_msec()) / 1000.0
	if left <= 0.0:
		return 0.0
	return 0.7 * (0.5 + 0.5 * sin(left * TAU * 2.0))


func _physics_process(_dt: float) -> void:
	# The game is paused while the panel is open, but a ship you called keeps
	# flying to you while the Map page is open, so it can watch her come.
	var pilot = demo.get("pilot") if demo != null and is_instance_valid(demo) else null
	if pilot != null and is_instance_valid(pilot) and pilot.calling and _map_open():
		pilot.call_tick(_dt)
	var p = _player()
	if p == null:
		return
	if WorldState.story_mode():
		return
	if _god:
		p.invulnerable_left = maxf(p.invulnerable_left, 1.0)
	if _endless_fuel and p.jetpack != null:
		p.jetpack.fuel = p.jetpack.fuel_max()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Issue #80: open on a page by its title, or on the page holding a section
## anchored by that name ("LLM": F10 lands on Options, scrolled to the AI brain).
func open_tab(title: String) -> void:
	open()
	var at: Control = _anchors.get(title, null)
	for i in tabs.get_tab_count():
		var page := tabs.get_tab_control(i)
		if tabs.get_tab_title(i) == title or (at != null and page.is_ancestor_of(at)):
			tabs.current_tab = i
			if at != null and page is ScrollContainer:
				var scroll := page as ScrollContainer
				(func():
					if is_instance_valid(scroll) and is_instance_valid(at):
						scroll.ensure_control_visible(at)).call_deferred()
			return


func open() -> void:
	if visible:
		return
	_build_tabs()
	_fit()
	visible = true
	_was_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _was_mouse
	_save()


## The panel's size: SIZE, or the window less a margin when that is smaller (a
## big text size on a small window), so the tabs and the buttons stay on screen.
const SIZE := Vector2(760, 620)


func _fit() -> void:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else SIZE
	var half := Vector2(minf(SIZE.x, vp.x - 24.0), minf(SIZE.y, vp.y - 24.0)) * 0.5
	_panel.offset_left = -half.x
	_panel.offset_right = half.x
	_panel.offset_top = -half.y
	_panel.offset_bottom = half.y


## Pull every control back from the live game (it changes while the panel is shut).
func refresh() -> void:
	if not tabs_built:
		return                      # nothing to refresh until the pages exist
	for r in _refreshers:
		r.call()
	_rebuild_flags()
	_lock_for_story()


## Grey out every control a story save has to earn in play, and show each page's
## note saying so; free roam gets them all back.
func _lock_for_story() -> void:
	var locked := WorldState.story_mode()
	for c in _cheats:
		if c is BaseButton:
			c.disabled = locked
		else:
			c.set("editable", not locked)   # sliders, spin boxes, line edits
	for n in _story_notes:
		n.visible = locked


## Register a control _lock_for_story greys out in a story save. Returns it.
func _cheat(c: Control) -> Control:
	_cheats.append(c)
	return c


## A page's line on what a story save keeps for play, hidden in free roam.
func _story_note(v: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = "Story save: " + text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	l.visible = false
	v.add_child(l)
	_story_notes.append(l)


# ------------------------------------------------------------------ inventory

## The Ledger, wired to the town's gear (its item names and wear toggle). Rebuilt
## on open and whenever the page is picked (a cheat on the Player page may have
## just handed you the jetpack); a waypoint picked there moves the HUD's pointer.
func _inventory_tab() -> Control:
	var gear = demo.get("gear") if demo != null else null
	inventory = gear.inventory_page() if gear != null else InventoryPanel.new()
	inventory.on_waypoint = _hud_refresh
	var pilot = demo.get("pilot") if demo != null else null
	if pilot != null:
		# Issue #368: your ships: pick the primary, call her (the panel closes to watch).
		inventory.set_primary = pilot.set_primary
		inventory.call_ship = pilot.call_ship
		inventory.call_state = pilot.call_state
		inventory.on_called = close
		inventory.on_renamed = pilot.refresh_vessel_name   # issue #835: the HUD shows the new name
	# Your speeders: Call brings one to you (SpeederPost.call_speeder). Looked up
	# when pressed: the post is built after this page, and only on the home planet.
	inventory.call_speeder = func(slot: int) -> String:
		var post = demo.get("speeder_post") if demo != null else null
		return post.call_speeder(slot) if post != null else "call_away"
	inventory.speeder_call_state = func(slot: int) -> Dictionary:
		var post = demo.get("speeder_post") if demo != null else null
		return post.call_state(slot) if post != null else { "ok": false, "text": SpeederPost.call_label("call_away") }
	# A laser droid's Lasers and Music buttons (DroidController), looked up when pressed.
	inventory.toggle_lasers = func(uid: int) -> bool:
		var dc = demo.get("droids") if demo != null else null
		return dc.toggle_lasers(uid) if dc != null else WorldState.droids.set_lasers(uid, not DroidRoster.lasers_on(WorldState.droids.find(uid)))
	inventory.cycle_station = func(uid: int) -> String:
		var dc = demo.get("droids") if demo != null else null
		if dc != null:
			return dc.cycle_station(uid)
		return WorldState.droids.set_station(uid, DroidRoster.next_station(DroidRoster.laser_station(WorldState.droids.find(uid))))
	if not inventory.on_called.is_valid():
		inventory.on_called = close
	_refreshers.append(inventory.refresh)
	tabs.tab_changed.connect(func(i):
		if tabs.get_tab_control(i) == inventory:
			inventory.refresh())
	return inventory


func _hud_refresh() -> void:
	if demo != null and demo.get("objective_hud") != null:
		demo.objective_hud.refresh()


# ------------------------------------------------------------------ map

## The globe (GlobeView) with the places that stay put, and beside it the star
## system and its planets, a legend, and the waypoint's own buttons. Not a scroll
## page: the wheel zooms the globe. Clicking a planet opens its own map in the same
## spot (another planet's globe, the system's chart: SystemView, or the cruiser's
## side view: CruiserMapView), with a button back to the page's own view; a
## waypoint set there stays on that planet. The page opens on the planet you are
## on, or on the system's chart when you are out in space (_map_home_view).
func _map_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Map"
	_map_page = page
	page.add_theme_constant_override("separation", 6)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 12)
	page.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var head := HBoxContainer.new()
	left.add_child(head)
	_map_title = Label.new()
	_map_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_title.add_theme_font_size_override("font_size", 18)
	head.add_child(_map_title)
	_map_back = Button.new()
	_map_back.pressed.connect(func(): open_map(_map_home_view()))
	head.add_child(_map_back)
	globe = GlobeView.new()
	globe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	globe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	globe.town_zoom = float(GlobeMap.cfg().get("town_zoom", 14.0))
	globe.pin_clicked.connect(map_pick)
	globe.spot_clicked.connect(func(m): map_pick(GlobeMap.spot_pin(m)))
	left.add_child(globe)
	cruiser_view = CruiserMapView.new()
	cruiser_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cruiser_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cruiser_view.visible = false
	cruiser_view.place_clicked.connect(map_pick)
	left.add_child(cruiser_view)
	station_view = StationMapView.new()
	station_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	station_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	station_view.visible = false
	station_view.place_clicked.connect(map_pick)
	left.add_child(station_view)
	system_view = SystemView.new()
	system_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	system_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	system_view.visible = false
	system_view.body_clicked.connect(func(id: String):
		open_map("" if id == GameFlow.current_planet_id() else id))
	left.add_child(system_view)
	_no_globe = Label.new()
	_no_globe.text = GlobeMap.line("no_globe")
	_no_globe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_globe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_no_globe.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_no_globe.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_no_globe)
	_map_note = Label.new()
	_map_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	page.add_child(_map_note)

	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.custom_minimum_size = Vector2(200, 0)
	h.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 6)
	side_scroll.add_child(side)
	_section(side, GlobeMap.line("off_planet"))
	_off_box = VBoxContainer.new()
	side.add_child(_off_box)
	# The legend in its groups (map.json "legend_groups": you and the vehicles,
	# settlements, places to explore, merchants). Every row is a button: the next
	# place of its kind, centred, as the waypoint.
	_legend = []
	for g in GlobeMap.cfg().get("legend_groups", []):
		_section(side, str(g.get("title", "")))
		for row in g.get("rows", []):
			_legend_row(side, str(row))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(gap)
	_map_you = Button.new()
	_map_you.text = GlobeMap.line("centre_you")
	_map_you.pressed.connect(func():
		if _map_view == "system":
			if system_view.player != Vector3.INF:
				system_view.focus(system_view.player)
		elif globe.player != Vector2.INF:
			globe.focus(globe.player))
	side.add_child(_map_you)
	_map_home = Button.new()
	_map_home.text = GlobeMap.line("home")
	_map_home.pressed.connect(func():
		if _map_view == "system":
			system_view.reset()
			return
		globe.set_zoom(1.0)
		globe.focus(Vector2.ZERO))
	side.add_child(_map_home)
	var clear := Button.new()
	clear.text = GlobeMap.line("clear")
	clear.pressed.connect(func():
		GlobeMap.clear_waypoint()
		_refresh_map())
	side.add_child(clear)
	_refreshers.append(_refresh_map.bind(true))
	tabs.tab_changed.connect(func(i):
		if tabs.get_tab_control(i) == page:
			_refresh_map())          # a waypoint picked in the Ledger since
	return page


## One row of a legend group by its name in map.json: a pin kind, or one of the
## '@' rows (you, the waypoint, your mark, who holds an outpost, a hostile camp,
## the rock).
func _legend_row(side: Control, row: String) -> void:
	var lk := GlobeMap.look()
	var pins_look: Dictionary = lk.get("pins", {})
	var owners: Dictionary = lk.get("owners", {})
	var locals := Color(str(owners.get("locals", "#5fd35f")))
	match row:
		"@you":
			_legend_add(side, lk.get("player", {}), GlobeMap.line("you"), { "special": "you" },
				Color(str(lk.get("player", {}).get("color", "#4dff88"))))
		"@goal":
			_legend_add(side, lk.get("goal", {}), GlobeMap.line("goal"), { "special": "goal" },
				Color(str(lk.get("goal", {}).get("color", "#ffd84a"))))
		"@spot":
			_legend_add(side, GlobeView.pin_look({ "kind": "spot" }), _kind_legend("spot"), { "special": "spot" })
		"@hostile_camp":
			_legend_add(side, GlobeView.pin_look({ "kind": "camp", "hostile": true }), GlobeMap.line("legend_hostile"),
				{ "test": func(p): return str(p.kind) == "camp" and bool(p.get("hostile", false)) })
		"@terrain":
			_legend_add(side, GlobeView.pin_look({ "kind": "mountain" }), GlobeMap.line("legend_terrain"), { "special": "terrain" })
		"@racers":
			# one line: the races you have heard of, or, while a race runs, the
			# rival racers in their place (_legend_texts swaps them)
			_legend_add(side, GlobeView.pin_look({ "kind": "race" }), _kind_legend("race"),
				{ "kind": "race", "when": func(): return not _racing() })
			_legend_add(side, GlobeView.pin_look({ "kind": "speeder_rival" }), _kind_legend("speeder_rival"),
				{ "kind": "speeder_rival", "when": _racing })
		"@held":
			_legend_add(side, pins_look.get("remnant_outpost", {}), GlobeMap.line("legend_held"),
				{ "test": func(p): return str(p.get("owner", "")) == Territory.LOCALS and not bool(p.get("short", false)) }, locals)
		"@short":
			_legend_add(side, pins_look.get("remnant_outpost", {}), GlobeMap.line("legend_short"),
				{ "test": func(p): return bool(p.get("short", false)) }, Color(str(owners.get("short", "#5fd35f"))))
		"@hold":
			_legend_add(side, { "shape": "ring" }, GlobeMap.line("legend_hold"),
				{ "test": func(p): return float(p.get("hold", -1.0)) >= 0.0 }, locals)
		_:
			_legend_add(side, GlobeView.pin_look({ "kind": row }), _kind_legend(row), { "kind": row })


## Whether a race runs on the globe shown: its rival racers are on it
## (GlobeMap.vehicles has them only while their race runs).
func _racing() -> bool:
	for p in globe.pins:
		if str(p.kind) == "speeder_rival":
			return true
	return false


func _kind_legend(kind: String) -> String:
	return str(GlobeMap.kind_cfg(kind).get("legend", GlobeMap.kind_cfg(kind).get("label", kind)))


## One legend line, a button: the pin's shape, drawn the way the globe draws it,
## and its name. `col` overrides the look's colour (you and the waypoint keep
## theirs off the pins). `e` says what a click finds (_legend_pick): a pin `kind`,
## a `test` (Callable on a pin: the held outposts), or a `special` ("you", "goal",
## "spot": the marked spot).
func _legend_add(side: Control, look: Dictionary, text: String, e: Dictionary, col := Color(0, 0, 0, 0)) -> void:
	var row := HBoxContainer.new()
	if col.a > 0.0:
		look = look.duplicate()
		look["color"] = col.to_html()
	row.add_child(_pin_icon(look))
	var b := Button.new()
	b.flat = true
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = GlobeMap.line("legend_hint")
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_child(b)
	e["button"] = b
	e["row"] = row
	e["text"] = text
	b.pressed.connect(_legend_pick.bind(e))
	_legend.append(e)
	side.add_child(row)


## The places a legend row finds on the globe shown, in the pins' order (the
## vehicles where they are now).
func _legend_hits(e: Dictionary) -> Array:
	var sp := str(e.get("special", ""))
	if sp == "you":
		return [{ "id": "you", "map": globe.player }] if globe.player != Vector2.INF and _map_view == "" else []
	if sp == "spot":
		return [GlobeMap.spot_pin(globe.spot)] if globe.spot != Vector2.INF else []
	if sp == "goal":
		return [] if Objective.current().is_empty() else [{ "id": "goal" }]
	if sp == "terrain":
		# the mountains and spires (not every boulder): each a waypoint like a marked spot
		var rocks: Array = []
		for m in globe.marks:
			if str(m.get("kind", "")) != "boulder":
				var pin := GlobeMap.spot_pin(m.map)      # drawn as a marked spot once picked
				pin["label"] = str(m.kind).capitalize()
				rocks.append(pin)
		return rocks
	var out: Array = []
	for p in globe.pins:
		if e.has("kind"):
			var k := str(p.kind)
			if k == str(e.kind) or (str(e.kind) == "camp" and k == "camp_hostile"):
				out.append(p)
		elif e.has("test") and (e["test"] as Callable).call(p):
			out.append(p)
	return out


## A legend row clicked: the globe turns to the next place of its kind (after the
## waypoint, if that is one of them; the first otherwise) and the waypoint goes
## there, following it if it is a vehicle. "You" and the marked spot only centre;
## "Waypoint" centres on wherever the waypoint is (its planet's map, if elsewhere).
func _legend_pick(e: Dictionary) -> void:
	var sp := str(e.get("special", ""))
	if sp == "goal":
		_centre_on_waypoint()
		return
	if not globe.visible or (sp == "you" and _map_view != ""):
		open_map("")
	if not globe.visible:
		return
	var hits := _legend_hits(e)
	if hits.is_empty():
		return
	var at := -1
	for i in hits.size():
		if _is_waypoint(hits[i]):
			at = i
	var pin: Dictionary = hits[(at + 1) % hits.size()]
	_globe_show(pin)
	if sp == "" or sp == "terrain":
		GlobeMap.set_waypoint(pin, _map_planet())
		_refresh_map()
		_hud_refresh()
	else:
		_legend_texts()


## Whether `pin` is the waypoint on the planet shown (a marked spot: by where it is).
func _is_waypoint(pin: Dictionary) -> bool:
	var w := WorldState.map_waypoint
	if w.is_empty() or str(w.get("planet", "")) != _map_planet():
		return false
	if str(pin.id) == "spot":
		var m: Vector2 = pin.map
		return str(w.get("target", "")) == "map:%.1f,%.1f" % [m.x, m.y]
	return str(pin.id) == GlobeMap.waypoint_id()


## Turn the globe to `pin`, zoomed in on its town or place first when its stops
## are hidden at this zoom (or back out for the port, hidden inside the town).
func _globe_show(pin: Dictionary) -> void:
	if not globe.shown(pin):
		var place: Dictionary = globe._place_by_id("town" if bool(pin.get("town", false)) else str(pin.get("detail", "")))
		if not place.is_empty():
			globe.fit(place.center, float(place.extent), 0.8, float(GlobeMap.look().get("details", {}).get("stops_px", 230.0)) + 8.0)
		elif bool(pin.get("town", false)):
			globe.set_zoom(globe.town_zoom)
		else:
			globe.set_zoom(1.0)
	globe.focus(pin.map)


## Turn the Map page to wherever the waypoint (or the objective's pointer) is: its
## pin, its marked spot, the vehicle it follows, or the planet or cruiser it is on.
func _centre_on_waypoint() -> void:
	var w := WorldState.map_waypoint
	if not w.is_empty():
		var t := str(w.get("target", ""))
		var on := str(w.get("planet", ""))
		var view := "" if on == GameFlow.current_planet_id() or on == "" else on
		if t.begins_with("planet:"):
			view = t.get_slice(":", 1)
			if view == GameFlow.current_planet_id():
				view = ""
		elif t.begins_with("cruiser"):
			view = "cruiser:" + (on if on != "" else GameFlow.current_planet_id())
		if view != _map_view or not globe.visible:
			open_map(view)
		if not globe.visible:
			return
		for p in globe.pins:
			if str(p.id) == GlobeMap.waypoint_id() and str(p.id) != "spot":
				_globe_show(p)
				return
		if globe.spot != Vector2.INF:
			globe.focus(globe.spot)
		return
	if _map_view != "":
		open_map("")
	if globe.visible and globe.goal != Vector2.INF:
		globe.focus(globe.goal)
	elif globe.visible and globe.goal_pin != "":
		for p in globe.pins:
			if str(p.id) == globe.goal_pin:
				globe.focus(p.map)


## Each legend row's count ("Village (5)", or "Village  2/5" when the waypoint is
## the second), greyed out when there are none on the globe shown. A row with a
## `when` (the races / rival racers line) shows only while it holds.
func _legend_texts() -> void:
	for e in _legend:
		var b: Button = e.get("button")
		if b == null or not is_instance_valid(b):
			continue
		if e.has("when"):
			(e.row as Control).visible = (e["when"] as Callable).call()
		var hits := _legend_hits(e)
		b.disabled = hits.is_empty()
		if e.has("special"):
			b.text = str(e.text)
			continue
		var at := 0
		for i in hits.size():
			if _is_waypoint(hits[i]):
				at = i + 1
		b.text = GlobeMap.line("legend_at") % [str(e.text), at, hits.size()] if at > 0 \
			else GlobeMap.line("legend_count") % [str(e.text), hits.size()]


## The vehicles where they are now (and you), on the globe of the planet you are
## on; the pins that stay put are as they were.
func _refresh_vehicles() -> void:
	var sphere := PlanetSphere.current
	if sphere == null or _map_view != "" or not globe.visible or demo == null:
		return
	globe.pins = _static_pins + GlobeMap.vehicle_pins(demo, sphere.world_to_map)
	if globe.hover >= globe.pins.size():
		globe.hover = -1
	_map_marks(sphere)
	_legend_texts()
	globe.queue_redraw()


## A pin's shape (content/look/map.json) as a small control, for the legend and
## the off-planet list. `glow` (optional) returns how far to whiten it (the
## cruiser's row flashing).
func _pin_icon(look: Dictionary, r := 5.0, glow := Callable()) -> Control:
	var icon := Control.new()
	icon.custom_minimum_size = Vector2.ONE * ceilf(r * 3.6)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.draw.connect(func():
		var col := Color(str(look.get("color", "#f2e2b0")))
		if glow.is_valid():
			col = col.lerp(Color.WHITE, float(glow.call()))
		if str(look.get("icon", "")) != "":
			GlobeView.draw_icon(icon, icon.size * 0.5, str(look.icon), col, icon.size.x - 2.0)
		else:
			GlobeView.draw_shape(icon, icon.size * 0.5, str(look.get("shape", "circle")), col, r))
	return icon


## Show `view` on the Map page: "" where you are, a planet's id, a cruiser's side
## view ("cruiser:<planet>": the one over that planet; "cruiser" alone: this
## planet's), a space station's ("station:<planet>", "station" alone: this
## planet's), or "system" (the star system's chart, as a whole).
func open_map(view: String) -> void:
	if view in ["cruiser", "station"]:
		view = view + ":" + GameFlow.current_planet_id()
	_map_view = view
	globe.set_zoom(1.0)
	_map_auto_zoomed = false
	_refresh_map()
	if view == "system":
		system_view.reset()
	elif view != "":
		globe.focus(Vector2.ZERO)


## What the Map page opens on: the planet you are on, or the system's chart when
## you are out in space (flying above this planet's space_altitude).
func _map_home_view() -> String:
	var pilot = demo.get("pilot") if demo != null else null
	if pilot != null and bool(pilot.get("piloting")) and pilot.get("atmo") != null:
		if pilot.atmo.altitude() >= pilot.atmo.space_altitude:
			return "system"
	return ""


## The planet a waypoint picked on the Map page now goes on: the one shown, or the
## one the cruiser or station shown hangs over (so a room on a cruiser elsewhere
## leads to its planet first).
func _map_planet() -> String:
	if _map_view.begins_with("cruiser:") or _map_view.begins_with("station:"):
		return _map_view.get_slice(":", 1)
	return _map_view if not _map_view in ["", "cruiser", "station", "system"] else GameFlow.current_planet_id()


## Rebuild the map's pins and off-planet list from the scene (the town's stops
## and the planets in the sky only exist once it is built), you and the waypoint.
## `centre`: back to where you are, the globe turned to you (on opening the panel).
## Another planet is drawn from its data (GlobeMap.other_planet): its ball, its
## ground, its places, no town stops and no you.
func _refresh_map(centre := false) -> void:
	if centre:
		_map_view = _map_home_view()
	var here := GameFlow.current_planet_id()
	var live := _map_view == ""
	var on_cruiser := _map_view.begins_with("cruiser")
	var on_station := _map_view.begins_with("station")
	var on_system := _map_view == "system"
	var flat := on_cruiser or on_station or on_system      # no globe: a side view or the chart
	var other: Dictionary = {} if live or flat else GlobeMap.other_planet(_map_view)
	var sphere: PlanetSphere = PlanetSphere.current if live else other.get("sphere", null)
	var world: Dictionary = (demo.world if demo != null else {}) if live else other.get("planet", {}).get("world", {})
	var planet: Dictionary = (demo.planet if demo != null else {}) if live else other.get("planet", {})
	var shown := _map_planet()
	globe.visible = sphere != null and not flat
	_no_globe.visible = sphere == null and not flat
	cruiser_view.visible = on_cruiser
	station_view.visible = on_station
	system_view.visible = on_system
	var home_view := _map_home_view()
	_map_back.visible = _map_view != home_view
	_map_back.text = GlobeMap.line("back") % (GlobeMap.line("system") if home_view == "system" else GlobeMap.planet_name(here))
	_map_you.visible = live or on_system
	_map_home.visible = not on_cruiser and not on_station
	_map_home.text = GlobeMap.line("system_reset" if on_system else "home")
	var w := WorldState.map_waypoint
	var w_here := str(w.get("planet", "")) == shown
	if on_cruiser:
		_refresh_cruiser(w_here)
	elif on_station:
		_refresh_station(w_here)
	elif on_system:
		_map_title.text = GlobeMap.line("system_title")
		_refresh_system(centre)
	else:
		_map_title.text = GlobeMap.planet_name(shown)
	if sphere != null and not flat:
		globe.radius_m = sphere.radius
		globe.town_zoom = float(GlobeMap.cfg().get("town_zoom", 14.0))
		# The town's stops and footprints: the built town here, another planet's
		# from its data (no stamping: that town is shared).
		var front := Territory.front_for_planet(shown)
		var town_obj = demo.town if demo != null and live else null
		if town_obj == null and not live and planet.get("town") is Dictionary and not (planet.town as Dictionary).is_empty():
			town_obj = TownLayoutScript.new()
			town_obj.data = planet.town
		var town_id := WorldState.current_town_id() if live else (str(town_obj.data.get("id", "")) if town_obj != null else "")
		var town: Array = GlobeMap.town_pins(town_obj, town_id, sphere.world_to_map, shown)
		_static_pins = GlobeMap.pins(world, planet, town)
		if live and demo != null:
			GlobeMap.place_barge(_static_pins, demo.get("barge"), sphere.world_to_map)
		globe.pins = _static_pins + (GlobeMap.vehicle_pins(demo, sphere.world_to_map) if live and demo != null else [])
		if globe.hover >= globe.pins.size():
			globe.hover = -1
		globe.shapes = GlobeMap.station_shapes(planet)
		globe.details = _map_details(shown, town_obj, town_id, world, sphere, front)
		globe.marks = GlobeMap.terrain_marks(planet, sphere, _live_boulders(sphere) if live else [])
		var mesas: Array = DesertLandforms.mesa_spots if DesertLandforms.mesa_planet == shown else []
		globe.ground = GlobeTerrain.for_sphere("%s/%d" % [shown, mesas.size()], sphere, mesas)
		globe.terrain = GlobeMap.terrain_look(planet)
	var aboard_target := str(w.get("target", "")).begins_with("cruiser") or str(w.get("target", "")).begins_with("station")
	globe.selected = GlobeMap.waypoint_id() if w_here and not aboard_target else ""
	var t := str(w.get("target", ""))
	globe.spot = Vector2(float(t.get_slice(":", 1).get_slice(",", 0)), float(t.get_slice(",", 1))) \
		if globe.selected == "spot" and t.begins_with("map:") else Vector2.INF
	_map_marks(sphere if live else null)
	if centre and globe.player != Vector2.INF:
		globe.focus(globe.player)
		_map_fit_town()
	globe.queue_redraw()
	# The star system's chart, then every planet in it (this one too: its own
	# map, where you are), then every cruiser in the system.
	var bodies: Array = []
	for b in GlobeMap.system():
		bodies.append({ "id": b.id, "name": GlobeMap.line("system_here") % b.label if str(b.id) == here else b.label })
	_off_planet = [{ "id": "system", "kind": "system", "label": GlobeMap.line("system"), "target": "system:" }] \
		+ GlobeMap.off_planet(bodies)
	for c in _off_box.get_children():
		c.queue_free()
	_cruiser_icon = null
	if _cruiser_changed and _map_open():
		_cruiser_changed = false
		_cruiser_flash_end = Time.get_ticks_msec() + int(1000.0 * float(GlobeMap.look().get("owners", {}).get("flash_s", 3.0)))
	for o in _off_planet:
		var row := HBoxContainer.new()
		var is_cruiser := str(o.kind) == "cruiser"
		var home_cruiser := is_cruiser and str(o.get("cfg", "")) == CruiserHull.HOME_ID
		var look := GlobeView.pin_look(o)
		if is_cruiser:                 # issue #497: by who holds it (nobody: the empty grey)
			look = look.duplicate()
			look["color"] = GlobeMap.cruiser_color(GlobeMap.cruiser_on(str(o.planet))).to_html()
		var icon := _pin_icon(look, 7.0, cruiser_flash if home_cruiser else Callable())
		if home_cruiser:
			_cruiser_icon = icon       # it flashes when the home cruiser changes hands
		row.add_child(icon)
		var b := Button.new()
		b.text = str(o.label)
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var view := "cruiser:" + str(o.planet) if is_cruiser else ("system" if str(o.kind) == "system" else str(o.target).get_slice(":", 1))
		if str(o.kind) == "station":
			view = "station:" + str(o.planet)
		if view == here:
			view = ""
		b.set_pressed_no_signal(view == _map_view)
		b.pressed.connect(func(): open_map(view))
		row.add_child(b)
		_off_box.add_child(row)
	if _off_planet.is_empty():
		var l := Label.new()
		l.text = "-"
		_off_box.add_child(l)
	_legend_texts()
	var now := Objective.current()
	_map_note.text = (GlobeMap.line("waypoint") % str(now.text) if now.get("key", "") != "map" else str(now.text)) \
		if not now.is_empty() else GlobeMap.line("system_hint" if on_system else ("station_hint" if on_station else "none"))


## What opens zoomed in (GlobeView.details): the town's footprints and every
## location's, made once per planet, town and barracks holder (a few thousand
## points: not on every refresh).
func _map_details(shown: String, town_obj, town_id: String, world: Dictionary, sphere: PlanetSphere, front: String) -> Array:
	var key := "%s/%s/%s/%d" % [shown, town_id, Territory.owner(Territory.barracks_of(front)), sphere.get_instance_id()]
	if key == _details_key:
		return _details
	var out: Array = []
	var t := GlobeMap.town_details(town_obj, sphere.world_to_map, front)
	if not t.is_empty():
		out.append(t)
	out.append_array(GlobeMap.place_details(world))
	_details_key = key
	_details = out
	return out


## The boulders in the built scene, as map spots: the desert's (DesertLandforms)
## and the rock round a station (AsteroidWorld).
func _live_boulders(sphere: PlanetSphere) -> Array:
	var out: Array = []
	if demo == null:
		return out
	var lf = demo.get("landforms")
	if lf != null and is_instance_valid(lf):
		for b in lf.boulders:
			out.append({ "map": sphere.world_to_map(b.center), "size": float(b.get("radius", 1.0)) * 2.0 })
	var plat = demo.get("platform")
	if plat is AsteroidWorld and is_instance_valid(plat):
		var xf: Transform3D = (plat as Node3D).global_transform
		for b in plat.boulders:
			var sz: Vector3 = b.get("size", Vector3.ONE * 2.0)
			out.append({ "map": sphere.world_to_map(xf * (b.xform as Transform3D).origin), "size": maxf(sz.x, sz.z) })
	return out


## Opening the page in the town (or a ranch): zoomed in on it so its insides
## show. Anywhere else, back out to the whole ball if it was this that zoomed in.
func _map_fit_town() -> void:
	for place in globe.details:
		var ext := float(place.extent)
		if ext < 25.0 or globe.player.distance_to(place.center) > ext * 1.15:
			continue
		globe.fit(place.center, ext, 0.8, float(GlobeMap.look().get("details", {}).get("stops_px", 230.0)) + 8.0)
		_map_auto_zoomed = true
		return
	if _map_auto_zoomed:
		_map_auto_zoomed = false
		globe.set_zoom(1.0)
		globe.focus(globe.player)


## The star system's chart: its planets, every cruiser, you and the other LAN
## players wherever you are (this scene's points carried into the system's frame),
## and the planet the pointer leads to. `centre`: the whole system, nothing moved.
func _refresh_system(centre: bool) -> void:
	var here := GameFlow.current_planet_id()
	system_view.bodies = GlobeMap.system()
	system_view.here = here
	system_view.cruisers = []
	for c in GlobeMap.system_cruisers():
		system_view.cruisers.append({ "id": "cruiser:" + str(c.planet), "planet": str(c.planet), "pos": c.pos,
			"label": GlobeMap.cruiser_label(c), "color": GlobeMap.cruiser_color(c),
			"status": GlobeMap.line("cruiser_at") % [GlobeMap.planet_name(str(c.planet)), GlobeMap.cruiser_status(c)] })
	system_view.stations = []
	var st_col := Color(str(GlobeMap.look().get("pins", {}).get("station", {}).get("color", "#9fd0e8")))
	for st in GlobeMap.system_stations():
		system_view.stations.append({ "id": "station:" + str(st.planet), "planet": str(st.planet), "pos": st.pos,
			"label": GlobeMap.station_label(st), "color": st_col,
			"status": GlobeMap.line("station_at") % GlobeMap.planet_name(str(st.planet)) })
	system_view.sun = PlanetGen.system_sun()
	system_view.player = Vector3.INF
	system_view.heading = Vector2.ZERO
	system_view.others = []
	var p = demo.get("_player") if demo != null else null
	if p is Node3D and is_instance_valid(p):
		var at: Vector3 = (p as Node3D).global_position
		system_view.player = GlobeMap.to_system(at, here)
		var cam := get_viewport().get_camera_3d()
		var fwd: Vector3 = -cam.global_basis.z if cam != null else -(p as Node3D).global_basis.z
		system_view.heading = Vector2(fwd.x, fwd.z)
		for o in NetSession.others():
			system_view.others.append({ "id": o.id, "pos": GlobeMap.to_system(o.pos, here), "name": o.name })
	var goal := ""
	var now := Objective.current()
	var t := str(now.get("target", ""))
	if t.begins_with("planet:"):
		goal = t.get_slice(":", 1)
	elif t.begins_with("cruiser"):
		goal = "cruiser:" + here            # an objective's cruiser is always this scene's
	elif now.get("key", "") == "map":
		goal = str(WorldState.map_waypoint.get("planet", ""))
		var wt := str(WorldState.map_waypoint.get("target", ""))
		if wt.begins_with("cruiser"):
			goal = "cruiser:" + goal
		elif wt.begins_with("station"):
			goal = "station:" + goal
	elif not now.is_empty():
		goal = here
	system_view.goal = goal
	if centre or system_view.pan == Vector2.ZERO:
		system_view.reset()
	system_view.queue_redraw()


## Where you are and which way you look, the other LAN players (on foot or in a
## ship, wherever it is over this planet), and
## where the pointer is (the globe flashes the pin there, or marks the spot).
## Off-planet targets (another planet, the cruiser up there) are not on the globe.
func _map_marks(sphere: PlanetSphere) -> void:
	globe.player = Vector2.INF
	globe.heading = Vector2.ZERO
	globe.others = []
	globe.goal_pin = ""
	globe.goal = Vector2.INF
	if sphere == null or demo == null:
		return
	var p = demo.get("_player")
	if p is Node3D and is_instance_valid(p):
		var at: Vector3 = (p as Node3D).global_position
		globe.player = sphere.world_to_map(at)
		var cam := get_viewport().get_camera_3d()
		var fwd: Vector3 = -cam.global_basis.z if cam != null else -(p as Node3D).global_basis.z
		globe.heading = sphere.world_to_map(at + fwd * 25.0) - globe.player
		for o in NetSession.others():
			globe.others.append({ "id": o.id, "map": sphere.world_to_map(o.pos), "name": o.name })
	var now := Objective.current()
	if now.is_empty():
		return
	if now.get("key", "") == "map":
		globe.goal_pin = globe.selected if globe.selected != "spot" else ""
		return
	var target := str(now.get("target", ""))
	var hud = demo.get("objective_hud")
	if target == "" or target.begins_with("planet:") or target.begins_with("cruiser") or target.begins_with("station") or hud == null:
		return
	var pos: Vector3 = hud.where(target)
	if pos == Vector3.INF:
		return
	globe.goal = sphere.world_to_map(pos)


## The cruiser's side view: its places, the waypoint's, and you when aboard.
func _refresh_cruiser(w_here: bool) -> void:
	var on := _map_planet()
	var c = demo.get("cruiser") if demo != null and on == GameFlow.current_planet_id() else null
	var data := GlobeMap.cruiser_on(on)
	var label: String = c.label() if c != null else (GlobeMap.cruiser_label(data) if not data.is_empty() else str(GlobeMap.kind_cfg("cruiser").get("label", "")))
	_map_title.text = GlobeMap.line("cruiser_title") % label
	cruiser_view.pins = GlobeMap.cruiser_pins()
	cruiser_view.selected = GlobeMap.waypoint_id() if w_here else ""
	cruiser_view.player = Vector3.INF
	var p = demo.get("_player") if demo != null else null
	if c != null and p is Node3D and is_instance_valid(p) and c.aboard((p as Node3D).global_position):
		cruiser_view.player = c.to_local_point((p as Node3D).global_position)
	cruiser_view.queue_redraw()


## The station's side view: its places, the waypoint's, and you when aboard.
func _refresh_station(w_here: bool) -> void:
	var on := _map_planet()
	var data := GlobeMap.station_on(on)
	var s = null
	if demo != null and on == GameFlow.current_planet_id() and demo.get("stations") != null:
		for st in demo.stations:
			if is_instance_valid(st) and (data.is_empty() or str(st.id) == str(data.id)):
				s = st
				break
	var label: String = GlobeMap.station_label(data) if not data.is_empty() else str(GlobeMap.kind_cfg("station").get("label", ""))
	_map_title.text = GlobeMap.line("station_title") % label
	station_view.show_station(StationHull.for_id(str(data.get("station", ""))) if not data.is_empty() else null,
		GlobeMap.orbital_pins(data) if not data.is_empty() else [])
	station_view.selected = GlobeMap.waypoint_id() if w_here else ""
	station_view.player = Vector3.INF
	var p = demo.get("_player") if demo != null else null
	if s != null and p is Node3D and is_instance_valid(p) and s.aboard((p as Node3D).global_position):
		station_view.player = s.to_local_point((p as Node3D).global_position)
	station_view.queue_redraw()


## Set the waypoint on a pin (on the planet shown, or a place on the cruiser or a
## station); the one already set clears. A station's own pin on the globe opens
## its side view instead.
func map_pick(pin: Dictionary) -> void:
	if str(pin.get("kind", "")) == "station":
		open_map(str(pin.get("view", "station")))
		return
	var planet := _map_planet()
	if GlobeMap.waypoint_id() == str(pin.id) and str(pin.id) != "spot" and str(WorldState.map_waypoint.get("planet", "")) == planet:
		GlobeMap.clear_waypoint()
	else:
		GlobeMap.set_waypoint(pin, planet)
	_refresh_map()
	_hud_refresh()


# ------------------------------------------------------------------ world

func _world_page(v: VBoxContainer) -> void:
	_section(v, "Time of day")
	# LAN: the host sets the time of day for everyone; a guest sees a line instead.
	var tod := VBoxContainer.new()
	v.add_child(tod)
	var hosts := Label.new()
	hosts.text = NetSession.label("lighting_host")
	v.add_child(hosts)
	_refreshers.append(func():
		tod.visible = not NetSession.is_guest()
		hosts.visible = NetSession.is_guest())
	_hour = HSlider.new()
	_hour.min_value = 0.0
	_hour.max_value = 24.0
	_hour.step = 0.25
	_hour.custom_minimum_size = Vector2(380, 0)
	_hour_label = Label.new()
	_hour_label.custom_minimum_size = Vector2(110, 0)
	# Issue #381: Auto moves the day on by itself (DayClock); a preset fixes it.
	# Moving the slider or pressing a preset sets the picker to where it lands.
	var day := OptionButton.new()
	for id in DayClock.PICKS:
		day.add_item(str(id).capitalize())
	day.item_selected.connect(func(i):
		var p := DayClock.pick(str(DayClock.PICKS[i]))
		if p != "":
			demo.set_preset(p)
		refresh())
	_row(tod, "Time of day", day)
	_hour.value_changed.connect(func(h):
		if DayClock.locked():
			return
		demo.set_hour(h)
		DayClock.set_by_hand(str(demo.preset))
		_show_hour())
	var hr := _row(tod, "Hour", _hour)
	hr.add_child(_hour_label)
	var presets := HBoxContainer.new()
	var buttons: Array[Button] = []
	for id in ["golden", "noon", "dusk"]:
		var btn := Button.new()
		btn.text = id.capitalize()
		btn.pressed.connect(func():
			if DayClock.locked():
				return
			demo.set_preset(id)
			DayClock.set_by_hand(id)
			_hour.set_value_no_signal(maxf(0.0, demo.look.hour_of(id)) if demo.look != null else 0.0)
			refresh())
		presets.add_child(btn)
		buttons.append(btn)
	_row(tod, "Preset", presets)
	var day_note := Label.new()
	day_note.text = "Story save: the chapters set the time of day; it is yours to pick once the cruiser is won."
	day_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	day_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	tod.add_child(day_note)
	_refreshers.append(func():
		var h: float = demo.look.hour if demo.look != null and demo.look.hour >= 0.0 else \
			(demo.look.hour_of(demo.preset) if demo.look != null else 0.0)
		_hour.set_value_no_signal(maxf(0.0, h))
		_show_hour()
		var locked := DayClock.locked()
		day.select(maxi(0, DayClock.PICKS.find(WorldState.day_pick)))
		day.disabled = locked
		_hour.editable = not locked
		for b in buttons:
			b.disabled = locked
		day_note.visible = locked)

	# Issue #175: a sandstorm now, so it can be checked without waiting for one.
	_section(v, "Weather")
	var weather := HBoxContainer.new()
	var storm_go := Button.new()
	storm_go.text = "Start a sandstorm now"
	storm_go.pressed.connect(func():
		var st = demo.get("storm") if demo != null else null
		if st != null:
			st.start_now()
		refresh())
	weather.add_child(storm_go)
	var storm_end := Button.new()
	storm_end.text = "End it"
	storm_end.pressed.connect(func():
		var st = demo.get("storm") if demo != null else null
		if st != null:
			st.stop_now()
		refresh())
	weather.add_child(storm_end)
	var storm_line := Label.new()
	weather.add_child(storm_line)
	_row(v, "Sandstorm", weather)
	_refreshers.append(func():
		var st = demo.get("storm") if demo != null else null
		storm_go.disabled = st == null
		storm_end.disabled = st == null or str(st.state) == "clear" or str(st.state) == "fading"
		storm_line.text = "  no storms on this planet" if st == null else "  %s (%d%%)" % [str(st.state), roundi(float(st.level) * 100.0)])

	_section(v, "Game")
	_story_note(v, "credits are earned and the Remnant fleet always meets you in orbit.")
	var speed := OptionButton.new()
	for s in SPEEDS:
		speed.add_item("%sx" % str(s))
	speed.item_selected.connect(func(i): Engine.time_scale = SPEEDS[i])
	_row(v, "Game speed", speed)
	_refreshers.append(func(): speed.select(maxi(0, SPEEDS.find(Engine.time_scale))))
	var credits: SpinBox = _cheat(_spin(0, 99999, 10))
	credits.value_changed.connect(func(x):
		WorldState.credits = int(x)
		CreditToast.settle())                # a cheat is not money changing hands
	_row(v, "Credits", credits)
	_refreshers.append(func(): credits.set_value_no_signal(WorldState.credits))
	# Issue #46: whether flying out of the atmosphere starts the pad's space fight.
	var dogfight: CheckBox = _cheat(CheckBox.new())
	dogfight.text = "Flying to space starts a dogfight"
	dogfight.toggled.connect(func(on): GameFlow.set_space_dogfight(on))
	_row(v, "", dogfight)
	_refreshers.append(func(): dogfight.set_pressed_no_signal(GameFlow.space_dogfight()))
	# Issue #237: which saved layout the home town is built to (this run only).
	_section(v, "Town")
	var layout := OptionButton.new()
	var ids: Array = PlanetGen.layouts()
	ids.sort()
	for id in ids:
		layout.add_item(str(id))
	layout.item_selected.connect(func(i): set_town_layout(str(ids[i])))
	_row(v, "Home town layout", layout)
	_refreshers.append(func():
		var here := str(demo.planet.get("town", {}).get("layout", "")) if demo != null and "planet" in demo else ""
		layout.select(ids.find(here))
		layout.disabled = demo == null or str(demo.planet.get("id", "")) != PlanetGen.home_id())


## Issue #237: build the home town to `layout` (content/core/towns/) and reload it.
func set_town_layout(layout: String, reload := true) -> void:
	PlanetGen.set_layout(PlanetGen.home_id(), layout)
	if not reload or not is_inside_tree():
		return
	_save()
	visible = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func _show_hour() -> void:
	var h := _hour.value
	var preset: String = demo.preset if demo != null else ""
	_hour_label.text = "%02d:%02d  %s" % [int(h) % 24, int(round(fmod(h, 1.0) * 60.0)) % 60, preset]


# ------------------------------------------------------------------ standing

func _standing_page(v: VBoxContainer) -> void:
	_section(v, "Factions  (-100 hostile .. 100 allied)")
	_story_note(v, "where you stand with each faction and person is earned in play. Shown here, not set.")
	for fac in WorldState.FACTIONS:
		var s: HSlider = _cheat(_slider(-100, 100))
		var lab := Label.new()
		lab.custom_minimum_size = Vector2(120, 0)
		var paint := func(x): lab.text = "%d  %s" % [int(x), WorldState.standing_label(int(x))]
		s.value_changed.connect(func(x):
			WorldState.standing[fac] = int(x)
			paint.call(x))
		_row(v, _faction_label(fac), s).add_child(lab)
		_refreshers.append(func():
			var x := int(WorldState.standing.get(fac, 0))
			s.set_value_no_signal(x)
			paint.call(x))
	var reset: Button = _cheat(Button.new())
	reset.text = "Reset to defaults"
	reset.pressed.connect(func():
		WorldState.standing = WorldState.DEFAULT_STANDING.duplicate()
		refresh())
	_row(v, "", reset)

	for who in _individuals():
		_individual(v, who.label, who.rel)


## Named people the player has a Relationship with. Only the cantina owner so far;
## add the next one here when an npc gets a Relationship.
func _individuals() -> Array:
	var out: Array = []
	if demo != null and demo.bar != null and demo.bar.brain != null:
		out.append({ "label": str(demo.bar.brain.card.get("name", "Cantina Owner")), "rel": demo.bar.brain.rel })
	return out


func _individual(v: VBoxContainer, label: String, rel: Relationship) -> void:
	_section(v, label + "  (trust 0 .. 100)")
	var trust: HSlider = _cheat(_slider(0, 100))
	var lab := Label.new()
	lab.custom_minimum_size = Vector2(120, 0)
	var paint := func(x): lab.text = "%d  %s" % [int(x), Relationship.tier_for(int(x))]
	trust.value_changed.connect(func(x):
		rel.trust = int(x)
		paint.call(x))
	_row(v, "Trust", trust).add_child(lab)
	var mood: OptionButton = _cheat(OptionButton.new())
	for m in MOODS:
		mood.add_item(m)
	mood.item_selected.connect(func(i): rel.mood = MOODS[i])
	_row(v, "Mood", mood)
	var tab: SpinBox = _cheat(_spin(0, 9999, 1))
	tab.value_changed.connect(func(x): rel.tab = int(x))
	var h := _row(v, "Tab owed", tab)
	var unban := Button.new()
	unban.text = "Clear ban"
	unban.pressed.connect(func():
		rel.banned_until = -1.0
		unban.disabled = true)
	h.add_child(unban)
	_refreshers.append(func():
		trust.set_value_no_signal(rel.trust)
		paint.call(rel.trust)
		mood.select(maxi(0, MOODS.find(rel.mood)))
		tab.set_value_no_signal(rel.tab)
		unban.disabled = WorldState.story_mode() or rel.banned_until <= WorldState.clock)


func _faction_label(id: String) -> String:
	var f := FileAccess.open("res://content/core/factions/%s.json" % id, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return str(d.get("label", id)) if d is Dictionary else id


# ------------------------------------------------------------------ player

func _player_page(v: VBoxContainer) -> void:
	_section(v, "Body")
	_story_note(v, "no god mode, free gear, teleports or guard x-ray; you live by your wits.")
	var god: CheckBox = _cheat(CheckBox.new())
	god.text = "God mode (no damage)"
	god.toggled.connect(func(on):
		_god = on
		var p = _player()
		if p != null and not on:
			p.invulnerable_left = 0.0)
	v.add_child(god)
	var heal: Button = _cheat(Button.new())
	heal.text = "Heal / revive"
	heal.pressed.connect(func():
		var p = _player()
		if p != null:
			p.revive(0.0))
	_row(v, "", heal)

	_section(v, "Jetpack")
	var give: Button = _cheat(Button.new())
	give.text = "Give and wear jetpack"
	give.pressed.connect(_give_jetpack)
	_row(v, "", give)
	var fuel: CheckBox = _cheat(CheckBox.new())
	fuel.text = "Endless fuel"
	fuel.toggled.connect(func(on): _endless_fuel = on)
	v.add_child(fuel)

	_section(v, "Teleport")
	var where: OptionButton = _cheat(OptionButton.new())
	var ids: Array = []
	if demo != null:
		for m in demo.town.markers():
			if str(m.role) in ["spawn", "waypoint", "interact"]:
				ids.append(str(m.id))
				where.add_item(str(m.id).replace("_", " "))
	var go: Button = _cheat(Button.new())
	go.text = "Go"
	go.pressed.connect(func():
		if where.selected >= 0:
			teleport(ids[where.selected]))
	_row(v, "Marker", where).add_child(go)

	_section(v, "Debug")
	var npc_dbg: CheckBox = _cheat(CheckBox.new())
	npc_dbg.text = "Guard senses [F4]"
	npc_dbg.toggled.connect(func(on): NpcBody.show_debug = on)
	v.add_child(npc_dbg)
	_refreshers.append(func():
		god.set_pressed_no_signal(_god)
		fuel.set_pressed_no_signal(_endless_fuel)
		npc_dbg.set_pressed_no_signal(NpcBody.show_debug))


func _player():
	return demo._player if demo != null else null


# ------------------------------------------------------------------ character

## The builder saves each pick itself; the player's body wears it at once.
func _character_page(v: VBoxContainer) -> void:
	_section(v, "Outfit")
	_story_note(v, "you play the smuggler; every piece and colour of their own kit is yours to pick.")
	# Issue #545: the outfit's turntable is a whole character (about 2.3 s to build),
	# so it is built the first time the Player page shows, not when the panel first
	# opens: I, M and F11 open at once. Issue #696: and not on the frame the page
	# shows either: it waits CharacterBuilder.BUILD_AFTER_FRAMES frames (_process),
	# then is built on the body the player already wears (its kit and materials).
	var holder := VBoxContainer.new()
	v.add_child(holder)
	var make := func():
		if builder != null or not holder.is_visible_in_tree():
			return
		var a = _avatar()
		builder = CharacterBuilder.new(false, a.kit if a != null else null,
				a.worn_outfit() if a != null else PlayerOutfit.load_outfit())
		builder.outfit_changed.connect(func(o):
			var av = _avatar()
			if av != null:
				av.set_outfit(o))
		holder.add_child(builder)
	_make_builder = make
	var later := func():
		if builder == null and _builder_in < 0 and holder.is_visible_in_tree():
			_builder_in = CharacterBuilder.BUILD_AFTER_FRAMES
	tabs.tab_changed.connect(func(_i): later.call())
	_refreshers.append(func():
		if builder == null:
			later.call()
			return
		var a = _avatar()
		builder.show_outfit(a.worn_outfit() if a != null else PlayerOutfit.load_outfit()))


## Issue #696: count down to building the Player page's preview, a few frames after
## the page shows.
func _tick_builder() -> void:
	if _builder_in < 0:
		return
	_builder_in -= 1
	if _builder_in < 0 and _make_builder.is_valid():
		_make_builder.call()


func _avatar() -> PlayerAvatar:
	return demo.player_kit.avatar if demo != null and demo.player_kit != null else null


func _give_jetpack() -> void:
	if demo == null or demo.gear == null:
		return
	var item: Dictionary = demo.gear.content.get_item("jetpack")
	var inv := WorldState.inventory
	if not inv.has("jetpack"):
		inv.add("jetpack")
	var on := inv.in_slot(str(item.get("slot", "")))
	if on != "" and on != "jetpack":
		inv.detach(on)
	inv.attach("jetpack", item)
	demo.gear.sync_gear()


## Stand on a town marker (not while flying, nor in a story save).
func teleport(marker_id: String) -> bool:
	var p = _player()
	if p == null or p.piloting or WorldState.story_mode() or demo.town.get_marker(marker_id).is_empty():
		return false
	p.global_position = demo.town.marker_pos(marker_id) + Vector3(0, 0.05, 0)
	if p.has_method("align_to_ground"):
		p.call("align_to_ground", true)
	else:
		p.velocity = Vector3.ZERO
	return true


# ------------------------------------------------------------------ respawn

## The Game page's first section: one button that puts you back where you started.
## Greyed out (and saying why) while you are seated or down; story saves keep it.
func _respawn_page(v: VBoxContainer) -> void:
	_section(v, "Respawn")
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var b := Button.new()
	b.text = "Respawn where you started"
	b.pressed.connect(func():
		if respawn():
			close())
	_row(v, "", b)
	_refreshers.append(func():
		var why := respawn_blocked()
		b.disabled = why != ""
		note.text = why if why != "" else RESPAWN_NOTE)


const RESPAWN_NOTE := "Stuck? Back to where the game started you: the pit, beside your ship. Nothing is lost or reset."


## Why respawn() would refuse right now, "" when it would not.
func respawn_blocked() -> String:
	var p = _player()
	if p == null or demo.town == null:
		return "There is nowhere to respawn here."
	if p.piloting:
		return "Get out of the ship or speeder first."
	if p.is_downed:
		return "You are down; you will wake in the pit on your own."
	return ""


## Back where you started: the town's spawn marker (the pit, beside your ship), the
## same spot a new game and a wake up in the pit use. Your primary ship is brought
## to its pad as on any wake up (ShipPilot.woke_in_pit). Not while seated (ship or
## speeder) nor while downed (the garrison's wake up, and its fee, comes first).
## A story save keeps it: it gives nothing, it only gets a stuck player out.
func respawn() -> bool:
	if respawn_blocked() != "":
		return false
	var p = _player()
	p.global_position = demo.town.spawn_pos() + Vector3(0, 0.05, 0)
	if p.has_method("align_to_ground"):
		p.call("align_to_ground", true)
	else:
		p.velocity = Vector3.ZERO
	var pl = demo.get("pilot")
	if pl != null and is_instance_valid(pl):
		pl.woke_in_pit()
	return true


# ------------------------------------------------------------------ flags

func _flags_page(v: VBoxContainer) -> void:
	_section(v, "World flags")
	var note := Label.new()
	note.text = "World flags the content reads (rumors, jobs, moods). Changes apply at once."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	_story_note(v, "the story sets these as you play. Shown here, not set.")
	_flags_box = VBoxContainer.new()
	v.add_child(_flags_box)
	_flag_new = _cheat(LineEdit.new())
	_flag_new.placeholder_text = "custom_flag"
	_flag_new.custom_minimum_size = Vector2(260, 0)
	var add: Button = _cheat(Button.new())
	add.text = "Set"
	add.pressed.connect(func():
		var n := _flag_new.text.strip_edges()
		if n != "":
			WorldState.set_flag(n)
			_flag_new.text = ""
			_rebuild_flags())
	_row(v, "Add", _flag_new).add_child(add)


func _rebuild_flags() -> void:
	for c in _flags_box.get_children():
		c.queue_free()
	for flag in known_flags():
		var cb := CheckBox.new()
		cb.text = flag
		cb.button_pressed = WorldState.has_flag(flag)
		cb.disabled = WorldState.story_mode()   # made fresh each refresh, so not a _cheat
		cb.toggled.connect(func(on): WorldState.set_flag(flag, on))
		_flags_box.add_child(cb)


## Flags set now, plus every flag a rumor, job or mood rule asks about. Sorted.
func known_flags() -> Array:
	var seen := {}
	for f in WorldState.flags:
		seen[str(f)] = true
	var reqs: Array = []
	for r in WorldState.all_rumors():
		reqs.append(r.get("requires", {}))
	for j in WorldState.board():
		reqs.append(j.get("requires", {}))
	for req in reqs:
		for f in req.get("flags", []) + req.get("not_flags", []):
			seen[str(f)] = true
	if demo != null and demo.bar != null and demo.bar.brain != null:
		for r in demo.bar.brain.card.get("mood_rules", []):
			for f in r.get("if_flags", []):
				seen[str(f)] = true
	var out := seen.keys()
	out.sort()
	return out


# ------------------------------------------------------------------ story (issue #64)

func _story_page(v: VBoxContainer) -> void:
	_section(v, "Main story")
	var now := Label.new()
	now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(now)
	var pick := OptionButton.new()
	for id in Story.chapter_ids():
		pick.add_item(str(id).replace("_", " "))
	var go := Button.new()
	go.pressed.connect(func():
		if pick.selected >= 0:
			skip_chapter(str(Story.chapter_ids()[pick.selected])))
	_row(v, "Chapter", pick).add_child(go)
	_story_note(v, "chapters are there to be played, but if you are truly stuck you can skip ahead (never back).")
	skip_confirm = ConfirmationDialog.new()
	skip_confirm.title = "Skip ahead?"
	skip_confirm.dialog_text = STUCK_WARNING
	skip_confirm.dialog_autowrap = true
	skip_confirm.min_size = Vector2i(420, 0)
	skip_confirm.ok_button_text = "Yes"
	skip_confirm.cancel_button_text = "No"
	skip_confirm.confirmed.connect(func():
		Story.skip_to(_skip_to)
		var t := DayClock.story_due()     # issue #381: open on the chapter's time
		if t != "":
			demo.set_preset(t)
		refresh())
	v.add_child(skip_confirm)
	_refreshers.append(func():
		var b := WorldState.bounty
		now.text = "Now: %s save, %s%s" % ["story" if WorldState.story_mode() else "free roam", Story.chapter().replace("_", " "),
			("   ·   bounty on %s (%s)" % [b.name, b.state]) if str(b.get("state", "")) in ["out", "dead"] else ""]
		var at := Story.index(Story.chapter())
		pick.select(maxi(0, at))
		for i in pick.item_count:
			pick.set_item_disabled(i, WorldState.story_mode() and (i <= at or not Story.applies(Story.chapters()[i])))
		go.text = "Skip ahead" if WorldState.story_mode() else "Skip to it")


## The story save and the free roam save, side by side (SaveSlots): the one being
## played, and Play on the other (from where it was left, or a new game when it
## has none).
func _saves_page(v: VBoxContainer) -> void:
	_section(v, "Saves")
	for m in [[WorldState.STORY, "Story"], [WorldState.FREEPLAY, "Free roam"]]:
		var row := HBoxContainer.new()
		var about := Label.new()
		about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var play := Button.new()
		play.pressed.connect(func(): switch_save(m[0]))
		row.add_child(about)
		row.add_child(play)
		_row(v, m[1], row)
		_refreshers.append(func():
			var here: bool = SaveSlots.playing() == m[0]
			var s := SaveSlots.summary(m[0])
			if here:
				about.text = "Playing now: %s, %d credits" % [Story.chapter().replace("_", " "), WorldState.credits]
			elif bool(s.exists):
				about.text = "%s, %d credits" % [str(s.chapter).replace("_", " "), int(s.credits)]
			else:
				about.text = "None yet: Play starts one"
			play.text = "Playing" if here else "Play"
			play.disabled = here)
	var note := Label.new()
	note.text = "Each save keeps its own world, gear, ships, standing, names and outfit. This one is saved before the other opens; the town reloads."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)


# ------------------------------------------------------------------ LAN (issue #401)

var _lan_refresh: Callable = Callable()


## Play with friends on the same wifi: your name (remembered), Host, or the host's
## address and Join, Leave, and who is here. Free roam only: hosting from a story
## save opens the free roam save first.
func _lan_page(v: VBoxContainer) -> void:
	_anchors["LAN"] = _section(v, "Play with friends (LAN)")
	var name_box := LineEdit.new()
	name_box.text = NetSession.saved_name()
	name_box.placeholder_text = "Your name over your head"
	name_box.max_length = int(NetSession.n("name_max", 16))
	name_box.custom_minimum_size = Vector2(260, 0)
	name_box.text_changed.connect(func(t): NetSession.save_name(t))
	_row(v, "Your name", name_box)
	var host := Button.new()
	host.text = "Host a game"
	_row(v, "", host)
	var addr := LineEdit.new()
	addr.text = NetSession.saved_address()
	addr.placeholder_text = "Host's address, e.g. 192.168.1.20"
	addr.custom_minimum_size = Vector2(260, 0)
	var join := Button.new()
	join.text = "Join"
	var join_row := HBoxContainer.new()
	join_row.add_child(addr)
	join_row.add_child(join)
	_row(v, "Join a friend", join_row)
	var leave := Button.new()
	leave.text = "Leave"
	_row(v, "", leave)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(status)
	var said := [""]                 # a refusal or a "type your name" stays until the next click
	host.pressed.connect(func():
		said[0] = lan_host(name_box.text)
		_lan_refresh.call())
	var go_join := func():
		said[0] = lan_join(addr.text, name_box.text)
		_lan_refresh.call()
	join.pressed.connect(go_join)
	addr.text_submitted.connect(func(_t): go_join.call())
	leave.pressed.connect(func():
		said[0] = ""
		NetSession.leave()
		lan_left()                       # issue #549: your own town again
		_lan_refresh.call())
	_lan_refresh = func():
		var on := NetSession.active()
		host.disabled = on
		join.disabled = on
		addr.editable = not on
		name_box.editable = not on
		leave.disabled = not on
		status.text = NetSession.status_line() if on or said[0] == "" else said[0]
	_refreshers.append(_lan_refresh)


## Host a LAN game as `who`. Returns "" or why not. From a story save the free roam
## save opens first (the town reloads; the session carries on).
func lan_host(who: String) -> String:
	if NetSession.clean_name(who) == "":
		return NetSession.label("need_name")
	NetSession.save_name(who)
	if NetSession.host(get_tree(), who, _worn()) != OK:
		var line := NetSession.label("cannot_host")
		return line % NetSession.port() if line.contains("%d") else line
	if SaveSlots.playing() != WorldState.FREEPLAY:
		switch_save(WorldState.FREEPLAY)
	return ""


## Join the LAN game at `address` as `who`. Returns "" or why not; the host's answer
## comes later (lan_arrive, or a toast saying no).
func lan_join(address: String, who: String) -> String:
	if NetSession.clean_name(who) == "":
		return NetSession.label("need_name")
	if address.strip_edges() == "":
		return NetSession.label("need_address")
	NetSession.save_name(who)
	NetSession.save_address(address)
	if NetSession.join(get_tree(), address, who, _worn()) != OK:
		var line := NetSession.label("no_answer")
		return line % address if line.contains("%s") else line
	return ""


## The outfit the others see you in.
func _worn() -> Dictionary:
	var a := _avatar()
	return a.worn_outfit() if a != null else PlayerOutfit.load_outfit()


## Issue #401: the host let you in. This game is saved, then your free roam save
## opens on the host's planet with you beside T-89: no opening landing, no hello
## and tutorial from him. `reload` false: just the state (tests).
func lan_arrive(planet_id: String, reload := true) -> void:
	var persist := _persists()
	_save_left()
	_leave()
	SaveSlots.enter(WorldState.FREEPLAY, persist)
	GameFlow.resumed = true                 # the host's planet, not where the save was left
	GameFlow.planet_id = "" if planet_id == PlanetGen.home_id() or PlanetGen.build(planet_id).is_empty() else planet_id
	WorldState.set_flag(WorldState.FREE_OPENING, false)
	ShipSalesman.greeted = true
	NetSession.guest_spawn = true
	_reload(reload)


## Issue #549: the session is over (you left, or the host did). A guest standing
## in the host's town, where the host's game ran the people, gets their own town
## back where they stand: this save is kept, then the town is built again from it
## (lan_arrive the other way round). Flying or riding, the town waits until you
## stand (TownDemo.lan_rebuild_waiting). Hosting, or a guest in a town of their
## own, nothing changes. `reload` false: just the state (tests).
func lan_left(reload := true) -> void:
	if demo == null or not bool(demo.get("lan_shared")):
		return
	if NetSession.active():
		demo.lan_rebuild_waiting = false    # joined again before landing: the host's town it stays
		return
	if not demo.on_own_feet():
		demo.lan_rebuild_waiting = true
		return
	demo.lan_rebuild_waiting = false
	var at: Vector3 = demo._player.global_position
	_save_left()
	_leave()
	GameFlow.resumed = true                 # this planet, not where the save was left
	GameFlow.resume_pos = at
	_reload(reload)


## Issue #64: start again, as a story or as free roam.
func _new_game_page(v: VBoxContainer) -> void:
	_section(v, "New game")
	var note := Label.new()
	note.text = "Starts that save again as on a first play: credits, gear, droids, ships, every flag, faction standing and what each character thinks of you. Its names are kept. The other save is not touched. The town reloads.\nStory: the story from the start, every faction neutral, the pistol only, locked to the smuggler.\nFree roam: drops and bounties on repeat, any character."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var row := HBoxContainer.new()
	for m in [[WorldState.STORY, "New story game"], [WorldState.FREEPLAY, "New free roam game"]]:
		var b := Button.new()
		b.text = m[1]
		b.pressed.connect(func(): new_game(m[0]))
		row.add_child(b)
	_row(v, "", row)


## Move the main story to chapter `id`. Free roam: at once, any chapter. A story
## save: only ahead, and only after the player says yes to STUCK_WARNING (the
## characters may have a hint first). Returns false when it will not skip.
func skip_chapter(id: String) -> bool:
	if Story.index(id) < 0:
		return false
	if not WorldState.story_mode():
		Story.skip_to(id)
		refresh()
		return true
	if Story.index(id) <= Story.index(Story.chapter()) or not Story.applies(Story.chapter_cfg(id)):
		return false
	_skip_to = id
	skip_confirm.popup_centered()
	return true


## Issue #64: back to the start, as on a first play. Everything the player has or
## has done goes (WorldState: credits, gear, droids, the bought ship, flags,
## standing, the story), every character's opinion of them goes back to a
## stranger's, T-89 says hello again. Issue #834: new people and ship names (a new
## name seed); places, gear and the story cast keep theirs. Issue #200: in
## `mode` (WorldState.STORY or FREEPLAY), in that mode's own save (SaveSlots): a
## new story game never touches the free roam save, nor the other way round. The
## game being left is saved first, then the town is built again from scratch, as
## on a launch (SaveSlots.fresh_launch). `reload` false: just the state (tests).
func new_game(mode: String, reload := true) -> void:
	var persist := _persists()
	if persist and mode != SaveSlots.current():
		_save_left()
	_leave()
	SaveSlots.start(mode, NameBook.fresh(), persist)
	if demo != null and demo.bar != null:
		for s in demo.bar.spots:
			s.brain.rel = Relationship.new()
	_reload(reload)


## Play `mode`'s save instead of this one: this one is saved, then the other opens
## from where it was left (a new game there when it has none). `reload` false:
## just the state (tests).
func switch_save(mode: String, reload := true) -> void:
	var persist := _persists()
	if persist and mode == SaveSlots.current():
		return
	_save_left()
	_leave()
	SaveSlots.enter(mode, persist)
	_reload(reload)


## This town saves to disk (not a test's or a trace's).
func _persists() -> bool:
	return demo != null and demo.bar != null and demo.bar.autosave


## Save the game being left in its slot, unless it never started (a first launch's
## menu is still up: there is nothing to keep).
func _save_left() -> void:
	if demo != null and demo.bar != null and not demo.bar.fresh:
		_save()


## The town being left must not save again on its way out: by then WorldState is
## the next game's.
func _leave() -> void:
	if demo != null and demo.bar != null:
		demo.bar.autosave = false


func _reload(reload: bool) -> void:
	if not reload or not is_inside_tree():
		return
	visible = false
	get_tree().paused = false
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ save

func _save() -> void:
	if demo != null and demo.bar != null:
		demo.bar._save_memory()


# ------------------------------------------------------------------ LLM (issue #80)

## The AI brain settings (they were a separate F10 panel): where the cantina
## owner's brain runs, its URLs, models and key, Test and Save.
func _llm_page(v: VBoxContainer) -> void:
	_anchors["LLM"] = _section(v, "AI characters' brain  (F10 jumps here)")
	var bar = demo.bar if demo != null and "bar" in demo else null
	if bar != null and bar.settings != null:
		bar.settings.embed_into(v, self)
		_refreshers.append(func(): bar.settings._load())
	else:
		var l := Label.new()
		l.text = "No AI characters in this scene."
		v.add_child(l)


# ------------------------------------------------------------------ HUD (issue #52)

## Every bound control (project.godot), by when it applies. Keep it in step with the input map.
## Keys are written as the HUD writes them: each one in brackets, "Hold [B]" for a hold.
const KEYS := [
	["On foot", [
		["[W] [A] [S] [D]", "Walk (tap for steps, hold to run); arrows too"],
		["[Space]", "Jump (hold for the jetpack)"],
		["[Right Shift]", "Sprint: faster, gun down, spends stamina"],
		["[C]", "Crouch"],
		["[V]", "First / third person (mouse middle button too)"],
		["[E]", "Interact: talk, board, ride, pick up"],
		["[W] into a ladder", "Climb it ([S] slides down, [Space] lets go; [E] at its top climbs down)"],
		["[G]", "Put on / take off your gear"],
		["[Z]", "Rest, at a tent"],
		["[I]", "What you carry, the job log, and Call (your ship flies to you)"],
	]],
	["Weapons", [
		["[1] / [2] / [3] / [8]", "Blaster / rifle / sniper rifle / energy sword (same key again holsters)"],
		["[Q] / [H]", "Last weapon / holster"],
		["[Tab] or wheel", "Next weapon"],
		["[LMB]", "Fire or swing"],
		["[RMB]", "Aim (blaster) or block (sword), toggles; with the sniper a second click zooms in twice as far"],
		["[R]", "Reload"],
		["Hold [F]", "Aim a grenade: a dotted arc shows where it lands; let go to throw"],
	]],
	["Flying", [
		["[W] / [S]", "Pitch ([W] pushes the nose down); the mouse steers too"],
		["[A] / [D]", "Turn"],
		["[Q] / [E]", "Roll"],
		["[R] / [F]", "Throttle up / down"],
		["[Shift]", "Boost"],
		["[C]", "Take off, and land on what is below"],
		["[Z]", "Land in the bay when near it (again to take her back)"],
		["[Space] or [LMB]", "Guns"],
		["[X] or [RMB]", "Seeker missile, once locked"],
		["[T]", "Next target"],
		["[J]", "Radio: next station, then off"],
		["[V]", "Chase / cockpit view"],
		["Hold [B]", "Eject, in the air"],
		["[E]", "Get out, once landed"],
	]],
	["Everywhere", [
		["[F1]", "Info: planet, town, time, credits, standing"],
		["[F3]", "AI debug overlay"],
		["[F4]", "Guard debug (what each guard sees and hears; free roam only)"],
		["[F10]", "AI model settings: the AI brain under Options here ([Shift]+[F10]: next model)"],
		["[F11]", "These settings"],
		["[M]", "The map: click a place for a waypoint"],
		["[L]", "Cycle the lighting"],
		["[Esc]", "Free the mouse, close a panel"],
	]],
]


func _hud_page(v: VBoxContainer) -> void:
	_section(v, "HUD colour")
	var grid := GridContainer.new()
	grid.columns = 3
	for name in RetroUI.PRESETS:
		var b := Button.new()
		b.text = name
		b.custom_minimum_size = Vector2(190, 0)
		b.pressed.connect(func(): _set_hud_color(RetroUI.PRESETS[name]))
		grid.add_child(b)
	v.add_child(grid)
	var pick := ColorPickerButton.new()
	pick.custom_minimum_size = Vector2(120, 30)
	pick.edit_alpha = false
	pick.color = RetroUI.accent
	pick.color_changed.connect(_set_hud_color)
	_row(v, "Your own", pick)
	_refreshers.append(func(): pick.color = RetroUI.accent)
	# Issue #71: one number sizes every UI element; saved per machine.
	_section(v, "Text size")
	RetroUI.load_settings()
	var ui := RetroUI.ui()
	var size := _slider(int(round(float(ui.get("min", 0.75)) * 100.0)), int(round(float(ui.get("max", 2.0)) * 100.0)))
	size.step = float(ui.get("step", 0.05)) * 100.0
	size.value = roundf(RetroUI.text_scale * 100.0)
	var shown := Label.new()
	shown.text = "%d%%" % int(size.value)
	size.drag_ended.connect(func(_changed): RetroUI.set_text_scale(get_tree(), size.value / 100.0))
	size.value_changed.connect(func(x):
		shown.text = "%d%%" % int(x)
		if not size.has_focus():
			RetroUI.set_text_scale(get_tree(), x / 100.0))
	var row := _row(v, "Size", size)
	row.add_child(shown)
	var reset := Button.new()
	reset.text = "Default"
	reset.pressed.connect(func(): size.value = roundf(float(ui.get("text_scale", 1.75)) * 100.0); RetroUI.set_text_scale(get_tree(), size.value / 100.0))
	row.add_child(reset)
	_refreshers.append(func(): size.set_value_no_signal(roundf(RetroUI.text_scale * 100.0)); shown.text = "%d%%" % int(size.value))


func _keys_page(v: VBoxContainer) -> void:
	_section(v, "Controls")
	for group in KEYS:
		var head := Label.new()
		head.text = group[0]
		head.add_theme_color_override("font_color", Color("#d8b878"))
		v.add_child(head)
		for k in group[1]:
			var l := Label.new()
			l.text = k[0]
			l.custom_minimum_size = Vector2(150, 0)
			var h := _row(v, "", l)
			h.get_child(0).custom_minimum_size = Vector2(0, 0)
			var what := Label.new()
			what.text = k[1]
			h.add_child(what)


## Issue #16: the music and the effects each get a volume, saved per machine.
func _sound_page(v: VBoxContainer) -> void:
	_section(v, "Volume  (0 .. 100)")
	for bus in [[Sound.MUSIC_BUS, "Music"], [Sound.SFX_BUS, "Effects"]]:
		var s := _slider(0, 100)
		s.value = roundf(Sound.volume(bus[0]) * 100.0)
		s.value_changed.connect(func(x): Sound.set_volume(bus[0], x / 100.0))
		_row(v, bus[1], s)
		_refreshers.append(func(): s.set_value_no_signal(roundf(Sound.volume(bus[0]) * 100.0)))


## Lower it if near things (the hands in first person, a ship's interior) look far
## too bright: some Windows GPUs overdo the bounce light (LookEnvironment.indirect_level).
func _graphics_page(v: VBoxContainer) -> void:
	_section(v, "Graphics")
	var s := _slider(0, 100)
	s.value = roundf(LookEnvironment.indirect_level() * 100.0)
	s.value_changed.connect(func(x):
		if demo != null and demo.look != null:
			demo.look.set_indirect(x / 100.0)
		else:
			LookEnvironment.save_indirect_level(x / 100.0)
		SavePrefs.save_soon(get_tree()))
	_row(v, "Indirect light", s)
	var note := Label.new()
	note.text = "How strong the bounce light and the sky's fill are."
	note.add_theme_font_size_override("font_size", 12)
	v.add_child(note)
	_refreshers.append(func(): s.set_value_no_signal(roundf(LookEnvironment.indirect_level() * 100.0)))
	# Issue #534: the temporal upscaler is the anti-aliasing; off falls back to FXAA
	# at full size, for a machine where it smears fast things.
	var taa := CheckBox.new()
	taa.set_pressed_no_signal(LookEnvironment.taa())
	taa.toggled.connect(func(on):
		if demo != null and demo.look != null:
			demo.look.set_taa(on)
		else:
			LookEnvironment.save_taa(on)
		SavePrefs.save_soon(get_tree()))
	_row(v, "Temporal anti-aliasing", taa)
	var taa_note := Label.new()
	taa_note.text = "Smooth edges and a faster frame. Turn off if bolts or the sword leave trails."
	taa_note.add_theme_font_size_override("font_size", 12)
	v.add_child(taa_note)
	_refreshers.append(func(): taa.set_pressed_no_signal(LookEnvironment.taa()))
	# For slower PCs (LookEnvironment.low_graphics): what it turns off is in time_of_day.json.
	# Its pieces have a checkbox each, folded under "Advanced graphics settings" (a
	# click opens the list, another closes it), to try one at a time. Every change
	# is saved per machine and in every save file (GraphicsPrefs).
	var low := CheckBox.new()
	var boxes := {}
	var sync := func():
		low.set_pressed_no_signal(LookEnvironment.low_graphics())
		for id in boxes:
			boxes[id].set_pressed_no_signal(LookEnvironment.cut(id))
	var show_now := func():
		if demo != null and demo.look != null:
			demo.look.apply_low()
			if demo.draw_distance != null:
				demo.draw_distance.apply_low_graphics()
	low.toggled.connect(func(on):
		GraphicsPrefs.set_asked()
		LookEnvironment.save_low_graphics(on)
		show_now.call()
		sync.call()
		SavePrefs.save_soon(get_tree()))
	_row(v, "Low graphics", low)
	var low_note := Label.new()
	low_note.text = "Faster on slower PCs."
	low_note.add_theme_font_size_override("font_size", 12)
	v.add_child(low_note)
	var fold := Button.new()
	fold.name = "AdvancedGraphics"
	fold.flat = true
	fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(fold)
	var advanced := VBoxContainer.new()
	advanced.name = "AdvancedGraphicsList"
	advanced.add_theme_constant_override("separation", 6)
	v.add_child(advanced)
	var adv_note := Label.new()
	adv_note.text = "Low graphics one piece at a time (to find what causes a glare):"
	adv_note.add_theme_font_size_override("font_size", 12)
	advanced.add_child(adv_note)
	var show_fold := func(open: bool):
		fold.text = ("[-] " if open else "[+] ") + "Advanced graphics settings"
		advanced.visible = open
	fold.pressed.connect(func(): show_fold.call(not advanced.visible))
	show_fold.call(false)
	for p in LookEnvironment.pieces():
		var id := str(p.id)
		var b := CheckBox.new()
		b.toggled.connect(func(on):
			GraphicsPrefs.set_asked()
			LookEnvironment.save_cut(id, on)
			show_now.call()
			sync.call()
			SavePrefs.save_soon(get_tree()))
		boxes[id] = b
		_row(advanced, "    " + str(p.get("label", id)), b)
	sync.call()
	_refreshers.append(sync)


func _set_hud_color(c: Color) -> void:
	if RetroSkin.current != null:
		RetroSkin.current.set_color(c)
	else:
		RetroUI.accent = c
		RetroUI.save_settings()


# ------------------------------------------------------------------ layout

## A scrolling page in the tab container; returns the column to fill.
func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	return v


## A section's heading (upper case, gold). Returns it (open_tab can scroll to it).
func _section(v: VBoxContainer, text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", Color("#d8b878"))
	v.add_child(l)
	return l


func _row(v: VBoxContainer, label: String, c: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(160, 0)
	h.add_child(l)
	h.add_child(c)
	v.add_child(h)
	return h


func _slider(lo: float, hi: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.custom_minimum_size = Vector2(300, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


func _spin(lo: float, hi: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	return s
