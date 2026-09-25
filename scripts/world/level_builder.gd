class_name LevelBuilder
extends RefCounted
## Costruisce la geometria del livello "alla DromEd": si parte da un blocco
## solido e si scavano volumi d'aria (brush sottrattivi). Brush additivi
## aggiungono pilastri, gradini, ecc.
##
## compile() fa il bake del CSG in mesh statiche, le divide per ZONA e per
## materiale, e crea una collisione trimesh unica. Ogni zona è un bit dei
## render layer: le luci di una stanza illuminano solo la sua zona, così la luce
## non "passa" attraverso i muri (nel Dark Engine ci pensavano le lightmap).

const SHADER := preload("res://shaders/level_surface.gdshader")

var root: Node3D
var csg: CSGCombiner3D
var bounds: AABB
var brushes: Array = []  # {aabb, zones, set, air, vol}
var sets := {}           # nome -> {material, sound}
var _mat_to_set := {}


func _init(level_root: Node3D, bmin: Vector3, bmax: Vector3) -> void:
	root = level_root
	bounds = AABB(bmin, bmax - bmin)
	csg = CSGCombiner3D.new()
	csg.name = "CSG"
	root.add_child(csg)
	var solid := CSGBox3D.new()
	solid.size = bounds.size
	solid.position = bounds.get_center()
	csg.add_child(solid)


static func vmin(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))


static func vmax(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))


## Definisce un "set di superfici": texture per pareti, pavimento e soffitto
## più il tipo di superficie per i passi (metal, grate, concrete, carpet).
func define_set(set_name: String, wall: String, floor_tex: String, ceil: String, sound := "concrete", scales := Vector3(0.5, 0.5, 0.5), tint := Color.WHITE) -> void:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tex_wall", Util.tex(wall))
	m.set_shader_parameter("tex_floor", Util.tex(floor_tex))
	m.set_shader_parameter("tex_ceil", Util.tex(ceil))
	m.set_shader_parameter("wall_scale", scales.x)
	m.set_shader_parameter("floor_scale", scales.y)
	m.set_shader_parameter("ceil_scale", scales.z)
	m.set_shader_parameter("tint", tint)
	sets[set_name] = {"material": m, "sound": sound}
	_mat_to_set[m.get_instance_id()] = set_name


## Brush d'aria: scava un volume dal solido.
func carve(a: Vector3, b: Vector3, set_name: String, zones: int) -> void:
	var mn := vmin(a, b)
	var mx := vmax(a, b)
	var box := CSGBox3D.new()
	box.size = mx - mn
	box.position = (mn + mx) * 0.5
	box.operation = CSGShape3D.OPERATION_SUBTRACTION
	box.material = sets[set_name].material
	csg.add_child(box)
	var aabb := AABB(mn, mx - mn)
	brushes.append({"aabb": aabb, "zones": zones, "set": set_name, "air": true, "vol": aabb.get_volume()})


## Brush solido: aggiunge materia (pilastri, pedane...). Può essere ruotato.
func add_solid(a: Vector3, b: Vector3, set_name: String, zones: int, rot_deg := Vector3.ZERO) -> void:
	var mn := vmin(a, b)
	var mx := vmax(a, b)
	var box := CSGBox3D.new()
	box.size = mx - mn
	box.position = (mn + mx) * 0.5
	box.rotation_degrees = rot_deg
	box.operation = CSGShape3D.OPERATION_UNION
	box.material = sets[set_name].material
	csg.add_child(box)
	var local := AABB(-box.size * 0.5, box.size)
	var aabb: AABB = Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), box.position) * local
	brushes.append({"aabb": aabb, "zones": zones, "set": set_name, "air": false, "vol": aabb.get_volume()})


func _brush_at(p: Vector3, want_air: int, grow := 0.02) -> Dictionary:
	# want_air: 1 = solo aria, 0 = solo solidi, -1 = qualsiasi
	var best := {}
	var best_vol := INF
	for b in brushes:
		if want_air == 1 and not b.air:
			continue
		if want_air == 0 and b.air:
			continue
		if b.aabb.grow(grow).has_point(p) and b.vol < best_vol:
			best = b
			best_vol = b.vol
	return best


