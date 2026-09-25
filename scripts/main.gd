extends Node
## Scena principale. Il mondo 3D viene renderizzato in un SubViewport a bassa
## risoluzione (default 640x360) e scalato con filtro nearest, poi passato allo
## shader di quantizzazione/dithering: il look "Dark Engine" nasce qui.
## HUD e menu restano a risoluzione piena, sopra.

const LevelScript := preload("res://scripts/world/level_seraph.gd")
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
	_apply_settings()

	level = LevelScript.new()
	level.name = "Level"
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
	if "--autotest" in OS.get_cmdline_user_args() and not get_tree().root.has_node("PostRestartTest"):
		var t: Node = load("res://tools/autotest.gd").new()
		t.name = "Autotest"
		add_child(t)
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
	if event.is_action_pressed("pause"):
		if Game.state == Game.State.PLAYING:
			ui.open_pause()
		elif Game.state == Game.State.PANEL:
			ui.close_panel()
		get_viewport().set_input_as_handled()
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
