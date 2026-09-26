@tool
class_name LightSwitch
extends StaticBody3D
## Interruttore a muro: accende/spegne un gruppo di luci (LightFixture) o toglie la
## corrente a un cavo scoperto (LiveCable). Funziona con qualunque nodo che abbia set_on().

## Le luci o i cavi comandati da questo interruttore.
@export var targets: Array[NodePath] = []
## light: interruttore della luce. power: interruttore della corrente (per i cavi).
@export_enum("light", "power") var switch_type := "light"

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
	if switch_type == "power":
		return tr("Power switch (turn off)") if is_on else tr("Power switch (turn on)")
	return tr("Light switch (turn off)") if is_on else tr("Light switch (turn on)")


func save_state() -> Dictionary:
	return {"on": is_on}


## Le luci collegate si salvano da sole: qui solo la leva.
func load_state(d: Dictionary) -> void:
	is_on = d.on
	_lever.position.y = 0.04 if is_on else -0.04


func frob(_player: Node) -> void:
	is_on = not is_on
	_lever.position.y = 0.04 if is_on else -0.04
	Sfx.play_3d("ui_click", global_position, 4.0)
	for l in lights:
		if is_instance_valid(l):
			l.set_on(is_on)