func _on_outer_boundary(p0: Vector3, p1: Vector3, p2: Vector3) -> bool:
	var e := 0.01
	var mn := bounds.position
	var mx := bounds.end
	for axis in 3:
		for plane in [mn[axis], mx[axis]]:
			if abs(p0[axis] - plane) < e and abs(p1[axis] - plane) < e and abs(p2[axis] - plane) < e:
				return true
	return false


## Bake del CSG → mesh per zona/materiale + collisione. Restituisce lo StaticBody.
func compile(parent: Node3D) -> StaticBody3D:
	# il CSG si aggiorna in differita: forziamo il calcolo ora
	if csg.has_method("_update_shape"):
		csg.call("_update_shape")
	var mesh: ArrayMesh = csg.bake_static_mesh()
	var buckets := {}
	var faces := PackedVector3Array()
	if mesh == null:
		push_error("LevelBuilder: bake del CSG fallito")
		return null
	for si in mesh.get_surface_count():
		var mat := mesh.surface_get_material(si)
		var surf_set: String = ""
		if mat != null:
			surf_set = _mat_to_set.get(mat.get_instance_id(), "")
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = PackedVector3Array()
		if arr[Mesh.ARRAY_NORMAL] != null:
			nrm = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] != null:
			idx = arr[Mesh.ARRAY_INDEX]
		var indexed := idx.size() > 0
		var tri_count := (idx.size() if indexed else v.size()) / 3
		for t in tri_count:
			var i0 := idx[t * 3] if indexed else t * 3
			var i1 := idx[t * 3 + 1] if indexed else t * 3 + 1
			var i2 := idx[t * 3 + 2] if indexed else t * 3 + 2
			var p0 := v[i0]
			var p1 := v[i1]
			var p2 := v[i2]
			if _on_outer_boundary(p0, p1, p2):
				continue
			var c := (p0 + p1 + p2) / 3.0
			var br := _brush_at(c, -1)
			if br.is_empty():
				continue
			var set_name: String = surf_set if surf_set != "" else String(br.set)
			var zones: int = br.zones
			var key := "%d|%s" % [zones, set_name]
			if not buckets.has(key):
				buckets[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "set": set_name, "zones": zones}
			var bk: Dictionary = buckets[key]
			var fn: Vector3
			if nrm.size() > 0:
				fn = nrm[i0]
			else:
				fn = (p2 - p0).cross(p1 - p0).normalized()
			bk.v.append(p0); bk.v.append(p1); bk.v.append(p2)
			bk.n.append(fn); bk.n.append(fn); bk.n.append(fn)
			faces.append(p0); faces.append(p1); faces.append(p2)

	var body := StaticBody3D.new()
	body.name = "LevelGeometry"
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	for key in buckets:
		var bk: Dictionary = buckets[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = bk.v
		arrays[Mesh.ARRAY_NORMAL] = bk.n
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "Geo_" + String(key).replace("|", "_")
		mi.mesh = am
		mi.material_override = sets[bk.set].material
		mi.layers = bk.zones
		body.add_child(mi)
	csg.queue_free()
	csg = null
	return body


# --- interrogazioni a runtime ---------------------------------------------------
func zone_mask_at(p: Vector3) -> int:
	var b := _brush_at(p, 1, 0.0)
	if b.is_empty():
		b = _brush_at(p, 1, 0.6)
	return int(b.zones) if not b.is_empty() else 1


func surface_at(feet: Vector3) -> String:
	var s := _brush_at(feet + Vector3(0, -0.06, 0), 0, 0.0)
	if not s.is_empty():
		return sets[s.set].sound
	var a := _brush_at(feet + Vector3(0, 0.3, 0), 1, 0.0)
	if not a.is_empty():
		return sets[a.set].sound
	return "concrete"
