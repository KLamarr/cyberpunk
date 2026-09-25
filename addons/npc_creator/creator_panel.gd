@tool
extends VBoxContainer
## Creatore di NPC: la scheda "NPC" nella barra in alto dell'editor.
## A sinistra le schede con i controlli (identità e corpo, forme, accessori, gameplay,
## inventario e voce), a destra l'anteprima 3D con il filtro retro del gioco.
## Ogni modifica passa dall'annulla/ripeti dell'editor (Ctrl+Z). Le definizioni si
## salvano come .tres in assets/npc/characters; le forme in assets/npc/segments.

const Preview := preload("res://addons/npc_creator/npc_preview.gd")
const SectionEditor := preload("res://addons/npc_creator/section_editor.gd")
const PART_LABELS := {
	"testa": "Testa", "collo": "Collo", "torace": "Torace", "addome": "Addome", "bacino": "Bacino",
	"braccio": "Braccio", "avambraccio": "Avambraccio", "mano": "Mano", "coscia": "Coscia",
	"stinco": "Stinco", "piede": "Piede",
}
const POSES: Array[String] = ["Riposo", "Cammina", "Corri", "Mira", "A terra"]

var plugin: EditorPlugin
var def: NPCDefinition
var dirty := false
## Il file dell'NPC aperto ("" se non è mai stato salvato): è sempre il percorso della
## definizione stessa, così non può restare indietro rispetto a lei.
var def_path: String:
	get:
		if def == null or def.resource_path == "" or def.resource_path.contains("::"):
			return ""
		return def.resource_path
## Le forme di libreria (condivise) si modificano solo dopo averlo chiesto esplicitamente.
var edit_library := false:
	set(v):
		edit_library = v
		NPCAttachment.library_locked = not v
		if lib_edit_check != null:
			lib_edit_check.set_pressed_no_signal(v)
		if def != null:
			acc_inspector.edit(null)
			_refresh_part_ui()
			_fill_acc_ui()

var preview: Preview
var tabs: TabContainer
var file_label: Label
var status_label: Label
var seed_spin: SpinBox
var name_edit: LineEdit
var arch_opt: OptionButton
var faction_edit: LineEdit
var keycard_id_edit: LineEdit
var keycard_name_edit: LineEdit
var barks_edit: TextEdit
var parts_list: ItemList
var shape_opt: OptionButton
var shape_b_opt: OptionButton
var morph_slider: EditorSpinSlider
var thick_slider: EditorSpinSlider
var lib_note: Label
var lib_edit_check: CheckButton
var ellipse_btn: Button
var section_ed: SectionEditor
var sym_check: CheckBox
var shape_inspector: EditorInspector
var acc_add_opt: OptionButton
var acc_list: ItemList
var acc_inspector: EditorInspector
var acc_note: Label
var pose_opt: OptionButton
var bg_opt: OptionButton
var bg_color: ColorPickerButton
var floor_check: CheckBox
var stats_label: Label
var file_dialog: EditorFileDialog
var confirm: ConfirmationDialog

var _ctrls := {}
var _colors: Array[ColorPickerButton] = []
var _selected_part := "torace"
var _selected_acc := -1
var _dialog_mode := ""
var _pending: Callable
var _after_save: Callable
var _quiet := 0
var _dirty_shapes := {}
## Modifiche a forme di libreria che l'NPC ha smesso di usare (Rendi unica, cambio forma,
## accessorio rimosso): la forma torna com'è su disco e le modifiche restano qui, pronte
## a tornare se l'annulla la rimette in uso.
var _released := {}
var _watched: Array[Resource] = []
var _refresh_queued := false
var _built := false


func _ready() -> void:
	if _built:
		return
	_built = true
	name = "NPCCreator"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_toolbar()
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(450, 0)
	tabs.size_flags_horizontal = Control.SIZE_FILL
	split.add_child(tabs)
	_build_body_tab()
	_build_shapes_tab()
	_build_acc_tab()
	_build_gameplay_tab()
	_build_inventory_tab()
	tabs.tab_changed.connect(_on_tab_changed)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	preview = Preview.new()
	preview.part_clicked.connect(_on_preview_part_clicked)
	right.add_child(preview)
	_build_preview_bar(right)
	file_dialog = EditorFileDialog.new()
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)
	file_dialog.canceled.connect(func(): _after_save = Callable())
	confirm = ConfirmationDialog.new()
	confirm.title = "Creatore di NPC"
	confirm.ok_button_text = "Scarta"
	confirm.cancel_button_text = "Annulla"
	confirm.add_button("Salva", true, "save")
	confirm.confirmed.connect(func():
		revert_unsaved()
		_run_pending())
	confirm.custom_action.connect(func(action):
		if action == "save":
			confirm.hide()
			_save_then(_pending)
			_pending = Callable())
	confirm.canceled.connect(func(): _pending = Callable())
	add_child(confirm)
	NPCAttachment.library_locked = not edit_library
	new_npc(NPCDefinition.Archetype.GUARDIA, 1)
	dirty = false
	_update_title()


func _process(delta: float) -> void:
	if is_visible_in_tree() and preview != null:
		preview.body.preview_tick(delta)


# --- costruzione dell'interfaccia --------------------------------------------------------
func _build_toolbar() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	var nuovo := MenuButton.new()
	nuovo.text = "Nuovo"
	nuovo.flat = false
	nuovo.tooltip_text = "Nuovo NPC casuale dell'archetipo scelto"
	var pm := nuovo.get_popup()
	for i in NPCLibrary.ARCH_LABELS.size():
		pm.add_item(NPCLibrary.ARCH_LABELS[i], i)
	pm.id_pressed.connect(func(id): _guard_discard(func(): new_npc(id, randi() % 100000)))
	bar.add_child(nuovo)
	_button(bar, "Apri…", _on_open_pressed, "Apri una definizione .tres")
	_button(bar, "Salva", save, "Salva la definizione (e le forme di libreria modificate)")
	_button(bar, "Salva come…", func(): _ask_save_path(), "Salva con un altro nome")
	_button(bar, "Duplica", _duplicate, "Copia modificabile di questo NPC, da salvare con un nuovo nome")
	bar.add_child(VSeparator.new())
	var l := Label.new()
	l.text = "Seme"
	bar.add_child(l)
	seed_spin = SpinBox.new()
	seed_spin.max_value = 999999
	seed_spin.tooltip_text = "Stesso seme = stesso aspetto (per l'archetipo scelto)"
	seed_spin.value_changed.connect(func(v): if not _syncing(): randomize_appearance(int(v)))
	bar.add_child(seed_spin)
	_button(bar, "Casuale", func(): randomize_appearance(randi() % 100000), "Rimescola proporzioni, forme, accessori e colori (i dati di gameplay restano)")
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	status_label = Label.new()
	status_label.modulate = Color(1, 1, 1, 0.6)
	bar.add_child(status_label)
	file_label = Label.new()
	bar.add_child(file_label)


