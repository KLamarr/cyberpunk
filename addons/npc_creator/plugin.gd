@tool
extends EditorPlugin
## Registra la scheda "NPC" (accanto a 2D, 3D, Script) con il creatore di NPC.
## Aprire una NPCDefinition (.tres) dal FileSystem la carica nel creatore.
## Autotest dell'interfaccia (serve l'editor, anche senza finestra), vedi selftest.gd:
##   NPC_CREATOR_SELFTEST=1 godot --headless --editor --path .

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


## Ctrl+S, avvio del gioco, chiusura con salvataggio: salva anche l'NPC aperto, ma solo
## se ha già il suo file e non tocca forme condivise (vedi save_on_editor_save).
func _save_external_data() -> void:
	if is_instance_valid(panel):
		panel.save_on_editor_save()


# --- autotest dell'interfaccia (vedi selftest.gd) ------------------------------------------
func _selftest() -> void:
	var t = load("res://addons/npc_creator/selftest.gd").new()
	t.plugin = self
	await t.run()
