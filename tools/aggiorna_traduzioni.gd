@tool
extends EditorScript
## AGGIORNA LE TRADUZIONI dall'editor: apri questo file (doppio clic nel FileSystem)
## e, nell'editor degli script, scegli File → Run (Ctrl+Shift+X).
## Aggiunge a locale/it.po le frasi nuove del gioco (da tradurre) e controlla il file:
## il resoconto compare nel pannello Output. Poi traduci le frasi nuove in
## locale/it.po (con Poedit o un editor di testo): vedi docs/GUIDA_EDITOR.md,
## sezione «Testi e traduzioni».


func _run() -> void:
	var core = load("res://tools/i18n_core.gd").new()
	core.scan()
	core.update()
	core.check()
	EditorInterface.get_resource_filesystem().scan()
