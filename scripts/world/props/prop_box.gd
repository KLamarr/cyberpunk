@tool
class_name PropBox
extends StaticBody3D
## Arredo a forma di scatola (scrivanie, casse, server, armadietti, vetri...).
## Mesh e collisione hanno sempre la stessa misura: cambia "Size" e basta.
## In gioco viene illuminato solo dalle luci della zona in cui si trova.

@export var size := Vector3.ONE:
	set(v):
		size = v
		_rebuild()
## Texture (assets/textures). Vuota = colore pieno ("Tint").
@export var texture: Texture2D:
	set(v):
		texture = v
		_rebuild()
## adatta: la texture copre ogni faccia una volta. densità: si ripete ogni 1/density metri.
@export_enum("adatta", "densita") var uv_mode := 0:
	set(v):
		uv_mode = v
		_rebuild()
@export var density := 1.0:
	set(v):
		density = v
		_rebuild()
@export var tint := Color.WHITE:
	set(v):
		tint = v
		_rebuild()
## Intensità emissiva (schermi, led). 0 = spento.
@export var emission := 0.0:
	set(v):
		emission = v
		_rebuild()
## Texture solo per l'emissione (es. i led di un server). Vuota = usa "Texture".
@export var emission_texture: Texture2D:
	set(v):
		emission_texture = v
		_rebuild()
## Meno di 1 = trasparente (vetri).
@export_range(0.0, 1.0, 0.01) var opacity := 1.0:
	set(v):
		opacity = v
		_rebuild()
## mondo: blocca tutto. vetro: blocca il passaggio ma non la vista delle guardie.
@export_enum("mondo", "vetro", "nessuna") var collision := 0:
	set(v):
		collision = v
		_rebuild()
@export var cast_shadows := true:
	set(v):
		cast_shadows = v
		_rebuild()

var _mesh: MeshInstance3D
var _shape: CollisionShape3D


func _ready() -> void:
	_rebuild()


func build_material() -> Material:
	if texture == null:
		var m := Util.color_mat(tint, emission)
		if opacity < 1.0:
			m = m.duplicate()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = opacity
		return m
	var opts := {"color": tint}
	if uv_mode == 0:
		opts["fit"] = size
	else:
		opts["density"] = density
	if emission > 0.0:
		opts["emission"] = emission
		if emission_texture != null:
			opts["emission_tex"] = emission_texture
	if opacity < 1.0:
		opts["transparent"] = opacity
	return Util.mat(texture, opts)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.mesh = BoxMesh.new()
		add_child(_mesh)
		_shape = CollisionShape3D.new()
		_shape.shape = BoxShape3D.new()
		add_child(_shape)
	(_mesh.mesh as BoxMesh).size = size
	(_shape.shape as BoxShape3D).size = size
	_mesh.material_override = build_material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows and opacity >= 1.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	collision_layer = [Layers.WORLD, Layers.GLASS, 0][collision]
	collision_mask = 0
	_shape.disabled = collision == 2
