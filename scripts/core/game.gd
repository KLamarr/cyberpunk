extends Node
## Autoload "Game": stato globale della missione.
## Skill, inventario, obiettivi, registri letti, sistema del rumore, allarmi,
## statistiche, impostazioni e lingua. Gli altri script comunicano soprattutto
## tramite i segnali qui sotto.
##
## Testi: notify() e say() ricevono testi già tradotti (tr()); gli obiettivi invece
## si salvano in inglese e si traducono quando vengono mostrati.

signal message(text: String, color: Color)
signal subtitle(speaker: String, text: String, duration: float)
signal objectives_changed
signal inventory_changed
signal skills_changed
signal alarm_changed(active: bool)
signal lockdown_started
signal player_damaged(amount: float, from_pos: Vector3)
signal state_changed(new_state: int)
signal settings_changed
signal log_read(id: String)
## Emesso dopo aver applicato un salvataggio (vedi load_game / finish_load).
signal game_loaded

enum State { MENU, PLAYING, PANEL, DEAD, COMPLETE }

# --- lingua e impostazioni ---------------------------------------------------
## Lingue del gioco. L'inglese è la lingua sorgente: i testi scritti nel codice e
## nelle scene sono in inglese e passano da tr(); le altre lingue sono traduzioni
## in locale/<codice>.po. Una frase senza traduzione resta in inglese.
const LANGUAGES := {"en": "English", "it": "Italiano"}
## Impostazioni del giocatore (lingua, grafica, audio, mouse).
const SETTINGS_PATH := "user://settings.cfg"

# --- skill -------------------------------------------------------------------
const SKILLS := ["hacking", "armi", "forza", "furtivita"]
## Nomi e descrizioni in inglese: usali con skill_name() e skill_desc(), che li traducono.
# i18n
const SKILL_NAMES := {
	"hacking": "HACKING",
	"armi": "FIREARMS",
	"forza": "STRENGTH",
	"furtivita": "STEALTH",
}
# i18n
const SKILL_DESC := {
	"hacking": "Lets you hack doors, terminals and turrets. Each device requires a minimum level; every extra level raises the success chance per node.",
	"armi": "More accurate pistol (-25% spread per level), more damage and faster reloads.",
	"forza": "+10 max health and more melee damage per level. Level 1: remove grates by hand, quietly. Level 2: lift heavy crates. You throw farther.",
	"furtivita": "-12% visibility and -15% footstep noise per level. You move faster while crouched.",
}
const SKILL_MAX := 4
const START_POINTS := 4
const START_CAP := 2
const MAG_SIZE := 8
const ALARM_DURATION := 45.0

const INPUT_MAP := {
	"move_forward": [["key", KEY_W]],
	"move_back": [["key", KEY_S]],
	"move_left": [["key", KEY_A]],
	"move_right": [["key", KEY_D]],
	"jump": [["key", KEY_SPACE]],
	"crouch": [["key", KEY_CTRL]],
	"crouch_toggle": [["key", KEY_C]],
	"sprint": [["key", KEY_SHIFT]],
	"lean_left": [["key", KEY_Q]],
	"lean_right": [["key", KEY_E]],
	"frob": [["key", KEY_F], ["mouse", MOUSE_BUTTON_RIGHT]],
	"attack": [["mouse", MOUSE_BUTTON_LEFT]],
	"reload": [["key", KEY_R]],
	"weapon_1": [["key", KEY_1]],
	"weapon_2": [["key", KEY_2]],
	"weapon_next": [["mouse", MOUSE_BUTTON_WHEEL_DOWN]],
	"weapon_prev": [["mouse", MOUSE_BUTTON_WHEEL_UP]],
	"medpatch": [["key", KEY_H]],
	"pda": [["key", KEY_TAB]],
	"pause": [["key", KEY_ESCAPE]],
	"toggle_pixel": [["key", KEY_F2]],
	"toggle_dither": [["key", KEY_F3]],
	"quicksave": [["key", KEY_F5]],
	"quickload": [["key", KEY_F9]],
}
## Comandi che il giocatore non può riassegnare (Esc apre la pausa e annulla).
const FIXED_ACTIONS := ["pause"]
## Nomi dei comandi nel pannello Opzioni > Comandi (in inglese, tradotti con tr()).
# i18n
const ACTION_LABELS := {
	"move_forward": "Move forward", "move_back": "Move back", "move_left": "Move left", "move_right": "Move right",
	"sprint": "Run", "crouch": "Crouch (hold)", "crouch_toggle": "Crouch (toggle)", "jump": "Jump / climb",
	"lean_left": "Lean left", "lean_right": "Lean right", "attack": "Attack · throw",
	"frob": "Interact (frob) · put down", "reload": "Reload", "weapon_1": "Wrench", "weapon_2": "Pistol",
	"weapon_next": "Next weapon", "weapon_prev": "Previous weapon", "medpatch": "Use medipatch", "pda": "PDA",
	"quicksave": "Quicksave", "quickload": "Quickload", "toggle_pixel": "Internal resolution",
	"toggle_dither": "Dithering",
}
## Nomi dei tasti come li scrive Godot, da tradurre (contesto "key") dove serve.
# i18n ctx=key
const KEY_NAMES := ["Space", "Escape", "Enter", "Backspace", "Delete", "Insert", "Home", "End", "PageUp",
	"PageDown", "Up", "Down", "Left", "Right", "CapsLock"]

