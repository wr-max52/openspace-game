class_name SeekerLockView
extends Control
## The seeker launcher's lock on screen (PlayerWeapons fills it while aimed in):
## corner brackets on what it is locking, the lock filling a ring round them as
## the flight HUD's does round a target box, and LOCKED with the range once it
## holds. Amber while it builds, red once locked. Off screen it draws nothing
## (the lock only builds inside the cone round the crosshair).

const BUILDING := Color(1.0, 0.72, 0.3, 0.95)
const HELD := Color(1.0, 0.3, 0.22, 0.98)

var target_pos := Vector3.ZERO
var fraction := 0.0
var locked := false
var dist := 0.0


func _init() -> void:
	name = "SeekerLock"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(target_pos):
		return
	var sp := cam.unproject_position(target_pos)
	if not get_viewport_rect().has_point(sp):
		return
	var col := HELD if locked else BUILDING
	var h := 20.0 if locked else 26.0
	var arm := 8.0
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var c := sp + Vector2(sx * h, sy * h)
			draw_line(c, c - Vector2(sx * arm, 0.0), col, 2.0)
			draw_line(c, c - Vector2(0.0, sy * arm), col, 2.0)
	if fraction > 0.0:
		draw_arc(sp, h + 9.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(fraction, 0.0, 1.0), 40, col, 2.5)
	var font := ThemeDB.fallback_font
	var fs := 15
	var line := "LOCKED  %d m" % int(dist) if locked else "%d m" % int(dist)
	draw_string(font, sp + Vector2(h + 14.0, -h + 4.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
