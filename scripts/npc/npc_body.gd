@tool
class_name NPCBody
extends Node3D
## Corpo visibile di un NPC: Skeleton3D generato da NPCRig + una sola MeshInstance3D
## skinnata costruita da NPCBodyBuilder. L'animazione è procedurale sulle ossa (passo,
## corsa, mira, respiro, postura), guidata dalla fase del passo del proprietario: così i
## passi udibili della guardia restano sincronizzati con le gambe.
## Nell'editor (anteprima del creatore) si anima da sola secondo preview_pose.

enum Pose { RIPOSO, CAMMINA, CORRI, MIRA, A_TERRA }

@export var definition: NPCDefinition:
	set(v):
		if definition != null and definition.changed.is_connected(_on_def_changed):
			definition.changed.disconnect(_on_def_changed)
		definition = v
		if definition != null and live_update:
			definition.changed.connect(_on_def_changed)
		if is_inside_tree():
			rebuild()
## Anteprima nell'editor: posa animata.
@export var preview_pose: Pose = Pose.RIPOSO
@export var preview_animate := false
## Ricostruisce la mesh quando la definizione cambia (serve solo nel creatore).
var live_update := false
## Parte evidenziata nell'anteprima del creatore ("testa", "braccio", "acc3"...).
var highlight_part := "":
	set(v):
		highlight_part = v
		if is_inside_tree():
			rebuild()
## Secondi fra due aggiornamenti della posa (0 = ogni frame): per gli NPC lontani.
var lod_interval := 0.0

var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var stats := NPCBodyBuilder.Stats.new()

var _bi := {}
var _rest := {}
var _muzzle_bone := -1
var _muzzle_off := Vector3.ZERO
var _t := 0.0
var _phase := 0.0
var _aim := 0.0
var _lod_acc := 0.0
var _k := 0.0      ## intensità della corsa, smorzata
var _move := 0.0   ## 0 = fermo, 1 = in movimento, smorzato (niente scatti alla posa neutra)
var _down := false
var _rebuild_queued := false
var _glow := Color(0.3, 0.9, 1.0)


func _ready() -> void:
	if skeleton == null and definition != null:
		rebuild()


func _on_def_changed() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_do_rebuild.call_deferred()


func _do_rebuild() -> void:
	_rebuild_queued = false
	if is_inside_tree():
		rebuild()


func rebuild() -> void:
	if skeleton != null:
		skeleton.queue_free()
		remove_child(skeleton)
	skeleton = null
	mesh_instance = null
	_bi.clear()
	_rest.clear()
	if definition == null:
		return
	var lay := NPCRig.layout(definition)
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	for i in NPCRig.BONES.size():
		var bn := NPCRig.BONES[i]
		skeleton.add_bone(bn)
		_bi[bn] = i
	for i in NPCRig.BONES.size():
		var bn := NPCRig.BONES[i]
		var parent := NPCRig.PARENTS[i]
		var local: Vector3 = lay.pos[bn]
		if parent != "":
			skeleton.set_bone_parent(i, _bi[parent])
			local -= lay.pos[parent]
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, local))
		_rest[i] = local
	skeleton.reset_bone_poses()
	add_child(skeleton)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	stats = NPCBodyBuilder.Stats.new()
	if highlight_part != "" or live_update:
		mesh_instance.mesh = NPCBodyBuilder.build_mesh(definition, {"highlight": highlight_part}, stats)
	else:
		var am: ArrayMesh = NPCBodyBuilder.get_mesh(definition)
		mesh_instance.mesh = am
		stats.vertices = am.surface_get_array_len(0) if am.get_surface_count() > 0 else 0
		stats.triangles = stats.vertices / 3
	mesh_instance.skin = skeleton.create_skin_from_rest_transforms()
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")
	var mz := NPCBodyBuilder.muzzle_local(definition)
	_muzzle_bone = _bi.get(mz[0], 0)
	_muzzle_off = mz[1]
	_glow = definition.color(SegmentShape.Slot.LUCE)
	set_glow(_glow)
	if _down:
		_apply_down_pose()
	else:
		_apply_pose(0.0, 0.0, 0.0, 0.0)


func bone_index(bone_name: String) -> int:
	return _bi.get(bone_name, -1)


func default_glow() -> Color:
	return definition.color(SegmentShape.Slot.LUCE) if definition != null else Color(0.3, 0.9, 1.0)


## Colore delle parti luminose (visore, impianto CALMA): cambia con lo stato della guardia.
func set_glow(c: Color) -> void:
	_glow = c
	if mesh_instance != null:
		mesh_instance.set_instance_shader_parameter("glow_color", c)


## Posizione globale della bocca dell'arma (o della punta della mano destra).
func muzzle_position() -> Vector3:
	if skeleton == null or _muzzle_bone < 0:
		return global_position + Vector3.UP * 1.3
	return skeleton.global_transform * (skeleton.get_bone_global_pose(_muzzle_bone) * _muzzle_off)


