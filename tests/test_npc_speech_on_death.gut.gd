extends GutTest
## An NPC cut down mid-line stops talking: the line over their head goes with
## them (the speech timer only ticks while alive, so it used to hang there), and
## a bark queued after death never shows.


func _npc() -> NpcBody:
	var npc := NpcBody.new()
	npc.setup({ "archetype": "remnant_trooper" }, Vector3.ZERO, 0.0, null)
	add_child_autofree(npc)
	return npc


func test_dying_mid_line_clears_the_speech() -> void:
	var npc := _npc()
	npc.say("Halt! Show me your papers!", 5.0)
	assert_eq(npc.speaking(), "Halt! Show me your papers!")
	npc.apply_damage(100000.0)
	assert_true(npc.dead, "the hit kills him")
	assert_eq(npc.speaking(), "", "no line hangs over the body")


func test_the_dead_do_not_bark() -> void:
	var npc := _npc()
	npc.apply_damage(100000.0)
	npc.say("Over here!")
	assert_eq(npc.speaking(), "")
