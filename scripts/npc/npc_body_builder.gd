@tool
class_name NPCBodyBuilder
extends RefCounted
## Genera la mesh di un NPC dalla sua NPCDefinition: ogni segmento è un loft di anelli
## low-poly lungo il proprio osso, con pesi rigidi (ogni vertice appartiene al 100% a un
## solo osso) e i segmenti che si sovrappongono alle articolazioni, come in System Shock 2.
## Tutto il corpo, accessori compresi, finisce in UNA superficie con UN materiale
## condiviso da tutti gli NPC: una draw call per personaggio.

const ATLAS_PATH := "res://assets/textures/npc_atlas.png"
const SHADER_PATH := "res://shaders/npc_body.gdshader"
const HIGHLIGHT := Color(1.0, 0.82, 0.2)

static var _material: ShaderMaterial
static var _cache := {}


class Stats:
	var vertices := 0
	var triangles := 0
	var segments := 0


## Materiale condiviso (atlante + shader con colore del visore per istanza).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH)
		_material.set_shader_parameter("atlas", load(ATLAS_PATH))
	return _material


## Mesh in cache per la definizione (ricostruita solo se la definizione è cambiata).
## opts: "highlight": nome di una parte da evidenziare (anteprima del creatore).
static func get_mesh(def: NPCDefinition, opts := {}) -> ArrayMesh:
	if not opts.is_empty():
		return build_mesh(def, opts)
	var key := def.get_instance_id()
	var c: Array = _cache.get(key, [])
	if not c.is_empty() and c[0] == def.revision:
		return c[1]
	var m := build_mesh(def)
	if _cache.size() > 64:
		for k in _cache.keys():
			if not is_instance_id_valid(k):
				_cache.erase(k)
	_cache[key] = [def.revision, m]
	return m


static func build_mesh(def: NPCDefinition, opts := {}, stats: Stats = null) -> ArrayMesh:
	var lay := NPCRig.layout(def)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ctx := {"st": st, "def": def, "group": 1, "tris": 0, "verts": 0, "aabb": AABB(), "first": true}
	var hl: String = opts.get("highlight", "")
	for seg in lay.segments:
		var part := def.get_part(seg.part)
		if part == null or part.shape == null:
			continue
		var frame := segment_frame(seg.from, seg.to)
		_loft(ctx, part.shape, part.shape_b, part.morph, frame, seg.from.distance_to(seg.to),
			seg.radial, lay.bone_index(seg.bone), seg.left, hl == seg.part)
	var ai := 0
	for a in def.attachments:
		if a == null or not a.enabled or a.shape == null or not lay.pos.has(String(a.bone)):
			ai += 1
			continue
		var targets: Array[String] = [String(a.bone)]
		if a.mirror and NPCRig.mirror_bone(a.bone) != String(a.bone):
			targets.append(NPCRig.mirror_bone(a.bone))
		for b in targets:
			var frame := attachment_frame(lay, a, b)
			var ls: float = lay.lengthscale.get(b, lay.scale)
			var rs: float = lay.radial.get(b, lay.scale)
			_loft(ctx, a.shape, null, 0.0, frame, a.length * ls, Vector2(rs, rs),
				lay.bone_index(b), b != String(a.bone), hl == "acc%d" % ai)
		ai += 1
	if ctx.verts == 0:
		return ArrayMesh.new()
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	# margine per braccia alzate e pose: la mesh skinnata usa l'AABB di riposo
	mesh.custom_aabb = (ctx.aabb as AABB).grow(0.45)
	if stats != null:
		stats.vertices = ctx.verts
		stats.triangles = ctx.tris
		stats.segments = ctx.group / 2
	return mesh


