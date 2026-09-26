extends Node
## Test automatico end-to-end. Avvio:
##   godot --path . -- --autotest            (headless: logica)
##   xvfb-run godot --path . -- --autotest --shots   (anche screenshot)
##   godot --path . -- --autotest --npc      (generatore di NPC: libreria, mesh, scheletro, pose)
##   godot --path . -- --autotest --stress   (10/25/50/100 guardie nella hall: tempi e draw call)
##   godot --path . -- --autotest --save     (salvataggi: slot, F5/F9, stato identico dopo il caricamento)
##   godot --path . -- --autotest --stimoli  (stimoli e materiali: cocci, urti, acqua e corrente, fumo, casse)
##   aggiungi --lang=it per fare gli stessi test con i testi in italiano
## Stampa OK/FAIL per ogni controllo ed esce con codice 0 se tutto passa.

var fails := 0
var oks := 0
var shots := false
var shot_dir := "user://shots"
var p: Node
var lvl: Node
var mode := "full"   # full | death | post_restart | ui | npc | stress | save | post_load | stimoli
## Per il test dei salvataggi: lo stato atteso dopo il caricamento e dove cercare le cose.
var expected := {}
var expect_info := {}
## Errori di script durante il test (condiviso anche col test dopo il riavvio).
static var _script_errors: ScriptErrors


## Un errore di script dentro una funzione del test la interrompe a metà senza far
## fallire nessun controllo: li contiamo e a fine test valgono come FAIL.
class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var _lock := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		count += 1
		if first == "":
			first = "%s:%d %s" % [file, line, rationale if rationale != "" else code]
		_lock.unlock()


## Orecchio di prova (test degli stimoli): sente i rumori come una guardia e li annota.
class NoiseProbe extends Node:
	var heard: Array = []   # [kind, radius, source]

	func hear(_pos: Vector3, radius: float, kind: String, source: Node, _info := {}) -> void:
		heard.append([kind, radius, source])

	func has_kind(kind: String) -> bool:
		return heard.any(func(h): return h[0] == kind)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _script_errors == null:
		_script_errors = ScriptErrors.new()
		OS.add_logger(_script_errors)
	shots = "--shots" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			shot_dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(shot_dir)
	if "--death" in OS.get_cmdline_user_args() and mode == "full":
		mode = "death"
	if "--ui" in OS.get_cmdline_user_args() and mode == "full":
		mode = "ui"
	if "--guida" in OS.get_cmdline_user_args() and mode == "full":
		mode = "guida"
	if "--npc" in OS.get_cmdline_user_args() and mode == "full":
		mode = "npc"
	if "--stress" in OS.get_cmdline_user_args() and mode == "full":
		mode = "stress"
	if "--save" in OS.get_cmdline_user_args() and mode == "full":
		mode = "save"
	if "--stimoli" in OS.get_cmdline_user_args() and mode == "full":
		mode = "stimoli"
	# watchdog: nessun test deve restare appeso
	get_tree().create_timer(240.0, true).timeout.connect(func():
		print("FAIL: timeout globale")
		get_tree().quit(2))
	match mode:
		"death":
			run_death()
		"post_restart":
			run_post_restart()
		"ui":
			run_ui()
		"guida":
			run_guida()
		"npc":
			run_npc()
		"stress":
			run_stress()
		"save":
			run_save()
		"post_load":
			run_post_load()
		"stimoli":
			run_stimoli()
		_:
			run()


## Morte del player, schermata "segnale perso" e riavvio della missione.
func run_death() -> void:
	await frames(20)
	p = Game.player
	Game.ui._begin()
	await wait(0.5)
	p.take_damage(500.0, p.global_position, Vector3.FORWARD, "test")
	await wait(3.0)
	check(Game.state == Game.State.DEAD and Game.ui.current_kind == "death", "morte: schermata SEGNALE PERSO")
	var helper := Node.new()
	helper.set_script(load("res://tools/autotest.gd"))
	helper.mode = "post_restart"
	helper.name = "PostRestartTest"
	helper.oks = oks
	helper.fails = fails
	get_tree().root.add_child(helper)
	Game.restart()


## Fine del test: risultato ed exit code (1 se qualche controllo o script è fallito).
func finish(exit_on_fail := true) -> void:
	if _script_errors.count > 0:
		check(false, "errori di script durante il test: %d (il primo: %s)" % [_script_errors.count, _script_errors.first])
	print("RISULTATO: %d ok, %d fail" % [oks, fails])
	get_tree().quit(1 if fails > 0 and exit_on_fail else 0)


func _find_button(n: Node, prefix: String) -> Button:
	if n is Button and (n as Button).text.begins_with(prefix):
		return n
	for c in n.get_children():
		var b := _find_button(c, prefix)
		if b:
			return b
	return null


## Inizio del testo tradotto di un bottone, fino al primo segnaposto (%d, %s).
func _label(msg: String) -> String:
	return tr(msg).get_slice("%", 0)


func _press(prefix: String) -> bool:
	var b := _find_button(Game.ui.root, prefix)
	if b == null or b.disabled:
		print("      (bottone non trovato/disabilitato: ", prefix, ")")
		return false
	b.pressed.emit()
	return true


## Preme davvero i bottoni dei pannelli (callback e lambda della UI).
func run_ui() -> void:
	await frames(20)
	p = Game.player
	p.god_mode = true
	Game.ui.show_start()
	await frames(2)
	# lingua dal menu iniziale: il menu si ridisegna nell'altra lingua e poi torna com'era
	var lang: String = Game.settings.language
	check(_press(_label("Language: %s")), "menu: bottone lingua")
	await frames(2)
	check(Game.settings.language != lang and Game.ui.current_kind == "start" and _find_button(Game.ui.root, _label("START (unspent points: %d)")) != null,
		"menu ridisegnato in %s" % Game.language_name())
	check(_press(_label("Language: %s")), "menu: di nuovo la lingua")
	await frames(2)
	check(Game.settings.language == lang and _find_button(Game.ui.root, _label("START (unspent points: %d)")) != null, "menu tornato in %s" % Game.language_name())
	check(_press(" + "), "menu: + su una skill")
	check(_press(_label("START (unspent points: %d)")), "menu: inizia")
	await wait(0.3)
	check(Game.state == Game.State.PLAYING, "partita avviata dal bottone")
	Game.add_modules(3)
	Game.ui.open_upgrade()
	await frames(2)
	var before := 0
	for sk in Game.SKILLS:
		before += Game.skill(sk)
	check(_press(_label("UPGRADE (cost: %d)")), "upgrade: bottone potenzia")
	await frames(2)
	var after := 0
	for sk in Game.SKILLS:
		after += Game.skill(sk)
	check(after == before + 1 and Game.ui.current_kind == "upgrade", "upgrade applicato e pannello aggiornato")
	await close_ui()
	p.health = 50.0
	Game.ui.open_pda(2)
	await frames(2)
	check(_press(tr("Use")), "PDA: usa medipatch")
	await frames(2)
	check(p.health > 50.0 and Game.ui.current_kind == "pda", "medipatch usato dal PDA")
	await close_ui()
	Game.ui.open_pause()
	await frames(2)
	var sv := _find_button(Game.ui.root, tr("Save game"))
	check(sv != null and not sv.disabled and _find_button(Game.ui.root, tr("Load game")) != null, "pausa: salva e carica")
	check(_press(tr("Options")), "pausa: opzioni")
	await frames(2)
	check(Game.ui.current_kind == "options", "pannello opzioni aperto")
	var sc: int = Game.settings.pixel_scale
	check(_press(_label("Internal resolution: %s  [%s]")), "opzioni: risoluzione")
	await frames(2)
	check(Game.settings.pixel_scale != sc and Game.ui.current_kind == "options", "risoluzione cambiata")
	var dt: bool = Game.settings.dither
	check(_press(_label("15-bit dithering: %s  [%s]")) and Game.settings.dither != dt, "opzioni: dithering")
	await frames(2)
	var fs: bool = Game.settings.fullscreen
	check(_press(_label("Fullscreen: %s")) and Game.settings.fullscreen != fs, "opzioni: schermo intero")
	await frames(2)
	_press(_label("Fullscreen: %s"))
	await frames(2)
	var vs: bool = Game.settings.vsync
	check(_press(_label("V-Sync: %s")) and Game.settings.vsync != vs, "opzioni: V-Sync")
	await frames(2)
	_press(_label("V-Sync: %s"))
	await frames(2)
	check(Game.settings.fullscreen == fs and Game.settings.vsync == vs, "schermo intero e V-Sync tornati com'erano")
	check(_press(_label("Language: %s")), "opzioni: lingua")
	await frames(2)
	check(Game.settings.language != lang and Game.ui.current_kind == "options" and _find_button(Game.ui.root, tr("Back  [Esc]")) != null,
		"opzioni ridisegnate in %s" % Game.language_name())
	check(_press(_label("Language: %s")), "opzioni: di nuovo la lingua")
	await frames(2)
	check(Game.settings.language == lang, "lingua tornata com'era")
	var cap0: String = Game.settings.env_captions
	check(cap0 == "auto" and _press(_label("Captions for signs and writings: %s")), "opzioni: didascalie (predefinite: auto)")
	await frames(2)
	var cap1: String = Game.settings.env_captions
	_press(_label("Captions for signs and writings: %s"))
	await frames(2)
	var cap2: String = Game.settings.env_captions
	_press(_label("Captions for signs and writings: %s"))
	await frames(2)
	check([cap1, cap2, Game.settings.env_captions] == ["always", "off", "auto"], "didascalie: auto → sempre → no → auto")
	await _check_rebinding()
	check(_press(tr("Back  [Esc]")), "opzioni: indietro")
	await frames(2)
	check(Game.ui.current_kind == "pause", "dalle opzioni si torna alla pausa")
	check(_press(tr("Options")), "pausa: di nuovo le opzioni")
	await frames(2)
	Game.ui.close_panel()   # come Esc
	await frames(2)
	check(Game.ui.current_kind == "pause", "Esc nelle opzioni torna alla pausa")
	check(_press(tr("Resume")), "pausa: riprendi")
	await frames(2)
	check(Game.state == Game.State.PLAYING, "ripreso")
	# tastierino: 0 4 5 1 OK
	var door: Node = null
	for d in get_tree().get_nodes_in_group("doors"):
		if d.locked and d.lock.get("code", "") == "0451":
			door = d
	Game.ui.open_lock(door)
	await frames(2)
	for k in ["0", "4", "5", "1"]:
		var b := _find_button(Game.ui.root, k)
		b.pressed.emit()
	check(_press("OK"), "tastierino: OK")
	await frames(2)
	check(not door.locked and Game.state == Game.State.PLAYING, "porta sbloccata dal tastierino")
	await _check_env_captions()
	finish()