# --- animazione -------------------------------------------------------------------
## Da chiamare ogni frame: speed in m/s, phase = fase del passo (radianti), aim 0..1.
func update_motion(delta: float, speed: float, phase: float, aim: float, run_speed := 4.0) -> void:
	_t += delta
	_aim = move_toward(_aim, aim, delta * 5.0)
	# ampiezza del passo e piegamento smorzati: fermandosi (o alternando fermo/cammino,
	# come in combattimento) la posa rallenta invece di scattare
	var moving := speed > 0.1
	_move = move_toward(_move, 1.0 if moving else 0.0, delta * 4.0)
	_k = move_toward(_k, clampf(speed / maxf(run_speed, 0.1), 0.0, 1.0) if moving else 0.0, delta * 3.0)
	if lod_interval > 0.0:
		_lod_acc += delta
		if _lod_acc < lod_interval:
			return
		_lod_acc = 0.0
	_apply_pose(_k, phase, _aim, _move)


func set_down(on: bool) -> void:
	_down = on
	if skeleton == null:
		return
	if on:
		_apply_down_pose()
	else:
		_apply_pose(0.0, 0.0, 0.0, 0.0)


func _rot(bone: String, e: Vector3) -> void:
	skeleton.set_bone_pose_rotation(_bi[bone], Quaternion.from_euler(e))


const _LEGS := [["thigh_l", "shin_l", "foot_l"], ["thigh_r", "shin_r", "foot_r"]]


## move: 0 = fermo, 1 = in movimento (valori intermedi mentre parte o si ferma).
func _apply_pose(k: float, phase: float, aim: float, move: float) -> void:
	if skeleton == null:
		return
	var post := definition.posture if definition != null else 0.0
	var amp := (0.24 + 0.3 * k) * move
	var swing := sin(phase) * amp
	var breath := sin(_t * 2.0) * 0.015
	# gambe: la coscia oscilla, il ginocchio si piega quando la gamba torna avanti
	for side in 2:
		var leg: Array = _LEGS[side]
		var ph := phase + (0.0 if side == 0 else PI)
		var th := sin(ph) * amp
		var knee := -(0.06 + (0.4 + 0.7 * k) * maxf(0.0, sin(ph + 1.1))) * move
		_rot(leg[0], Vector3(th, 0, 0))
		_rot(leg[1], Vector3(knee, 0, 0))
		_rot(leg[2], Vector3(-(th + knee) * 0.6, 0, 0))
	# busto: postura, inclinazione in corsa, respiro
	_rot("spine", Vector3(-post * 0.16 - 0.1 * k + breath * 0.5, sin(phase) * 0.05 * k, 0))
	_rot("chest", Vector3(-post * 0.1 + breath, -sin(phase) * 0.08 * k * (1.0 - aim), 0))
	_rot("neck", Vector3(post * 0.18 + 0.06 * k, 0, 0))
	_rot("head", Vector3(post * 0.08, 0, 0))
	var hip := _bi["hips"] as int
	skeleton.set_bone_pose_position(hip, _rest[hip] + Vector3(0, -absf(sin(phase)) * 0.035 * k - 0.01 * move, 0))
	# braccia: oscillano in controfase alle gambe; in mira il destro punta, il sinistro sostiene
	var elbow := 0.12 + 0.75 * k
	_rot("upperarm_l", Vector3(lerpf(-swing * 0.7, 1.18, aim), lerpf(0.0, -0.25, aim), lerpf(-0.09, 0.62, aim)))
	_rot("forearm_l", Vector3(lerpf(elbow, 0.3, aim), 0, lerpf(0.0, 0.35, aim)))
	_rot("hand_l", Vector3.ZERO)
	_rot("upperarm_r", Vector3(lerpf(swing * 0.7, 1.45, aim), 0, lerpf(0.09, -0.12, aim)))
	_rot("forearm_r", Vector3(lerpf(elbow, 0.08, aim), 0, 0))
	_rot("hand_r", Vector3(lerpf(0.0, -0.05, aim), 0, 0))


func _apply_down_pose() -> void:
	for i in NPCRig.BONES.size():
		skeleton.set_bone_pose_rotation(i, Quaternion.IDENTITY)
		skeleton.set_bone_pose_position(i, _rest[i])
	_rot("upperarm_l", Vector3(0.35, 0, -0.75))
	_rot("upperarm_r", Vector3(0.2, 0, 0.9))
	_rot("forearm_l", Vector3(0.5, 0, 0))
	_rot("forearm_r", Vector3(0.3, 0, 0))
	_rot("thigh_l", Vector3(0.1, 0, -0.12))
	_rot("thigh_r", Vector3(-0.05, 0, 0.1))
	_rot("shin_l", Vector3(-0.35, 0, 0))
	_rot("head", Vector3(0.25, 0.35, 0))


# --- anteprima nell'editor ------------------------------------------------------------
## Fa avanzare l'animazione dell'anteprima (il creatore la chiama dal suo _process).
func preview_tick(delta: float) -> void:
	if skeleton == null or not preview_animate:
		return
	match preview_pose:
		Pose.RIPOSO:
			update_motion(delta, 0.0, _phase, 0.0)
		Pose.CAMMINA:
			var sp := definition.walk_speed if definition else 1.8
			_phase += delta * (5.0 + sp * 1.6)
			update_motion(delta, sp, _phase, 0.0, definition.run_speed if definition else 4.0)
		Pose.CORRI:
			var sp := definition.run_speed if definition else 4.0
			_phase += delta * (5.0 + sp * 1.6)
			update_motion(delta, sp, _phase, 0.0, sp)
		Pose.MIRA:
			update_motion(delta, 0.0, _phase, 1.0)
		Pose.A_TERRA:
			if not _down:
				set_down(true)
			return
	if _down:
		_down = false
