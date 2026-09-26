class_name Player
extends CharacterBody3D
## Controller in prima persona da immersive sim:
## - camminata/corsa/accovacciamento, sporgersi (Q/E), mantle su sporgenze e condotti
## - visibilità calcolata dalle luci della scena (la "gemma di luce" alla Thief)
## - passi rumorosi in base a superficie, velocità e skill Furtività
## - chiave inglese (colpo alla nuca = KO) e pistola, frob di oggetti, trasporto
##   di oggetti fisici e di corpi.

const WALK := 3.2
const RUN := 5.4
const CROUCH_SPEED := 1.7
const ACCEL := 11.0
const AIR_ACCEL := 2.5
const GRAVITY := 18.0
const JUMP := 5.4
const STAND_H := 1.75
const CROUCH_H := 0.95
const RADIUS := 0.3
const EYE_STAND := 1.6
const EYE_CROUCH := 0.8
const FROB_DIST := 2.1
const WORLD_MASK := 1 | 8 | 16 | 32 | 128   # world, door, glass, prop, device
const SHOT_MASK := 1 | 4 | 8 | 16 | 32 | 128  # + npc

var health := 100.0
var max_health := 100.0
var dead := false
var crouching := false
var crouch_toggled := false
var lean := 0.0
var yaw := 0.0
var pitch := 0.0
var light_level := 0.0
var visibility := 0.0
var weapon := 0              # 0 = chiave inglese, 1 = pistola
var attack_cd := 0.0
var reloading := 0.0
var frob_target: Node = null
var held: Throwable = null
var carried_body: Node = null
var mantling := false
var zone_mask := 1
var god_mode := false        # solo per i test automatici: non si muore

var head: Node3D
var lean_pivot: Node3D
var camera: Camera3D
var viewmodel: Node3D
var wrench_vm: Node3D
var pistol_vm: Node3D
var muzzle: Node3D
var col: CollisionShape3D
var shape: CapsuleShape3D

var _step_accum := 0.0
var _vis_timer := 0.0
var _zone_timer := 0.0
var _muzzle_timer := 0.0
var _bob_t := 0.0
var _sway := Vector2.ZERO
var _kick := 0.0
var _swing_t := -1.0
var _eye := EYE_STAND
var _shake := 0.0
var _mantle_cd := 0.0
var _was_on_floor := true
var _last_vy := 0.0
var _last_step_surface := ""


func _ready() -> void:
	add_to_group("player")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.NPC | Layers.DOOR | Layers.GLASS | Layers.PROP | Layers.DEVICE
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50)
	max_health = 100.0 + 10.0 * Game.skill("forza")
	health = max_health

	shape = CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = STAND_H
	col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = STAND_H * 0.5
	add_child(col)

	head = Node3D.new()
	head.position.y = EYE_STAND
	add_child(head)
	lean_pivot = Node3D.new()
	head.add_child(lean_pivot)
	camera = Camera3D.new()
	camera.fov = 80.0
	camera.near = 0.04
	camera.far = 150.0
	camera.current = true
	lean_pivot.add_child(camera)
	_build_viewmodels()
	yaw = rotation.y
	Game.player = self


func on_skills_changed() -> void:
	var old := max_health
	max_health = 100.0 + 10.0 * Game.skill("forza")
	health += max_health - old


