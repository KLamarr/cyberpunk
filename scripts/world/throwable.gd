@tool
class_name Throwable
extends RigidBody3D
## Oggetto fisico raccoglibile e lanciabile. Quando urta qualcosa abbastanza forte
## genera un rumore: è il modo classico per distrarre una guardia.

## can: lattina. bottle: bottiglia (più rumorosa). box: scatola da 4 kg. heavy: cassa da 40 kg (Forza 2).
@export_enum("can", "bottle", "box", "heavy") var kind := "can":
	set(v):
		kind = v
		_apply_kind()
		if Engine.is_editor_hint() and is_inside_tree():
			for c in get_children():
				if c.owner == null:
					remove_child(c)
					c.queue_free()
			_build()

var display := "Lattina"
var shape_kind := "can"
var size := Vector3(0.07, 0.13, 0.07)
var tex := ""
var col := Color(0.7, 0.1, 0.1)
var noise_mult := 1.0
var heavy := false         # serve Forza 2 per sollevarla
var held := false
var _last_speed := 0.0
var _cooldown := 0.0


func setup(pos: Vector3, k: String) -> Throwable:
	position = pos
	kind = k
	return self


func _apply_kind() -> void:
	shape_kind = kind
	noise_mult = 1.0
	heavy = false
	tex = ""
	match kind:
		"can":
			display = "Lattina di Kaffa-Nova"
			size = Vector3(0.07, 0.13, 0.07)
			col = [Color(0.75, 0.1, 0.12), Color(0.1, 0.5, 0.75), Color(0.85, 0.7, 0.1)][randi() % 3]
			mass = 0.3
		"bottle":
			display = "Bottiglia"
			size = Vector3(0.08, 0.28, 0.08)
			col = Color(0.25, 0.55, 0.35)
			mass = 0.6
			noise_mult = 1.3
		"box":
			display = "Scatola di componenti"
			size = Vector3(0.45, 0.32, 0.35)
			tex = "crate"
			mass = 4.0
			noise_mult = 1.2
		"heavy":
			display = "Cassa SB-14"
			size = Vector3(0.8, 0.7, 0.8)
			tex = "crate"
			mass = 40.0
			heavy = true
			noise_mult = 1.5


func _ready() -> void:
	_apply_kind()
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("throwables")
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	body_entered.connect(_on_body_entered)


func _build() -> void:
	collision_layer = Layers.PROP
	collision_mask = Layers.WORLD | Layers.DOOR | Layers.GLASS | Layers.PROP | Layers.NPC | Layers.PLAYER | Layers.DEVICE
	var m: Material
	if tex != "":
		m = Util.mat(tex, {"fit": size})
	else:
		m = Util.color_mat(col)
	var cs := CollisionShape3D.new()
	if shape_kind == "can" or shape_kind == "bottle":
		Util.cylinder(self, size.x * 0.5, size.y, Vector3.ZERO, m, Vector3.ZERO, 6)
		var cyl := CylinderShape3D.new()
		cyl.radius = size.x * 0.5
		cyl.height = size.y
		cs.shape = cyl
	else:
		Util.box(self, size, Vector3.ZERO, m)
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
	add_child(cs)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_last_speed = linear_velocity.length()
	_cooldown -= delta


func _on_body_entered(_body: Node) -> void:
	if held or _cooldown > 0.0 or _last_speed < 2.2:
		return
	_cooldown = 0.3
	var radius := clampf(3.0 + _last_speed * 1.5, 4.0, 16.0) * noise_mult
	Game.emit_noise(global_position, radius, "impact", self)
	Sfx.play_3d("clatter", global_position, clampf(_last_speed - 6.0, -10.0, 3.0))


func get_frob_text() -> String:
	if heavy and Game.skill("forza") < 2:
		return display + " — troppo pesante (Forza 2)"
	return "Prendi: " + display


func frob(player: Node) -> void:
	if heavy and Game.skill("forza") < 2:
		Game.notify("Troppo pesante. Serve Forza 2.", Color(1, 0.7, 0.4))
		return
	player.pick_up(self)


func set_held(on: bool) -> void:
	held = on
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = on
	if on:
		collision_layer = 0
	else:
		collision_layer = Layers.PROP
