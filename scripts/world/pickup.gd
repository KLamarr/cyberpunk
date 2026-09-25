@tool
class_name Pickup
extends StaticBody3D
## Oggetto raccoglibile: medipatch, munizioni, cyber-moduli, crediti, tessere.
## Appoggialo su una superficie: l'origine è la base dell'oggetto.

@export_enum("medpatch", "ammo", "module", "credits", "keycard") var kind := "medpatch":
	set(v):
		kind = v
		_editor_rebuild()
## Quantità (colpi, crediti, moduli, medipatch).
@export var amount := 1
## Per le tessere: id usato dalle porte (es. "lab").
@export var item_id := "":
	set(v):
		item_id = v
		_editor_rebuild()
## Nome mostrato. Vuoto = nome predefinito del tipo.
@export var display := ""
## Se non vuoto, raccoglierlo conta come segreto trovato (id univoco).
@export var secret_id := ""

var _built: Array[Node] = []


func setup(pos: Vector3, k: String, amt := 1, id := "", disp := "", secret := "") -> Pickup:
	position = pos
	kind = k
	amount = amt
	item_id = id
	display = disp
	secret_id = secret
	return self


func _ready() -> void:
	_build()
	if not Engine.is_editor_hint():
		rotation_degrees.y += randf_range(-40, 40)


func _editor_rebuild() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		_build()


func _default_name() -> String:
	match kind:
		"medpatch":
			return "Medipatch"
		"ammo":
			return "Munizioni 9mm (%d)" % amount
		"module":
			return "Cyber-modulo"
		"credits":
			return "Chip di credito (%d ¢)" % amount
		"keycard":
			return "Tessera " + item_id
	return kind


func _build() -> void:
	for n in _built:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_built.clear()
	var before := get_child_count()
	collision_layer = Layers.INTERACT
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.22
	cs.shape = sph
	cs.position = Vector3(0, 0.08, 0)
	add_child(cs)
	match kind:
		"medpatch":
			Util.box(self, Vector3(0.2, 0.07, 0.14), Vector3(0, 0.035, 0), Util.color_mat(Color(0.85, 0.87, 0.85)))
			Util.box(self, Vector3(0.12, 0.075, 0.03), Vector3(0, 0.036, 0), Util.color_mat(Color(0.8, 0.1, 0.1)))
			Util.box(self, Vector3(0.03, 0.075, 0.1), Vector3(0, 0.036, 0), Util.color_mat(Color(0.8, 0.1, 0.1)))
		"ammo":
			Util.box(self, Vector3(0.18, 0.1, 0.1), Vector3(0, 0.05, 0), Util.mat("crate", {"fit": Vector3(0.18, 0.1, 0.1), "color": Color(0.7, 0.6, 0.4)}))
			Util.box(self, Vector3(0.16, 0.02, 0.08), Vector3(0, 0.105, 0), Util.color_mat(Color(0.75, 0.6, 0.2), 0.3))
		"module":
			Util.box(self, Vector3(0.16, 0.04, 0.11), Vector3(0, 0.02, 0), Util.color_mat(Color(0.15, 0.2, 0.22)))
			Util.box(self, Vector3(0.1, 0.045, 0.06), Vector3(0, 0.024, 0), Util.color_mat(Color(0.2, 0.95, 0.9), 2.0, true))
		"credits":
			Util.box(self, Vector3(0.1, 0.015, 0.06), Vector3(0, 0.008, 0), Util.color_mat(Color(1.0, 0.8, 0.2), 1.2))
		"keycard":
			Util.box(self, Vector3(0.14, 0.012, 0.09), Vector3(0, 0.006, 0), Util.color_mat(Color(0.9, 0.9, 0.85)))
			var stripe := Color(1.0, 0.3, 0.2) if item_id == "lab" else Color(0.95, 0.8, 0.2)
			Util.box(self, Vector3(0.14, 0.014, 0.025), Vector3(0, 0.007, 0.02), Util.color_mat(stripe, 1.5, true))
	for i in range(before, get_child_count()):
		_built.append(get_child(i))


func get_display() -> String:
	return display if display != "" else _default_name()


func get_frob_text() -> String:
	return "Raccogli: " + get_display()


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
			Game.give_keycard(item_id, get_display())
	Sfx.play_ui("pickup")
	Game.notify("Raccolto: " + get_display())
	if secret_id != "":
		Game.found_secret(secret_id)
	queue_free()
