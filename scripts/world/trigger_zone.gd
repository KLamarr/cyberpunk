class_name TriggerZone
extends Area3D
## Volume che esegue una Callable quando il player ci entra (una volta sola).

var callback: Callable
var once := true
var _fired := false


func setup(center: Vector3, size: Vector3, cb: Callable, fire_once := true) -> TriggerZone:
	position = center
	callback = cb
	once = fire_once
	collision_layer = 0
	collision_mask = Game.L_PLAYER
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	add_child(cs)
	return self


func _ready() -> void:
	body_entered.connect(_on_body)


func _on_body(b: Node) -> void:
	if _fired and once:
		return
	if b.is_in_group("player"):
		_fired = true
		callback.call()
