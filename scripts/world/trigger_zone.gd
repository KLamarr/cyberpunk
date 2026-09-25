@tool
class_name TriggerZone
extends Area3D
## Volume che reagisce quando il player ci entra: mostra un sottotitolo o un
## messaggio (proprietà qui sotto) oppure, da codice, chiama una Callable.

## Dimensioni del volume in metri.
@export var size := Vector3(4, 3, 4):
	set(v):
		size = v
		if _shape != null:
			(_shape.shape as BoxShape3D).size = size
## Chi parla (es. "VESPER"). Vuoto + testo = messaggio in alto a sinistra.
@export var speaker := ""
@export_multiline var text := ""
@export var duration := 4.0
## Scatta una volta sola.
@export var once := true

var callback: Callable
var _fired := false
var _shape: CollisionShape3D


func setup(center: Vector3, sz: Vector3, cb: Callable, fire_once := true) -> TriggerZone:
	position = center
	size = sz
	callback = cb
	once = fire_once
	return self


func say(who: String, what: String, secs := 4.0) -> TriggerZone:
	speaker = who
	text = what
	duration = secs
	return self


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	_shape.shape = bs
	add_child(_shape)
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body)


func _on_body(b: Node) -> void:
	if _fired and once:
		return
	if not b.is_in_group("player"):
		return
	_fired = true
	if callback.is_valid():
		callback.call()
	if text != "":
		if speaker != "":
			Game.say(speaker, text, duration)
		else:
			Game.notify(text)
