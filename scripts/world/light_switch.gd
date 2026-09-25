@tool
class_name LightSwitch
extends StaticBody3D
## Interruttore a muro: accende/spegne un gruppo di LightFixture.

## Le luci (LightFixture) comandate da questo interruttore.
@export var targets: Array[NodePath] = []

var lights: Array = []
var is_on := true
var _lever: MeshInstance3D


func setup(pos: Vector3, yaw_deg: float, light_nodes: Array) -> LightSwitch:
	position = pos
	rotation_degrees.y = yaw_deg
	lights = light_nodes
	return self


func _ready() -> void:
	collision_layer = Layers.INTERACT
	collision_mask = 0
	Util.box(self, Vector3(0.14, 0.22, 0.04), Vector3.ZERO, Util.color_mat(Color(0.7, 0.7, 0.66)))
	_lever = Util.box(self, Vector3(0.05, 0.09, 0.05), Vector3(0, 0.04, 0.03), Util.color_mat(Color(0.2, 0.2, 0.2)))
	Util.add_box_collider(self, Vector3(0.25, 0.3, 0.12))
	if Engine.is_editor_hint():
		return
	for p in targets:
		var n := get_node_or_null(p)
		if n != null and not (n in lights):
			lights.append(n)


func get_frob_text() -> String:
	return "Interruttore luci (" + ("spegni" if is_on else "accendi") + ")"


func frob(_player: Node) -> void:
	is_on = not is_on
	_lever.position.y = 0.04 if is_on else -0.04
	Sfx.play_3d("ui_click", global_position, 4.0)
	for l in lights:
		if is_instance_valid(l):
			l.set_on(is_on)
