class_name WeldSpot
extends Node3D
## Issue #722: something the plasma welder can fix, hung where you stand to fix
## it (a child of the speeder, the droid, the ship). PlayerWelder looks through
## WeldSpot.all for the nearest one in reach whose `need` holds. Its owner fills in:
##   need:  () -> bool    does it want welding right now?
##   label: () -> String  what it is, for the prompt ("your speeder")
##   block: () -> String  "" when it can be welded, else why not (the prompt says
##                        it instead): "needs 10 flasks of refined quantonium"
##   done:  () -> void    welded: fix it
##   use_e: false when E belongs to something else here (a parked speeder: E
##          mounts it), so only fire with the welder drawn welds it.
## The list is kept by entering and leaving the tree, so finding one scans no tree.

static var all: Array = []

var need := Callable()
var label := Callable()
var block := Callable()
var done := Callable()
var use_e := true
var reach := -1.0                   ## metres; < 0 = Welder.reach()
var spark_height := 0.6             ## where the sparks land, metres above the spot


static func make(p_need: Callable, p_label: Callable, p_done: Callable, p_block := Callable(), p_use_e := true) -> WeldSpot:
	var s := WeldSpot.new()
	s.name = "WeldSpot"
	s.need = p_need
	s.label = p_label
	s.done = p_done
	s.block = p_block
	s.use_e = p_use_e
	return s


func _enter_tree() -> void:
	if not all.has(self):
		all.append(self)


func _exit_tree() -> void:
	all.erase(self)


func needs() -> bool:
	return need.is_valid() and bool(need.call())


func what() -> String:
	return str(label.call()) if label.is_valid() else "it"


func blocked() -> String:
	return str(block.call()) if block.is_valid() else ""


func weld() -> void:
	if done.is_valid():
		done.call()


func range_m() -> float:
	return reach if reach > 0.0 else Welder.reach()