func _build_body_tab() -> void:
	var v := _tab("Corpo")
	_header(v, "Identità")
	name_edit = _line(v, "Nome", "display_name")
	arch_opt = OptionButton.new()
	for a in NPCLibrary.ARCH_LABELS:
		arch_opt.add_item(a)
	arch_opt.tooltip_text = "Archetipo: decide cosa pesca il pulsante Casuale"
	arch_opt.item_selected.connect(func(i): _set_prop(def, "archetype", i))
	_row(v, "Archetipo", arch_opt)
	faction_edit = _line(v, "Fazione", "faction")
	_header(v, "Proporzioni")
	_spin(v, "height", "Altezza", 1.4, 2.2, 0.01, "m")
	_spin(v, "mass", "Corporatura", 0.7, 1.5, 0.01)
	_spin(v, "shoulders", "Spalle", 0.75, 1.35, 0.01)
	_spin(v, "hips", "Fianchi", 0.75, 1.35, 0.01)
	_spin(v, "arm_length", "Braccia", 0.8, 1.2, 0.01)
	_spin(v, "leg_length", "Gambe", 0.8, 1.2, 0.01)
	_spin(v, "head_size", "Testa", 0.8, 1.3, 0.01)
	_spin(v, "neck_length", "Collo", 0.6, 1.5, 0.01)
	_spin(v, "posture", "Postura (dritto ↔ curvo)", -1.0, 1.0, 0.01)
	_header(v, "Colori")
	var grid := GridContainer.new()
	grid.columns = 2
	v.add_child(grid)
	for i in NPCDefinition.SLOT_NAMES.size():
		var lab := Label.new()
		lab.text = NPCDefinition.SLOT_NAMES[i]
		grid.add_child(lab)
		var cp := ColorPickerButton.new()
		cp.edit_alpha = false
		cp.custom_minimum_size = Vector2(120, 26)
		cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cp.color_changed.connect(_on_color_changed.bind(i))
		grid.add_child(cp)
		_colors.append(cp)


