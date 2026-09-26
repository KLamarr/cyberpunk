class_name SaveGame
extends RefCounted
## SALVATAGGI: la partita intera in un file (user://saves/<slot>.json) più
## un'anteprima (<slot>.png). Slot: "quick" (F5/F9), "auto" (inizio missione) e
## "1".."5" (manuali, dalla pausa).
##
## Cosa si salva:
##   - lo stato di Game (skill, inventario, obiettivi, registri, statistiche, allarme...);
##   - ogni nodo del livello che ha i metodi save_state() -> Dictionary e
##     load_state(Dictionary), identificato dal suo percorso nella scena: player,
##     guardie, porte, luci, telecamere, torrette, oggetti, trigger...;
##   - i nodi che c'erano all'inizio e non ci sono più (oggetti raccolti, datapad
##     letti, grate sfondate), che al caricamento vengono tolti.
## Per rendere salvabile un'entità nuova basta darle save_state()/load_state(); anche
## un oggetto senza stato che può sparire (raccolto, rotto) deve averli, magari vuoti,
## perché il caricamento sappia toglierlo. Se aggiungi un campo a un save_state()
## esistente, i salvataggi vecchi non lo hanno: il caricamento lascia quell'entità
## com'è all'inizio (con un avviso) invece di caricarla a metà.
## Timer e ritardi della logica di missione: usa Level.later(), che si salva (un timer
## di get_tree() si perde).
## I nodi creati da codice a partita iniziata non si salvano: mettili nella scena
## (es. le guardie di rinforzo sono «dormant» già piazzate).
##
## Il caricamento ricarica la scena da capo e poi applica lo stato (apply()).

const FORMAT := 1
const MANUAL_SLOTS := 5
const THUMB_SIZE := Vector2i(192, 108)

## Cartella dei salvataggi (i test ne usano un'altra, vedi Game._init_settings).
static var dir := "user://saves"


static func slots() -> Array[String]:
	var out: Array[String] = ["quick", "auto"]
	for i in MANUAL_SLOTS:
		out.append(str(i + 1))
	return out


static func path(slot: String) -> String:
	return dir.path_join(slot + ".json")


static func thumb_path(slot: String) -> String:
	return dir.path_join(slot + ".png")


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path(slot))


# --- raccolta e applicazione dello stato -----------------------------------------------
## Nodi del livello che si salvano da sé (compreso il livello, per la logica di missione).
static func savables(level: Node) -> Array[Node]:
	var out: Array[Node] = []
	if level.has_method("save_state"):
		out.append(level)
	for n in level.find_children("*", "", true, false):
		if n.has_method("save_state") and not n.is_queued_for_deletion():
			out.append(n)
	return out


static func collect(level: Level) -> Dictionary:
	var ents := {}
	for n in savables(level):
		ents[String(level.get_path_to(n))] = n.save_state()
	var removed: Array[String] = []
	for p in level.initial_savables:
		if not ents.has(p):
			removed.append(p)
	var done := 0
	for o in Game.objectives:
		if o.state == "done":
			done += 1
	return {
		"format": FORMAT,
		"level": Game.level_path,
		"meta": {
			"saved_at": Time.get_datetime_string_from_system(false, true).substr(0, 16),
			"unix": Time.get_unix_time_from_system(),
			"playtime": float(Game.stats.time),
			"objectives": "%d/%d" % [done, Game.objectives.size()],
		},
		"game": Game.save_state(),
		"audio": {"siren": Sfx.alarm_player.playing},
		"entities": ents,
		"removed": removed,
		"ui": Game.ui.save_state() if Game.ui != null else {},
	}


