@tool
class_name PropCylinder
extends Node3D
## Cilindro decorativo a pochi lati (tubi, colonne, capsule). Asse lungo la Y
## locale: ruota il nodo per orientarlo. Nessuna collisione: se serve, aggiungi
## un PropBox invisibile ("Opacity" 0) o usa un PropBox.

@export var radius := 0.1:
	set(v):
		radius = v
		_rebuild()
@export var length := 1.0:
	set(v):
		length = v
		_rebuild()
@export_range(3, 32) var sides := 6:
	set(v):
		sides = v
		_rebuild()
@export var texture: Texture2D:
	set(v):
		texture = v
		_rebuild()
@export var tint := Color.WHITE:
	set(v):
		tint = v
		_rebuild()
@export_range(0.0, 1.0, 0.01) var opacity := 1.0:
	set(v):
		opacity = v
		_rebuild()

var _mesh: MeshInstance3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.mesh = CylinderMesh.new()
		add_child(_mesh)
	var cm := _mesh.mesh as CylinderMesh
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = sides
	cm.rings = 1
	var opts := {"color": tint, "fit": Vector3(radius * 2.0, length, radius * 2.0)}
	if opacity < 1.0:
		opts["transparent"] = opacity
	_mesh.material_override = Util.mat(texture, opts) if texture != null else Util.color_mat(tint)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if opacity >= 1.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
