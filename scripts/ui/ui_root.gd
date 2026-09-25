extends CanvasLayer
## Gestore dei pannelli a schermo: menu iniziale (con allocazione delle skill),
## pausa/opzioni, PDA, serrature/tastierino, minigioco di hacking, stazione di
## potenziamento, terminali, lettore registri, schermate di morte e di fine.

const CONTROLS := "[b]WASD[/b] muovi   [b]Shift[/b] corri   [b]Ctrl[/b] (tieni) / [b]C[/b] (alterna) accovacciati\n[b]Spazio[/b] salta / aggrappati alle sporgenze (mantle)   [b]Q / E[/b] sporgiti\n[b]Mouse sx[/b] attacca · lancia   [b]Mouse dx[/b] o [b]F[/b] interagisci (frob) · posa\n[b]1 / 2[/b] o rotella: chiave inglese / pistola   [b]R[/b] ricarica   [b]H[/b] medipatch\n[b]Tab[/b] PDA   [b]Esc[/b] pausa   [b]F2[/b] risoluzione interna   [b]F3[/b] dithering"

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


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.ui = self
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	if current != null:
		current.queue_free()
	current = null
	current_kind = ""
	dim.visible = false


func close_panel() -> void:
	if current_kind == "hack" and _hk.get("started", false) and not _hk.get("done", false):
		_hack_lose()
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
	left.add_child(UITheme.label("PROTOCOLLO SERAPH", 40, UITheme.BORDER))
	left.add_child(UITheme.label("vertical slice — immersive sim FPS/RPG", 16, UITheme.DIM))
	left.add_child(_spacer(6))
	var brief := _rich("Arcologia Nysa, livello 14, turno di notte. Il tuo contatto, [color=#ffcc55]Vesper[/color], ti ha fatto salire con l'ascensore di servizio nell'ala laboratori della [b]Seraph Biotek[/b].\n\nObiettivo: estrarre il nucleo dati [color=#ffcc55]SERAPH-7[/color] dal Laboratorio C e tornare all'ascensore.\n\nLe ombre sono tue alleate: la [b]gemma[/b] in basso ti dice quanto sei visibile, gli archi accanto quanto rumore fai. Ogni ostacolo ha più di una soluzione: codici, tessere, hacking, condotti, distrazioni... o la pistola.", 16)
	brief.custom_minimum_size.x = 570
	left.add_child(brief)
	left.add_child(_spacer(4))
	left.add_child(UITheme.label("COMANDI", 16, UITheme.ACCENT))
	left.add_child(_rich(CONTROLS, 14, 570))

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 500
	right.add_theme_constant_override("separation", 6)
	h.add_child(right)
	right.add_child(UITheme.label("PROFILO DELL'OPERATIVO", 20, UITheme.ACCENT))
	_st_pts = UITheme.label("", 16, UITheme.TEXT)
	right.add_child(_st_pts)
	_st_rows = VBoxContainer.new()
	right.add_child(_st_rows)
	_st_btn = UITheme.button("INIZIA LA MISSIONE", _begin, 300)
	_build_start_rows()
	right.add_child(_spacer(6))
	right.add_child(UITheme.label("Altri potenziamenti: cyber-moduli + stazioni.", 13, UITheme.DIM))
	right.add_child(_st_btn)
	_show(pc, "start", false)
	dim.color = Color(0, 0.01, 0.01, 0.72)


func _build_start_rows() -> void:
	for c in _st_rows.get_children():
		c.queue_free()
	var used := 0
	for s in Game.SKILLS:
		used += int(Game.start_alloc[s])
	var left_pts: int = Game.START_POINTS - used
	_st_pts.text = "Punti da assegnare: %d   (max %d per skill all'inizio)" % [left_pts, Game.START_CAP]
	for s in Game.SKILLS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := UITheme.label(Game.SKILL_NAMES[s], 17, UITheme.TEXT)
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
		var d := UITheme.label(Game.SKILL_DESC[s], 13, UITheme.DIM, true)
		d.custom_minimum_size.x = 490
		_st_rows.add_child(d)
	_st_btn.text = "INIZIA LA MISSIONE" if left_pts == 0 else "INIZIA (punti non spesi: %d)" % left_pts


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


