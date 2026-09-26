extends CanvasLayer
## Gestore dei pannelli a schermo: menu iniziale (con allocazione delle skill),
## pausa, salva/carica, opzioni (con la rimappatura dei tasti), PDA,
## serrature/tastierino, minigioco di hacking, stazione di potenziamento, terminali,
## lettore registri, schermate di morte e di fine.
##
## Testi: in inglese dentro tr(); l'italiano è in locale/it.po. La traduzione
## automatica dei Control è spenta (root.auto_translate_mode): ogni testo passa
## esplicitamente da tr(), così lo strumento tools/i18n.gd li trova tutti.

## Riepilogo dei comandi: ogni %s è un tasto (quelli attuali, vedi controls_text()).
# i18n
const CONTROLS := "%s move   %s run   %s (hold) / %s (toggle) crouch\n%s jump / climb onto ledges (mantle)   %s lean\n%s attack · throw   %s interact (frob) · put down\n%s wrench / pistol   %s reload   %s medipatch\n%s PDA   %s pause   %s internal resolution   %s dithering\n%s quicksave   %s quickload"

var root: Control
var dim: ColorRect
var current: Control = null
var current_kind := ""
var hack_lockouts := {}

# stato del minigioco di hacking
var _hk := {}
# menu iniziale
var _st_rows: VBoxContainer
var _st_pts: Label
var _st_btn: Button
# pannelli aperti da un altro pannello (opzioni, salva, carica): dove torna Esc
var _return_to := Callable()
# tasto da assegnare nel pannello Comandi: {action, slot}
var _capture := {}
var _ctl_msg := ""


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.ui = self
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(root)
	dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0.01, 0.01, 0.6)
	dim.visible = false
	root.add_child(dim)


func is_open() -> bool:
	return current != null


func _show(panel: Control, kind: String, pause := true) -> void:
	_clear()
	var node: Control = panel.get_meta("wrapper") if panel.has_meta("wrapper") else panel
	current = node
	current_kind = kind
	dim.visible = true
	root.add_child(node)
	if pause:
		Game.set_state(Game.State.PANEL)


func _clear() -> void:
	if current_kind in ["pause", "options"]:
		Game.save_settings()   # sensibilità e volume cambiati con i cursori
	if current != null:
		current.queue_free()
	current = null
	current_kind = ""
	dim.visible = false


func close_panel() -> void:
	if current_kind == "hack" and _hk.get("started", false) and not _hk.get("done", false):
		_hack_lose()
		return
	if current_kind in ["options", "save", "load"] and _return_to.is_valid():
		var back := _return_to
		_return_to = Callable()
		_capture = {}
		back.call()   # torna al pannello da cui si era partiti (pausa o menu iniziale)
		return
	if current_kind in ["start", "death", "complete", ""]:
		return
	_clear()
	Game.set_state(Game.State.PLAYING)


func toggle_pda() -> void:
	if current_kind == "pda":
		close_panel()
	elif current == null and Game.state == Game.State.PLAYING:
		open_pda()


# --- mattoncini --------------------------------------------------------------------
## Pannello centrato. h = 0: altezza automatica in base al contenuto.
func _panel(w: float, h: float) -> PanelContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(w, h)
	cc.add_child(pc)
	pc.set_meta("wrapper", cc)
	return pc