func _build_shapes_tab() -> void:
	var vs := VSplitContainer.new()
	vs.name = "Forme"
	tabs.add_child(vs)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 450)
	vs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	parts_list = ItemList.new()
	parts_list.custom_minimum_size = Vector2(165, 400)
	parts_list.max_text_lines = 2
	parts_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parts_list.item_selected.connect(func(i): select_part(parts_list.get_item_metadata(i), true))
	h.add_child(parts_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	shape_opt = OptionButton.new()
	shape_opt.fit_to_longest_item = false
	shape_opt.item_selected.connect(_on_shape_selected.bind(false))
	right.add_child(_caption("Forma"))
	right.add_child(shape_opt)
	shape_b_opt = OptionButton.new()
	shape_b_opt.fit_to_longest_item = false
	shape_b_opt.item_selected.connect(_on_shape_selected.bind(true))
	right.add_child(_caption("Morph verso"))
	right.add_child(shape_b_opt)
	morph_slider = _slider(right, "Morph", 0.0, 1.0, 0.01)
	morph_slider.value_changed.connect(func(x): if not _syncing(): _set_prop(_part(), "morph", x))
	thick_slider = _slider(right, "Spessore", 0.5, 1.8, 0.01)
	thick_slider.value_changed.connect(func(x): if not _syncing(): _set_prop(_part(), "thickness", x))
	var hb := HFlowContainer.new()
	right.add_child(hb)
	_button(hb, "Rendi unica", _make_unique, "Copia la forma dentro questo NPC: le modifiche non toccano gli altri")
	_button(hb, "Salva in libreria…", func(): _ask_shape_path(), "Salva la forma come nuovo file della libreria")
	right.add_child(_caption("Sezione (vista lungo l'osso)"))
	section_ed = SectionEditor.new()
	section_ed.custom_minimum_size = Vector2(180, 150)
	section_ed.section_edited.connect(_on_section_edited)
	section_ed.section_committed.connect(_on_section_committed)
	right.add_child(section_ed)
	var sh := HBoxContainer.new()
	right.add_child(sh)
	sym_check = CheckBox.new()
	sym_check.text = "Simmetria"
	sym_check.button_pressed = true
	sym_check.toggled.connect(func(on): section_ed.symmetric = on)
	sh.add_child(sym_check)
	ellipse_btn = _button(sh, "Ellisse", func(): if _part() != null and _shape_editable(_part().shape): _set_prop(_part().shape, "section", PackedFloat32Array(), "sezione"), "Riporta la sezione all'ellisse")
	lib_note = Label.new()
	lib_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lib_note.custom_minimum_size = Vector2(150, 0)
	v.add_child(lib_note)
	lib_edit_check = CheckButton.new()
	lib_edit_check.text = "Modifica la libreria (cambia tutti gli NPC che usano la forma)"
	lib_edit_check.tooltip_text = "Spento: le forme di libreria si possono solo guardare; per cambiarle solo qui usa «Rendi unica»."
	lib_edit_check.toggled.connect(func(on): edit_library = on)
	v.add_child(lib_edit_check)
	shape_inspector = EditorInspector.new()
	shape_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shape_inspector.custom_minimum_size = Vector2(0, 240)
	vs.add_child(shape_inspector)


func _build_acc_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "Accessori"
	tabs.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	acc_add_opt = OptionButton.new()
	acc_add_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(acc_add_opt)
	_button(h, "Aggiungi", _add_accessory, "Aggiunge l'accessorio nella sua posizione predefinita")
	acc_list = ItemList.new()
	acc_list.custom_minimum_size = Vector2(0, 170)
	acc_list.item_selected.connect(func(i): _select_acc(i))
	v.add_child(acc_list)
	var hb := HBoxContainer.new()
	v.add_child(hb)
	_button(hb, "Attiva/disattiva", _toggle_acc, "")
	_button(hb, "Duplica", _dup_acc, "")
	_button(hb, "Rimuovi", _remove_acc, "")
	_button(hb, "Rendi unica la forma", _make_acc_unique, "Copia la forma dentro questo NPC: le modifiche non toccano gli altri")
	acc_note = Label.new()
	acc_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	acc_note.modulate = Color(1, 1, 1, 0.6)
	acc_note.custom_minimum_size = Vector2(150, 0)
	v.add_child(acc_note)
	acc_inspector = EditorInspector.new()
	acc_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(acc_inspector)


func _build_gameplay_tab() -> void:
	var v := _tab("Gameplay")
	_header(v, "Sensi")
	_spin(v, "sight_range", "Portata vista", 5.0, 40.0, 0.5, "m")
	_spin(v, "fov_deg", "Cono visivo (metà)", 20.0, 90.0, 1.0, "°")
	_spin(v, "perception", "Prontezza", 0.2, 3.0, 0.05)
	_spin(v, "hearing", "Udito", 0.2, 3.0, 0.05)
	_header(v, "Combattimento")
	_spin(v, "max_health", "Salute", 10.0, 300.0, 1.0)
	_spin(v, "accuracy", "Precisione", 0.1, 0.85, 0.01)
	_spin(v, "damage_min", "Danno minimo", 0.0, 100.0, 0.5)
	_spin(v, "damage_max", "Danno massimo", 0.0, 100.0, 0.5)
	_spin(v, "reaction_time", "Tempo di reazione", 0.1, 3.0, 0.05, "s")
	_spin(v, "walk_speed", "Passo", 0.5, 4.0, 0.05, "m/s")
	_spin(v, "run_speed", "Corsa", 1.0, 8.0, 0.05, "m/s")
	_header(v, "Comportamento")
	_check(v, "investigates_noises", "Va a controllare i rumori")
	_check(v, "reacts_to_bodies", "Dà l'allarme se trova un corpo")
	_check(v, "responds_to_alarms", "Risponde agli allarmi")
	_check(v, "calls_for_help", "In combattimento chiama rinforzi")


func _build_inventory_tab() -> void:
	var v := _tab("Inventario")
	_header(v, "Bottino (borseggio e perquisizione)")
	_spin(v, "ammo", "Munizioni", 0, 99, 1)
	_spin(v, "credits", "Crediti", 0, 999, 1)
	_spin(v, "medpatch", "Medipatch", 0, 9, 1)
	keycard_id_edit = _line(v, "Tessera (id)", "keycard_id")
	keycard_id_edit.placeholder_text = "es. sicurezza, lab"
	keycard_name_edit = _line(v, "Nome tessera", "keycard_name")
	keycard_name_edit.placeholder_text = "es. Tessera Sicurezza"
	_header(v, "Battute di ronda (una per riga)")
	barks_edit = TextEdit.new()
	barks_edit.custom_minimum_size = Vector2(0, 180)
	barks_edit.placeholder_text = "Vuoto = battute standard delle guardie"
	barks_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	barks_edit.text_changed.connect(_on_barks_changed)
	v.add_child(barks_edit)


func _build_preview_bar(parent: Control) -> void:
	var bar := HBoxContainer.new()
	parent.add_child(bar)
	pose_opt = OptionButton.new()
	for p in POSES:
		pose_opt.add_item(p)
	pose_opt.item_selected.connect(func(i):
		preview.body.set_down(false)
		preview.body.preview_pose = i)
	bar.add_child(pose_opt)
	var retro := CheckBox.new()
	retro.text = "Retro 640×360"
	retro.button_pressed = true
	retro.toggled.connect(func(on): preview.retro = on)
	bar.add_child(retro)
	var light := EditorSpinSlider.new()
	light.label = "Luce"
	light.min_value = 0.0
	light.max_value = 3.0
	light.step = 0.05
	light.value = 1.5
	light.custom_minimum_size = Vector2(130, 0)
	light.value_changed.connect(func(x): preview.set_light(x))
	bar.add_child(light)
	bar.add_child(VSeparator.new())
	bg_opt = OptionButton.new()
	bg_opt.tooltip_text = "Sfondo dell'anteprima: uno chiaro o saturo fa risaltare i dettagli scuri"
	for b in Preview.BACKGROUNDS:
		bg_opt.add_item(b[0])
	bg_opt.add_item("Personalizzato")
	bg_opt.item_selected.connect(func(i):
		if i < Preview.BACKGROUNDS.size():
			set_preview_background(Preview.BACKGROUNDS[i][1]))
	bar.add_child(bg_opt)
	bg_color = ColorPickerButton.new()
	bg_color.edit_alpha = false
	bg_color.custom_minimum_size = Vector2(32, 0)
	bg_color.tooltip_text = "Colore dello sfondo"
	bg_color.color_changed.connect(set_preview_background.bind(false))
	bg_color.popup_closed.connect(func(): _save_view_setting("preview_bg", bg_color.color))
	bar.add_child(bg_color)
	floor_check = CheckBox.new()
	floor_check.text = "Pavimento"
	floor_check.button_pressed = true
	floor_check.toggled.connect(func(on):
		preview.set_floor_visible(on)
		_save_view_setting("preview_floor", on))
	bar.add_child(floor_check)
	stats_label = Label.new()
	stats_label.clip_text = true
	stats_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stats_label.custom_minimum_size = Vector2(60, 0)
	stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_label.modulate = Color(1, 1, 1, 0.6)
	bar.add_child(stats_label)
	# sfondo e pavimento restano quelli scelti l'ultima volta (per questo progetto)
	set_preview_background(_load_view_setting("preview_bg", Preview.BACKGROUNDS[0][1]))
	var fl: bool = _load_view_setting("preview_floor", true)
	floor_check.set_pressed_no_signal(fl)
	preview.set_floor_visible(fl)


func set_preview_background(c: Color, persist := true) -> void:
	preview.set_background(c)
	bg_color.color = c
	var idx := Preview.BACKGROUNDS.size()
	for i in Preview.BACKGROUNDS.size():
		if (Preview.BACKGROUNDS[i][1] as Color).is_equal_approx(c):
			idx = i
	bg_opt.select(idx)
	if persist:
		_save_view_setting("preview_bg", c)


func _load_view_setting(key: String, fallback: Variant) -> Variant:
	if not Engine.is_editor_hint():
		return fallback
	return EditorInterface.get_editor_settings().get_project_metadata("npc_creator", key, fallback)


func _save_view_setting(key: String, value: Variant) -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_editor_settings().set_project_metadata("npc_creator", key, value)


# --- piccoli costruttori -------------------------------------------------------------
func _tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HeaderSmall"
	parent.add_child(l)


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)
	return l


