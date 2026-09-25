@tool
class_name SecurityCamera
extends Node3D
## Telecamera di sorveglianza: ruota avanti e indietro; se vede il player
## abbastanza a lungo (dipende da luce e distanza) fa scattare l'allarme.
## Il suo cono di luce illumina davvero il player (conta per la visibilità).
## Si disattiva dal terminale di sicurezza o si distrugge con la pistola.
## Guarda verso la -Z locale: ruota il nodo per decidere il centro della rotazione.

## Ampiezza della rotazione, in gradi per lato.
@export_range(0.0, 90.0) var sweep := 40.0
## Secondi per un'oscillazione completa.
@export var period := 7.0
## Inclinazione verso il basso (gradi negativi).
@export_range(-80.0, 0.0) var pitch := -28.0
@export var cam_range := 15.0
## Semiapertura del cono visivo (gradi).
@export var half_fov := 26.0
## Zone illuminate dal cono. Vuoto = la zona in cui si trova.
@export_flags_3d_render var zones_override := 0

var yaw_center := 0.0      # relativo al nodo
var zones := 1

var awareness := 0.0
var disabled := false
var destroyed := false
var hp := 15.0
var _pivot: Node3D
var _head: StaticBody3D
var _spot: SpotLight3D
var _lens_mat: StandardMaterial3D
var _t := 0.0
var _alarm_cd := 0.0
var _beep_cd := 0.0
var _perceive_t := 0.0
var _tracking := false


func setup(pos: Vector3, yaw_deg: float, sweep_deg: float, zone_mask: int) -> SecurityCamera:
	position = pos
	rotation_degrees.y = yaw_deg
	sweep = sweep_deg
	zones_override = zone_mask
	return self


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("security_cameras")
	add_to_group("game_lights")
	add_to_group("level_aware")


func on_level_ready(level: Node) -> void:
	zones = zones_override if zones_override != 0 else level.zone_mask_at(global_position)
	_spot.light_cull_mask = zones
	Util.set_layers_recursive(self, zones)


func _build() -> void:
	var dark := Util.color_mat(Color(0.14, 0.15, 0.16))
	var body := Util.color_mat(Color(0.62, 0.63, 0.6))
	Util.box(self, Vector3(0.16, 0.3, 0.16), Vector3(0, 0.12, 0), dark)
	_pivot = Node3D.new()
	add_child(_pivot)
	_head = StaticBody3D.new()
	_head.collision_layer = Layers.DEVICE
	_head.collision_mask = 0
	_head.rotation_degrees.x = pitch
	_pivot.add_child(_head)
	Util.box(_head, Vector3(0.22, 0.2, 0.46), Vector3(0, 0, -0.12), body)
	Util.box(_head, Vector3(0.26, 0.03, 0.5), Vector3(0, 0.12, -0.12), dark)
	_lens_mat = StandardMaterial3D.new()
	_lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var lens := Util.box(_head, Vector3(0.12, 0.12, 0.03), Vector3(0, 0, -0.36), _lens_mat)
	lens.set_meta("keep_layers", true)
	Util.add_box_collider(_head, Vector3(0.26, 0.24, 0.5), Vector3(0, 0, -0.12))
	_spot = SpotLight3D.new()
	_spot.spot_range = cam_range
	_spot.spot_angle = half_fov
	_spot.spot_attenuation = 1.0
	_spot.light_energy = 1.2
	_spot.position = Vector3(0, 0, -0.4)
	_head.add_child(_spot)
	_set_color(Color(0.3, 1.0, 0.5))


func _set_color(c: Color) -> void:
	_lens_mat.albedo_color = c
	_spot.light_color = c


## Proxy per i danni: il collider è sulla testa, ma take_damage è qui.
func take_damage(amount: float, hit_pos: Vector3, _dir: Vector3, _kind: String) -> void:
	if destroyed:
		return
	hp -= amount
	Effects.sparks(hit_pos, Color(0.6, 0.9, 1.0), 10, 3.0)
	if hp <= 0.0:
		destroyed = true
		_spot.visible = false
		_set_color(Color(0.05, 0.05, 0.05))
		_head.rotation_degrees.x = -70.0
		Sfx.play_3d("glass_break", global_position)
		Game.emit_noise(global_position, 10.0, "glass", Game.player)
		Game.notify("Telecamera distrutta.")


func set_disabled(on: bool) -> void:
	disabled = on
	_spot.visible = not on and not destroyed
	_set_color(Color(0.1, 0.1, 0.1) if on else Color(0.3, 1.0, 0.5))
	if on:
		_head.rotation_degrees.x = -55.0


func is_hostile_active() -> bool:
	return not disabled and not destroyed


func light_contribution(p: Vector3) -> float:
	if not is_hostile_active():
		return 0.0
	var from := _spot.global_position
	var to := p - from
	var d := to.length()
	if d > cam_range:
		return 0.0
	var fwd := -_spot.global_basis.z
	if rad_to_deg(fwd.angle_to(to)) > half_fov:
		return 0.0
	if not Util.ray_clear(get_world_3d().direct_space_state, from, p, Layers.WORLD | Layers.DOOR, [_head.get_rid()]):
		return 0.0
	return _spot.light_energy * (1.0 - d / cam_range) * 0.6


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_hostile_active():
		return
	_t += delta
	_alarm_cd -= delta
	_beep_cd -= delta
	_perceive_t -= delta
	var sees := false
	var p: Node = Game.player
	if _perceive_t <= 0.0:
		_perceive_t = 0.1
		if p != null and not p.dead:
			var from := _spot.global_position
			var target: Vector3 = p.get_aim_point()
			var to := target - from
			var d := to.length()
			var fwd := -_head.global_basis.z
			if d < cam_range and rad_to_deg(fwd.angle_to(to)) < half_fov + 4.0:
				if Util.ray_clear(get_world_3d().direct_space_state, from, target, Layers.WORLD | Layers.DOOR, [_head.get_rid()]):
					sees = true
					var vis: float = p.visibility
					var df := 1.0 - d / cam_range
					awareness += vis * (0.5 + 2.4 * df * df) * 0.1
		if not sees:
			awareness = maxf(awareness - 0.25 * 0.1, 0.0)
		_tracking = awareness > 0.3 and sees
	if _tracking and p != null:
		var to: Vector3 = global_basis.inverse() * (p.global_position - global_position)
		var want := rad_to_deg(atan2(-to.x, -to.z))
		_pivot.rotation_degrees.y = rad_to_deg(lerp_angle(deg_to_rad(_pivot.rotation_degrees.y), deg_to_rad(want), clampf(delta * 3.0, 0.0, 1.0)))
		_t = asin(clampf(angle_difference(deg_to_rad(yaw_center), deg_to_rad(_pivot.rotation_degrees.y)) / deg_to_rad(max(sweep, 1.0)), -1.0, 1.0)) * period / TAU
	else:
		_pivot.rotation_degrees.y = yaw_center + sin(_t * TAU / period) * sweep
	if awareness >= 1.0:
		_set_color(Color(1.0, 0.15, 0.1))
		if _alarm_cd <= 0.0 and p != null:
			_alarm_cd = 12.0
			Sfx.play_3d("cam_alert", global_position, 2.0)
			Game.raise_alarm(p.global_position, "Rilevato dalle telecamere.")
		awareness = minf(awareness, 1.2)
	elif awareness > 0.3:
		_set_color(Color(1.0, 0.8, 0.1))
		if _beep_cd <= 0.0:
			_beep_cd = 0.5
			Sfx.play_3d("cam_beep", global_position, 0.0)
	else:
		_set_color(Color(0.3, 1.0, 0.5))
