extends SceneTree
## Fotografa una fila di NPC generati (verifica visiva del generatore e della libreria).
##   xvfb-run godot --path . --script tools/npc_lineup.gd -- --out=/percorso/lineup.png
## Opzioni: --retro (640x360 + dithering come in gioco), --pose=cammina|corri|mira|a_terra,
##          --chars (le definizioni salvate in assets/npc/characters invece dei casuali),
##          --yaw=gradi (rotazione dei personaggi), --dist=metri (distanza della camera).

const POST := preload("res://shaders/retro_post.gdshader")

var out := "user://npc_lineup.png"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run.call_deferred()


func _arg(prefix: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return def


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var retro := "--retro" in args
	var parent: Node = root
	if retro:
		var cont := SubViewportContainer.new()
		cont.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var pm := ShaderMaterial.new()
		pm.shader = POST
		cont.material = pm
		root.add_child(cont)
		var sv := SubViewport.new()
		cont.add_child(sv)
		cont.stretch = true
		cont.stretch_shrink = 2
		cont.position = Vector2.ZERO
		cont.size = Vector2(root.size)
		parent = sv
	var world := Node3D.new()
	parent.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.33, 0.38)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 0.9
	world.add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.8, 2.2)
	lamp.omni_range = 9.0
	lamp.light_energy = 1.4
	lamp.light_color = Color(0.85, 0.92, 1.0)
	world.add_child(lamp)
	var floor_mi := MeshInstance3D.new()
	var pm2 := PlaneMesh.new()
	pm2.size = Vector2(30, 30)
	floor_mi.mesh = pm2
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = load("res://assets/textures/floor_tiles.png")
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	fm.uv1_scale = Vector3(15, 15, 1)
	floor_mi.material_override = fm
	world.add_child(floor_mi)

	var defs: Array[NPCDefinition] = []
	if "--chars" in args:
		var dir := DirAccess.open(NPCLibrary.CHARACTERS_DIR)
		var files := dir.get_files() if dir else PackedStringArray()
		files.sort()
		for f in files:
			if f.ends_with(".tres"):
				defs.append(load(NPCLibrary.CHARACTERS_DIR.path_join(f)))
	else:
		defs.append(NPCLibrary.preset(NPCDefinition.Archetype.GUARDIA))
		for s in [11, 12, 13]:
			defs.append(NPCLibrary.random_npc(NPCDefinition.Archetype.GUARDIA, s))
		for a in [NPCDefinition.Archetype.TECNICO, NPCDefinition.Archetype.SCIENZIATO, NPCDefinition.Archetype.DIRIGENTE, NPCDefinition.Archetype.CIVILE]:
			defs.append(NPCLibrary.random_npc(a, 100 + a))
	var pose_name := _arg("--pose=", "riposo")
	var poses := {"riposo": NPCBody.Pose.RIPOSO, "cammina": NPCBody.Pose.CAMMINA, "corri": NPCBody.Pose.CORRI, "mira": NPCBody.Pose.MIRA, "a_terra": NPCBody.Pose.A_TERRA}
	var yaw := float(_arg("--yaw=", "180"))
	var spacing := 0.85
	var bodies: Array[NPCBody] = []
	for i in defs.size():
		var b := NPCBody.new()
		b.definition = defs[i]
		b.position = Vector3((i - (defs.size() - 1) * 0.5) * spacing, 0, 0)
		b.rotation.y = deg_to_rad(yaw)
		b.preview_pose = poses.get(pose_name, NPCBody.Pose.RIPOSO)
		b.preview_animate = true
		world.add_child(b)
		bodies.append(b)
		var st := NPCBodyBuilder.Stats.new()
		NPCBodyBuilder.build_mesh(defs[i], {}, st)
		print("%-16s h %.2f  vertici %4d  triangoli %4d  segmenti %2d" % [defs[i].display_name, defs[i].height, st.vertices, st.triangles, st.segments])
	var cam := Camera3D.new()
	var dist := float(_arg("--dist=", str(1.6 + defs.size() * 0.55)))
	cam.position = Vector3(0, 1.25, dist)
	cam.fov = 38
	world.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true
	for f in 40:
		for b in bodies:
			b.preview_tick(1.0 / 60.0 * (0.27 if pose_name in ["cammina", "corri"] else 1.0))
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("salvato: ", out)
	quit()
