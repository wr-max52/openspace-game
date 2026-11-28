extends GutTest
## Issue #714: flying home from the gas giant, home's scene loads fresh, so its
## once-a-session pieces are made on the way in (SpaceTravel._prepare, 30 km out):
## the rocks' meshes and colliders and the wrecks' parts, on worker threads. This
## checks the hand-over: after the prepare step, what the build asks for is already
## made, so building on the way down makes nothing new.

var _meshes: Dictionary
var _shapes: Dictionary
var _made_for: Dictionary
var _parts_keys: Array
var _parts_out: Array


func before_each() -> void:
	_meshes = DesertLandforms._meshes
	_shapes = DesertLandforms._shapes
	_made_for = DesertLandforms._made_for
	_parts_keys = StarcruiserWreck._parts_keys
	_parts_out = StarcruiserWreck._parts_out
	DesertLandforms._meshes = {}
	DesertLandforms._shapes = {}
	DesertLandforms._made_for = {}
	StarcruiserWreck._parts_keys = []
	StarcruiserWreck._parts_out = []


func after_each() -> void:
	DesertLandforms._meshes = _meshes
	DesertLandforms._shapes = _shapes
	DesertLandforms._made_for = _made_for
	StarcruiserWreck._parts_keys = _parts_keys
	StarcruiserWreck._parts_out = _parts_out


func test_the_rocks_are_all_made_before_the_build() -> void:
	var planet := PlanetGen.build(PlanetGen.home_id())
	assert_true(DesertLandforms.builds_on(planet), "home builds landforms")
	assert_true(DesertLandforms.prepare(planet), "the approach starts the rocks")
	await DesertLandforms.finish_prepared()
	var made := DesertLandforms._meshes.size()
	assert_gt(made, 0, "the worker made the rocks")
	var d := DesertLandforms.load_data()
	var sp := PlanetSphere.new(float(planet.world.terrain.sphere_radius))
	# What the landforms build asks for, in the build's own calls.
	for m in DesertLandforms.mountain_spots(d, sp):
		var got := DesertLandforms._mountain(m.plan, int(m.variant))
		assert_not_null(got.shape, "a mountain comes with its collider")
	for k in (d.get("spire_variants", []) as Array).size():
		DesertLandforms._spire(d, k)
	for hd in DesertLandforms.short_spots(d, sp):
		for job in DesertLandforms._hoodoo_jobs(hd):
			assert_true(DesertLandforms._meshes.has(job.key), "hoodoo %s is made" % job.key)
	if int(d.get("boulders", {}).get("count", 0)) > 0:
		assert_true(DesertLandforms._meshes.has("boulder"), "the boulder is made")
		assert_false(DesertLandforms._boulder_verts.is_empty(), "with the vertices its hulls need")
	assert_eq(DesertLandforms._meshes.size(), made, "building made nothing new")
	assert_false(DesertLandforms.prepare(planet), "a second arrival has nothing to prepare")


func test_the_wrecks_parts_come_from_the_worker() -> void:
	var planet := PlanetGen.build(PlanetGen.home_id())
	var wrecks: Array = planet.world.get("landmarks", []).filter(func(lm): return str(lm.get("kind", "")) == "wreck")
	assert_gt(wrecks.size(), 0, "home has wrecks")
	assert_true(StarcruiserWreck.prepare(planet), "the approach starts the wrecks")
	for lm in wrecks:
		var pitch := float(lm.get("pitch_deg", StarcruiserWreck.PITCH_DEG))
		var variant: Dictionary = lm.get("variant", {})
		var a: Array = StarcruiserWreck._parts_for(pitch, variant)
		assert_gt(a.size(), 0, "a wreck has parts")
		assert_same(a, StarcruiserWreck._parts_for(pitch, variant), "the worker's parts, not new ones")
