class_name SlidingDoor
extends Node3D
## Porta scorrevole sci-fi. Il pannello scivola dentro lo stipite (lungo l'asse X
## locale). Le guardie la aprono automaticamente (hanno l'accesso), il player la
## "frobba". Le serrature possono richiedere tessera, codice o hacking.
##
## lock = {
##   title: "Laboratorio C", keycard: "lab", keycard_name: "Tessera Laboratorio C",
##   code: "0451", hack: 2 (livello minimo), difficulty: 2, alarm_on_fail: true,
##   bypass_zone: <maschera zona da cui si apre sempre, es. dall'interno>
## }

var width := 1.6
var height := 2.5
var thickness := 0.12
var tex := "door"
var locked := false
var lock := {}
var auto_close := 6.0

var panel: AnimatableBody3D
var sensor: Area3D
var blocker: Area3D
var _status_mats: Array[StandardMaterial3D] = []
var open_t := 0.0
var target := 0.0
var close_timer := 0.0
var _was_moving := false


func setup(pos: Vector3, yaw_deg: float, w: float, h: float, lock_info := {}) -> SlidingDoor:
	position = pos
	rotation_degrees.y = yaw_deg
	width = w
	height = h
	lock = lock_info
	locked = not lock_info.is_empty()
	return self


func _ready() -> void:
	add_to_group("doors")
	panel = AnimatableBody3D.new()
	panel.sync_to_physics = false
	panel.collision_layer = Game.L_DOOR
	panel.collision_mask = 0
	add_child(panel)
	var m := Util.mat(tex, {"fit": Vector3(width, height, thickness)})
	Util.box(panel, Vector3(width - 0.02, height - 0.02, thickness), Vector3(0, height * 0.5, 0), m)
	Util.add_box_collider(panel, Vector3(width, height, thickness), Vector3(0, height * 0.5, 0))

	sensor = Area3D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = Game.L_NPC
	add_child(sensor)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width + 0.6, height, 4.5)
	cs.shape = bs
	cs.position = Vector3(0, height * 0.5, 0)
	sensor.add_child(cs)

	blocker = Area3D.new()
	blocker.collision_layer = 0
	blocker.collision_mask = Game.L_NPC | Game.L_PLAYER | Game.L_PROP
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


func _update_status() -> void:
	var c := Color(1.0, 0.15, 0.1) if locked else Color(0.2, 1.0, 0.4)
	for sm in _status_mats:
		sm.albedo_color = c


func _physics_process(delta: float) -> void:
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