var state: int = State.MENU
var skills := {}
var start_alloc := {}
var modules := 0
var credits := 0
var ammo_mag := 6
var ammo_reserve := 10
var medpatches := 1
var keycards := {}          # id -> nome leggibile
var items := {}             # oggetti di missione (es. "core")
var logs_read: Array[String] = []
var objectives: Array = []  # [{id, text, optional, state}]  state: "active"|"done"|"failed"
var stats := {}
var alarm_time := 0.0
var security_disabled := false
var lockdown := false
var secrets_found: Array[String] = []

## Scena del livello da caricare (vedi scenes/main.tscn).
var level_path := "res://levels/seraph/seraph.tscn"
## true = salta il menu iniziale (livello avviato con F6 dall'editor).
var quick_start := false

var player: Node = null
var level: Node = null
var ui: Node = null
var hud: Node = null

var settings := {
	"language": "en",
	"pixel_scale": 2,
	"dither": true,
	"sensitivity": 0.12,
	"volume": 0.8,
	"env_captions": "auto",   # didascalie dei testi ambientali: off | auto | always (EnvTexts)
	"fullscreen": false,
	"vsync": true,
	"bindings": {},           # tasti riassegnati: comando -> [evento, evento] (vedi binding())
}
## false = non legge e non scrive user://settings.cfg (test e strumenti di sviluppo,
## così partono sempre dalle impostazioni predefinite).
var persist_settings := true
var settings_path := SETTINGS_PATH
## Lingua da salvare quando quella attiva viene da --lang= (che vale solo per la sessione).
var _saved_language := ""

## Salvataggio da applicare dopo aver ricaricato la scena (vedi load_game).
var pending_load := {}
## Il SubViewport del mondo 3D (lo imposta main): serve per l'anteprima dei salvataggi.
var world_viewport: SubViewport = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_input_map()
	for s in SKILLS:
		start_alloc[s] = 0
	reset_state()
	_init_settings()


# --- impostazioni e lingua ------------------------------------------------------
## Al primo avvio il gioco è in inglese; poi usa la lingua salvata dal giocatore.
## Da riga di comando: -- --lang=it (vale solo per quella sessione).
func _init_settings() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a in ["--autotest", "--validate", "--convert-seraph", "--write-input-map"] or a.begins_with("--tool="):
			persist_settings = false
	if "--script" in OS.get_cmdline_args() or "-s" in OS.get_cmdline_args():
		persist_settings = false   # strumenti lanciati con --script (tools/i18n.gd, npc_seed.gd...)
	if persist_settings:
		load_settings()
	else:
		SaveGame.dir = "user://saves_test"   # i test non toccano i salvataggi veri
	apply_bindings()
	apply_display()
	var lang: String = settings.language
	for a in args:
		if a.begins_with("--lang="):
			_saved_language = settings.language
			lang = a.substr(7)
	set_language(lang, false)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	for k in settings:
		var v: Variant = cfg.get_value("settings", k, settings[k])
		var t := typeof(settings[k])
		if typeof(v) == TYPE_FLOAT and not is_finite(v):
			continue   # nan/inf in un file modificato a mano
		if typeof(v) == t or (t == TYPE_FLOAT and typeof(v) == TYPE_INT):
			settings[k] = v
	if not LANGUAGES.has(settings.language):
		settings.language = "en"
	if not (settings.env_captions in EnvTexts.MODES):
		settings.env_captions = "auto"
	settings.pixel_scale = clampi(int(settings.pixel_scale), 1, 4)
	settings.sensitivity = clampf(float(settings.sensitivity), 0.03, 0.4)
	settings.volume = clampf(float(settings.volume), 0.0, 1.0)
	settings.bindings = _valid_bindings(settings.bindings)