## Rimappatura dal pannello Comandi (già aperto): tasto nuovo, scambio con un altro
## comando, Esc che annulla, Backspace che svuota, tasto del mouse, ripristino.
func _check_rebinding() -> void:
	var press_slot := func(action: String, i: int) -> bool:
		var b: Button = Game.ui.root.find_child("%s_%d" % [action, i], true, false)
		if b == null:
			return false
		b.pressed.emit()
		return Game.ui.capturing_key()
	var send_key := func(code: int) -> void:
		var ev := InputEventKey.new()
		ev.physical_keycode = code as Key
		ev.keycode = code as Key
		ev.pressed = true
		Input.parse_input_event(ev)
	check(press_slot.call("reload", 0), "comandi: in attesa di un tasto")
	send_key.call(KEY_T)
	await frames(3)
	check(Game.binding("reload")[0] == ["key", KEY_T] and not Game.ui.capturing_key() and Game.ui.current_kind == "options",
		"ricarica su T")
	var t_in_map := false
	for e in InputMap.action_get_events("reload"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_T:
			t_in_map = true
	check(t_in_map and Game.key_label("reload") == "T" and Game.ui.controls_text().contains("[b]T[/b]"), "T nell'InputMap e nei testi dei comandi")
	press_slot.call("reload", 0)
	send_key.call(KEY_W)
	await frames(3)
	check(Game.binding("reload")[0] == ["key", KEY_W] and Game.binding("move_forward")[0] == ["key", KEY_T], "W già usato da «avanti»: i due tasti si scambiano")
	press_slot.call("reload", 0)
	send_key.call(KEY_ESCAPE)
	await frames(3)
	check(Game.binding("reload")[0] == ["key", KEY_W] and not Game.ui.capturing_key() and Game.ui.current_kind == "options", "Esc annulla senza chiudere il pannello")
	var click := func(button: MouseButton, pos: Vector2) -> void:
		var mb := InputEventMouseButton.new()
		mb.button_index = button
		mb.position = pos
		mb.global_position = pos
		mb.pressed = true
		Input.parse_input_event(mb)
		var up := mb.duplicate() as InputEventMouseButton
		up.pressed = false
		Input.parse_input_event(up)
	# posizione nella finestra (gli eventi del mouse arrivano in coordinate della finestra)
	var slot_center := func(action: String, i: int) -> Vector2:
		var b: Button = Game.ui.root.find_child("%s_%d" % [action, i], true, false)
		return get_viewport().get_final_transform() * b.get_global_rect().get_center() if b else Vector2.ZERO
	# un clic altrove annulla, senza assegnare il tasto del mouse
	press_slot.call("reload", 1)
	click.call(MOUSE_BUTTON_LEFT, Vector2(4, 4))
	await frames(3)
	check(Game.binding("reload")[1] == [] and Game.binding("attack")[0] == ["mouse", MOUSE_BUTTON_LEFT] and not Game.ui.capturing_key(),
		"clic fuori dal tasto: annulla senza assegnare")
	# il secondo clic di un doppio clic non conta
	press_slot.call("reload", 1)
	click.call(MOUSE_BUTTON_LEFT, slot_center.call("reload", 1))
	await frames(3)
	check(Game.binding("reload")[1] == [] and Game.ui.capturing_key(), "doppio clic: non assegna il tasto sinistro")
	await wait(0.35)
	click.call(MOUSE_BUTTON_MIDDLE, slot_center.call("reload", 1))
	await frames(3)
	check(Game.binding("reload")[1] == ["mouse", MOUSE_BUTTON_MIDDLE] and Game.key_label("reload") == "W/" + tr("MMB"), "tasto del mouse come secondo tasto")
	# «rubare» il solo tasto di un comando lo lascia senza tasti: il pannello avvisa
	press_slot.call("medpatch", 1)
	await wait(0.35)
	click.call(MOUSE_BUTTON_LEFT, slot_center.call("medpatch", 1))
	await frames(3)
	var warn := tr("Careful: «%s» has no key now.") % tr(Game.ACTION_LABELS.attack)
	check(Game.binding("medpatch")[1] == ["mouse", MOUSE_BUTTON_LEFT] and Game.key_label("attack") == "—"
		and Game.ui.root.find_children("*", "Label", true, false).any(func(l): return l.text == warn),
		"tasto preso a un comando che resta senza: avviso")
	press_slot.call("reload", 1)
	send_key.call(KEY_BACKSPACE)
	await frames(3)
	check(Game.binding("reload")[1] == [], "Backspace toglie il tasto")
	check(_press(tr("Restore default keys")), "comandi: ripristina")
	await frames(2)
	check(Game.binding("reload")[0] == ["key", KEY_R] and Game.binding("move_forward")[0] == ["key", KEY_W] and Game.settings.bindings.is_empty(), "tasti predefiniti ripristinati")


## Salvataggi: autosalvataggio, pannelli salva/carica, F5, caricamento con lo stesso
## stato (continua in run_post_load, dopo che la scena si è ricaricata).
func run_save() -> void:
	await frames(20)
	lvl = Game.level
	p = Game.player
	p.god_mode = true
	check(SaveGame.dir == "user://saves_test", "i test salvano in user://saves_test")
	for s in SaveGame.slots():
		SaveGame.delete(s)
	Game.ui._begin()
	await wait(0.3)
	check(SaveGame.exists("auto") and SaveGame.latest() == "auto", "autosalvataggio a inizio missione")
	# cambia il mondo: guardie a terra e perquisite, porta aperta, oggetto raccolto, luce
	# rotta, telecamera distrutta, moduli, ferite, un corpo in spalla
	var kov := guard("Ofc. Kovač")
	kov.knock_out()
	var ruiz := guard("Ofc. Ruiz")
	ruiz.knock_out()
	ruiz.frob(p)
	var door: Node = null
	for d in get_tree().get_nodes_in_group("doors"):
		if d.locked and d.lock.get("code", "") == "0451":
			door = d
	door.try_code("0451")
	var pk: Node = lvl.find_children("*", "", true, false).filter(func(n): return n is Pickup)[0]
	var pk_path := String(lvl.get_path_to(pk))
	pk.frob(p)
	var lamp: Node = lvl.find_children("*", "", true, false).filter(func(n): return n is LightFixture and n.style != "none" and not n.emergency)[0]
	lamp.take_damage(1.0, Vector3.ZERO, Vector3.ZERO, "bullet")
	var cam: Node = get_tree().get_nodes_in_group("security_cameras")[0]
	cam.take_damage(100.0, cam.global_position, Vector3.ZERO, "bullet")
	Game.add_modules(3)
	# stimoli: bottiglia in cocci, tanica in pozza, estintore scaricato, cavo spento
	for n in ["Bottle1", "Tanica3", "Estintore1"]:
		(lvl.find_child(n, true, false) as Throwable).shatter()
	(lvl.find_child("InterruttoreCorrente", true, false) as LightSwitch).frob(p)
	await tp(Vector3(0, 0.05, 3), 90, -10)
	p.take_damage(35.0, p.global_position, Vector3.FORWARD, "test")
	p.carry_body(kov)
	await frames(3)
	# tornando dalle Opzioni si può ancora salvare
	Game.ui.open_pause()
	await frames(2)
	check(_press(tr("Options")), "pausa: opzioni")
	await frames(2)
	Game.ui.close_panel()
	await frames(2)
	var sv := _find_button(Game.ui.root, tr("Save game"))
	check(Game.ui.current_kind == "pause" and sv != null and not sv.disabled, "tornando dalle opzioni «Salva partita» è attivo")
	# pannello Salva della pausa: slot vuoto, poi sovrascrittura con conferma
	check(_press(tr("Save game")), "pausa: salva")
	await frames(2)
	check(Game.ui.current_kind == "save" and _press(tr("Save")), "slot vuoto: salva")
	await frames(2)
	check(SaveGame.exists("1") and Game.ui.current_kind == "save", "salvato nello slot 1")
	check(_press(tr("Overwrite")) and SaveGame.exists("1"), "sovrascrivere chiede conferma")
	await frames(1)
	check(_press(tr("Click to confirm")), "conferma della sovrascrittura")
	await frames(2)
	var snap := SaveGame.collect(lvl)
	var m := SaveGame.meta("1")
	check(String(m.get("saved_at", "")).length() == 16 and float(m.get("playtime", -1.0)) >= 0.0 and m.get("objectives", "") != "",
		"metadati dello slot: %s" % str(m))
	Game.ui.close_panel()
	await frames(2)
	check(Game.ui.current_kind == "pause", "dal pannello Salva si torna alla pausa")
	check(_press(tr("Load game")), "pausa: carica")
	await frames(2)
	var load_btns: Array = Game.ui.root.find_children("*", "Button", true, false).filter(func(b): return b.text == tr("Load"))
	check(load_btns.size() == SaveGame.slots().size() and load_btns.filter(func(b): return not b.disabled).size() == 2,
		"pannello Carica: %d slot, 2 pieni (auto, 1)" % load_btns.size())
	Game.ui.close_panel()
	await frames(2)
	Game.ui.close_panel()
	await frames(2)
	check(Game.state == Game.State.PLAYING, "ripreso")
	# F5
	var ev := InputEventAction.new()
	ev.action = "quicksave"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(3)
	check(SaveGame.exists("quick") and SaveGame.latest() == "quick", "F5: salvataggio rapido (ora è il più recente)")
	# carica lo slot 1: la scena si ricarica e questo nodo sparisce, continua l'aiutante
	var helper := Node.new()
	helper.set_script(load("res://tools/autotest.gd"))
	helper.mode = "post_load"
	helper.name = "PostRestartTest"
	helper.oks = oks
	helper.fails = fails
	helper.expected = snap
	helper.expect_info = {"door": String(lvl.get_path_to(door)), "pickup": pk_path}
	get_tree().root.add_child(helper)
	Game.add_modules(10)   # cambiato dopo il salvataggio: al caricamento torna com'era
	check(Game.load_game("1"), "caricamento dello slot 1 avviato")


func run_post_load() -> void:
	await Game.game_loaded
	var got := SaveGame.collect(Game.level)
	var diffs := _diff("game", expected.game, got.game) + _diff("entities", expected.entities, got.entities)
	check(diffs.is_empty(), "stato caricato identico a quello salvato (%d entità)%s" % [got.entities.size(), "" if diffs.is_empty() else " — differenze: " + str(diffs.slice(0, 6))])
	var r1: Array = expected.removed.duplicate()
	var r2: Array = got.removed.duplicate()
	r1.sort()
	r2.sort()
	check(r1 == r2 and r1.has(expect_info.pickup), "oggetti raccolti restano raccolti: %s" % str(r2))
	lvl = Game.level
	p = Game.player
	check(Game.level.get_node_or_null(NodePath(expect_info.pickup)) == null, "l'oggetto raccolto non c'è")
	check(not Game.level.get_node(NodePath(expect_info.door)).locked, "la porta sbloccata resta sbloccata")
	check(p.carried_body != null and p.carried_body.carried and p.carried_body.state == Guard.S.DOWN, "il corpo è ancora in spalla")
	check(Game.has_keycard("sicurezza") and Game.modules == int(expected.game.modules), "inventario: tessera e moduli com'erano")
	check(Game.state == Game.State.PLAYING and Game.ui.current_kind == "", "si riprende subito a giocare")
	check(lvl._later.any(func(c): return c[0] == "_intro_2"), "la battuta di Vesper in sospeso resta in sospeso (Level.later)")
	check(Stimuli.fields(Stimuli.SHARDS).size() == 1 and Stimuli.fields(Stimuli.WATER).size() == 1 and Stimuli.fields(Stimuli.SMOKE).size() == 1,
		"cocci, pozza e nube di fumo ritrovati dopo il caricamento")
	var cable := lvl.find_child("CavoScoperto", true, false) as LiveCable
	check(not cable.powered and not Stimuli.fields(Stimuli.CURRENT).any(func(f): return f.source == cable), "il cavo spento resta spento")
	await frames(10)
	# F9: salvataggio rapido
	var ev := InputEventAction.new()
	ev.action = "quickload"
	ev.pressed = true
	Input.parse_input_event(ev)
	await Game.game_loaded
	check(Game.level != null and Game.player.carried_body != null, "F9: caricato il salvataggio rapido")
	await frames(5)
	# i ritardi della partita lasciata (furto del nucleo → lockdown, ascensore → fine
	# missione) non devono scattare in quella caricata
	var core: Node = Game.level.find_children("*", "", true, false).filter(func(n): return n is ServerCore)[0]
	core.frob(Game.player)
	await frames(2)
	Game.quickload()
	await Game.game_loaded
	await wait(4.5)
	core = Game.level.find_children("*", "", true, false).filter(func(n): return n is ServerCore)[0]
	check(not Game.lockdown and not core.taken and not Game.has_item("core"), "furto del nucleo e subito F9: niente lockdown dopo il caricamento")
	var lift: Node = Game.level.find_children("*", "", true, false).filter(func(n): return n is ElevatorPanel)[0]
	Game.give_item("core")
	lift.frob(Game.player)
	await frames(2)
	Game.quickload()
	await Game.game_loaded
	await wait(2.8)
	check(Game.state == Game.State.PLAYING, "ascensore e subito F9: la missione non finisce da sola")
	# slot rovinato: ignorato
	var f := FileAccess.open(SaveGame.path("5"), FileAccess.WRITE)
	f.store_string("{rotto")
	f.close()
	check(SaveGame.meta("5").is_empty() and not Game.load_game("5"), "uno slot rovinato si ignora (e non si carica)")
	# morte: si può ripartire dall'ultimo salvataggio
	Game.player.god_mode = false
	Game.player.take_damage(999.0, Game.player.global_position, Vector3.FORWARD, "test")
	await wait(3.0)
	check(Game.state == Game.State.DEAD and _find_button(Game.ui.root, tr("Load last save")) != null, "schermata di morte: «carica l'ultimo salvataggio»")
	for s in SaveGame.slots():
		SaveGame.delete(s)
	finish()


## Stimoli e materiali: bottiglie che si rompono in cocci rumorosi, oggetti lanciati che
## rompono le luci (non le lattine), pozze elettrificate (luce rotta = KO, cavo scoperto =
## morte, interruttore della corrente), fumo che acceca guardie e torrette, casse pesanti
## (Forza 2) che si impilano.
func run_stimoli() -> void:
	await frames(20)
	lvl = Game.level
	p = Game.player
	p.god_mode = true
	Game.start_alloc = {"hacking": 1, "armi": 1, "forza": 2, "furtivita": 0}
	Game.ui._begin()
	await wait(0.5)
	var probe := NoiseProbe.new()
	probe.add_to_group("ai")
	add_child(probe)
	# le guardie restano ferme dove il test le mette (sentono e prendono la scossa lo stesso)
	for g in get_tree().get_nodes_in_group("guards"):
		g.process_mode = Node.PROCESS_MODE_DISABLED

	# --- materiali
	var kinds := ["can", "bottle", "box", "heavy", "jug", "extinguisher"]
	check(kinds.all(func(k): return load("res://assets/prop_materials/%s.tres" % k) is PropMaterial), "un PropMaterial per ogni Kind dei Throwable")
	var box1 := lvl.find_child("Box1", true, false) as Throwable
	var crate1 := lvl.find_child("CassaPesante1", true, false) as Throwable
	var crate2 := lvl.find_child("CassaPesante2", true, false) as Throwable
	check(box1.tex == "crate_light" and crate1.tex == "crate" and crate1.mass >= 40.0, "SB-14 solo sulle casse pesanti (40 kg)")

	# --- cocci: la bottiglia lanciata si rompe; sui cocci i passi fanno rumore
	var bottle := lvl.find_child("Bottle2", true, false) as Throwable
	await tp(Vector3(13.0, 0.05, -4.7), 180, -30)
	check(bottle.get_frob_text() == tr("Take: %s") % tr("Bottle"), "bottiglia: %s" % bottle.get_frob_text())
	bottle.frob(p)
	await frames(3)
	check(p.held == bottle, "bottiglia in mano")
	await face(p.camera.global_position + Vector3(3.0, -0.4, 0.0))
	probe.heard.clear()
	p._drop_held(true)
	for i in 30:
		await wait(0.1)
		if bottle.broken:
			break
	check(bottle.broken and Stimuli.fields(Stimuli.SHARDS).size() == 1, "bottiglia lanciata: si rompe in cocci")
	check(probe.has_kind("glass"), "la bottiglia rotta fa rumore di vetri")
	check(lvl.surface_at(bottle.fx_pos) == "glass", "sotto i cocci la superficie è vetro")
	if shots:
		await tp(bottle.fx_pos + Vector3(-1.4, 0.05, 0.6), -60, -35)
		await face(bottle.fx_pos)
		await shot("stimoli_01_cocci")
	var r_glass: float = await _crouch_step_noise(bottle.fx_pos + Vector3.UP * 0.05)
	var r_floor: float = await _crouch_step_noise(bottle.fx_pos + Vector3(0, 0.05, 2.2))
	check(r_glass > 4.0 and r_glass > r_floor * 2.0, "accovacciati sui cocci si fa rumore (%.1f m contro %.1f m)" % [r_glass, r_floor])

	# --- urti: una lattina non rompe la lampada, una scatola sì (e fa scintille)
	var lamp := lvl.find_child("Luce8", true, false) as LightFixture
	var can := lvl.find_child("Can4", true, false) as Throwable
	await tp(Vector3(0, 0.05, 7.0), 180)
	can.global_position = lamp.global_position + Vector3(1.2, 0.05, 0)
	can.linear_velocity = Vector3(-9.5, 0, 0)
	probe.heard.clear()
	await wait(0.6)
	check(probe.heard.any(func(h): return h[0] == "impact" and h[2] == can) and not lamp.broken, "una lattina lanciata colpisce la lampada ma non la rompe")
	can.global_position = Vector3(-1.6, 1.23, 4.4)   # via dalla traiettoria della scatola
	can.linear_velocity = Vector3.ZERO
	var box3 := lvl.find_child("Box3", true, false) as Throwable
	box3.global_position = lamp.global_position + Vector3(1.4, 0.08, 0)
	box3.linear_velocity = Vector3(-4.8, 0.4, 0)
	await wait(0.8)
	check(lamp.broken, "una scatola lanciata rompe la lampada")
	check(Stimuli.fields(Stimuli.CURRENT).any(func(f): return f.source == lamp), "la lampada rotta fa scintille (corrente a bassa tensione)")

	# --- acqua e bassa tensione: pozza sotto la luce della sala relax, la luce si rompe
	var jug1 := lvl.find_child("Tanica1", true, false) as Throwable
	var light12 := lvl.find_child("Luce12", true, false) as LightFixture
	await tp(Vector3(13.2, 0.05, -4.6), 0)
	probe.heard.clear()
	jug1.global_position = Vector3(15.6, 1.2, -2.6)
	jug1.linear_velocity = Vector3(0, -5.0, 0)
	await wait(2.0)
	check(jug1.broken and lvl.surface_at(Vector3(15.6, 0.02, -2.6)) == "water", "tanica rotta: pozza d'acqua")
	check(probe.has_kind("splash"), "la tanica rotta fa rumore")
	var ruiz := guard("Ofc. Ruiz")
	ruiz.global_position = Vector3(16.2, 0.0, -2.9)
	await frames(3)
	check(Stimuli.voltage_of(jug1._field) == 0 and ruiz.is_active(), "acqua senza corrente: innocua")
	light12.take_damage(30.0, light12.global_position, Vector3.DOWN, "bullet")
	await wait(0.4)
	check(ruiz.state == Guard.S.DOWN and not ruiz.dead, "luce rotta sopra la pozza: la guardia nell'acqua sviene (bassa tensione)")
	if shots:
		await tp(Vector3(13.2, 0.05, -4.6), 0)
		await face(Vector3(15.6, 0.0, -2.4))
		await shot("stimoli_02_pozza_elettrificata")
	check(Game.stats.kos >= 1 and Game.is_objective_active("nokill"), "lo svenimento non conta come uccisione")
	var hp0: float = p.health
	await tp(Vector3(15.8, 0.05, -2.2), 0)
	await wait(1.0)
	check(p.health < hp0, "anche il giocatore prende la scossa nell'acqua elettrificata (salute %d)" % int(p.health))
	p.health = p.max_health
	light12._spark_t = 0.05
	await wait(0.3)
	check(Stimuli.voltage_of(jug1._field) == 0, "finite le scintille l'acqua torna innocua")

	# --- alta tensione: il cavo scoperto del magazzino
	var cable := lvl.find_child("CavoScoperto", true, false) as LiveCable
	check(cable.powered and Stimuli.fields(Stimuli.CURRENT).any(func(f): return f.source == cable and int(f.strength) == Stimuli.HIGH_VOLTAGE),
		"il cavo scoperto porta corrente ad alta tensione a terra")
	var tip := cable.tip_position()
	if shots:
		await tp(Vector3(-14.8, 0.05, 8.2), 0)
		await face(tip + Vector3.UP * 1.0)
		await shot("stimoli_03_cavo_scoperto")
	await tp(Vector3(tip.x + 0.38, 0.05, tip.z), 90)
	hp0 = p.health
	await wait(0.5)
	check(p.health < hp0 - 30.0, "toccare il cavo: scossa forte (salute %d)" % int(p.health))
	await tp(Vector3(-14.5, 0.05, 9.5), 0)
	p.health = p.max_health
	var jug2 := lvl.find_child("Tanica2", true, false) as Throwable
	jug2.global_position = Vector3(-12.1, 1.0, 6.1)
	jug2.linear_velocity = Vector3(0, -5.0, 0)
	await wait(2.0)
	check(jug2.broken and Stimuli.voltage_of(jug2._field) == Stimuli.HIGH_VOLTAGE, "pozza che tocca il cavo: elettrificata ad alta tensione")
	var kov := guard("Ofc. Kovač")
	kov.global_position = Vector3(-13.3, 0.0, 6.9)
	await wait(0.4)
	check(kov.state == Guard.S.DOWN and kov.dead, "la guardia nell'acqua elettrificata dal cavo muore")
	check(not Game.is_objective_active("nokill"), "morta di scossa: conta come uccisione")
	var sw := lvl.find_child("InterruttoreCorrente", true, false) as LightSwitch
	check(sw.get_frob_text() == tr("Power switch (turn off)"), "interruttore della corrente: %s" % sw.get_frob_text())
	sw.frob(p)
	await frames(2)
	check(not cable.powered and Stimuli.voltage_of(jug2._field) == 0, "corrente staccata: l'acqua torna innocua")
	await tp(Vector3(-12.9, 0.05, 6.4), 0)
	hp0 = p.health
	await wait(1.0)
	check(p.health == hp0 and lvl.surface_at(p.global_position) == "water", "si cammina nell'acqua senza scossa")
	if shots:
		kov.visible = false   # (ferma dal test, è rimasta in piedi: toglila dall'inquadratura)
		await tp(Vector3(-12.2, 0.05, 9.4), 0)
		await face(jug2.fx_pos)
		await shot("stimoli_03b_pozza_magazzino")
		kov.visible = true

	# --- casse pesanti: Forza 2, si posano una sull'altra, ci si arrampica
	Game.skills["forza"] = 1
	check(crate2.get_frob_text() == tr("%s — too heavy (Strength %d)") % [tr("SB-14 crate"), 2], "cassa SB-14 con Forza 1: troppo pesante")
	Game.skills["forza"] = 2
	await tp(Vector3(-14.2, 0.05, 8.5), 90)
	await face(crate2.global_position)
	await frob_expect("cassa pesante")
	check(p.held == crate2, "cassa pesante sollevata con Forza 2")
	await tp(Vector3(-14.07, 0.05, crate1.global_position.z), 90, 0)
	await wait(0.6)
	p._drop_held(false)
	await wait(1.2)
	var flat := Vector2(crate2.global_position.x - crate1.global_position.x, crate2.global_position.z - crate1.global_position.z).length()
	check(crate2.global_position.y > 0.95 and flat < 0.35, "cassa posata sull'altra: impilate (y %.2f)" % crate2.global_position.y)
	if shots:
		await tp(Vector3(-13.0, 0.05, 8.2), 0)
		await face(crate1.global_position + Vector3.UP * 0.5)
		await shot("stimoli_04_casse_impilate")
	await tp(Vector3(crate1.global_position.x + 0.95, 0.05, crate1.global_position.z), 90, 0)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await wait(0.9)
	check(p.global_position.y > 1.3, "mantle in cima alla pila (y %.2f)" % p.global_position.y)
	# due casse sotto la mensola alta: le munizioni si raggiungono
	crate1.global_position = Vector3(-11.85, 0.36, 12.3)
	crate1.linear_velocity = Vector3.ZERO
	crate2.global_position = Vector3(-11.85, 1.08, 12.3)
	crate2.linear_velocity = Vector3.ZERO
	await tp(Vector3(-13.0, 0.05, 10.5), 0)
	await wait(0.8)
	await tp(Vector3(-11.85, 1.48, 12.3), -90)
	await wait(0.3)
	var ammo0: int = Game.ammo_reserve
	await face(lvl.find_child("Ammo3", true, false).global_position + Vector3.UP * 0.04)
	await frob_expect("munizioni sulla mensola alta")
	check(Game.ammo_reserve > ammo0, "munizioni raccolte in piedi su due casse")

	# --- fumo: la guardia non vede il giocatore in piena luce a 3 m; senza fumo sì
	var hale := guard("Op. Hale")
	var ext1 := lvl.find_child("Estintore1", true, false) as Throwable
	await tp(Vector3(-13.0, 0.05, 0.6), 90, 0)
	ext1.global_position = Vector3(-14.6, 0.3, 0.6)
	ext1.linear_velocity = Vector3.ZERO
	await frames(2)
	probe.heard.clear()
	ext1.take_damage(30.0, ext1.global_position, Vector3.ZERO, "bullet")
	check(ext1.broken and probe.has_kind("hiss"), "estintore colpito: si scarica con un sibilo")
	await wait(1.6)
	check(Stimuli.smoke_between(Vector3(-16.3, 1.7, 0.6), p.get_aim_point()) >= Stimuli.SMOKE_BLOCKS, "nube di fumo fra la guardia e il giocatore")
	if shots:
		await tp(Vector3(-11.6, 0.05, -2.8), 50, 0)
		await face(Vector3(-15.0, 1.2, 0.8))
		await shot("stimoli_05_fumo_sala_sicurezza")
		await tp(Vector3(-13.0, 0.05, 0.6), 90, 0)
	hale.global_position = hale.post_pos
	hale.post_yaw = deg_to_rad(-90)
	hale.rotation.y = hale.post_yaw
	hale.state = Guard.S.PATROL
	hale.awareness = 0.0
	hale.process_mode = Node.PROCESS_MODE_INHERIT
	var seen := false
	for i in 30:
		await wait(0.1)
		seen = seen or hale.can_see_player or hale.state == Guard.S.COMBAT
	check(not seen, "nel fumo la guardia non vede il giocatore (visibilità %.2f)" % p.visibility)
	ext1.fx_t = ext1.mat.effect_duration - 0.05
	await wait(0.3)
	check(Stimuli.fields(Stimuli.SMOKE).is_empty(), "la nube si dirada e sparisce")
	await tp(Vector3(-13.0, 0.05, 0.6), 90, 0)
	hale.global_position = hale.post_pos
	hale.rotation.y = hale.post_yaw
	hale.state = Guard.S.PATROL
	hale.awareness = 0.0
	for i in 40:
		await wait(0.1)
		if hale.state == Guard.S.COMBAT:
			seen = true
			break
	check(seen, "senza fumo la stessa guardia lo vede subito")
	hale.process_mode = Node.PROCESS_MODE_DISABLED
	hale.state = Guard.S.PATROL
	hale.awareness = 0.0
	p.health = p.max_health
	# i rumori nuovi fanno indagare le guardie
	hale.hear(hale.global_position + Vector3(2.0, 0, 0), 9.0, "splash", null)
	check(hale.state == Guard.S.INVESTIGATE, "una guardia va a vedere il rumore di una pozza")
	hale.state = Guard.S.PATROL
	hale.awareness = 0.0

	# --- fumo e torretta: nel corridoio la torretta non spara
	var turret := lvl.find_child("Torretta", true, false) as Turret
	var ext2 := lvl.find_child("Estintore2", true, false) as Throwable
	await tp(Vector3(0.3, 0.05, -6.5), 0)
	ext2.global_position = Vector3(0.3, 1.0, -12.5)
	ext2.linear_velocity = Vector3.ZERO
	await frames(2)
	ext2.take_damage(30.0, ext2.global_position, Vector3.ZERO, "melee")
	await wait(1.6)
	turret.awareness = 0.0
	turret.state = Turret.T.IDLE
	await tp(Vector3(0.3, 0.05, -10.5), 0)
	hp0 = p.health
	await wait(4.0)
	check(p.health == hp0 and turret.state != Turret.T.FIRE, "nel fumo la torretta non vede il giocatore")
	await shot("stimoli_fumo_corridoio")
	finish()


## Raggio del rumore di un passo accovacciato in quel punto.
func _crouch_step_noise(pos: Vector3) -> float:
	await tp(pos, 0)
	p._set_crouch(true)
	var probe: NoiseProbe = get_children().filter(func(c): return c is NoiseProbe)[0]
	probe.heard.clear()
	p._footstep(false)
	p._set_crouch(false)
	var r := 0.0
	for h in probe.heard:
		if h[0] == "step" and h[2] == p:
			r = h[1]
	return r


## Differenze fra due stati salvati (i numeri con un margine minimo).
func _diff(path: String, a: Variant, b: Variant) -> Array:
	var num := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) != typeof(b) and not (typeof(a) in num and typeof(b) in num):
		return [path]
	match typeof(a):
		TYPE_DICTIONARY:
			var out := []
			for k in a:
				if not b.has(k):
					out.append("%s/%s (manca)" % [path, k])
				else:
					out.append_array(_diff("%s/%s" % [path, k], a[k], b[k]))
			for k in b:
				if not a.has(k):
					out.append("%s/%s (in più)" % [path, k])
			return out
		TYPE_ARRAY:
			if a.size() != b.size():
				return [path + " (lunghezza)"]
			var out := []
			for i in a.size():
				out.append_array(_diff("%s[%d]" % [path, i], a[i], b[i]))
			return out
		TYPE_INT, TYPE_FLOAT:
			return [] if absf(float(a) - float(b)) < 0.01 else [path]
		TYPE_VECTOR3:
			return [] if (a as Vector3).distance_to(b) < 0.01 else [path]
		TYPE_TRANSFORM3D:
			return [] if (a as Transform3D).origin.distance_to((b as Transform3D).origin) < 0.01 and (a as Transform3D).basis.is_equal_approx((b as Transform3D).basis) else [path]
	return [] if a == b else [path]


