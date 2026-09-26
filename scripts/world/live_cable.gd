@tool
class_name LiveCable
extends Node3D
## CAVO SCOPERTO: un cavo elettrico tranciato che pende da un condotto rotto fino quasi
## a terra e fa scintille. Chi lo tocca prende la scossa. La sua punta porta corrente
## sul pavimento lì sotto (vedi Stimuli): se ci arriva una pozza d'acqua, la pozza è
## elettrificata e chi ci sta dentro prende la scossa, guardie comprese.
## Voltage "high" è mortale (conta come uccisione); "low" fa svenire.
## Si spegne con un interruttore: un LightSwitch con Switch Type "power" e questo cavo
## nei Targets.
## Origine: l'attacco in alto (sul soffitto); il cavo pende verso il basso per Length metri.

## Lunghezza del cavo: perché elettrifichi le pozze la punta deve arrivare a meno di
## 80 cm dal pavimento (il validatore lo controlla).
@export_range(0.3, 6.0, 0.05, "suffix:m") var length := 3.0:
	set(v):
		length = v
		_rebuild()
## high: scossa mortale. low: fa svenire (come le scintille di una luce rotta).
@export_enum("low", "high") var voltage := "high"
## Acceso all'inizio.
@export var powered := true:
	set(v):
		powered = v
		_update_power()

## Distanza dalla punta entro cui la si tocca.
const TOUCH := 0.45

var _built: Array[Node] = []
var _tip: MeshInstance3D
var _tip_mat: StandardMaterial3D
var _field: Stimuli.Field
var _spark_cd := 0.0
var _tick := 0.0


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	add_to_group("live_cables")
	add_to_group("level_aware")


func on_level_ready(_level: Node) -> void:
	_update_power()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for n in _built:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_built.clear()
	var before := get_child_count()
	var metal := Util.color_mat(Color(0.2, 0.21, 0.22))
	var rubber := Util.color_mat(Color(0.06, 0.06, 0.06))
	# condotto rotto sul soffitto
	Util.box(self, Vector3(0.3, 0.14, 0.3), Vector3(0, -0.07, 0), metal)
	Util.box(self, Vector3(0.08, 0.1, 0.08), Vector3(0.1, -0.18, 0.05), metal, Vector3(0, 0, 25))
	# il cavo: dritto e poi piegato verso la punta
	var bend := 0.35
	var straight := maxf(length - bend - 0.15, 0.05)
	Util.cylinder(self, 0.018, straight, Vector3(0, -0.15 - straight * 0.5, 0), rubber, Vector3.ZERO, 5)
	Util.cylinder(self, 0.018, bend + 0.02, Vector3(0.06, -0.15 - straight - bend * 0.5, 0), rubber, Vector3(0, 0, 20), 5)
	# la punta di rame scoperta
	_tip_mat = StandardMaterial3D.new()
	_tip_mat.albedo_color = Color(0.85, 0.45, 0.2)
	_tip_mat.emission_enabled = true
	_tip_mat.emission = Color(1.0, 0.6, 0.3)
	_tip = Util.box(self, Vector3(0.05, 0.08, 0.05), tip_local(), _tip_mat)
	# un collider sottile: le guardie ci girano intorno (navmesh) e non ci si passa attraverso
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	add_child(body)
	Util.add_box_collider(body, Vector3(0.1, length, 0.1), Vector3(0.03, -length * 0.5, 0))
	for i in range(before, get_child_count()):
		_built.append(get_child(i))
	_update_power()


## La punta, in coordinate locali.
func tip_local() -> Vector3:
	return Vector3(0.12, -length + 0.04, 0)


func tip_position() -> Vector3:
	return to_global(tip_local())


func get_voltage() -> int:
	return Stimuli.HIGH_VOLTAGE if voltage == "high" else Stimuli.LOW_VOLTAGE


## Chiamato dall'interruttore (LightSwitch con Switch Type "power").
func set_on(on: bool) -> void:
	if on == powered:
		return
	powered = on
	if not Engine.is_editor_hint():
		Sfx.play_3d("spark" if on else "servo", tip_position(), -2.0)


func _update_power() -> void:
	if _tip_mat != null:
		_tip_mat.emission_energy_multiplier = 1.5 if powered else 0.0
	if Engine.is_editor_hint() or not is_inside_tree() or Game.level == null:
		return
	Stimuli.remove_field(_field)
	_field = null
	if powered:
		var floor_pt := Stimuli.floor_below(get_world_3d().direct_space_state, tip_position())
		if tip_position().y - floor_pt.y < 0.8:
			_field = Stimuli.add_field(Stimuli.CURRENT, floor_pt, 0.55, get_voltage(), self)


func _exit_tree() -> void:
	Stimuli.remove_field(_field)
	_field = null


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not powered:
		return
	_spark_cd -= delta
	if _spark_cd <= 0.0:
		_spark_cd = randf_range(0.25, 1.1)
		Effects.sparks(tip_position(), Color(0.7, 0.85, 1.0), 6, 1.6)
		if randf() < 0.5:
			Sfx.play_3d("spark", tip_position(), -5.0)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.1
	# chi tocca la punta prende la scossa
	var tip := tip_position()
	for a in Stimuli.actors():
		var feet: Vector3 = a.global_position
		if Vector2(feet.x - tip.x, feet.z - tip.z).length() < TOUCH and tip.y > feet.y - 0.2 and tip.y < feet.y + 1.9:
			Stimuli.shock(a, get_voltage(), tip)


func save_state() -> Dictionary:
	return {"powered": powered}


func load_state(d: Dictionary) -> void:
	powered = bool(d.powered)
