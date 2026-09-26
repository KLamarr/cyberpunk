@tool
class_name TurretPanel
extends StaticBody3D
## Pannello di manutenzione della torretta. Hack (Hacking 2): con Hacking 2 la
## spegne, con Hacking 3 la riprogramma contro le guardie.

## La torretta controllata da questo pannello.
@export var turret_path: NodePath

var turret: Turret


func setup(pos: Vector3, yaw_deg: float, t: Turret) -> TurretPanel:
	position = pos
	rotation_degrees.y = yaw_deg
	turret = t
	return self


func _ready() -> void:
	collision_layer = Layers.INTERACT
	collision_mask = 0
	Util.box(self, Vector3(0.4, 0.5, 0.06), Vector3.ZERO, Util.mat("wall_tech", {"fit": Vector3(0.4, 0.5, 0.06)}))
	var scr := Util.box(self, Vector3(0.26, 0.14, 0.02), Vector3(0, 0.1, 0.035), Util.mat("screen_amber", {"fit": Vector3(0.26, 0.14, 0.02), "emission": 1.3}))
	scr.set_meta("keep_layers", true)
	Util.add_box_collider(self, Vector3(0.45, 0.55, 0.15))
	if not Engine.is_editor_hint() and turret == null and not turret_path.is_empty():
		turret = get_node_or_null(turret_path) as Turret


func get_frob_text() -> String:
	if turret == null or not turret.is_hostile_active():
		return tr("Turret panel (inactive)")
	return tr("Turret maintenance panel")


func frob(_player: Node) -> void:
	if turret == null or not turret.is_hostile_active():
		Game.notify(tr("The turret is already out of service."))
		return
	Game.ui.open_lock(self)


func get_lock_info() -> Dictionary:
	return {
		"kind": "turret", "title": tr("Turret panel C-2"), "hack": 2, "difficulty": 2,
		"alarm_on_fail": true,
		"note": tr("Hacking 2: disable it.  Hacking 3: turn it against the guards."),
	}


func try_code(_code: String) -> bool:
	return false


func on_hack_result(ok: bool) -> void:
	if not ok:
		return
	Game.stats.hacks += 1
	if Game.skill("hacking") >= 3:
		turret.set_friendly()
	else:
		turret.set_disabled(true)
		Game.notify(tr("Turret disabled."), Color(0.5, 1.0, 0.6))