## Didascalie dei testi ambientali: regole della modalità "auto" e didascalia in gioco
## (davanti all'insegna, spente, guardando altrove, dietro un muro).
func _check_env_captions() -> void:
	var sign: Node3D = Game.level.find_child("Pannello_sign_sec1", true, false)
	var graf: Texture2D = load("res://assets/textures/graffiti.png")
	var lang0: String = Game.settings.language
	Game.set_language("en", false)
	check(not EnvTexts.wanted("auto", "SECURITY", sign.texture) and EnvTexts.wanted("always", "SECURITY", sign.texture)
		and not EnvTexts.wanted("off", "SECURITY", sign.texture), "didascalie in inglese: auto no, sempre sì, no mai")
	Game.set_language("it", false)
	check(not EnvTexts.wanted("auto", "SECURITY", sign.texture), "auto in italiano: l'insegna ha già la texture italiana")
	check(EnvTexts.wanted("auto", "SECURITY", graf), "auto: scritta tradotta ma texture solo inglese → didascalia")
	check(not EnvTexts.wanted("auto", "NO CALMA", graf), "auto: scritta uguale nelle due lingue → niente didascalia")
	Game.set_language(lang0, false)
	var cap := func() -> String: return Game.hud.env_caption.get_parsed_text()
	Game.settings.env_captions = "always"
	await _stand_before(sign, sign.global_position + sign.global_basis.z * 2.6)
	await wait(0.3)
	check(cap.call().contains(tr("SECURITY")) and cap.call().contains(tr("Sign")), "didascalia davanti all'insegna: «%s»" % cap.call())
	Game.settings.env_captions = "off"
	await wait(0.2)
	check(cap.call() == "", "didascalie spente: niente")
	Game.settings.env_captions = "always"
	await wait(0.2)
	p.yaw += PI
	p.rotation.y = p.yaw
	await wait(0.9)
	check(cap.call() == "", "guardando altrove la didascalia sparisce")
	# un punto davanti all'insegna ma con un muro in mezzo
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var behind := Vector3.INF
	for i in 48:
		var a := i * TAU / 48.0
		var c: Vector3 = sign.global_position + Vector3(cos(a), 0, sin(a)) * (4.0 + (i % 3) * 2.0)
		if sign.global_basis.z.dot(c - sign.global_position) <= 0.5:
			continue
		var down: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(c, c + Vector3.DOWN * 6.0, Layers.WORLD))
		if down.is_empty() or Game.level.builder.air_brush_at(down.position + Vector3.UP).is_empty():
			continue
		var eye: Vector3 = down.position + Vector3.UP * 1.6
		var block: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, sign.global_position, Layers.WORLD | Layers.DOOR))
		if not block.is_empty() and eye.distance_to(block.position) < eye.distance_to(sign.global_position) - 0.3:
			behind = down.position
			break
	check(behind != Vector3.INF, "trovato un punto con un muro davanti all'insegna")
	if behind != Vector3.INF:
		await _stand_before(sign, behind)
		await wait(0.9)
		check(cap.call() == "", "insegna dietro un muro: niente didascalia")
	Game.settings.env_captions = "auto"


