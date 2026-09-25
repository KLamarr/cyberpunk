@tool
extends RefCounted
## Autotest del creatore di NPC, dentro l'editor (anche senza finestra):
##   NPC_CREATOR_SELFTEST=1 godot --headless --editor --path .
## Con NPC_CREATOR_SHOT=/percorso.png (e un display) salva anche uno screenshot per scheda.
## Scrive solo in user://npc_selftest/ (forme e NPC di prova) e lo cancella alla fine: i
## file del progetto non vengono toccati, e il test lo verifica.

const TMP := "user://npc_selftest"

var plugin: EditorPlugin
var p   # il pannello del creatore
var ur: EditorUndoRedoManager
var hist: UndoRedo
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
		await plugin.get_tree().process_frame


func _scene_marked_unsaved() -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return false
	var id := ur.get_object_history_id(root)
	return ur.get_history_undo_redo(id).get_history_count() > 0


## Impronta dei file del progetto che il creatore potrebbe toccare per sbaglio.
func _project_files_hash() -> Dictionary:
	var out := {}
	for dir in [NPCLibrary.SHAPES_DIR, NPCLibrary.CHARACTERS_DIR, "res://levels/palestra"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".tres") or f.ends_with(".tscn"):
				var path: String = dir.path_join(f)
				out[path] = FileAccess.get_md5(path)
	return out


