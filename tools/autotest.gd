extends Node
## Test automatico end-to-end. Avvio:
##   godot --path . -- --autotest            (headless: logica)
##   xvfb-run godot --path . -- --autotest --shots   (anche screenshot)
## Stampa OK/FAIL per ogni controllo ed esce con codice 0 se tutto passa.

var fails := 0
var oks := 0
var shots := false
var shot_dir := "user://shots"
var p: Node
var lvl: Node
var mode := "full"   # full | death | post_restart


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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


func _find_button(n: Node, prefix: String) -> Button:
	if n is Button and (n as Button).text.begins_with(prefix):
		return n
	for c in n.get_children():
		var b := _find_button(c, prefix)
		if b:
			return b
	return null


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
	check(_press(" + "), "menu: + su una skill")
	check(_press("INIZIA"), "menu: inizia")
	await wait(0.3)
	check(Game.state == Game.State.PLAYING, "partita avviata dal bottone")
	Game.add_modules(3)
	Game.ui.open_upgrade()
	await frames(2)
	var before := 0
	for sk in Game.SKILLS:
		before += Game.skill(sk)
	check(_press("POTENZIA"), "upgrade: bottone potenzia")
	await frames(2)
	var after := 0
	for sk in Game.SKILLS:
		after += Game.skill(sk)
	check(after == before + 1 and Game.ui.current_kind == "upgrade", "upgrade applicato e pannello aggiornato")
	await close_ui()
	p.health = 50.0
	Game.ui.open_pda(2)
	await frames(2)
	check(_press("Usa"), "PDA: usa medipatch")
	await frames(2)
	check(p.health > 50.0 and Game.ui.current_kind == "pda", "medipatch usato dal PDA")
	await close_ui()
	Game.ui.open_pause()
	await frames(2)
	var sc: int = Game.settings.pixel_scale
	check(_press("Risoluzione interna"), "pausa: risoluzione")
	check(Game.settings.pixel_scale != sc, "risoluzione cambiata")
	check(_press("Dithering"), "pausa: dithering")
	check(_press("Riprendi"), "pausa: riprendi")
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
	print("RISULTATO: %d ok, %d fail" % [oks, fails])
	get_tree().quit(0 if fails == 0 else 1)


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
	var rossi := guard("Ag. Rossi")
	var from: Vector3 = rossi.global_position
	await wait(6.0)
	check(rossi.global_position.distance_to(from) > 1.0, "guida: la guardia fa la ronda (%.1f m)" % rossi.global_position.distance_to(from))
	await tp(Vector3(2.2, 0.05, -10.2), 0, 0)
	await face(Vector3(-0.8, 1.1, -5.5))
	await wait(0.8)
	await shot("guida_02_magazzino")
	print("RISULTATO: %d ok, %d fail" % [oks, fails])
	get_tree().quit(0 if fails == 0 else 1)


func run_post_restart() -> void:
	await wait(1.5)
	check(Game.level != null and Game.player != null and Game.player.health > 0.0, "riavvio: livello ricostruito")
	check(Game.state == Game.State.MENU and Game.ui.current_kind == "start", "riavvio: menu iniziale")
	check(Game.logs_read.is_empty() and Game.stats.kills == 0, "riavvio: stato azzerato")
	print("RISULTATO: %d ok, %d fail" % [oks, fails])
	get_tree().quit(0 if fails == 0 else 1)


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
	check(grate == null or not is_instance_valid(grate), "grata rimossa")
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
	check(g2 == null or not is_instance_valid(g2), "grata del laboratorio sfondata")
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
	var kov := guard("Ag. Kovač")
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
	var ruiz := guard("Ag. Ruiz")
	ruiz.state = Guard.S.PATROL
	ruiz.awareness = 0.0
	ruiz._wait = 10.0
	var rb: Vector3 = ruiz.global_position + ruiz.global_basis.z * 0.9
	await tp(Vector3(rb.x, 0.05, rb.z), rad_to_deg(ruiz.rotation.y), -10)
	check(ruiz.get_frob_text().begins_with("Borseggia"), "borseggio disponibile alle spalle")
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
	check(Game.lockdown and guard("Ag. Mori") != null, "lockdown: rinforzo arrivato")
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
	print("RISULTATO: %d ok, %d fail" % [oks, fails])
	get_tree().quit(0 if fails == 0 else 1)