# --- viewmodel -------------------------------------------------------------------
func _build_viewmodels() -> void:
	viewmodel = Node3D.new()
	camera.add_child(viewmodel)
	var steel := Util.color_mat(Color(0.55, 0.57, 0.6))
	var dark := Util.color_mat(Color(0.12, 0.12, 0.13))
	var grip := Util.color_mat(Color(0.35, 0.12, 0.08))
	# chiave inglese
	wrench_vm = Node3D.new()
	wrench_vm.position = Vector3(0.26, -0.3, -0.46)
	viewmodel.add_child(wrench_vm)
	Util.box(wrench_vm, Vector3(0.035, 0.035, 0.42), Vector3(0, 0, -0.1), steel)
	Util.box(wrench_vm, Vector3(0.04, 0.04, 0.14), Vector3(0, 0, 0.08), grip)
	Util.box(wrench_vm, Vector3(0.12, 0.04, 0.05), Vector3(0.02, 0, -0.32), steel)
	Util.box(wrench_vm, Vector3(0.03, 0.04, 0.06), Vector3(-0.035, 0, -0.36), steel)
	Util.box(wrench_vm, Vector3(0.03, 0.04, 0.06), Vector3(0.075, 0, -0.36), steel)
	wrench_vm.rotation_degrees = Vector3(52, 12, -12)
	# pistola
	pistol_vm = Node3D.new()
	pistol_vm.position = Vector3(0.2, -0.2, -0.4)
	viewmodel.add_child(pistol_vm)
	Util.box(pistol_vm, Vector3(0.05, 0.07, 0.24), Vector3(0, 0, -0.06), dark)
	Util.box(pistol_vm, Vector3(0.045, 0.14, 0.06), Vector3(0, -0.09, 0.03), dark, Vector3(-12, 0, 0))
	Util.box(pistol_vm, Vector3(0.052, 0.025, 0.2), Vector3(0, 0.045, -0.06), Util.color_mat(Color(0.25, 0.26, 0.28)))
	Util.box(pistol_vm, Vector3(0.01, 0.012, 0.03), Vector3(0, 0.063, -0.15), Util.color_mat(Color(0.2, 0.9, 0.8), 2.0, true))
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.01, -0.2)
	pistol_vm.add_child(muzzle)
	for n in [wrench_vm, pistol_vm]:
		for c in n.get_children():
			if c is GeometryInstance3D:
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update_weapon_visibility()


func _update_weapon_visibility() -> void:
	var busy := held != null or carried_body != null
	wrench_vm.visible = weapon == 0 and not busy
	pistol_vm.visible = weapon == 1 and not busy


# --- input di visuale (chiamato da Main) -------------------------------------------
func look(rel: Vector2) -> void:
	if dead:
		return
	var s: float = Game.settings.sensitivity
	yaw -= deg_to_rad(rel.x * s)
	pitch = clampf(pitch - deg_to_rad(rel.y * s), deg_to_rad(-88), deg_to_rad(88))
	rotation.y = yaw
	head.rotation.x = pitch
	_sway += rel * 0.0006


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * (0.55 if crouching else 1.15)


func get_head_point() -> Vector3:
	return head.global_position


func is_active() -> bool:
	return not dead


# --- ciclo principale ----------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if dead:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	_timers(delta)
	if not mantling:
		_update_crouch(delta)
		_move(delta)
	_update_lean(delta)
	_update_view(delta)
	_update_frob()
	_handle_actions(delta)
	_update_held(delta)
	_vis_timer -= delta
	if _vis_timer <= 0.0:
		_vis_timer = 0.1
		_update_visibility()
	_zone_timer -= delta
	if _zone_timer <= 0.0 and Game.level:
		_zone_timer = 0.25
		zone_mask = Game.level.zone_mask_at(global_position + Vector3.UP * 0.5)
		Util.set_layers_recursive(viewmodel, zone_mask)
		if held:
			Util.set_layers_recursive(held, zone_mask)


func _timers(delta: float) -> void:
	attack_cd = max(attack_cd - delta, 0.0)
	_muzzle_timer = max(_muzzle_timer - delta, 0.0)
	_mantle_cd = max(_mantle_cd - delta, 0.0)
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			var need: int = Game.MAG_SIZE - Game.ammo_mag
			var take: int = min(need, Game.ammo_reserve)
			Game.ammo_mag += take
			Game.ammo_reserve -= take
			Game.inventory_changed.emit()


