@tool
class_name PropQuad
extends MeshInstance3D
## Pannello piatto con una texture: insegne, poster, graffiti, schermi a muro.
## Guarda verso la Z positiva locale: appoggialo a 1-2 cm dal muro.

@export var size := Vector2(1, 1):
	set(v):
		size = v
		_rebuild()
@export var texture: Texture2D:
	set(v):
		texture = v
		_rebuild()
## Intensità emissiva (insegne luminose, schermi). 0 = normale.
@export var emission := 0.0:
	set(v):
		emission = v
		_rebuild()
## Usa la trasparenza della texture (graffiti, grate).
@export var alpha_cut := false:
	set(v):
		alpha_cut = v
		_rebuild()


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		Game.settings_changed.connect(_rebuild)   # insegne con scritte: cambia la lingua


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if not (mesh is QuadMesh):
		mesh = QuadMesh.new()
	(mesh as QuadMesh).size = size
	var opts := {"mesh_uv": true}
	if emission > 0.0:
		opts["emission"] = emission
	if alpha_cut:
		opts["alpha"] = true
	material_override = Util.mat(texture, opts) if texture != null else null
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