## Tiene solo i tasti validi: comandi esistenti e riassegnabili, due posti ciascuno,
## ognuno [] oppure ["key", codice] / ["mouse", tasto].
func _valid_bindings(b: Dictionary) -> Dictionary:
	var out := {}
	for action in b:
		if not INPUT_MAP.has(action) or action in FIXED_ACTIONS or typeof(b[action]) != TYPE_ARRAY:
			continue
		var evs: Array = []
		for e in b[action]:
			if evs.size() >= 2:
				break
			if typeof(e) == TYPE_ARRAY and (e.is_empty() or (e.size() == 2 and e[0] in ["key", "mouse"] and typeof(e[1]) in [TYPE_INT, TYPE_FLOAT] and int(e[1]) > 0)):
				evs.append([] if e.is_empty() else [String(e[0]), int(e[1])])
		out[action] = evs
	return out


func save_settings() -> void:
	if not persist_settings:
		return
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	if _saved_language != "":
		cfg.set_value("settings", "language", _saved_language)
	if cfg.save(settings_path) != OK:
		push_warning("Impossibile salvare le impostazioni in " + settings_path)


## Cambia lingua: i testi mostrati da qui in poi usano la nuova lingua.
func set_language(code: String, persist := true) -> void:
	if not LANGUAGES.has(code):
		push_warning("Lingua sconosciuta '%s': uso l'inglese" % code)
		code = "en"
	settings.language = code
	TranslationServer.set_locale(code)
	get_window().title = tr("Seraph Protocol (Vertical Slice)")
	settings_changed.emit()
	if persist:
		_saved_language = ""   # scelta del giocatore: da ora vale anche per le prossime partite
		save_settings()


func cycle_language() -> void:
	var codes: Array = LANGUAGES.keys()
	set_language(codes[(codes.find(settings.language) + 1) % codes.size()])


func language_name() -> String:
	return LANGUAGES.get(settings.language, settings.language)


func skill_name(s: String) -> String:
	return tr(SKILL_NAMES.get(s, s))


func skill_desc(s: String) -> String:
	return tr(SKILL_DESC.get(s, ""))


## Nome di un personaggio con il titolo tradotto: "Ofc. Rossi" -> "Ag. Rossi".
## I titoli (la parola che finisce col punto) sono in locale/it.po con contesto "title".
func person_name(full: String) -> String:
	var sp := full.find(" ")
	if sp > 1 and full[sp - 1] == ".":
		return tr(full.substr(0, sp), "title") + full.substr(sp)
	return tr(full)


static func ensure_input_map() -> void:
	for action in INPUT_MAP:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for ev_def in INPUT_MAP[action]:
			InputMap.action_add_event(action, make_event(ev_def))


## Evento di input da ["key", codice fisico] o ["mouse", tasto] (null per []).
static func make_event(def: Array) -> InputEvent:
	if def.is_empty():
		return null
	var ev: InputEvent
	if def[0] == "key":
		var k := InputEventKey.new()
		k.physical_keycode = int(def[1])
		ev = k
	else:
		var m := InputEventMouseButton.new()
		m.button_index = int(def[1])
		ev = m
	ev.device = -1  # tutti i dispositivi
	return ev


# --- tasti riassegnabili -------------------------------------------------------------
## I due tasti di un comando: quelli scelti dal giocatore o i predefiniti.
func binding(action: String) -> Array:
	var evs: Array = (settings.bindings[action] if settings.bindings.has(action) else INPUT_MAP.get(action, [])).duplicate(true)
	while evs.size() < 2:
		evs.append([])
	return evs


## Applica i tasti all'InputMap (all'avvio e a ogni modifica).
func apply_bindings() -> void:
	for action in INPUT_MAP:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		for def in binding(action):
			var ev := make_event(def)
			if ev != null:
				InputMap.action_add_event(action, ev)


