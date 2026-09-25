@tool
class_name VentGrate
extends StaticBody3D
## Grata di un condotto. Con Forza 1 si toglie a mano in silenzio; altrimenti va
## sfondata con la chiave inglese (o a colpi di pistola): rumorosa.
## inner_zone: se il player è nel condotto (zona indicata) può sempre spingerla
## via con un calcio (rumore medio).

## Larghezza e altezza della grata.
@export var size := Vector2(1.1, 1.1):
	set(v):
		size = v
		if Engine.is_editor_hint() and is_inside_tree():
			for c in get_children():
				if c.owner == null:
					remove_child(c)
					c.queue_free()
			_build()
## Livello di Forza per toglierla a mano (in silenzio).
@export_range(0, 4) var pry_skill := 1
## Zona "interna" (il condotto): da lì il player la può sempre sfondare con un calcio.
## Il lato esterno della grata è verso +Z locale.
@export_flags_3d_render var inner_zone := 0

var removed := false


func setup(pos: Vector3, yaw_deg: float, sz: Vector2, inner := 0) -> VentGrate:
	position = pos
	rotation_degrees.y = yaw_deg
	size = sz
	inner_zone = inner
	return self


func _ready() -> void:
	_build()


func _build() -> void:
	collision_layer = Layers.WORLD | Layers.DEVICE
	collision_mask = 0
	var m := Util.mat("vent_grate", {"fit": Vector3(size.x, size.y, 0.04), "alpha": true})
	Util.box(self, Vector3(size.x, size.y, 0.04), Vector3.ZERO, m)
	Util.add_box_collider(self, Vector3(size.x, size.y, 0.08))


func _player_inside(player: Node) -> bool:
	if player == null:
		return false
	return inner_zone != 0 and Game.level != null and (Game.level.zone_mask_at(player.global_position) & inner_zone) != 0


func get_frob_text() -> String:
	if _player_inside(Game.player):
		return "Spingi via la grata (calcio)"
	if Game.skill("forza") >= pry_skill:
		return "Rimuovi la grata"
	return "Grata fissata (Forza %d, o sfondala)" % pry_skill


func frob(player: Node) -> void:
	if _player_inside(player):
		_remove("grate_break", 7.0 * (1.0 - 0.12 * Game.skill("furtivita")))
		return
	if Game.skill("forza") >= pry_skill:
		_remove("grate_pry", 2.5)
	else:
		Game.notify("La grata è avvitata. Serve Forza %d per toglierla a mano, oppure puoi sfondarla." % pry_skill, Color(1, 0.75, 0.4))


func take_damage(_amount: float, _hit_pos: Vector3, _dir: Vector3, kind: String) -> void:
	if kind == "melee" or kind == "bullet":
		_remove("grate_break", 13.0)


func _remove(snd: String, noise: float) -> void:
	if removed:
		return
	removed = true
	Sfx.play_3d(snd, global_position)
	Game.emit_noise(global_position, noise, "grate", Game.player)
	# lascia la grata a terra (solo visiva)
	var fallen := Node3D.new()
	get_parent().add_child(fallen)
	var down := Util.ray(get_world_3d().direct_space_state, global_position + global_basis.z * 0.6, global_position + global_basis.z * 0.6 + Vector3.DOWN * 4.0, Layers.WORLD)
	var ground: Vector3 = down.get("position", global_position + Vector3.DOWN * size.y)
	fallen.global_position = ground + Vector3.UP * 0.03 + global_basis.z * 0.1
	fallen.rotation_degrees = Vector3(90, rotation_degrees.y + randf_range(-20, 20), 0)
	Util.box(fallen, Vector3(size.x, size.y, 0.04), Vector3.ZERO, Util.mat("vent_grate", {"fit": Vector3(size.x, size.y, 0.04), "alpha": true}))
	if Game.level:
		Util.set_layers_recursive(fallen, Game.level.zone_mask_at(fallen.global_position + Vector3.UP * 0.3))
	queue_free()