## Mette il giocatore in pos (sul pavimento sotto) e lo gira verso target.
func _stand_before(target: Node3D, pos: Vector3) -> void:
	var down: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP, pos + Vector3.DOWN * 6.0, Layers.WORLD))
	p.global_position = (down.position if not down.is_empty() else pos) + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO
	await frames(4)
	await face(target.global_position)


## Il livello d'esempio di docs/GUIDA_EDITOR.md (levels/guida): stanza, porta
## col codice del datapad, guardia di ronda. Avvio:
##   godot --headless --path . -- --level=res://levels/guida/guida.tscn --autotest --guida
func run_guida() -> void:
	await frames(20)
	lvl = Game.level
	p = Game.player
	p.god_mode = true
	Game.ui._begin()
	await wait(0.5)
	check(Game.state == Game.State.PLAYING, "guida: partita avviata")
	await shot("guida_01_stanza")
	await tp(Vector3(2.5, 0.05, 1.6), 180, -30)
	await face(Vector3(2.5, 0.81, 2.8))
	await frob_expect("datapad col codice")
	check("codice_magazzino" in Game.logs_read, "guida: registro col codice letto")
	await close_ui()
	var door: Node = lvl.find_child("PortaMagazzino", true, false)
	check(door != null and door.locked, "guida: porta del magazzino chiusa")
	check(not door.try_code("0000") and door.try_code("2468"), "guida: il codice 2468 apre la porta")
	var rossi := guard("Ofc. Rossi")
	var from: Vector3 = rossi.global_position
	await wait(6.0)
	check(rossi.global_position.distance_to(from) > 1.0, "guida: la guardia fa la ronda (%.1f m)" % rossi.global_position.distance_to(from))
	await tp(Vector3(2.2, 0.05, -10.2), 0, 0)
	await face(Vector3(-0.8, 1.1, -5.5))
	await wait(0.8)
	await shot("guida_02_magazzino")
	finish()