# --- pausa ----------------------------------------------------------------------------
func open_pause() -> void:
	var w := _window("PAUSA", 620, 0)
	var v: VBoxContainer = w[1]
	v.add_child(UITheme.button("Riprendi", close_panel))
	v.add_child(UITheme.button("PDA: obiettivi, registri, inventario  [Tab]", open_pda))
	v.add_child(_spacer(4))
	v.add_child(UITheme.label("OPZIONI", 16, UITheme.ACCENT))
	v.add_child(_slider_row("Sensibilità mouse", 0.03, 0.4, Game.settings.sensitivity, func(x): Game.settings.sensitivity = x))
	v.add_child(_slider_row("Volume", 0.0, 1.0, Game.settings.volume, func(x):
		Game.settings.volume = x
		Sfx.set_master_volume(x)))
	var px_btn := UITheme.button("", func(): pass)
	var dt_btn := UITheme.button("", func(): pass)
	var refresh := func():
		var s: int = Game.settings.pixel_scale
		px_btn.text = "Risoluzione interna: %s  [F2]" % ["1280x720 (nativa)", "640x360 (default)", "427x240", "320x180"][s - 1]
		dt_btn.text = "Dithering a 15 bit: %s  [F3]" % ("SÌ" if Game.settings.dither else "NO")
	px_btn.pressed.connect(func():
		Game.cycle_pixel_scale()
		refresh.call())
	dt_btn.pressed.connect(func():
		Game.toggle_dither()
		refresh.call())
	refresh.call()
	v.add_child(px_btn)
	v.add_child(dt_btn)
	v.add_child(_spacer(4))
	v.add_child(UITheme.label("COMANDI", 16, UITheme.ACCENT))
	v.add_child(_rich(CONTROLS, 13, 590))
	v.add_child(_spacer(4))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.add_child(UITheme.button("Ricomincia missione", Game.restart))
	hb.add_child(UITheme.button("Esci dal gioco", func(): get_tree().quit()))
	v.add_child(hb)
	_show(w[0], "pause")


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
	row.add_child(s)
	return row


# --- PDA ----------------------------------------------------------------------------------
func open_pda(tab := 0) -> void:
	Sfx.play_ui("ui_open", -4.0)
	var pc := _panel(1000, 620)
	var tabs := TabContainer.new()
	pc.add_child(tabs)

	var obj := VBoxContainer.new()
	obj.name = "OBIETTIVI"
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
		var l := UITheme.label("%s %s%s" % [mark, "(opzionale) " if o.optional else "", o.text], 17, col, true)
		l.custom_minimum_size.x = 940
		obj.add_child(l)
	obj.add_child(_spacer(12))
	obj.add_child(UITheme.label("Tempo: %s    Segreti: %d/2    Allarmi: %d    Avvistamenti: %d" % [Util.fmt_time(Game.stats.time), Game.secrets_found.size(), Game.stats.alarms, Game.stats.detections], 15, UITheme.DIM))

	var logs := HBoxContainer.new()
	logs.name = "REGISTRI"
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
	var reader := _rich("[color=#6a9c98]Seleziona un registro.[/color]", 16)
	reader.custom_minimum_size.x = 600
	scroll.add_child(reader)
	for id in Game.logs_read:
		list.add_item(Logs.ENTRIES.get(id, {}).get("title", id))
	list.item_selected.connect(func(i: int):
		reader.text = _log_bbcode(Game.logs_read[i]))
	if Game.logs_read.size() > 0:
		list.select(Game.logs_read.size() - 1)
		reader.text = _log_bbcode(Game.logs_read[Game.logs_read.size() - 1])

	var inv := VBoxContainer.new()
	inv.name = "INVENTARIO"
	inv.add_theme_constant_override("separation", 8)
	tabs.add_child(inv)
	inv.add_child(UITheme.label("Chiave inglese — mischia. Alle spalle di una guardia ignara: KO silenzioso.", 16))
	inv.add_child(UITheme.label("Pistola 9mm — caricatore %d/%d, riserva %d." % [Game.ammo_mag, Game.MAG_SIZE, Game.ammo_reserve], 16))
	var med_row := HBoxContainer.new()
	med_row.add_child(UITheme.label("Medipatch x%d  (+40 salute)   " % Game.medpatches, 16))
	var use_b := UITheme.button("Usa", func():
		if Game.player:
			Game.player.use_medpatch()
		open_pda(2))
	use_b.disabled = Game.medpatches <= 0
	med_row.add_child(use_b)
	inv.add_child(med_row)
	inv.add_child(UITheme.label("Cyber-moduli: %d    Crediti: %d ¢" % [Game.modules, Game.credits], 16))
	inv.add_child(_spacer(6))
	inv.add_child(UITheme.label("TESSERE E OGGETTI DI MISSIONE", 15, UITheme.ACCENT))
	if Game.keycards.is_empty() and Game.items.is_empty():
		inv.add_child(UITheme.label("— nessuno —", 15, UITheme.DIM))
	for k in Game.keycards:
		inv.add_child(UITheme.label("▪ " + String(Game.keycards[k]), 16))
	if Game.has_item("core"):
		inv.add_child(UITheme.label("▪ Nucleo dati SERAPH-7 (è tiepido. E vibra.)", 16, UITheme.BORDER))

	var ch := VBoxContainer.new()
	ch.name = "PERSONAGGIO"
	ch.add_theme_constant_override("separation", 6)
	tabs.add_child(ch)
	ch.add_child(UITheme.label("Cyber-moduli disponibili: %d — spendili in una stazione di potenziamento." % Game.modules, 16, UITheme.ACCENT))
	for s in Game.SKILLS:
		ch.add_child(UITheme.label("%-16s %s" % [Game.SKILL_NAMES[s], UITheme.pips(Game.skill(s), Game.SKILL_MAX)], 18, UITheme.TEXT))
		var d := UITheme.label(Game.SKILL_DESC[s], 13, UITheme.DIM, true)
		d.custom_minimum_size.x = 940
		ch.add_child(d)
	tabs.current_tab = tab
	_show(pc, "pda")


