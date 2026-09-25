@tool
extends SubViewportContainer
## Anteprima del creatore di NPC: un piccolo mondo 3D con l'NPC su un pavimento, una
## plafoniera e la camera che gli gira attorno. Con "retro" il SubViewport lavora a metà
## risoluzione con lo stesso shader di dithering del gioco: vedi l'NPC come in partita.
## Trascina col sinistro per ruotare, rotella per lo zoom, destro/centrale per alzare o
## abbassare la camera; un clic su una parte del corpo la seleziona.

signal part_clicked(part: String)

const POST := preload("res://shaders/retro_post.gdshader")

var body: NPCBody
var viewport: SubViewport
var camera: Camera3D
var lamp: OmniLight3D
var env: Environment
var retro := true:
	set(v):
		retro = v
		_apply_retro()

var _yaw := PI - 0.4
var _pitch := -0.12
var _dist := 3.2
var _target_y := 1.0
var _drag := false
var _moved := 0.0
var _post_mat: ShaderMaterial


func _init() -> void:
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(320, 300)
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.018, 0.024)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.35, 0.4)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	lamp = OmniLight3D.new()
	lamp.position = Vector3(0.4, 2.9, 1.4)
	lamp.omni_range = 7.0
	lamp.omni_attenuation = 1.2
	lamp.light_color = Color(0.86, 0.93, 1.0)
	lamp.light_energy = 1.5
	world.add_child(lamp)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, 160, 0)
	rim.light_energy = 0.25
	rim.light_color = Color(0.6, 0.75, 1.0)
	world.add_child(rim)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = load("res://assets/textures/floor_tiles.png")
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	fm.uv1_scale = Vector3(4, 4, 1)
	fm.roughness = 1.0
	floor_mi.material_override = fm
	world.add_child(floor_mi)
	body = NPCBody.new()
	body.live_update = true
	body.preview_animate = true
	world.add_child(body)
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.05
	world.add_child(camera)
	camera.current = true
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = POST
	_apply_retro()
	_update_camera()


func set_definition(def: NPCDefinition) -> void:
	body.definition = def
	if def != null:
		_target_y = clampf(def.height * 0.55, 0.7, 1.3)
	_update_camera()


func set_light(energy: float) -> void:
	lamp.light_energy = energy
	env.ambient_light_energy = 0.15 + energy * 0.3


func frame_part(part: String) -> void:
	if body.definition == null or body.skeleton == null:
		return
	if part == "" or part.begins_with("acc"):
		_target_y = clampf(body.definition.height * 0.55, 0.7, 1.3)
		_dist = 3.2
	else:
		var lay := NPCRig.layout(body.definition)
		for sg in lay.segments:
			if sg.part == part:
				_target_y = (sg.from.y + sg.to.y) * 0.5
				_dist = 1.4 if part in ["testa", "collo", "mano", "piede"] else 2.1
				break
	_update_camera()


func _apply_retro() -> void:
	if not is_instance_valid(viewport):
		return
	material = _post_mat if retro else null
	stretch_shrink = 2 if retro else 1


func _update_camera() -> void:
	if camera == null:
		return
	var off := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	var target := Vector3(0, _target_y, 0)
	camera.position = target + off
	camera.look_at_from_position(camera.position, target, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(0.6, _dist * 0.9)
			_update_camera()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(8.0, _dist * 1.1)
			_update_camera()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_moved = 0.0
			else:
				_drag = false
				if _moved < 4.0:
					_pick(mb.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_moved += mm.relative.length()
			_yaw -= mm.relative.x * 0.01
			_pitch = clampf(_pitch - mm.relative.y * 0.006, -1.2, 0.6)
			_update_camera()
			accept_event()
		elif mm.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			_target_y = clampf(_target_y + mm.relative.y * 0.004 * _dist, 0.05, 2.2)
			_update_camera()
			accept_event()


## Seleziona la parte il cui segmento (nella posa attuale) passa più vicino al clic.
func _pick(pos: Vector2) -> void:
	if body.definition == null or body.skeleton == null:
		return
	var vp_pos := pos / float(stretch_shrink)
	var lay := NPCRig.layout(body.definition)
	var best := ""
	var best_d := 26.0 / stretch_shrink
	for sg in lay.segments:
		var bi := body.bone_index(sg.bone)
		var bone_tr := body.skeleton.global_transform * body.skeleton.get_bone_global_pose(bi)
		var rest: Vector3 = lay.pos[sg.bone]
		var a := bone_tr * (sg.from - rest)
		var b := bone_tr * (sg.to - rest)
		if camera.is_position_behind(a) or camera.is_position_behind(b):
			continue
		var sa := camera.unproject_position(a)
		var sb := camera.unproject_position(b)
		var d := _seg_dist(vp_pos, sa, sb)
		if d < best_d:
			best_d = d
			best = sg.part
	if best != "":
		part_clicked.emit(best)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 0.001 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)