## Generatore di NPC: libreria, definizioni dei personaggi, mesh, scheletro, pose, cache.
func run_npc() -> void:
	await frames(10)
	lvl = Game.level
	p = Game.player
	var shapes := NPCLibrary.list_shapes()
	check(shapes.size() >= 30, "libreria: %d forme su disco" % shapes.size())
	var broken := []
	for e in shapes:
		var sh: SegmentShape = e[1]
		if sh == null or sh.width_curve == null or sh.depth_curve == null:
			broken.append(e[0])
	check(broken.is_empty(), "libreria: tutte le forme hanno le curve di profilo %s" % str(broken))
	for cat in 11:
		check(not NPCLibrary.list_shapes(cat).is_empty(), "libreria: almeno una forma per la parte %s" % NPCDefinition.PART_NAMES[cat])
	# personaggi della slice: il bottino deve restare quello del livello originale
	var expected := {
		"ruiz": {"keycard": ["sicurezza", "Security Keycard"], "ammo": 6, "credits": 30},
		"hale": {"ammo": 4, "credits": 20, "medpatch": 1},
		"kovac": {"ammo": 6, "credits": 15},
		"mori": {"ammo": 8, "credits": 10},
	}
	for id in expected:
		var d: NPCDefinition = load(NPCLibrary.CHARACTERS_DIR.path_join(id + ".tres"))
		check(d != null and d.parts.size() == 11, "%s.tres: 11 parti" % id)
		check(d != null and d.loot() == expected[id], "%s.tres: bottino %s" % [id, str(d.loot() if d else {})])
	var g_ruiz := guard("Ofc. Ruiz")
	check(g_ruiz != null and g_ruiz.definition != null and g_ruiz.definition.resource_path.ends_with("ruiz.tres"), "Ruiz nel livello usa ruiz.tres")
	var g_hale := guard("Op. Hale")
	check(g_hale != null and not g_hale.definition.idle_barks.is_empty(), "Hale ha le sue battute di ronda")

	# mesh: una superficie, pesi rigidi, tutte le ossa usate
	var ruiz: NPCDefinition = load(NPCLibrary.CHARACTERS_DIR.path_join("ruiz.tres"))
	var st := NPCBodyBuilder.Stats.new()
	var mesh := NPCBodyBuilder.build_mesh(ruiz, {}, st)
	check(mesh.get_surface_count() == 1 and mesh.surface_get_material(0) == NPCBodyBuilder.material(), "una superficie con il materiale condiviso")
	check(st.triangles > 500 and st.triangles < 2500, "triangoli in stile SS2: %d" % st.triangles)
	var arr := mesh.surface_get_arrays(0)
	var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var rigid := true
	var used := {}
	for i in w.size() / 4:
		rigid = rigid and is_equal_approx(w[i * 4], 1.0) and w[i * 4 + 1] == 0.0 and w[i * 4 + 2] == 0.0 and w[i * 4 + 3] == 0.0
		used[b[i * 4]] = true
	check(rigid, "pesi rigidi: ogni vertice al 100% su un osso")
	check(used.size() == NPCRig.BONES.size(), "tutte le %d ossa hanno geometria (%d)" % [NPCRig.BONES.size(), used.size()])
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var glow := 0
	for c in cols:
		if c.a < 0.5:
			glow += 1
	check(glow > 0, "visore e impianto CALMA marcati come luminosi (%d vertici)" % glow)
	# proporzioni
	var lay := NPCRig.layout(ruiz)
	check(absf(lay.top - ruiz.height) < 0.01, "l'altezza della definizione è la sommità della testa")
	var tall := ruiz.clone()
	tall.height = 2.0
	check(tall.eye_height() > ruiz.eye_height() + 0.2, "più alto = occhi più alti")
	# determinismo del generatore
	var a1 := NPCLibrary.random_npc(NPCDefinition.Archetype.GUARDIA, 5)
	var a2 := NPCLibrary.random_npc(NPCDefinition.Archetype.GUARDIA, 5)
	var same := a1.height == a2.height and a1.palette == a2.palette and a1.display_name == a2.display_name
	for k in a1.parts:
		same = same and a1.parts[k].shape == a2.parts[k].shape
	check(same, "stesso seme = stesso NPC")
	var a3 := NPCLibrary.random_npc(NPCDefinition.Archetype.GUARDIA, 6)
	check(a3.height != a1.height or a3.palette != a1.palette, "seme diverso = NPC diverso")
	# cache della mesh
	var m1 := NPCBodyBuilder.get_mesh(a1)
	check(NPCBodyBuilder.get_mesh(a1) == m1, "mesh in cache se la definizione non cambia")
	a1.mass = 1.3
	check(NPCBodyBuilder.get_mesh(a1) != m1, "mesh ricostruita dopo una modifica")
	# corpo animato
	var body := NPCBody.new()
	body.definition = ruiz
	lvl.add_child(body)
	await frames(2)
	check(body.skeleton.get_bone_count() == NPCRig.BONES.size() and body.mesh_instance.skin.get_bind_count() == NPCRig.BONES.size(), "scheletro e skin con %d ossa" % NPCRig.BONES.size())
	body.update_motion(0.016, 0.0, 0.0, 0.0)
	var m0 := body.muzzle_position()
	for i in 40:
		body.update_motion(0.05, 0.0, 0.0, 1.0)
	var m_aim := body.muzzle_position()
	check(m_aim.y > m0.y + 0.4, "in mira la pistola si alza (%.2f -> %.2f)" % [m0.y, m_aim.y])
	var hand := body.bone_index("hand_l")
	var h0 := body.skeleton.get_bone_global_pose(hand).origin
	body.update_motion(0.016, 1.8, PI * 0.5, 0.0)
	var h1 := body.skeleton.get_bone_global_pose(hand).origin
	check(h0.distance_to(h1) > 0.05, "camminando le braccia oscillano")
	body.lod_interval = 0.2
	body.update_motion(0.016, 1.8, PI * 1.5, 0.0)
	check(body.skeleton.get_bone_global_pose(hand).origin.is_equal_approx(h1), "LOD: posa non aggiornata prima dell'intervallo")
	body.queue_free()
	await _npc_render_checks(ruiz)
	# costi
	var t0 := Time.get_ticks_usec()
	for i in 20:
		NPCBodyBuilder.build_mesh(NPCLibrary.random_npc(i % 5, 900 + i))
	var build_ms := (Time.get_ticks_usec() - t0) / 20000.0
	var bodies: Array[NPCBody] = []
	for i in 50:
		var bb := NPCBody.new()
		bb.definition = ruiz
		lvl.add_child(bb)
		bodies.append(bb)
	await frames(1)
	t0 = Time.get_ticks_usec()
	for f in 20:
		for bb in bodies:
			bb.update_motion(0.016, 1.8, f * 0.3, 0.0)
	var pose_us := (Time.get_ticks_usec() - t0) / (20.0 * 50.0)
	for bb in bodies:
		bb.queue_free()
	print("      costruzione di un NPC (dati + mesh): %.2f ms   posa per NPC per frame: %.1f µs" % [build_ms, pose_us])
	check(build_ms < 50.0, "costruzione della mesh sotto i 50 ms")
	finish()


