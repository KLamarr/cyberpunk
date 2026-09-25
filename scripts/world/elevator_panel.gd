class_name ElevatorPanel
extends StaticBody3D
## Pulsantiera dell'ascensore di servizio: punto di estrazione.

var used := false


func setup(pos: Vector3, yaw_deg: float) -> ElevatorPanel:
	position = pos
	rotation_degrees.y = yaw_deg
	return self


func _ready() -> void:
	collision_layer = Game.L_INTERACT
	collision_mask = 0
	Util.box(self, Vector3(0.3, 0.5, 0.05), Vector3.ZERO, Util.color_mat(Color(0.25, 0.24, 0.22)))
	var b := Util.box(self, Vector3(0.1, 0.1, 0.03), Vector3(0, 0.1, 0.035), Util.color_mat(Color(0.2, 0.8, 1.0), 2.0, true))
	b.set_meta("keep_layers", true)
	var b2 := Util.box(self, Vector3(0.1, 0.1, 0.03), Vector3(0, -0.08, 0.035), Util.color_mat(Color(1.0, 0.5, 0.1), 2.0, true))
	b2.set_meta("keep_layers", true)
	Util.add_box_collider(self, Vector3(0.35, 0.55, 0.15))


func get_frob_text() -> String:
	return "Ascensore di servizio — " + ("SCENDI" if Game.has_item("core") else "in attesa")


func frob(_player: Node) -> void:
	if used:
		return
	if not Game.has_item("core"):
		Sfx.play_ui("denied")
		Game.say("VESPER", "Non ti muovi da lì senza il nucleo. Laboratorio C, a nord della hall.", 3.5)
		return
	used = true
	Sfx.play_ui("elevator")
	Game.say("VESPER", "Ottimo lavoro. Ti porto giù.", 2.0)
	get_tree().create_timer(2.2, false).timeout.connect(Game.complete_mission)
