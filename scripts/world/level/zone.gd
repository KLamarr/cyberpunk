@tool
class_name Zone
extends CSGCombiner3D
## Una zona del livello: una stanza o un gruppo di ambienti. I Brush figli
## vengono uniti e scavati dal blocco solido.
## Il layer è anche il layer di render: le luci della zona illuminano solo
## questa zona, così la luce non passa attraverso i muri (come le lightmap del
## Dark Engine). Dai un nome ai layer in Impostazioni progetto > Nomi layer >
## Render 3D.

## Una sola casella: il bit di questa zona.
@export_flags_3d_render var layer := 1:
	set(v):
		layer = v
		update_configuration_warnings()
		if get_parent() != null:
			for z in get_parent().get_children():
				if z is Zone and z != self:
					z.update_configuration_warnings()


func _ready() -> void:
	operation = CSGShape3D.OPERATION_SUBTRACTION


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	var bits := 0
	for i in 20:
		if layer & (1 << i):
			bits += 1
	if bits != 1:
		w.append("Seleziona esattamente un layer: è il bit che identifica la zona.")
	if get_parent() != null:
		for z in get_parent().get_children():
			if z != self and z is Zone and (z as Zone).layer == layer:
				w.append("Stesso layer della zona '%s': ogni zona deve avere il suo." % z.name)
	return w