## Applica uno stato salvato al livello appena caricato.
static func apply(level: Level, data: Dictionary) -> void:
	Game.load_state(data.get("game", {}))
	for p in data.get("removed", []):
		var n := level.get_node_or_null(NodePath(p))
		if n != null:
			n.get_parent().remove_child(n)
			n.queue_free()
	var ents: Dictionary = data.get("entities", {})
	var later: Array = []
	for p in ents:
		var n := level.get_node_or_null(NodePath(p))
		if n == null or not n.has_method("load_state"):
			push_warning("Salvataggio: «%s» non c'è più nel livello (scena modificata?)" % p)
			continue
		# un salvataggio fatto con una versione precedente dell'entità (campi mancanti)
		# la lascerebbe caricata a metà: meglio lasciarla com'è all'inizio
		var cur: Dictionary = n.save_state()
		if typeof(ents[p]) != TYPE_DICTIONARY or not (ents[p] as Dictionary).has_all(cur.keys()):
			push_warning("Salvataggio: lo stato di «%s» è di una versione diversa, resta com'è all'inizio" % p)
			continue
		if n is Player:
			later.append(n)   # dopo gli oggetti e i corpi che potrebbe avere in mano
			continue
		n.load_state(ents[p])
	for n in later:
		n.load_state(ents[String(level.get_path_to(n))])
	if Game.ui != null:
		Game.ui.load_state(data.get("ui", {}))


# --- file --------------------------------------------------------------------------------
static func write(slot: String, data: Dictionary, thumb: Image = null) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	# si scrive su un file temporaneo e poi lo si rinomina: un salvataggio interrotto
	# non rovina quello di prima
	var tmp := path(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Salvataggio: impossibile scrivere %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	var ok := f.store_string(JSON.stringify(JSON.from_native(data)))
	f.flush()
	ok = ok and f.get_error() == OK
	f.close()
	# rename sostituisce il file vecchio in un colpo solo (su Windows ci pensa Godot)
	if not ok or DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path(slot))) != OK:
		push_warning("Salvataggio: impossibile scrivere %s (disco pieno?)" % path(slot))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	if thumb != null and not thumb.is_empty():
		var t := thumb.duplicate() as Image
		t.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_NEAREST)
		var ttmp := thumb_path(slot) + ".tmp.png"
		if t.save_png(ttmp) == OK:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(ttmp), ProjectSettings.globalize_path(thumb_path(slot)))
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(ttmp))
	elif FileAccess.file_exists(thumb_path(slot)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(thumb_path(slot)))
	return true


## Legge un salvataggio; {} se manca, è rovinato o è di un formato diverso.
static func read(slot: String) -> Dictionary:
	if not exists(slot):
		return {}
	var json := JSON.new()   # (JSON.parse_string stamperebbe un errore per ogni file rovinato)
	if json.parse(FileAccess.get_file_as_string(path(slot))) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("Salvataggio rovinato: %s" % path(slot))
		return {}
	var parsed: Variant = json.data
	var data: Variant = JSON.to_native(parsed)
	if typeof(data) != TYPE_DICTIONARY or int(data.get("format", 0)) != FORMAT \
			or not data.has("game") or not data.has("entities") or not ResourceLoader.exists(String(data.get("level", ""))):
		push_warning("Salvataggio non valido o di un'altra versione: %s" % path(slot))
		return {}
	return data


## Solo i dati per l'elenco degli slot ({} = slot vuoto o illeggibile).
static func meta(slot: String) -> Dictionary:
	var data := read(slot)
	return data.get("meta", {}) if not data.is_empty() else {}


static func thumbnail(slot: String) -> Texture2D:
	if not FileAccess.file_exists(thumb_path(slot)):
		return null
	var img := Image.load_from_file(thumb_path(slot))
	return ImageTexture.create_from_image(img) if img != null else null


## Lo slot salvato più di recente ("" se non ce ne sono).
static func latest() -> String:
	var best := ""
	var best_t := -1.0
	for s in slots():
		var m := meta(s)
		if not m.is_empty() and float(m.get("unix", 0.0)) > best_t:
			best_t = float(m.unix)
			best = s
	return best


static func delete(slot: String) -> void:
	for p in [path(slot), thumb_path(slot)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
