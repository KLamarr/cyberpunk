@tool
class_name SurfaceSet
extends Resource
## Set di superfici per i Brush: texture di pareti, pavimento e soffitto,
## densità (ripetizioni per metro) e tipo di passi. Le texture sono proiettate
## in spazio mondo e scelte in base all'orientamento della faccia, quindi non
## serve allinearle a mano.
## Per crearne uno: FileSystem > tasto destro > Crea nuovo > Risorsa > SurfaceSet.

const SHADER := preload("res://shaders/level_surface.gdshader")

@export var wall_texture: Texture2D:
	set(v):
		wall_texture = v
		_refresh()
@export var floor_texture: Texture2D:
	set(v):
		floor_texture = v
		_refresh()
@export var ceiling_texture: Texture2D:
	set(v):
		ceiling_texture = v
		_refresh()
## Ripetizioni della texture per metro (0.5 = una texture ogni 2 m).
@export_range(0.05, 4.0, 0.05) var wall_scale := 0.5:
	set(v):
		wall_scale = v
		_refresh()
@export_range(0.05, 4.0, 0.05) var floor_scale := 0.5:
	set(v):
		floor_scale = v
		_refresh()
@export_range(0.05, 4.0, 0.05) var ceiling_scale := 0.5:
	set(v):
		ceiling_scale = v
		_refresh()
@export var tint := Color.WHITE:
	set(v):
		tint = v
		_refresh()
## Rumore dei passi sul pavimento (vedi Player._footstep).
@export_enum("metal", "grate", "concrete", "carpet") var footsteps := "concrete"

var _mat: ShaderMaterial


func get_material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_refresh()
	return _mat


func _refresh() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("tex_wall", wall_texture)
	_mat.set_shader_parameter("tex_floor", floor_texture)
	_mat.set_shader_parameter("tex_ceil", ceiling_texture)
	_mat.set_shader_parameter("wall_scale", wall_scale)
	_mat.set_shader_parameter("floor_scale", floor_scale)
	_mat.set_shader_parameter("ceil_scale", ceiling_scale)
	_mat.set_shader_parameter("tint", tint)
