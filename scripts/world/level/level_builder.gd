class_name LevelBuilder
extends RefCounted
## Compila la geometria di un livello (nodo LevelGeometry, fatto di Brush dentro
## Zone) in mesh statiche + una collisione trimesh.
##
## Ogni triangolo prodotto dal CSG viene assegnato al brush che lo ha generato
## (quello più piccolo che lo contiene), da cui prende zona e SurfaceSet. Le mesh
## sono divise per zona e per materiale: ogni zona è un bit dei render layer, e le
## luci di una zona illuminano solo quel bit, così la luce non attraversa i muri
## anche senza ombre (nel Dark Engine ci pensavano le lightmap).

## I brush d'aria vengono allargati di 1 mm prima del CSG: due stanze che "si
## toccano" in editor possono differire di un milionesimo di metro per gli
## arrotondamenti dei float, e il CSG lascerebbe un muro sottilissimo in mezzo.
const AIR_GROW := 0.001

var brushes: Array = []   # {aabb, zones, surface, air, vol, path}
var zones: Array = []     # {path, layer}  (per il validatore)
var solid_aabb := AABB()  # il blocco "Solido" (vuoto se manca)
var _mat_to_surface := {}


## Registra i Brush sotto `geo` (volumi e zone servono anche a runtime).
func collect(geo: Node) -> void:
	brushes.clear()
	zones.clear()
	_mat_to_surface.clear()
	solid_aabb = AABB()
	if geo.get_child_count() > 0 and geo.get_child(0) is CSGBox3D and not (geo.get_child(0) is Brush):
		var sb: CSGBox3D = geo.get_child(0)
		solid_aabb = sb.global_transform * AABB(-sb.size * 0.5, sb.size)
	for n in _descendants(geo):
		var path := "%s/%s" % [geo.name, geo.get_path_to(n)]
		if n is Zone:
			zones.append({"path": path, "layer": (n as Zone).layer})
		if not (n is Brush):
			continue
		var b: Brush = n
		var aabb := b.world_aabb()
		brushes.append({
			"aabb": aabb, "zones": b.zone_mask(), "surface": b.surface,
			"air": b.is_air(), "vol": aabb.get_volume(), "path": path,
		})
		if b.surface != null:
			_mat_to_surface[b.surface.get_material().get_instance_id()] = b.surface


func _descendants(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_descendants(c))
	return out


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


## Bake del CSG → mesh per zona/materiale + collisione. Restituisce lo StaticBody.
## Il nodo `geo` viene rimosso: in gioco serve solo il risultato.
func compile(geo: CSGCombiner3D, parent: Node3D) -> StaticBody3D:
	collect(geo)
	# i solidi aggiunti vanno applicati dopo tutte le zone, qualunque sia l'ordine in editor
	for c in geo.get_children():
		if c.get_index() > 0 and not (c is Zone) and c is CSGShape3D:
			geo.move_child(c, geo.get_child_count() - 1)
	for n in _descendants(geo):
		if n is Brush and (n as Brush).is_air():
			(n as Brush).size += Vector3.ONE * (AIR_GROW * 2.0)
	# il CSG si aggiorna in differita: forziamo il calcolo ora
	if geo.has_method("_update_shape"):
		geo.call("_update_shape")
	var mesh: ArrayMesh = geo.bake_static_mesh()
	if mesh == null:
		push_error("LevelBuilder: bake del CSG fallito")
		return null
	var to_world := geo.global_transform
	var basis := to_world.basis
	var buckets := {}
	var faces := PackedVector3Array()
	for si in mesh.get_surface_count():
		var mat := mesh.surface_get_material(si)
		var surf: SurfaceSet = null
		if mat != null:
			surf = _mat_to_surface.get(mat.get_instance_id())
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
			var p0 := to_world * v[i0]
			var p1 := to_world * v[i1]
			var p2 := to_world * v[i2]
			var br := _brush_at((p0 + p1 + p2) / 3.0, -1)
			if br.is_empty():
				continue   # facce esterne del blocco solido: mai visibili
			var s: SurfaceSet = surf if surf != null else br.surface
			if s == null:
				continue
			var zm: int = br.zones
			var key := "%d|%d" % [zm, s.get_instance_id()]
			if not buckets.has(key):
				buckets[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "surface": s, "zones": zm}
			var bk: Dictionary = buckets[key]
			var fn: Vector3
			if nrm.size() > 0:
				fn = (basis * nrm[i0]).normalized()
			else:
				fn = (p2 - p0).cross(p1 - p0).normalized()
			bk.v.append(p0); bk.v.append(p1); bk.v.append(p2)
			bk.n.append(fn); bk.n.append(fn); bk.n.append(fn)
			faces.append(p0); faces.append(p1); faces.append(p2)

	var body := StaticBody3D.new()
	body.name = "GeometriaCompilata"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	body.global_transform = Transform3D.IDENTITY
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
		var sname: String = bk.surface.resource_path.get_file().get_basename()
		mi.name = "Geo_%d_%s" % [bk.zones, sname]
		mi.mesh = am
		mi.material_override = bk.surface.get_material()
		mi.layers = bk.zones
		body.add_child(mi)
	geo.queue_free()
	return body


# --- interrogazioni a runtime ---------------------------------------------------
## Il brush d'aria (volume di una stanza) che contiene p, allargato di `grow`.
func air_brush_at(p: Vector3, grow := 0.0) -> Dictionary:
	return _brush_at(p, 1, grow)


func zone_mask_at(p: Vector3) -> int:
	var b := _brush_at(p, 1, 0.0)
	if b.is_empty():
		b = _brush_at(p, 1, 0.6)
	return int(b.zones) if not b.is_empty() else 1


func surface_at(feet: Vector3) -> String:
	var s := _brush_at(feet + Vector3(0, -0.06, 0), 0, 0.0)
	if not s.is_empty() and s.surface != null:
		return s.surface.footsteps
	var a := _brush_at(feet + Vector3(0, 0.3, 0), 1, 0.0)
	if not a.is_empty() and a.surface != null:
		return a.surface.footsteps
	return "concrete"
