extends GutTest
## Issue #542: the dressings' palettes are data (content/look/dressing.json). The
## market's canopies wear the palette's cloths, a planet's variant changes only
## the names it gives, and every fallback left in the scripts is the file's colour
## (so nothing changes on screen when the file is read).

const DressingScript := preload("res://src/systems/look/dressing.gd")
const TownBuildings := preload("res://src/systems/world/town_buildings.gd")
const TownMarket := preload("res://src/systems/world/town_market.gd")
const SCRIPTS := ["barge_look", "club_props", "club_dressing", "town_market", "station_fill", "remnant_outposts"]

var _root: Node3D


func after_each() -> void:
	DressingScript.override("market", {})
	DressingScript.use("")
	(DressingScript.data().get("variants", {}) as Dictionary).erase("test_variant")
	if _root != null:
		_root.free()
		_root = null


func test_market_canopies_wear_the_palette_cloths() -> void:
	var one := Color("#123456")
	DressingScript.override("market", { "cloths": ["#123456"] })
	var kit := TownBuildings.new(LookMaterials.new(), null)
	var market := TownMarket.new(kit)
	_root = Node3D.new()
	var stalls := []
	for i in 3:                      # a slanted canopy, a peaked tent and twin parasols
		stalls.append({ "id": "s%d" % i, "xf": Transform3D(Basis.IDENTITY, Vector3(i * 6.0, 0, 0)), "size": Vector3(1.4, 1.0, 3.0) })
	market.dress_at(_root, stalls)
	assert_eq(market.canopies.size(), 3, "three canopies")
	assert_gt(market.awnings.size(), 0, "canopy cloth was made")
	var plain := 0
	for a in market.awnings:
		var c: Color = ((a as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
		assert_true(c.is_equal_approx(one) or c.is_equal_approx(one.darkened(0.15)),
			"%s is the palette's one cloth (or its fringe, a shade darker): %s" % [a.name, c.to_html()])
		if c.is_equal_approx(one):
			plain += 1
	assert_gt(plain, 0, "the canopies themselves are that colour")


func test_a_variant_changes_only_its_names() -> void:
	var base: Color = DressingScript.c("club", "bar_steel", "#000000")
	var heads: Array = DressingScript.list("club", "rave_heads", "#000000")
	(DressingScript.data()["variants"] as Dictionary)["test_variant"] = { "base": "club", "rave_heads": ["#010203"] }
	DressingScript.use("test_variant")
	var six: Array = DressingScript.list("club", "rave_heads", "#000000", 6)
	assert_eq(six.size(), 6, "the variant's list, repeated to the six the rig indexes")
	for c in six:
		assert_eq(c, Color("#010203"), "every moving head is the variant's colour")
	assert_eq(DressingScript.c("club", "bar_steel", "#000000"), base, "a name the variant does not give stays the base's")
	assert_eq(DressingScript.list("market", "cloths", "#000000").size(), 6, "another palette is untouched")
	DressingScript.use("")
	assert_eq(DressingScript.list("club", "rave_heads", "#000000"), heads, "no variant: the base again")


func test_missing_names_fall_back() -> void:
	assert_eq(DressingScript.c("club", "no_such_colour", "#abcdef"), Color("#abcdef"), "a missing name is the fallback")
	assert_eq(DressingScript.list("nowhere", "cloths", "#abcdef"), [Color("#abcdef")], "a missing list is [fallback]")
	assert_eq(DressingScript.list("nowhere", "cloths", "#abcdef", 3).size(), 3, "padded to what the caller indexes")


func test_script_fallbacks_match_the_file() -> void:
	var pals: Dictionary = DressingScript.data().get("palettes", {})
	var re := RegEx.new()
	re.compile('Dressing\\.c\\("(\\w+)", "(\\w+)", "(#[0-9a-fA-F]{6})"\\)')
	# Issue #876: StationFill reads "station_fill" through _dc (a station's own
	# dressing first), so its fallbacks are that palette's.
	var fill_re := RegEx.new()
	fill_re.compile('_dc\\("(\\w+)", "(#[0-9a-fA-F]{6})"\\)')
	var n := 0
	for s in SCRIPTS:
		var text := FileAccess.get_file_as_string("res://src/systems/world/%s.gd" % s)
		assert_gt(text.length(), 0, "%s.gd read" % s)
		for m in re.search_all(text):
			n += 1
			var got = (pals.get(m.get_string(1), {}) as Dictionary).get(m.get_string(2), null)
			assert_eq(got, m.get_string(3), "%s.gd: %s.%s is the same colour in the file and the code" % [s, m.get_string(1), m.get_string(2)])
		for m in fill_re.search_all(text):
			n += 1
			var got = (pals.get("station_fill", {}) as Dictionary).get(m.get_string(1), null)
			assert_eq(got, m.get_string(2), "%s.gd: station_fill.%s is the same colour in the file and the code" % [s, m.get_string(1)])
		assert_false(text.contains("const CLOTHS") or text.contains("const FABRICS") or text.contains("const NEON"),
			"%s.gd keeps no palette consts" % s)
	assert_gt(n, 300, "the dressings read their colours from the palette")
