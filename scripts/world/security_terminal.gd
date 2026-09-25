@tool
class_name SecurityTerminal
extends StaticBody3D
## Terminale della sala sicurezza: con la tessera sicurezza (o un hack di livello 1)
## permette di spegnere telecamere e torretta.

var logged_in := false


func setup(pos: Vector3, yaw_deg: float) -> SecurityTerminal:
	position = pos
	rotation_degrees.y = yaw_deg
	return self


func _ready() -> void:
	collision_layer = Layers.INTERACT
	collision_mask = 0
	# monitor su staffa
	Util.box(self, Vector3(0.7, 0.48, 0.08), Vector3(0, 0.3, 0), Util.color_mat(Color(0.16, 0.17, 0.19)))
	var scr := Util.box(self, Vector3(0.6, 0.38, 0.02), Vector3(0, 0.3, 0.045), Util.mat("screen_amber", {"fit": Vector3(0.6, 0.38, 0.02), "emission": 1.3}))
	scr.set_meta("keep_layers", true)
	Util.box(self, Vector3(0.08, 0.12, 0.08), Vector3(0, 0.02, -0.02), Util.color_mat(Color(0.2, 0.2, 0.22)))
	Util.box(self, Vector3(0.5, 0.03, 0.18), Vector3(0, -0.04, 0.2), Util.color_mat(Color(0.12, 0.12, 0.13)))
	Util.add_box_collider(self, Vector3(0.7, 0.6, 0.4), Vector3(0, 0.25, 0.1))


func get_frob_text() -> String:
	return "Terminale di sicurezza"


func frob(_player: Node) -> void:
	if logged_in or Game.has_keycard("sicurezza"):
		logged_in = true
		Sfx.play_ui("ui_open")
		Game.ui.open_terminal(self)
	else:
		Game.ui.open_lock(self)


func get_lock_info() -> Dictionary:
	return {
		"kind": "terminal", "title": "Terminale di sicurezza", "keycard": "sicurezza",
		"keycard_name": "Tessera Sicurezza", "hack": 1, "difficulty": 1,
	}


func try_code(_code: String) -> bool:
	return false


func on_hack_result(ok: bool) -> void:
	if ok:
		Game.stats.hacks += 1
		logged_in = true
		Game.ui.open_terminal(self)


func get_terminal_title() -> String:
	return "SERAPH-SEC // NODO 14 // SESSIONE: " + ("HALE.J" if Game.has_keycard("sicurezza") else "ROOT (bypass)")


func get_terminal_options() -> Array:
	var turret_on := false
	for t in get_tree().get_nodes_in_group("turrets"):
		if t.is_hostile_active():
			turret_on = true
	return [
		{"id": "cams", "label": "Disattiva telecamere di sorveglianza", "enabled": not Game.security_disabled},
		{"id": "turret", "label": "Disattiva torretta corridoio C", "enabled": turret_on},
		{"id": "log", "label": "Leggi registro di turno", "enabled": true},
	]


func terminal_action(id: String) -> void:
	match id:
		"cams":
			Game.disable_security()
		"turret":
			Game.disable_turrets()
		"log":
			Game.read_log("sicurezza")