## Controlli di resa del corpo e dei parametri della guardia (bug trovati in review).
func _npc_render_checks(ruiz: NPCDefinition) -> void:
	var d := ruiz.clone()
	d.palette = PackedColorArray([Color(0.9, 0.1, 0.1), Color(0.1, 0.9, 0.1), Color(0.1, 0.1, 0.9),
		Color(0.9, 0.9, 0.1), Color(0.2, 0.2, 0.2), Color(0.9, 0.1, 0.9), Color(0.1, 0.9, 0.9)])
	# tappi: con split = 1 hanno il colore del segmento, non quello della seconda banda
	var sh := SegmentShape.create(SegmentShape.Category.TORACE, 0.1, 0.1, [Vector2(0, 1), Vector2(1, 1)], [], {"cap_start": true, "cap_end": true})
	sh.color_slot = SegmentShape.Slot.UNIFORME
	sh.color_slot_b = SegmentShape.Slot.STIVALI
	var cols := _loft_colors(d, sh)
	var all_main := true
	for c in cols:
		all_main = all_main and c.is_equal_approx(d.color(SegmentShape.Slot.UNIFORME))
	check(all_main and cols.size() > 0, "tappi del colore del segmento (split = 1)")
	sh.split = 0.5
	cols = _loft_colors(d, sh)
	var n_b := 0
	for c in cols:
		if c.is_equal_approx(d.color(SegmentShape.Slot.STIVALI)):
			n_b += 1
	check(n_b > 0 and n_b < cols.size(), "con split 0.5 il tappo finale prende la seconda banda")
	# parti luminose: ogni vertice dell'impianto CALMA è emissivo
	var calma := -1
	for i in d.attachments.size():
		if d.attachments[i].shape != null and d.attachments[i].shape.band == SegmentShape.Band.LUCE:
			calma = i
	check(calma >= 0, "Ruiz ha un accessorio luminoso")
	if calma >= 0:
		var with_st := NPCBodyBuilder.Stats.new()
		var m_with := NPCBodyBuilder.build_mesh(d, {}, with_st)
		d.attachments[calma].enabled = false
		var m_without := NPCBodyBuilder.build_mesh(d)
		d.attachments[calma].enabled = true
		var dv := _glow_count(m_with) - _glow_count(m_without)
		var dt := m_with.surface_get_array_len(0) - m_without.surface_get_array_len(0)
		check(dt > 0 and dv == dt, "impianto CALMA tutto luminoso (%d vertici su %d)" % [dv, dt])
	# mirror su un osso centrale: due copie (le cuffie di Hale)
	var one := NPCDefinition.new()
	one.parts = d.parts
	one.attachments = [NPCLibrary.attachment_from("cuffia")]
	one.attachments[0].mirror = false
	var single := NPCBodyBuilder.build_mesh(one).surface_get_array_len(0)
	one.attachments[0].mirror = true
	var both := NPCBodyBuilder.build_mesh(one).surface_get_array_len(0)
	one.attachments = []
	var none := NPCBodyBuilder.build_mesh(one).surface_get_array_len(0)
	check(both - none == 2 * (single - none), "mirror sulla testa: due cuffie (%d → %d vertici)" % [single - none, both - none])
	# accessori: seguono la larghezza dei fianchi come il bacino
	var wide := d.clone()
	wide.hips = 1.3
	var lay := NPCRig.layout(wide)
	var rh: Vector2 = lay.radial["hips"]
	check(rh.x > rh.y * 1.2, "accessori sul bacino larghi quanto i fianchi (%.3f × %.3f)" % [rh.x, rh.y])
	# la bocca dell'arma non dipende dal nome della forma
	var renamed := d.clone()
	for a in renamed.attachments:
		if a.shape != null and a.shape.is_weapon:
			a.shape = a.shape.duplicate(true)
			a.shape.resource_name = "arma_senza_nome"
			a.label = "Arma"
	check(NPCBodyBuilder.muzzle_local(renamed) == NPCBodyBuilder.muzzle_local(d), "bocca dell'arma trovata anche con un altro nome")
	# posa: fermandosi le gambe rallentano invece di scattare alla posa neutra
	var body := NPCBody.new()
	body.definition = d
	lvl.add_child(body)
	await frames(1)
	for i in 60:
		body.update_motion(0.016, 1.8, PI * 0.5, 0.0)
	var thigh := body.bone_index("thigh_l")
	var before := body.skeleton.get_bone_pose_rotation(thigh).get_angle()
	body.update_motion(0.016, 0.0, PI * 0.5, 0.0)
	var after := body.skeleton.get_bone_pose_rotation(thigh).get_angle()
	check(before > 0.1 and after > before * 0.8, "fermandosi la gamba non scatta (%.2f → %.2f rad)" % [before, after])
	body.queue_free()
	# valori impossibili nella definizione non bloccano la guardia
	var bad := d.clone()
	bad.walk_speed = 0.0
	bad.run_speed = 0.0
	bad.reaction_time = -1.0
	bad.hearing = 0.0
	bad.sight_range = 0.0
	var g := Guard.new()
	g._apply_definition(bad)
	check(g.walk_speed >= 0.3 and g.run_speed >= g.walk_speed and g.reaction_time >= 0.2 and g.hearing > 0.0 and g.sight_range >= 1.0,
		"valori della definizione validati (passo %.1f, reazione %.1f)" % [g.walk_speed, g.reaction_time])
	g.free()


func _loft_colors(d: NPCDefinition, sh: SegmentShape) -> PackedColorArray:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ctx := {"st": st, "def": d, "group": 1, "tris": 0, "verts": 0, "aabb": AABB(), "first": true}
	NPCBodyBuilder._loft(ctx, sh, null, 0.0, Transform3D.IDENTITY, 1.0, Vector2.ONE, 0, false, false)
	return st.commit_to_arrays()[Mesh.ARRAY_COLOR]


func _glow_count(m: ArrayMesh) -> int:
	var n := 0
	for c in m.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		if c.a < 0.5:
			n += 1
	return n


## Stress test: 10, 25, 50, 100 guardie casuali nella hall. Misura il tempo di un frame
## (media e 95° percentile, dal tempo reale fra un frame e l'altro: comprende IA,
## percezione, navigazione, animazione e, con un display, il rendering) e le draw call
## (solo con un display). Non è un test che passa o fallisce: stampa una tabella.
func run_stress() -> void:
	await frames(20)
	lvl = Game.level
	p = Game.player
	p.god_mode = true
	Game.ui._begin()
	await wait(0.5)
	# il player resta nell'ascensore: le guardie fanno la ronda senza vederlo
	await tp(Vector3(19.4, 0.05, 15.2), 90)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var added := 0
	print("  guardie   frame ms (media)   frame ms (95%)   draw call")
	for n in [10, 25, 50, 100]:
		while added < n:
			var def := NPCLibrary.random_npc(NPCDefinition.Archetype.GUARDIA, 5000 + added)
			var pos := Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 5))
			var to := pos + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
			var g := Guard.new().setup_def(def, pos, rng.randf_range(0, 360), [[pos, rng.randf_range(1, 3)], [to, rng.randf_range(1, 3)]])
			lvl.spawn(g, "Guardie")
			added += 1
		# lo spawn (mesh generate nello stesso frame) non entra nella misura
		await wait(1.5)
		var times: Array[float] = []
		var dc_sum := 0.0
		var t_prev := Time.get_ticks_usec()
		var t_start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t_start < 2500:
			await get_tree().process_frame
			var t_now := Time.get_ticks_usec()
			times.append((t_now - t_prev) / 1000.0)
			t_prev = t_now
			dc_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		times.sort()
		var avg := 0.0
		for t in times:
			avg += t
		avg /= times.size()
		var p95: float = times[mini(int(times.size() * 0.95), times.size() - 1)]
		print("  %7d   %16.2f   %14.2f   %9.0f" % [get_tree().get_nodes_in_group("guards").size(), avg, p95, dc_sum / times.size()])
	finish(false)


