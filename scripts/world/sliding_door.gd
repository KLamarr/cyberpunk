@tool
class_name SlidingDoor
extends Node3D
## Porta scorrevole sci-fi. Il pannello scivola dentro lo stipite (lungo l'asse X
## locale): mettila al centro di un passaggio profondo 1 m, con la X lungo il muro.
## Le guardie la aprono automaticamente (hanno l'accesso), il player la "frobba".
## Una porta chiusa a chiave si apre con tessera, codice o hacking (anche più
## modi insieme): il validatore di livello controlla che almeno uno esista.

## Larghezza del passaggio in metri.
@export var width := 1.6:
	set(v):
		width = v
		_editor_rebuild()
@export var height := 2.5:
	set(v):
		height = v
		_editor_rebuild()
@export var texture: Texture2D = preload("res://assets/textures/door.png"):
	set(v):
		texture = v
		_editor_rebuild()
## Secondi prima che si richiuda da sola dopo che il player l'ha aperta.
@export var auto_close := 6.0

@export_group("Serratura")
@export var locked := false:
	set(v):
		locked = v
		_editor_rebuild()
## Nome mostrato nel pannello della serratura.
@export var lock_title := ""
## Id della tessera che la apre (vuoto = nessuna). Es. "lab", "sicurezza".
@export var keycard_id := ""
@export var keycard_name := ""
## Codice del tastierino (vuoto = nessun tastierino). Mettilo in un registro!
@export var code := "":
	set(v):
		code = v
		_editor_rebuild()
## Livello di Hacking minimo (0 = non hackerabile).
@export_range(0, 4) var hack_level := 0
@export_range(1, 4) var hack_difficulty := 1
## Se l'hack fallisce, 60% di probabilità di far scattare l'allarme.
@export var alarm_on_fail := false
## Zone da cui la porta si apre sempre (es. dall'interno di una stanza).
@export_flags_3d_render var bypass_zones := 0

var thickness := 0.12
var lock := {}

var panel: AnimatableBody3D
var sensor: Area3D
var blocker: Area3D
var _status_mats: Array[StandardMaterial3D] = []
var _built: Array[Node] = []
var open_t := 0.0
var target := 0.0
var close_timer := 0.0


## Crea la porta da codice. lock_info: title, keycard, keycard_name, code, hack,
## difficulty, alarm_on_fail, bypass_zone.
func setup(pos: Vector3, yaw_deg: float, w: float, h: float, lock_info := {}) -> SlidingDoor:
	position = pos
	rotation_degrees.y = yaw_deg
	width = w
	height = h
	locked = not lock_info.is_empty()
	lock_title = lock_info.get("title", "")
	keycard_id = lock_info.get("keycard", "")
	keycard_name = lock_info.get("keycard_name", "")
	code = lock_info.get("code", "")
	hack_level = lock_info.get("hack", 0)
	hack_difficulty = lock_info.get("difficulty", 1)
	alarm_on_fail = lock_info.get("alarm_on_fail", false)
	bypass_zones = lock_info.get("bypass_zone", 0)
	return self


func _make_lock() -> Dictionary:
	if not locked:
		return {}
	var d := {"title": lock_title if lock_title != "" else "Porta"}
	if keycard_id != "":
		d["keycard"] = keycard_id
		d["keycard_name"] = keycard_name if keycard_name != "" else keycard_id
	if code != "":
		d["code"] = code
	if hack_level > 0:
		d["hack"] = hack_level
		d["difficulty"] = hack_difficulty
	if alarm_on_fail:
		d["alarm_on_fail"] = true
	if bypass_zones != 0:
		d["bypass_zone"] = bypass_zones
	return d


func _ready() -> void:
	lock = _make_lock()
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("doors")


func _editor_rebuild() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		lock = _make_lock()
		_build()