func _move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := (global_basis * Vector3(input.x, 0, input.y))
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	var running := Input.is_action_pressed("sprint") and not crouching and input.y < -0.1 and carried_body == null
	var speed := WALK
	if crouching:
		speed = CROUCH_SPEED * (1.0 + 0.08 * Game.skill("furtivita"))
	elif running:
		speed = RUN
	if carried_body != null:
		speed *= 0.6
	elif held != null and held.mass > 3.0:
		speed *= 0.8
	var on_floor := is_on_floor()
	var accel := ACCEL if on_floor else AIR_ACCEL
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.lerp(wish * speed, clampf(accel * delta, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	if not on_floor:
		velocity.y -= GRAVITY * delta

	if Input.is_action_just_pressed("jump"):
		if not _try_mantle():
			if on_floor and not crouching:
				velocity.y = JUMP
				Game.emit_noise(global_position, 2.5, "step", self)
	elif not on_floor and Input.is_action_pressed("jump") and _mantle_cd <= 0.0:
		_try_mantle()
	if mantling:
		return

	_was_on_floor = on_floor
	_last_vy = velocity.y
	move_and_slide()
	# spinge i piccoli oggetti fisici
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider()
		if body is RigidBody3D and not body.freeze:
			(body as RigidBody3D).apply_central_impulse(-c.get_normal() * 0.4)
	# atterraggio
	if not _was_on_floor and is_on_floor() and _last_vy < -5.0:
		var fall := -_last_vy
		Sfx.play_3d("land", global_position, -4.0 + fall * 0.4)
		Game.emit_noise(global_position, clampf(fall * 1.1, 3.0, 14.0) * (1.0 - 0.12 * Game.skill("furtivita")), "step", self)
		if fall > 11.5:
			take_damage((fall - 11.0) * 8.0, global_position, Vector3.DOWN, "fall")
	# passi
	if is_on_floor():
		var hs := Vector2(velocity.x, velocity.z).length()
		_bob_t += hs * delta * 2.2
		_step_accum += hs * delta
		var stride := 0.62 if crouching else (0.95 if running else 0.78)
		if _step_accum >= stride:
			_step_accum = 0.0
			_footstep(running)


func _footstep(running: bool) -> void:
	var surf := "concrete"
	if Game.level:
		surf = Game.level.surface_at(global_position)
	var base: float = {"metal": 1.0, "grate": 1.25, "concrete": 0.75, "carpet": 0.35}.get(surf, 0.8)
	var mult := 0.3 if crouching else (1.9 if running else 1.0)
	var radius := 7.0 * base * mult * (1.0 - 0.15 * Game.skill("furtivita"))
	Game.emit_noise(global_position, radius, "step", self)
	var vol := linear_to_db(clampf(radius / 9.0, 0.08, 1.2)) - 4.0
	Sfx.play_3d("step_" + surf, global_position + Vector3.UP * 0.05, vol, 0.12, 20.0)


func _update_crouch(delta: float) -> void:
	if Input.is_action_just_pressed("crouch_toggle"):
		crouch_toggled = not crouch_toggled
	var want := Input.is_action_pressed("crouch") or crouch_toggled
	if want and not crouching:
		_set_crouch(true)
	elif not want and crouching and _fits_at(global_position, STAND_H):
		_set_crouch(false)
	var target_eye := EYE_CROUCH if crouching else EYE_STAND
	_eye = move_toward(_eye, target_eye, delta * 4.5)


func _set_crouch(on: bool) -> void:
	crouching = on
	shape.height = CROUCH_H if on else STAND_H
	col.position.y = shape.height * 0.5


func _fits_at(pos: Vector3, h: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS - 0.02
	cap.height = h
	q.shape = cap
	q.transform = Transform3D(Basis(), pos + Vector3.UP * (h * 0.5 + 0.03))
	q.collision_mask = WORLD_MASK
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# --- mantle ----------------------------------------------------------------------
func _try_mantle() -> bool:
	if carried_body != null or _mantle_cd > 0.0:
		return false
	var space := get_world_3d().direct_space_state
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var feet := global_position
	var ex: Array[RID] = [get_rid()]
	# 1) c'è un ostacolo davanti?
	var hit_low := Util.ray(space, feet + Vector3.UP * 0.5, feet + Vector3.UP * 0.5 + fwd * 0.8, WORLD_MASK, ex)
	var hit_mid := Util.ray(space, feet + Vector3.UP * 1.1, feet + Vector3.UP * 1.1 + fwd * 0.8, WORLD_MASK, ex)
	if hit_low.is_empty() and hit_mid.is_empty():
		return false
	# 2) spazio libero sopra la testa e in avanti alla quota massima
	var top := feet + Vector3.UP * 2.02
	if not Util.ray_clear(space, feet + Vector3.UP * 1.2, top, WORLD_MASK, ex):
		return false
	var probe := top + fwd * 0.75
	if not Util.ray_clear(space, top, probe, WORLD_MASK, ex):
		return false
	# 3) superficie d'appoggio
	var down := Util.ray(space, probe, Vector3(probe.x, feet.y + 0.3, probe.z), WORLD_MASK, ex)
	if down.is_empty() or down.normal.y < 0.7:
		return false
	var ledge: Vector3 = down.position
	var h := ledge.y - feet.y
	if h < 0.4 or h > 1.95:
		return false
	var target := ledge + fwd * 0.05
	var crouch_after := false
	if _fits_at(target, STAND_H):
		crouch_after = false
	elif _fits_at(target, CROUCH_H):
		crouch_after = true
	else:
		return false
	# esegue
	mantling = true
	_mantle_cd = 0.6
	velocity = Vector3.ZERO
	if crouch_after:
		_set_crouch(true)
	var tw := create_tween()
	tw.tween_property(self, "global_position", Vector3(feet.x, ledge.y + 0.05, feet.z) - fwd * 0.05, 0.28).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "global_position", target + Vector3.UP * 0.02, 0.22).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): mantling = false)
	Game.emit_noise(global_position, 2.0 * (1.0 - 0.12 * Game.skill("furtivita")), "step", self)
	return true