func run_post_restart() -> void:
	await wait(1.5)
	check(Game.level != null and Game.player != null and Game.player.health > 0.0, "riavvio: livello ricostruito")
	check(Game.state == Game.State.MENU and Game.ui.current_kind == "start", "riavvio: menu iniziale")
	check(Game.logs_read.is_empty() and Game.stats.kills == 0, "riavvio: stato azzerato")
	finish()


func check(cond: bool, what: String) -> void:
	if cond:
		oks += 1
		print("OK:   ", what)
	else:
		fails += 1
		print("FAIL: ", what)


func wait(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func tp(pos: Vector3, yaw_deg: float, pitch_deg := 0.0) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.rotation.y = p.yaw
	p.pitch = deg_to_rad(pitch_deg)
	p.head.rotation.x = p.pitch
	await frames(4)


func face(target: Vector3) -> void:
	var eye: Vector3 = p.camera.global_position
	var d := target - eye
	p.yaw = atan2(-d.x, -d.z)
	p.rotation.y = p.yaw
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	p.head.rotation.x = p.pitch
	await frames(3)


func shot(name: String) -> void:
	if not shots:
		return
	await wait(0.35)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_dir.path_join(name + ".png"))
	print("shot: ", name)


func frob_expect(what: String) -> Node:
	await frames(3)
	var t: Node = p.frob_target
	check(t != null, "frob target: " + what + (" -> " + t.get_frob_text() if t else ""))
	if t:
		t.frob(p)
	await frames(2)
	return t


func close_ui() -> void:
	if Game.ui.is_open():
		Game.ui.close_panel()
	await frames(2)


func _nav_path_ok(a: Vector3, b: Vector3) -> bool:
	var map: RID = lvl.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	return path.size() > 1 and path[path.size() - 1].distance_to(b) < 0.8


## Lingua: traduzioni caricate, fallback in inglese, titoli dei nomi, impostazioni.
func _check_language() -> void:
	check(not Game.persist_settings, "test: impostazioni non lette né salvate su disco")
	var it := TranslationServer.get_translation_object("it")
	check(it != null and String(it.get_message("Resume")) == "Riprendi", "traduzione italiana caricata (locale/it.po)")
	check(TranslationServer.get_locale().begins_with(Game.settings.language), "lingua attiva: %s" % Game.language_name())
	if Game.settings.language == "it":
		check(Game.person_name("Ofc. Rossi") == "Ag. Rossi" and Game.skill_name("forza") == "FORZA", "italiano: titoli e skill tradotti")
	else:
		check(Game.person_name("Ofc. Rossi") == "Ofc. Rossi" and Game.skill_name("forza") == "STRENGTH", "inglese: testi sorgente")
	check(tr("A sentence nobody translated.") == "A sentence nobody translated.", "frase senza traduzione: resta in inglese")
	# insegne con scritte: seguono la lingua anche a partita in corso
	var sign: MeshInstance3D = lvl.find_child("Pannello_sign_sec1", true, false)
	var sign_tex := func() -> String: return (sign.material_override as StandardMaterial3D).albedo_texture.resource_path
	var lang0: String = Game.settings.language
	Game.set_language("it", false)
	var it_path: String = sign_tex.call()
	Game.set_language("en", false)
	var en_path: String = sign_tex.call()
	Game.set_language(lang0, false)
	check(it_path.ends_with("sign_sec_it.png") and en_path.ends_with("sign_sec.png"), "insegna SECURITY/SICUREZZA segue la lingua")
	# salva e rilegge da un file di prova (non tocca le impostazioni vere)
	var saved: Dictionary = Game.settings.duplicate()
	var other := "it" if saved.language == "en" else "en"
	Game.settings_path = "user://test_settings.cfg"
	Game.persist_settings = true
	Game.settings.volume = 0.33
	Game.settings.language = other
	Game.save_settings()
	Game.settings = saved.duplicate()
	Game.load_settings()
	check(is_equal_approx(Game.settings.volume, 0.33) and Game.settings.language == other, "impostazioni salvate e rilette")
	# --lang=xx vale solo per la sessione: si salva la lingua scelta dal giocatore
	Game._saved_language = saved.language
	Game.settings.language = other
	Game.save_settings()
	var cfg := ConfigFile.new()
	cfg.load(Game.settings_path)
	var kept: bool = cfg.get_value("settings", "language") == saved.language
	Game.set_language(other)   # ora sceglie il giocatore: questa si salva
	cfg.load(Game.settings_path)
	check(kept and cfg.get_value("settings", "language") == other and Game._saved_language == "", "--lang non sovrascrive la lingua salvata")
	Game.set_language(saved.language, false)
	var f := FileAccess.open(Game.settings_path, FileAccess.WRITE)
	f.store_string("[settings]\nlanguage=\"xx\"\nvolume=\"forte\"\npixel_scale=9\nsensitivity=nan\n")
	f.close()
	Game.settings = saved.duplicate()
	Game.load_settings()
	check(Game.settings.language == "en" and is_equal_approx(Game.settings.volume, saved.volume) and Game.settings.pixel_scale == 4 \
			and is_equal_approx(Game.settings.sensitivity, saved.sensitivity),
		"file di impostazioni rovinato: valori non validi ignorati")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.settings_path))
	Game.settings_path = Game.SETTINGS_PATH
	Game.persist_settings = false
	Game.settings = saved


func guard(n: String) -> Node:
	for g in get_tree().get_nodes_in_group("guards"):
		if g.guard_name == n:
			return g
	return null


