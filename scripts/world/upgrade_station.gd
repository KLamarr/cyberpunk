@tool
class_name UpgradeStation
extends StaticBody3D
## Stazione di potenziamento neurale: spendi i cyber-moduli per alzare le skill
## (omaggio alle stazioni di System Shock 2).


func setup(pos: Vector3, yaw_deg: float) -> UpgradeStation:
	position = pos
	rotation_degrees.y = yaw_deg
	return self


func _ready() -> void:
	collision_layer = Layers.INTERACT | Layers.WORLD
	collision_mask = 0
	Util.box(self, Vector3(0.9, 2.1, 0.5), Vector3(0, 1.05, 0), Util.mat("wall_tech", {"fit": Vector3(0.9, 2.1, 0.5)}))
	var scr := Util.box(self, Vector3(0.6, 0.5, 0.02), Vector3(0, 1.45, 0.26), Util.mat("screen_blue", {"fit": Vector3(0.6, 0.5, 0.02), "emission": 1.6}))
	scr.set_meta("keep_layers", true)
	var glow := Util.box(self, Vector3(0.7, 0.05, 0.02), Vector3(0, 1.9, 0.26), Util.color_mat(Color(0.3, 0.9, 1.0), 3.0, true))
	glow.set_meta("keep_layers", true)
	Util.box(self, Vector3(0.5, 0.1, 0.25), Vector3(0, 1.0, 0.35), Util.color_mat(Color(0.2, 0.22, 0.24)))
	Util.add_box_collider(self, Vector3(0.9, 2.1, 0.5), Vector3(0, 1.05, 0))


func get_frob_text() -> String:
	return "Stazione di potenziamento (%d cyber-moduli)" % Game.modules


func frob(_player: Node) -> void:
	Sfx.play_ui("ui_open")
	Game.ui.open_upgrade()
