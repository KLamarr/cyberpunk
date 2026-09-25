@tool
class_name Brush
extends CSGBox3D
## Brush del livello, alla DromEd.
## - Dentro una Zona è un volume d'ARIA: viene scavato dal blocco solido.
## - Dentro il nodo "Solidi" è MATERIA aggiunta (pilastri, fasce, gradini).
## Muovilo e ridimensionalo come un normale CSGBox3D (Size nell'Inspector).

## Texture e suono dei passi (risorsa SurfaceSet in assets/surfaces/).
@export var surface: SurfaceSet:
	set(v):
		surface = v
		_update_material()
		update_configuration_warnings()
## Zone in più a cui appartiene questo brush. Per un passaggio fra due stanze
## spunta anche la zona dell'altra stanza, così è illuminato da entrambe.
## Per i brush solidi indica la zona di appartenenza (obbligatoria).
@export_flags_3d_render var extra_zones := 0:
	set(v):
		extra_zones = v
		update_configuration_warnings()


func _ready() -> void:
	_update_material()


## Il materiale viene sempre dal SurfaceSet: non lo mostriamo e non lo salviamo
## nella scena (così modificare il SurfaceSet aggiorna tutti i brush).
func _validate_property(property: Dictionary) -> void:
	if property.name == "material":
		property.usage = PROPERTY_USAGE_NONE


func _update_material() -> void:
	material = surface.get_material() if surface != null else null


func get_zone_node() -> Zone:
	var p := get_parent()
	while p != null:
		if p is Zone:
			return p
		if p is LevelGeometry:
			return null
		p = p.get_parent()
	return null


## true = volume d'aria (scavato), false = materia aggiunta.
func is_air() -> bool:
	return get_zone_node() != null


func zone_mask() -> int:
	var z := get_zone_node()
	return (z.layer if z != null else 0) | extra_zones


func world_aabb() -> AABB:
	return global_transform * AABB(-size * 0.5, size)


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if surface == null:
		w.append("Manca il SurfaceSet: assegnane uno (assets/surfaces/).")
	if get_parent() is LevelGeometry:
		w.append("Spostalo dentro una Zona (volume d'aria) oppure dentro 'Solidi' (materia).")
	elif is_inside_tree() and not is_air() and extra_zones == 0:
		w.append("Brush solido senza zona: spunta in 'Extra Zones' la zona in cui si trova.")
	return w