## Assegna def (["key", codice] / ["mouse", tasto]; [] = nessuno) al posto i (0 o 1)
## del comando. Se un altro comando usava già quel tasto, gli passa il tasto vecchio
## (scambio). Restituisce il comando con cui c'è stato lo scambio ("" = nessuno).
func set_binding(action: String, i: int, def: Array) -> String:
	var all := {}
	for a in INPUT_MAP:
		all[a] = binding(a)
	var old: Array = all[action][i]
	var swapped := ""
	if not def.is_empty():
		for a in all:
			for j in 2:
				if all[a][j] == def and not (a == action and j == i):
					all[a][j] = old
					swapped = a
	all[action][i] = def
	for a in FIXED_ACTIONS:
		all.erase(a)
	settings.bindings = all
	apply_bindings()
	save_settings()
	settings_changed.emit()
	return swapped


func reset_bindings() -> void:
	settings.bindings = {}
	apply_bindings()
	save_settings()
	settings_changed.emit()


## Nome leggibile di un tasto (tradotto): «F», «Mouse dx», «Spazio»...
func event_label(def: Array) -> String:
	if def.is_empty():
		return "—"
	if def[0] == "mouse":
		match int(def[1]):
			MOUSE_BUTTON_LEFT: return tr("LMB")
			MOUSE_BUTTON_RIGHT: return tr("RMB")
			MOUSE_BUTTON_MIDDLE: return tr("MMB")
			MOUSE_BUTTON_WHEEL_UP: return tr("Wheel up")
			MOUSE_BUTTON_WHEEL_DOWN: return tr("Wheel down")
		return tr("Mouse %d") % int(def[1])
	var code := int(def[1])
	if DisplayServer.get_name() != "headless":
		# il tasto in quella posizione con la tastiera del giocatore (es. Z su AZERTY)
		var local := DisplayServer.keyboard_get_keycode_from_physical(code)
		if local != KEY_NONE:
			code = local
	if code > 32 and code < 127:
		return char(code).to_upper()   # lettere, cifre e simboli: «Q», «1», «[» (non «BracketLeft»)
	var key_name := OS.get_keycode_string(code)
	if key_name.begins_with("Kp "):   # tastierino numerico
		var rest := key_name.substr(3)
		return "Num " + String({"Multiply": "*", "Divide": "/", "Subtract": "-", "Add": "+", "Period": "."}.get(rest, rest))
	return tr(key_name, "key")


## Tasti di un comando per i testi a schermo: «F/Mouse dx».
func key_label(action: String) -> String:
	var parts: Array[String] = []
	for def in binding(action):
		if not def.is_empty():
			parts.append(event_label(def))
	return "/".join(parts) if not parts.is_empty() else "—"