func _row(parent: Control, text: String, c: Control) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(110, 0)
	h.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(c)
	parent.add_child(h)


func _button(parent: Control, text: String, cb: Callable, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _slider(parent: Control, text: String, mn: float, mx: float, step: float, suffix := "") -> EditorSpinSlider:
	var s := EditorSpinSlider.new()
	s.label = text
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.suffix = suffix
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)
	return s


func _spin(parent: Control, prop: String, text: String, mn: float, mx: float, step: float, suffix := "") -> EditorSpinSlider:
	var s := _slider(parent, text, mn, mx, step, suffix)
	s.value_changed.connect(func(x):
		if _syncing():
			return
		var cur: Variant = def.get(prop)
		_set_prop(def, prop, int(x) if typeof(cur) == TYPE_INT else x))
	_ctrls[prop] = s
	return s


func _check(parent: Control, prop: String, text: String) -> void:
	var c := CheckBox.new()
	c.text = text
	c.toggled.connect(func(on): if not _syncing(): _set_prop(def, prop, on))
	parent.add_child(c)
	_ctrls[prop] = c


func _line(parent: Control, text: String, prop: String) -> LineEdit:
	var e := LineEdit.new()
	e.text_changed.connect(func(t): if not _syncing(): _set_prop(def, prop, t))
	_row(parent, text, e)
	return e


# --- modifica con annulla/ripeti -------------------------------------------------------
var _sync_depth := 0


func _syncing() -> bool:
	return _sync_depth > 0 or def == null


var _last_merge_key := ""


## Imposta una proprietà registrando l'azione nell'annulla dell'editor. Le modifiche
## consecutive alla stessa proprietà dello stesso oggetto (trascinare uno slider)
## diventano un solo passo; tutto il resto resta separato.
func _set_prop(obj: Object, prop: String, value: Variant, label := "") -> void:
	if obj == null:
		return
	var ur := plugin.get_undo_redo() if plugin != null else null
	if ur == null:
		obj.set(prop, value)
		_after_edit()
		return
	var key := "%d:%s" % [obj.get_instance_id(), prop]
	var merge := UndoRedo.MERGE_ENDS if key == _last_merge_key else UndoRedo.MERGE_DISABLE
	_last_merge_key = key
	# contesto = il pannello (un nodo fuori dalla scena): l'azione va nella cronologia
	# globale e non marca come modificata la scena aperta
	ur.create_action("NPC: " + (label if label != "" else prop), merge, self)
	ur.add_do_method(self, &"_apply", def, obj, prop, value)
	ur.add_undo_method(self, &"_apply", def, obj, prop, obj.get(prop))
	ur.commit_action()


## Esegue un passo di annulla/ripeti. Le azioni restano nella cronologia anche dopo aver
## aperto un altro NPC: se riguardano il documento precedente non fanno niente.
func _apply(owner: NPCDefinition, obj: Object, prop: String, value: Variant) -> void:
	if owner != def or not is_instance_valid(obj):
		return
	obj.set(prop, value)
	if obj is SegmentShape and NPCDefinition.is_library_shape(obj) and _uses_shape(obj):
		_dirty_shapes[obj.resource_path] = obj
	_after_edit()


func _after_edit() -> void:
	_assign_history_paths()
	_watch_shapes()
	_sync_library_shapes()
	_mark_dirty()
	_queue_refresh()


func _mark_dirty() -> void:
	if not dirty:
		dirty = true
		_update_title()


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_do_refresh.call_deferred()


func _do_refresh() -> void:
	_refresh_queued = false
	_watch_shapes()
	sync_ui()


func _snapshot(d: NPCDefinition) -> Dictionary:
	var out := {}
	for p in d.get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE and p.name != "script" and not String(p.name).begins_with("resource_"):
			var v: Variant = d.get(p.name)
			if v is Dictionary or v is Array:
				v = v.duplicate()
			out[p.name] = v
	return out


func _restore(owner: NPCDefinition, snap: Dictionary) -> void:
	if owner != def:
		return
	for k in snap:
		def.set(k, snap[k])
	_after_edit()


# --- documento: nuovo, apri, salva ---------------------------------------------------
func new_npc(arch: int, rseed: int) -> void:
	var d := NPCLibrary.random_npc(arch, rseed)
	_load_def(d)
	_mark_dirty()
	_status("Nuovo NPC: %s (seme %d)" % [NPCLibrary.ARCH_LABELS[arch], rseed])


func open_definition(d: NPCDefinition) -> void:
	if d == def:
		return
	_guard_discard(func(): _load_def(d))


func _load_def(d: NPCDefinition, keep_dirty_shapes := false) -> void:
	if def != null and def.changed.is_connected(_on_def_changed):
		def.changed.disconnect(_on_def_changed)
	if def != null and d != def and plugin != null:
		# le modifiche fatte negli Inspector integrati sono azioni normali dell'editor: un
		# Ctrl+Z dopo aver cambiato NPC cambierebbe quello chiuso. Si riparte da zero.
		plugin.get_undo_redo().clear_history(EditorUndoRedoManager.GLOBAL_HISTORY, false)
	def = d
	dirty = false
	_last_merge_key = ""
	_released.clear()
	if not keep_dirty_shapes:
		_dirty_shapes.clear()
	def.changed.connect(_on_def_changed)
	_assign_history_paths()
	preview.set_definition(def)
	_selected_acc = -1
	acc_inspector.edit(null)
	_watch_shapes()
	sync_ui()
	select_part(_selected_part, false)
	_update_title()


func _on_def_changed() -> void:
	if _quiet > 0:
		return
	# subito, non al prossimo frame: una forma appena assegnata va già sorvegliata
	_watch_shapes()
	_sync_library_shapes()
	_mark_dirty()
	_queue_refresh()


## Scarta le modifiche: la definizione aperta e le forme di libreria modificate tornano
## come sono su disco, in tutte le proprietà (anche quelle al valore predefinito). Gli
## oggetti in memoria restano gli stessi: anche il livello e gli altri NPC li vedono.
func revert_unsaved() -> void:
	_quiet += 1
	for sp in _dirty_shapes:
		NPCLibrary.restore_from_disk(_dirty_shapes[sp])
	_dirty_shapes.clear()
	_released.clear()
	if def != null and def_path != "" and dirty:
		NPCLibrary.restore_from_disk(def)
	_quiet -= 1
	dirty = false
	_assign_history_paths()
	_update_title()
	_queue_refresh()


