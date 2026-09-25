@tool
class_name PatrolRoute
extends Node3D
## Percorso di pattuglia: i figli (Waypoint) in ordine, percorsi in ciclo.
## Assegnalo a una guardia nella proprietà "Patrol Route". Nell'editor il
## percorso è disegnato come una linea gialla.

var _line: MeshInstance3D
var _last_sig := ""
var _t := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_redraw()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	_t += delta
	if _t > 0.25:
		_t = 0.0
		_redraw()


func _redraw() -> void:
	var pts: Array[Vector3] = []
	for c in get_children():
		if c is Node3D and c != _line:
			pts.append((c as Node3D).position)
	var sig := str(pts)
	if sig == _last_sig:
		return
	_last_sig = sig
	if _line == null:
		_line = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.85, 0.2)
		m.no_depth_test = true
		_line.material_override = m
		add_child(_line)
	var im := ImmediateMesh.new()
	if pts.size() >= 2:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in pts:
			im.surface_add_vertex(p + Vector3.UP * 0.1)
		im.surface_add_vertex(pts[0] + Vector3.UP * 0.1)
		im.surface_end()
	_line.mesh = im
