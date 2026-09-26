extends SceneTree
## Traduzioni da riga di comando (la logica è in tools/i18n_core.gd):
##   godot --headless --path . --script res://tools/i18n.gd -- --update [--drop-obsolete]
##       aggiunge a locale/*.po le frasi nuove; --drop-obsolete toglie le obsolete
##   godot --headless --path . --script res://tools/i18n.gd -- --check [--strict]
##       controlla le traduzioni; con --strict anche le frasi non tradotte sono
##       errori (lo usa la CI). Esce con 1 se ci sono errori.
##   godot --headless --path . --script res://tools/i18n.gd -- --new=fr
##       crea locale/fr.po per una nuova lingua
## Dall'editor: apri tools/aggiorna_traduzioni.gd e scegli File → Run.

const Core := preload("res://tools/i18n_core.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var core := Core.new()
	var code := 0
	for a in args:
		if a.begins_with("--new="):
			core.new_language(a.substr(6))
	core.scan()
	if "--update" in args and core.update("--drop-obsolete" in args) > 0:
		code = 1
	if "--check" in args and core.check("--strict" in args) > 0:
		code = 1
	if not ("--update" in args or "--check" in args or Array(args).any(func(a): return String(a).begins_with("--new="))):
		print("Uso: godot --headless --path . --script res://tools/i18n.gd -- --update | --check [--strict] | --new=<lingua>")
		code = 2
	quit(code)