func _log_bbcode(id: String) -> String:
	var e: Dictionary = Logs.ENTRIES.get(id, {})
	return "[color=#ffcc55][b]%s[/b][/color]\n[color=#6a9c98]%s[/color]\n\n%s" % [e.get("title", id), e.get("author", ""), e.get("text", "")]


func show_log(id: String) -> void:
	var w := _window("REGISTRO", 760, 0)
	var v: VBoxContainer = w[1]
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var r := _rich(_log_bbcode(id), 17)
	r.custom_minimum_size.x = 700
	scroll.add_child(r)
	v.add_child(UITheme.button("Chiudi  [Esc]", close_panel))
	_show(w[0], "log")


# --- serrature / tastierino ------------------------------------------------------------
func open_lock(target: Node) -> void:
	var info: Dictionary = target.get_lock_info()
	var w := _window("ACCESSO NEGATO — " + String(info.get("title", "")), 560, 0)
	var v: VBoxContainer = w[1]
	if info.get("keycard", "") != "":
		var has: bool = Game.has_keycard(info.keycard)
		v.add_child(UITheme.label("Tessera: %s  %s" % [info.get("keycard_name", info.keycard), "(ce l'hai)" if has else "(non ce l'hai)"], 16, UITheme.GOOD if has else UITheme.DIM))
	if info.has("code"):
		v.add_child(UITheme.label("Tastierino — inserisci il codice a 4 cifre:", 16))
		var disp := LineEdit.new()
		disp.max_length = 4
		disp.alignment = HORIZONTAL_ALIGNMENT_CENTER
		disp.add_theme_font_size_override("font_size", 30)
		disp.custom_minimum_size = Vector2(200, 50)
		v.add_child(disp)
		var submit := func(_t := ""):
			if target.try_code(disp.text):
				Sfx.play_ui("granted")
				Game.notify("Codice accettato.", UITheme.GOOD)
				_clear()
				Game.set_state(Game.State.PLAYING)
			else:
				Sfx.play_ui("denied")
				disp.text = ""
				disp.placeholder_text = "ERRATO"
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
		v.add_child(UITheme.label("Hacking richiesto: %d — il tuo: %d" % [req, sk], 16, UITheme.GOOD if sk >= req else UITheme.DANGER))
		if info.has("note"):
			v.add_child(UITheme.label(info.note, 13, UITheme.DIM, true))
		var hb := UITheme.button("AVVIA INTRUSIONE", func(): open_hack(target, info))
		if sk < req:
			hb.disabled = true
			hb.text = "Skill insufficiente"
		elif lock_until > now:
			hb.disabled = true
			hb.text = "Dispositivo in blocco (%ds)" % int(ceil(lock_until - now))
		v.add_child(hb)
	v.add_child(_spacer(4))
	v.add_child(UITheme.button("Chiudi  [Esc]", close_panel))
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
	var w := _window("INTRUSIONE — " + String(info.get("title", "")), 640, 0)
	var v: VBoxContainer = w[1]
	var help := UITheme.label("Crea un percorso da sinistra a destra. Ogni nodo deve toccare il precedente (anche in diagonale). I nodi falliti bruciano.", 14, UITheme.DIM, true)
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
	v.add_child(UITheme.button("Interrompi  [Esc]", close_panel))
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
	_hk.status.text = "Probabilità per nodo: %d%%    Errori tollerati: %d" % [int(_hk.p * 100.0), max(left, 0)]
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
	_hk.status.text = "ACCESSO OTTENUTO"
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
	_hk.status.text = "INTRUSIONE FALLITA — dispositivo bloccato per 20 s"
	_hk.status.add_theme_color_override("font_color", UITheme.DANGER)
	Sfx.play_ui("denied")
	var target: Node = _hk.target
	var info: Dictionary = _hk.info
	hack_lockouts[target.get_instance_id()] = Time.get_ticks_msec() / 1000.0 + 20.0
	get_tree().create_timer(1.1, true).timeout.connect(func():
		_clear()
		Game.set_state(Game.State.PLAYING)
		if info.get("alarm_on_fail", false) and randf() < 0.6 and Game.player:
			Game.raise_alarm(Game.player.global_position, "ICE: intrusione rilevata.")
		if is_instance_valid(target):
			target.on_hack_result(false))


