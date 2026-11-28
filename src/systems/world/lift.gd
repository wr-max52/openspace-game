class_name Lift
extends Node3D
## Issue #877: a glass lift up a mountain town's peak: the space station's
## elevator (src/systems/world/space_station.gd: its car, its stops, its "you are
## at its door, it waits for you" rule) with two stops, the sand by the peak's
## foot and the top, in a glass tube. It stands in its parent's frame (the peak's:
## y up), its shaft at `at` (x, z). The car is an AnimatableBody3D, so you stand on
## it and ride; the tube's panels are colliders, open at the bottom on its far side
## from the rock (+x) and at the top toward the bridge (-x).
##
## It waits at a stop until someone steps on (it goes to the other stop) or stands
## at a door on the other floor (it comes for them).

const CharBody := preload("res://src/systems/player/character_body.gd")
const CAR_H := 0.5

var at := Vector2.ZERO             ## the shaft's middle, in the parent's frame
var stops: Array = []              ## [bottom y, top y]
var radius := 2.6
var speed := 5.0
var wait_s := 3.0
var player_of: Callable            ## () -> Vector3 the player's world position, or INF
var car: AnimatableBody3D
var car_look: Node3D
var i := 0                         ## the stop it is at (or left)
var target := 0
var moving := false
var wait := 0.0
var y := 0.0                       ## the car's top, parent frame
var prev := 0.0
var tick := 0
var rides := 0                     ## trips with someone on (tests)


func setup(cfg: Dictionary, shaft: Vector2, bottom: float, top: float, who: Callable) -> void:
	name = "Lift"
	at = shaft
	stops = [bottom, top]
	radius = float(cfg.get("car_radius", 2.6))
	speed = float(cfg.get("speed", 5.0))
	wait_s = float(cfg.get("wait", 3.0))
	player_of = who
	y = bottom
	prev = bottom
	car = AnimatableBody3D.new()
	car.name = "Car"
	car.sync_to_physics = true
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = CAR_H
	cs.shape = shape
	cs.position = Vector3(0, -CAR_H * 0.5, 0)
	car.add_child(cs)
	car.position = Vector3(at.x, y, at.y)
	add_child(car)


## The tube's panels: `panels` round the shaft from the bottom stop to `over` m
## above the top, each a collider, with a door gap at each stop (bottom +x, top -x).
func walls(panels: int, over: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Tube"
	var r := radius + 0.35
	var b := float(stops[0])
	var t := float(stops[1])
	for k in panels:
		var a := TAU * (float(k) + 0.5) / float(panels)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var spans: Array = [[b, t + over]]
		if dir.x > 0.75:
			spans = [[b + 3.2, t + over]]                 # the bottom's door, away from the rock
		elif dir.x < -0.75:
			spans = [[b, t], [t + 3.2, t + over]]         # the top's door, onto the bridge
		for s in spans:
			if float(s[1]) - float(s[0]) < 0.2:
				continue
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.2, float(s[1]) - float(s[0]), TAU * r / float(panels) + 0.1)
			cs.shape = shape
			cs.transform = Transform3D(Basis(Vector3.UP, -a), Vector3(at.x, 0, at.y) + dir * r
				+ Vector3(0, (float(s[0]) + float(s[1])) * 0.5, 0))
			body.add_child(cs)
	add_child(body)
	return body


func _physics_process(dt: float) -> void:
	var pw: Vector3 = player_of.call() if player_of.is_valid() else Vector3.INF
	var p := Vector3.INF if pw == Vector3.INF else global_transform.affine_inverse() * pw
	step(dt, p)


## One tick: `p` the player in the parent's frame (INF: nobody).
func step(dt: float, p: Vector3) -> void:
	var on_car := p != Vector3.INF and Vector2(p.x - at.x, p.z - at.y).length() <= radius + 0.3 and absf(p.y - y) < 2.5
	prev = y
	tick = Engine.get_physics_frames()
	if moving:
		var ty := float(stops[target])
		y = move_toward(y, ty, speed * dt)
		car.position = Vector3(at.x, y, at.y)
		if absf(y - ty) < 0.001:
			moving = false
			i = target
			wait = wait_s
			if on_car:
				rides += 1
		return
	wait -= dt
	if wait > 0.0:
		return
	var next := -1
	if on_car:
		next = 1 - i
	else:
		var called := called_stop(p)
		if called == i or called < 0:
			wait = 0.5             # at its door, or nobody about: it waits
			return
		next = called
	target = next
	moving = true


## The stop whose door the player stands at (within a few metres of the shaft,
## level with it), or -1.
func called_stop(p: Vector3) -> int:
	if p == Vector3.INF or Vector2(p.x - at.x, p.z - at.y).length() > radius + 4.0:
		return -1
	for k in stops.size():
		if p.y >= float(stops[k]) - 0.5 and p.y <= float(stops[k]) + 3.0:
			return k
	return -1


## The car's look follows it between ticks, like the station's (draw_y).
func _process(_dt: float) -> void:
	if car_look == null:
		return
	var dy := y
	if CharBody.smoothing_active() and Engine.get_physics_frames() - tick <= 1:
		dy = lerpf(prev, y, Engine.get_physics_interpolation_fraction())
	car_look.position = Vector3(at.x, dy, at.y)
