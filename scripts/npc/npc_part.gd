@tool
class_name NPCPart
extends Resource
## Una parte del corpo di un NPC: quale forma usa, un'eventuale seconda forma verso cui
## fare morph, e lo spessore. Braccia e gambe usano la stessa parte sui due lati.

@export var shape: SegmentShape:
	set(v):
		var old := shape
		shape = v
		_rewire(old)
		emit_changed()
## Seconda forma: con morph > 0 gli anelli vengono interpolati fra le due.
@export var shape_b: SegmentShape:
	set(v):
		var old := shape_b
		shape_b = v
		_rewire(old)
		emit_changed()
@export_range(0.0, 1.0, 0.01) var morph := 0.0:
	set(v):
		morph = v
		emit_changed()
@export_range(0.5, 1.8, 0.01) var thickness := 1.0:
	set(v):
		thickness = v
		emit_changed()


func _init(s: SegmentShape = null) -> void:
	if s != null:
		shape = s


## La stessa forma può stare in entrambi gli slot: si scollega solo se non è più usata.
func _rewire(old: Resource) -> void:
	if old != null and old != shape and old != shape_b and old.changed.is_connected(emit_changed):
		old.changed.disconnect(emit_changed)
	for s in [shape, shape_b]:
		if s != null and not s.changed.is_connected(emit_changed):
			s.changed.connect(emit_changed)