## Chiede cosa fare delle modifiche non salvate: Salva, Scarta o Annulla.
func _guard_discard(then: Callable) -> void:
	if not dirty:
		then.call()
		return
	_pending = then
	confirm.dialog_text = "%s ha modifiche non salvate." % (def.display_name if def else "L'NPC")
	confirm.popup_centered()


func _run_pending() -> void:
	var cb := _pending
	_pending = Callable()
	if cb.is_valid():
		cb.call()


## Salva e poi prosegue (se l'NPC non ha ancora un file, prima chiede dove).
func _save_then(then: Callable) -> void:
	if def_path == "":
		_after_save = then
		_ask_save_path()
		return
	if save_to(def_path) == OK and then.is_valid():
		then.call()


func _on_open_pressed() -> void:
	# prima si sceglie il file: se poi si annulla, le modifiche restano dove sono
	_dialog_mode = "open"
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.clear_filters()
	file_dialog.add_filter("*.tres", "Definizione NPC")
	file_dialog.current_dir = NPCLibrary.CHARACTERS_DIR
	file_dialog.popup_file_dialog()


func _ask_save_path() -> void:
	_dialog_mode = "save"
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_dialog.clear_filters()
	file_dialog.add_filter("*.tres", "Definizione NPC")
	file_dialog.current_dir = NPCLibrary.CHARACTERS_DIR
	file_dialog.current_file = _slug(def.display_name) + ".tres"
	file_dialog.popup_file_dialog()


func _ask_shape_path() -> void:
	if _part() == null or _part().shape == null:
		return
	_dialog_mode = "shape"
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_dialog.clear_filters()
	file_dialog.add_filter("*.tres", "Forma di segmento")
	file_dialog.current_dir = NPCLibrary.SHAPES_DIR
	file_dialog.current_file = NPCLibrary.shape_name_of(_part().shape).replace(" ", "_") + "_2.tres"
	file_dialog.popup_file_dialog()


func _on_file_selected(path: String) -> void:
	match _dialog_mode:
		"open":
			var r := load(path)
			if r is NPCDefinition:
				_guard_discard(func():
					_load_def(r)
					_status("Aperto " + path.get_file()))
			else:
				_status("Non è una definizione di NPC: " + path.get_file())
		"save":
			var then := _after_save
			_after_save = Callable()
			if save_to(path) == OK and then.is_valid():
				then.call()
		"shape":
			save_shape_to_library(path)


func save() -> void:
	if def_path == "":
		_ask_save_path()
	else:
		save_to(def_path)


## Ctrl+S dell'editor (anche da un'altra scheda), avvio del gioco, chiusura con
## salvataggio. Godot a ogni Ctrl+S salva comunque le risorse modificate che hanno un file
## (l'NPC aperto e le forme di libreria cambiate con «Modifica la libreria»): il creatore
## fa lo stesso, in ordine. Un NPC mai salvato non ha un file: resta da salvare, con un avviso.
func save_on_editor_save() -> void:
	if def == null or (not dirty and _dirty_shapes.is_empty()):
		return
	if def_path != "":
		save_to(def_path)
		return
	var n := _save_library_shapes()
	_warn_unsaved("non è mai stato salvato" + (" (salvate %d forme di libreria)" % n if n > 0 else ""))


func _warn_unsaved(why: String) -> void:
	var msg := "Creatore di NPC: «%s» %s. Usa Salva nella scheda NPC per dargli un file." % [def.display_name, why]
	_status("NPC non salvato: " + why)
	push_warning(msg)