# --- sporgersi -------------------------------------------------------------------
func _update_lean(delta: float) -> void:
	var want := 0.0
	if not mantling and carried_body == null:
		want = Input.get_axis("lean_left", "lean_right")
	lean = move_toward(lean, want, delta * 4.0)
	var dist := 0.55 * lean
	if absf(dist) > 0.01:
		var space := get_world_3d().direct_space_state
		var side := global_basis.x * signf(dist)
		var from := global_position + Vector3.UP * _eye
		var hit := Util.ray(space, from, from + side * (absf(dist) + 0.25), WORLD_MASK, [get_rid()])
		if not hit.is_empty():
			var allowed := maxf(from.distance_to(hit.position) - 0.25, 0.0)
			dist = signf(dist) * minf(absf(dist), allowed)
	lean_pivot.position.x = dist
	lean_pivot.rotation.z = -lean * 0.15


func _update_view(delta: float) -> void:
	head.position.y = _eye
	# bobbing e sway del viewmodel
	var moving := Vector2(velocity.x, velocity.z).length()
	var bob_amt := clampf(moving / RUN, 0.0, 1.0)
	var bob := Vector3(cos(_bob_t) * 0.012, absf(sin(_bob_t)) * 0.016, 0.0) * bob_amt
	_sway = _sway.lerp(Vector2.ZERO, clampf(delta * 8.0, 0.0, 1.0))
	_kick = move_toward(_kick, 0.0, delta * 1.2)
	viewmodel.position = bob + Vector3(-_sway.x, _sway.y, _kick * 0.35)
	viewmodel.rotation = Vector3(_kick * 1.4, 0, 0)
	# animazione colpo di chiave
	if _swing_t >= 0.0:
		_swing_t += delta / 0.42
		var t := _swing_t
		var r: float
		if t < 0.25:
			r = lerpf(0.0, 0.9, t / 0.25)
		elif t < 0.55:
			r = lerpf(0.9, -1.3, (t - 0.25) / 0.3)
		else:
			r = lerpf(-1.3, 0.0, clampf((t - 0.55) / 0.45, 0.0, 1.0))
		wrench_vm.rotation = Vector3(deg_to_rad(52) + r, deg_to_rad(12) - r * 0.4, deg_to_rad(-12))
		if _swing_t >= 1.0:
			_swing_t = -1.0
	# ricarica
	if reloading > 0.0:
		pistol_vm.rotation.x = lerpf(pistol_vm.rotation.x, -0.8, clampf(delta * 10.0, 0.0, 1.0))
		pistol_vm.position.y = lerpf(pistol_vm.position.y, -0.32, clampf(delta * 10.0, 0.0, 1.0))
	else:
		pistol_vm.rotation.x = lerpf(pistol_vm.rotation.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		pistol_vm.position.y = lerpf(pistol_vm.position.y, -0.2, clampf(delta * 10.0, 0.0, 1.0))
	# scossa
	if _shake > 0.0:
		_shake = max(_shake - delta * 2.5, 0.0)
		camera.h_offset = randf_range(-1, 1) * _shake * 0.05
		camera.v_offset = randf_range(-1, 1) * _shake * 0.05
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


# --- frob --------------------------------------------------------------------------
func _update_frob() -> void:
	var new_target: Node = null
	if held == null and carried_body == null:
		var space := get_world_3d().direct_space_state
		var from := camera.global_position
		var to := from - camera.global_basis.z * FROB_DIST
		var mask := Layers.WORLD | Layers.NPC | Layers.DOOR | Layers.PROP | Layers.INTERACT | Layers.DEVICE
		var q := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
		q.hit_back_faces = false
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var t := Util.find_method_owner(hit.collider, "frob")
			if t != null and t.get_frob_text() != "":
				new_target = t
	if new_target != frob_target:
		if frob_target != null and is_instance_valid(frob_target):
			Util.set_highlight(frob_target, false)
		frob_target = new_target
		if frob_target != null:
			Util.set_highlight(frob_target, true)


func get_frob_prompt() -> String:
	if held != null:
		return tr("[%s] Throw   [%s] Put down") % [Game.key_label("attack"), Game.key_label("frob")]
	if carried_body != null:
		return tr("[%s] Put down the body") % Game.key_label("frob")
	if frob_target != null and is_instance_valid(frob_target):
		return frob_target.get_frob_text()
	return ""


# --- azioni ------------------------------------------------------------------------
func _handle_actions(_delta: float) -> void:
	if mantling:
		return
	if Input.is_action_just_pressed("frob"):
		if held != null:
			_drop_held(false)
		elif carried_body != null:
			_drop_body()
		elif frob_target != null and is_instance_valid(frob_target):
			frob_target.frob(self)
	if Input.is_action_just_pressed("attack"):
		if held != null:
			_drop_held(true)
		elif carried_body != null:
			pass
		elif weapon == 0:
			_swing()
		else:
			_fire()
	if Input.is_action_just_pressed("reload"):
		_reload()
	if Input.is_action_just_pressed("weapon_1"):
		_select_weapon(0)
	if Input.is_action_just_pressed("weapon_2"):
		_select_weapon(1)
	if Input.is_action_just_pressed("weapon_next") or Input.is_action_just_pressed("weapon_prev"):
		_select_weapon(1 - weapon)
	if Input.is_action_just_pressed("medpatch"):
		use_medpatch()


func _select_weapon(w: int) -> void:
	if w == weapon or reloading > 0.0:
		return
	weapon = w
	attack_cd = max(attack_cd, 0.25)
	Sfx.play_ui("ui_click", -8.0)
	_update_weapon_visibility()
	Game.inventory_changed.emit()


func use_medpatch() -> void:
	if Game.medpatches <= 0:
		Game.notify(tr("No medipatches."), Color(1, 0.6, 0.4))
		return
	if health >= max_health:
		Game.notify(tr("You're already at full health."))
		return
	Game.medpatches -= 1
	health = min(health + 40.0, max_health)
	Sfx.play_ui("medpatch")
	Game.inventory_changed.emit()


func _swing() -> void:
	if attack_cd > 0.0:
		return
	attack_cd = 0.55
	_swing_t = 0.0
	Sfx.play_3d("swing", global_position + Vector3.UP * 1.4, -4.0)
	get_tree().create_timer(0.15, false).timeout.connect(_swing_hit)


func _swing_hit() -> void:
	if dead:
		return
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var hit := Util.ray(space, from, from + dir * 1.9, SHOT_MASK, [get_rid()])
	if hit.is_empty():
		return
	var dmg := 12.0 + 7.0 * Game.skill("forza")
	var target := Util.find_method_owner(hit.collider, "take_damage")
	if target != null and target.has_method("can_knockout") and target.can_knockout(global_position):
		target.knock_out()
		Sfx.play_3d("hit_flesh", hit.position, 2.0)
		return
	if target != null:
		target.take_damage(dmg, hit.position, dir, "melee")
	if hit.collider is RigidBody3D:
		(hit.collider as RigidBody3D).apply_impulse(dir * 3.0, hit.position - hit.collider.global_position)
	if target == null or not target.is_in_group("guards"):
		Sfx.play_3d("hit_metal", hit.position, -2.0)
		Effects.sparks(hit.position, Color(1, 0.85, 0.5), 6, 2.0)
		Game.emit_noise(hit.position, 7.0, "clang", self)
	else:
		Sfx.play_3d("hit_flesh", hit.position)


func _fire() -> void:
	if attack_cd > 0.0 or reloading > 0.0:
		return
	if Game.ammo_mag <= 0:
		attack_cd = 0.3
		Sfx.play_3d("empty", global_position + Vector3.UP * 1.4)
		if Game.ammo_reserve > 0:
			_reload()
		return
	Game.ammo_mag -= 1
	Game.stats.shots += 1
	Game.inventory_changed.emit()
	attack_cd = 0.32
	_kick = 0.12
	_muzzle_timer = 0.12
	var armi := Game.skill("armi")
	var spread := 3.2 * (1.0 - 0.22 * armi)
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs > 0.5:
		spread += 1.8 if hs > 4.0 else 0.8
	if crouching:
		spread *= 0.7
	var dir := -camera.global_basis.z
	dir = dir.rotated(camera.global_basis.x, deg_to_rad(randf_range(-spread, spread) * 0.5))
	dir = dir.rotated(camera.global_basis.y, deg_to_rad(randf_range(-spread, spread) * 0.5))
	var from := camera.global_position
	var space := get_world_3d().direct_space_state
	var hit := Util.ray(space, from, from + dir * 70.0, SHOT_MASK, [get_rid()])
	Sfx.play_3d("pistol", global_position + Vector3.UP * 1.4, 0.0, 0.05, 60.0)
	Effects.flash_light(muzzle.global_position, Color(1.0, 0.8, 0.5), 2.5, 5.0)
	Game.emit_noise(global_position, 30.0, "gunshot", self)
	if hit.is_empty():
		Effects.tracer(muzzle.global_position, from + dir * 40.0)
		return
	Effects.tracer(muzzle.global_position, hit.position)
	var dmg := 24.0 + 5.0 * armi
	var target := Util.find_method_owner(hit.collider, "take_damage")
	if target != null:
		target.take_damage(dmg, hit.position, dir, "bullet")
	if hit.collider is RigidBody3D:
		(hit.collider as RigidBody3D).apply_impulse(dir * 4.0, hit.position - hit.collider.global_position)
	if target == null or not target.is_in_group("guards"):
		Effects.sparks(hit.position, Color(1, 0.9, 0.6), 8, 3.0)
		Effects.dust(hit.position, hit.normal)
		Sfx.play_3d("impact", hit.position, -2.0)
		Game.emit_noise(hit.position, 6.0, "impact", self)


func _reload() -> void:
	if reloading > 0.0 or weapon != 1 or Game.ammo_mag >= Game.MAG_SIZE or Game.ammo_reserve <= 0:
		return
	reloading = 1.6 - 0.22 * Game.skill("armi")
	Sfx.play_3d("reload", global_position + Vector3.UP * 1.3, -3.0)


# --- oggetti e corpi ------------------------------------------------------------------
func pick_up(body: Throwable) -> void:
	if held != null or carried_body != null:
		return
	held = body
	body.set_held(true)
	Util.set_highlight(body, false)
	frob_target = null
	Sfx.play_ui("ui_click", -6.0)
	_update_weapon_visibility()


func _update_held(delta: float) -> void:
	if held == null:
		return
	if not is_instance_valid(held):
		held = null
		_update_weapon_visibility()
		return
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var reach := 1.0 + held.size.length() * 0.4
	var target := from + fwd * reach + Vector3.DOWN * 0.15
	var hit := Util.ray(get_world_3d().direct_space_state, from, target, WORLD_MASK, [get_rid()])
	if not hit.is_empty():
		target = hit.position - fwd * (0.1 + held.size.length() * 0.3)
	held.global_position = held.global_position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))
	held.rotation.y = lerp_angle(held.rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0))