# --- stazione di potenziamento --------------------------------------------------------
func open_upgrade() -> void:
	var w := _window("STAZIONE DI POTENZIAMENTO NEURALE", 760, 0)
	var v: VBoxContainer = w[1]
	v.add_child(UITheme.label("Cyber-moduli disponibili: %d" % Game.modules, 18, UITheme.ACCENT))
	for s in Game.SKILLS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var n := UITheme.label(Game.SKILL_NAMES[s], 18)
		n.custom_minimum_size.x = 190
		row.add_child(n)
		var pl := UITheme.label(UITheme.pips(Game.skill(s), Game.SKILL_MAX), 18, UITheme.GOOD)
		pl.custom_minimum_size.x = 90
		row.add_child(pl)
		var lvl := Game.skill(s)
		var b: Button
		if lvl >= Game.SKILL_MAX:
			b = UITheme.button("MASSIMO", func(): pass)
			b.disabled = true
		else:
			var cost := Game.upgrade_cost(s)
			b = UITheme.button("POTENZIA (%d moduli)" % cost, func():
				if Game.try_upgrade(s):
					Sfx.play_ui("upgrade")
					Game.notify("%s portata a livello %d." % [Game.SKILL_NAMES[s], Game.skill(s)], UITheme.GOOD)
				open_upgrade())
			b.disabled = Game.modules < cost
		row.add_child(b)
		v.add_child(row)
		var d := UITheme.label(Game.SKILL_DESC[s], 13, UITheme.DIM, true)
		d.custom_minimum_size.x = 720
		v.add_child(d)
	v.add_child(UITheme.button("Chiudi  [Esc]", close_panel))
	_show(w[0], "upgrade")


# --- terminali ------------------------------------------------------------------------
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
	v.add_child(UITheme.button("Disconnetti  [Esc]", close_panel))
	_show(w[0], "terminal")


# --- fine partita ----------------------------------------------------------------------
func _stats_text() -> String:
	var st := Game.stats
	return "Tempo: %s\nGuardie uccise: %d    Messe KO: %d    Borseggi: %d\nAllarmi: %d    Volte avvistato: %d    Hack riusciti: %d\nSegreti: %d/2    Crediti: %d ¢" % [
		Util.fmt_time(st.time), st.kills, st.kos, st.pickpockets, st.alarms, st.detections, st.hacks,
		Game.secrets_found.size(), Game.credits]


func show_death() -> void:
	var w := _window("SEGNALE PERSO", 620, 0)
	var v: VBoxContainer = w[1]
	w[1].get_child(0).add_theme_color_override("font_color", UITheme.DANGER)
	v.add_child(UITheme.label("La Seraph Biotek ringrazia per la collaborazione involontaria.", 16, UITheme.DIM, true))
	v.add_child(_rich(_stats_text(), 15, 580))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.add_child(UITheme.button("Ricomincia", Game.restart))
	hb.add_child(UITheme.button("Esci", func(): get_tree().quit()))
	v.add_child(hb)
	_show(w[0], "death", false)


func show_complete() -> void:
	var w := _window("ESTRAZIONE RIUSCITA", 860, 0)
	var v: VBoxContainer = w[1]
	var txt := _rich("[color=#ffcc55]VESPER:[/color] Il nucleo è mio, il pagamento è già sul tuo conto. Bel lavoro, davvero.\n...Aspetta. Perché il nucleo sta [i]trasmettendo[/i]? Chi— ", 16)
	txt.custom_minimum_size.x = 820
	v.add_child(txt)
	v.add_child(_spacer(4))
	for o in Game.objectives:
		var ok: bool = o.state == "done"
		v.add_child(UITheme.label("%s %s" % ["[✓]" if ok else ("[✗]" if o.state == "failed" else "[ ]"), o.text], 15, UITheme.GOOD if ok else (UITheme.DANGER if o.state == "failed" else UITheme.DIM)))
	v.add_child(_spacer(4))
	v.add_child(_rich(_stats_text(), 15, 580))
	v.add_child(UITheme.label("VALUTAZIONE: " + Game.rating(), 22, UITheme.BORDER))
	v.add_child(UITheme.label("Fine della vertical slice. Grazie per aver giocato.", 14, UITheme.DIM))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.add_child(UITheme.button("Rigioca", Game.restart))
	hb.add_child(UITheme.button("Esci", func(): get_tree().quit()))
	v.add_child(hb)
	_show(w[0], "complete", false)
