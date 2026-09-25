@tool
class_name LevelGeometry
extends CSGCombiner3D
## Radice della geometria del livello. Ordine dei figli:
##   1. "Solido": il blocco pieno (invisibile) da cui si scava tutto
##   2. le Zone, con i loro Brush d'aria
##   3. "Solidi": materia aggiunta (pilastri, fasce...)
## In gioco il CSG viene compilato da LevelBuilder in mesh statiche divise per
## zona e in una collisione unica; questo nodo poi viene rimosso.


func _ready() -> void:
	if Engine.is_editor_hint():
		child_order_changed.connect(update_configuration_warnings)


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if get_child_count() == 0 or not (get_child(0) is CSGBox3D) or get_child(0) is Brush:
		w.append("Il primo figlio deve essere il blocco 'Solido' (CSGBox3D) che contiene tutto il livello.")
	var last_zone := -1
	for c in get_children():
		if c is Zone:
			last_zone = c.get_index()
	for c in get_children():
		if c.get_index() > 0 and not (c is Zone) and c is CSGShape3D and c.get_index() < last_zone:
			w.append("'%s' deve stare sotto tutte le Zone (trascinalo in fondo): altrimenti le zone successive lo scavano." % c.name)
	return w