func _window(title: String, w: float, h: float) -> Array:
	var pc := _panel(w, h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var t := UITheme.label(title, 22, UITheme.ACCENT)
	v.add_child(t)
	var sep := ColorRect.new()
	sep.color = UITheme.BORDER.darkened(0.3)
	sep.custom_minimum_size = Vector2(0, 2)
	v.add_child(sep)
	return [pc, v]


func _rich(text: String, size := 17, width := 0.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.custom_minimum_size.x = width
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", UITheme.TEXT)
	return r


func _spacer(h := 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Riepilogo dei comandi con i tasti attuali (BBCode).
func controls_text() -> String:
	var k := func(actions: Array, sep := " / ") -> String:
		return "[b]%s[/b]" % sep.join(actions.map(func(a): return Game.key_label(a)))
	return tr(CONTROLS) % [
		k.call(["move_forward", "move_left", "move_back", "move_right"], " "), k.call(["sprint"]),
		k.call(["crouch"]), k.call(["crouch_toggle"]),
		k.call(["jump"]), k.call(["lean_left", "lean_right"]),
		k.call(["attack"]), k.call(["frob"]),
		k.call(["weapon_1", "weapon_2"]), k.call(["reload"]), k.call(["medpatch"]),
		k.call(["pda"]), "[b]Esc[/b]", k.call(["toggle_pixel"]), k.call(["toggle_dither"]),
		k.call(["quicksave"]), k.call(["quickload"]),
	]


func _on_off(on: bool) -> String:
	return tr("ON") if on else tr("OFF")


# --- menu iniziale ---------------------------------------------------------------------
func show_start() -> void:
	var pc := _panel(1160, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	pc.add_child(h)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 580
	left.add_theme_constant_override("separation", 8)
	h.add_child(left)
	left.add_child(UITheme.label(tr("SERAPH PROTOCOL"), 40, UITheme.BORDER))
	left.add_child(UITheme.label(tr("vertical slice — FPS/RPG immersive sim"), 16, UITheme.DIM))
	left.add_child(_spacer(6))
	var brief := _rich(tr("Nysa Arcology, Level 14, night shift. Your contact, [color=#ffcc55]Vesper[/color], got you up the service elevator into the lab wing of [b]Seraph Biotek[/b].\n\nObjective: extract the [color=#ffcc55]SERAPH-7[/color] data core from Lab C and get back to the elevator.\n\nShadows are your allies: the [b]gem[/b] at the bottom shows how visible you are, the arcs beside it how much noise you make. Every obstacle has more than one solution: codes, keycards, hacking, vents, distractions... or the pistol."), 16)
	brief.custom_minimum_size.x = 570
	left.add_child(brief)
	left.add_child(_spacer(4))
	left.add_child(UITheme.label(tr("CONTROLS"), 16, UITheme.ACCENT))
	left.add_child(_rich(controls_text(), 14, 570))

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 500
	right.add_theme_constant_override("separation", 6)
	h.add_child(right)
	var top := HBoxContainer.new()
	right.add_child(top)
	var title := UITheme.label(tr("OPERATIVE PROFILE"), 20, UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_language_button(show_start))
	_st_pts = UITheme.label("", 16, UITheme.TEXT)
	right.add_child(_st_pts)
	_st_rows = VBoxContainer.new()
	right.add_child(_st_rows)
	_st_btn = UITheme.button(tr("START MISSION"), _begin, 300)
	_build_start_rows()
	right.add_child(_spacer(6))
	right.add_child(UITheme.label(tr("Later: spend cyber-modules at upgrade stations."), 13, UITheme.DIM))
	right.add_child(_st_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var latest := SaveGame.latest()
	var cont := UITheme.button(tr("Continue"), func(): Game.load_game(latest))
	cont.disabled = latest == ""
	row.add_child(cont)
	row.add_child(UITheme.button(tr("Load game"), open_load.bind(show_start)))
	row.add_child(UITheme.button(tr("Options"), open_options.bind(show_start)))
	row.add_child(UITheme.button(tr("Quit"), Game.quit_game))
	right.add_child(row)
	_show(pc, "start", false)
	dim.color = Color(0, 0.01, 0.01, 0.72)


func _build_start_rows() -> void:
	for c in _st_rows.get_children():
		c.queue_free()
	var used := 0
	for s in Game.SKILLS:
		used += int(Game.start_alloc[s])
	var left_pts: int = Game.START_POINTS - used
	_st_pts.text = tr("Points to assign: %d   (max %d per skill at start)") % [left_pts, Game.START_CAP]
	for s in Game.SKILLS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := UITheme.label(Game.skill_name(s), 17, UITheme.TEXT)
		name_l.custom_minimum_size.x = 170
		row.add_child(name_l)
		var pl := UITheme.label(UITheme.pips(int(Game.start_alloc[s]), Game.SKILL_MAX), 17, UITheme.GOOD)
		pl.custom_minimum_size.x = 80
		row.add_child(pl)
		var minus := UITheme.button(" - ", _alloc.bind(s, -1))
		minus.disabled = int(Game.start_alloc[s]) <= 0
		row.add_child(minus)
		var plus := UITheme.button(" + ", _alloc.bind(s, 1))
		plus.disabled = left_pts <= 0 or int(Game.start_alloc[s]) >= Game.START_CAP
		row.add_child(plus)
		_st_rows.add_child(row)
		var d := UITheme.label(Game.skill_desc(s), 13, UITheme.DIM, true)
		d.custom_minimum_size.x = 490
		_st_rows.add_child(d)
	_st_btn.text = tr("START MISSION") if left_pts == 0 else tr("START (unspent points: %d)") % left_pts


func _alloc(s: String, delta: int) -> void:
	Game.start_alloc[s] = clampi(int(Game.start_alloc[s]) + delta, 0, Game.START_CAP)
	_build_start_rows()


func _begin() -> void:
	Game.skills = Game.start_alloc.duplicate()
	Game.skills_changed.emit()
	if Game.player:
		Game.player.on_skills_changed()
	_clear()
	dim.color = Color(0, 0.01, 0.01, 0.6)
	Game.set_state(Game.State.PLAYING)
	if Game.level:
		Game.level.start_intro()
		if not Game.quick_start:
			Game.save_game("auto")   # autosalvataggio a inizio missione (non con F6 dall'editor)


# --- lingua ----------------------------------------------------------------------------
## Bottone che passa alla lingua successiva e poi ridisegna il pannello (rebuild).
func _language_button(rebuild: Callable) -> Button:
	return UITheme.button(tr("Language: %s") % Game.language_name(), func():
		Game.cycle_language()
		rebuild.call())


# --- pausa ----------------------------------------------------------------------------
func open_pause() -> void:
	var w := _window(tr("PAUSED"), 520, 0)
	var v: VBoxContainer = w[1]
	v.add_child(UITheme.button(tr("Resume"), close_panel))
	var sv := UITheme.button(tr("Save game"), open_save)
	v.add_child(sv)
	v.add_child(UITheme.button(tr("Load game"), open_load.bind(open_pause)))
	v.add_child(UITheme.button(tr("Options"), open_options.bind(open_pause)))
	v.add_child(UITheme.button(tr("PDA: objectives, logs, inventory  [%s]") % Game.key_label("pda"), open_pda))
	v.add_child(_spacer(6))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.add_child(UITheme.button(tr("Restart mission"), Game.restart))
	hb.add_child(UITheme.button(tr("Quit game"), Game.quit_game))
	v.add_child(hb)
	_show(w[0], "pause")
	sv.disabled = not Game.can_save()   # dopo _show: tornando da Opzioni o Carica il pannello aperto è ancora quello


# --- salva / carica --------------------------------------------------------------------
func open_save() -> void:
	var w := _window(tr("SAVE GAME"), 760, 0)
	var v: VBoxContainer = w[1]
	for i in SaveGame.MANUAL_SLOTS:
		v.add_child(_slot_row(str(i + 1), true))
	v.add_child(_spacer(4))
	v.add_child(UITheme.button(tr("Back  [Esc]"), close_panel))
	_return_to = open_pause
	_show(w[0], "save")


## back: il pannello a cui tornare (pausa o menu iniziale).
func open_load(back: Callable) -> void:
	var w := _window(tr("LOAD GAME"), 760, 0)
	var v: VBoxContainer = w[1]
	for slot in SaveGame.slots():
		v.add_child(_slot_row(slot, false))
	v.add_child(_spacer(4))
	v.add_child(UITheme.button(tr("Back  [Esc]"), close_panel))
	_return_to = back
	_show(w[0], "load", Game.state != Game.State.MENU)


func _slot_name(slot: String) -> String:
	match slot:
		"quick": return tr("Quicksave")
		"auto": return tr("Autosave")
	return tr("Slot %s") % slot


## Riga di uno slot: anteprima, nome, data e tempo di gioco, bottone Salva/Carica.
func _slot_row(slot: String, saving: bool) -> Control:
	var m := SaveGame.meta(slot)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(116, 67)
	frame.add_theme_stylebox_override("panel", UITheme.box(Color(0, 0.02, 0.02), UITheme.BORDER.darkened(0.35), 1, 2))
	var thumb := TextureRect.new()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	thumb.texture = SaveGame.thumbnail(slot) if not m.is_empty() else null
	frame.add_child(thumb)
	row.add_child(frame)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_child(UITheme.label(_slot_name(slot), 17, UITheme.ACCENT))
	var desc := tr("— empty —")
	if not m.is_empty():
		desc = tr("%s   time played %s   objectives %s") % [m.get("saved_at", "?"), Util.fmt_time(float(m.get("playtime", 0.0))), m.get("objectives", "?")]
	info.add_child(UITheme.label(desc, 14, UITheme.DIM))
	row.add_child(info)
	var b := UITheme.button("", func(): pass, 170)
	if saving:
		b.text = tr("Save") if m.is_empty() else tr("Overwrite")
		b.pressed.connect(func():
			if not m.is_empty() and not b.has_meta("armed"):
				b.set_meta("armed", true)   # sovrascrivere chiede un secondo clic
				b.text = tr("Click to confirm")
				return
			if Game.save_game(slot):
				open_save())
	else:
		b.text = tr("Load")
		b.disabled = m.is_empty()
		b.pressed.connect(func(): Game.load_game(slot))
	row.add_child(b)
	return row


# --- opzioni -----------------------------------------------------------------------------
## Pannello Opzioni a schede. back: il pannello a cui tornare (pausa o menu iniziale).
func open_options(back: Callable, tab := 0) -> void:
	var w := _window(tr("OPTIONS"), 860, 0)
	var v: VBoxContainer = w[1]
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(820, 470)
	v.add_child(tabs)
	var reopen := func(t: int): open_options(back, t)

	var game := VBoxContainer.new()
	game.name = "Game"
	game.add_theme_constant_override("separation", 10)
	tabs.add_child(game)
	game.add_child(_language_button(reopen.bind(0)))
	game.add_child(UITheme.button(tr("Captions for signs and writings: %s") % Game.env_captions_name(), func():
		Game.cycle_env_captions()
		reopen.call(0)))
	game.add_child(UITheme.label(tr("Captions: AUTO shows them only when a sign isn't in your language."), 13, UITheme.DIM, true))

	var video := VBoxContainer.new()
	video.name = "Video"
	video.add_theme_constant_override("separation", 10)
	tabs.add_child(video)
	video.add_child(UITheme.button(tr("Fullscreen: %s") % _on_off(Game.settings.fullscreen), func():
		Game.set_fullscreen(not Game.settings.fullscreen)
		reopen.call(1)))
	video.add_child(UITheme.button(tr("V-Sync: %s") % _on_off(Game.settings.vsync), func():
		Game.set_vsync(not Game.settings.vsync)
		reopen.call(1)))
	video.add_child(UITheme.button(tr("Internal resolution: %s  [%s]") % [Game.pixel_scale_name(Game.settings.pixel_scale), Game.key_label("toggle_pixel")], func():
		Game.cycle_pixel_scale()
		reopen.call(1)))
	video.add_child(UITheme.button(tr("15-bit dithering: %s  [%s]") % [_on_off(Game.settings.dither), Game.key_label("toggle_dither")], func():
		Game.toggle_dither()
		reopen.call(1)))

	var audio := VBoxContainer.new()
	audio.name = "Audio"
	tabs.add_child(audio)
	audio.add_child(_slider_row(tr("Volume"), 0.0, 1.0, Game.settings.volume, func(x):
		Game.settings.volume = x
		Sfx.set_master_volume(x)))

	var ctl := VBoxContainer.new()
	ctl.name = "Controls"
	ctl.add_theme_constant_override("separation", 6)
	tabs.add_child(ctl)
	ctl.add_child(_slider_row(tr("Mouse sensitivity"), 0.03, 0.4, Game.settings.sensitivity, func(x): Game.settings.sensitivity = x))
	var status := UITheme.label(_ctl_msg if _ctl_msg != "" else tr("Click a key to change it."), 14, UITheme.DIM)
	_ctl_msg = ""
	ctl.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ctl.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	for action in Game.ACTION_LABELS:
		var l := UITheme.label(tr(Game.ACTION_LABELS[action]), 15)
		l.custom_minimum_size.x = 330
		grid.add_child(l)
		var evs := Game.binding(action)
		for i in 2:
			var b := UITheme.button(Game.event_label(evs[i]), func(): pass, 200)
			b.name = "%s_%d" % [action, i]
			b.pressed.connect(func():
				if not _capture.is_empty() and is_instance_valid(_capture.button):
					_capture.button.text = _capture.label   # un altro tasto era in attesa
				_capture = {"action": action, "slot": i, "button": b, "label": b.text, "status": status,
					"t": Time.get_ticks_msec()}
				b.text = tr("Press a key…")
				status.text = tr("Esc: cancel   Backspace: clear"))
			grid.add_child(b)
	ctl.add_child(UITheme.button(tr("Restore default keys"), func():
		Game.reset_bindings()
		reopen.call(3)))

	for i in 4:
		tabs.set_tab_title(i, [tr("GAME"), tr("VIDEO"), tr("AUDIO"), tr("CONTROLS")][i])
	tabs.current_tab = tab
	v.add_child(UITheme.button(tr("Back  [Esc]"), close_panel))
	_return_to = back
	_show(w[0], "options", Game.state != Game.State.MENU)


func capturing_key() -> bool:
	return not _capture.is_empty()


## Il pannello Comandi aspetta un tasto: lo prende qui, prima di tutto il resto.
func _input(event: InputEvent) -> void:
	if _capture.is_empty():
		return
	var def: Array = []
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		if code == KEY_ESCAPE:
			_capture = {}
			get_viewport().set_input_as_handled()
			open_options(_return_to, 3)
			return
		if code != KEY_BACKSPACE and code != KEY_DELETE:
			def = ["key", int(code)]
	elif event is InputEventMouseButton and event.pressed:
		var b: Button = _capture.button
		if not is_instance_valid(b) or not b.get_global_rect().has_point(b.get_global_mouse_position()):
			# clic altrove (Indietro, un'altra scheda, un altro tasto...): niente
			# assegnazione, il clic fa quello che deve
			if is_instance_valid(b):
				b.text = _capture.label
			if is_instance_valid(_capture.status):
				_capture.status.text = tr("Click a key to change it.")
			_capture = {}
			return
		get_viewport().set_input_as_handled()
		if Time.get_ticks_msec() - int(_capture.t) < 300:
			return   # secondo clic di un doppio clic: non è una scelta
		def = ["mouse", int(event.button_index)]
	else:
		return
	get_viewport().set_input_as_handled()
	var action: String = _capture.action
	var slot := int(_capture.slot)
	var old: Array = Game.binding(action)[slot]
	var swapped := Game.set_binding(action, slot, def)
	_capture = {}
	var unbound := func(a: String) -> bool:
		return Game.binding(a).all(func(e): return e.is_empty())
	if swapped != "" and swapped != action:
		var other := tr(Game.ACTION_LABELS.get(swapped, swapped))
		if unbound.call(swapped):
			_ctl_msg = tr("Careful: «%s» has no key now.") % other
		elif old.is_empty():
			_ctl_msg = tr("Key removed from «%s».") % other
		else:
			_ctl_msg = tr("Swapped with «%s».") % other
	elif def.is_empty() and unbound.call(action):
		_ctl_msg = tr("Careful: «%s» has no key now.") % tr(Game.ACTION_LABELS.get(action, action))
	open_options(_return_to, 3)


## Blocchi dei dispositivi dopo un hacking fallito, per i salvataggi.
func save_state() -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	var out := {}
	for id in hack_lockouts:
		var n := instance_from_id(id) as Node
		if n != null and Game.level != null and float(hack_lockouts[id]) > now:
			out[String(Game.level.get_path_to(n))] = float(hack_lockouts[id]) - now
	return {"hack_lockouts": out}


func load_state(d: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var locks: Dictionary = d.get("hack_lockouts", {})
	for p in locks:
		var n := Game.level.get_node_or_null(NodePath(p))
		if n != null:
			hack_lockouts[n.get_instance_id()] = now + float(locks[p])


func _slider_row(label_text: String, mn: float, mx: float, val: float, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UITheme.label(label_text, 15)
	l.custom_minimum_size.x = 200
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = (mx - mn) / 100.0
	s.value = val
	s.custom_minimum_size = Vector2(320, 24)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(cb)
	s.drag_ended.connect(func(_changed: bool): Game.save_settings())
	row.add_child(s)
	return row


# --- PDA ----------------------------------------------------------------------------------
func open_pda(tab := 0) -> void:
	Sfx.play_ui("ui_open", -4.0)
	var pc := _panel(1000, 620)
	var tabs := TabContainer.new()
	pc.add_child(tabs)

	var obj := VBoxContainer.new()
	obj.name = "Objectives"
	obj.add_theme_constant_override("separation", 8)
	tabs.add_child(obj)
	for o in Game.objectives:
		var mark := "[ ]"
		var col := UITheme.TEXT
		if o.state == "done":
			mark = "[✓]"
			col = UITheme.GOOD
		elif o.state == "failed":
			mark = "[✗]"
			col = UITheme.DANGER
		var l := UITheme.label("%s %s%s" % [mark, tr("(optional)") + " " if o.optional else "", tr(o.text)], 17, col, true)
		l.custom_minimum_size.x = 940
		obj.add_child(l)
	obj.add_child(_spacer(12))
	obj.add_child(UITheme.label(tr("Time: %s    Secrets: %d/2    Alarms: %d    Times spotted: %d") % [Util.fmt_time(Game.stats.time), Game.secrets_found.size(), Game.stats.alarms, Game.stats.detections], 15, UITheme.DIM))

	var logs := HBoxContainer.new()
	logs.name = "Logs"
	logs.add_theme_constant_override("separation", 12)
	tabs.add_child(logs)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(300, 480)
	list.focus_mode = Control.FOCUS_NONE
	logs.add_child(list)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	logs.add_child(scroll)
	var reader := _rich("[color=#6a9c98]%s[/color]" % tr("Select a log."), 16)
	reader.custom_minimum_size.x = 600
	scroll.add_child(reader)
	for id in Game.logs_read:
		list.add_item(tr(Logs.ENTRIES.get(id, {}).get("title", id)))
	list.item_selected.connect(func(i: int):
		reader.text = _log_bbcode(Game.logs_read[i]))
	if Game.logs_read.size() > 0:
		list.select(Game.logs_read.size() - 1)
		reader.text = _log_bbcode(Game.logs_read[Game.logs_read.size() - 1])

	var inv := VBoxContainer.new()
	inv.name = "Inventory"
	inv.add_theme_constant_override("separation", 8)
	tabs.add_child(inv)
	inv.add_child(UITheme.label(tr("Wrench — melee. Hit an unaware guard from behind for a silent KO."), 16))
	inv.add_child(UITheme.label(tr("9mm pistol — magazine %d/%d, reserve %d.") % [Game.ammo_mag, Game.MAG_SIZE, Game.ammo_reserve], 16))
	var med_row := HBoxContainer.new()
	med_row.add_child(UITheme.label(tr("Medipatch x%d  (+40 health)") % Game.medpatches + "   ", 16))
	var use_b := UITheme.button(tr("Use"), func():
		if Game.player:
			Game.player.use_medpatch()
		open_pda(2))
	use_b.disabled = Game.medpatches <= 0
	med_row.add_child(use_b)
	inv.add_child(med_row)
	inv.add_child(UITheme.label(tr("Cyber-modules: %d    Credits: %d ¢") % [Game.modules, Game.credits], 16))
	inv.add_child(_spacer(6))
	inv.add_child(UITheme.label(tr("KEYCARDS AND MISSION ITEMS"), 15, UITheme.ACCENT))
	if Game.keycards.is_empty() and Game.items.is_empty():
		inv.add_child(UITheme.label(tr("— none —"), 15, UITheme.DIM))
	for k in Game.keycards:
		inv.add_child(UITheme.label("▪ " + Game.keycard_name(k), 16))
	if Game.has_item("core"):
		inv.add_child(UITheme.label("▪ " + tr("SERAPH-7 data core (it's warm. And it hums.)"), 16, UITheme.BORDER))

	var ch := VBoxContainer.new()
	ch.name = "Character"
	ch.add_theme_constant_override("separation", 6)
	tabs.add_child(ch)
	ch.add_child(UITheme.label(tr("Cyber-modules available: %d — spend them at an upgrade station.") % Game.modules, 16, UITheme.ACCENT))
	for s in Game.SKILLS:
		ch.add_child(UITheme.label("%-16s %s" % [Game.skill_name(s), UITheme.pips(Game.skill(s), Game.SKILL_MAX)], 18, UITheme.TEXT))
		var d := UITheme.label(Game.skill_desc(s), 13, UITheme.DIM, true)
		d.custom_minimum_size.x = 940
		ch.add_child(d)
	for i in 4:
		tabs.set_tab_title(i, [tr("OBJECTIVES"), tr("LOGS"), tr("INVENTORY"), tr("CHARACTER")][i])
	tabs.current_tab = tab
	_show(pc, "pda")


func _log_bbcode(id: String) -> String:
	var e: Dictionary = Logs.ENTRIES.get(id, {})
	return "[color=#ffcc55][b]%s[/b][/color]\n[color=#6a9c98]%s[/color]\n\n%s" % [tr(e.get("title", id)), tr(e.get("author", "")), tr(e.get("text", ""))]


func show_log(id: String) -> void:
	var w := _window(tr("LOG"), 760, 0)
	var v: VBoxContainer = w[1]
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var r := _rich(_log_bbcode(id), 17)
	r.custom_minimum_size.x = 700
	scroll.add_child(r)
	v.add_child(UITheme.button(tr("Close  [Esc]"), close_panel))
	_show(w[0], "log")


# --- serrature / tastierino ------------------------------------------------------------
## target.get_lock_info() restituisce testi già tradotti (title, keycard_name, note).
func open_lock(target: Node) -> void:
	var info: Dictionary = target.get_lock_info()
	var w := _window(tr("ACCESS DENIED — %s") % String(info.get("title", "")), 560, 0)
	var v: VBoxContainer = w[1]
	if info.get("keycard", "") != "":
		var has: bool = Game.has_keycard(info.keycard)
		v.add_child(UITheme.label(tr("Keycard: %s  %s") % [info.get("keycard_name", info.keycard), tr("(in inventory)") if has else tr("(missing)")], 16, UITheme.GOOD if has else UITheme.DIM))
	if info.has("code"):
		v.add_child(UITheme.label(tr("Keypad — enter the 4-digit code:"), 16))
		var disp := LineEdit.new()
		disp.max_length = 4
		disp.alignment = HORIZONTAL_ALIGNMENT_CENTER
		disp.add_theme_font_size_override("font_size", 30)
		disp.custom_minimum_size = Vector2(200, 50)
		v.add_child(disp)
		var submit := func(_t := ""):
			if target.try_code(disp.text):
				Sfx.play_ui("granted")
				Game.notify(tr("Code accepted."), UITheme.GOOD)
				_clear()
				Game.set_state(Game.State.PLAYING)
			else:
				Sfx.play_ui("denied")
				disp.text = ""
				disp.placeholder_text = tr("WRONG")
		disp.text_submitted.connect(submit)
		disp.text_changed.connect(func(t: String):
			var clean := ""
			for ch in t:
				if ch >= "0" and ch <= "9":
					clean += ch
			if clean != t:
				disp.text = clean
				disp.caret_column = clean.length()
			Sfx.play_ui("keypad", -6.0))
		var grid := GridContainer.new()
		grid.columns = 3
		for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK"]:
			var b := UITheme.button(k, func():
				if k == "C":
					disp.text = ""
				elif k == "OK":
					submit.call()
				elif disp.text.length() < 4:
					disp.text += k
					Sfx.play_ui("keypad", -6.0), 70)
			b.custom_minimum_size.y = 40
			grid.add_child(b)
		v.add_child(grid)
		disp.call_deferred("grab_focus")
	if info.has("hack"):
		v.add_child(_spacer(4))
		var req: int = info.hack
		var sk := Game.skill("hacking")
		var lock_until: float = hack_lockouts.get(target.get_instance_id(), 0.0)
		var now := Time.get_ticks_msec() / 1000.0
		v.add_child(UITheme.label(tr("Hacking required: %d — yours: %d") % [req, sk], 16, UITheme.GOOD if sk >= req else UITheme.DANGER))
		if info.has("note"):
			v.add_child(UITheme.label(info.note, 13, UITheme.DIM, true))
		var hb := UITheme.button(tr("START INTRUSION"), func(): open_hack(target, info))
		if sk < req:
			hb.disabled = true
			hb.text = tr("Insufficient skill")
		elif lock_until > now:
			hb.disabled = true
			hb.text = tr("Device locked out (%ds)") % int(ceil(lock_until - now))
		v.add_child(hb)
	v.add_child(_spacer(4))
	v.add_child(UITheme.button(tr("Close  [Esc]"), close_panel))
	_show(w[0], "lock")


# --- minigioco di hacking --------------------------------------------------------------
## Collega un percorso di nodi da sinistra a destra: ogni nodo deve toccare il
## precedente (anche in diagonale). Ogni tentativo riesce con probabilità che
## dipende dalla skill; i nodi falliti bruciano. Troppi errori o un vicolo
## cieco = intrusione fallita (e, sui sistemi protetti, possibile allarme).
func open_hack(target: Node, info: Dictionary) -> void:
	var sk := Game.skill("hacking")
	var diff: int = info.get("difficulty", 1)
	_hk = {
		"target": target, "info": info, "cols": 5, "rows": 3,
		"p": clampf(0.55 + 0.12 * (sk - diff), 0.3, 0.92),
		"max_fail": max(1, 2 + sk - diff), "fails": 0,
		"grid": [], "last": Vector2i(-1, -1), "started": false, "done": false, "buttons": [],
	}
	for c in 5:
		var col := []
		for r in 3:
			col.append(0)
		_hk.grid.append(col)
	var w := _window(tr("INTRUSION — %s") % String(info.get("title", "")), 640, 0)
	var v: VBoxContainer = w[1]
	var help := UITheme.label(tr("Build a path from left to right. Each node must touch the previous one (diagonals count). Failed nodes burn out."), 14, UITheme.DIM, true)
	help.custom_minimum_size.x = 600
	v.add_child(help)
	var status := UITheme.label("", 16, UITheme.ACCENT)
	v.add_child(status)
	_hk["status"] = status
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var cc := CenterContainer.new()
	cc.add_child(grid)
	v.add_child(cc)
	var btns := {}
	for r in 3:
		for c in 5:
			var b := Button.new()
			b.custom_minimum_size = Vector2(90, 64)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 26)
			b.pressed.connect(_hack_click.bind(c, r))
			grid.add_child(b)
			btns[Vector2i(c, r)] = b
	_hk["buttons"] = btns
	v.add_child(UITheme.button(tr("Abort  [Esc]"), close_panel))
	_show(w[0], "hack")
	_hack_refresh()


func _hack_clickable(c: int, r: int) -> bool:
	if _hk.done or _hk.grid[c][r] != 0:
		return false
	var last: Vector2i = _hk.last
	if last.x < 0:
		return c == 0
	return c == last.x + 1 and absi(r - last.y) <= 1


func _hack_refresh() -> void:
	var any := false
	for key in _hk.buttons:
		var b: Button = _hk.buttons[key]
		var st: int = _hk.grid[key.x][key.y]
		var can := _hack_clickable(key.x, key.y)
		any = any or can
		b.disabled = not can
		match st:
			1:
				b.text = "◆"
				b.add_theme_color_override("font_disabled_color", UITheme.GOOD)
			2:
				b.text = "✕"
				b.add_theme_color_override("font_disabled_color", UITheme.DANGER)
			_:
				b.text = "◇"
				b.add_theme_color_override("font_disabled_color", Color(0.25, 0.35, 0.35))
	var left: int = _hk.max_fail - _hk.fails
	_hk.status.text = tr("Chance per node: %d%%    Mistakes left: %d") % [int(_hk.p * 100.0), max(left, 0)]
	if not any and not _hk.done:
		_hack_lose()


func _hack_click(c: int, r: int) -> void:
	if not _hack_clickable(c, r):
		return
	_hk.started = true
	if randf() < _hk.p:
		_hk.grid[c][r] = 1
		_hk.last = Vector2i(c, r)
		Sfx.play_ui("hack_ok")
		if c == _hk.cols - 1:
			_hack_win()
			return
	else:
		_hk.grid[c][r] = 2
		_hk.fails += 1
		Sfx.play_ui("hack_fail")
		if _hk.fails > _hk.max_fail:
			_hack_refresh()
			_hack_lose()
			return
	_hack_refresh()


func _hack_win() -> void:
	_hk.done = true
	_hack_refresh()
	_hk.status.text = tr("ACCESS GRANTED")
	_hk.status.add_theme_color_override("font_color", UITheme.GOOD)
	Sfx.play_ui("hack_win")
	var target: Node = _hk.target
	get_tree().create_timer(0.7, true).timeout.connect(func():
		_clear()
		Game.set_state(Game.State.PLAYING)
		if is_instance_valid(target):
			target.on_hack_result(true))


func _hack_lose() -> void:
	if _hk.get("done", false):
		return
	_hk.done = true
	_hk.status.text = tr("INTRUSION FAILED — device locked for 20s")
	_hk.status.add_theme_color_override("font_color", UITheme.DANGER)
	Sfx.play_ui("denied")
	var target: Node = _hk.target
	var info: Dictionary = _hk.info
	hack_lockouts[target.get_instance_id()] = Time.get_ticks_msec() / 1000.0 + 20.0
	get_tree().create_timer(1.1, true).timeout.connect(func():
		_clear()
		Game.set_state(Game.State.PLAYING)
		if info.get("alarm_on_fail", false) and randf() < 0.6 and Game.player:
			Game.raise_alarm(Game.player.global_position, tr("ICE: intrusion detected."))
		if is_instance_valid(target):
			target.on_hack_result(false))


# --- stazione di potenziamento --------------------------------------------------------
func open_upgrade() -> void:
	var w := _window(tr("NEURAL UPGRADE STATION"), 760, 0)
	var v: VBoxContainer = w[1]
	v.add_child(UITheme.label(tr("Cyber-modules available: %d") % Game.modules, 18, UITheme.ACCENT))
	for s in Game.SKILLS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var n := UITheme.label(Game.skill_name(s), 18)
		n.custom_minimum_size.x = 190
		row.add_child(n)
		var pl := UITheme.label(UITheme.pips(Game.skill(s), Game.SKILL_MAX), 18, UITheme.GOOD)
		pl.custom_minimum_size.x = 90
		row.add_child(pl)
		var lvl := Game.skill(s)
		var b: Button
		if lvl >= Game.SKILL_MAX:
			b = UITheme.button(tr("MAX"), func(): pass)
			b.disabled = true
		else:
			var cost := Game.upgrade_cost(s)
			b = UITheme.button(tr("UPGRADE (cost: %d)") % cost, func():
				if Game.try_upgrade(s):
					Sfx.play_ui("upgrade")
					Game.notify(tr("%s raised to level %d.") % [Game.skill_name(s), Game.skill(s)], UITheme.GOOD)
				open_upgrade())
			b.disabled = Game.modules < cost
		row.add_child(b)
		v.add_child(row)
		var d := UITheme.label(Game.skill_desc(s), 13, UITheme.DIM, true)
		d.custom_minimum_size.x = 720
		v.add_child(d)
	v.add_child(UITheme.button(tr("Close  [Esc]"), close_panel))
	_show(w[0], "upgrade")


# --- terminali ------------------------------------------------------------------------
## Titolo ed etichette delle opzioni arrivano già tradotti dal terminale.
func open_terminal(target: Node) -> void:
	var w := _window(target.get_terminal_title(), 660, 0)
	var v: VBoxContainer = w[1]
	for opt in target.get_terminal_options():
		var id: String = opt.id
		var b := UITheme.button("> " + String(opt.label), func():
			target.terminal_action(id)
			if current_kind == "terminal":
				open_terminal(target))
		b.disabled = not opt.enabled
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
	v.add_child(_spacer(6))
	v.add_child(UITheme.button(tr("Disconnect  [Esc]"), close_panel))
	_show(w[0], "terminal")


# --- fine partita ----------------------------------------------------------------------
func _stats_text() -> String:
	var st := Game.stats
	return tr("Time: %s\nGuards killed: %d    Knocked out: %d    Pickpockets: %d\nAlarms: %d    Times spotted: %d    Successful hacks: %d\nSecrets: %d/2    Credits: %d ¢") % [
		Util.fmt_time(st.time), st.kills, st.kos, st.pickpockets, st.alarms, st.detections, st.hacks,
		Game.secrets_found.size(), Game.credits]


func show_death() -> void:
	var w := _window(tr("SIGNAL LOST"), 620, 0)
	var v: VBoxContainer = w[1]
	w[1].get_child(0).add_theme_color_override("font_color", UITheme.DANGER)
	v.add_child(UITheme.label(tr("Seraph Biotek thanks you for your involuntary cooperation."), 16, UITheme.DIM, true))
	v.add_child(_rich(_stats_text(), 15, 580))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var latest := SaveGame.latest()
	if latest != "":
		hb.add_child(UITheme.button(tr("Load last save"), func(): Game.load_game(latest)))
	hb.add_child(UITheme.button(tr("Restart"), Game.restart))
	hb.add_child(UITheme.button(tr("Quit"), Game.quit_game))
	v.add_child(hb)
	_show(w[0], "death", false)


func show_complete() -> void:
	var w := _window(tr("EXTRACTION SUCCESSFUL"), 860, 0)
	var v: VBoxContainer = w[1]
	var txt := _rich(tr("[color=#ffcc55]VESPER:[/color] The core is mine, and the payment's already in your account. Nice work, really.\n...Wait. Why is the core [i]transmitting[/i]? Who— "), 16)
	txt.custom_minimum_size.x = 820
	v.add_child(txt)
	v.add_child(_spacer(4))
	for o in Game.objectives:
		var ok: bool = o.state == "done"
		v.add_child(UITheme.label("%s %s" % ["[✓]" if ok else ("[✗]" if o.state == "failed" else "[ ]"), tr(o.text)], 15, UITheme.GOOD if ok else (UITheme.DANGER if o.state == "failed" else UITheme.DIM)))
	v.add_child(_spacer(4))
	v.add_child(_rich(_stats_text(), 15, 580))
	v.add_child(UITheme.label(tr("RATING: %s") % Game.rating(), 22, UITheme.BORDER))
	v.add_child(UITheme.label(tr("End of the vertical slice. Thanks for playing."), 14, UITheme.DIM))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.add_child(UITheme.button(tr("Play again"), Game.restart))
	hb.add_child(UITheme.button(tr("Quit"), Game.quit_game))
	v.add_child(hb)
	_show(w[0], "complete", false)