func _disk(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func run() -> void:
	await _frames(10)
	plugin.get_tree().create_timer(240.0).timeout.connect(func():
		print("FAIL: timeout dell'autotest del creatore")
		plugin.get_tree().quit(2))
	DirAccess.make_dir_recursive_absolute(TMP)
	# una scena aperta, come quando si lavora: le modifiche agli NPC non devono toccarla
	EditorInterface.open_scene_from_path("res://levels/palestra/palestra.tscn")
	await _frames(10)
	_check(EditorInterface.get_edited_scene_root() != null, "scena aperta per il test (palestra)")
	var files0 := _project_files_hash()
	EditorInterface.save_scene()
	await _frames(5)
	_check(_project_files_hash() == files0, "salvare la scena non riscrive i file degli NPC né la scena")
	EditorInterface.set_main_screen_editor("NPC")
	await _frames(3)
	p = plugin.panel
	ur = plugin.get_undo_redo()
	hist = ur.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	_check(p.visible, "la scheda NPC si apre")

	await _test_basics()
	await _test_history()
	await _test_editor_save()
	await _setup_temp_library()
	await _test_make_unique()
	await _test_save_shape_to_library()
	await _test_save_as()
	await _test_discard()
	await _test_open_cancel_and_save()
	await _test_existing_characters()
	await _test_background()
	_check(not _scene_marked_unsaved(), "modificare gli NPC non marca come modificata la scena aperta")

	var shot := OS.get_environment("NPC_CREATOR_SHOT")
	if shot != "" and DisplayServer.get_name() != "headless":
		p.set_preview_background(p.Preview.BACKGROUNDS[2][1])
		for t in p.tabs.get_tab_count():
			p.tabs.current_tab = t
			if t == 2:
				p._select_acc(1)
			await plugin.get_tree().create_timer(0.6).timeout
			await RenderingServer.frame_post_draw
			var f := shot.get_basename() + "_%d.png" % t
			EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(f)
			print("screenshot: ", f)

	p.revert_unsaved()
	_check(_project_files_hash() == files0, "nessun file del progetto modificato dal test")
	_cleanup(files0)
	print("RISULTATO CREATORE NPC: %d ok, %d fail" % [_ok, _fail])
	plugin.get_tree().quit(0 if _fail == 0 else 1)


func _cleanup(files0: Dictionary) -> void:
	for f in DirAccess.get_files_at(TMP):
		DirAccess.remove_absolute(TMP.path_join(f))
	DirAccess.remove_absolute(TMP)
	# se un salvataggio automatico sbagliato avesse creato un personaggio, lo si toglie
	for f in DirAccess.get_files_at(NPCLibrary.CHARACTERS_DIR):
		var path := NPCLibrary.CHARACTERS_DIR.path_join(f)
		if f.ends_with(".tres") and not files0.has(path):
			DirAccess.remove_absolute(path)


# --- controlli, annulla, anteprima --------------------------------------------------------
func _test_basics() -> void:
	p.new_npc(NPCDefinition.Archetype.GUARDIA, 42)
	await _frames(3)
	_check(p.def != null and p.def.parts.size() == 11, "nuova guardia casuale con 11 parti")
	var body = p.preview.body
	_check(body.skeleton != null and body.skeleton.get_bone_count() == NPCRig.BONES.size(), "anteprima: scheletro di %d ossa" % NPCRig.BONES.size())
	_check(body.mesh_instance != null and body.mesh_instance.mesh.get_surface_count() == 1 and body.stats.triangles > 300,
		"anteprima: una sola superficie (%d triangoli)" % body.stats.triangles)
	var h0: float = p.def.height
	p._set_prop(p.def, "height", 1.95)
	_check(is_equal_approx(p.def.height, 1.95) and p.dirty, "slider altezza applicato")
	hist.undo()
	_check(is_equal_approx(p.def.height, h0), "Ctrl+Z ripristina l'altezza")
	hist.redo()
	_check(is_equal_approx(p.def.height, 1.95), "Ctrl+Shift+Z la rimette")
	var name0: String = p.def.display_name
	var torso0: float = p.def.get_part("torace").thickness
	p.randomize_appearance(777)
	_check(p.def.random_seed == 777 and p.def.display_name == name0, "Casuale con seme (il nome resta)")
	hist.undo()
	_check(p.def.random_seed != 777 and is_equal_approx(p.def.get_part("torace").thickness, torso0), "Ctrl+Z annulla il Casuale")
	# forma di libreria: bloccata finché non si chiede di modificare la libreria
	p.tabs.current_tab = 1
	p.select_part("testa", true)
	await _frames(2)
	var lib: SegmentShape = p.def.get_part("testa").shape
	_check(NPCDefinition.is_library_shape(lib) and p.shape_inspector.get_edited_object() == null and not p.section_ed.editable,
		"forma di libreria bloccata: niente Inspector integrato, sezione non modificabile")
	var sec0 := lib.section
	p._on_section_committed(PackedFloat32Array(), SegmentShape.symmetric_section([1.0, 1.3, 1.0, 1.3, 1.0]))
	_check(lib.section == sec0 and p._dirty_shapes.is_empty(), "la sezione di una forma bloccata non cambia")
	p._make_unique()
	var uniq: SegmentShape = p.def.get_part("testa").shape
	_check(not NPCDefinition.is_library_shape(uniq), "Rendi unica")
	await _frames(2)
	_check(p.shape_inspector.get_edited_object() == uniq and p.section_ed.editable, "la forma unica si modifica nell'Inspector integrato")
	p._on_section_committed(PackedFloat32Array(), SegmentShape.symmetric_section([1.0, 1.1, 1.0, 1.2, 0.9]))
	_check(uniq.section.size() == 8, "sezione della testa modificata")
	var tris0: int = body.stats.triangles
	p._set_prop(uniq, "sides", 10)
	await _frames(3)
	_check(p.preview.body.stats.triangles > tris0, "più lati = più triangoli nell'anteprima (%d → %d)" % [tris0, p.preview.body.stats.triangles])
	var n_acc: int = p.def.attachments.size()
	for i in p.acc_add_opt.item_count:
		if p.acc_add_opt.get_item_text(i) == "cuffia":
			p.acc_add_opt.select(i)
	p._add_accessory()
	_check(p.def.attachments.size() == n_acc + 1, "accessorio aggiunto")
	var acc: NPCAttachment = p.def.attachments[-1]
	var ro := false
	for prop in acc.get_property_list():
		if prop.name == "shape":
			ro = prop.usage & PROPERTY_USAGE_READ_ONLY != 0
	_check(ro, "la forma di libreria di un accessorio è in sola lettura nell'Inspector")
	# clic sull'anteprima: la testa è in alto al centro
	await _frames(2)
	var picked := [""]
	var cb := func(part): picked[0] = part
	p.preview.part_clicked.connect(cb)
	var cam: Camera3D = p.preview.camera
	var head_pos: Vector3 = body.skeleton.global_transform * body.skeleton.get_bone_global_pose(body.bone_index("head")).origin + Vector3(0, 0.08, 0)
	p.preview._pick(cam.unproject_position(head_pos) * p.preview.stretch_shrink)
	_check(picked[0] == "testa", "clic sulla testa nell'anteprima seleziona la testa (%s)" % picked[0])
	p.preview.part_clicked.disconnect(cb)
	# due parti diverse: due passi di annulla distinti
	var pa: NPCPart = p.def.get_part("braccio")
	var pb: NPCPart = p.def.get_part("coscia")
	var ta := pa.thickness
	p._set_prop(pa, "thickness", 1.3)
	p._set_prop(pb, "thickness", 1.4)
	hist.undo()
	_check(is_equal_approx(pa.thickness, 1.3) and not is_equal_approx(pb.thickness, 1.4), "modifiche a parti diverse non si fondono nell'annulla")
	hist.undo()
	_check(is_equal_approx(pa.thickness, ta), "…e si annullano una alla volta")


## Le modifiche fatte negli Inspector integrati vanno nella cronologia globale, anche per
## un NPC mai salvato (le sue parti non hanno ancora un file).
func _test_history() -> void:
	var global_all := true
	for k in p.def.parts:
		global_all = global_all and ur.get_object_history_id(p.def.parts[k]) == EditorUndoRedoManager.GLOBAL_HISTORY
	for a in p.def.attachments:
		global_all = global_all and ur.get_object_history_id(a) == EditorUndoRedoManager.GLOBAL_HISTORY
	var uniq: SegmentShape = p.def.get_part("testa").shape
	global_all = global_all and ur.get_object_history_id(uniq) == EditorUndoRedoManager.GLOBAL_HISTORY
	global_all = global_all and ur.get_object_history_id(uniq.width_curve) == EditorUndoRedoManager.GLOBAL_HISTORY
	_check(global_all, "parti, accessori e forme uniche di un NPC nuovo nella cronologia globale")
	# una modifica come la fa l'Inspector integrato (azione senza contesto)
	var acc: NPCAttachment = p.def.attachments[-1]
	var old := acc.length
	ur.create_action("Imposta length")
	ur.add_do_property(acc, "length", 0.3)
	ur.add_undo_property(acc, "length", old)
	ur.commit_action()
	_check(is_equal_approx(acc.length, 0.3) and not _scene_marked_unsaved(), "modifica dall'Inspector integrato: la scena aperta resta intatta")


## Ctrl+S dell'editor da un'altra scheda: un NPC nuovo non crea file da solo.
func _test_editor_save() -> void:
	var before := DirAccess.get_files_at(NPCLibrary.CHARACTERS_DIR)
	_check(p.dirty and p.def_path == "", "NPC nuovo non salvato")
	plugin._save_external_data()
	_check(DirAccess.get_files_at(NPCLibrary.CHARACTERS_DIR) == before and p.dirty, "Ctrl+S non crea un personaggio senza chiedere")
	var path := TMP.path_join("nuovo.tres")
	_check(p.save_to(path) == OK and not p.dirty and p.def_path == path, "primo salvataggio con nome")
	var back: NPCDefinition = _disk(path)
	_check(back != null and back.attachments.size() == p.def.attachments.size()
		and back.get_part("testa").shape.section.size() == 8 and is_equal_approx(back.height, 1.95),
		"ricaricato identico (forma unica inclusa)")
	_check(back.get_part("torace").shape.resource_path.begins_with(NPCLibrary.SHAPES_DIR), "le forme di libreria restano riferimenti ai file")
	var ids_ok := true
	for k in p.def.parts:
		ids_ok = ids_ok and p.def.parts[k].resource_path != "" and ur.get_object_history_id(p.def.parts[k]) == EditorUndoRedoManager.GLOBAL_HISTORY
	_check(ids_ok, "dopo il salvataggio le parti restano nella cronologia globale")
	p._set_prop(p.def, "height", 1.7)
	plugin._save_external_data()
	_check(not p.dirty and is_equal_approx((_disk(path) as NPCDefinition).height, 1.7), "Ctrl+S salva un NPC che ha già il suo file")


# --- libreria di prova in user:// ------------------------------------------------------
var testa_path := TMP.path_join("testa_prova.tres")
var torace_path := TMP.path_join("torace_prova.tres")
var prova_path := TMP.path_join("prova.tres")


func _save_copy(sh: SegmentShape, path: String) -> SegmentShape:
	var c: SegmentShape = sh.duplicate(true)
	c.take_over_path(path)
	ResourceSaver.save(c, path, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
	return c


func _setup_temp_library() -> void:
	var ruiz: NPCDefinition = load(NPCLibrary.CHARACTERS_DIR.path_join("ruiz.tres"))
	var testa := _save_copy(ruiz.get_part("testa").shape, testa_path)
	var torace := _save_copy(ruiz.get_part("torace").shape, torace_path)
	var d := ruiz.clone()
	d.display_name = "Prova"
	d.get_part("testa").shape = testa
	d.get_part("torace").shape = torace
	d.take_over_path(prova_path)
	ResourceSaver.save(d, prova_path, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
	p.revert_unsaved()
	p.open_definition(load(prova_path))
	await _frames(2)
	_check(p.def_path == prova_path and not p.dirty and NPCDefinition.is_library_shape(p.def.get_part("testa").shape),
		"NPC di prova con forme di libreria di prova")


## Bug: «Rendi unica» salvava comunque le modifiche nel file di libreria condiviso.
func _test_make_unique() -> void:
	p.select_part("testa", false)
	var lib: SegmentShape = p.def.get_part("testa").shape
	p.edit_library = true
	p._set_prop(lib, "smooth", false)      # valore diverso dal predefinito
	p._set_prop(lib, "cap_start", true)
	_check(p._dirty_shapes.has(testa_path), "modifica alla forma di libreria registrata")
	p.edit_library = false
	p._make_unique()
	var uniq: SegmentShape = p.def.get_part("testa").shape
	_check(not uniq.smooth and uniq.cap_start, "la copia unica tiene le modifiche")
	_check(lib.smooth and not lib.cap_start and not p._dirty_shapes.has(testa_path), "la forma di libreria torna com'era in memoria")
	p.save()
	var disk: SegmentShape = _disk(testa_path)
	_check(disk.smooth and not disk.cap_start, "Rendi unica + Salva: il file di libreria non cambia")


## Bug: «Salva in libreria…» salvava le modifiche anche nella forma di partenza.
func _test_save_shape_to_library() -> void:
	p.select_part("torace", false)
	var lib: SegmentShape = p.def.get_part("torace").shape
	var r0 := lib.radius_x
	p.edit_library = true
	p._set_prop(lib, "radius_x", 0.3)
	var new_path := TMP.path_join("torace_nuovo.tres")
	p.save_shape_to_library(new_path)
	p.edit_library = false
	_check(p.def.get_part("torace").shape.resource_path == new_path and is_equal_approx(p.def.get_part("torace").shape.radius_x, 0.3), "la parte usa la nuova forma")
	p.save()
	_check(is_equal_approx((_disk(torace_path) as SegmentShape).radius_x, r0) and is_equal_approx(lib.radius_x, r0), "la forma di partenza resta com'era (su disco e in memoria)")
	_check(is_equal_approx((_disk(new_path) as SegmentShape).radius_x, 0.3), "la nuova forma è nel suo file")


## Bug: dopo «Salva come» originale e copia condividevano parti e accessori.
func _test_save_as() -> void:
	var orig: NPCDefinition = p.def
	var h0 := orig.height
	p._set_prop(orig, "height", h0 + 0.1)
	var elite_path := TMP.path_join("prova_elite.tres")
	p._dialog_mode = "save"
	p._on_file_selected(elite_path)
	var copy: NPCDefinition = p.def
	_check(copy != orig and copy.resource_path == elite_path and orig.resource_path == prova_path, "Salva come: il documento aperto è la copia, l'originale tiene il suo file")
	_check(is_equal_approx(copy.height, h0 + 0.1) and is_equal_approx(orig.height, h0), "le modifiche vanno nella copia, l'originale resta com'è su disco")
	var shared := false
	for i in orig.attachments.size():
		shared = shared or orig.attachments[i] == copy.attachments[i]
	for k in orig.parts:
		shared = shared or orig.parts[k] == copy.parts[k]
	_check(not shared, "originale e copia non condividono parti né accessori")
	p.open_definition(load(prova_path))
	await _frames(2)
	_check(p.def == orig, "riaperto l'originale")
	var casco_len: float = copy.attachments[0].length
	p._set_prop(orig.attachments[0], "length", casco_len + 0.4)
	_check(is_equal_approx(copy.attachments[0].length, casco_len), "modificare l'originale non cambia la copia")
	p.revert_unsaved()


## Bug: «Scarta» non riportava le proprietà al valore predefinito (non scritte nel .tres).
func _test_discard() -> void:
	var d: NPCDefinition = p.def
	var disk: NPCDefinition = _disk(prova_path)
	var lib: SegmentShape = d.get_part("testa").shape if NPCDefinition.is_library_shape(d.get_part("testa").shape) else null
	if lib == null:
		d.get_part("testa").shape = load(testa_path)
		p.save()
		lib = d.get_part("testa").shape
	var lib_disk: SegmentShape = _disk(testa_path)
	var files_before := FileAccess.get_md5(prova_path)
	p._set_prop(d, "max_health", 250.0)
	p._set_prop(d, "investigates_noises", false)
	p._set_prop(d, "faction", "ribelli")
	p._set_prop(d.attachments[0], "enabled", false)
	p._set_prop(d.get_part("bacino"), "thickness", 1.6)
	p.edit_library = true
	p._set_prop(lib, "extend_start", 0.4)
	p._set_prop(lib, "smooth", false)
	p.edit_library = false
	p.revert_unsaved()
	_check(is_equal_approx(d.max_health, disk.max_health) and d.investigates_noises == disk.investigates_noises and d.faction == disk.faction,
		"Scarta ripristina i valori predefiniti della definizione")
	_check(d.attachments[0].enabled == disk.attachments[0].enabled and is_equal_approx(d.get_part("bacino").thickness, disk.get_part("bacino").thickness),
		"Scarta ripristina accessori e parti")
	_check(is_equal_approx(lib.extend_start, lib_disk.extend_start) and lib.smooth == lib_disk.smooth, "Scarta ripristina la forma di libreria")
	_check(not p.dirty and p._dirty_shapes.is_empty(), "dopo Scarta niente da salvare")
	plugin._save_external_data()
	_check(FileAccess.get_md5(prova_path) == files_before, "le modifiche scartate non finiscono su disco col Ctrl+S successivo")
	# Ctrl+S con una forma condivisa modificata: non salva senza chiedere
	p.edit_library = true
	p._set_prop(lib, "rings", lib.rings + 1)
	p.edit_library = false
	plugin._save_external_data()
	_check(p.dirty and (_disk(testa_path) as SegmentShape).rings == lib_disk.rings, "Ctrl+S non salva da solo le forme condivise")
	p.revert_unsaved()


## «Apri…» annullato non perde le modifiche; «Salva» nella conferma salva e prosegue.
func _test_open_cancel_and_save() -> void:
	var d: NPCDefinition = p.def
	var h := d.height + 0.05
	p._set_prop(d, "height", h)
	p._on_open_pressed()
	_check(p.file_dialog.visible and not p.confirm.visible, "Apri: prima si sceglie il file")
	p.file_dialog.hide()
	p.file_dialog.canceled.emit()
	_check(p.def == d and p.dirty and is_equal_approx(d.height, h), "annullando la scelta del file le modifiche restano")
	p._dialog_mode = "open"
	p._on_file_selected(TMP.path_join("prova_elite.tres"))
	_check(p.confirm.visible, "con modifiche non salvate chiede Salva / Scarta / Annulla")
	p.confirm.hide()
	p.confirm.canceled.emit()
	_check(p.def == d and p.dirty, "Annulla: resta l'NPC di prima, con le modifiche")
	p._on_file_selected(TMP.path_join("prova_elite.tres"))
	p.confirm.custom_action.emit("save")
	_check(p.def != d and p.def.resource_path.ends_with("prova_elite.tres"), "Salva: salva e apre l'altro NPC")
	_check(is_equal_approx((_disk(prova_path) as NPCDefinition).height, h), "…e le modifiche sono su disco")


func _test_existing_characters() -> void:
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
	_check(p.lib_note.text.contains("ruiz"), "la nota della forma condivisa dice quali personaggi la usano")


## Lo sfondo scelto si memorizza alla chiusura del selettore, non a ogni movimento.
func _test_background() -> void:
	var settings := EditorInterface.get_editor_settings()
	var bg0: Color = p.preview.env.background_color
	p.bg_opt.select(2)
	p.bg_opt.item_selected.emit(2)
	_check(p.preview.env.background_color.is_equal_approx(p.Preview.BACKGROUNDS[2][1]) and p.bg_color.color.is_equal_approx(p.Preview.BACKGROUNDS[2][1]), "sfondo dell'anteprima: preset Chiaro")
	var stored: Color = settings.get_project_metadata("npc_creator", "preview_bg", Color.BLACK)
	p.bg_color.color = Color(0.1, 0.4, 0.8)
	p.bg_color.color_changed.emit(Color(0.1, 0.4, 0.8))
	_check(p.preview.env.background_color.is_equal_approx(Color(0.1, 0.4, 0.8)) and p.bg_opt.selected == p.Preview.BACKGROUNDS.size(), "sfondo personalizzato dal selettore")
	_check((settings.get_project_metadata("npc_creator", "preview_bg", Color.BLACK) as Color).is_equal_approx(stored), "trascinando il colore la configurazione non viene riscritta")
	p.bg_color.popup_closed.emit()
	_check((settings.get_project_metadata("npc_creator", "preview_bg", Color.BLACK) as Color).is_equal_approx(Color(0.1, 0.4, 0.8)), "chiuso il selettore, lo sfondo resta memorizzato")
	p.set_preview_background(bg0)
