class_name Effects
extends RefCounted
## Piccoli effetti visivi usa-e-getta (scintille, polvere, traccianti).

static func _world() -> Node3D:
	if Game.level != null and is_instance_valid(Game.level):
		return Game.level
	return null


static func sparks(pos: Vector3, col := Color(1.0, 0.8, 0.4), amount := 12, speed := 3.5) -> void:
	var w := _world()
	if w == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.8, 0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, 0.025)
	mesh.material = Util.color_mat(col, 2.0, true)
	p.mesh = mesh
	w.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


static func dust(pos: Vector3, normal: Vector3) -> void:
	var w := _world()
	if w == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 8
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 35.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -2.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.05, 0.05)
	mesh.material = Util.color_mat(Color(0.45, 0.45, 0.42), 0.0, true)
	p.mesh = mesh
	w.add_child(p)
	p.global_position = pos + normal * 0.03
	p.emitting = true
	p.finished.connect(p.queue_free)


static func tracer(from: Vector3, to: Vector3, col := Color(1.0, 0.85, 0.5)) -> void:
	var w := _world()
	if w == null:
		return
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.012, length)
	mi.mesh = bm
	mi.material_override = Util.color_mat(col, 3.0, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tree := w.get_tree()
	tree.create_timer(0.05, false).timeout.connect(mi.queue_free)


static func flash_light(pos: Vector3, col: Color, energy := 3.0, rng := 6.0, time := 0.06) -> void:
	var w := _world()
	if w == null:
		return
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	w.add_child(l)
	l.global_position = pos
	w.get_tree().create_timer(time, false).timeout.connect(l.queue_free)