## Sistema di riferimento di un segmento: Y lungo l'osso, -Z verso il "davanti"
## (la faccia per la testa, il dorso del piede per il piede), origine all'attacco.
static func segment_frame(from: Vector3, to: Vector3) -> Transform3D:
	var y := (to - from).normalized()
	if y.length() < 0.5:
		y = Vector3.UP
	var fwd := Vector3.FORWARD
	if absf(y.dot(fwd)) > 0.8:
		fwd = Vector3.UP
	var front := (fwd - y * y.dot(fwd)).normalized()
	var z := -front
	var x := y.cross(z)
	return Transform3D(Basis(x, y, z), from)


static func attachment_frame(lay: NPCRig.Layout, a: NPCAttachment, bone: String) -> Transform3D:
	var mirrored := bone != String(a.bone)
	var off := a.offset
	var rot := a.rotation_deg
	if mirrored:
		off.x = -off.x
		rot.y = -rot.y
		rot.z = -rot.z
	var ls: float = lay.lengthscale.get(bone, lay.scale)
	var origin: Vector3 = lay.pos[bone] + off * ls
	var basis := Basis.from_euler(rot * (PI / 180.0))
	return Transform3D(basis, origin)


## Punto della bocca dell'arma, nello spazio dell'osso (usato da NPCBody.muzzle_position).
static func muzzle_local(def: NPCDefinition) -> Array:
	var lay := NPCRig.layout(def)
	for a in def.attachments:
		var is_gun := a != null and a.shape != null and (NPCLibrary.shape_name_of(a.shape).begins_with("pistol") or a.label.to_lower().contains("pistol"))
		if is_gun and a.enabled and String(a.bone) == "hand_r":
			var f := attachment_frame(lay, a, "hand_r")
			var tip: Vector3 = f.origin + f.basis.y * (a.length * float(lay.lengthscale.get("hand_r", lay.scale)))
			return ["hand_r", tip - lay.pos["hand_r"]]
	for seg in lay.segments:
		if seg.bone == "hand_r":
			return ["hand_r", seg.to - lay.pos["hand_r"]]
	return ["hips", Vector3(0.3, 0.5, -0.3)]


# --- loft ---------------------------------------------------------------------------
static func _loft(ctx: Dictionary, a: SegmentShape, b: SegmentShape, morph: float, frame: Transform3D,
		length: float, radial: Vector2, bone: int, left: bool, highlight: bool) -> void:
	var st: SurfaceTool = ctx.st
	var def: NPCDefinition = ctx.def
	if b == null:
		morph = 0.0
	var n := a.sides
	var ts: Array[float] = []
	for k in a.rings:
		ts.append(float(k) / float(a.rings - 1))
	if a.split > 0.001 and a.split < 0.999:
		var dup := false
		for t in ts:
			dup = dup or absf(t - a.split) < 0.02
		if not dup:
			ts.append(a.split)
			ts.sort()
	var y0 := -a.extend_start
	var y1 := 1.0 + a.extend_end
	var mx := -1.0 if left else 1.0
	# anelli: posizione nel mondo di ogni vertice (n + 1 per chiudere la cucitura UV)
	var ring_pos: Array = []
	var axis: Array[Vector3] = []
	for t in ts:
		var r := a.radius_at(t)
		var bl := a.bulge_at(t)
		if morph > 0.0:
			r = r.lerp(b.radius_at(t), morph)
			bl = lerpf(bl, b.bulge_at(t), morph)
		r *= radial
		bl *= radial.y
		var y := lerpf(y0, y1, t) * length
		var ring := PackedVector3Array()
		ring.resize(n + 1)
		for i in n + 1:
			var th := TAU * float(i) / float(n)
			var sm := a.section_at(i % n, n)
			if morph > 0.0:
				sm = lerpf(sm, b.section_at(i % n, n), morph)
			var lp := Vector3(sin(th) * r.x * sm * mx, y, cos(th) * r.y * sm - bl)
			ring[i] = frame * lp
		ring_pos.append(ring)
		axis.append(frame * Vector3(0, y, -bl))
	var g: int = ctx.group
	ctx.group = g + 2
	var bones := PackedInt32Array([bone, 0, 0, 0])
	var weights := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
	# fianchi
	for k in ts.size() - 1:
		var t0 := ts[k]
		var t1 := ts[k + 1]
		var use_b := (t0 + t1) * 0.5 >= a.split
		var band: int = a.band_b if use_b else a.band
		var col := _slot_color(def, a.color_slot_b if use_b else a.color_slot, highlight)
		var ra: PackedVector3Array = ring_pos[k]
		var rb: PackedVector3Array = ring_pos[k + 1]
		var mid_axis := (axis[k] + axis[k + 1]) * 0.5
		for i in n:
			var p00 := ra[i]
			var p01 := ra[i + 1]
			var p11 := rb[i + 1]
			var p10 := rb[i]
			var u0 := float(i) / n
			var u1 := float(i + 1) / n
			var v0 := _v(band, t0)
			var v1 := _v(band, t1)
			var outward := (p00 + p01 + p11 + p10) * 0.25 - mid_axis
			var sg := g if a.smooth else -1
			_tri(ctx, [p00, p01, p11], [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1)], outward, col, sg, bones, weights)
			_tri(ctx, [p00, p11, p10], [Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1)], outward, col, sg, bones, weights)
	# tappi
	var dir := frame.basis.y
	if a.cap_start:
		_cap(ctx, ring_pos[0], axis[0], -dir, _v(a.band, 0.0), _slot_color(def, a.color_slot, highlight), bones, weights, n)
	if a.cap_end:
		var last := ts.size() - 1
		var ub := ts[last] >= a.split
		_cap(ctx, ring_pos[last], axis[last], dir, _v(a.band_b if ub else a.band, 1.0),
			_slot_color(def, a.color_slot_b if ub else a.color_slot, highlight), bones, weights, n)


