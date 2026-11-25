extends SceneTree
## Vehicle textures import GPU-compressed (VRAM compressed), not lossless: a
## 2048 map is 21 MiB uncompressed and 2.7 to 5.3 MiB compressed, and every paint
## job carries four. Godot extracts a vehicle .glb's textures as lossless PNGs and
## only switches them to VRAM compressed when the editor draws them in 3D, which a
## headless import never does, so prep_vehicle.gd's new models come out heavy.
## Run this after a new model is prepped and imported, then import again:
##
##   godot --headless --path . --import
##   godot --headless --path . -s res://tools/look/vram_textures.gd
##   godot --headless --path . --import
##
## Colour maps (albedo, diffuse) BC7/ASTC, normal maps RGTC, ORM and glow maps
## DXT1/ETC2. All the vehicles' textures came down from 1190 to 277 MiB
## (DECISIONS, "Vehicle textures are GPU-compressed"). Only the .import files in
## DIR change; the PNGs stay as they are.

const DIR := "res://assets/vehicles/"
const PARAMS := {
	"compress/mode": 2,               # VRAM compressed
	"detect_3d/compress_to": 0,       # already compressed: nothing to detect
	"mipmaps/generate": true,
}


func _init() -> void:
	var changed := 0
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".png.import"):
			continue
		var cf := ConfigFile.new()
		if cf.load(DIR + f) != OK:
			push_error("vram_textures: cannot read " + f)
			continue
		var want := PARAMS.duplicate()
		# Colour maps BC7: DXT1 blocks thin paint stripes and smooth canopy shading
		# up close. Normal maps RGTC (BC7's size, the usual normal-map format), ORM
		# and glow maps DXT1: no visible change at half BC7's size, and BC7 is the
		# slow one to import.
		want["compress/high_quality"] = f.contains("_albedo") or f.contains("_diffuse")
		if f.contains("_normal"):
			want["compress/normal_map"] = 1
		var dirty := false
		for k in want:
			if cf.get_value("params", k, null) != want[k]:
				cf.set_value("params", k, want[k])
				dirty = true
		if dirty:
			cf.save(DIR + f)
			changed += 1
			print("vram_textures: " + f)
	print("vram_textures: %d .import files changed; run godot --headless --path . --import" % changed)
	quit()