func run() -> void:
	await frames(20)
	lvl = Game.level
	p = Game.player
	p.god_mode = true
	check(lvl != null and p != null, "livello e player creati")
	_check_language()
	check(get_tree().get_nodes_in_group("game_lights").size() > 20, "luci registrate: %d" % get_tree().get_nodes_in_group("game_lights").size())

	# --- navigazione
	check(_nav_path_ok(Vector3(-7, 0, -3.5), Vector3(-2.8, 0, -19.5)), "navmesh: hall -> laboratorio")
	check(_nav_path_ok(Vector3(-7, 0, -3.5), Vector3(-16.3, 0, 0.6)), "navmesh: hall -> sala sicurezza")
	check(_nav_path_ok(Vector3(0, 0, 0), Vector3(-14, 0, 9)), "navmesh: hall -> magazzino")
	check(_nav_path_ok(Vector3(0, 0, 0), Vector3(15, 0, -2)), "navmesh: hall -> sala relax")
	check(_nav_path_ok(Vector3(0, 0, 0), Vector3(15, 0, 15)), "navmesh: hall -> partenza")
	check(not _nav_path_ok(Vector3(15, 0, -2), Vector3(16, 1.0, -12)), "navmesh: i condotti non sono percorribili dalle guardie")

	# --- inizio missione con build hacker/furtivo
	Game.start_alloc = {"hacking": 2, "armi": 0, "forza": 1, "furtivita": 1}
	if shots:
		Game.ui.show_start()
		await shot("ui_01_menu_iniziale")
	Game.ui._begin()
	await wait(0.5)
	check(Game.state == Game.State.PLAYING, "missione iniziata")
	check("vesper" in Game.logs_read, "briefing nel PDA")
	await shot("01_ascensore")

	# --- movimento
	var start: Vector3 = p.global_position
	Input.action_press("move_forward")
	await wait(1.2)
	Input.action_release("move_forward")
	check(p.global_position.x < start.x - 2.0, "il player cammina (x %.2f -> %.2f)" % [start.x, p.global_position.x])
	check(p.is_on_floor(), "il player è a terra")

	# --- visibilità: luce contro buio
	await tp(Vector3(0, 0.05, 1.5), 0)
	await wait(0.3)
	var lit: float = p.light_level
	await tp(Vector3(-8.8, 0.05, 7.2), 0)
	p.crouch_toggled = true
	await wait(0.4)
	var dark: float = p.light_level
	var dark_vis: float = p.visibility
	p.crouch_toggled = false
	print("      luce sotto il faro: %.2f   angolo buio: %.2f (visibilità accovacciato %.2f)" % [lit, dark, dark_vis])
	check(lit > 0.45 and dark < 0.25 and lit > dark * 2.5, "la visibilità dipende dalla luce")

	# --- telecamera della hall: allarme se ti vede in piena luce
	await tp(Vector3(6.5, 0.05, 1.5), 160)
	var alarm := false
	for i in 80:
		await wait(0.1)
		if Game.alarm_time > 0.0:
			alarm = true
			break
	check(alarm, "la telecamera della hall fa scattare l'allarme")
	check(not Game.is_objective_active("noalarm"), "obiettivo 'nessun allarme' fallito")
	# --- torretta del corridoio
	var hp_t: float = p.health
	await tp(Vector3(0.3, 0.05, -10.5), 0)
	for i in 60:
		await wait(0.1)
		if p.health < hp_t:
			break
	check(p.health < hp_t, "la torretta spara (salute %d)" % int(p.health))
	# ripristino
	p.health = p.max_health
	Game.alarm_time = 0.0
	Sfx.set_alarm(false)
	for g in get_tree().get_nodes_in_group("guards"):
		g.state = Guard.S.PATROL
		g.awareness = 0.0
		g.alertness = 0.0
		g.global_position = g.post_pos
	await tp(Vector3(6.0, 0.05, 12.0), 0)
	await wait(3.0)
	var turret := lvl.find_child("Torretta", true, false) as Turret
	turret.awareness = 0.0
	turret.state = Turret.T.IDLE

	# --- porta di servizio + hall
	await tp(Vector3(6.0, 0.05, 10.0), 0)
	await face(Vector3(6.0, 1.3, 8.5))
	var d1 := await frob_expect("porta hall")
	await wait(0.8)
	check(d1 != null and d1.is_open(), "porta si apre col frob")
	await shot("02_hall_dalla_porta")

	# --- sala relax: registri e grata
	await tp(Vector3(14.6, 0.05, 0.2), 180, -35)
	await face(Vector3(14.6, 0.81, -1.2))
	await frob_expect("datapad turni")
	check("turni" in Game.logs_read and Game.ui.current_kind == "log", "registro letto e mostrato")
	await close_ui()
	await tp(Vector3(17.6, 0.05, -3.5), -90)
	await face(Vector3(18.95, 1.5, -3.5))
	await frob_expect("terminale okafor1")
	await close_ui()
	check("okafor1" in Game.logs_read, "terminale a muro letto")
	await tp(Vector3(13.4, 0.05, -4.6), 180, -20)
	await face(Vector3(13.6, 0.91, -5.5))
	await frob_expect("cyber-modulo")
	check(Game.modules == 1, "modulo raccolto")
	await shot("03_sala_relax")
	if shots:
		Game.ui.open_pda(1)
		await shot("ui_02_pda_registri")
		Game.ui.open_upgrade()
		await shot("ui_03_potenziamento")
		await close_ui()

	# grata (Forza 1: si toglie a mano)
	await tp(Vector3(16.05, 0.05, -4.9), 180, 5)
	await face(Vector3(16.05, 1.55, -6.0))
	var grate := await frob_expect("grata sala relax")
	await wait(0.2)
	check(grate is VentGrate and grate.removed and grate.collision_layer == 0, "grata rimossa")
	# mantle nel condotto
	await tp(Vector3(16.05, 0.05, -5.55), 0, 0)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await wait(0.8)
	check(p.global_position.y > 0.9 and p.crouching, "mantle nel condotto (y %.2f, accovacciato %s)" % [p.global_position.y, p.crouching])
	Input.action_press("move_forward")
	await wait(2.0)
	Input.action_release("move_forward")
	check(p.global_position.z < -8.0, "si striscia nel condotto (z %.2f)" % p.global_position.z)
	await shot("04_condotto")
	# ramo segreto
	await tp(Vector3(18.4, 1.05, -13.45), -90, -30)
	await face(Vector3(19.1, 1.02, -13.2))
	await frob_expect("datapad intruso")
	await close_ui()
	await face(Vector3(19.5, 1.02, -13.6))
	await frob_expect("modulo segreto")
	check("condotto" in Game.secrets_found, "segreto trovato")
	# uscita nel laboratorio (calcio alla grata)
	await tp(Vector3(8.6, 1.05, -21.45), 90, 0)
	await face(Vector3(8.0, 1.55, -21.45))
	var g2 := await frob_expect("grata lato laboratorio")
	await wait(0.2)
	check(g2 is VentGrate and g2.removed and g2.collision_layer == 0, "grata del laboratorio sfondata")
	await tp(Vector3(9.0, 1.05, -21.45), 90, -15)
	await shot("05_laboratorio_dal_condotto")

	# --- sala sicurezza: codice 0451
	await tp(Vector3(-8.8, 0.05, 1.8), 90, 0)
	await face(Vector3(-10.5, 1.3, 1.8))
	var od := await frob_expect("porta sicurezza")
	check(Game.ui.current_kind == "lock", "pannello serratura aperto")
	await shot("ui_04_tastierino")
	check(not od.try_code("1234") and od.try_code("0451"), "codice 0451 accettato, 1234 rifiutato")
	await close_ui()
	await wait(0.8)
	check(od.is_open(), "porta sicurezza aperta")
	# tessera laboratorio
	await tp(Vector3(-12.6, 0.05, -2.4), 180, -30)
	await face(Vector3(-12.6, 0.91, -3.6))
	await frob_expect("tessera laboratorio")
	check(Game.has_keycard("lab"), "tessera laboratorio raccolta")
	await shot("06_sala_sicurezza")

	# --- terminale di sicurezza via minigioco di hacking (forzato)
	var term: Node = null
	for e in lvl.find_children("*", "", true, false):
		if e is SecurityTerminal:
			term = e
	Game.ui.open_lock(term)
	Game.ui.open_hack(term, term.get_lock_info())
	if shots:
		Game.ui._hk.p = 0.0
		Game.ui._hack_click(0, 0)
		Game.ui._hk.p = 1.0
		Game.ui._hack_click(0, 1)
		await shot("ui_05_hacking")
	Game.ui._hk.p = 1.0
	for c in 5:
		Game.ui._hack_click(c, 1)
	await wait(1.0)
	check(Game.ui.current_kind == "terminal", "hack riuscito: terminale aperto")
	term.terminal_action("cams")
	term.terminal_action("turret")
	await close_ui()
	var cams_off := true
	for c in get_tree().get_nodes_in_group("security_cameras"):
		cams_off = cams_off and c.disabled
	check(cams_off and not turret.is_hostile_active(), "telecamere e torretta disattivate")

	# --- IA: una guardia mi vede in piena luce
	var hale := guard("Op. Hale")
	await tp(Vector3(-13.0, 0.05, 0.6), 90, 0)
	hale.post_yaw = deg_to_rad(-90)  # si gira verso il player
	hale.rotation.y = hale.post_yaw
	var hp0: float = p.health
	var seen := false
	for i in 40:
		await wait(0.1)
		if hale.state == Guard.S.COMBAT:
			seen = true
			break
	check(seen, "Hale entra in combattimento vedendo il player (awareness %.2f, vis %.2f)" % [hale.awareness, p.visibility])
	for i in 70:
		await wait(0.1)
		if p.health < hp0:
			break
	check(p.health < hp0, "la guardia spara e colpisce (salute %d)" % int(p.health))
	p.health = p.max_health

	# --- KO silenzioso alle spalle e perquisizione
	var kov := guard("Ofc. Kovač")
	kov.state = Guard.S.PATROL
	kov.awareness = 0.0
	kov._wait = 10.0
	var behind: Vector3 = kov.global_position + kov.global_basis.z * 1.2
	await tp(Vector3(behind.x, 0.05, behind.z), rad_to_deg(kov.rotation.y), -10)
	check(kov.can_knockout(p.global_position), "KO possibile alle spalle")
	await face(kov.global_position + Vector3.UP * 1.5)
	p.weapon = 0
	p._swing()
	await wait(0.4)
	check(kov.state == Guard.S.DOWN and not kov.dead, "Kovač messo KO con la chiave inglese")
	var ammo0: int = Game.ammo_reserve
	kov.frob(p)
	check(Game.ammo_reserve > ammo0, "perquisizione: munizioni recuperate")
	kov.frob(p)
	check(p.carried_body == kov, "corpo sollevato")
	await tp(Vector3(-5.5, 0.05, -20), 0)
	p._drop_body()
	await wait(0.5)
	check(p.carried_body == null and kov.visible, "corpo posato")

	# --- borseggio (Ruiz, alle spalle, al buio)
	var ruiz := guard("Ofc. Ruiz")
	ruiz.state = Guard.S.PATROL
	ruiz.awareness = 0.0
	ruiz._wait = 10.0
	var rb: Vector3 = ruiz.global_position + ruiz.global_basis.z * 0.9
	await tp(Vector3(rb.x, 0.05, rb.z), rad_to_deg(ruiz.rotation.y), -10)
	check(ruiz.get_frob_text().begins_with(_label("Pickpocket %s")), "borseggio disponibile alle spalle")
	ruiz.frob(p)
	check(Game.has_keycard("sicurezza"), "tessera sicurezza borseggiata")

	# --- lancio di un oggetto: rumore
	var can: Node = null
	for t in get_tree().get_nodes_in_group("throwables"):
		if t.shape_kind == "can":
			can = t
			break
	await tp(can.global_position + Vector3(0.9, 0.0, 0.0) + Vector3(0, 0.05, 0), 90, -40)
	await face(can.global_position)
	await frob_expect("lattina")
	check(p.held == can, "lattina in mano")
	await face(p.camera.global_position + Vector3(0, 0.6, -3))
	var throw_from: Vector3 = can.global_position
	p._drop_held(true)
	await wait(1.2)
	check(p.held == null and can.global_position.distance_to(throw_from) > 2.5, "lattina lanciata a %.1f m" % can.global_position.distance_to(throw_from))

	# --- laboratorio: porta con tessera, registro, nucleo e lockdown
	Game.alarm_time = 0.0
	await tp(Vector3(0, 0.05, -16.0), 0, 0)
	await face(Vector3(0, 1.3, -17.5))
	var ld := await frob_expect("porta laboratorio")
	await wait(0.9)
	check(ld.is_open(), "porta laboratorio aperta con la tessera")
	await tp(Vector3(-4.4, 0.05, -28.1), 180, -30)
	await face(Vector3(-4.4, 0.91, -29.1))
	await frob_expect("diario okafor")
	await close_ui()
	check(not Game.is_objective_active("okafor") , "obiettivo Okafor completato")
	await tp(Vector3(0, 0.05, -25.6), 0, -5)
	await shot("07_nucleo")
	await face(Vector3(0, 1.25, -27.3))
	await frob_expect("nucleo")
	check(Game.has_item("core") and not Game.is_objective_active("core"), "nucleo estratto")
	await wait(4.5)
	check(Game.lockdown and guard("Ofc. Mori") != null, "lockdown: rinforzo arrivato")
	await tp(Vector3(0, 0.05, 3), 0, 5)
	await shot("08_lockdown_hall")
	if shots:
		Game.ui.open_pause()
		await shot("ui_06_pausa")
		await close_ui()

	# --- estrazione
	await tp(Vector3(19.4, 0.05, 15.2), 180, -10)
	await face(Vector3(19.9, 1.3, 14.04))
	await frob_expect("pulsantiera ascensore")
	await wait(3.0)
	check(Game.state == Game.State.COMPLETE, "missione completata")
	check(Game.ui.current_kind == "complete", "schermata finale mostrata")
	await shot("09_fine")
	print("VALUTAZIONE: ", Game.rating())
	finish()