## Salva nel file `path`. Se l'NPC aveva già un altro file è un «Salva come» (vedi save_as).
func save_to(path: String) -> Error:
	if def_path != "" and path != def_path:
		return save_as(path)
	var target := _adopt_path(def, path)
	# le sottorisorse (parti, accessori, forme uniche) prendono percorsi di questo file:
	# niente oggetti condivisi con altri file, e le modifiche vanno nella cronologia giusta
	var err := ResourceSaver.save(target, path, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
	if err != OK:
		_status("Errore %d nel salvare %s" % [err, path])
		return err
	if target != def:
		_load_def(target, true)
	var extra := _save_library_shapes()
	dirty = false
	_update_title()
	_fs_update(path)
	NPCLibrary.invalidate()
	_status("Salvato %s%s" % [path.get_file(), (" + %d forme di libreria" % extra) if extra > 0 else ""])
	return OK


## «Salva come»: l'NPC aperto diventa una copia nel nuovo file; il file di prima resta
## com'era su disco (con i livelli che lo usano).
func save_as(path: String) -> Error:
	var copy := _adopt_path(def.clone(), path)
	var err := ResourceSaver.save(copy, path, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
	if err != OK:
		_status("Errore %d nel salvare %s" % [err, path])
		return err
	var old := def
	_quiet += 1
	if dirty:
		NPCLibrary.restore_from_disk(old)
	_quiet -= 1
	_load_def(copy, true)
	var extra := _save_library_shapes()
	dirty = false
	_update_title()
	_fs_update(path)
	NPCLibrary.invalidate()
	_status("Salvato come %s%s" % [path.get_file(), (" + %d forme di libreria" % extra) if extra > 0 else ""])
	return OK


## Salvare sopra un file già caricato da un'altra risorsa (per esempio ruiz.tres, usato
## dalle guardie di un livello aperto): i dati vanno nell'oggetto che tutti usano, così il
## livello continua a puntare al file invece di incorporarsi la versione vecchia.
func _adopt_path(src: NPCDefinition, path: String) -> NPCDefinition:
	if ResourceLoader.has_cached(path):
		var target := load(path)
		if target is NPCDefinition and target != src:
			_quiet += 1
			NPCLibrary.copy_storage(src, target)
			_quiet -= 1
			return target
	src.take_over_path(path)
	return src


## Salva le forme di libreria modificate che l'NPC usa ancora; quelle che non usa più
## tornano com'erano (le modifiche valevano solo per lui).
func _save_library_shapes() -> int:
	var n := 0
	for sp in _dirty_shapes.keys():
		var sh: SegmentShape = _dirty_shapes[sp]
		if _uses_shape(sh):
			if ResourceSaver.save(sh, sp, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS) == OK:
				n += 1
				_fs_update(sp)
		else:
			_quiet += 1
			NPCLibrary.restore_from_disk(sh)
			_quiet -= 1
	_dirty_shapes.clear()
	_released.clear()
	return n


func save_shape_to_library(path: String) -> void:
	var part := _part()
	var old := part.shape
	var copy: SegmentShape = part.shape.duplicate(true)
	copy.resource_name = path.get_file().get_basename()
	var target := copy
	if ResourceLoader.has_cached(path):
		# si sovrascrive una forma già caricata: si aggiorna quella, così la vedono tutti
		target = load(path)
		_quiet += 1
		NPCLibrary.copy_storage(copy, target)
		_quiet -= 1
	else:
		copy.take_over_path(path)
	if ResourceSaver.save(target, path, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS) != OK:
		_status("Errore nel salvare la forma")
		return
	_fs_update(path)
	NPCLibrary.invalidate()
	_set_prop(part, "shape", target, "forma in libreria")
	_status("Forma salvata in libreria: " + path.get_file())


func _fs_update(path: String) -> void:
	if Engine.is_editor_hint() and EditorInterface.get_resource_filesystem() != null:
		EditorInterface.get_resource_filesystem().update_file(path)


func _duplicate() -> void:
	var d := def.clone()
	d.display_name = def.display_name + " (copia)"
	# l'originale torna com'è su disco: le modifiche non salvate passano nella copia
	var had_changes := dirty
	var old := def
	_load_def(d, true)
	if had_changes:
		_quiet += 1
		NPCLibrary.restore_from_disk(old)
		_quiet -= 1
	_mark_dirty()
	_status("Copia creata: salvala con un nuovo nome")


func randomize_appearance(rseed: int) -> void:
	var before := _snapshot(def)
	NPCLibrary.randomize_appearance(def, rseed, false)
	var after := _snapshot(def)
	var ur := plugin.get_undo_redo() if plugin != null else null
	if ur != null:
		_last_merge_key = ""
		ur.create_action("NPC: aspetto casuale", UndoRedo.MERGE_DISABLE, self)
		ur.add_do_method(self, &"_restore", def, after)
		ur.add_undo_method(self, &"_restore", def, before)
		ur.commit_action(false)
	_after_edit()
	_status("Aspetto casuale (seme %d)" % rseed)


## Le forme di libreria modificate (con «Modifica la libreria») si salvano nei loro file.
func _watch_shapes() -> void:
	for r in _watched:
		if is_instance_valid(r) and r.changed.is_connected(_on_lib_shape_changed):
			r.changed.disconnect(_on_lib_shape_changed)
	_watched.clear()
	if def == null:
		return
	for sh in _used_shapes():
		if NPCDefinition.is_library_shape(sh) and not sh in _watched:
			sh.changed.connect(_on_lib_shape_changed.bind(sh))
			_watched.append(sh)


func _used_shapes() -> Array[SegmentShape]:
	var out: Array[SegmentShape] = []
	if def == null:
		return out
	for k in def.parts:
		for sh in [def.parts[k].shape, def.parts[k].shape_b]:
			if sh != null:
				out.append(sh)
	for a in def.attachments:
		if a != null and a.shape != null:
			out.append(a.shape)
	return out


func _uses_shape(sh: SegmentShape) -> bool:
	return sh in _used_shapes()


func _on_lib_shape_changed(sh: SegmentShape) -> void:
	if _quiet > 0 or not _uses_shape(sh):
		return
	_dirty_shapes[sh.resource_path] = sh
	_mark_dirty()


## Forme di libreria modificate che l'NPC non usa più (Rendi unica, cambio di forma,
## accessorio rimosso, anche per annulla/ripeti): tornano com'erano su disco, così gli
## altri NPC e i livelli non vedono modifiche orfane. Se l'annulla le rimette in uso,
## riprendono le modifiche.
func _sync_library_shapes() -> void:
	if def == null:
		return
	var used := _used_shapes()
	for sp in _dirty_shapes.keys():
		var sh: SegmentShape = _dirty_shapes[sp]
		if not sh in used:
			_released[sp] = sh.duplicate(true)
			_dirty_shapes.erase(sp)
			_quiet += 1
			NPCLibrary.restore_from_disk(sh)
			_quiet -= 1
			_status("«%s» in libreria è rimasta com'era" % NPCLibrary.shape_name_of(sh))
	for sp in _released.keys():
		for sh in used:
			if sh.resource_path == sp:
				_quiet += 1
				NPCLibrary.copy_storage(_released[sp], sh)
				_quiet -= 1
				_dirty_shapes[sp] = sh
				_released.erase(sp)
				break


## Le sottorisorse senza percorso (parti e accessori di un NPC nuovo, forme uniche non
## ancora salvate) finirebbero nella cronologia della scena aperta quando le modifica un
## Inspector integrato. Un percorso interno provvisorio le manda nella cronologia globale;
## al salvataggio viene sostituito da quello vero.
func _assign_history_paths() -> void:
	if def == null:
		return
	var base := def_path if def_path != "" else NPCLibrary.CHARACTERS_DIR.path_join("_nuovo_npc.tres")
	var subs: Array[Resource] = []
	for k in def.parts:
		subs.append(def.parts[k])
	for a in def.attachments:
		subs.append(a)
	for sh in _used_shapes():
		if not NPCDefinition.is_library_shape(sh):
			subs.append(sh)
			for cv in [sh.width_curve, sh.depth_curve, sh.bulge_curve]:
				if cv != null:
					subs.append(cv)
	for r in subs:
		if r != null and r.resource_path == "":
			r.set_path_cache("%s::npc_tmp_%d" % [base, r.get_instance_id()])


# --- sincronizzazione dell'interfaccia --------------------------------------------------
func sync_ui() -> void:
	if def == null:
		return
	_sync_depth += 1
	for prop in _ctrls:
		var c: Control = _ctrls[prop]
		var v: Variant = def.get(prop)
		if c is EditorSpinSlider:
			(c as EditorSpinSlider).set_value_no_signal(float(v))
		elif c is CheckBox:
			(c as CheckBox).set_pressed_no_signal(bool(v))
	for i in _colors.size():
		_colors[i].color = def.color(i)
	if not name_edit.has_focus():
		name_edit.text = def.display_name
	if not faction_edit.has_focus():
		faction_edit.text = def.faction
	if not keycard_id_edit.has_focus():
		keycard_id_edit.text = def.keycard_id
	if not keycard_name_edit.has_focus():
		keycard_name_edit.text = def.keycard_name
	if not barks_edit.has_focus():
		barks_edit.text = "\n".join(def.idle_barks)
	arch_opt.select(def.archetype)
	seed_spin.set_value_no_signal(def.random_seed)
	_fill_parts_list()
	_refresh_part_ui()
	_fill_acc_ui()
	_sync_depth -= 1
	_update_stats.call_deferred()


func _update_title() -> void:
	if file_label == null:
		return
	var nm := def_path.get_file() if def_path != "" else "(non salvato)"
	file_label.text = ("● " if dirty else "") + nm
	file_label.tooltip_text = def_path


func _status(t: String) -> void:
	if status_label != null:
		status_label.text = t + "   "


func _update_stats() -> void:
	if preview == null or preview.body == null or def == null:
		return
	var st := preview.body.stats
	stats_label.text = "%d tri · 1 draw call · occhi %.2f m" % [st.triangles, def.eye_height()]
	stats_label.tooltip_text = "%d triangoli, %d ossa, una sola superficie (1 draw call per passata di luce). Occhi a %.2f m: da lì la guardia guarda." % [st.triangles, NPCRig.BONES.size(), def.eye_height()]


# --- forme -----------------------------------------------------------------------------
func _part() -> NPCPart:
	return def.get_part(_selected_part) if def != null else null


func select_part(p: String, frame: bool) -> void:
	_selected_part = p
	for i in parts_list.item_count:
		if parts_list.get_item_metadata(i) == p:
			parts_list.select(i)
	preview.body.highlight_part = p if tabs.current_tab == 1 else ""
	if frame:
		preview.frame_part(p)
	_refresh_part_ui()


func _on_tab_changed(t: int) -> void:
	if preview == null:
		return
	match t:
		1:
			preview.body.highlight_part = _selected_part
		2:
			preview.body.highlight_part = "acc%d" % _selected_acc if _selected_acc >= 0 else ""
		_:
			preview.body.highlight_part = ""


func _on_preview_part_clicked(p: String) -> void:
	tabs.current_tab = 1
	select_part(p, false)


func _fill_parts_list() -> void:
	var sel := _selected_part
	parts_list.clear()
	for p in NPCDefinition.PART_NAMES:
		var part := def.get_part(p)
		var sn := NPCLibrary.shape_name_of(part.shape) if part != null else "—"
		if part != null and part.shape != null and not NPCDefinition.is_library_shape(part.shape):
			sn = "★ " + sn
		var i := parts_list.add_item("%s\n   %s" % [PART_LABELS[p], sn])
		parts_list.set_item_metadata(i, p)
		if p == sel:
			parts_list.select(i)


func _fill_shape_opt(opt: OptionButton, cat: int, cur: SegmentShape, allow_none: bool) -> void:
	opt.clear()
	var idx := 0
	if allow_none:
		opt.add_item("(nessuna)")
		opt.set_item_metadata(0, "")
		idx = 1
	var selected := 0 if allow_none and cur == null else -1
	if cur != null and not NPCDefinition.is_library_shape(cur):
		opt.add_item("★ unica: " + NPCLibrary.shape_name_of(cur))
		opt.set_item_metadata(idx, "*")
		selected = idx
		idx += 1
	for e in NPCLibrary.list_shapes(cat):
		opt.add_item(e[0])
		opt.set_item_metadata(idx, NPCLibrary.shape_path(e[0]))
		if cur != null and cur.resource_path == NPCLibrary.shape_path(e[0]):
			selected = idx
		idx += 1
	if selected >= 0:
		opt.select(selected)


func _refresh_part_ui() -> void:
	var part := _part()
	if part == null:
		section_ed.set_shape(null)
		shape_inspector.edit(null)
		return
	_sync_depth += 1
	var cat := NPCDefinition.PART_NAMES.find(_selected_part)
	_fill_shape_opt(shape_opt, cat, part.shape, false)
	_fill_shape_opt(shape_b_opt, cat, part.shape_b, true)
	morph_slider.set_value_no_signal(part.morph)
	thick_slider.set_value_no_signal(part.thickness)
	section_ed.set_shape(part.shape)
	var can_edit := _shape_editable(part.shape)
	section_ed.editable = can_edit
	ellipse_btn.disabled = not can_edit
	# una forma condivisa bloccata non va nell'Inspector integrato: lì si modificherebbe
	var inspected: Object = part.shape if can_edit else null
	if shape_inspector.get_edited_object() != inspected:
		shape_inspector.edit(inspected)
	var lib := part.shape != null and NPCDefinition.is_library_shape(part.shape)
	lib_edit_check.visible = lib
	if lib:
		var users := NPCLibrary.shape_users(part.shape.resource_path)
		var who := ("usata da %d personaggi: %s" % [users.size(), ", ".join(users)]) if not users.is_empty() else "condivisa con gli altri NPC"
		if edit_library:
			lib_note.text = "Stai modificando la forma di libreria «%s» (%s): cambia per tutti e si salva nel suo file." % [NPCLibrary.shape_name_of(part.shape), who]
		else:
			lib_note.text = "Forma di libreria «%s», %s. Per cambiarla solo qui: «Rendi unica». Per cambiarla per tutti: attiva «Modifica la libreria»." % [NPCLibrary.shape_name_of(part.shape), who]
		lib_note.modulate = Color(1.0, 0.82, 0.45)
	else:
		lib_note.text = "Forma unica di questo NPC: si salva dentro il suo file."
		lib_note.modulate = Color(1, 1, 1, 0.65)
	_sync_depth -= 1


## Le forme uniche si modificano sempre; quelle di libreria solo con «Modifica la libreria».
func _shape_editable(sh: SegmentShape) -> bool:
	return sh != null and (edit_library or not NPCDefinition.is_library_shape(sh))


func _on_shape_selected(i: int, is_b: bool) -> void:
	if _syncing():
		return
	var opt := shape_b_opt if is_b else shape_opt
	var path: String = opt.get_item_metadata(i)
	if path == "*":
		return
	var s: SegmentShape = null if path == "" else load(path)
	var part := _part()
	_set_prop(part, "shape_b" if is_b else "shape", s, "forma")


func _make_unique() -> void:
	var part := _part()
	if part == null or part.shape == null or not NPCDefinition.is_library_shape(part.shape):
		return
	var lib := part.shape
	var copy: SegmentShape = lib.duplicate(true)
	copy.resource_name = NPCLibrary.shape_name_of(lib) + "_unica"
	_set_prop(part, "shape", copy, "rendi unica")


func _on_section_edited(sec: PackedFloat32Array) -> void:
	if _part() != null and _shape_editable(_part().shape):
		_part().shape.section = sec


func _on_section_committed(old: PackedFloat32Array, sec: PackedFloat32Array) -> void:
	if _part() == null or not _shape_editable(_part().shape):
		return
	var s := _part().shape
	var ur := plugin.get_undo_redo() if plugin != null else null
	if ur == null:
		s.section = sec
		_after_edit()
		return
	_last_merge_key = ""
	ur.create_action("NPC: sezione", UndoRedo.MERGE_DISABLE, self)
	ur.add_do_method(self, &"_apply", def, s, "section", sec)
	ur.add_undo_method(self, &"_apply", def, s, "section", old)
	ur.commit_action()


func _on_color_changed(c: Color, slot: int) -> void:
	if _syncing():
		return
	var p := def.palette.duplicate()
	while p.size() <= slot:
		p.append(Color.GRAY)
	p[slot] = c
	_set_prop(def, "palette", p, "colore " + NPCDefinition.SLOT_NAMES[slot])


func _on_barks_changed() -> void:
	if _syncing():
		return
	var lines := PackedStringArray()
	for l in barks_edit.text.split("\n"):
		if l.strip_edges() != "":
			lines.append(l.strip_edges())
	_set_prop(def, "idle_barks", lines, "battute")


# --- accessori ---------------------------------------------------------------------------
var _acc_lib_version := -1


func _fill_acc_ui() -> void:
	if _acc_lib_version != NPCLibrary.version or acc_add_opt.item_count == 0:
		_acc_lib_version = NPCLibrary.version
		var keep := acc_add_opt.get_item_text(acc_add_opt.selected) if acc_add_opt.selected >= 0 else ""
		acc_add_opt.clear()
		for e in NPCLibrary.list_shapes(SegmentShape.Category.ACCESSORIO):
			acc_add_opt.add_item(e[0])
			if e[0] == keep:
				acc_add_opt.select(acc_add_opt.item_count - 1)
	acc_list.clear()
	for i in def.attachments.size():
		var a := def.attachments[i]
		var bl: String = NPCRig.BONE_LABELS.get(a.bone, a.bone)
		var idx := acc_list.add_item("%s  ·  %s%s" % [a.label, bl, "  (×2)" if a.mirror else ""])
		if not a.enabled:
			acc_list.set_item_custom_fg_color(idx, Color(1, 1, 1, 0.35))
	if _selected_acc >= def.attachments.size():
		_selected_acc = -1
	if _selected_acc >= 0:
		acc_list.select(_selected_acc)
	# dopo Casuale o annulla l'Inspector deve seguire l'accessorio che c'è davvero
	var cur: NPCAttachment = def.attachments[_selected_acc] if _selected_acc >= 0 else null
	if acc_inspector.get_edited_object() != cur:
		acc_inspector.edit(cur)
	_update_acc_note(cur)


func _select_acc(i: int) -> void:
	_selected_acc = i if i >= 0 and i < def.attachments.size() else -1
	var a: NPCAttachment = def.attachments[_selected_acc] if _selected_acc >= 0 else null
	acc_inspector.edit(a)
	_update_acc_note(a)
	preview.body.highlight_part = "acc%d" % _selected_acc if a != null else ""


func _update_acc_note(a: NPCAttachment) -> void:
	if a == null or a.shape == null:
		acc_note.text = "Posizione, direzione e lunghezza qui sotto."
	elif NPCDefinition.is_library_shape(a.shape) and not edit_library:
		acc_note.text = "Forma «%s» della libreria, bloccata (%s). «Rendi unica la forma» per cambiarla solo qui, oppure attiva «Modifica la libreria» nella scheda Forme per cambiarla per tutti." % [NPCLibrary.shape_name_of(a.shape), ", ".join(NPCLibrary.shape_users(a.shape.resource_path)) if not NPCLibrary.shape_users(a.shape.resource_path).is_empty() else "condivisa"]
	elif NPCDefinition.is_library_shape(a.shape):
		acc_note.text = "Stai modificando la forma di libreria «%s»: cambia per tutti gli NPC che la usano." % NPCLibrary.shape_name_of(a.shape)
	else:
		acc_note.text = "Forma unica di questo accessorio (si apre cliccandoci sopra): si salva dentro il file dell'NPC."


func _make_acc_unique() -> void:
	if _selected_acc < 0:
		return
	var a := def.attachments[_selected_acc]
	if a.shape == null or not NPCDefinition.is_library_shape(a.shape):
		return
	var lib := a.shape
	var copy: SegmentShape = lib.duplicate(true)
	copy.resource_name = NPCLibrary.shape_name_of(lib) + "_unica"
	_set_prop(a, "shape", copy, "rendi unica")
	acc_inspector.edit(null)
	_fill_acc_ui()


func _add_accessory() -> void:
	if acc_add_opt.selected < 0:
		return
	var nm := acc_add_opt.get_item_text(acc_add_opt.selected)
	var arr := def.attachments.duplicate()
	arr.append(NPCLibrary.attachment_from(nm))
	_set_prop(def, "attachments", arr, "aggiungi accessorio")
	_selected_acc = arr.size() - 1
	_select_acc.call_deferred(_selected_acc)


func _toggle_acc() -> void:
	if _selected_acc < 0:
		return
	var a := def.attachments[_selected_acc]
	_set_prop(a, "enabled", not a.enabled, "attiva accessorio")


func _dup_acc() -> void:
	if _selected_acc < 0:
		return
	var arr := def.attachments.duplicate()
	var c: NPCAttachment = def.attachments[_selected_acc].duplicate(false)
	if c.shape != null and not NPCDefinition.is_library_shape(c.shape):
		c.shape = c.shape.duplicate(true)
	c.label += " 2"
	arr.append(c)
	_set_prop(def, "attachments", arr, "duplica accessorio")


func _remove_acc() -> void:
	if _selected_acc < 0:
		return
	var arr := def.attachments.duplicate()
	arr.remove_at(_selected_acc)
	_selected_acc = -1
	acc_inspector.edit(null)
	preview.body.highlight_part = ""
	_set_prop(def, "attachments", arr, "rimuovi accessorio")


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree() and def != null:
		_queue_refresh()


static func _slug(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch in "àáâä":
			out += "a"
		elif ch in "èéêë":
			out += "e"
		elif ch in "ìíîï":
			out += "i"
		elif ch in "òóôö":
			out += "o"
		elif ch in "ùúûü":
			out += "u"
		elif ch in "čćç":
			out += "c"
		elif ch in "šś":
			out += "s"
		elif ch in "žź":
			out += "z"
		elif not out.ends_with("_") and out != "":
			out += "_"
	return out.trim_suffix("_") if out != "" else "npc"
