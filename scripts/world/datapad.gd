@tool
class_name Datapad
extends StaticBody3D
## Datapad (si raccoglie e finisce nel PDA) o terminale a muro (resta, si rilegge).
## I testi stanno in scripts/data/logs.gd: qui metti solo l'id del registro.

## Id del registro in Logs.ENTRIES (es. "turni", "okafor1").
@export var log_id := ""
## true = schermo a muro che resta al suo posto (guarda verso +Z locale).
@export var wall_terminal := false:
	set(v):
		wall_terminal = v
		if Engine.is_editor_hint() and is_inside_tree():
			for c in get_children():
				if c.owner == null:
					remove_child(c)
					c.queue_free()
			_build()


func setup(pos: Vector3, id: String, yaw_deg := 0.0, is_wall := false) -> Datapad:
	position = pos
	rotation_degrees.y = yaw_deg
	log_id = id
	wall_terminal = is_wall
	return self


func _ready() -> void:
	_build()


func _build() -> void:
	collision_layer = Layers.INTERACT
	collision_mask = 0
	if wall_terminal:
		Util.box(self, Vector3(0.62, 0.46, 0.08), Vector3.ZERO, Util.color_mat(Color(0.2, 0.22, 0.24)))
		var scr := Util.box(self, Vector3(0.52, 0.36, 0.02), Vector3(0, 0, 0.045), Util.mat("screen_green", {"fit": Vector3(0.52, 0.36, 0.02), "emission": 1.4}))
		scr.set_meta("keep_layers", true)
		Util.add_box_collider(self, Vector3(0.62, 0.46, 0.12))
	else:
		Util.box(self, Vector3(0.22, 0.02, 0.15), Vector3(0, 0.01, 0), Util.color_mat(Color(0.12, 0.13, 0.14)))
		Util.box(self, Vector3(0.18, 0.022, 0.11), Vector3(0, 0.012, 0), Util.mat("screen_green", {"fit": Vector3(0.18, 0.02, 0.11), "emission": 1.2}))
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.2
		cs.shape = sph
		add_child(cs)


func get_frob_text() -> String:
	var t: String = Logs.ENTRIES.get(log_id, {}).get("title", "")
	return (tr("Read terminal: %s") if wall_terminal else tr("Read datapad: %s")) % tr(t)


func frob(_player: Node) -> void:
	Game.read_log(log_id)
	if not wall_terminal:
		queue_free()


# --- salvataggi: niente da salvare, ma se sparisce (raccolto, letto, sfondata) al
# caricamento viene tolto anche lui (vedi SaveGame, «removed») -------------------------
func save_state() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