func _drop_held(throw: bool) -> void:
	var body := held
	held = null
	body.set_held(false)
	body.linear_velocity = velocity * 0.5
	if throw:
		var power: float = (7.5 + 1.8 * Game.skill("forza")) / maxf(1.0, sqrt(body.mass))
		body.linear_velocity += -camera.global_basis.z * power + Vector3.UP * 1.2
		body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		Sfx.play_3d("swing", global_position + Vector3.UP * 1.4, -8.0)
	add_collision_exception_with(body)
	get_tree().create_timer(0.4, false).timeout.connect(_clear_exception.bind(body))
	attack_cd = 0.3
	_update_weapon_visibility()


func _clear_exception(body: Node) -> void:
	if is_instance_valid(body):
		remove_collision_exception_with(body)


func carry_body(body: Node) -> void:
	if held != null or carried_body != null:
		return
	carried_body = body
	body.set_carried(true)
	Util.set_highlight(body, false)
	frob_target = null
	Sfx.play_3d("body_fall", global_position, -10.0)
	Game.notify(tr("Carrying the body. [%s] to put it down.") % Game.key_label("frob"))
	_update_weapon_visibility()


func _drop_body() -> void:
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.0
	var spot := global_position + fwd * 0.9
	var wall := Util.ray(space, from, spot + Vector3.UP * 1.0, WORLD_MASK, [get_rid()])
	if not wall.is_empty():
		spot = global_position
	var down := Util.ray(space, spot + Vector3.UP * 1.0, spot + Vector3.DOWN * 2.0, WORLD_MASK, [get_rid()])
	if not down.is_empty():
		spot = down.position
	carried_body.drop_at(spot, yaw)
	carried_body = null
	_update_weapon_visibility()


