@tool
class_name ServerCore
extends StaticBody3D
## Il server con il nucleo SERAPH-7. Estrarre il nucleo avvia il lockdown.

var taken := false
var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _t := 0.0


func setup(pos: Vector3, yaw_deg: float) -> ServerCore:
	position = pos
	rotation_degrees.y = yaw_deg
	return self


func _ready() -> void:
	collision_layer = Layers.INTERACT | Layers.WORLD
	collision_mask = 0
	var sm := Util.mat("server", {"fit": Vector3(1.4, 2.4, 0.9), "emission": 1.0, "emission_tex": "server_emit"})
	Util.box(self, Vector3(1.4, 2.4, 0.9), Vector3(0, 1.2, 0), sm)
	# alloggiamento del nucleo
	Util.box(self, Vector3(0.6, 0.5, 0.1), Vector3(0, 1.25, 0.46), Util.color_mat(Color(0.05, 0.06, 0.07)))
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = Color(0.4, 1.0, 0.95)
	_core = Util.cylinder(self, 0.12, 0.4, Vector3(0, 1.25, 0.5), _core_mat, Vector3(0, 0, 90), 6)
	_core.set_meta("keep_layers", true)
	Util.add_box_collider(self, Vector3(1.4, 2.4, 1.0), Vector3(0, 1.2, 0.05))
	if Engine.is_editor_hint():
		return
	add_to_group("server_cores")
	Sfx.attach_loop("server_hum", self, -4.0, 14.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or taken:
		return
	_t += delta
	_core_mat.albedo_color = Color(0.3, 0.9, 0.85).lerp(Color(0.8, 1.0, 1.0), 0.5 + 0.5 * sin(_t * 3.0))


func save_state() -> Dictionary:
	return {"taken": taken}


func load_state(d: Dictionary) -> void:
	taken = d.taken
	_core.visible = not taken
	# salvato nei pochi secondi fra il furto e il lockdown: il lockdown parte adesso
	if taken and not Game.lockdown:
		_start_lockdown.call_deferred()


func get_frob_text() -> String:
	if taken:
		return ""
	return tr("Extract the SERAPH-7 core")


func frob(_player: Node) -> void:
	if taken:
		return
	taken = true
	_core.visible = false
	Sfx.play_ui("pickup")
	Sfx.play_3d("whisper", global_position + Vector3.UP * 1.2, 4.0)
	Game.give_item("core")
	Game.complete_objective("core", 2)
	Game.add_objective("extract", "Get back to the service elevator with the core.")
	Game.say("???", tr("...don't shut me down... get me out..."), 3.5)
	# collegato a un metodo del nodo, non di Game: se nel frattempo si carica una partita
	# o si ricomincia, il nodo sparisce con la scena e il timer non fa più nulla
	get_tree().create_timer(3.8, false).timeout.connect(_start_lockdown)


func _start_lockdown() -> void:
	Game.start_lockdown()
