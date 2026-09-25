@tool
extends EditorPlugin
## Registra la scheda "NPC" (accanto a 2D, 3D, Script) con il creatore di NPC.
## Aprire una NPCDefinition (.tres) dal FileSystem la carica nel creatore.
## Autotest dell'interfaccia (serve l'editor, anche senza finestra):
##   NPC_CREATOR_SELFTEST=1 godot --headless --editor --path .
## Con NPC_CREATOR_SHOT=/percorso.png (e un display) salva anche uno screenshot.

const CreatorPanel := preload("res://addons/npc_creator/creator_panel.gd")

var panel: CreatorPanel


func _enter_tree() -> void:
	panel = CreatorPanel.new()
	panel.plugin = self
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.filesystem_changed.connect(NPCLibrary.invalidate)
	if OS.get_environment("NPC_CREATOR_SELFTEST") != "":
		_selftest.call_deferred()


func _exit_tree() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null and fs.filesystem_changed.is_connected(NPCLibrary.invalidate):
		fs.filesystem_changed.disconnect(NPCLibrary.invalidate)
	if is_instance_valid(panel):
		panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = visible


func _get_plugin_name() -> String:
	return "NPC"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"Skeleton3D", &"EditorIcons")


func _handles(object: Object) -> bool:
	return object is NPCDefinition


func _edit(object: Object) -> void:
	if object is NPCDefinition and is_instance_valid(panel):
		panel.open_definition(object)


## Chiudendo l'editor con un NPC modificato, Godot chiede se salvarlo.
func _get_unsaved_status(for_scene: String) -> String:
	if for_scene == "" and is_instance_valid(panel) and panel.dirty and panel.def != null:
		return "Salvare le modifiche all'NPC «%s»?" % panel.def.display_name
	return ""


## Ctrl+S, avvio del gioco, chiusura con salvataggio: salva anche l'NPC aperto.
func _save_external_data() -> void:
	if is_instance_valid(panel) and panel.dirty and panel.def != null:
		panel.save_quietly()


# --- autotest dell'interfaccia -----------------------------------------------------------
func _scene_marked_unsaved() -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return false
	var ur := get_undo_redo()
	var id := ur.get_object_history_id(root)
	return ur.get_history_undo_redo(id).get_history_count() > 0
