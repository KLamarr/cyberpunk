@tool
class_name Turret
extends Node3D
## Torretta automatica a sensori ottici: come le guardie, vede meglio se sei
## illuminato. Si spegne dal terminale di sicurezza, si distrugge a colpi di
## pistola, oppure si hackera dal pannello: con Hacking 3 diventa amica e spara
## alle guardie.
## Guarda verso la -Z locale: ruota il nodo per orientarla.

enum T { IDLE, ACQUIRE, FIRE, OFF, FRIENDLY, DESTROYED }

## Ampiezza della rotazione in pattuglia (gradi per lato).
@export_range(0.0, 90.0) var sweep := 35.0
@export var period := 6.0
## Portata in metri.
@export var t_range := 12.0
## Semiapertura del cono di rilevamento (gradi).
@export var half_fov := 45.0
## Parte spenta (es. si attiva solo con un evento).
@export var start_disabled := false
@export_flags_3d_render var zones_override := 0

var yaw_center := 0.0
var zones := 1
var state: int = T.IDLE
var hp := 90.0
var awareness := 0.0

var _pivot: Node3D
var _head: StaticBody3D
var _lens_mat: StandardMaterial3D
var _spot: SpotLight3D
var _muzzle: Node3D
var _t := 0.0
var _acq := 0.0
var _fire_cd := 0.0
var _lost := 0.0
var _perceive_t := 0.0
var _sees := false
var _target: Node = null
var _servo_cd := 0.0


func setup(pos: Vector3, yaw_deg: float, zone_mask: int) -> Turret:
	position = pos
	rotation_degrees.y = yaw_deg
	zones_override = zone_mask
	return self


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("turrets")
	add_to_group("game_lights")
	add_to_group("level_aware")
	if start_disabled:
		set_disabled(true)


func on_level_ready(level: Node) -> void:
	zones = zones_override if zones_override != 0 else level.zone_mask_at(global_position)
	_spot.light_cull_mask = zones
	Util.set_layers_recursive(self, zones)


func _build() -> void:
	var dark := Util.color_mat(Color(0.13, 0.14, 0.15))
	var metal := Util.mat("wall_panel", {"fit": Vector3(0.5, 0.35, 0.6), "color": Color(0.9, 0.8, 0.6)})
	Util.box(self, Vector3(0.5, 0.12, 0.3), Vector3(0, 0.25, 0.1), dark)
	_pivot = Node3D.new()
	add_child(_pivot)
	_head = StaticBody3D.new()
	_head.collision_layer = Layers.DEVICE
	_head.collision_mask = 0
	_head.rotation_degrees.x = -12.0
	_pivot.add_child(_head)
	Util.box(_head, Vector3(0.5, 0.35, 0.6), Vector3.ZERO, metal)
	for x in [-0.12, 0.12]:
		Util.box(_head, Vector3(0.06, 0.06, 0.5), Vector3(x, -0.04, -0.5), dark)
	_lens_mat = StandardMaterial3D.new()
	_lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var lens := Util.box(_head, Vector3(0.14, 0.08, 0.03), Vector3(0, 0.08, -0.31), _lens_mat)
	lens.set_meta("keep_layers", true)
	Util.add_box_collider(_head, Vector3(0.55, 0.4, 0.9), Vector3(0, 0, -0.2))
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, -0.04, -0.78)
	_head.add_child(_muzzle)
	_spot = SpotLight3D.new()
	_spot.spot_range = t_range
	_spot.spot_angle = 12.0
	_spot.light_energy = 0.8
	_spot.position = Vector3(0, 0.08, -0.35)
	_head.add_child(_spot)
	_apply_look()


func _apply_look() -> void:
	var c := Color(0.3, 1.0, 0.5)
	match state:
		T.ACQUIRE:
			c = Color(1.0, 0.8, 0.1)
		T.FIRE:
			c = Color(1.0, 0.1, 0.05)
		T.FRIENDLY:
			c = Color(0.3, 0.7, 1.0)
		T.OFF, T.DESTROYED:
			c = Color(0.05, 0.05, 0.05)
	_lens_mat.albedo_color = c
	_spot.light_color = c
	_spot.visible = state != T.OFF and state != T.DESTROYED


