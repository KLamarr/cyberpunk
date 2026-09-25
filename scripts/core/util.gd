class_name Util
extends RefCounted
## Funzioni di servizio statiche: materiali retro, costruzione mesh a primitive,
## raycast, evidenziazione degli oggetti "frobbabili".

static var _mat_cache := {}
static var _highlight_mat: StandardMaterial3D


static func tex(tex_name: String) -> Texture2D:
	return load("res://assets/textures/%s.png" % tex_name)


## Materiale con texture a filtro nearest (look Dark Engine).
## opts:
##   density: float    -> triplanare in spazio mondo, ripetizioni per metro (default 0.5 = texture ogni 2 m)
##   fit: Vector3      -> triplanare locale che "stende" la texture una volta per faccia di un box di quelle dimensioni
##   color: Color      -> tinta
##   emission: float   -> intensità emissiva (usa la texture come emissione, o emission_tex)
##   emission_tex: String
##   unshaded: bool, alpha: bool (alpha scissor), transparent: float (0..1), cull_off: bool
static func mat(tex_name: String, opts := {}) -> StandardMaterial3D:
	var key := tex_name + str(opts)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 1.0
	m.metallic_specular = 0.2
	if tex_name != "":
		m.albedo_texture = tex(tex_name)
	m.albedo_color = opts.get("color", Color.WHITE)
	if opts.has("fit"):
		var s: Vector3 = opts.fit
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(1.0 / max(s.x, 0.01), 1.0 / max(s.y, 0.01), 1.0 / max(s.z, 0.01))
		m.uv1_offset = Vector3(0.5, 0.5, 0.5)
	elif tex_name != "" and not opts.get("mesh_uv", false):
		var d: float = opts.get("density", 0.5)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(d, d, d)
	if opts.has("emission"):
		m.emission_enabled = true
		m.emission_energy_multiplier = opts.emission
		# in Godot 4 l'emissione è (colore + texture): colore nero = solo la texture
		if opts.has("emission_tex"):
			m.emission_texture = tex(opts.emission_tex)
			m.emission = Color.BLACK
		elif opts.has("emission_color"):
			m.emission = opts.emission_color
		else:
			m.emission_texture = m.albedo_texture
			m.emission = Color.BLACK
	if opts.get("unshaded", false):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if opts.get("alpha", false):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if opts.has("transparent"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = opts.transparent
	if opts.get("cull_off", false):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[key] = m
	return m


static func color_mat(c: Color, emission := 0.0, unshaded := false) -> StandardMaterial3D:
	var key := "col" + str(c) + str(emission) + str(unshaded)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = m
	return m


# --- mesh primitive -------------------------------------------------------------
static func box(parent: Node, size: Vector3, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func cylinder(parent: Node, radius: float, height: float, pos: Vector3, material: Material, rot_deg := Vector3.ZERO, sides := 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = sides  # pochi lati: look low-poly
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func quad(parent: Node, size: Vector2, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func add_box_collider(body: CollisionObject3D, size: Vector3, pos := Vector3.ZERO, rot_deg := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	cs.rotation_degrees = rot_deg
	body.add_child(cs)
	return cs


## Box statico solido (mesh + collisione).
static func static_box(parent: Node, size: Vector3, pos: Vector3, material: Material, layer := 1, rot_deg := Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation_degrees = rot_deg
	parent.add_child(sb)
	box(sb, size, Vector3.ZERO, material)
	add_box_collider(sb, size)
	return sb


static func set_layers_recursive(n: Node, layers: int) -> void:
	if n is VisualInstance3D and not n.has_meta("keep_layers"):
		(n as VisualInstance3D).layers = layers
	for c in n.get_children():
		set_layers_recursive(c, layers)


# --- raycast --------------------------------------------------------------------
static func ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int, exclude: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.hit_back_faces = false
	q.collide_with_areas = false
	return space.intersect_ray(q)


static func ray_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int, exclude: Array[RID] = []) -> bool:
	return ray(space, from, to, mask, exclude).is_empty()


# --- frob -----------------------------------------------------------------------
static func find_method_owner(n: Node, method: String) -> Node:
	var cur := n
	var depth := 0
	while cur != null and depth < 6:
		if cur.has_method(method):
			return cur
		cur = cur.get_parent()
		depth += 1
	return null


static func highlight_material() -> StandardMaterial3D:
	if _highlight_mat == null:
		_highlight_mat = StandardMaterial3D.new()
		_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_highlight_mat.albedo_color = Color(0.22, 0.28, 0.24)
		_highlight_mat.render_priority = 1
	return _highlight_mat


static func set_highlight(n: Node, on: bool) -> void:
	if n == null or not is_instance_valid(n):
		return
	var m: Material = highlight_material() if on else null
	_apply_highlight(n, m)


static func _apply_highlight(n: Node, m: Material) -> void:
	if n is GeometryInstance3D and not (n is Label3D) and not n.has_meta("no_highlight"):
		(n as GeometryInstance3D).material_overlay = m
	for c in n.get_children():
		_apply_highlight(c, m)


static func fmt_time(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]
