class_name Pickup
extends StaticBody3D
## Oggetto raccoglibile: medipatch, munizioni, cyber-moduli, crediti, tessere.

var kind := "medpatch"   # medpatch | ammo | module | credits | keycard
var amount := 1
var item_id := ""        # id della tessera
var display := ""
var secret_id := ""


func setup(pos: Vector3, k: String, amt := 1, id := "", disp := "", secret := "") -> Pickup:
	position = pos
	kind = k
	amount = amt
	item_id = id
	display = disp
	secret_id = secret
	return self


func _ready() -> void:
	collision_layer = Game.L_INTERACT
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.22
	cs.shape = sph
	cs.position = Vector3(0, 0.08, 0)
	add_child(cs)
	rotation_degrees.y = randf_range(-40, 40)
	match kind:
		"medpatch":
			if display == "": display = "Medipatch"
			Util.box(self, Vector3(0.2, 0.07, 0.14), Vector3(0, 0.035, 0), Util.color_mat(Color(0.85, 0.87, 0.85)))
			Util.box(self, Vector3(0.12, 0.075, 0.03), Vector3(0, 0.036, 0), Util.color_mat(Color(0.8, 0.1, 0.1)))
			Util.box(self, Vector3(0.03, 0.075, 0.1), Vector3(0, 0.036, 0), Util.color_mat(Color(0.8, 0.1, 0.1)))
		"ammo":
			if display == "": display = "Munizioni 9mm (%d)" % amount
			Util.box(self, Vector3(0.18, 0.1, 0.1), Vector3(0, 0.05, 0), Util.mat("crate", {"fit": Vector3(0.18, 0.1, 0.1), "color": Color(0.7, 0.6, 0.4)}))
			Util.box(self, Vector3(0.16, 0.02, 0.08), Vector3(0, 0.105, 0), Util.color_mat(Color(0.75, 0.6, 0.2), 0.3))
		"module":
			if display == "": display = "Cyber-modulo"
			Util.box(self, Vector3(0.16, 0.04, 0.11), Vector3(0, 0.02, 0), Util.color_mat(Color(0.15, 0.2, 0.22)))
			Util.box(self, Vector3(0.1, 0.045, 0.06), Vector3(0, 0.024, 0), Util.color_mat(Color(0.2, 0.95, 0.9), 2.0, true))
		"credits":
			if display == "": display = "Chip di credito (%d ¢)" % amount
			Util.box(self, Vector3(0.1, 0.015, 0.06), Vector3(0, 0.008, 0), Util.color_mat(Color(1.0, 0.8, 0.2), 1.2))
		"keycard":
			Util.box(self, Vector3(0.14, 0.012, 0.09), Vector3(0, 0.006, 0), Util.color_mat(Color(0.9, 0.9, 0.85)))
			var stripe := Color(1.0, 0.3, 0.2) if item_id == "lab" else Color(0.95, 0.8, 0.2)
			Util.box(self, Vector3(0.14, 0.014, 0.025), Vector3(0, 0.007, 0.02), Util.color_mat(stripe, 1.5, true))


func get_frob_text() -> String:
	return "Raccogli: " + display


func frob(_player: Node) -> void:
	match kind:
		"medpatch":
			Game.add_medpatch(amount)
		"ammo":
			Game.add_ammo(amount)
		"module":
			Game.add_modules(amount)
		"credits":
			Game.add_credits(amount)
		"keycard":
			Game.give_keycard(item_id, display)
	Sfx.play_ui("pickup")
	Game.notify("Raccolto: " + display)
	if secret_id != "":
		Game.found_secret(secret_id)
	queue_free()