var _ok := 0
var _fail := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		_ok += 1
		print("OK:   ", what)
	else:
		_fail += 1
		print("FAIL: ", what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _selftest() -> void:
	await _frames(10)
	get_tree().create_timer(120.0).timeout.connect(func():
		print("FAIL: timeout dell'autotest del creatore")
		get_tree().quit(2))
	EditorInterface.set_main_screen_editor("NPC")
	await _frames(3)
	var p := panel
	_check(p.visible, "la scheda NPC si apre")
	p.new_npc(NPCDefinition.Archetype.GUARDIA, 42)
	await _frames(3)
	_check(p.def != null and p.def.parts.size() == 11, "nuova guardia casuale con 11 parti")
	var body := p.preview.body
	_check(body.skeleton != null and body.skeleton.get_bone_count() == NPCRig.BONES.size(), "anteprima: scheletro di %d ossa" % NPCRig.BONES.size())
	_check(body.mesh_instance != null and body.mesh_instance.mesh.get_surface_count() == 1 and body.stats.triangles > 300,
		"anteprima: una sola superficie (%d triangoli)" % body.stats.triangles)
	var ur := get_undo_redo()
	var hist := ur.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var h0 := p.def.height
	p._set_prop(p.def, "height", 1.95)
	_check(is_equal_approx(p.def.height, 1.95) and p.dirty, "slider altezza applicato")
	hist.undo()
	_check(is_equal_approx(p.def.height, h0), "Ctrl+Z ripristina l'altezza")
	hist.redo()
	_check(is_equal_approx(p.def.height, 1.95), "Ctrl+Shift+Z la rimette")
	var name0 := p.def.display_name
	var torso0 := p.def.get_part("torace").thickness
	p.randomize_appearance(777)
	_check(p.def.random_seed == 777 and p.def.display_name == name0, "Casuale con seme (il nome resta)")
	hist.undo()
	_check(p.def.random_seed != 777 and is_equal_approx(p.def.get_part("torace").thickness, torso0), "Ctrl+Z annulla il Casuale")
	p.tabs.current_tab = 1
	p.select_part("testa", true)
	await _frames(2)
	_check(p.shape_inspector.get_edited_object() == p.def.get_part("testa").shape, "l'Inspector integrato mostra la forma della testa")
	p._make_unique()
	_check(not NPCDefinition.is_library_shape(p.def.get_part("testa").shape), "Rendi unica")
	var sec := SegmentShape.symmetric_section([1.0, 1.1, 1.0, 1.2, 0.9])
	p._on_section_committed(PackedFloat32Array(), sec)
	_check(p.def.get_part("testa").shape.section.size() == 8, "sezione della testa modificata")
	var tris0 := body.stats.triangles
	p._set_prop(p.def.get_part("testa").shape, "sides", 10)
	await _frames(3)
	_check(p.preview.body.stats.triangles > tris0, "più lati = più triangoli nell'anteprima (%d → %d)" % [tris0, p.preview.body.stats.triangles])
	var n_acc := p.def.attachments.size()
	for i in p.acc_add_opt.item_count:
		if p.acc_add_opt.get_item_text(i) == "cuffia":
			p.acc_add_opt.select(i)
	p._add_accessory()
	_check(p.def.attachments.size() == n_acc + 1, "accessorio aggiunto")
	# clic sull'anteprima: la testa è in alto al centro
	await _frames(2)
	var picked := [""]
	var cb := func(part): picked[0] = part
	p.preview.part_clicked.connect(cb)
	var cam := p.preview.camera
	var head_pos := body.skeleton.global_transform * body.skeleton.get_bone_global_pose(body.bone_index("head")).origin + Vector3(0, 0.08, 0)
	p.preview._pick(cam.unproject_position(head_pos) * p.preview.stretch_shrink)
	_check(picked[0] == "testa", "clic sulla testa nell'anteprima seleziona la testa (%s)" % picked[0])
	var path := "user://npc_selftest.tres"
	_check(p.save_to(path) == OK and not p.dirty, "salvataggio")
	var back: NPCDefinition = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(back != null and back.attachments.size() == p.def.attachments.size()
		and back.get_part("testa").shape.section.size() == 8 and is_equal_approx(back.height, 1.95),
		"ricaricato identico (forma unica inclusa)")
	_check(back.get_part("torace").shape.resource_path.begins_with(NPCLibrary.SHAPES_DIR), "le forme di libreria restano riferimenti ai file")
	# due parti diverse: due passi di annulla distinti
	var pa := p.def.get_part("braccio")
	var pb := p.def.get_part("coscia")
	var ta := pa.thickness
	p._set_prop(pa, "thickness", 1.3)
	p._set_prop(pb, "thickness", 1.4)
	hist.undo()
	_check(is_equal_approx(pa.thickness, 1.3) and not is_equal_approx(pb.thickness, 1.4), "modifiche a parti diverse non si fondono nell'annulla")
	hist.undo()
	_check(is_equal_approx(pa.thickness, ta), "…e si annullano una alla volta")
	p.dirty = false
	var ruiz: NPCDefinition = load(NPCLibrary.CHARACTERS_DIR.path_join("ruiz.tres"))
	p.open_definition(ruiz)
	await _frames(3)
	_check(p.def == ruiz and p.name_edit.text == "Ag. Ruiz" and p.keycard_id_edit.text == "sicurezza", "apre ruiz.tres (nome e tessera nei campi)")
	var h_disk := ruiz.height
	p._set_prop(ruiz, "height", h_disk + 0.2)
	p.revert_unsaved()
	_check(is_equal_approx(ruiz.height, h_disk) and not p.dirty, "Scarta riporta ruiz.tres com'è su disco")
	p._set_prop(ruiz, "height", h_disk + 0.1)
	p.revert_unsaved()
	var hale: NPCDefinition = load(NPCLibrary.CHARACTERS_DIR.path_join("hale.tres"))
	p.open_definition(hale)
	var hh := hale.height
	hist.undo()
	_check(is_equal_approx(hale.height, hh) and is_equal_approx(ruiz.height, h_disk) and not p.dirty, "l'annulla di un NPC chiuso non tocca quello aperto")
	p.open_definition(ruiz)
	await _frames(2)
	p.select_part("torace", true)
	var bg0 := p.preview.env.background_color
	p.bg_opt.select(2)
	p.bg_opt.item_selected.emit(2)
	_check(p.preview.env.background_color.is_equal_approx(p.Preview.BACKGROUNDS[2][1]) and p.bg_color.color.is_equal_approx(p.Preview.BACKGROUNDS[2][1]), "sfondo dell'anteprima: preset Chiaro")
	p.bg_color.color_changed.emit(Color(0.1, 0.4, 0.8))
	_check(p.preview.env.background_color.is_equal_approx(Color(0.1, 0.4, 0.8)) and p.bg_opt.selected == p.Preview.BACKGROUNDS.size(), "sfondo personalizzato dal selettore")
	_check((EditorInterface.get_editor_settings().get_project_metadata("npc_creator", "preview_bg", Color.BLACK) as Color).is_equal_approx(Color(0.1, 0.4, 0.8)), "lo sfondo scelto resta memorizzato")
	var shot_bg := OS.get_environment("NPC_CREATOR_SHOT") != ""
	p.set_preview_background(p.Preview.BACKGROUNDS[2][1] if shot_bg else bg0)
	await _frames(5)
	_check(not _scene_marked_unsaved(), "modificare un NPC non marca come modificata la scena aperta")
	var shot := OS.get_environment("NPC_CREATOR_SHOT")
	if shot != "" and DisplayServer.get_name() != "headless":
		# una schermata per scheda: <nome>_0.png ... <nome>_4.png
		for t in p.tabs.get_tab_count():
			p.tabs.current_tab = t
			if t == 2:
				p._select_acc(1)
			await get_tree().create_timer(0.6).timeout
			await RenderingServer.frame_post_draw
			var f := shot.get_basename() + "_%d.png" % t
			EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(f)
			print("screenshot: ", f)
	p.dirty = false
	print("RISULTATO CREATORE NPC: %d ok, %d fail" % [_ok, _fail])
	get_tree().quit(0 if _fail == 0 else 1)