func _build() -> void:
	for n in _built:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_built.clear()
	_status_mats.clear()
	var before := get_child_count()
	panel = AnimatableBody3D.new()
	panel.sync_to_physics = false
	panel.collision_layer = Layers.DOOR
	panel.collision_mask = 0
	add_child(panel)
	var m := Util.mat(texture, {"fit": Vector3(width, height, thickness)})
	Util.box(panel, Vector3(width - 0.02, height - 0.02, thickness), Vector3(0, height * 0.5, 0), m)
	Util.add_box_collider(panel, Vector3(width, height, thickness), Vector3(0, height * 0.5, 0))

	if not Engine.is_editor_hint():
		sensor = Area3D.new()
		sensor.collision_layer = 0
		sensor.collision_mask = Layers.NPC
		add_child(sensor)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(width + 0.6, height, 4.5)
		cs.shape = bs
		cs.position = Vector3(0, height * 0.5, 0)
		sensor.add_child(cs)

		blocker = Area3D.new()
		blocker.collision_layer = 0
		blocker.collision_mask = Layers.NPC | Layers.PLAYER | Layers.PROP
		add_child(blocker)
		var cs2 := CollisionShape3D.new()
		var bs2 := BoxShape3D.new()
		bs2.size = Vector3(width, height - 0.2, 1.1)
		cs2.shape = bs2
		cs2.position = Vector3(0, height * 0.5, 0)
		blocker.add_child(cs2)

	# spie di stato su entrambi i lati del muro
	for side in [-1.0, 1.0]:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_status_mats.append(sm)
		Util.box(self, Vector3(0.12, 0.12, 0.04), Vector3(width * 0.5 + 0.25, 1.75, side * 0.51), sm)
		if lock.has("code"):
			var kp := Util.box(self, Vector3(0.22, 0.28, 0.04), Vector3(width * 0.5 + 0.25, 1.3, side * 0.51), Util.mat("keypad", {"fit": Vector3(0.22, 0.28, 0.04)}))
			kp.set_meta("no_highlight", true)
	_update_status()
	for i in range(before, get_child_count()):
		_built.append(get_child(i))


func _update_status() -> void:
	var c := Color(1.0, 0.15, 0.1) if locked else Color(0.2, 1.0, 0.4)
	for sm in _status_mats:
		sm.albedo_color = c


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var guard_near := false
	for b in sensor.get_overlapping_bodies():
		if b.is_in_group("guards") and b.has_method("is_active") and b.is_active():
			guard_near = true
			break
	if guard_near:
		if target < 1.0:
			_set_target(1.0)
		close_timer = max(close_timer, 2.0)
	if target > 0.5 and close_timer > 0.0:
		close_timer -= delta
		if close_timer <= 0.0:
			if _blocked():
				close_timer = 0.8
			else:
				_set_target(0.0)
	# mentre si chiude, se qualcosa è in mezzo riapre
	if target < 0.5 and open_t > 0.05 and _blocked():
		_set_target(1.0)
		close_timer = 1.5
	var prev := open_t
	open_t = move_toward(open_t, target, delta * 2.2)
	if prev != open_t:
		panel.position.x = open_t * (width * 0.97)


func _blocked() -> bool:
	for b in blocker.get_overlapping_bodies():
		if b is CharacterBody3D or b is RigidBody3D:
			if b.has_method("is_active") and not b.is_active():
				continue
			return true
	return false


func _set_target(t: float, by_player := false) -> void:
	if t == target:
		return
	target = t
	Sfx.play_3d("door_open", global_position + Vector3.UP * 1.2, -2.0, 0.05, 18.0)
	if by_player:
		Game.emit_noise(global_position, 5.0, "door", Game.player)


func is_open() -> bool:
	return target > 0.5


func open(timer := -1.0, by_player := true) -> void:
	_set_target(1.0, by_player)
	close_timer = auto_close if timer < 0.0 else timer


func close() -> void:
	_set_target(0.0, true)


# --- frob / serratura ----------------------------------------------------------
func get_frob_text() -> String:
	if locked:
		return "Porta bloccata — " + String(lock.get("title", ""))
	return "Chiudi porta" if is_open() else "Apri porta"


func frob(player: Node) -> void:
	if locked:
		var bz: int = lock.get("bypass_zone", 0)
		if bz != 0 and Game.level and (Game.level.zone_mask_at(player.global_position) & bz) != 0:
			unlock(false)
			Game.notify("Sblocchi la porta dall'interno.")
			open()
			return
		var kc: String = lock.get("keycard", "")
		if kc != "" and Game.has_keycard(kc):
			unlock()
			Game.notify("Usi: " + String(Game.keycards[kc]))
			open()
			return
		Sfx.play_3d("door_locked", global_position + Vector3.UP * 1.3, -2.0)
		if Game.ui:
			Game.ui.open_lock(self)
		return
	if is_open():
		close()
	else:
		open()


func get_lock_info() -> Dictionary:
	var info := lock.duplicate()
	info["kind"] = "door"
	return info


func try_code(code: String) -> bool:
	if lock.has("code") and code == String(lock.code):
		unlock()
		open()
		return true
	return false


func on_hack_result(ok: bool) -> void:
	if ok:
		Game.stats.hacks += 1
		unlock()
		open()


func unlock(sound := true) -> void:
	locked = false
	_update_status()
	if sound:
		Sfx.play_3d("granted", global_position + Vector3.UP * 1.3, -2.0)