static func _cap(ctx: Dictionary, ring: PackedVector3Array, center: Vector3, outward: Vector3, v: float,
		col: Color, bones: PackedInt32Array, weights: PackedFloat32Array, n: int) -> void:
	for i in n:
		_tri(ctx, [center, ring[i], ring[i + 1]],
			[Vector2(0.5, v), Vector2(float(i) / n, v), Vector2(float(i + 1) / n, v)],
			outward, col, -1, bones, weights)


## Coordinata v nell'atlante: fascia della banda, estremità del segmento in alto.
static func _v(band: int, t: float) -> float:
	return (float(band) + 0.06 + (1.0 - clampf(t, 0.0, 1.0)) * 0.88) / float(SegmentShape.BAND_COUNT)


static func _slot_color(def: NPCDefinition, slot: int, highlight: bool) -> Color:
	var c := def.color(slot)
	if slot == SegmentShape.Slot.LUCE:
		c.a = 0.0
	else:
		c.a = 1.0
	if highlight:
		# anche le parti luminose diventano gialle (alpha 1 = non emissive)
		c = c.lerp(HIGHLIGHT, 0.6) if c.a > 0.5 else HIGHLIGHT
		c.a = 1.0
	return c


## Triangolo con avvolgimento orario visto da fuori (faccia frontale in Godot).
static func _tri(ctx: Dictionary, p: Array, uv: Array, outward: Vector3, col: Color, group: int,
		bones: PackedInt32Array, weights: PackedFloat32Array) -> void:
	var a: Vector3 = p[0]
	var b: Vector3 = p[1]
	var c: Vector3 = p[2]
	var nrm := (c - a).cross(b - a)
	if nrm.length_squared() < 1e-12:
		return
	var order := [0, 1, 2]
	if nrm.dot(outward) < 0.0:
		order = [0, 2, 1]
	var st: SurfaceTool = ctx.st
	for j in order:
		st.set_smooth_group(group)
		st.set_color(col)
		st.set_uv(uv[j])
		st.set_bones(bones)
		st.set_weights(weights)
		st.add_vertex(p[j])
		if ctx.first:
			ctx.aabb = AABB(p[j], Vector3.ZERO)
			ctx.first = false
		else:
			ctx.aabb = (ctx.aabb as AABB).expand(p[j])
	ctx.tris += 1
	ctx.verts += 3
