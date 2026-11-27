extends GutTest
## M0: the core data layer loads every entry under content/core and exposes it
## by id. This is the proof the IP-neutral layer actually works.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var content


func before_each() -> void:
	content = CoreScript.new()


func test_loader_loads_manifest() -> void:
	var ok: bool = content.load_from()
	assert_true(ok, "load_from should succeed on the shipped content/core")
	assert_gt(content.manifest.size(), 0, "manifest should not be empty")


func test_all_weapons_present_by_id() -> void:
	content.load_from()
	var pistol: Dictionary = content.get_weapon("pistol_blaster")
	var rifle: Dictionary = content.get_weapon("rifle_blaster")
	var blade: Dictionary = content.get_weapon("energy_blade")
	assert_eq(pistol.get("class"), "pistol", "pistol class label")
	assert_eq(rifle.get("class"), "rifle", "rifle class label")
	assert_eq(blade.get("class"), "melee", "blade class label")
	assert_gt(pistol.get("damage", 0), 0, "pistol has damage")
	assert_eq(pistol.get("visible_bolt"), true, "pistol is a visible-bolt weapon")


func test_cantina_owner_is_the_only_llm_npc() -> void:
	content.load_from()
	var llm_count := 0
	for id in content.npcs:
		if content.get_npc(id).get("kind") == "llm":
			llm_count += 1
	assert_eq(llm_count, 1, "exactly one LLM-driven npc (the cantina owner)")
	var cantina_owner: Dictionary = content.get_npc("cantina_owner")
	assert_eq(cantina_owner.get("kind"), "llm", "cantina owner is LLM-driven")
	var expected := PackedStringArray(["give_rumor", "set_disposition", "offer_drink", "call_guards"])
	var tools: Array = cantina_owner.get("tools", [])
	for tool in expected:
		assert_true(tools.has(tool), "tool present: " + str(tool))
	assert_eq(tools.size(), int(expected.size()), "no tools outside the allowed set")


func test_cantina_owner_persona_prompt_is_loaded() -> void:
	content.load_from()
	var prompt: String = content.get_persona("cantina_owner")
	assert_gt(prompt.length(), 50, "persona prompt text is loaded")


func test_fixer_has_authored_dialogue() -> void:
	content.load_from()
	var lines: Array = content.get_dialogue("fixer_lines")
	assert_gt(lines.size(), 0, "fixer has authored dialogue lines")
	var first: Dictionary = lines[0]
	assert_true(first.has("line"), "dialogue line has text")
	assert_true(first.has("speaker"), "dialogue line has speaker")


func test_mission_loaded_by_id() -> void:
	content.load_from()
	var m: Dictionary = content.get_mission("crate_retrieval")
	assert_gt(m.size(), 0, "crate_retrieval mission is loaded")
	assert_eq(m.get("id"), "crate_retrieval", "mission id")
	assert_eq(m.get("fixer"), "fixer", "mission fixer id")
	assert_eq(m.get("objective_location"), "outpost", "mission objective location id")
	assert_eq(m.get("payout"), 150, "mission payout")
	var enemies: Dictionary = m.get("enemies", {})
	assert_eq(enemies.get("troopers"), 4, "4 troopers in the mission")
	assert_eq(enemies.get("duelist"), 1, "1 duelist in the mission")



## Issue #542: the dressings' palettes load and every colour in them parses.
func test_dressing_palettes_parse() -> void:
	var d: Dictionary = load("res://src/systems/look/dressing.gd").data()
	var pals: Dictionary = d.get("palettes", {})
	for id in ["barge", "club", "market", "station_fill", "outpost"]:
		assert_true(pals.has(id), "dressing.json has a %s palette" % id)
	var n := 0
	for id in pals:
		var p: Dictionary = pals[id]
		for name in p:
			if name == "note":
				continue
			var v = p[name]
			var list: Array = v if v is Array else [v]
			assert_gt(list.size(), 0, "%s.%s is not empty" % [id, name])
			for c in list:
				assert_true(c is String and str(c).begins_with("#") and str(c).length() == 7 and Color.html_is_valid(str(c)),
					"%s.%s: %s is a #rrggbb colour" % [id, name, str(c)])
				n += 1
	assert_gt(n, 250, "the six dressings' colours are in the file")
	var variants: Dictionary = d.get("variants", {})
	for v in variants:
		assert_true(pals.has(str((variants[v] as Dictionary).get("base", ""))), "variant %s names a palette as its base" % v)


func test_loader_tolerates_missing_root() -> void:
	var ok: bool = content.load_from("res://this/path/does/not/exist")
	assert_false(ok, "missing root returns false, not crash")