func is_hostile_active() -> bool:
	return state == T.IDLE or state == T.ACQUIRE or state == T.FIRE


func set_disabled(on: bool) -> void:
	if state == T.DESTROYED:
		return
	state = T.OFF if on else T.IDLE
	if on:
		_head.rotation_degrees.x = -45.0
		Sfx.play_3d("servo", global_position, -2.0)
	_apply_look()


func set_friendly() -> void:
	if state == T.DESTROYED:
		return
	state = T.FRIENDLY
	_head.rotation_degrees.x = -12.0
	Game.notify(tr("Turret reprogrammed: now targeting guards."), Color(0.4, 0.8, 1.0))
	_apply_look()


func save_state() -> Dictionary:
	return {"state": state, "hp": hp, "t": _t, "awareness": awareness}


func load_state(d: Dictionary) -> void:
	hp = d.hp
	_t = d.t
	awareness = float(d.awareness)
	state = int(d.state)
	if state == T.ACQUIRE or state == T.FIRE:
		state = T.IDLE   # la mira si riprende da sola se ti vede ancora
	match state:
		T.OFF:
			_head.rotation_degrees.x = -45.0
		T.FRIENDLY:
			_head.rotation_degrees.x = -12.0
		T.DESTROYED:
			_head.rotation_degrees.x = -50.0
	_apply_look()


func light_contribution(p: Vector3) -> float:
	if not _spot.visible:
		return 0.0
	var from := _spot.global_position
	var to := p - from
	var d := to.length()
	if d > t_range or rad_to_deg((-_spot.global_basis.z).angle_to(to)) > _spot.spot_angle:
		return 0.0
	if not Util.ray_clear(get_world_3d().direct_space_state, from, p, Layers.WORLD | Layers.DOOR, [_head.get_rid()]):
		return 0.0
	return _spot.light_energy * (1.0 - d / t_range) * 0.5


func take_damage(amount: float, hit_pos: Vector3, _dir: Vector3, _kind: String) -> void:
	if state == T.DESTROYED:
		return
	hp -= amount
	Effects.sparks(hit_pos, Color(1.0, 0.8, 0.4), 10, 3.0)
	Sfx.play_3d("hit_metal", hit_pos, -2.0)
	if state == T.IDLE or state == T.ACQUIRE:
		awareness = 1.0
		state = T.ACQUIRE
		_acq = 0.3
	if hp <= 0.0:
		state = T.DESTROYED
		_head.rotation_degrees.x = -50.0
		Effects.sparks(global_position, Color(1.0, 0.6, 0.2), 30, 5.0)
		Sfx.play_3d("grate_break", global_position, 3.0)
		Game.emit_noise(global_position, 16.0, "clang", Game.player)
		Game.notify(tr("Turret destroyed."))
		_apply_look()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or state == T.OFF or state == T.DESTROYED:
		return
	_t += delta
	_fire_cd -= delta
	_servo_cd -= delta
	_perceive_t -= delta
	if _perceive_t <= 0.0:
		_perceive_t = 0.1
		_perceive()
	match state:
		T.IDLE:
			_pivot.rotation_degrees.y = yaw_center + sin(_t * TAU / period) * sweep
			if awareness >= 1.0:
				state = T.ACQUIRE
				_acq = 0.7
				Sfx.play_3d("turret_alert", global_position, 3.0)
				_apply_look()
		T.ACQUIRE:
			_track(delta)
			_acq -= delta
			if _acq <= 0.0:
				state = T.FIRE
				_lost = 0.0
				_apply_look()
		T.FIRE:
			_track(delta)
			if _sees:
				_lost = 0.0
				if _fire_cd <= 0.0:
					_fire_cd = 0.18
					_shoot_at(_target, 0.55, Vector2(6.0, 8.0))
			else:
				_lost += delta
				if _lost > 2.5:
					state = T.IDLE
					awareness = 0.4
					_apply_look()
		T.FRIENDLY:
			if _target != null and _sees:
				_track(delta)
				if _fire_cd <= 0.0:
					_fire_cd = 0.22
					_shoot_at(_target, 0.8, Vector2(8.0, 10.0))
			else:
				_pivot.rotation_degrees.y = yaw_center + sin(_t * TAU / period) * sweep


