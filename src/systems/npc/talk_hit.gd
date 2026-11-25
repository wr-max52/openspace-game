class_name TalkHit
extends StaticBody3D
## Issue #606: what bolts and blades find on a talk-only NPC (a merchant at his
## stall, the mechanic, the cantina owner behind her bar): a hit lands (the
## hit marker shows, HitFeedback reads damage_usec) and the NPC flinches, but they
## take no damage and never die, so trading, jobs and the story stay as they are.
##
## On the enemies' layer like the crowds' hit capsules (StationCrowd.CrowdHit,
## PartyBarge.PartyHit): bolts and blades find it, the player walks past it.

const LAYER_ENEMIES := 1 << 3

signal hit(shooter: Node)

var owner_npc: Node                  ## the NPC it belongs to: flinch() if it has one
var damage_usec := 0                 ## Time.get_ticks_usec() of the last hit (hit markers)
var dead := false                    ## never: talk-only NPCs take no damage
var hits_taken := 0


## A capsule `height` tall standing on `npc`'s origin, added under it.
static func make(npc: Node3D, radius := 0.35, height := 1.8) -> TalkHit:
	var h := TalkHit.new()
	h.name = "TalkHit"
	h.owner_npc = npc
	h.collision_layer = LAYER_ENEMIES
	h.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	cs.shape = cap
	cs.position = Vector3(0, height * 0.5, 0)
	h.add_child(cs)
	npc.add_child(h)
	return h


func apply_damage(amount: float) -> void:
	_take(amount, null)


func apply_damage_from(amount: float, shooter: Node) -> void:
	_take(amount, shooter)


func apply_blade_hit(amount: float, _sweep: Vector3) -> void:
	_take(amount, null)


func _take(amount: float, shooter: Node) -> void:
	if amount <= 0.0:
		return
	hits_taken += 1
	if owner_npc != null and is_instance_valid(owner_npc) and owner_npc.has_method("flinch"):
		owner_npc.flinch()
	hit.emit(shooter)
	damage_usec = Time.get_ticks_usec()       # last, so the marker reads it fresh