# --- salvataggi (vedi SaveGame) --------------------------------------------------------
func save_state() -> Dictionary:
	var lvl: Node = Game.level
	return {
		"pos": global_position, "vel": velocity, "yaw": yaw, "pitch": pitch, "health": health, "weapon": weapon,
		"crouch": crouching, "crouch_toggled": crouch_toggled,
		"held": String(lvl.get_path_to(held)) if held != null and is_instance_valid(held) else "",
		"carried": String(lvl.get_path_to(carried_body)) if carried_body != null and is_instance_valid(carried_body) else "",
	}


func load_state(d: Dictionary) -> void:
	global_position = d.pos
	velocity = d.vel   # anche a mezz'aria: la caduta (e il suo danno) continua
	yaw = d.yaw
	rotation.y = yaw
	pitch = d.pitch
	head.rotation.x = pitch
	max_health = 100.0 + 10.0 * Game.skill("forza")
	health = clampf(float(d.health), 1.0, max_health)
	weapon = int(d.weapon)
	crouch_toggled = bool(d.crouch_toggled)
	if bool(d.crouch):
		_set_crouch(true)
		_eye = EYE_CROUCH
		head.position.y = _eye
	var lvl: Node = Game.level
	if String(d.held) != "":
		var h := lvl.get_node_or_null(NodePath(d.held)) as Throwable
		if h != null:
			held = h
			h.set_held(true)
	if String(d.carried) != "":
		var b := lvl.get_node_or_null(NodePath(d.carried))
		if b != null and b.has_method("set_carried"):
			carried_body = b
			b.set_carried(true)
	_update_weapon_visibility()