func _perceive() -> void:
	_sees = false
	var from := _muzzle.global_position
	var fwd := -_head.global_basis.z
	var space := get_world_3d().direct_space_state
	if state == T.FRIENDLY:
		_target = null
		var best := INF
		for g in get_tree().get_nodes_in_group("guards"):
			if not g.is_active():
				continue
			var tp: Vector3 = g.global_position + Vector3.UP * 1.2
			var d := from.distance_to(tp)
			if d < t_range and d < best and rad_to_deg(Vector3(fwd.x, 0, fwd.z).angle_to(Vector3(tp.x - from.x, 0, tp.z - from.z))) < 80.0:
				if Util.ray_clear(space, from, tp, Layers.WORLD | Layers.DOOR, [_head.get_rid()]):
					best = d
					_target = g
		_sees = _target != null
		return
	var p: Node = Game.player
	_target = p
	if p == null or p.dead:
		return
	var aim: Vector3 = p.get_aim_point()
	var to := aim - from
	var d := to.length()
	var fov := half_fov if state == T.IDLE else 80.0
	if d < t_range and rad_to_deg(Vector3(fwd.x, 0, fwd.z).angle_to(Vector3(to.x, 0, to.z))) < fov:
		if Util.ray_clear(space, from, aim, Layers.WORLD | Layers.DOOR, [_head.get_rid()]):
			_sees = true
	if _sees:
		var vis: float = p.visibility
		var df := 1.0 - d / t_range
		awareness += vis * (0.6 + 2.6 * df) * 0.1
	else:
		awareness = maxf(awareness - 0.03, 0.0)


func _track(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var to: Vector3 = global_basis.inverse() * (_target.global_position - global_position)
	var want := atan2(-to.x, -to.z)
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, want, clampf(delta * 5.0, 0.0, 1.0))
	if _servo_cd <= 0.0:
		_servo_cd = 1.2
		Sfx.play_3d("servo", global_position, -8.0)


func _shoot_at(t: Node, base_chance: float, dmg: Vector2) -> void:
	if t == null or not is_instance_valid(t):
		return
	var from := _muzzle.global_position
	var aim: Vector3 = t.get_aim_point() if t.has_method("get_aim_point") else t.global_position + Vector3.UP * 1.2
	var chance := base_chance
	if t == Game.player:
		var hs := Vector2(t.velocity.x, t.velocity.z).length()
		chance -= 0.2 if hs > 4.0 else (0.08 if hs > 0.5 else 0.0)
		chance -= (1.0 - float(t.visibility)) * 0.3
		chance -= from.distance_to(aim) * 0.01
	chance = clampf(chance, 0.12, 0.85)
	Sfx.play_3d("turret_fire", from, 0.0, 0.1, 40.0)
	Effects.flash_light(from, Color(1.0, 0.7, 0.3), 2.0, 4.0, 0.05)
	Game.emit_noise(global_position, 22.0, "gunshot", self, {"target": aim})
	if randf() < chance:
		Effects.tracer(from, aim, Color(1.0, 0.4, 0.3))
		t.take_damage(randf_range(dmg.x, dmg.y), aim, (aim - from).normalized(), "turret")
	else:
		var miss := aim + Vector3(randf_range(-0.9, 0.9), randf_range(-0.4, 0.8), randf_range(-0.9, 0.9))
		var dir := (miss - from).normalized()
		var hit := Util.ray(get_world_3d().direct_space_state, from, from + dir * 30.0, Layers.WORLD | Layers.DOOR | Layers.PROP, [_head.get_rid()])
		var end: Vector3 = hit.get("position", from + dir * 30.0)
		Effects.tracer(from, end, Color(1.0, 0.4, 0.3))
		if not hit.is_empty():
			Effects.sparks(end, Color(1, 0.8, 0.5), 5, 2.5)
