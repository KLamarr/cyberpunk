extends Node
## Scena principale. Il mondo 3D viene renderizzato in un SubViewport a bassa
## risoluzione (default 640x360) e scalato con filtro nearest, poi passato allo
## shader di quantizzazione/dithering: il look "Dark Engine" nasce qui.
## HUD e menu restano a risoluzione piena, sopra.

const HudScript := preload("res://scripts/ui/hud.gd")
const UIScript := preload("res://scripts/ui/ui_root.gd")
const POST := preload("res://shaders/retro_post.gdshader")

var container: SubViewportContainer
var viewport: SubViewport
var level: Node3D
var post_mat: ShaderMaterial
var hud: CanvasLayer
var ui: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	container = SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = POST
	container.material = post_mat
	add_child(container)
	viewport = SubViewport.new()
	viewport.audio_listener_enable_3d = true
	viewport.handle_input_locally = false
	viewport.positional_shadow_atlas_size = 4096
	container.add_child(viewport)
	Game.world_viewport = viewport   # per l'anteprima dei salvataggi
	_apply_settings()

	if "--convert-seraph" in OS.get_cmdline_user_args():
		add_child(load("res://tools/convert_seraph.gd").new())
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			Game.level_path = a.substr(8)
	var level_scene: PackedScene = load(Game.level_path)
	level = level_scene.instantiate()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	viewport.add_child(level)

	hud = HudScript.new()
	hud.name = "HUD"
	add_child(hud)
	ui = UIScript.new()
	ui.name = "UI"
	add_child(ui)
	Game.settings_changed.connect(_apply_settings)

	if "--write-input-map" in OS.get_cmdline_user_args():
		Game.write_input_map_to_project()
		get_tree().quit()
		return
	var tool_script := ""
	if "--validate" in OS.get_cmdline_user_args():
		tool_script = "res://tools/validate_level.gd"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tool="):
			tool_script = a.substr(7)
	if not Game.pending_load.is_empty():
		# caricamento di un salvataggio: la scena è pronta, si applica lo stato
		Game.finish_load.call_deferred()
	elif tool_script != "":
		# strumenti di sviluppo (es. tools/validate_level.gd) che girano sul livello caricato
		var scr: GDScript = load(tool_script)
		if scr == null or not scr.can_instantiate():
			push_error("Script non valido: " + tool_script)
			get_tree().quit(3)
			return
		var tl: Node = scr.new()
		tl.name = "Tool"
		add_child(tl)
	elif "--autotest" in OS.get_cmdline_user_args() and not get_tree().root.has_node("PostRestartTest"):
		var ts: GDScript = load("res://tools/autotest.gd")
		if ts == null or not ts.can_instantiate():
			push_error("tools/autotest.gd non si carica (errore nello script)")
			get_tree().quit(3)   # altrimenti il gioco resterebbe aperto fino al timeout
			return
		var t: Node = ts.new()
		t.name = "Autotest"
		add_child(t)
	elif Game.quick_start:
		# livello avviato con F6 dall'editor: niente menu, 1 punto in ogni skill
		for sk in Game.SKILLS:
			Game.start_alloc[sk] = 1
		ui._begin()
		# controlla il livello in sottofondo: errori e avvisi finiscono nell'Output
		var v: Node = load("res://tools/validate_level.gd").new()
		v.quit_when_done = false
		v.name = "Validatore"
		add_child(v)
	else:
		Game.set_state(Game.State.MENU)
		ui.show_start()


func _apply_settings() -> void:
	container.stretch_shrink = int(Game.settings.pixel_scale)
	post_mat.set_shader_parameter("dither_enabled", bool(Game.settings.dither))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Game.state == Game.State.PLAYING and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Game.player:
			Game.player.look(event.relative)
		return
	if event is InputEventMouseButton and event.pressed and Game.state == Game.State.PLAYING and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if ui.capturing_key():
		return   # il pannello Comandi sta aspettando un tasto da assegnare
	if event.is_action_pressed("pause"):
		if Game.state == Game.State.PLAYING:
			ui.open_pause()
		elif Game.state == Game.State.PANEL or (Game.state == Game.State.MENU and ui.current_kind in ["options", "load"]):
			ui.close_panel()
		get_viewport().set_input_as_handled()
		return
	# i tasti rapidi non scattano mentre si scrive un codice nel tastierino, né con i
	# clic nei menu (anche se il giocatore li ha messi su un tasto del mouse o una cifra)
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event is InputEventMouseButton and Game.state != Game.State.PLAYING:
		return
	if event.is_action_pressed("quicksave"):
		Game.quicksave()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quickload") and Game.state != Game.State.MENU:
		get_viewport().set_input_as_handled()   # prima: caricando, la scena (e main) se ne va
		Game.quickload()
	elif event.is_action_pressed("pda"):
		ui.toggle_pda()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_pixel"):
		Game.cycle_pixel_scale()
	elif event.is_action_pressed("toggle_dither"):
		Game.toggle_dither()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Game.state == Game.State.PLAYING and ui != null:
		ui.open_pause()