# --- visibilità ----------------------------------------------------------------------
func _update_visibility() -> void:
	var p := get_aim_point()
	var sum := 0.0
	for l in get_tree().get_nodes_in_group("game_lights"):
		sum += l.light_contribution(p)
	light_level = clampf(1.0 - exp(-1.7 * sum) + 0.03, 0.0, 1.0)
	var m := 1.0
	if crouching:
		m *= 0.72
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs > 4.0:
		m *= 1.3
	elif hs > 0.5:
		m *= 1.1
	else:
		m *= 0.92
	m *= 1.0 - 0.12 * Game.skill("furtivita")
	if carried_body != null:
		m *= 1.2
	visibility = clampf(light_level * m + (0.7 if _muzzle_timer > 0.0 else 0.0), 0.0, 1.0)


# --- danni -----------------------------------------------------------------------
func take_damage(amount: float, _hit_pos: Vector3, dir: Vector3, _kind: String) -> void:
	if dead:
		return
	health -= amount
	if god_mode:
		health = maxf(health, 1.0)
	_shake = min(_shake + amount / 25.0, 1.0)
	Sfx.play_ui("hurt", -3.0, randf_range(0.9, 1.1))
	Game.player_damaged.emit(amount, global_position - dir * 5.0)
	if health <= 0.0:
		health = 0.0
		_die()


func _die() -> void:
	dead = true
	if held != null:
		_drop_held(false)
	if carried_body != null:
		_drop_body()
	viewmodel.visible = false
	var tw := create_tween()
	tw.tween_property(head, "position:y", 0.25, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lean_pivot, "rotation:z", 1.2, 0.8)
	tw.tween_interval(1.4)
	tw.tween_callback(Game.on_player_died)