# --- schermo ------------------------------------------------------------------------
func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want and not (want == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
		DisplayServer.window_set_mode(want)
	var vs := DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != vs:
		DisplayServer.window_set_vsync_mode(vs)


func set_fullscreen(on: bool) -> void:
	settings.fullscreen = on
	apply_display()
	save_settings()


func set_vsync(on: bool) -> void:
	settings.vsync = on
	apply_display()
	save_settings()


## Scrive l'InputMap in project.godot, così i comandi compaiono (e si
## rimappano) in Progetto > Impostazioni > Mappa input. Uso:
##   godot --path . -- --write-input-map
func write_input_map_to_project() -> void:
	for action in INPUT_MAP:
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": InputMap.action_get_events(action)})
	ProjectSettings.save()
	print("InputMap salvata in project.godot")


func reset_state() -> void:
	skills = start_alloc.duplicate()
	modules = 0
	credits = 0
	ammo_mag = 6
	ammo_reserve = 10
	medpatches = 1
	keycards = {}
	items = {}
	logs_read = []
	secrets_found = []
	alarm_time = 0.0
	security_disabled = false
	lockdown = false
	player = null
	level = null
	stats = {
		"time": 0.0, "kills": 0, "kos": 0, "alarms": 0, "detections": 0,
		"pickpockets": 0, "hacks": 0, "shots": 0,
	}
	objectives = []   # li aggiunge lo script di missione del livello (setup_mission)


# --- stato / pausa ------------------------------------------------------------
func set_state(s: int) -> void:
	state = s
	match s:
		State.PLAYING:
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		State.PANEL, State.MENU:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		State.DEAD, State.COMPLETE:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	state_changed.emit(s)


func is_playing() -> bool:
	return state == State.PLAYING


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	stats.time += delta
	if alarm_time > 0.0:
		alarm_time -= delta
		if alarm_time <= 0.0:
			alarm_time = 0.0
			Sfx.set_alarm(false)
			alarm_changed.emit(false)
			notify(tr("Alarm cleared."), Color(0.6, 0.9, 0.8))


# --- skill --------------------------------------------------------------------
func skill(s: String) -> int:
	return int(skills.get(s, 0))


func upgrade_cost(s: String) -> int:
	return skill(s) + 1


func try_upgrade(s: String) -> bool:
	if skill(s) >= SKILL_MAX:
		return false
	var cost := upgrade_cost(s)
	if modules < cost:
		return false
	modules -= cost
	skills[s] = skill(s) + 1
	skills_changed.emit()
	inventory_changed.emit()
	if player and player.has_method("on_skills_changed"):
		player.on_skills_changed()
	return true


# --- inventario ---------------------------------------------------------------
## display_name: nome della tessera in inglese, come scritto nel livello
## (vuoto = "<Id> Keycard"). Viene tradotto quando lo si mostra.
func give_keycard(id: String, display_name := "") -> void:
	keycards[id] = display_name
	inventory_changed.emit()


func has_keycard(id: String) -> bool:
	return keycards.has(id)


## Nome tradotto di una tessera posseduta.
func keycard_name(id: String) -> String:
	return keycard_label(id, keycards.get(id, ""))


## Nome tradotto di una tessera: display_name in inglese, oppure "<Id> Keycard".
func keycard_label(id: String, display_name := "") -> String:
	return tr(display_name) if display_name != "" else tr("%s Keycard") % id.capitalize()


func add_modules(n: int) -> void:
	modules += n
	inventory_changed.emit()


func add_credits(n: int) -> void:
	credits += n
	inventory_changed.emit()


func add_ammo(n: int) -> void:
	ammo_reserve += n
	inventory_changed.emit()


func add_medpatch(n: int = 1) -> void:
	medpatches += n
	inventory_changed.emit()


func give_item(id: String) -> void:
	items[id] = true
	inventory_changed.emit()


func has_item(id: String) -> bool:
	return items.has(id)


func found_secret(id: String) -> void:
	if id in secrets_found:
		return
	secrets_found.append(id)
	notify(tr("You found a secret!"), Color(1.0, 0.85, 0.3))


# --- registri -----------------------------------------------------------------
func read_log(id: String, open_reader := true) -> void:
	var first := not (id in logs_read)
	if first:
		logs_read.append(id)
		Sfx.play_ui("datapad")
		var title: String = Logs.ENTRIES.get(id, {}).get("title", id)
		notify(tr("Log added to PDA: %s") % tr(title), Color(0.5, 0.9, 1.0))
		log_read.emit(id)
	if open_reader and ui:
		ui.show_log(id)


# --- obiettivi ----------------------------------------------------------------
## text in inglese: viene tradotto quando lo si mostra (l'italiano va in locale/it.po).
func add_objective(id: String, text: String, optional := false) -> void:
	for o in objectives:
		if o.id == id:
			return
	objectives.append({"id": id, "text": text, "optional": optional, "state": "active"})
	objectives_changed.emit()


func _obj(id: String) -> Dictionary:
	for o in objectives:
		if o.id == id:
			return o
	return {}


func is_objective_active(id: String) -> bool:
	var o := _obj(id)
	return not o.is_empty() and o.state == "active"


func complete_objective(id: String, reward_modules := 0) -> void:
	var o := _obj(id)
	if o.is_empty() or o.state != "active":
		return
	o.state = "done"
	Sfx.play_ui("objective")
	var extra := ""
	if reward_modules > 0:
		modules += reward_modules
		extra = "  " + tr("(cyber-modules +%d)") % reward_modules
		inventory_changed.emit()
	notify(tr("OBJECTIVE COMPLETE: %s") % tr(o.text) + extra, Color(0.4, 1.0, 0.6))
	objectives_changed.emit()


func fail_objective(id: String) -> void:
	var o := _obj(id)
	if o.is_empty() or o.state != "active":
		return
	o.state = "failed"
	notify(tr("OBJECTIVE FAILED: %s") % tr(o.text), Color(1.0, 0.35, 0.3))
	objectives_changed.emit()


# --- messaggi -----------------------------------------------------------------
func notify(text: String, color := Color(0.75, 0.95, 0.9)) -> void:
	message.emit(text, color)


func say(speaker: String, text: String, duration := 3.5) -> void:
	subtitle.emit(speaker, text, duration)


# --- rumore -------------------------------------------------------------------
## Ogni suono "udibile" dall'IA passa da qui. kind: step, impact, clang, glass,
## grate, gunshot, shout, body, alarm.  source: nodo che l'ha generato.
func emit_noise(pos: Vector3, radius: float, kind: String, source: Node = null, info := {}) -> void:
	if radius <= 0.05:
		return
	for n in get_tree().get_nodes_in_group("ai"):
		if n != source and n.has_method("hear"):
			n.hear(pos, radius, kind, source, info)
	if hud and hud.has_method("on_noise") and source == player:
		hud.on_noise(radius)


# --- allarmi / eventi ---------------------------------------------------------
## source_name: testo già tradotto (es. tr("Spotted by the cameras.")).
func raise_alarm(pos: Vector3, source_name := "") -> void:
	if state != State.PLAYING:
		return
	var was_active := alarm_time > 0.0
	alarm_time = ALARM_DURATION
	if not was_active:
		stats.alarms += 1
		fail_objective("noalarm")
		Sfx.set_alarm(true)
		alarm_changed.emit(true)
		notify((tr("ALARM! %s") % source_name).strip_edges(), Color(1.0, 0.3, 0.25))
		say(tr("PA SYSTEM"), tr("Security alert in sector 14. All security personnel, respond."), 4.0)
	for g in get_tree().get_nodes_in_group("guards"):
		if g.has_method("on_alarm"):
			g.on_alarm(pos)


func disable_security() -> void:
	security_disabled = true
	for c in get_tree().get_nodes_in_group("security_cameras"):
		c.set_disabled(true)
	notify(tr("Cameras disabled."), Color(0.5, 1.0, 0.6))


func disable_turrets() -> void:
	for t in get_tree().get_nodes_in_group("turrets"):
		t.set_disabled(true)
	notify(tr("Turrets disabled."), Color(0.5, 1.0, 0.6))


func on_player_spotted() -> void:
	stats.detections += 1


func on_guard_down(guard: Node, killed: bool) -> void:
	if killed:
		stats.kills += 1
		fail_objective("nokill")
	else:
		stats.kos += 1


func start_lockdown() -> void:
	if lockdown:
		return
	lockdown = true
	lockdown_started.emit()
	if level and level.has_method("on_lockdown"):
		level.on_lockdown()


func complete_mission() -> void:
	# gli obiettivi opzionali ancora attivi (tranne Okafor) valgono come riusciti
	for id in ["nokill", "noalarm"]:
		if is_objective_active(id):
			_obj(id).state = "done"
	complete_objective("extract")
	set_state(State.COMPLETE)
	if ui:
		ui.show_complete()


func on_player_died() -> void:
	set_state(State.DEAD)
	if ui:
		ui.show_death()


func rating() -> String:
	if stats.kills == 0 and stats.alarms == 0 and stats.detections == 0 and stats.kos == 0:
		return tr("SPECTER — nobody knows you were here")
	if stats.kills == 0 and stats.alarms == 0 and stats.detections == 0:
		return tr("SHADOW")
	if stats.kills == 0:
		return tr("NON-LETHAL PROFESSIONAL")
	if stats.kills >= 3:
		return tr("BUTCHER OF SERAPH")
	return tr("OPERATIVE")


func cycle_pixel_scale() -> void:
	settings.pixel_scale = settings.pixel_scale % 4 + 1
	settings_changed.emit()
	save_settings()
	notify(tr("Internal resolution: %s") % pixel_scale_name(settings.pixel_scale))


func pixel_scale_name(scale: int) -> String:
	match scale:
		1: return tr("1280x720 (native)")
		2: return tr("640x360 (default)")
		3: return "427x240"
	return "320x180"


## Didascalie di insegne e scritte: spente, automatiche, sempre.
func cycle_env_captions() -> void:
	var i: int = EnvTexts.MODES.find(settings.env_captions)
	settings.env_captions = EnvTexts.MODES[(i + 1) % EnvTexts.MODES.size()]
	save_settings()


func env_captions_name() -> String:
	match settings.env_captions:
		"off": return tr("OFF")
		"always": return tr("ALWAYS")
	return tr("AUTO")


func toggle_dither() -> void:
	settings.dither = not settings.dither
	settings_changed.emit()
	save_settings()
	notify(tr("Dithering: %s") % (tr("ON") if settings.dither else tr("OFF")))


## Esce dal gioco salvando le impostazioni.
func quit_game() -> void:
	save_settings()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_settings()   # finestra chiusa: salva i cursori della pausa


# --- salvataggi (vedi SaveGame) -------------------------------------------------------
## Variabili di Game che finiscono nei salvataggi.
const SAVED_VARS := ["skills", "start_alloc", "modules", "credits", "ammo_mag", "ammo_reserve", "medpatches",
	"keycards", "items", "logs_read", "objectives", "stats", "alarm_time", "security_disabled", "lockdown",
	"secrets_found"]


func save_state() -> Dictionary:
	var d := {}
	for k in SAVED_VARS:
		var v: Variant = get(k)
		d[k] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return d


func load_state(d: Dictionary) -> void:
	for k in SAVED_VARS:
		if not d.has(k):
			continue
		var v: Variant = d[k]
		if get(k) is Array and (get(k) as Array).is_typed():
			(get(k) as Array).assign(v)
		else:
			set(k, v.duplicate(true) if (v is Dictionary or v is Array) else v)
	inventory_changed.emit()
	objectives_changed.emit()
	skills_changed.emit()


## Si può salvare adesso? In gioco, o dalla pausa; non da morti, non durante un
## minigioco o un terminale, non nel menu iniziale o dopo la fine.
func can_save() -> bool:
	if level == null or player == null or player.dead:
		return false
	if state == State.PLAYING:
		return true
	return state == State.PANEL and ui != null and ui.current_kind in ["pause", "save"]


func save_game(slot: String) -> bool:
	if not can_save():
		notify(tr("You can't save right now."), Color(1, 0.6, 0.4))
		return false
	var data := SaveGame.collect(level)
	var img: Image = null
	if world_viewport != null and DisplayServer.get_name() != "headless":
		img = world_viewport.get_texture().get_image()
	var ok := SaveGame.write(slot, data, img)
	if not ok:
		notify(tr("Couldn't save the game."), Color(1, 0.35, 0.3))
	elif slot == "quick":
		notify(tr("Quicksave done."), Color(0.6, 0.9, 0.8))
	elif slot == "auto":
		notify(tr("Autosave done."), Color(0.6, 0.9, 0.8))
	else:
		notify(tr("Game saved."), Color(0.6, 0.9, 0.8))
	return ok


## Carica uno slot: ricarica la scena e poi applica il salvataggio (finish_load).
func load_game(slot: String) -> bool:
	var data := SaveGame.read(slot)
	if data.is_empty():
		notify(tr("Couldn't load the save."), Color(1, 0.35, 0.3))
		return false
	save_settings()
	pending_load = data
	level_path = String(data.level)
	quick_start = false
	Sfx.set_alarm(false)
	reset_state()
	get_tree().paused = false
	state = State.MENU
	get_tree().reload_current_scene()
	return true


## Chiamato da main quando la scena è pronta: applica il salvataggio in attesa.
func finish_load() -> void:
	var data := pending_load
	pending_load = {}
	SaveGame.apply(level, data)
	set_state(State.PLAYING)
	Sfx.start_ambient()
	Sfx.set_alarm(bool(data.get("audio", {}).get("siren", alarm_time > 0.0)))
	notify(tr("Game loaded."), Color(0.6, 0.9, 0.8))
	game_loaded.emit()


func quicksave() -> void:
	if state == State.PLAYING:
		save_game("quick")


func quickload() -> void:
	if SaveGame.exists("quick"):
		load_game("quick")
	else:
		notify(tr("No quicksave yet (%s to quicksave).") % key_label("quicksave"), Color(1, 0.6, 0.4))


func restart() -> void:
	save_settings()
	Sfx.set_alarm(false)
	reset_state()
	get_tree().paused = false
	state = State.MENU
	get_tree().reload_current_scene()
